import * as fs from 'fs';
import * as path from 'path';
import type {
  AgentContext,
  AgentParser,
  DetectionResult,
  InteractionTurn,
  ModifiedFile,
  TokenUsage,
  ToolUseInfo,
} from '../types.js';
import { detectAgent } from '../detect.js';

const PATCH_FILE_LINE_RE = /^\*\*\* (?:Update|Add|Delete) File: (.+)$/;
const PATCH_MOVE_LINE_RE = /^\*\*\* Move to: (.+)$/;
const EDITING_TOOLS = new Set([
  'apply_patch',
  'write_file',
  'edit_file',
  'create_file',
  'replace_file',
]);
const FILE_PATH_KEYS = [
  'path',
  'file_path',
  'filePath',
  'filename',
  'target_path',
  'targetPath',
  'new_path',
  'newPath',
  'old_path',
  'oldPath',
  'notebook_path',
];
const TASK_PROMPT_SKIP_PREFIXES = [
  '# AGENTS.md instructions for ',
  '<permissions instructions>',
  '<app-context>',
  '<collaboration_mode>',
  '<skills_instructions>',
  '<environment_context>',
];

interface CodexRecord {
  type?: string;
  payload?: Record<string, unknown>;
}

interface CodexSessionMetaPayload {
  id?: string;
  timestamp?: string;
  cwd?: string;
  cli_version?: string;
  git?: {
    branch?: string;
  };
}

interface CodexTurnContextPayload {
  model?: string;
  cwd?: string;
}

interface CodexTokenUsagePayload {
  input_tokens?: number;
  cached_input_tokens?: number;
  output_tokens?: number;
}

function parseLines(raw: string): CodexRecord[] {
  const records: CodexRecord[] = [];
  for (const line of raw.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    try {
      records.push(JSON.parse(trimmed));
    } catch {
      // Skip partial lines while a session file is still being written.
    }
  }
  return records;
}

function extractTextContent(content: unknown): string {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return '';

  return content
    .map((part) => {
      if (typeof part === 'string') return part;
      if (
        part &&
        typeof part === 'object' &&
        'text' in part &&
        typeof part.text === 'string'
      ) {
        return part.text;
      }
      return '';
    })
    .filter(Boolean)
    .join('\n');
}

function truncateString(value: string): string {
  if (value.length <= 200) return value;
  return value.slice(0, 200) + '... (truncated)';
}

function sanitizeInput(input: Record<string, unknown>): Record<string, unknown> {
  const sanitized: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(input)) {
    if (typeof value === 'string') {
      sanitized[key] = truncateString(value);
    } else if (Array.isArray(value)) {
      sanitized[key] = value.map((item) =>
        typeof item === 'string' ? truncateString(item) : item,
      );
    } else {
      sanitized[key] = value;
    }
  }
  return sanitized;
}

function parseJsonObject(raw: unknown): Record<string, unknown> {
  if (typeof raw !== 'string' || !raw.trim()) return {};
  try {
    const parsed: unknown = JSON.parse(raw);
    if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
      return parsed as Record<string, unknown>;
    }
  } catch {
    // Ignore malformed arguments payloads.
  }
  return {};
}

function extractPatchFilePaths(inputText: string): string[] {
  const filePaths = new Set<string>();

  for (const line of inputText.split('\n')) {
    const fileMatch = line.match(PATCH_FILE_LINE_RE);
    if (fileMatch) {
      filePaths.add(fileMatch[1]);
      continue;
    }

    const moveMatch = line.match(PATCH_MOVE_LINE_RE);
    if (moveMatch) {
      filePaths.add(moveMatch[1]);
    }
  }

  return Array.from(filePaths);
}

function extractKnownFilePaths(input: Record<string, unknown>): string[] {
  const filePaths = new Set<string>();

  for (const key of FILE_PATH_KEYS) {
    const value = input[key];
    if (typeof value === 'string' && value.trim()) {
      filePaths.add(value);
    } else if (Array.isArray(value)) {
      for (const item of value) {
        if (typeof item === 'string' && item.trim()) {
          filePaths.add(item);
        }
      }
    }
  }

  return Array.from(filePaths);
}

function extractPatchInputText(
  input: Record<string, unknown>,
  rawInputText?: string,
): string {
  const parsedInputText = input.input;
  if (typeof parsedInputText === 'string' && parsedInputText.trim()) {
    return parsedInputText;
  }

  const parsedPatchText = input.patch;
  if (typeof parsedPatchText === 'string' && parsedPatchText.trim()) {
    return parsedPatchText;
  }

  const rawInputObject = parseJsonObject(rawInputText);
  const rawObjectInputText = rawInputObject.input;
  if (typeof rawObjectInputText === 'string' && rawObjectInputText.trim()) {
    return rawObjectInputText;
  }

  const rawObjectPatchText = rawInputObject.patch;
  if (typeof rawObjectPatchText === 'string' && rawObjectPatchText.trim()) {
    return rawObjectPatchText;
  }

  return typeof rawInputText === 'string' ? rawInputText : '';
}

function extractModifiedFiles(
  toolName: string,
  toolUseId: string,
  input: Record<string, unknown>,
  rawInputText?: string,
): ModifiedFile[] {
  let filePaths: string[] = [];

  if (toolName === 'apply_patch') {
    const patchInputText = extractPatchInputText(input, rawInputText);
    if (patchInputText) {
      filePaths = extractPatchFilePaths(patchInputText);
    }
  } else if (EDITING_TOOLS.has(toolName)) {
    filePaths = extractKnownFilePaths(input);
  }

  return filePaths.map((filePath) => ({
    filePath,
    toolName,
    toolUseId,
  }));
}

function getOrCreateAssistantTurn(transcript: InteractionTurn[]): InteractionTurn {
  const lastTurn = transcript[transcript.length - 1];
  if (lastTurn && lastTurn.role === 'assistant') {
    return lastTurn;
  }

  const turn: InteractionTurn = {
    turnIndex: transcript.length,
    role: 'assistant',
    content: '',
    modifiedFiles: [],
    toolUses: [],
  };
  transcript.push(turn);
  return turn;
}

function isMeaningfulTaskPrompt(content: string): boolean {
  const trimmed = content.trim();
  if (!trimmed) return false;
  return !TASK_PROMPT_SKIP_PREFIXES.some((prefix) => trimmed.startsWith(prefix));
}

function extractSessionId(sessionFilePath: string, sessionMeta?: CodexSessionMetaPayload): string {
  if (sessionMeta?.id) return sessionMeta.id;

  const basename = path.basename(sessionFilePath);
  const match = basename.match(
    /([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.jsonl$/i,
  );
  return match ? match[1] : basename.replace(/\.jsonl$/, '');
}

export class CodexParser implements AgentParser {
  async detect(repoPath: string): Promise<DetectionResult> {
    return detectAgent(repoPath);
  }

  async parse(
    sessionFilePath: string,
    _repoPath: string,
  ): Promise<AgentContext> {
    const raw = fs.readFileSync(sessionFilePath, 'utf-8');
    const records = parseLines(raw);
    const transcript: InteractionTurn[] = [];
    const fallbackUserPrompts: string[] = [];
    let taskPrompt = '';
    let sessionMeta: CodexSessionMetaPayload | undefined;
    let latestTurnContext: CodexTurnContextPayload | undefined;
    let totalUsage: TokenUsage = {
      inputTokens: 0,
      outputTokens: 0,
      cacheReadTokens: 0,
      cacheCreationTokens: 0,
    };

    for (const record of records) {
      if (!record.type || !record.payload) continue;

      if (record.type === 'session_meta') {
        sessionMeta = record.payload as unknown as CodexSessionMetaPayload;
        continue;
      }

      if (record.type === 'turn_context') {
        latestTurnContext = record.payload as unknown as CodexTurnContextPayload;
        continue;
      }

      if (record.type === 'event_msg') {
        const payloadType = record.payload.type;
        if (payloadType === 'token_count') {
          const usage = (
            record.payload.info as { total_token_usage?: CodexTokenUsagePayload } | undefined
          )?.total_token_usage;
          if (usage) {
            totalUsage = {
              inputTokens: usage.input_tokens || 0,
              outputTokens: usage.output_tokens || 0,
              cacheReadTokens: usage.cached_input_tokens || 0,
              cacheCreationTokens: 0,
            };
          }
        }
        continue;
      }

      if (record.type !== 'response_item') continue;

      const payloadType = record.payload.type;
      if (payloadType === 'message') {
        const role = record.payload.role;
        if (role !== 'user' && role !== 'assistant') continue;

        const content = extractTextContent(record.payload.content);
        if (role === 'user') {
          if (content) {
            fallbackUserPrompts.push(content);
            if (!taskPrompt && isMeaningfulTaskPrompt(content)) {
              taskPrompt = content;
            }
          }
        }

        transcript.push({
          turnIndex: transcript.length,
          role,
          content,
          modifiedFiles: [],
          toolUses: [],
        });
        continue;
      }

      if (payloadType === 'function_call') {
        const toolName =
          typeof record.payload.name === 'string' ? record.payload.name : 'unknown';
        const toolUseId =
          typeof record.payload.call_id === 'string' ? record.payload.call_id : '';
        const rawArguments =
          typeof record.payload.arguments === 'string' ? record.payload.arguments : undefined;
        const input = parseJsonObject(record.payload.arguments);
        const assistantTurn = getOrCreateAssistantTurn(transcript);

        assistantTurn.toolUses.push({
          toolName,
          toolUseId,
          input: sanitizeInput(input),
        });
        assistantTurn.modifiedFiles.push(
          ...extractModifiedFiles(toolName, toolUseId, input, rawArguments),
        );
        continue;
      }

      if (payloadType === 'custom_tool_call') {
        const toolName =
          typeof record.payload.name === 'string' ? record.payload.name : 'unknown';
        const toolUseId =
          typeof record.payload.call_id === 'string' ? record.payload.call_id : '';
        const rawInput =
          typeof record.payload.input === 'string' ? record.payload.input : '';
        const input = rawInput ? { input: rawInput } : {};
        const assistantTurn = getOrCreateAssistantTurn(transcript);

        assistantTurn.toolUses.push({
          toolName,
          toolUseId,
          input: sanitizeInput(input),
        });
        assistantTurn.modifiedFiles.push(
          ...extractModifiedFiles(toolName, toolUseId, input, rawInput),
        );
      }
    }

    if (!taskPrompt) {
      taskPrompt = fallbackUserPrompts.find((prompt) => prompt.trim()) || '';
    }

    const allModifiedFiles = new Set<string>();
    for (const turn of transcript) {
      for (const modifiedFile of turn.modifiedFiles) {
        allModifiedFiles.add(modifiedFile.filePath);
      }
    }

    const stat = fs.statSync(sessionFilePath);

    return {
      agent: 'codex',
      sessionId: extractSessionId(sessionFilePath, sessionMeta),
      sessionFilePath,
      taskPrompt,
      modifiedFiles: Array.from(allModifiedFiles),
      tokenUsage: totalUsage,
      transcript,
      metadata: {
        model: latestTurnContext?.model,
        version: sessionMeta?.cli_version,
        gitBranch: sessionMeta?.git?.branch,
        startedAt: sessionMeta?.timestamp,
        sessionFileModifiedAt: stat.mtime.toISOString(),
      },
    };
  }
}

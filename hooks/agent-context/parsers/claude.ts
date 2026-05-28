import * as fs from 'fs';
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

const FILE_MOD_TOOLS = new Set([
  'Write',
  'Edit',
  'NotebookEdit',
  'mcp__acp__Write',
  'mcp__acp__Edit',
]);

interface ClaudeLine {
  type?: string;
  sessionId?: string;
  version?: string;
  gitBranch?: string;
  uuid?: string;
  timestamp?: string;
  // Old format: message wrapper with role/content/usage
  message?: {
    id?: string;
    model?: string;
    role?: string;
    content?: unknown;
    usage?: {
      input_tokens?: number;
      output_tokens?: number;
      cache_creation_input_tokens?: number;
      cache_read_input_tokens?: number;
    };
  };
  // New Entire CLI format: id/content at top level (type is the role)
  id?: string;
  content?: unknown;
}

interface ContentBlock {
  type?: string;  // Optional: new format blocks may omit type
  text?: string;
  thinking?: string;
  name?: string;
  id?: string;
  input?: Record<string, unknown>;
}

function parseLines(raw: string): ClaudeLine[] {
  const lines: ClaudeLine[] = [];
  for (const line of raw.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    try {
      lines.push(JSON.parse(trimmed));
    } catch {
      // Skip unparseable lines (e.g. partial write from concurrent agent)
    }
  }
  return lines;
}

function extractTextContent(content: unknown): string {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return '';

  const parts: string[] = [];
  for (const block of content as ContentBlock[]) {
    // Support both old ({type: "text", text}) and new ({id, text}) content blocks
    if (block.text && (block.type === 'text' || !block.type)) {
      parts.push(block.text);
    }
  }
  return parts.join('\n');
}

function extractModifiedFiles(content: unknown): ModifiedFile[] {
  if (!Array.isArray(content)) return [];
  const files: ModifiedFile[] = [];

  for (const block of content as ContentBlock[]) {
    if (block.type !== 'tool_use' || !block.name) continue;
    if (!FILE_MOD_TOOLS.has(block.name)) continue;

    const filePath =
      (block.input?.file_path as string) ||
      (block.input?.path as string) ||
      (block.input?.notebook_path as string);
    if (filePath) {
      files.push({
        filePath,
        toolName: block.name,
        toolUseId: block.id,
      });
    }
  }
  return files;
}

function extractToolUses(content: unknown): ToolUseInfo[] {
  if (!Array.isArray(content)) return [];
  const tools: ToolUseInfo[] = [];

  for (const block of content as ContentBlock[]) {
    if (block.type !== 'tool_use' || !block.name) continue;
    tools.push({
      toolName: block.name,
      toolUseId: block.id || '',
      input: sanitizeInput(block.input || {}),
    });
  }
  return tools;
}

// intentional: sanitize tool input for display in hook output, not LLM context
function sanitizeInput(input: Record<string, unknown>): Record<string, unknown> {
  const sanitized: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(input)) {
    if (typeof value === 'string' && value.length > 200) {
      sanitized[key] = value.slice(0, 200) + '... (truncated)';
    } else {
      sanitized[key] = value;
    }
  }
  return sanitized;
}

export class ClaudeParser implements AgentParser {
  async detect(repoPath: string): Promise<DetectionResult> {
    return detectAgent(repoPath);
  }

  async parse(
    sessionFilePath: string,
    _repoPath: string,
  ): Promise<AgentContext> {
    const raw = fs.readFileSync(sessionFilePath, 'utf-8');
    const allLines = parseLines(raw);

    // Filter to user and assistant lines only
    const userLines = allLines.filter((l) => l.type === 'user');
    const assistantLines = allLines.filter((l) => l.type === 'assistant');

    // Deduplicate assistant messages by message.id (streaming produces duplicates)
    // Support both old format (line.message.id) and new format (line.id)
    const dedupedAssistant = new Map<string, ClaudeLine>();
    for (const line of assistantLines) {
      const msgId = line.message?.id || line.id;
      if (msgId) {
        dedupedAssistant.set(msgId, line);
      }
    }
    const uniqueAssistant = Array.from(dedupedAssistant.values());

    // Build transcript turns
    const transcript: InteractionTurn[] = [];
    let turnIndex = 0;

    // Interleave user and assistant messages by position
    // User messages appear at even indices, assistant at odd
    const maxTurns = Math.max(userLines.length, uniqueAssistant.length);
    for (let i = 0; i < maxTurns; i++) {
      if (i < userLines.length) {
        const user = userLines[i];
        // Support both old ({message: {content}}) and new ({content}) formats
        const userContent = user.message?.content ?? user.content;
        transcript.push({
          turnIndex: turnIndex++,
          role: 'user',
          content: extractTextContent(userContent),
          modifiedFiles: [],
          toolUses: [],
        });
      }
      if (i < uniqueAssistant.length) {
        const asst = uniqueAssistant[i];
        // Support both old ({message: {content, usage}}) and new ({content}) formats
        const content = asst.message?.content ?? asst.content;
        const usage = asst.message?.usage;
        transcript.push({
          turnIndex: turnIndex++,
          role: 'assistant',
          content: extractTextContent(content),
          modifiedFiles: extractModifiedFiles(content),
          tokenUsage: usage
            ? {
                inputTokens: usage.input_tokens || 0,
                outputTokens: usage.output_tokens || 0,
                cacheCreationTokens: usage.cache_creation_input_tokens,
                cacheReadTokens: usage.cache_read_input_tokens,
              }
            : undefined,
          toolUses: extractToolUses(content),
        });
      }
    }

    // Task prompt: first user message where content is a plain string
    // (not a tool_result array) and not a system instruction injected by the host
    let taskPrompt = '';
    for (const user of userLines) {
      const content = user.message?.content ?? user.content;
      if (typeof content !== 'string') continue;
      if (content.startsWith('<system_instruction>') || content.startsWith('<system-')) continue;
      taskPrompt = content;
      break;
    }

    // Aggregate token usage
    const totalUsage: TokenUsage = {
      inputTokens: 0,
      outputTokens: 0,
      cacheCreationTokens: 0,
      cacheReadTokens: 0,
    };
    for (const asst of uniqueAssistant) {
      const usage = asst.message?.usage;
      if (usage) {
        totalUsage.inputTokens += usage.input_tokens || 0;
        totalUsage.outputTokens += usage.output_tokens || 0;
        totalUsage.cacheCreationTokens! += usage.cache_creation_input_tokens || 0;
        totalUsage.cacheReadTokens! += usage.cache_read_input_tokens || 0;
      }
    }

    // Collect all modified files (deduplicated)
    const allModifiedFiles = new Set<string>();
    for (const turn of transcript) {
      for (const f of turn.modifiedFiles) {
        allModifiedFiles.add(f.filePath);
      }
    }

    // Metadata from first lines
    const firstUser = userLines[0];
    const firstAssistant = uniqueAssistant[0];
    const stat = fs.statSync(sessionFilePath);

    return {
      agent: 'claude-code',
      sessionId: firstUser?.sessionId || '',
      sessionFilePath,
      taskPrompt,
      modifiedFiles: Array.from(allModifiedFiles),
      tokenUsage: totalUsage,
      transcript,
      metadata: {
        model: firstAssistant?.message?.model,
        version: firstUser?.version,
        gitBranch: firstUser?.gitBranch,
        startedAt: firstUser?.timestamp,
        sessionFileModifiedAt: stat.mtime.toISOString(),
      },
    };
  }
}

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

interface GeminiToolCall {
  id?: string;
  name?: string;
  args?: Record<string, unknown>;
  status?: string;
}

interface GeminiTokens {
  input?: number;
  output?: number;
  cached?: number;
  thought?: number;
}

interface GeminiMessage {
  id?: string;
  type: 'user' | 'gemini';
  content: string | Array<{ text: string }>;
  toolCalls?: GeminiToolCall[];
  tokens?: GeminiTokens;
}

interface GeminiSession {
  messages: GeminiMessage[];
}

const FILE_PATH_KEYS = ['file_path', 'path', 'filename'];

function extractContent(content: string | Array<{ text: string }>): string {
  if (typeof content === 'string') return content;
  if (Array.isArray(content)) {
    return content.map((c) => c.text).join('\n');
  }
  return '';
}

function extractModifiedFiles(toolCalls?: GeminiToolCall[]): ModifiedFile[] {
  if (!toolCalls) return [];
  const files: ModifiedFile[] = [];

  for (const call of toolCalls) {
    if (!call.args) continue;
    for (const key of FILE_PATH_KEYS) {
      const val = call.args[key];
      if (typeof val === 'string') {
        files.push({
          filePath: val,
          toolName: call.name || 'unknown',
          toolUseId: call.id,
        });
        break;
      }
    }
  }
  return files;
}

function extractToolUses(toolCalls?: GeminiToolCall[]): ToolUseInfo[] {
  if (!toolCalls) return [];
  return toolCalls.map((call) => ({
    toolName: call.name || 'unknown',
    toolUseId: call.id || '',
    input: (call.args as Record<string, unknown>) || {},
  }));
}

export class GeminiParser implements AgentParser {
  async detect(repoPath: string): Promise<DetectionResult> {
    return detectAgent(repoPath);
  }

  async parse(
    sessionFilePath: string,
    _repoPath: string,
  ): Promise<AgentContext> {
    const raw = fs.readFileSync(sessionFilePath, 'utf-8');
    const session: GeminiSession = JSON.parse(raw);
    const messages = session.messages || [];

    const transcript: InteractionTurn[] = [];
    const totalUsage: TokenUsage = {
      inputTokens: 0,
      outputTokens: 0,
    };

    let taskPrompt = '';

    for (let i = 0; i < messages.length; i++) {
      const msg = messages[i];
      const role = msg.type === 'user' ? 'user' : 'assistant';
      const content = extractContent(msg.content);

      if (role === 'user' && !taskPrompt && content) {
        taskPrompt = content;
      }

      if (msg.tokens) {
        totalUsage.inputTokens += msg.tokens.input || 0;
        totalUsage.outputTokens += msg.tokens.output || 0;
      }

      transcript.push({
        turnIndex: i,
        role,
        content,
        modifiedFiles: role === 'assistant' ? extractModifiedFiles(msg.toolCalls) : [],
        tokenUsage: msg.tokens
          ? {
              inputTokens: msg.tokens.input || 0,
              outputTokens: msg.tokens.output || 0,
            }
          : undefined,
        toolUses: role === 'assistant' ? extractToolUses(msg.toolCalls) : [],
      });
    }

    const allModifiedFiles = new Set<string>();
    for (const turn of transcript) {
      for (const f of turn.modifiedFiles) {
        allModifiedFiles.add(f.filePath);
      }
    }

    const stat = fs.statSync(sessionFilePath);
    const sessionId = sessionFilePath
      .split('/')
      .pop()
      ?.replace(/\.json$/, '') || '';

    return {
      agent: 'gemini-cli',
      sessionId,
      sessionFilePath,
      taskPrompt,
      modifiedFiles: Array.from(allModifiedFiles),
      tokenUsage: totalUsage,
      transcript,
      metadata: {
        sessionFileModifiedAt: stat.mtime.toISOString(),
      },
    };
  }
}

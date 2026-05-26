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

const FILE_MOD_TOOLS = new Set(['edit', 'write', 'patch']);

interface OpenCodeTokens {
  input?: number;
  output?: number;
  cache?: {
    read?: number;
    write?: number;
  };
}

interface OpenCodePart {
  type: 'text' | 'tool';
  text?: string;
  tool?: string;
  state?: {
    input?: Record<string, unknown>;
  };
}

interface OpenCodeMessage {
  info: {
    id?: string;
    role: 'user' | 'assistant';
    createdAt?: string;
    tokens?: OpenCodeTokens;
  };
  parts: OpenCodePart[];
}

interface OpenCodeSession {
  info: {
    id: string;
    title?: string;
    createdAt?: string;
    updatedAt?: string;
  };
  messages: OpenCodeMessage[];
}

function extractTextContent(parts: OpenCodePart[]): string {
  return parts
    .filter((p) => p.type === 'text' && p.text)
    .map((p) => p.text!)
    .join('\n');
}

function extractModifiedFiles(parts: OpenCodePart[]): ModifiedFile[] {
  const files: ModifiedFile[] = [];
  for (const part of parts) {
    if (part.type !== 'tool' || !part.tool) continue;
    if (!FILE_MOD_TOOLS.has(part.tool)) continue;

    const input = part.state?.input;
    if (!input) continue;

    const filePath = (input.filePath as string) || (input.path as string);
    if (filePath) {
      files.push({
        filePath,
        toolName: part.tool,
      });
    }
  }
  return files;
}

function extractToolUses(parts: OpenCodePart[]): ToolUseInfo[] {
  const tools: ToolUseInfo[] = [];
  for (const part of parts) {
    if (part.type !== 'tool' || !part.tool) continue;
    tools.push({
      toolName: part.tool,
      toolUseId: '',
      input: (part.state?.input as Record<string, unknown>) || {},
    });
  }
  return tools;
}

export class OpenCodeParser implements AgentParser {
  async detect(repoPath: string): Promise<DetectionResult> {
    return detectAgent(repoPath);
  }

  async parse(
    sessionFilePath: string,
    _repoPath: string,
  ): Promise<AgentContext> {
    const raw = fs.readFileSync(sessionFilePath, 'utf-8');
    const session: OpenCodeSession = JSON.parse(raw);
    const messages = session.messages || [];

    const transcript: InteractionTurn[] = [];
    const totalUsage: TokenUsage = {
      inputTokens: 0,
      outputTokens: 0,
      cacheCreationTokens: 0,
      cacheReadTokens: 0,
    };

    let taskPrompt = '';

    for (let i = 0; i < messages.length; i++) {
      const msg = messages[i];
      const role = msg.info.role;
      const content = extractTextContent(msg.parts);

      if (role === 'user' && !taskPrompt && content) {
        taskPrompt = content;
      }

      const tokens = msg.info.tokens;
      if (tokens) {
        totalUsage.inputTokens += tokens.input || 0;
        totalUsage.outputTokens += tokens.output || 0;
        totalUsage.cacheReadTokens! += tokens.cache?.read || 0;
        totalUsage.cacheCreationTokens! += tokens.cache?.write || 0;
      }

      transcript.push({
        turnIndex: i,
        role,
        content,
        modifiedFiles:
          role === 'assistant' ? extractModifiedFiles(msg.parts) : [],
        tokenUsage: tokens
          ? {
              inputTokens: tokens.input || 0,
              outputTokens: tokens.output || 0,
              cacheReadTokens: tokens.cache?.read,
              cacheCreationTokens: tokens.cache?.write,
            }
          : undefined,
        toolUses: role === 'assistant' ? extractToolUses(msg.parts) : [],
      });
    }

    const allModifiedFiles = new Set<string>();
    for (const turn of transcript) {
      for (const f of turn.modifiedFiles) {
        allModifiedFiles.add(f.filePath);
      }
    }

    const stat = fs.statSync(sessionFilePath);

    return {
      agent: 'opencode',
      sessionId: session.info.id,
      sessionFilePath,
      taskPrompt,
      modifiedFiles: Array.from(allModifiedFiles),
      tokenUsage: totalUsage,
      transcript,
      metadata: {
        startedAt: session.info.createdAt,
        sessionFileModifiedAt: stat.mtime.toISOString(),
      },
    };
  }
}

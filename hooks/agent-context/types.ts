export type AgentType = 'claude-code' | 'gemini-cli' | 'opencode' | 'codex';

export interface ModifiedFile {
  filePath: string;
  toolName: string;
  toolUseId?: string;
}

export interface TokenUsage {
  inputTokens: number;
  outputTokens: number;
  cacheCreationTokens?: number;
  cacheReadTokens?: number;
}

export interface ToolUseInfo {
  toolName: string;
  toolUseId: string;
  input: Record<string, unknown>;
}

export interface InteractionTurn {
  turnIndex: number;
  role: 'user' | 'assistant';
  content: string;
  modifiedFiles: ModifiedFile[];
  tokenUsage?: TokenUsage;
  toolUses: ToolUseInfo[];
}

export interface AgentContext {
  agent: AgentType;
  sessionId: string;
  sessionFilePath: string;
  taskPrompt: string;
  modifiedFiles: string[];
  tokenUsage: TokenUsage;
  transcript: InteractionTurn[];
  metadata: {
    model?: string;
    version?: string;
    gitBranch?: string;
    startedAt?: string;
    sessionFileModifiedAt: string;
  };
}

export interface DetectionResult {
  detected: boolean;
  agent?: AgentType;
  sessionFilePath?: string;
  sessionId?: string;
}

export interface AgentParser {
  detect(repoPath: string): Promise<DetectionResult>;
  parse(sessionFilePath: string, repoPath: string): Promise<AgentContext>;
}

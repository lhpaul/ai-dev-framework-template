import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
import * as crypto from 'crypto';
import type { DetectionResult, AgentType } from './types.js';

const STALENESS_MINUTES = parseInt(
  process.env.AGENT_CONTEXT_STALENESS_MINUTES ?? '5',
  10,
);

export function sanitizePath(absPath: string): string {
  return absPath.replace(/[^a-zA-Z0-9]/g, '-');
}

function sha256(input: string): string {
  return crypto.createHash('sha256').update(input).digest('hex');
}

function isRecent(filePath: string): boolean {
  try {
    const stat = fs.statSync(filePath);
    const ageMs = Date.now() - stat.mtimeMs;
    return ageMs < STALENESS_MINUTES * 60 * 1000;
  } catch {
    return false;
  }
}

function findMostRecentFile(dir: string, pattern: RegExp): string | null {
  if (!fs.existsSync(dir)) return null;

  let entries: fs.Dirent[];
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return null;
  }

  let bestPath: string | null = null;
  let bestMtime = 0;

  for (const entry of entries) {
    if (!entry.isFile() || !pattern.test(entry.name)) continue;
    const fullPath = path.join(dir, entry.name);
    try {
      const stat = fs.statSync(fullPath);
      if (stat.mtimeMs > bestMtime) {
        bestMtime = stat.mtimeMs;
        bestPath = fullPath;
      }
    } catch {
      continue;
    }
  }

  return bestPath;
}

function extractSessionId(filePath: string, ext: string): string {
  return path.basename(filePath, ext);
}

function findMostRecentFileRecursive(
  dir: string,
  matches: (filePath: string) => boolean,
): string | null {
  if (!fs.existsSync(dir)) return null;

  const stack = [dir];
  let bestPath: string | null = null;
  let bestMtime = 0;

  while (stack.length > 0) {
    const currentDir = stack.pop();
    if (!currentDir) continue;

    let entries: fs.Dirent[];
    try {
      entries = fs.readdirSync(currentDir, { withFileTypes: true });
    } catch {
      continue;
    }

    for (const entry of entries) {
      const fullPath = path.join(currentDir, entry.name);
      if (entry.isDirectory()) {
        stack.push(fullPath);
        continue;
      }
      if (!entry.isFile() || !matches(fullPath)) continue;

      try {
        const stat = fs.statSync(fullPath);
        if (stat.mtimeMs > bestMtime) {
          bestMtime = stat.mtimeMs;
          bestPath = fullPath;
        }
      } catch {
        continue;
      }
    }
  }

  return bestPath;
}

function readCodexSessionRepoPath(filePath: string): string | null {
  let fd: number | undefined;

  try {
    fd = fs.openSync(filePath, 'r');
    const buffer = Buffer.alloc(32 * 1024);
    const bytesRead = fs.readSync(fd, buffer, 0, buffer.length, 0);
    const header = buffer.toString('utf8', 0, bytesRead);

    for (const line of header.split('\n')) {
      const trimmed = line.trim();
      if (!trimmed) continue;

      try {
        const parsed = JSON.parse(trimmed) as {
          type?: string;
          payload?: { cwd?: string };
        };
        if (
          (parsed.type === 'session_meta' || parsed.type === 'turn_context') &&
          typeof parsed.payload?.cwd === 'string'
        ) {
          return parsed.payload.cwd;
        }
      } catch {
        continue;
      }
    }
  } catch {
    return null;
  } finally {
    if (fd !== undefined) {
      fs.closeSync(fd);
    }
  }

  return null;
}

function codexSessionMatchesRepo(
  sessionFilePath: string,
  repoPath: string,
): boolean {
  const sessionRepoPath = readCodexSessionRepoPath(sessionFilePath);
  return !sessionRepoPath || sessionRepoPath === repoPath;
}

function getCodexSessionRoots(): string[] {
  const overrideDir = process.env.ENTIRE_TEST_CODEX_SESSION_DIR;
  if (overrideDir) return [overrideDir];

  const codexHome =
    process.env.ENTIRE_TEST_CODEX_HOME ||
    process.env.CODEX_HOME ||
    path.join(os.homedir(), '.codex');

  return [
    path.join(codexHome, 'sessions'),
    path.join(codexHome, 'archived_sessions'),
  ];
}

function extractCodexSessionId(filePath: string): string {
  const basename = path.basename(filePath);
  const match = basename.match(
    /([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.jsonl$/i,
  );
  return match ? match[1] : extractSessionId(filePath, '.jsonl');
}

function detectClaude(repoPath: string): DetectionResult {
  const overrideDir = process.env.ENTIRE_TEST_CLAUDE_PROJECT_DIR;
  const sessionDir =
    overrideDir ||
    path.join(os.homedir(), '.claude', 'projects', sanitizePath(repoPath));

  const sessionFile = findMostRecentFile(sessionDir, /\.jsonl$/);
  if (!sessionFile || !isRecent(sessionFile)) {
    return { detected: false };
  }

  return {
    detected: true,
    agent: 'claude-code',
    sessionFilePath: sessionFile,
    sessionId: extractSessionId(sessionFile, '.jsonl'),
  };
}

function detectGemini(repoPath: string): DetectionResult {
  const overrideDir = process.env.ENTIRE_TEST_GEMINI_PROJECT_DIR;
  const projectHash = sha256(repoPath);
  const sessionDir =
    overrideDir ||
    path.join(os.homedir(), '.gemini', 'tmp', projectHash, 'chats');

  const sessionFile = findMostRecentFile(sessionDir, /^session-.*\.json$/);
  if (!sessionFile || !isRecent(sessionFile)) {
    return { detected: false };
  }

  return {
    detected: true,
    agent: 'gemini-cli',
    sessionFilePath: sessionFile,
    sessionId: extractSessionId(sessionFile, '.json'),
  };
}

function detectOpenCode(repoPath: string): DetectionResult {
  const overrideDir = process.env.ENTIRE_TEST_OPENCODE_PROJECT_DIR;
  const sessionDir =
    overrideDir ||
    path.join(os.tmpdir(), 'entire-opencode', sanitizePath(repoPath));

  const sessionFile = findMostRecentFile(sessionDir, /\.json$/);
  if (!sessionFile || !isRecent(sessionFile)) {
    return { detected: false };
  }

  return {
    detected: true,
    agent: 'opencode',
    sessionFilePath: sessionFile,
    sessionId: extractSessionId(sessionFile, '.json'),
  };
}

function detectCodex(repoPath: string): DetectionResult {
  const overrideFile = process.env.ENTIRE_TEST_CODEX_SESSION_FILE;
  if (
    overrideFile &&
    isRecent(overrideFile) &&
    codexSessionMatchesRepo(overrideFile, repoPath)
  ) {
    return {
      detected: true,
      agent: 'codex',
      sessionFilePath: overrideFile,
      sessionId: extractCodexSessionId(overrideFile),
    };
  }

  const sessionRoots = getCodexSessionRoots();
  const threadId = process.env.CODEX_THREAD_ID;

  if (threadId) {
    for (const sessionRoot of sessionRoots) {
      const sessionFile = findMostRecentFileRecursive(
        sessionRoot,
        (filePath) =>
          filePath.endsWith(`${threadId}.jsonl`) &&
          path.basename(filePath).startsWith('rollout-'),
      );

      if (
        sessionFile &&
        isRecent(sessionFile) &&
        codexSessionMatchesRepo(sessionFile, repoPath)
      ) {
        return {
          detected: true,
          agent: 'codex',
          sessionFilePath: sessionFile,
          sessionId: extractCodexSessionId(sessionFile),
        };
      }
    }
  }

  for (const sessionRoot of sessionRoots) {
    const sessionFile = findMostRecentFileRecursive(
      sessionRoot,
      (filePath) =>
        filePath.endsWith('.jsonl') &&
        path.basename(filePath).startsWith('rollout-') &&
        isRecent(filePath) &&
        codexSessionMatchesRepo(filePath, repoPath),
    );

    if (sessionFile) {
      return {
        detected: true,
        agent: 'codex',
        sessionFilePath: sessionFile,
        sessionId: extractCodexSessionId(sessionFile),
      };
    }
  }

  return { detected: false };
}

const detectors: Array<(repoPath: string) => DetectionResult> = [
  detectClaude,
  detectCodex,
  detectGemini,
  detectOpenCode,
];

export async function detectAgent(
  repoPath: string,
): Promise<DetectionResult> {
  for (const detect of detectors) {
    const result = detect(repoPath);
    if (result.detected) return result;
  }
  return { detected: false };
}

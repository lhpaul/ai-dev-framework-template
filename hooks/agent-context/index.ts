import { detectAgent } from './detect.js';
import { ClaudeParser } from './parsers/claude.js';
import { CodexParser } from './parsers/codex.js';
import { GeminiParser } from './parsers/gemini.js';
import { OpenCodeParser } from './parsers/opencode.js';
import { formatContext } from './format.js';
import type { AgentParser } from './types.js';

const PARSERS: Record<string, AgentParser> = {
  'claude-code': new ClaudeParser(),
  codex: new CodexParser(),
  'gemini-cli': new GeminiParser(),
  opencode: new OpenCodeParser(),
};

async function main() {
  const repoRoot = process.argv[2] || process.cwd();

  const detection = await detectAgent(repoRoot);

  if (!detection.detected || !detection.agent || !detection.sessionFilePath) {
    if (process.env.AGENT_CONTEXT_VERBOSE) {
      console.error('[agent-context] No AI agent session detected.');
    }
    return;
  }

  const parser = PARSERS[detection.agent];
  if (!parser) {
    console.error(`[agent-context] No parser for agent: ${detection.agent}`);
    return;
  }

  const context = await parser.parse(detection.sessionFilePath, repoRoot);
  const output = formatContext(context);
  console.error(output);
}

main().catch((err) => {
  console.error(`[agent-context] Error: ${err.message}`);
});

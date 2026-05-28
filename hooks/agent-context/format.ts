import type { AgentContext, InteractionTurn } from './types.js';

const AGENT_DISPLAY_NAMES: Record<string, string> = {
  'claude-code': 'Claude Code',
  'gemini-cli': 'Gemini CLI',
  codex: 'Codex',
  opencode: 'OpenCode',
};

// intentional: truncation for display formatting in hook output, not LLM context
function truncate(text: string, maxLen: number): string {
  if (text.length <= maxLen) return text;
  return text.slice(0, maxLen) + '...';
}

function formatNumber(n: number): string {
  return n.toLocaleString('en-US');
}

function formatTurnSummary(turn: InteractionTurn): string {
  const role = turn.role.toUpperCase();
  const content = truncate(turn.content.replace(/\n/g, ' '), 200);
  const toolNames = turn.toolUses.map((t) => t.toolName);
  const toolSuffix = toolNames.length > 0 ? ` [tools: ${toolNames.join(', ')}]` : '';
  return `  [${turn.turnIndex + 1}] ${role}: ${content}${toolSuffix}`;
}

function formatHuman(ctx: AgentContext): string {
  const lines: string[] = [];

  lines.push('========================================');
  lines.push('  AGENT CONTEXT DETECTED');
  lines.push('========================================');
  lines.push(`Agent:       ${AGENT_DISPLAY_NAMES[ctx.agent] || ctx.agent}`);
  lines.push(`Session ID:  ${ctx.sessionId}`);

  if (ctx.metadata.model) {
    lines.push(`Model:       ${ctx.metadata.model}`);
  }
  if (ctx.metadata.version) {
    lines.push(`Version:     ${ctx.metadata.version}`);
  }
  if (ctx.metadata.gitBranch) {
    lines.push(`Git Branch:  ${ctx.metadata.gitBranch}`);
  }
  if (ctx.metadata.startedAt) {
    lines.push(`Started At:  ${ctx.metadata.startedAt}`);
  }

  lines.push('');
  lines.push('Task Prompt:');
  lines.push(`  ${truncate(ctx.taskPrompt.replace(/\n/g, ' '), 500)}`);

  lines.push('');
  lines.push(`Modified Files (${ctx.modifiedFiles.length}):`);
  if (ctx.modifiedFiles.length === 0) {
    lines.push('  (none)');
  } else {
    for (const f of ctx.modifiedFiles) {
      // Find which tools modified this file
      const tools = new Set<string>();
      for (const turn of ctx.transcript) {
        for (const mf of turn.modifiedFiles) {
          if (mf.filePath === f) tools.add(mf.toolName);
        }
      }
      lines.push(`  - ${f} (${Array.from(tools).join(', ')})`);
    }
  }

  lines.push('');
  lines.push('Token Usage:');
  lines.push(
    `  Input:  ${formatNumber(ctx.tokenUsage.inputTokens)}  Output: ${formatNumber(ctx.tokenUsage.outputTokens)}`,
  );
  if (ctx.tokenUsage.cacheCreationTokens || ctx.tokenUsage.cacheReadTokens) {
    lines.push(
      `  Cache Creation: ${formatNumber(ctx.tokenUsage.cacheCreationTokens || 0)}  Cache Read: ${formatNumber(ctx.tokenUsage.cacheReadTokens || 0)}`,
    );
  }

  lines.push('');
  lines.push(`Transcript (${ctx.transcript.length} turns):`);
  for (const turn of ctx.transcript) {
    lines.push(formatTurnSummary(turn));
  }

  lines.push('========================================');
  return lines.join('\n');
}

function formatJson(ctx: AgentContext): string {
  return JSON.stringify(ctx, null, 2);
}

export function formatContext(ctx: AgentContext): string {
  const mode = process.env.AGENT_CONTEXT_FORMAT || 'human';
  if (mode === 'json') return formatJson(ctx);
  return formatHuman(ctx);
}

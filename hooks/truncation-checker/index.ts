/**
 * Truncation Pattern Checker
 *
 * Scans staged git diff for patterns that violate the "No Truncation Without Permission" rule.
 * See LLM_RULES.md for the full policy.
 */

import { execSync } from 'child_process';
import { join } from 'path';
import { analyzeFiles, formatASTViolations, type ASTViolation } from './ast-analyzer.js';

// ============================================================================
// CONFIGURATION
// ============================================================================

/** Paths that should be checked for truncation violations */
const CHECKED_PATH_PATTERNS = [
  /^agent\//,
  /^analysis\//,
  /\/prompts?\//i,
  /tool/i,
  /llm/i,
  /agent/i,
  /pipeline/i,
  /context/i,
];

/** Paths that should be excluded from checks */
const EXCLUDED_PATH_PATTERNS = [
  /node_modules/,
  /\.test\./,
  /\.spec\./,
  /__tests__/,
  /\/test\//,
  /\/tests\//,
  /^hooks\/truncation-checker\//, // Don't scan our own pattern definitions (false-positive risk)
  /\.md$/,
  /\.json$/,
  /\.yaml$/,
  /\.yml$/,
  /\.svg$/,
  /\.png$/,
  /\.jpg$/,
  /\.gif$/,
  /\.ico$/,
  /\.lock$/,
  /package-lock/,
  /pnpm-lock/,
];

// ============================================================================
// PATTERN DEFINITIONS
// ============================================================================

interface TruncationPattern {
  id: string;
  name: string;
  description: string;
  patterns: RegExp[];
  severity: 'error' | 'warning';
}

const TRUNCATION_PATTERNS: TruncationPattern[] = [
  // -------------------------------------------------------------------------
  // Category 1: Direct slice/substring with numeric limits
  // -------------------------------------------------------------------------
  {
    id: 'slice-numeric',
    name: 'Slice with numeric limit',
    description: 'Direct .slice(0, N) or .substring(0, N) with hardcoded limit',
    patterns: [
      /\.slice\s*\(\s*0\s*,\s*\d+\s*\)/,
      /\.substring\s*\(\s*0\s*,\s*\d+\s*\)/,
      /\.substr\s*\(\s*0\s*,\s*\d+\s*\)/,
    ],
    severity: 'error',
  },
  {
    id: 'slice-variable',
    name: 'Slice with limit variable',
    description: '.slice(0, limit) or .slice(0, max...) with variable limit',
    patterns: [
      /\.slice\s*\(\s*0\s*,\s*(?:max|limit|MAX|LIMIT|cutoff|truncate)/i,
      /\.substring\s*\(\s*0\s*,\s*(?:max|limit|MAX|LIMIT|cutoff|truncate)/i,
      /\.slice\s*\(\s*0\s*,\s*[A-Z_]+(?:LENGTH|LIMIT|SIZE|COUNT|ITEMS|LINES|CHARS|TOKENS)\s*\)/,
    ],
    severity: 'error',
  },

  // -------------------------------------------------------------------------
  // Category 2: Ellipsis additions indicating truncation
  // -------------------------------------------------------------------------
  {
    id: 'ellipsis-concat',
    name: 'Ellipsis concatenation',
    description: 'Adding "..." or ellipsis character to indicate truncation',
    patterns: [
      /\+\s*['"`]\.\.\.['"`]/,
      /\+\s*['"`]…['"`]/, // Unicode ellipsis
      /\+\s*['"`]\[\.\.\.?\]]['"`]/,
      /\+\s*['"`]\s*\.\.\.\s*\(truncated\)['"`]/i,
      /\+\s*['"`]\[truncated\]['"`]/i,
      /\+\s*['"`]\(truncated\)['"`]/i,
      /\+\s*['"`]\[omitted\]['"`]/i,
      /\+\s*['"`]\(omitted\)['"`]/i,
      /['"`]\.\.\.['"`]\s*\+/, // Prefix ellipsis
    ],
    severity: 'error',
  },
  {
    id: 'ellipsis-template',
    name: 'Ellipsis in template literal',
    description: 'Template literal with ellipsis pattern',
    patterns: [
      /`[^`]*\.\.\.[^`]*\$\{/,
      /`[^`]*\$\{[^}]+\}[^`]*\.\.\.`/,
      /`\.\.\./,
    ],
    severity: 'warning', // Lower severity - could be legitimate UI
  },

  // -------------------------------------------------------------------------
  // Category 3: "N more" patterns
  // -------------------------------------------------------------------------
  {
    id: 'n-more-pattern',
    name: '"N more" truncation indicator',
    description: 'Patterns like "and X more", "+ N others"',
    patterns: [
      /\$\{[^}]+\}\s*more/i,
      /`[^`]*and\s+\$\{[^}]+\}\s+more[^`]*`/i,
      /`[^`]*\+\s*\$\{[^}]+\}\s*(?:more|others|items|remaining)[^`]*`/i,
      /['"`]\s*\.\.\.\s*and\s+['"`]\s*\+/i,
      /\[\s*\+\s*\$\{[^}]+\}\s*\]/,
      /`[^`]*\$\{[^}]+\}\s+additional[^`]*`/i,
      /`[^`]*\$\{[^}]+\}\s+remaining[^`]*`/i,
    ],
    severity: 'error',
  },

  // -------------------------------------------------------------------------
  // Category 4: "First N" / "Showing N" patterns
  // -------------------------------------------------------------------------
  {
    id: 'showing-first-n',
    name: '"Showing first N" pattern',
    description: 'Patterns indicating partial display',
    patterns: [
      /['"`](?:showing|displaying)\s+(?:first|only)\s+\d+/i,
      /['"`]first\s+\d+\s+(?:results?|items?|lines?|entries)/i,
      /['"`]limited\s+to\s+\d+/i,
      /['"`]only\s+showing\s+\d+/i,
      /['"`]top\s+\d+\s+(?:results?|items?)/i,
      /['"`]truncated\s+to\s+\d+/i,
    ],
    severity: 'error',
  },

  // -------------------------------------------------------------------------
  // Category 5: Truncation functions
  // -------------------------------------------------------------------------
  {
    id: 'truncate-function',
    name: 'Truncation function call',
    description: 'Calling truncate(), shortenText(), etc.',
    patterns: [
      /(?<!function\s)(?<!\.)\btruncate\s*\(/i,
      /(?<!function\s)truncateText\s*\(/i,
      /(?<!function\s)truncateString\s*\(/i,
      /(?<!function\s)shortenText\s*\(/i,
      /(?<!function\s)limitLength\s*\(/i,
      /(?<!function\s)ellipsize\s*\(/i,
      /(?<!function\s)abbreviate\s*\(/i,
      /_\.truncate\s*\(/,
      /_\.take\s*\(/,
      /lodash.*\.truncate\s*\(/,
    ],
    severity: 'error',
  },

  // -------------------------------------------------------------------------
  // Category 6: Conditional length checks with truncation
  // -------------------------------------------------------------------------
  {
    id: 'conditional-truncation',
    name: 'Conditional length check',
    description: 'if (x.length > N) patterns suggesting truncation',
    patterns: [
      /if\s*\([^)]*\.length\s*>\s*\d+[^)]*\)\s*\{[^}]*\.slice/,
      /if\s*\([^)]*\.length\s*>\s*(?:max|limit|MAX|LIMIT)/i,
      /\.length\s*>\s*\d+\s*\?\s*[^:]+\.slice\s*\(/,
      /\.length\s*>\s*(?:max|limit|MAX|LIMIT)[^?]*\?[^:]*\.slice/i,
    ],
    severity: 'error',
  },

  // -------------------------------------------------------------------------
  // Category 7: Content omission markers
  // -------------------------------------------------------------------------
  {
    id: 'omission-marker',
    name: 'Content omission marker',
    description: 'Strings indicating content was omitted',
    patterns: [
      /['"`]\[content\s+omitted\]['"`]/i,
      /['"`]\[\.\.\.\s*snip\s*\.\.\.\]['"`]/i,
      /['"`]<!--\s*truncated\s*-->['"`]/i,
      /['"`]\[showing\s+\d+\s+of\s+\d+\]['"`]/i,
      /['"`]\[\d+\s+items?\s+hidden\]['"`]/i,
      /['"`]\[rest\s+omitted\]['"`]/i,
      /['"`]output\s+truncated['"`]/i,
      /['"`]results?\s+truncated['"`]/i,
    ],
    severity: 'error',
  },

  // -------------------------------------------------------------------------
  // Category 8: Array truncation
  // -------------------------------------------------------------------------
  {
    id: 'array-truncation',
    name: 'Array truncation',
    description: 'Truncating arrays via length assignment or splice',
    patterns: [
      /\.length\s*=\s*\d+/, // array.length = N (truncates)
      /\.length\s*=\s*(?:max|limit|MAX|LIMIT)/i,
      /\.splice\s*\(\s*\d+\s*\)/, // splice(N) removes from index N
      /\.splice\s*\(\s*(?:max|limit|MAX|LIMIT)/i,
    ],
    severity: 'warning',
  },

  // -------------------------------------------------------------------------
  // Category 9: Take/head operations (lodash style)
  // -------------------------------------------------------------------------
  {
    id: 'take-head',
    name: 'Take/head operations',
    description: 'Lodash-style take() or head() limiting',
    patterns: [
      /\.take\s*\(\s*\d+\s*\)/,
      /\.head\s*\(\s*\d+\s*\)/,
      /\.first\s*\(\s*\d+\s*\)/,
      /\.limit\s*\(\s*\d+\s*\)/,
    ],
    severity: 'warning',
  },

  // -------------------------------------------------------------------------
  // Category 10: Max/limit constants being defined (context: likely used for truncation)
  // -------------------------------------------------------------------------
  {
    id: 'limit-constant',
    name: 'Limit constant definition',
    description: 'Defining MAX_* or *_LIMIT constants',
    patterns: [
      /(?:const|let|var)\s+MAX_(?:LENGTH|ITEMS|LINES|TOKENS|CHARS|RESULTS|OUTPUT|CONTENT)\s*=/i,
      /(?:const|let|var)\s+(?:LENGTH|ITEMS|LINES|TOKENS|CHARS|RESULTS|OUTPUT|CONTENT)_(?:LIMIT|MAX)\s*=/i,
      /(?:const|let|var)\s+(?:max|limit)(?:Length|Items|Lines|Tokens|Chars|Results|Output|Content)\s*=/,
      /(?:const|let|var)\s+TRUNCATE_(?:AT|AFTER|LENGTH)\s*=/i,
      /(?:const|let|var)\s+head_limit\s*=/i,
    ],
    severity: 'warning',
  },

  // -------------------------------------------------------------------------
  // Category 11: Output/result slicing (common in agent code)
  // -------------------------------------------------------------------------
  {
    id: 'output-slicing',
    name: 'Output/result slicing',
    description: 'Slicing output, result, content, or text variables',
    patterns: [
      /(?:output|result|content|text|response|data|items|lines|entries)\s*(?:=|\.)\s*[^;]*\.slice\s*\(\s*0\s*,/i,
      /(?:output|result|content|text|response|data)\s*=\s*[^;]*\.substring\s*\(\s*0\s*,/i,
    ],
    severity: 'error',
  },
];

// ============================================================================
// VIOLATION DETECTION
// ============================================================================

export interface Violation {
  file: string;
  line: number;
  column: number;
  content: string;
  pattern: TruncationPattern;
  matchedText: string;
}

interface DiffHunk {
  file: string;
  lines: Array<{
    lineNumber: number;
    content: string;
    type: 'add' | 'remove' | 'context';
  }>;
}

function parseDiff(diffOutput: string): DiffHunk[] {
  const hunks: DiffHunk[] = [];
  let currentFile = '';
  let currentHunk: DiffHunk | null = null;
  let lineNumber = 0;

  for (const line of diffOutput.split('\n')) {
    // New file
    if (line.startsWith('+++ b/')) {
      currentFile = line.slice(6);
      currentHunk = { file: currentFile, lines: [] };
      hunks.push(currentHunk);
      continue;
    }

    // Hunk header: @@ -old,count +new,count @@
    const hunkMatch = line.match(/^@@\s+-\d+(?:,\d+)?\s+\+(\d+)(?:,\d+)?\s+@@/);
    if (hunkMatch) {
      lineNumber = parseInt(hunkMatch[1], 10) - 1; // Will be incremented on first line
      continue;
    }

    // Only process if we're in a file
    if (!currentHunk) continue;

    if (line.startsWith('+') && !line.startsWith('+++')) {
      lineNumber++;
      currentHunk.lines.push({
        lineNumber,
        content: line.slice(1), // Remove the '+' prefix
        type: 'add',
      });
    } else if (line.startsWith('-') && !line.startsWith('---')) {
      // Removed lines don't increment lineNumber
      // We don't check removed lines
    } else if (line.startsWith(' ')) {
      lineNumber++;
      // Context line, don't check
    }
  }

  return hunks;
}

function shouldCheckFile(filePath: string): boolean {
  // Check exclusions first
  for (const pattern of EXCLUDED_PATH_PATTERNS) {
    if (pattern.test(filePath)) {
      return false;
    }
  }

  // Check if it matches any included path
  for (const pattern of CHECKED_PATH_PATTERNS) {
    if (pattern.test(filePath)) {
      return true;
    }
  }

  return false;
}

function findViolations(hunks: DiffHunk[]): Violation[] {
  const violations: Violation[] = [];

  for (const hunk of hunks) {
    if (!shouldCheckFile(hunk.file)) {
      continue;
    }

    for (const line of hunk.lines) {
      if (line.type !== 'add') continue;

      // Skip comments (basic heuristic)
      const trimmed = line.content.trim();
      if (trimmed.startsWith('//') || trimmed.startsWith('*') || trimmed.startsWith('/*')) {
        // But still check if it's a suspicious comment
        if (!/intentional|pagination|user.?control|by.?design|expected/i.test(line.content)) {
          // Check for omission markers in comments too
          for (const pattern of TRUNCATION_PATTERNS.filter(p => p.id === 'omission-marker')) {
            for (const regex of pattern.patterns) {
              const match = regex.exec(line.content);
              if (match) {
                violations.push({
                  file: hunk.file,
                  line: line.lineNumber,
                  column: match.index + 1,
                  content: line.content,
                  pattern,
                  matchedText: match[0],
                });
              }
            }
          }
        }
        continue;
      }

      // Check each pattern
      for (const pattern of TRUNCATION_PATTERNS) {
        for (const regex of pattern.patterns) {
          const match = regex.exec(line.content);
          if (match) {
            violations.push({
              file: hunk.file,
              line: line.lineNumber,
              column: match.index + 1,
              content: line.content,
              pattern,
              matchedText: match[0],
            });
            break; // One match per pattern per line is enough
          }
        }
      }
    }
  }

  return violations;
}

// ============================================================================
// OUTPUT FORMATTING
// ============================================================================

function formatViolations(violations: Violation[]): string {
  if (violations.length === 0) {
    return '';
  }

  const lines: string[] = [];
  lines.push('');
  lines.push('========================================');
  lines.push('  TRUNCATION VIOLATIONS DETECTED');
  lines.push('========================================');
  lines.push('');
  lines.push('The following changes appear to violate the "No Truncation Without Permission" rule.');
  lines.push('See LLM_RULES.md for the full policy.');
  lines.push('');

  // Group by file
  const byFile = new Map<string, Violation[]>();
  for (const v of violations) {
    const existing = byFile.get(v.file) || [];
    existing.push(v);
    byFile.set(v.file, existing);
  }

  for (const [file, fileViolations] of byFile) {
    lines.push(`📄 ${file}`);
    for (const v of fileViolations) {
      const severity = v.pattern.severity === 'error' ? '❌' : '⚠️';
      lines.push(`  ${severity} Line ${v.line}: ${v.pattern.name}`);
      lines.push(`     Pattern: ${v.pattern.description}`);
      lines.push(`     Matched: ${v.matchedText}`);
      lines.push(`     Code: ${v.content.trim().slice(0, 100)}${v.content.length > 100 ? '...' : ''}`);
      lines.push('');
    }
  }

  lines.push('----------------------------------------');
  lines.push('');
  lines.push('If this truncation is intentional and user-approved:');
  lines.push('  1. Add a comment explaining why truncation is needed');
  lines.push('  2. Include "intentional" or "user-approved" in the comment');
  lines.push('  3. Document what content is being truncated and how much');
  lines.push('');
  lines.push('If this is pagination or user-controlled:');
  lines.push('  1. Ensure the user can access the full content');
  lines.push('  2. Add a comment with "pagination" or "user-control"');
  lines.push('');
  lines.push('========================================');

  return lines.join('\n');
}

// ============================================================================
// MAIN
// ============================================================================

export interface CheckResult {
  violations: Violation[];
  astViolations: ASTViolation[];
  hasErrors: boolean;
  hasWarnings: boolean;
  output: string;
}

function getStagedFiles(): string[] {
  try {
    const output = execSync('git diff --cached --name-only', {
      encoding: 'utf-8',
    });
    return output
      .trim()
      .split('\n')
      .filter((f) => f && shouldCheckFile(f));
  } catch {
    return [];
  }
}

function getRepoRoot(): string {
  try {
    return execSync('git rev-parse --show-toplevel', {
      encoding: 'utf-8',
    }).trim();
  } catch {
    return process.cwd();
  }
}

export function checkStagedChanges(): CheckResult {
  const startTime = Date.now();

  let diffOutput: string;
  try {
    diffOutput = execSync('git diff --cached --unified=0', {
      encoding: 'utf-8',
      maxBuffer: 10 * 1024 * 1024, // 10MB
    });
  } catch {
    return {
      violations: [],
      astViolations: [],
      hasErrors: false,
      hasWarnings: false,
      output: '',
    };
  }

  if (!diffOutput.trim()) {
    return {
      violations: [],
      astViolations: [],
      hasErrors: false,
      hasWarnings: false,
      output: '',
    };
  }

  // Regex-based detection (fast, catches obvious patterns)
  const hunks = parseDiff(diffOutput);
  const violations = findViolations(hunks);

  // AST-based detection (semantic analysis)
  const repoRoot = getRepoRoot();
  const stagedFiles = getStagedFiles().map((f) => join(repoRoot, f));
  const astViolations = analyzeFiles(stagedFiles);

  const regexTime = Date.now() - startTime;

  const hasErrors =
    violations.some((v) => v.pattern.severity === 'error') ||
    astViolations.some((v) => v.severity === 'error');
  const hasWarnings =
    violations.some((v) => v.pattern.severity === 'warning') ||
    astViolations.some((v) => v.severity === 'warning');

  // Combine output
  let output = formatViolations(violations);
  const astOutput = formatASTViolations(astViolations);
  if (astOutput) {
    output += '\n' + astOutput;
  }

  // Emit timing info directly to stderr in verbose mode (not part of the violation output)
  if (process.env.TRUNCATION_CHECK_VERBOSE) {
    process.stderr.write(`[Timing: regex=${regexTime}ms, total=${Date.now() - startTime}ms, files=${stagedFiles.length}]\n`);
  }

  return {
    violations,
    astViolations,
    hasErrors,
    hasWarnings,
    output,
  };
}

// CLI entry point
if (process.argv[1]?.endsWith('index.ts') || process.argv[1]?.endsWith('index.js')) {
  const result = checkStagedChanges();
  if (result.output) {
    console.error(result.output);
  }
  // Exit with error if any errors found (regex or AST)
  if (result.hasErrors) {
    process.exit(1);
  }
}

export { type ASTViolation } from './ast-analyzer.js';

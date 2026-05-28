/**
 * Tree-sitter based truncation detection.
 *
 * Detects semantic truncation patterns that regex can't catch:
 * - Truncation in function returns
 * - LLM context variable truncation
 * - Loop-based truncation
 * - Chained truncations
 */

import Parser from "tree-sitter";
import TypeScript from "tree-sitter-typescript";
import { readFileSync, existsSync } from "fs";
import { extname } from "path";

// Initialize parsers
const tsxParser = new Parser();
tsxParser.setLanguage(TypeScript.tsx as unknown as Parser.Language);

const tsParser = new Parser();
tsParser.setLanguage(TypeScript.typescript as unknown as Parser.Language);

// ============================================================================
// TYPES
// ============================================================================

export interface ASTViolation {
  file: string;
  line: number;
  column: number;
  type: string;
  description: string;
  code: string;
  severity: "error" | "warning";
}

// Variables that likely contain LLM context
const LLM_CONTEXT_VARS = new Set([
  "context",
  "prompt",
  "messages",
  "output",
  "result",
  "response",
  "content",
  "text",
  "data",
  "input",
  "toolOutput",
  "toolResult",
  "searchResults",
  "fileContent",
  "fileContents",
  "codeContent",
  "sourceCode",
]);

// Truncation method names
const TRUNCATION_METHODS = new Set([
  "slice",
  "substring",
  "substr",
  "splice",
  "truncate",
  "take",
  "head",
  "limit",
]);

// ============================================================================
// HELPERS
// ============================================================================

function getParser(filePath: string): Parser | null {
  const ext = extname(filePath);
  if (ext === ".tsx" || ext === ".jsx") return tsxParser;
  if (ext === ".ts" || ext === ".js") return tsParser;
  return null;
}

function nodeText(node: Parser.SyntaxNode, source: string): string {
  return source.slice(node.startIndex, node.endIndex);
}

function findNodes(
  node: Parser.SyntaxNode,
  types: string[],
  results: Parser.SyntaxNode[] = []
): Parser.SyntaxNode[] {
  if (types.includes(node.type)) {
    results.push(node);
  }
  for (const child of node.children) {
    findNodes(child, types, results);
  }
  return results;
}

function findParent(
  node: Parser.SyntaxNode,
  types: string[]
): Parser.SyntaxNode | null {
  let current = node.parent;
  while (current) {
    if (types.includes(current.type)) return current;
    current = current.parent;
  }
  return null;
}

function getLineContent(source: string, line: number): string {
  const lines = source.split("\n");
  return lines[line - 1] || "";
}

// ============================================================================
// DETECTION: Return statement truncation
// ============================================================================

function detectReturnTruncation(
  tree: Parser.Tree,
  source: string,
  filePath: string
): ASTViolation[] {
  const violations: ASTViolation[] = [];

  // Find all return statements
  const returnStatements = findNodes(tree.rootNode, ["return_statement"]);

  for (const ret of returnStatements) {
    const retText = nodeText(ret, source);

    // Check if return contains truncation
    const callExpressions = findNodes(ret, ["call_expression"]);
    for (const call of callExpressions) {
      const funcNode = call.childForFieldName("function");
      if (!funcNode) continue;

      // Check for method calls like .slice(), .substring()
      if (funcNode.type === "member_expression") {
        const property = funcNode.childForFieldName("property");
        if (property && TRUNCATION_METHODS.has(nodeText(property, source))) {
          // Check if it has numeric arguments (indicates truncation)
          const args = call.childForFieldName("arguments");
          if (args) {
            const hasNumericArg = findNodes(args, ["number"]).length > 0;
            const hasLimitVar = /max|limit|MAX|LIMIT/i.test(nodeText(args, source));

            if (hasNumericArg || hasLimitVar) {
              violations.push({
                file: filePath,
                line: ret.startPosition.row + 1,
                column: ret.startPosition.column + 1,
                type: "return-truncation",
                description: `Function returns truncated data via .${nodeText(property, source)}()`,
                code: retText.slice(0, 100),
                severity: "error",
              });
            }
          }
        }
      }
    }
  }

  return violations;
}

// ============================================================================
// DETECTION: LLM context variable truncation
// ============================================================================

function detectContextVarTruncation(
  tree: Parser.Tree,
  source: string,
  filePath: string
): ASTViolation[] {
  const violations: ASTViolation[] = [];

  // Find all call expressions
  const callExpressions = findNodes(tree.rootNode, ["call_expression"]);

  for (const call of callExpressions) {
    const funcNode = call.childForFieldName("function");
    if (!funcNode || funcNode.type !== "member_expression") continue;

    const object = funcNode.childForFieldName("object");
    const property = funcNode.childForFieldName("property");
    if (!object || !property) continue;

    const methodName = nodeText(property, source);
    if (!TRUNCATION_METHODS.has(methodName)) continue;

    // Check if the object is an LLM context variable
    const objectName = nodeText(object, source);

    // Direct variable: context.slice()
    if (LLM_CONTEXT_VARS.has(objectName)) {
      violations.push({
        file: filePath,
        line: call.startPosition.row + 1,
        column: call.startPosition.column + 1,
        type: "context-var-truncation",
        description: `LLM context variable '${objectName}' is truncated via .${methodName}()`,
        code: nodeText(call, source).slice(0, 100),
        severity: "error",
      });
      continue;
    }

    // Property access: result.content.slice()
    if (object.type === "member_expression") {
      const innerProp = object.childForFieldName("property");
      if (innerProp && LLM_CONTEXT_VARS.has(nodeText(innerProp, source))) {
        violations.push({
          file: filePath,
          line: call.startPosition.row + 1,
          column: call.startPosition.column + 1,
          type: "context-var-truncation",
          description: `LLM context property '${nodeText(innerProp, source)}' is truncated via .${methodName}()`,
          code: nodeText(call, source).slice(0, 100),
          severity: "error",
        });
      }
    }
  }

  return violations;
}

// ============================================================================
// DETECTION: Loop-based truncation (Math.min pattern)
// ============================================================================

function detectLoopTruncation(
  tree: Parser.Tree,
  source: string,
  filePath: string
): ASTViolation[] {
  const violations: ASTViolation[] = [];

  // Find for loops
  const forLoops = findNodes(tree.rootNode, ["for_statement"]);

  for (const loop of forLoops) {
    const loopText = nodeText(loop, source);

    // Check for Math.min pattern in condition
    if (/Math\.min\s*\([^)]*\.length/.test(loopText)) {
      violations.push({
        file: filePath,
        line: loop.startPosition.row + 1,
        column: loop.startPosition.column + 1,
        type: "loop-truncation",
        description: "Loop uses Math.min() to limit iterations (may truncate data)",
        code: loopText.split("\n")[0].slice(0, 100),
        severity: "warning",
      });
    }

    // Check for hardcoded limit comparison: i < 10
    const condition = loop.children.find((c) => c.type === "binary_expression");
    if (condition) {
      const condText = nodeText(condition, source);
      // Pattern: i < NUMBER where NUMBER is small
      const limitMatch = condText.match(/[a-z_]\w*\s*<\s*(\d+)/i);
      if (limitMatch && parseInt(limitMatch[1]) <= 100) {
        // Check if it's iterating over an array
        if (/\.length|\.size/.test(loopText)) {
          violations.push({
            file: filePath,
            line: loop.startPosition.row + 1,
            column: loop.startPosition.column + 1,
            type: "loop-truncation",
            description: `Loop hardcodes limit of ${limitMatch[1]} iterations`,
            code: loopText.split("\n")[0].slice(0, 100),
            severity: "warning",
          });
        }
      }
    }
  }

  return violations;
}

// ============================================================================
// DETECTION: Filter/map that drops items
// ============================================================================

function detectFilterTruncation(
  tree: Parser.Tree,
  source: string,
  filePath: string
): ASTViolation[] {
  const violations: ASTViolation[] = [];

  const callExpressions = findNodes(tree.rootNode, ["call_expression"]);

  for (const call of callExpressions) {
    const funcNode = call.childForFieldName("function");
    if (!funcNode || funcNode.type !== "member_expression") continue;

    const property = funcNode.childForFieldName("property");
    if (!property) continue;

    const methodName = nodeText(property, source);

    // Check .filter((_, i) => i < N) pattern
    if (methodName === "filter") {
      const args = call.childForFieldName("arguments");
      if (args) {
        const argsText = nodeText(args, source);
        // Pattern: filter with index comparison
        if (/\(\s*_?\s*,\s*\w+\s*\)\s*=>\s*\w+\s*<\s*\d+/.test(argsText)) {
          violations.push({
            file: filePath,
            line: call.startPosition.row + 1,
            column: call.startPosition.column + 1,
            type: "filter-truncation",
            description: ".filter() uses index to limit results (truncates data)",
            code: nodeText(call, source).slice(0, 100),
            severity: "error",
          });
        }
      }
    }

    // Check for chained .slice() after .map()/.filter()
    if (methodName === "slice") {
      const object = funcNode.childForFieldName("object");
      if (object && object.type === "call_expression") {
        const innerFunc = object.childForFieldName("function");
        if (innerFunc && innerFunc.type === "member_expression") {
          const innerMethod = innerFunc.childForFieldName("property");
          if (innerMethod) {
            const innerMethodName = nodeText(innerMethod, source);
            if (["map", "filter", "flatMap", "reduce"].includes(innerMethodName)) {
              violations.push({
                file: filePath,
                line: call.startPosition.row + 1,
                column: call.startPosition.column + 1,
                type: "chained-truncation",
                description: `.${innerMethodName}() results are truncated with .slice()`,
                code: nodeText(call, source).slice(0, 100),
                severity: "error",
              });
            }
          }
        }
      }
    }
  }

  return violations;
}

// ============================================================================
// DETECTION: Conditional early return with truncation
// ============================================================================

function detectConditionalTruncation(
  tree: Parser.Tree,
  source: string,
  filePath: string
): ASTViolation[] {
  const violations: ASTViolation[] = [];

  // Find if statements
  const ifStatements = findNodes(tree.rootNode, ["if_statement"]);

  for (const ifStmt of ifStatements) {
    const condition = ifStmt.childForFieldName("condition");
    const consequence = ifStmt.childForFieldName("consequence");

    if (!condition || !consequence) continue;

    const condText = nodeText(condition, source);

    // Check for length comparison in condition
    if (/\.length\s*>\s*\d+/.test(condText)) {
      // Check if consequence contains return with slice
      const returns = findNodes(consequence, ["return_statement"]);
      for (const ret of returns) {
        const retText = nodeText(ret, source);
        if (/\.slice\s*\(/.test(retText)) {
          violations.push({
            file: filePath,
            line: ifStmt.startPosition.row + 1,
            column: ifStmt.startPosition.column + 1,
            type: "conditional-return-truncation",
            description: "Conditional early return truncates data when length exceeds limit",
            code: `if ${condText} { ${retText.slice(0, 50)}... }`,
            severity: "error",
          });
        }
      }
    }
  }

  return violations;
}

// ============================================================================
// DETECTION: Assignment truncation (result = x.slice())
// ============================================================================

function detectAssignmentTruncation(
  tree: Parser.Tree,
  source: string,
  filePath: string
): ASTViolation[] {
  const violations: ASTViolation[] = [];

  // Find assignments and variable declarations
  const assignments = [
    ...findNodes(tree.rootNode, ["assignment_expression"]),
    ...findNodes(tree.rootNode, ["variable_declarator"]),
  ];

  for (const assign of assignments) {
    // Get the left side (variable name)
    const left =
      assign.childForFieldName("left") || assign.childForFieldName("name");
    if (!left) continue;

    const varName = nodeText(left, source);

    // Check if it's an LLM context variable being assigned
    if (!LLM_CONTEXT_VARS.has(varName)) continue;

    // Get the right side (value)
    const right =
      assign.childForFieldName("right") || assign.childForFieldName("value");
    if (!right) continue;

    // Check if right side contains truncation
    const calls = findNodes(right, ["call_expression"]);
    for (const call of calls) {
      const funcNode = call.childForFieldName("function");
      if (funcNode && funcNode.type === "member_expression") {
        const property = funcNode.childForFieldName("property");
        if (property && TRUNCATION_METHODS.has(nodeText(property, source))) {
          violations.push({
            file: filePath,
            line: assign.startPosition.row + 1,
            column: assign.startPosition.column + 1,
            type: "assignment-truncation",
            description: `LLM context variable '${varName}' assigned truncated value`,
            code: nodeText(assign, source).slice(0, 100),
            severity: "error",
          });
        }
      }
    }
  }

  return violations;
}

// ============================================================================
// MAIN ANALYZER
// ============================================================================

export function analyzeFile(filePath: string): ASTViolation[] {
  if (!existsSync(filePath)) return [];

  const parser = getParser(filePath);
  if (!parser) return [];

  let source: string;
  try {
    source = readFileSync(filePath, "utf-8");
  } catch {
    return [];
  }
  const tree = parser.parse(source);

  const violations: ASTViolation[] = [
    ...detectReturnTruncation(tree, source, filePath),
    ...detectContextVarTruncation(tree, source, filePath),
    ...detectLoopTruncation(tree, source, filePath),
    ...detectFilterTruncation(tree, source, filePath),
    ...detectConditionalTruncation(tree, source, filePath),
    ...detectAssignmentTruncation(tree, source, filePath),
  ];

  return violations;
}

export function analyzeFiles(filePaths: string[]): ASTViolation[] {
  const allViolations: ASTViolation[] = [];

  for (const filePath of filePaths) {
    const violations = analyzeFile(filePath);
    allViolations.push(...violations);
  }

  return allViolations;
}

export function formatASTViolations(violations: ASTViolation[]): string {
  if (violations.length === 0) return "";

  const lines: string[] = [];
  lines.push("");
  lines.push("========================================");
  lines.push("  AST-BASED TRUNCATION VIOLATIONS");
  lines.push("========================================");
  lines.push("");

  // Group by file
  const byFile = new Map<string, ASTViolation[]>();
  for (const v of violations) {
    const existing = byFile.get(v.file) || [];
    existing.push(v);
    byFile.set(v.file, existing);
  }

  for (const [file, fileViolations] of byFile) {
    lines.push(`📄 ${file}`);
    for (const v of fileViolations) {
      const severity = v.severity === "error" ? "❌" : "⚠️";
      lines.push(`  ${severity} Line ${v.line}: ${v.type}`);
      lines.push(`     ${v.description}`);
      lines.push(`     Code: ${v.code}`);
      lines.push("");
    }
  }

  lines.push("========================================");
  return lines.join("\n");
}

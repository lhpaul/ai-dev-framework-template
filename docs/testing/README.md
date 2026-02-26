# Testing — Smoke Test Execution Guide

> **STATUS: TEMPLATE**
>
> Fill in this file during project setup. Replace all `[placeholders]` with your project's actual tools, commands, and paths. Delete sections that don't apply.

**Audience**: AI agents running smoke tests (smoke-tester agent, Cursor run-smoke-test command, or equivalent).

The smoke test *process* (inputs, output format, pass criteria, fail handling) is defined in the [Smoke Test Protocol](../ai/development-workflow/protocols/05-smoke-test-protocol.md). This guide covers **how** to execute tests in this specific repo.

---

## 1. Read Context

Before running anything:

1. **Read the smoke test runbook** — provided by the human or located under `docs/testing/` (e.g. `docs/testing/[app]/[feature].smoke-test.md`).
2. **Read the application source** for the pages under test — selectors, form structure, component patterns.

---

## 2. Choose Execution Approach

Before writing any code, check whether a committed automated spec already exists for the feature under test.

```
Does [path/to/committed/spec/for/feature] exist?
  │
  ├─ YES → Run the committed test suite (preferred)
  │         [your e2e suite command]
  │
  └─ NO  → Write an ad-hoc script (fallback — see Section 3 below)
            After validating, consider promoting the script to a committed spec.
```

> **TODO**: Define the path convention for committed specs (e.g. `apps/e2e/src/[portal]/[feature].spec.ts`) and the run commands for your project.

If the spec exists, run it and report results directly. Do not write a duplicate ad-hoc script.

---

## 2a. Run the Committed Test Suite

> **TODO**: Fill in your project's test runner commands and any notes about what setup is handled automatically vs. manually.

```bash
# [your e2e suite command]
[command]

# [headed/debug mode if applicable]
[command]
```

---

## 3. Ad-hoc Script (Fallback)

Use when no committed spec exists yet.

### Environment Setup

> **TODO**: Fill in commands to start all required services and the application.

```bash
# Start backing services (e.g. local database)
[command]

# Reset and seed the database
[command]

# Start the application
[command]   # → http://localhost:[port]
```

### Install Browser Automation and Run

> **TODO**: Fill in your browser automation tooling. If using Node.js + Playwright:

```bash
cd /tmp && npm install playwright 2>/dev/null
npx playwright install chromium 2>/dev/null
node /tmp/smoke-test.mjs
```

### Script Structure

```js
// Example using Node.js + Playwright
import { chromium } from 'playwright';

const BASE_URL = 'http://localhost:[port]';
const results = [];

function pass(step) {
  results.push({ step, status: 'PASS' });
  console.log(`✅ PASS — ${step}`);
}

function fail(step, error) {
  results.push({ step, status: 'FAIL', error: String(error) });
  console.error(`❌ FAIL — ${step}: ${error}`);
}

(async () => {
  const browser = await chromium.launch({ headless: false });
  const context = await browser.newContext();
  const page = await context.newPage();

  try {
    // Step 1 — Login
    await page.goto(`${BASE_URL}/[login-path]`);
    // ... authentication
    pass('Step 1: Login');
  } catch (e) {
    fail('Step 1: Login', e);
  }

  console.log('\n--- RESULTS ---');
  results.forEach(r => console.log(`${r.status} — ${r.step}${r.error ? ': ' + r.error : ''}`));
  await browser.close();
})();
```

### Selector Priority

1. `[data-testid="..."]` — preferred (stable, automation-only)
2. ARIA roles (`getByRole(...)`)
3. Visible text (`getByText(...)`, `getByLabel(...)`)
4. CSS class / tag — last resort

### Waiting Strategy

```js
// ✅ Wait for element
await page.waitForSelector('[data-testid="my-element"]');

// ✅ Wait for navigation
await page.waitForURL('**/expected-path');

// ⚠️ Last resort only — document why no observable signal exists
await page.waitForTimeout(500);
```

### OTP / Email Testing

> **TODO**: Document how to extract OTPs or verification emails in your local environment (e.g. Mailpit, Mailhog, or similar).

```bash
# Example with Mailpit
curl -s http://localhost:[mailpit-port]/api/v1/messages | jq -r '.messages[0].Snippet' | grep -oE '[0-9]{6}'
```

### Database Verification

> **TODO**: Document how to query the database directly for verification.

```bash
# Example with PostgreSQL
[db-query-command]
```

### Cleanup

> **TODO**: Fill in cleanup commands.

```bash
# Stop app server
[kill-command]

# Stop backing services
[command]

# Remove temporary test files
rm -f /tmp/smoke-test*.mjs && rm -rf /tmp/smoke-screenshots
```

---

## Troubleshooting

> **TODO**: Document known issues, UI library quirks, and workarounds specific to this project's tech stack. For example: dialog rendering behaviour, dropdown interaction patterns, form submission edge cases.

---

## References

- **Smoke test process and output format**: [Smoke Test Protocol](../ai/development-workflow/protocols/05-smoke-test-protocol.md)

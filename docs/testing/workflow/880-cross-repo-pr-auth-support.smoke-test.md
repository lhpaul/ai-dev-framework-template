# Smoke Test Runbook: Cross-Repository Pull Request Authentication and Operation Support

**Feature**: Cross-repository pull request authentication and operation support
**Spec**: [1_880-cross-repo-pr-auth-support_specs.md](../../specs/developments/20260610165914_880-cross-repo-pr-auth-support/1_880-cross-repo-pr-auth-support_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] You are reviewing the implementation PR for #880.
- [ ] #875 is merged into `develop-workflow-hub-mode`.
- [ ] The PR targets `develop-workflow-hub-mode`.
- [ ] The implementation diff is available locally.
- [ ] No live GitHub App credentials are required for the automated fixture
      tests.

---

## Test Data

| Item | Value |
| --- | --- |
| Token helper | `scripts/development-workflow/github-app-token.sh` |
| Product PR helper | `scripts/development-workflow/open-product-pr.sh` |
| Config resolver | `scripts/development-workflow/workflow-config-resolver.py` |
| Local config example | `.ai-dev-workflow.local.example.yaml` |
| GitHub App docs | `docs/workflow/development-workflow/integrations/workflow-hub-github-app.md` |
| Auth fixture tests | `scripts/development-workflow/tests/test-workflow-hub-pr-auth.sh` |

---

## Smoke Test Steps

### Step 1: Verify Setup Documentation

**Maps to**: AC1, AC2, AC3, AC4

1. Open the GitHub App integration doc.
2. Confirm it lists required product repository permissions and installation
   steps.
3. Confirm it distinguishes committed shared config from local-only config.
4. Confirm the local example uses placeholders only.
5. If a token cache was introduced, confirm its path is listed in `.gitignore`.

**Expected result**: Operators can configure product repository access without
putting private key paths, secret-manager locations, tokens, or cache paths in
versioned shared config.

### Step 2: Verify Local Config Validation

**Maps to**: AC2, AC3, AC8

1. Run the auth fixture test harness.
2. Inspect the cases where shared config contains local-only secret-bearing
   auth fields.
3. Inspect the cases where shared config contains non-secret app id and
   installation id values.
4. Inspect the cases where local config contains placeholder auth refs.
5. Confirm shared config fails closed only for secret-bearing fields and local
   config is accepted.

**Expected result**: Auth references are local-only and versioned config remains
secret-free.

### Step 3: Verify Token Helper Redaction

**Maps to**: AC5, AC8, AC10

1. Run token helper fixture cases for missing app id, missing private key or
   secret ref, missing installation, and permission denied.
2. Confirm each failure reports the selected product repository and the missing
   setup step.
3. Confirm captured stdout/stderr do not contain fixture tokens, private key
   text, or secret-ref values.
4. Run explicit machine token mode with a fixture token.
5. Confirm stdout contains only the token and human logs are on stderr.

**Expected result**: Normal logs and failure output never disclose token or key
material, while machine mode has a narrow token-output contract.

### Step 4: Verify Product PR Dry Run

**Maps to**: AC6, AC7, AC9

1. Use a workflow hub fixture with two product repositories.
2. Run the product PR helper in dry-run mode for `mobile-app`.
3. Run the same helper in dry-run mode for `admin-portal`.
4. Confirm the output shows distinct target repositories, base branches, head
   branches, titles, and redacted command shapes.
5. Confirm dry-run mode does not require credentials.

**Expected result**: Dry-run output proves PR command construction for two
product repositories without exposing secrets.

### Step 5: Verify Product PR Live Command Contract

**Maps to**: AC6, AC10

1. Run the live-mode fixture with a stubbed token helper and stubbed `gh`.
2. Confirm `gh pr create` receives `--repo <owner/repo>` for the selected
   product repository.
3. Confirm `GH_TOKEN` is set only for the child command.
4. Confirm the token value is absent from captured logs and summary output.

**Expected result**: Live PR creation targets the product repository and passes
credentials through a non-logging environment path.

### Step 6: Verify Failure Boundaries

**Maps to**: AC6, AC8, AC9

1. Run fixture cases for no product repo selection in a multi-product hub.
2. Run fixture cases for an unknown product repo name.
3. Run fixture cases for a non-GitHub product repo `git_url`.
4. Run fixture cases for missing title, base, head, or body file values.
5. Confirm every case fails before auth or PR creation.

**Expected result**: The helpers fail closed before unsafe fallback or hub-repo
PR creation.

### Step 7: Run Automated Validation

**Maps to**: AC1 through AC10

1. Run:

   ```bash
   bash scripts/development-workflow/tests/test-workflow-hub-pr-auth.sh
   bash scripts/development-workflow/tests/test-workflow-config-resolver.sh
   ```

2. Run shell, Python, markdown, and changelog validation from the implementation
   plan.

**Expected result**: Auth, dry-run, command routing, redaction, and config
regression checks pass.

---

## Assertions Checklist

- [ ] AC1: Setup docs list GitHub App permissions and product repo installation
      steps.
- [ ] AC2: Versioned config excludes private key paths, machine-local secret
      locations, token values, and cache paths.
- [ ] AC3: Secret refs and private key paths are documented as local-only.
- [ ] AC4: Any introduced auth cache path is gitignored.
- [ ] AC5: Token helper logs do not print token values.
- [ ] AC6: Product PR helper targets the selected product repository.
- [ ] AC7: Dry-run or fixture validation covers two product repositories.
- [ ] AC8: Missing app id, private key or secret ref, installation access, and
      permission failures are actionable.
- [ ] AC9: Help and dry-run output work before real credentials are available.
- [ ] AC10: Scripts use the selected product token and repo context without
      exposing secrets.

---

## Seed Data Reference

No persistent seed data is required. Automated tests should create temporary
workflow hub fixtures, two product repo definitions, placeholder local auth
refs, stub token responses, and a stubbed `gh` command.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Dry-run targets the hub repository | Product repo slug resolution fell back to the current remote | Resolve `TARGET_GITHUB_REPO` or GitHub-form `TARGET_GIT_URL` before constructing `gh pr create`. |
| Token appears in logs | Helper mixed machine output with human logs | Keep token stdout behind explicit machine mode and send redacted status logs to stderr. |
| Shared config accepts `private_key_path` | Local-only key validation missed nested auth keys | Extend resolver validation and tests for nested `github_app` fields. |
| Missing auth uses a human `gh` token | Helper fell back to ambient auth | Fail closed when selected product repo GitHub App config is incomplete. |
| Non-GitHub target reaches auth | PR helper did not validate repo slug first | Fail before token helper invocation for unsupported `git_url` values. |

---

## Known Limitations

- The smoke test uses fixtures and command stubs. It does not prove live GitHub
  App installation permissions in a real product repository.
- The MVP should avoid persistent token caching. If implementation introduces a
  cache, reviewers must verify the additional cache-specific checks in this
  runbook.

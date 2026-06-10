# Cross-Repository Pull Request Authentication and Operation Support - Spec

**Depends on**: 875-shared-local-workflow-config

---

## Overview

Workflow hub mode needs to open and inspect implementation pull requests in
product repositories while keeping credentials out of versioned configuration
and logs. This feature defines the operator-facing setup, authentication
handling, local-only secret reference rules, and pull-request operation behavior
needed for a workflow hub to work across product repositories safely.

## Brief Objective List

1. Document GitHub App setup for product repositories.
2. Add token helper behavior for workflow hub product repository operations.
3. Add a local auth cache ignore path if needed.
4. Store secret paths or secret-manager references in local workflow config,
   not shared workflow config.
5. Add helper behavior for opening pull requests against the correct product
   repository.
6. Ensure scripts can use the correct token and repository context without
   printing secrets.
7. List required GitHub App permissions and installation steps.
8. Ensure token helper output avoids normal-log token disclosure.
9. Ensure secret references and private key paths are gitignored/local-only.
10. Ensure versioned config excludes private key paths and machine-local secret
    locations.
11. Validate pull-request command construction for two different product
    repositories in dry-run or fixture mode.
12. Provide clear failures for missing app id, private key, or installation
    access.

## Use Cases

### Use Case 1: Operator configures cross-repository GitHub App access

**Actor**: Workflow hub operator
**Preconditions**: The team uses a workflow hub to coordinate implementation
work in one or more GitHub product repositories.

**Steps**:

1. The operator reads workflow hub authentication setup guidance.
2. The guidance lists required GitHub App permissions and installation scope.
3. The operator installs or verifies app access for each target product
   repository.
4. The operator stores app identifiers, private key locations, or secret-manager
   references only in local workflow configuration.
5. The operator confirms no private key paths or machine-local secret locations
   were added to versioned workflow configuration.

**Postconditions**: Product repository pull-request operations have a documented
authentication setup path, and sensitive material stays local-only.

**Information shown**:

- Required GitHub App permissions.
- Installation steps for product repositories.
- Local-only configuration fields.
- Versioned configuration fields that are safe to commit.
- Explicit warning against storing secrets or private key paths in shared
  configuration.

**Actions available**:

- Add local secret references.
- Verify product repository app installation.
- Run dry-run validation before opening a pull request.

**Considerations**:

- The spec does not require one specific secret manager, but it must support
  local secret references without putting secret values in the repository.

### Use Case 2: Workflow hub obtains an operation token without exposing it

**Actor**: Workflow script or operator
**Preconditions**: Local authentication configuration points to valid GitHub App
or token source information for a selected product repository.

**Steps**:

1. The script requests credentials for one selected product repository.
2. The authentication helper resolves local-only secret references.
3. The helper returns a token to the calling script through a non-logging path.
4. Normal logs report token source status without printing token material.
5. If required auth material is missing, the helper fails with a clear
   actionable error.

**Postconditions**: The caller can authenticate product repository operations
without exposing token values in normal logs.

**Information shown**:

- Selected product repository.
- Whether required local auth references were found.
- Clear failure reason when app id, private key, secret reference, or
  installation access is missing.

**Actions available**:

- Retry after fixing local config.
- Stop before attempting a product repository operation.

**Considerations**:

- Token output is sensitive even when short-lived. Normal user-facing logs must
  not include it.

### Use Case 3: Workflow hub opens a pull request in the selected product repository

**Actor**: Workflow script or orchestrator
**Preconditions**: A product repository implementation branch exists, and a
selected product repository has resolvable auth and repository context.

**Steps**:

1. The workflow asks to open an implementation pull request.
2. The pull-request helper resolves selected product repository context.
3. The helper obtains the correct token for that product repository.
4. The helper constructs the pull-request operation for the selected product
   repository rather than the workflow hub.
5. The helper opens the pull request or, in dry-run mode, reports the intended
   command without using real credentials.

**Postconditions**: The implementation pull request is opened against the
selected product repository, or dry-run output proves the operation would target
the selected product repository.

**Information shown**:

- Selected product repository.
- Base branch and head branch.
- Pull request title and target repository.
- Dry-run command shape without token values.
- Success URL or clear failure reason.

**Actions available**:

- Open a pull request for one selected product repository.
- Run dry-run validation.
- Stop and fix auth or repository context errors.

**Considerations**:

- Product repository identity must not be inferred from the workflow hub remote
  when a selected product repository is available.

### Use Case 4: Operator diagnoses authentication failures

**Actor**: Workflow hub operator
**Preconditions**: A cross-repository pull-request operation cannot authenticate
or cannot access the selected product repository.

**Steps**:

1. The operator runs the authentication or pull-request helper.
2. The helper detects missing app id, missing private key or secret reference,
   inaccessible installation, or insufficient repository access.
3. The helper reports the specific missing requirement and where to configure
   it.
4. The helper exits without printing secrets and without attempting an unsafe
   fallback.

**Postconditions**: The operator knows which auth setup step is missing without
secret exposure.

**Information shown**:

- Failure category.
- Selected product repository.
- Local config location or setup step to fix.
- No token or private key values.

**Actions available**:

- Add missing local config.
- Install or reconfigure the GitHub App.
- Retry dry-run validation.

**Considerations**:

- Silent fallback to the operator's general GitHub CLI token can hide product
  repository installation problems; failures must be explicit when the selected
  auth source is incomplete.

## Business Rules

- Versioned workflow configuration must not contain private key paths,
  machine-local secret locations, token values, or private secret-manager
  account details.
- Local workflow configuration may contain private key paths or secret-manager
  references, but not secret values that should be logged or committed.
- Any local auth cache path introduced by this feature must be gitignored.
- Token helpers must not print token values in normal logs.
- Pull-request helpers must target the selected product repository in
  workflow hub mode.
- Dry-run validation must show target repository, base branch, head branch, and
  title without exposing credentials.
- Authentication failures must identify missing app id, missing private key or
  secret reference, missing installation access, or insufficient permission
  where that category is known.
- Scripts must not silently fall back to the workflow hub repository when a
  selected product repository is required.
- Setup documentation must list required GitHub App permissions and
  installation steps.

## Security and Command Experience Rules

- Normal output may report that a token was acquired, but not the token value.
- Error output must never include private key contents or token values.
- Local-only config examples must use placeholders, not real paths or private
  account names.
- Help and dry-run output must be usable before real credentials are available.
- Failure messages should prefer "missing `<local config field>`" or "missing
  GitHub App installation for `<product repo>`" over generic auth failures.

## Statuses / Enum Values

| Code value | Display label | Description |
| --- | --- | --- |
| `auth_configured` | Auth configured | Required local auth references exist for the selected product repository. |
| `missing_app_id` | Missing app id | The app identifier needed for auth is absent. |
| `missing_private_key` | Missing private key | The configured private key path or secret reference cannot be resolved. |
| `missing_installation` | Missing installation | The GitHub App is not installed or cannot access the product repository. |
| `permission_denied` | Permission denied | Auth exists but lacks required repository permission. |
| `dry_run_ready` | Dry-run ready | PR operation construction can be shown without real token use. |
| `pr_opened` | Pull request opened | The product repository pull request was created successfully. |

**Valid transitions**:

- `missing_app_id` -> `auth_configured` after local app id configuration is
  added.
- `missing_private_key` -> `auth_configured` after local secret reference or
  private key path is valid.
- `missing_installation` -> `auth_configured` after the GitHub App is installed
  for the selected product repository.
- `auth_configured` -> `dry_run_ready` when dry-run command construction
  succeeds.
- `auth_configured` -> `pr_opened` when a real pull-request operation succeeds.

## Operational Visibility

- **Setup docs**: Operators can see required GitHub App permissions,
  installation steps, local-only fields, and safe versioned fields.
- **Helper output**: Authentication helpers report success/failure state without
  token disclosure.
- **Dry-run output**: Pull-request helpers show target product repository and
  branch/title construction without credentials.
- **Failure output**: Missing auth requirements name the field or setup step
  that must be fixed.

## Acceptance Criteria

- [ ] AC1: Setup documentation lists required GitHub App permissions and
      installation steps for product repository pull-request operations.
- [ ] AC2: Versioned configuration does not contain private key paths,
      machine-local secret locations, token values, or local auth cache paths.
- [ ] AC3: Secret references and private key paths are documented as
      local-only configuration.
- [ ] AC4: Any local auth cache path introduced by the feature is gitignored.
- [ ] AC5: Token helper behavior does not print token values in normal logs or
      failure output.
- [ ] AC6: Pull-request helper behavior targets the selected product
      repository, not the workflow hub repository, in workflow hub mode.
- [ ] AC7: Dry-run or fixture validation proves pull-request command
      construction for two different product repositories.
- [ ] AC8: Missing app id, missing private key or secret reference, missing
      installation access, and insufficient permission failures are clear and
      actionable.
- [ ] AC9: Help and dry-run output are usable before real credentials are
      available and do not require printing secrets.
- [ ] AC10: Scripts can use the correct token and product repository context
      without exposing secrets in user-facing output.

## Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| Document GitHub App setup for product repositories. | AC1 |
| Add token helper behavior for workflow hub product repository operations. | AC5, AC8, AC10 |
| Add a local auth cache ignore path if needed. | AC4 |
| Store secret paths or secret-manager references in local workflow config, not shared workflow config. | AC2, AC3 |
| Add helper behavior for opening pull requests against the correct product repository. | AC6, AC7 |
| Ensure scripts can use the correct token and repository context without printing secrets. | AC5, AC10 |
| List required GitHub App permissions and installation steps. | AC1 |
| Ensure token helper output avoids normal-log token disclosure. | AC5 |
| Ensure secret references and private key paths are gitignored/local-only. | AC2, AC3, AC4 |
| Ensure versioned config excludes private key paths and machine-local secret locations. | AC2 |
| Validate pull-request command construction for two different product repositories in dry-run or fixture mode. | AC7 |
| Provide clear failures for missing app id, private key, or installation access. | AC8 |

## Out of Scope (MVP)

- Building a full credential management product or choosing a required secret
  manager.
- Storing token values, private key contents, or secret-manager credentials in
  repository files.
- Automatically installing the GitHub App into product repositories.
- Opening pull requests that span multiple product repositories at once.
- Merging, approving, or reviewing product repository pull requests.
- Replacing existing human GitHub authentication for single-repository mode.

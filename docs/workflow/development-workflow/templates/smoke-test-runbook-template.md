# Smoke Test Runbook: [Feature Name]

**Feature**: [Feature name]
**Spec**: [Link to spec]
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] Application is running locally (or in staging)
- [ ] Database is seeded with the required test data (see Seed Data section)
- [ ] You are in a fresh session (logged out)

---

## Test Data

| Item | Value |
|---|---|
| Test user (role X) | `[email or username]` |
| Test user (role Y) | `[email or username]` |
| [Entity] ID | `[ID or how to find it]` |
| Feature URL | `[URL path]` |

---

## Smoke Test Steps

### Step 0: Ensure logged out

- Navigate to the application
- If logged in, log out

### Step 1: Log in as [Actor]

- Navigate to `[login URL]`
- Log in as `[test user]`
- Verify: [what the user sees after login]

### Step 2: [Use Case Name]

**Maps to**: Acceptance Criterion N

1. [Action 1]
2. [Action 2]
3. ...

**Expected result**: [What the user should see / what should happen]

### Step 3: [Next Use Case or Flow]

1. [Action 1]
2. ...

**Expected result**: [Expected result]

<!-- Add steps for each use case and acceptance criterion -->

### Last Step: Validate & Shut Down

- Verify all assertions in the checklist below are met
- Shut down the application

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] [Criterion 1: testable description]
- [ ] [Criterion 2: testable description]
- [ ] [Criterion 3: testable description]

---

## Seed Data Reference

The following seed data must be present:

| Entity | Scenario | How to load |
|---|---|---|
| [Entity] | [Scenario description] | `[seed command]` |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| [Symptom 1] | [Cause] | [How to fix] |
| [Symptom 2] | [Cause] | [How to fix] |

---

## Known Limitations

<!-- Document any known issues with the smoke test itself (not the feature) -->

- [Limitation 1]

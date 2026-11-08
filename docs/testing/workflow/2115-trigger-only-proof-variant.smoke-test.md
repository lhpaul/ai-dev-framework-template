# Trigger- or gate-only proof variant — Synthetic smoke test

## Scope

Reproducible evidence for acceptance criterion 3 of #2115: a trigger-only
fixture pull request that carries live run evidence in both directions is not
marked blocking by the local AI reviewer preset. It also records a negative
control: the same fixture with run evidence in one direction only still
blocks, so the variant does not relax the evidence requirement.

The fixture is disposable and synthetic. The repository, the pull request
(`fixture/trigger-only#7`), its body and its run IDs are fabricated. GitHub is
replaced by a `gh` stub that serves the fixture metadata, so no remote pull
request is opened. The reviewer itself is real: the bundled Codex preset of
`scripts/development-workflow/local-ai-reviewer.sh`. No private local
configuration, credential or user data is read or copied.

## Fixture

- Base commit: `.github/workflows/build.yml` with two jobs (`docker-build`,
  `integration-tests`) on `pull_request` `types: [opened, synchronize,
  reopened]` and a `paths: ["packages/**"]` filter.
- Head commit on `fix/skip-ci-on-draft`: adds `ready_for_review` to `types`
  (line 4) and a job-level `if: github.event.pull_request.draft == false` to
  each job (lines 12 and 20), plus a `changelog.d/` fragment. No `run:`,
  `uses:` or step changes.
- Pull request body: cites the three gate locations and two runs with the same
  plant (`packages/plant/README.md`): one where the gate lets the jobs run
  (ready for review) and one where it skips them (draft).
- `FIXTURE_EVIDENCE=one-direction` removes the draft row (negative control).
- `REVIEW.md`, `docs/best-practices/3-testing.md` and the review doctrine are
  copied from the ADF ref under test, so the same fixture is reviewed against
  the old and the new contract.

## Recipe

Save the script below as `run-2115-fixture.sh` outside the repository, then
run it from any directory with the ADF checkout, the ref under test and an
output directory:

```text
LOCAL_CODEX_REVIEWER_BIN=codex-review-high \
  bash run-2115-fixture.sh <adf-checkout> <review-ref> <out-dir>
FIXTURE_EVIDENCE=one-direction LOCAL_CODEX_REVIEWER_BIN=codex-review-high \
  bash run-2115-fixture.sh <adf-checkout> <review-ref> <out-dir>
```

`LOCAL_CODEX_REVIEWER_BIN` is optional (default `codex`); the runs below used
the `codex-review-high` wrapper that the ready-phase reviewer uses on the
recording machine. The script prints `RESULT`, `BLOCKING_COUNT` and each
blocking finding, and keeps `fixture.diff`, `pr-body.md`, the full reviewer
output and its evidence JSON in `<out-dir>`.

```bash
#!/usr/bin/env bash
# Usage: run-2115-fixture.sh <adf-checkout> <review-ref> <out-dir>
# Builds a disposable trigger-only fixture PR whose REVIEW.md, testing guide
# and review doctrine come from <review-ref>, then runs the real
# local-ai-reviewer bundled preset against it with GitHub mocked.
set -euo pipefail

ADF="$(cd "$1" && pwd -P)"
REVIEW_REF="$2"
OUT="$3"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd -P)"
WORK="$(mktemp -d)"
FIX="$WORK/fixture"
MOCK_BIN="$WORK/bin"
mkdir -p "$FIX" "$MOCK_BIN"

git -C "$WORK" init -q --bare origin.git
git -C "$FIX" init -q -b develop
git -C "$FIX" config user.email fixture@example.invalid
git -C "$FIX" config user.name "Fixture"
git -C "$FIX" remote add origin "$WORK/origin.git"

# Review contract under test, taken verbatim from <review-ref>.
mkdir -p "$FIX/docs/best-practices" "$FIX/docs/workflow/development-workflow"
git -C "$ADF" show "$REVIEW_REF:REVIEW.md" >"$FIX/REVIEW.md"
git -C "$ADF" show "$REVIEW_REF:docs/best-practices/3-testing.md" \
  >"$FIX/docs/best-practices/3-testing.md"
git -C "$ADF" show "$REVIEW_REF:docs/workflow/development-workflow/review-doctrine.md" \
  >"$FIX/docs/workflow/development-workflow/review-doctrine.md"

mkdir -p "$FIX/.github/workflows" "$FIX/packages/api"
printf 'export const ok = true;\n' >"$FIX/packages/api/index.js"
cat >"$FIX/.github/workflows/build.yml" <<'YAML'
name: Build validation
on:
  pull_request:
    types: [opened, synchronize, reopened]
    paths:
      - "packages/**"
permissions:
  contents: read
jobs:
  docker-build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
      - name: Build images
        run: docker build -f packages/api/Dockerfile .
  integration-tests:
    runs-on: ubuntu-latest
    needs: docker-build
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
      - name: Integration tests
        run: npm run test:integration
YAML
git -C "$FIX" add -A
git -C "$FIX" commit -q -m "chore: baseline"
git -C "$FIX" push -q origin develop
git -C "$FIX" fetch -q origin

# Trigger-only change: run the jobs only on non-draft PRs.
git -C "$FIX" checkout -q -b fix/skip-ci-on-draft
python3 - "$FIX/.github/workflows/build.yml" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
text = text.replace("types: [opened, synchronize, reopened]",
                    "types: [opened, synchronize, reopened, ready_for_review]")
gate = "    if: github.event.pull_request.draft == false\n"
text = text.replace("    runs-on: ubuntu-latest\n    steps:",
                    "    runs-on: ubuntu-latest\n" + gate + "    steps:", 1)
text = text.replace("    runs-on: ubuntu-latest\n    needs: docker-build\n",
                    "    runs-on: ubuntu-latest\n    needs: docker-build\n" + gate, 1)
open(path, "w", encoding="utf-8").write(text)
PY
mkdir -p "$FIX/changelog.d"
printf '%s\n' "- **Build validation skips draft pull requests** (#42): Docker build and integration tests run only once a pull request is ready for review." \
  >"$FIX/changelog.d/42.fixed.skip-ci-on-draft.md"
git -C "$FIX" add -A
git -C "$FIX" commit -q -m "fix(ci): skip build validation on draft pull requests"
git -C "$FIX" diff origin/develop...HEAD >"$OUT/fixture.diff"
HEAD_SHA="$(git -C "$FIX" rev-parse HEAD)"

cat >"$WORK/body.md" <<'BODY'
## Summary

Run Build validation (`docker-build`, `integration-tests`) only on non-draft
pull requests to cut Actions minutes. Only the trigger and job-level `if:`
keys change; no `run:`, `uses:` or step changed.

Closes #42.

## Verification

Gate locations:

- `.github/workflows/build.yml:4` adds `ready_for_review` to `pull_request.types`.
- `.github/workflows/build.yml:12` and `.github/workflows/build.yml:20` add
  `if: github.event.pull_request.draft == false` to each job.

Live runs in both directions with the same plant, a new file
`packages/plant/README.md` that matches the `packages/**` path filter:

| Direction | PR state | Run | Result |
| --- | --- | --- | --- |
| Gate must let the check run | ready for review | 18500000001 | `docker-build` success, `integration-tests` success |
| Gate must skip the check | draft | 18500000002 | `docker-build` skipped, `integration-tests` skipped |

The steps of both jobs are unchanged, so their validation logic keeps its
existing proof.
BODY

# FIXTURE_EVIDENCE=one-direction keeps only the "gate lets the check run" row
# (negative control: the variant must still block one-directional evidence).
if [ "${FIXTURE_EVIDENCE:-both}" = "one-direction" ]; then
  grep -v '| Gate must skip the check |' "$WORK/body.md" >"$WORK/body.one" || true
  sed 's/Live runs in both directions with the same plant/A live run with a plant/' "$WORK/body.one" >"$WORK/body.md"
fi

cat >"$MOCK_BIN/gh" <<'MOCK_GH'
#!/usr/bin/env bash
case "$*" in
  *"pr view 7 "*"--json baseRefName,headRefName,headRefOid,body"*)
    jq -n --arg head "$FIXTURE_HEAD" --rawfile body "$FIXTURE_BODY" \
      '{baseRefName:"develop",headRefName:"fix/skip-ci-on-draft",headRefOid:$head,body:$body}' ;;
  *"pr diff 7 "*"--name-only"*)
    printf '%s\n' ".github/workflows/build.yml" "changelog.d/42.fixed.skip-ci-on-draft.md" ;;
  *"pr view 7 "*"--json headRefOid,body"*)
    jq -n --arg head "$FIXTURE_HEAD" --rawfile body "$FIXTURE_BODY" '{headRefOid:$head,body:$body}' ;;
  *"api"*"repos/fixture/trigger-only/issues/7/comments"*)
    printf '[[]]\n' ;;
  *) exit 1 ;;
esac
MOCK_GH
chmod +x "$MOCK_BIN/gh"

set +e
(
  cd "$FIX"
  env -u LOCAL_AI_REVIEWER_COMMAND \
    PATH="$MOCK_BIN:$PATH" \
    FIXTURE_HEAD="$HEAD_SHA" FIXTURE_BODY="$WORK/body.md" \
    LOCAL_AI_REVIEWER_BACKEND=codex \
    LOCAL_CODEX_REVIEWER_BIN="${LOCAL_CODEX_REVIEWER_BIN:-codex}" \
    LOCAL_AI_REVIEWER_EVIDENCE_FILE="$OUT/evidence.json" \
    "$ADF/scripts/development-workflow/local-ai-reviewer.sh" 7 fixture trigger-only --timeout 900
) >"$OUT/reviewer.out" 2>"$OUT/reviewer.err"
status=$?
set -e
printf 'REVIEW_REF=%s\nFIXTURE_EVIDENCE=%s\nFIXTURE_HEAD=%s\nEXIT=%s\n' "$REVIEW_REF" "${FIXTURE_EVIDENCE:-both}" "$HEAD_SHA" "$status" >"$OUT/summary.txt"
grep -E '^(RESULT|REASON|BLOCKING_COUNT|BLOCKING_[0-9]+_(PATH|LINE|BODY)|ADVISORY_COUNT)=' "$OUT/reviewer.out" >>"$OUT/summary.txt" || true
cat "$OUT/summary.txt"
cp "$WORK/body.md" "$OUT/pr-body.md"
rm -rf "$WORK"
```

## Recorded runs

Recorded 2026-11-08 with Codex CLI 0.160.1. Baseline ref: `origin/develop` at
`46d14b28` (before this change). Candidate refs: the first commit of this
branch, `8f59ada2`; `8909afb3`, which rewords the variant so the two runs
differ only in the input the gate keys on; and `5719ef34`, which adds the
no-run evidence form for skips by a workflow-level filter. Each run is an
independent model call.

| Contract | Evidence in body | Runs | Result |
| --- | --- | --- | --- |
| Candidate (`8f59ada2`) | both directions | 2 | `clean`, 0 blocking (2/2) |
| Candidate (`8f59ada2`) | one direction | 2 | `needs_fixes`, 1 blocking (2/2) |
| Candidate (`8909afb3`) | both directions | 2 | `clean`, 0 blocking (2/2) |
| Candidate (`8909afb3`) | one direction | 2 | `needs_fixes`, 1 blocking (2/2) |
| Candidate (`5719ef34`) | both directions | 2 | `clean`, 0 blocking (2/2) |
| Candidate (`5719ef34`) | one direction | 2 | `needs_fixes`, 1 blocking (2/2) |
| Baseline (`46d14b28`) | both directions | 2 | `clean`, 0 blocking (2/2) |
| Baseline (`46d14b28`) | one direction | 2 | `needs_fixes`, 1 blocking (2/2) |

Blocking findings in the one-direction runs (abridged, `build.yml:12`):

- Candidate `8f59ada2`: "REVIEW.md requires live run IDs in both directions for
  trigger/gate-only changes … This is missing verification proof, not an
  identified code defect; no failing-check run is required."
- Candidate `8909afb3`: "REVIEW.md requires live run-and-skip evidence for
  trigger/gate-only changes. Supply a draft-PR run showing both jobs skipped,
  retaining the same path-matching plant and varying only PR state/event …"
- Candidate `5719ef34`: "REVIEW.md requires both run and skip evidence for
  this gate-only change. Add a live draft-PR run showing docker-build and
  integration-tests skipped, retaining the same plant and varying only the
  gate input … no failing-check run is required."
- Baseline: "REVIEW.md requires bidirectional planted-violation proof for
  materially modified CI controls … demonstrates neither a targeted violation
  nor the draft-blocking direction … Unchanged steps do not exempt the changed
  trigger and guards."

Two earlier runs (one per contract) used a fixture without a `changelog.d/`
fragment and both blocked only on the missing fragment (REVIEW.md Pass 1).
The fragment was added to the fixture; those runs are not counted above.

## Reading the result

- Acceptance criterion 3 holds: with the new contract, the trigger-only
  fixture with two-direction run evidence is `clean` in every run.
- The variant does not weaken the gate: one-directional evidence still blocks,
  and the candidate finding names the variant's own requirement (both
  directions, run IDs, no failing-check run).
- The difference shows in what the reviewer asks for. Under the old contract
  the reviewer asks for a "targeted violation" — the failing-check demand that
  blocked the downstream pull request. Under the new contract it asks only for
  the missing direction and states that no failing-check run is required.
- The fixture covers a job-level `if:` gate, where both directions create a
  run. The no-run evidence form for skips by a workflow-level filter is
  reviewed as text only; no fixture exercises it.
- This fixture does not reproduce the downstream false positive on the old
  contract when two-direction evidence is present (baseline `clean`, 2/2).
  The model's verdict varies with how the body argues the case, so the
  downstream three-round block is not claimed as reproduced here.

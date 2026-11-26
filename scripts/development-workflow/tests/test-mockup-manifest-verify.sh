#!/usr/bin/env bash
# test-mockup-manifest-verify.sh — mockup-manifest-verify.sh (#2206) verifies a
# manifest, an opted-in design tree, the id inventory and citations, reads
# manifests as data without running them, and changes no file.
#
# Spec: docs/specs/developments/20261126075749_2206-mockup-manifest-contract/
# Every case copies the committed fixtures
# (tests/fixtures/mockup-manifest-verify/) or writes its input into a fresh
# mktemp -d directory, runs the tool, and compares stdout lines and the exit
# status. Each run snapshots its case directory before and after (sorted find
# listing with cksum) and fails when anything changed (AC15). Each run has a
# 30-second watchdog. Runs use the invoking bash with the default python3,
# and /bin/bash with /usr/bin/python3 when present (Bash 3.2 and Python 3.9 on
# macOS). No real .ai-dev-workflow.local.* file is read or written; tree cases
# write a fabricated versioned .ai-dev-workflow.yaml into a disposable repo.
#
# Usage: bash scripts/development-workflow/tests/test-mockup-manifest-verify.sh
# covers: scripts/development-workflow/mockup-manifest-verify.sh
# covers: scripts/development-workflow/mockup-manifest-verify.py
# covers: scripts/development-workflow/workflow-lib.sh
# covers: scripts/development-workflow/workflow-config-resolver.py
# duration: 60

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts/development-workflow"
TOOL="$SCRIPTS_DIR/mockup-manifest-verify.sh"
MODULE="$SCRIPTS_DIR/mockup-manifest-verify.py"
FX="$SCRIPT_DIR/fixtures/mockup-manifest-verify"
INTENT="design/mockups/intent-app/mockup-manifest.js"
REPRO="design/mockups/repro-app/mockup-manifest.js"

PASS=0
FAIL=0
SKIP=0
WORK_DIR="$(mktemp -d)"
mkdir -p "$WORK_DIR/cases" "$WORK_DIR/run" "$WORK_DIR/markers"
cleanup() {
  # A mode-000 fixture would block rm -rf; restore permissions first.
  chmod -R u+rwx "$WORK_DIR" 2>/dev/null || true
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }
skip() { printf 'SKIP: %s\n' "$1"; SKIP=$((SKIP + 1)); }

IS_ROOT=0
[ "$(id -u)" = "0" ] && IS_ROOT=1

# ── Run configurations ──────────────────────────────────────────────────────

CFG_SHELL=()
CFG_PATH=()
CFG_LABEL=()
add_config() {
  local shell="$1" path_prefix="$2" label="$3" i
  [ -n "$shell" ] && [ -x "$shell" ] || return 0
  for i in ${CFG_SHELL[@]+"${!CFG_SHELL[@]}"}; do
    if [ "${CFG_SHELL[$i]}" = "$shell" ] && [ "${CFG_PATH[$i]}" = "$path_prefix" ]; then
      return 0
    fi
  done
  CFG_SHELL+=("$shell")
  CFG_PATH+=("$path_prefix")
  CFG_LABEL+=("$label")
}
add_config "${BASH:-}" "" "$(basename -- "${BASH:-bash}") $BASH_VERSION, python3"
SYS_PY_SHIM=""
if [ -x /usr/bin/python3 ] && [ "$(command -v python3)" != "/usr/bin/python3" ]; then
  SYS_PY_SHIM="$WORK_DIR/sys-python"
  mkdir -p "$SYS_PY_SHIM"
  printf '#!/bin/sh\nexec /usr/bin/python3 "$@"\n' >"$SYS_PY_SHIM/python3"
  chmod +x "$SYS_PY_SHIM/python3"
fi
add_config /bin/bash "$SYS_PY_SHIM" "/bin/bash, ${SYS_PY_SHIM:+/usr/bin/}python3"

# ── Helpers ─────────────────────────────────────────────────────────────────

new_case() {
  mktemp -d "$WORK_DIR/cases/case.XXXXXX"
}

copy_fixture() {
  cp -R "$FX/." "$1/"
}

MUTATE_PY='
import json, sys
path, code = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as handle:
    text = handle.read()
marker = "window.__MOCKUP_MANIFEST__ = "
start = text.index(marker) + len(marker)
m, end = json.JSONDecoder().raw_decode(text, start)
exec(code, {"m": m})
with open(path, "w", encoding="utf-8") as handle:
    handle.write(text[:start] + json.dumps(m, indent=2, ensure_ascii=False) + text[end:])
'
# mutate <manifest> <python statements editing the manifest object m>
mutate() {
  python3 -I -B -c "$MUTATE_PY" "$1" "$2"
}

EDIT_JSON_PY='
import json, sys
path, code = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as handle:
    t = json.load(handle)
scope = {"t": t}
exec(code, scope)
with open(path, "w", encoding="utf-8") as handle:
    json.dump(scope["t"], handle, indent=2, ensure_ascii=False)
'
# edit_json <file> <python statements editing the JSON value t>
edit_json() {
  python3 -I -B -c "$EDIT_JSON_PY" "$1" "$2"
}

EDIT_TEXT_PY='
import sys
path, old, new = sys.argv[1:4]
with open(path, encoding="utf-8") as handle:
    text = handle.read()
if old not in text:
    sys.exit("edit_text: text not found in " + path)
with open(path, "w", encoding="utf-8") as handle:
    handle.write(text.replace(old, new, 1))
'
# edit_text <file> <old> <new>: replaces the first occurrence; the old text must exist.
edit_text() {
  python3 -I -B -c "$EDIT_TEXT_PY" "$1" "$2" "$3"
}

# The repro-app manifest JSON on one line: a conforming value with no mirroring.
REPRO_JSON="$(python3 -I -B -c '
import json, sys
text = open(sys.argv[1], encoding="utf-8").read()
start = text.index("= ") + 2
print(json.dumps(json.JSONDecoder().raw_decode(text, start)[0]))
' "$FX/$REPRO")"
MIN_INTENT='{"$kind": "design-intent", "$status": "complete", "default_screen": "main", "frame": "desktop", "navigation": [], "screens": [{"screen_id": "main", "kind": "html"}]}'

# write_manifest <path> <json>
write_manifest() {
  mkdir -p "$(dirname -- "$1")"
  printf '// fabricated test manifest\nwindow.__MOCKUP_MANIFEST__ = %s;\n' "$2" >"$1"
}

# snapshot <dir>: sorted listing with checksums; the template checkout uses git status.
snapshot() {
  local dir="$1"
  if [ "$dir" = "$REPO_ROOT" ]; then
    GIT_OPTIONAL_LOCKS=0 git -C "$REPO_ROOT" status --porcelain --untracked-files=all 2>&1 || true
    return 0
  fi
  (
    cd "$dir" || exit 0
    find . 2>/dev/null | LC_ALL=C sort | while IFS= read -r entry; do
      if [ -L "$entry" ]; then
        printf '%s -> %s\n' "$entry" "$(readlink "$entry")"
      elif [ -f "$entry" ] && [ -r "$entry" ]; then
        printf '%s %s\n' "$entry" "$(cksum <"$entry")"
      else
        printf '%s\n' "$entry"
      fi
    done
  ) || true
}

OUT=""
ERR=""
RC=0
TIMED_OUT=0
CASE_CWD=""
CASE_TOOL=""
CASE_PATH=""
CASE_PATH_PREFIX=""

# run_tool <config index> <args...>: sets OUT, ERR, RC and TIMED_OUT.
run_tool() {
  local cfg="$1" out="$WORK_DIR/run/out" err="$WORK_DIR/run/err" pid start path_value
  shift
  path_value="$PATH"
  [ -z "${CFG_PATH[$cfg]}" ] || path_value="${CFG_PATH[$cfg]}:$path_value"
  [ -z "$CASE_PATH_PREFIX" ] || path_value="$CASE_PATH_PREFIX:$path_value"
  [ -z "$CASE_PATH" ] || path_value="$CASE_PATH"
  (
    cd "${CASE_CWD:-$WORK_DIR/run}" || exit 99
    PATH="$path_value" exec "${CFG_SHELL[$cfg]}" "${CASE_TOOL:-$TOOL}" "$@"
  ) >"$out" 2>"$err" </dev/null &
  pid=$!
  start=$SECONDS
  TIMED_OUT=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ $((SECONDS - start)) -ge 30 ]; then
      kill -9 "$pid" 2>/dev/null || true
      TIMED_OUT=1
      break
    fi
    sleep 0.02
  done
  RC=0
  wait "$pid" || RC=$?
  OUT="$(cat "$out")"
  ERR="$(cat "$err")"
}

# spec_ok <spec>: line:<exact line> | prefix:<line start> | noprefix:<line start> |
# contains:<text> | nocontains:<text> | exact:<whole stdout> | empty | stderr-clean
spec_ok() {
  local spec="$1" value="${1#*:}"
  case "$spec" in
    line:*) case $'\n'"$OUT"$'\n' in *$'\n'"$value"$'\n'*) return 0 ;; esac ;;
    prefix:*) case $'\n'"$OUT" in *$'\n'"$value"*) return 0 ;; esac ;;
    noprefix:*) case $'\n'"$OUT" in *$'\n'"$value"*) return 1 ;; *) return 0 ;; esac ;;
    contains:*) case "$OUT" in *"$value"*) return 0 ;; esac ;;
    nocontains:*) case "$OUT" in *"$value"*) return 1 ;; *) return 0 ;; esac ;;
    exact:*) [ "$OUT" = "$value" ] && return 0 ;;
    empty) [ -z "$OUT" ] && return 0 ;;
    stderr-clean) case "$ERR" in *Traceback*) return 1 ;; *) return 0 ;; esac ;;
    *) printf '  unknown spec: %s\n' "$spec" ;;
  esac
  return 1
}

# check <name> <case dir> <expected exit> <spec...> -- <tool args...>
# Runs under every configuration; asserts the exit, every spec, no watchdog
# kill, an unchanged case directory, and that a usage error (exit 2) printed
# nothing on stdout.
check() {
  local name="$1" dir="$2" want_rc="$3" spec cfg before after why
  local -a specs=()
  shift 3
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do
    specs+=("$1")
    shift
  done
  if [ "$#" -eq 0 ]; then
    fail "$name (test bug: missing --)"
    return 0
  fi
  shift
  for cfg in "${!CFG_SHELL[@]}"; do
    before="$(snapshot "$dir")"
    run_tool "$cfg" "$@"
    after="$(snapshot "$dir")"
    why=""
    [ "$TIMED_OUT" = 0 ] || why="$why; killed by the 30-second watchdog"
    [ "$RC" = "$want_rc" ] || why="$why; exit $RC, expected $want_rc"
    [ "$before" = "$after" ] || why="$why; the case directory changed"
    if [ "$want_rc" = 2 ] && [ -n "$OUT" ]; then
      why="$why; stdout is not empty on a caller error"
    fi
    for spec in ${specs[@]+"${specs[@]}"}; do
      spec_ok "$spec" || why="$why; spec failed: $spec"
    done
    if [ -z "$why" ]; then
      pass "$name [${CFG_LABEL[$cfg]}]"
    else
      fail "$name [${CFG_LABEL[$cfg]}]${why}"
      printf '  stdout:\n%s\n  stderr:\n%s\n' "$OUT" "$ERR" | sed 's/^/    /'
    fi
  done
  return 0
}

# ── Valid fixtures (AC4, AC5, AC7, AC9) ─────────────────────────────────────

run_valid_cases() {
  local dir shape
  shape="$(python3 -I -B -c '
import json, re, sys
root = sys.argv[1]
text = open(root + "/design/mockups/intent-app/mockup-manifest.js", encoding="utf-8").read()
m = json.JSONDecoder().raw_decode(text, text.index("= ") + 2)[0]
screens = m["screens"]
def depth(items, d):
    return max([depth(i.get("items", []), d + 1) for i in items] or [d])
html = open(root + "/design/mockups/intent-app/index.html", encoding="utf-8").read()
tokens = json.load(open(root + "/design/tokens.json", encoding="utf-8"))
ok = (len(screens) >= 3
      and any(sum(1 for s in x.get("states", []) if s.get("initial") is True) == 1 for x in screens)
      and max(depth(g["items"], 1) for g in m["navigation"]) >= 3
      and len(m.get("viewports", [])) >= 2
      and any(x["kind"] == "image" for x in screens)
      and any(k.startswith("$") for k in tokens)
      and "href=\"styles/tokens.css\"" in html
      and html.count("--color-primary: #1f6feb;") == 2)
print("ok" if ok else "bad")
' "$FX")"
  if [ "$shape" = "ok" ]; then
    pass "T-intent-fixture-shape (AC4 fixture has every required property)"
  else
    fail "T-intent-fixture-shape (AC4 fixture lost a required property)"
  fi

  dir="$(new_case)"
  copy_fixture "$dir"
  check "T-intent-valid" "$dir" 0 \
    "exact:$(printf '%s\n' 'MANIFEST_RESULT=conforms' 'MANIFEST_RESULT_LABEL=Conforms' \
      "MANIFEST_PATH=$INTENT" 'MANIFEST_KIND=design-intent' 'PROBLEM_COUNT=0')" \
    -- manifest "$dir/$INTENT" --repo-root "$dir"
  check "T-repro-valid" "$dir" 0 \
    "exact:$(printf '%s\n' 'MANIFEST_RESULT=conforms' 'MANIFEST_RESULT_LABEL=Conforms' \
      "MANIFEST_PATH=$REPRO" 'MANIFEST_KIND=reproduction' 'PROBLEM_COUNT=0')" \
    -- manifest "$dir/$REPRO" --repo-root "$dir"
  check "T-shared-state-id (empty under two screens conforms)" "$dir" 0 \
    "line:SCREEN_1_STATE_1_ID=empty" "line:SCREEN_2_STATE_1_ID=empty" "line:SCREEN_1_ID=login-email" \
    "line:SCREEN_2_ID=login-code" -- inventory "$dir/$INTENT" --repo-root "$dir"
  # Default repository root: the git toplevel of the committed fixture.
  check "T-intent-valid-default-root" "$FX" 0 "line:MANIFEST_RESULT=conforms" "line:PROBLEM_COUNT=0" \
    "line:MANIFEST_PATH=scripts/development-workflow/tests/fixtures/mockup-manifest-verify/$INTENT" \
    -- manifest "$FX/$INTENT"

  dir="$(new_case)"
  copy_fixture "$dir"
  mutate "$dir/$INTENT" 'm["notes"] = "free text"; m["updated_at"] = "2026-11-26"; m["screens"][0]["owner"] = "design"; m["screens"][0]["states"][0]["reviewed"] = True'
  check "T-unknown-fields" "$dir" 0 "line:MANIFEST_RESULT=conforms" "line:PROBLEM_COUNT=0" \
    -- manifest "$dir/$INTENT" --repo-root "$dir"
}

# ── AC6 binding enumeration ─────────────────────────────────────────────────

# ac6 <name> <python mutation of m> <expected problem start> [expected PROBLEM_COUNT]
ac6() {
  local name="$1" code="$2" prefix="$3" count="${4:-}" dir
  local -a specs=("line:MANIFEST_RESULT=does_not_conform" "line:MANIFEST_RESULT_LABEL=Does not conform"
    "prefix:PROBLEM=$prefix")
  [ -z "$count" ] || specs+=("line:PROBLEM_COUNT=$count")
  dir="$(new_case)"
  copy_fixture "$dir"
  mutate "$dir/$INTENT" "$code"
  check "$name" "$dir" 1 "${specs[@]}" -- manifest "$dir/$INTENT" --repo-root "$dir"
}

# ac6_files <name> <setup function> <expected problem start> [count]: the
# setup function receives the case directory and edits the page or tokens.
ac6_files() {
  local name="$1" setup="$2" prefix="$3" count="${4:-}" dir
  local -a specs=("line:MANIFEST_RESULT=does_not_conform" "prefix:PROBLEM=$prefix")
  [ -z "$count" ] || specs+=("line:PROBLEM_COUNT=$count")
  dir="$(new_case)"
  copy_fixture "$dir"
  "$setup" "$dir"
  check "$name" "$dir" 1 "${specs[@]}" -- manifest "$dir/${AC6_MANIFEST:-$INTENT}" --repo-root "$dir"
}

FORM_PREFIX="BR1 manifest: not readable as data: "

run_ac6_file_form_cases() {
  local dir value
  dir="$(new_case)"
  copy_fixture "$dir"
  check "T-ac6-missing-file" "$dir" 1 "line:MANIFEST_RESULT=does_not_conform" "line:PROBLEM_COUNT=1" \
    "line:PROBLEM=BR1 manifest: manifest file not found or unreadable: absent; expected a readable regular file" \
    -- manifest "$dir/design/mockups/missing-app/mockup-manifest.js" --repo-root "$dir"
  check "T-ac6-missing-file (a directory)" "$dir" 1 "line:PROBLEM_COUNT=1" \
    "prefix:PROBLEM=BR1 manifest: manifest file not found or unreadable: found a path that is not a readable regular file" \
    -- manifest "$dir/design/mockups/intent-app" --repo-root "$dir"
  check "T-ac6-function-wrapper" "$dir" 1 "line:PROBLEM_COUNT=1" "prefix:PROBLEM=$FORM_PREFIX" \
    "line:MANIFEST_KIND=" -- manifest "$dir/invalid-examples/function-wrapper.js" --repo-root "$dir"
  check "T-ac6-object-literal" "$dir" 1 "line:PROBLEM_COUNT=1" "prefix:PROBLEM=$FORM_PREFIX" \
    -- manifest "$dir/invalid-examples/object-literal.js" --repo-root "$dir"
  for value in '[]' '"x"' 'null'; do
    dir="$(new_case)"
    write_manifest "$dir/mockup-manifest.js" "$value"
    check "T-ac6-not-object ($value)" "$dir" 1 "line:PROBLEM_COUNT=1" \
      "prefix:PROBLEM=BR1 manifest: manifest is not an object: found " \
      -- manifest "$dir/mockup-manifest.js" --repo-root "$dir"
  done
}

run_ac6_field_cases() {
  ac6 "T-ac6-kind-missing" 'del m["$kind"]' 'BR2 manifest: $kind: absent; expected design-intent (Design intent), reproduction (Reproduction)' 1
  # The BR2 $kind problem is the only kind-related problem: mirroring is skipped.
  ac6 "T-ac6-kind-unknown" 'm["$kind"] = "design intent"' 'BR2 manifest: $kind: found "design intent"; expected design-intent (Design intent), reproduction (Reproduction)' 1
  ac6 "T-ac6-status-missing" 'del m["$status"]' 'BR2 manifest: $status: absent; expected complete (Complete), skeleton (Skeleton)' 1
  ac6 "T-ac6-status-unknown" 'm["$status"] = "done"' 'BR2 manifest: $status: found "done"; expected complete (Complete), skeleton (Skeleton)' 1
  ac6 "T-ac6-frame-unknown" 'm["frame"] = "tablet"' 'BR2 manifest: frame: found "tablet"; expected phone (Phone), desktop (Desktop), browser (Browser)' 1
  ac6 "T-ac6-default-screen-unknown" 'm["default_screen"] = "nowhere"' 'BR2 manifest: default_screen: found "nowhere", which is not a screen_id in screens; expected a screen_id that exists in screens (login-email, login-code, home, onboarding-illustration)' 1
  ac6 "T-ac6-screens-empty" 'm["screens"] = []' 'BR2 manifest: screens: found an empty list; expected a non-empty list of screens'

  ac6 "T-ac6-screen-id-duplicate" 'm["screens"].append(dict(m["screens"][2]))' 'BR3 screens[4]: screen_id: found "home", which duplicates screens[2]; expected a screen_id unique across screens' 1
  ac6 "T-ac6-screen-id-not-slug" 'm["screens"].append({"screen_id": "Login Frame 1", "kind": "html"})' 'BR6 screens[4]: screen_id: found "Login Frame 1"; expected a slug' 1
  ac6 "T-ac6-screen-kind-missing" 'del m["screens"][2]["kind"]' 'BR3 screen home: kind: absent; expected html (HTML), image (Image)' 1
  ac6 "T-ac6-screen-kind-unknown" 'm["screens"][2]["kind"] = "video"' 'BR3 screen home: kind: found "video"; expected html (HTML), image (Image)' 1
  ac6 "T-ac6-image-without-export" 'del m["screens"][3]["export"]' 'BR3 screen onboarding-illustration: export: absent; expected the path of the exported image, required when kind is image' 1
  ac6 "T-ac6-title-not-string" 'm["screens"][2]["title"] = 42' 'BR19 screen home: title: found a number (42); expected a non-empty string' 1
  ac6 "T-ac6-title-not-string (empty string)" 'm["screens"][2]["title"] = ""' 'BR19 screen home: title: found an empty string; expected a non-empty string' 1
  ac6 "T-ac6-states-empty" 'm["screens"][2]["states"] = []' 'BR3 screen home: states: found an empty list; expected a non-empty list of states, or omit states' 1
  ac6 "T-ac6-state-without-id" 'del m["screens"][0]["states"][1]["state_id"]' 'BR4 screen login-email states[1]: state_id: absent; expected a slug' 1
  ac6 "T-ac6-state-id-duplicate" 'm["screens"][0]["states"][2]["state_id"] = "filled"' 'BR4 screen login-email states[2]: state_id: found "filled", which duplicates states[1]; expected a state_id unique within its screen' 1
  ac6 "T-ac6-no-initial" 'del m["screens"][0]["states"][0]["initial"]' 'BR4 screen login-email: initial: absent (no state sets initial true); expected exactly one state of the screen with initial true' 1
  ac6 "T-ac6-two-initial" 'm["screens"][0]["states"][1]["initial"] = True' 'BR4 screen login-email: initial: found true on 2 states (empty, filled); expected exactly one state of the screen with initial true' 1
  ac6 "T-ac6-state-route" 'm["screens"][0]["states"][1]["route"] = "/login/filled"' 'BR5 screen login-email state filled: route: found "/login/filled"; expected absent, because a state never declares a screen-level field' 1
  ac6 "T-ac6-state-export" 'm["screens"][0]["states"][1]["export"] = "exports/filled.png"' 'BR5 screen login-email state filled: export: found "exports/filled.png"; expected absent' 1
  ac6 "T-ac6-state-nested-states" 'm["screens"][0]["states"][1]["states"] = [{"state_id": "inner", "initial": True}]' 'BR5 screen login-email state filled: states: found a list; expected absent' 1

  ac6 "T-ac6-navigation-not-list" 'm["navigation"] = {"label": "Main"}' 'BR7 manifest: navigation: found a mapping; expected a list of navigation groups' 1
  ac6 "T-ac6-group-without-label" 'del m["navigation"][1]["label"]' 'BR7 navigation[1]: label: absent; expected a non-empty string' 1
  ac6 "T-ac6-group-without-items" 'del m["navigation"][1]["items"]' 'BR7 navigation[1]: items: absent; expected a list of navigation entries (it may be empty)' 1
  ac6 "T-ac6-entry-without-screen-id" 'del m["navigation"][1]["items"][0]["screen_id"]' 'BR7 navigation[1].items[0]: screen_id: absent; expected a screen_id that exists in screens' 1
  ac6 "T-ac6-nested-unknown-screen" 'm["navigation"][0]["items"][0]["items"][0]["items"][0]["screen_id"] = "ghost"' 'BR7 navigation[0].items[0].items[0].items[0]: screen_id: found "ghost", which is not a screen_id in screens' 1
  ac6 "T-ac6-nav-screen-unknown" 'm["screens"][1]["nav_screen"] = "ghost"' 'BR3 screen login-code: nav_screen: found "ghost", which is not a screen_id in screens' 1
  ac6 "T-ac6-viewport-id-duplicate" 'm["viewports"][1]["id"] = "phone"' 'BR8 viewports[1]: id: found "phone", which duplicates viewports[0]; expected a viewport id unique across viewports' 1
  ac6 "T-ac6-viewport-width-not-positive" 'm["viewports"][0]["width"] = 0' 'BR8 viewport phone: width: found a number (0); expected a positive whole number' 1
  ac6 "T-ac6-viewport-width-not-positive (negative)" 'm["viewports"][0]["width"] = -390' 'BR8 viewport phone: width: found a number (-390); expected a positive whole number' 1
  ac6 "T-ac6-viewport-width-not-positive (not whole)" 'm["viewports"][0]["width"] = 390.5' 'BR8 viewport phone: width: found a number (390.5); expected a positive whole number' 1
}

PAGE="design/mockups/intent-app/index.html"
SHEET="design/mockups/intent-app/styles/tokens.css"
setup_token_missing() { edit_text "$1/$PAGE" $'      --space-sm: 8px;\n' ''; }
setup_token_different() { edit_text "$1/$PAGE" '--space-md: 16px;' '--space-md: 18px;'; }
setup_token_earlier() { edit_text "$1/$PAGE" '  <style>' $'  <style>:root { --color-text: #000000; }</style>\n  <style>'; }
setup_important_1() { edit_text "$1/$PAGE" '--space-sm: 8px;' '--space-sm: 8px !important;'; }
setup_important_2() { edit_text "$1/$PAGE" '--space-sm: 8px;' '--space-sm: 8px!IMPORTANT;'; }
setup_important_3() { edit_text "$1/$PAGE" '--space-sm: 8px;' '--space-sm: 8px ! important;'; }
setup_link_missing() { rm "$1/$SHEET"; }
setup_token_not_string() { edit_json "$1/design/tokens.json" 't["space"]["lg"] = 24'; }
setup_tokens_missing() { rm "$1/design/tokens.json"; }
setup_tokens_invalid() { printf '{ "color": ' >"$1/design/tokens.json"; }
setup_tokens_not_object() { printf '["#ffffff"]\n' >"$1/design/tokens.json"; }
setup_no_index() { rm "$1/$PAGE"; }
setup_not_in_mockups() {
  mkdir -p "$1/elsewhere/app"
  cp -R "$1/design/mockups/intent-app/." "$1/elsewhere/app/"
}
setup_page_unreadable() { chmod 000 "$1/$PAGE"; }
setup_tokens_fifo() { rm "$1/design/tokens.json" && mkfifo "$1/design/tokens.json"; }
setup_sheet_fifo() { rm "$1/$SHEET" && mkfifo "$1/$SHEET"; }

run_ac6_mirroring_cases() {
  ac6_files "T-ac6-token-missing" setup_token_missing \
    'BR10 token space.sm: --space-sm: absent from the :root rules; expected --space-sm: 8px' 1
  ac6_files "T-ac6-token-different" setup_token_different \
    'BR10 token space.md: --space-md in index.html <style> #1 line 12: found "18px"; expected "16px"' 1
  ac6_files "T-ac6-token-earlier-different" setup_token_earlier \
    'BR10 token color.text: --color-text in index.html <style> #1 line 7: found "#000000"; expected "#1f2328"' 1
  ac6_files "T-ac6-token-important (v !important)" setup_important_1 \
    'BR10 token space.sm: --space-sm in index.html <style> #1 line 11: found !important; expected a declaration without !important' 1
  ac6_files "T-ac6-token-important (v!IMPORTANT)" setup_important_2 \
    'BR10 token space.sm: --space-sm in index.html <style> #1 line 11: found !important' 1
  ac6_files "T-ac6-token-important (v ! important)" setup_important_3 \
    'BR10 token space.sm: --space-sm in index.html <style> #1 line 11: found !important' 1
  ac6_files "T-ac6-link-missing" setup_link_missing \
    "BR11 manifest: stylesheet $SHEET linked from index.html: absent; expected a readable UTF-8 stylesheet"
  ac6_files "T-ac6-token-not-string" setup_token_not_string \
    'BR10 token space.lg: value: found a number (24); expected a string, mirrored as --space-lg in :root' 1
  ac6_files "T-ac6-tokens-missing" setup_tokens_missing \
    'BR11 manifest: token file design/tokens.json: absent; expected a readable UTF-8 JSON object file' 1
  ac6_files "T-ac6-tokens-invalid-json" setup_tokens_invalid \
    'BR11 manifest: token file design/tokens.json: found text that is not valid JSON (' 1
  ac6_files "T-ac6-tokens-not-object" setup_tokens_not_object \
    'BR11 manifest: token file design/tokens.json: found a list; expected a JSON object' 1
  ac6_files "T-ac6-no-index-html" setup_no_index \
    "BR11 manifest: page $PAGE: absent; expected a readable UTF-8 index.html beside the manifest" 1
  AC6_MANIFEST="elsewhere/app/mockup-manifest.js" ac6_files "T-ac6-not-in-mockups" setup_not_in_mockups \
    'BR11 manifest: token file: absent, because the manifest is not inside a mockups folder' 1

  if [ "$IS_ROOT" = 1 ]; then
    skip "T-page-unreadable - running as root, where mode 000 does not deny reads"
  else
    ac6_files "T-page-unreadable" setup_page_unreadable \
      "BR11 manifest: page $PAGE: found a path that is not a readable regular file" 1
  fi
  ac6_files "T-mirroring-fifo (token file)" setup_tokens_fifo \
    'BR11 manifest: token file design/tokens.json: found a path that is not a readable regular file' 1
  ac6_files "T-mirroring-fifo (linked stylesheet)" setup_sheet_fifo \
    "BR11 manifest: stylesheet $SHEET linked from index.html: found a path that is not a readable regular file"
}

# ── Problems, safety and runtime (AC8, AC10, AC16) ──────────────────────────

run_safety_cases() {
  local dir line bad stub name found_marker shape_re
  dir="$(new_case)"
  copy_fixture "$dir"
  check "T-several-problems" "$dir" 1 "line:PROBLEM_COUNT=6" "prefix:PROBLEM=BR3 screen home: kind: found " \
    "prefix:PROBLEM=BR5 screen home state error-modal: route: found " \
    "prefix:PROBLEM=BR7 navigation[0].items[1]: screen_id: found " \
    "prefix:PROBLEM=BR6 screens[1]: screen_id: found " "prefix:PROBLEM=BR4 screen home: initial: found " \
    -- manifest "$dir/invalid-examples/several-problems.js" --repo-root "$dir"
  # Every problem line names a place, a rule, found or absent, and expected.
  bad=0
  shape_re='^PROBLEM=BR[0-9]+ [^:]+: [^;]*(found |absent).*; expected .+'
  while IFS= read -r line; do
    case "$line" in
      PROBLEM=*)
        [[ "$line" =~ $shape_re ]] || bad=1
        ;;
    esac
  done <<EOF
$OUT
EOF
  if [ "$bad" = 0 ]; then
    pass "T-several-problems (every line has rule, place, found/absent and expected)"
  else
    fail "T-several-problems (a problem line lacks rule, place, found/absent or expected)"
  fi

  # T-no-execution: stub JavaScript runtimes first on PATH; any call writes a marker.
  stub="$WORK_DIR/js-stubs"
  mkdir -p "$stub"
  for name in node deno bun; do
    printf '#!/bin/sh\n: >"%s/%s-ran"\n' "$WORK_DIR/markers" "$name" >"$stub/$name"
    chmod +x "$stub/$name"
  done
  dir="$(new_case)"
  cp "$FX/invalid-examples/executes-on-load.js" "$dir/mockup-manifest.js"
  CASE_CWD="$dir" CASE_PATH_PREFIX="$stub" check "T-no-execution" "$dir" 1 "line:PROBLEM_COUNT=1" \
    "prefix:PROBLEM=$FORM_PREFIX" -- manifest "$dir/mockup-manifest.js" --repo-root "$dir"
  found_marker="$(find "$WORK_DIR/markers" "$dir" -name '*-ran' -o -name 'executed-on-load.marker' 2>/dev/null | head -n 1 || true)"
  if [ -z "$found_marker" ] && [ ! -e "$WORK_DIR/run/executed-on-load.marker" ]; then
    pass "T-no-execution (no runtime called, no marker file created)"
  else
    fail "T-no-execution (found $found_marker)"
  fi
}

# ── Parser-risk addendum: manifest file form (P4) ───────────────────────────

# form <name> <expected exit> <spec> <printf format> [printf args...]
form() {
  local name="$1" want="$2" spec="$3" dir
  shift 3
  dir="$(new_case)"
  # shellcheck disable=SC2059 # the format is the test input
  printf "$@" >"$dir/mockup-manifest.js"
  if [ "$want" = 0 ]; then
    check "$name" "$dir" 0 "line:MANIFEST_RESULT=conforms" "line:PROBLEM_COUNT=0" ${spec:+"$spec"} \
      -- manifest "$dir/mockup-manifest.js" --repo-root "$dir"
  else
    check "$name" "$dir" 1 "line:PROBLEM_COUNT=1" "prefix:PROBLEM=$FORM_PREFIX" "stderr-clean" ${spec:+"$spec"} \
      -- manifest "$dir/mockup-manifest.js" --repo-root "$dir"
  fi
}

run_form_cases() {
  local dir j="$REPRO_JSON" a='window.__MOCKUP_MANIFEST__'
  form "T-form-comments" 0 "" '/* a */ // b\n%s = %s;\n// c\n' "$a" "$j"
  form "T-form-no-semicolon" 0 "" '%s = %s\n' "$a" "$j"
  form "T-form-double-semicolon" 1 "" '%s = %s;;\n' "$a" "$j"
  form "T-form-bom" 0 "" '\357\273\277%s = %s;\n' "$a" "$j"
  form "T-form-not-utf8" 1 "prefix:PROBLEM=${FORM_PREFIX}not UTF-8 text" '%s = {"a": "caf\351"};\n' "$a"
  form "T-form-unterminated-comment" 1 "contains:block comment is not closed" '/* never closed\n%s = %s;\n' "$a" "$j"
  form "T-form-name-comment" 1 "" 'window./*x*/__MOCKUP_MANIFEST__ = %s;\n' "$j"
  form "T-form-similar-names (missing underscores)" 1 "" 'window.__MOCKUP_MANIFEST = %s;\n' "$j"
  form "T-form-similar-names (globalThis)" 1 "" 'globalThis.__MOCKUP_MANIFEST__ = %s;\n' "$j"
  form "T-form-similar-names (bracket access)" 1 "" 'window["__MOCKUP_MANIFEST__"] = %s;\n' "$j"
  form "T-form-double-equals" 1 "" '%s == %s;\n' "$a" "$j"
  form "T-form-second-statement" 1 "" '%s = %s; console.log(1)\n' "$a" "$j"
  form "T-form-two-assignments" 1 "" '%s = %s;\n%s = %s;\n' "$a" "$j" "$a" "$j"
  form "T-form-comment-in-json" 1 "" '%s = {"a": 1 /* x */};\n' "$a"
  form "T-form-json5 (trailing comma)" 1 "" '%s = {"a": 1,};\n' "$a"
  form "T-form-json5 (single quotes)" 1 "" "%s = {'a': 1};\n" "$a"
  form "T-form-json5 (unquoted key)" 1 "" '%s = {a: 1};\n' "$a"
  form "T-form-nonfinite (NaN)" 1 "contains:non-finite number NaN" '%s = {"a": NaN};\n' "$a"
  form "T-form-nonfinite (Infinity)" 1 "contains:non-finite number Infinity" '%s = {"a": Infinity};\n' "$a"
  form "T-form-nonfinite (-Infinity)" 1 "contains:non-finite number -Infinity" '%s = {"a": -Infinity};\n' "$a"
  form "T-form-duplicate-key" 1 'contains:duplicate key "c" in a JSON object' '%s = {"a": {"b": {"c": 1, "c": 2}}};\n' "$a"
  form "T-form-markers-in-string" 0 "" '%s = %s;\n' "$a" "${j%\}}, \"\$note\": \"see // and /* here\"}"
  form "T-form-empty" 1 "" ''
  form "T-form-whitespace-only" 1 "" ' \n\t \n'
  dir="$(new_case)"
  python3 -I -B -c '
import sys
with open(sys.argv[1], "w") as handle:
    handle.write("window.__MOCKUP_MANIFEST__ = {\"a\":" + "[" * 100000)
' "$dir/mockup-manifest.js"
  check "T-form-deep-nesting" "$dir" 1 "line:PROBLEM_COUNT=1" "prefix:PROBLEM=$FORM_PREFIX" "stderr-clean" \
    -- manifest "$dir/mockup-manifest.js" --repo-root "$dir"
}

# ── Parser-risk addendum: CSS and HTML reading (P6) ─────────────────────────

# css_tree <dir> <tokens json> <index.html content>: a minimal Design intent tree.
css_tree() {
  mkdir -p "$1/design/mockups/app"
  printf '%s\n' "$2" >"$1/design/tokens.json"
  write_manifest "$1/design/mockups/app/mockup-manifest.js" "$MIN_INTENT"
  printf '%s\n' "$3" >"$1/design/mockups/app/index.html"
}

style_page() {
  printf '<!DOCTYPE html>\n<html>\n<head>\n<style>\n%s\n</style>\n</head>\n<body></body>\n</html>' "$1"
}

APP="design/mockups/app/mockup-manifest.js"

# css <name> <tokens json> <css> <expected exit> [spec...]
css() {
  local name="$1" tokens="$2" text="$3" want="$4" dir
  shift 4
  dir="$(new_case)"
  css_tree "$dir" "$tokens" "$(style_page "$text")"
  check "$name" "$dir" "$want" "stderr-clean" "$@" -- manifest "$dir/$APP" --repo-root "$dir"
}

ABSENT_A='prefix:PROBLEM=BR10 token a: --a: absent from the :root rules'

run_css_cases() {
  local a='{"a": "v"}' dir variant
  css "T-css-selector-list" "$a" ':root, .x { --a: v }' 0 "line:PROBLEM_COUNT=0"
  for variant in ':root.dark { --a: v }' 'html { --a: v }' ':is(:root) { --a: v }' 'html:root { --a: v }'; do
    css "T-css-not-plain-root ($variant)" "$a" "$variant" 1 "$ABSENT_A" "line:PROBLEM_COUNT=1"
  done
  css "T-css-root-case" "$a" ':ROOT { --a: v }' 0 "line:PROBLEM_COUNT=0"
  css "T-css-name-case" "$a" ':root { --A: v }' 1 "$ABSENT_A" "line:PROBLEM_COUNT=1"
  css "T-css-root-in-string" "$a" $'.x[data-a=":root"] { --a: v }\n/* :root { --a: v } */' 1 "$ABSENT_A" "line:PROBLEM_COUNT=1"
  css "T-css-media" "$a" $':root { --a: v }\n@media (min-width: 1px) { :root { --a: other } }' 1 \
    'prefix:PROBLEM=BR10 token a: --a in index.html <style> #1 line 6: found "other"; expected "v"' "line:PROBLEM_COUNT=1"
  dir="$(new_case)"
  css_tree "$dir" "$a" "$(style_page $'@import "x.css";\n@charset "utf-8";\n:root { --a: v }')"
  printf ':root { --a: bad }\n' >"$dir/design/mockups/app/x.css"
  check "T-css-import (x.css never read)" "$dir" 0 "line:PROBLEM_COUNT=0" -- manifest "$dir/$APP" --repo-root "$dir"
  css "T-css-nested-at-rule" "$a" ':root { --a: v; @media (x) { --a: other } }' 1 \
    'prefix:PROBLEM=BR10 token a: --a in index.html <style> #1 line 5: found "other"' "line:PROBLEM_COUNT=1"
  css "T-css-nested-rule" "$a" ':root { --a: v; .x & { --a: other } }' 0 "line:PROBLEM_COUNT=0"
  css "T-css-string-semicolon" '{"f": "\"a;b\""}' ':root { --f: "a;b"; }' 0 "line:PROBLEM_COUNT=0"
  css "T-css-value-comment" "$a" ':root { --a: v /* note */; }' 0 "line:PROBLEM_COUNT=0"
  css "T-css-important-in-string" '{"f": "\"x !important\""}' ':root { --f: "x !important"; }' 0 "line:PROBLEM_COUNT=0"
  css "T-css-trim" '{"a": "16px"}' ':root{--a:   16px  ;}' 0 "line:PROBLEM_COUNT=0"
  css "T-css-inner-whitespace" '{"a": "a b"}' ':root { --a: a  b; }' 1 \
    'prefix:PROBLEM=BR10 token a: --a in index.html <style> #1 line 5: found "a  b"; expected "a b"' "line:PROBLEM_COUNT=1"
  css "T-css-unterminated-string" "$a" $':root {\n  --b: "v\n  ; --a: v;\n}' 0 "line:PROBLEM_COUNT=0"
  css "T-css-unbalanced" "$a" ':root { --a: v' 0 "line:PROBLEM_COUNT=0"

  dir="$(new_case)"
  css_tree "$dir" "$a" $'<!DOCTYPE html>\n<html style="--a: v">\n<body></body>\n</html>'
  check "T-html-style-attr" "$dir" 0 "line:PROBLEM_COUNT=0" -- manifest "$dir/$APP" --repo-root "$dir"
  dir="$(new_case)"
  css_tree "$dir" "$a" $'<!DOCTYPE html>\n<html>\n<!-- <style>:root{--a:v}</style> -->\n</html>'
  check "T-html-commented-style" "$dir" 1 "$ABSENT_A" "line:PROBLEM_COUNT=1" -- manifest "$dir/$APP" --repo-root "$dir"

  dir="$(new_case)"
  css_tree "$dir" '{"a": "v", "b": "v", "c": "v"}' $'<html><head>\n<link rel="Stylesheet preload" href="a.css">\n<link rel="alternate stylesheet" href="b.css">\n<link rel="icon" href="c.css">\n</head></html>'
  printf ':root { --a: v }\n' >"$dir/design/mockups/app/a.css"
  printf ':root { --b: v }\n' >"$dir/design/mockups/app/b.css"
  printf ':root { --c: v }\n' >"$dir/design/mockups/app/c.css"
  check "T-html-rel" "$dir" 1 "line:PROBLEM_COUNT=1" 'prefix:PROBLEM=BR10 token c: --c: absent' \
    -- manifest "$dir/$APP" --repo-root "$dir"

  dir="$(new_case)"
  css_tree "$dir" "$a" $'<html><head>\n<link rel="stylesheet" href="https://x.example/y.css">\n<link rel="stylesheet" href="//x.example/y.css">\n<link rel="stylesheet" href="/y.css">\n<style>:root { --a: v }</style>\n</head></html>'
  check "T-css-link-absolute" "$dir" 0 "line:PROBLEM_COUNT=0" -- manifest "$dir/$APP" --repo-root "$dir"

  dir="$(new_case)"
  mkdir -p "$dir/repo"
  css_tree "$dir/repo" "$a" $'<html><head>\n<link rel="stylesheet" href="../../../../outside.css">\n<link rel="stylesheet" href="../../../../missing.css">\n<style>:root { --a: v }</style>\n</head></html>'
  printf ':root { --a: bad }\n' >"$dir/outside.css"
  check "T-css-link-outside" "$dir" 0 "line:PROBLEM_COUNT=0" -- manifest "$dir/repo/$APP" --repo-root "$dir/repo"

  dir="$(new_case)"
  css_tree "$dir" "$a" '<html><head><link rel="stylesheet" href="styles/tokens.css?v=2#x"></head></html>'
  mkdir -p "$dir/design/mockups/app/styles"
  printf ':root { --a: v }\n' >"$dir/design/mockups/app/styles/tokens.css"
  check "T-html-href-query" "$dir" 0 "line:PROBLEM_COUNT=0" -- manifest "$dir/$APP" --repo-root "$dir"

  dir="$(new_case)"
  css_tree "$dir" "$a" '<html><head><link rel="stylesheet" href="styles/my%20tokens.css"></head></html>'
  mkdir -p "$dir/design/mockups/app/styles"
  printf ':root { --a: v }\n' >"$dir/design/mockups/app/styles/my tokens.css"
  check "T-html-href-encoded (path with a space)" "$dir" 0 "line:PROBLEM_COUNT=0" -- manifest "$dir/$APP" --repo-root "$dir"

  # A root reached through a symlink: link and real path must agree (/var vs
  # /private/var on macOS; an explicit symlink everywhere else).
  dir="$(new_case)"
  css_tree "$dir" "$a" '<html><head><link rel="stylesheet" href="styles/tokens.css"></head></html>'
  mkdir -p "$dir/design/mockups/app/styles"
  printf ':root { --a: v }\n' >"$dir/design/mockups/app/styles/tokens.css"
  ln -s "$dir" "$WORK_DIR/root-link.$$"
  check "T-css-link-realpath (root through a symlink)" "$dir" 0 "line:PROBLEM_COUNT=0" \
    -- manifest "$dir/$APP" --repo-root "$WORK_DIR/root-link.$$"
  check "T-css-link-realpath (manifest through a symlink)" "$dir" 0 "line:PROBLEM_COUNT=0" \
    -- manifest "$WORK_DIR/root-link.$$/$APP" --repo-root "$dir"
}

# ── Tree (AC11, AC12) ───────────────────────────────────────────────────────

OPTED_IN=$'# fabricated test configuration\ndesign:\n  home: product\n  kind: design-intent\n'

# tree_repo <dir> <config>: a disposable Git repository with a versioned config.
tree_repo() {
  git init -q "$1"
  printf '%s' "$2" >"$1/.ai-dev-workflow.yaml"
}

tree_manifest_lines() {
  printf '%s\n' "MANIFEST_$1_PATH=$2" "MANIFEST_$1_RESULT=conforms" "MANIFEST_$1_PROBLEM_COUNT=0"
}

run_tree_cases() {
  local dir all_conform cfg stub
  dir="$(new_case)"
  tree_repo "$dir" $'# fabricated test configuration\nissue_tracker:\n  provider: none\n'
  cp -R "$FX/design" "$dir/design"
  check "T-tree-not-opted-in" "$dir" 0 "exact:$(printf '%s\n' 'TREE_RESULT=not_opted_in' 'TREE_RESULT_LABEL=Not opted in')" \
    -- tree --repo-root "$dir"

  dir="$(new_case)"
  tree_repo "$dir" $'design:\n  home: x\n'
  cp -R "$FX/design" "$dir/design"
  check "T-tree-invalid" "$dir" 1 "line:TREE_RESULT=invalid_configuration" \
    "line:TREE_RESULT_LABEL=Invalid configuration" "line:DESIGN_PROBLEM_COUNT=2" \
    "prefix:DESIGN_PROBLEM=design.home: found \"x\"" "prefix:DESIGN_PROBLEM=design.kind: absent" \
    "noprefix:MANIFEST_COUNT=" -- tree --repo-root "$dir"

  dir="$(new_case)"
  tree_repo "$dir" "$OPTED_IN"
  check "T-tree-no-mockups (mockups folder missing)" "$dir" 0 \
    "exact:$(printf '%s\n' 'TREE_RESULT=no_mockups_found' 'TREE_RESULT_LABEL=No mockups found' \
      'DESIGN_ROOT=design/' 'MOCKUPS_FOLDER=design/mockups' 'UNREADABLE_FOLDER_COUNT=0' 'MANIFEST_COUNT=0')" \
    -- tree --repo-root "$dir"
  mkdir -p "$dir/design/mockups/shared"
  cp "$FX/design/mockups/shared/mockup-manifest.js" "$dir/design/mockups/shared/"
  check "T-tree-no-mockups (scaffold only, shared ignored)" "$dir" 0 "line:TREE_RESULT=no_mockups_found" \
    "line:MANIFEST_COUNT=0" -- tree --repo-root "$dir"

  dir="$(new_case)"
  tree_repo "$dir" "$OPTED_IN"
  cp -R "$FX/design" "$dir/design"
  all_conform="$(printf '%s\n' 'TREE_RESULT=conforms' 'TREE_RESULT_LABEL=Conforms' 'DESIGN_ROOT=design/' \
    'MOCKUPS_FOLDER=design/mockups' 'UNREADABLE_FOLDER_COUNT=0' 'MANIFEST_COUNT=2'
  tree_manifest_lines 1 "$INTENT"
  tree_manifest_lines 2 "$REPRO")"
  check "T-tree-all-conform" "$dir" 0 "exact:$all_conform" "nocontains:mockups/shared" -- tree --repo-root "$dir"
  CASE_CWD="$dir/design/mockups" check "T-tree-all-conform (default root: git toplevel)" "$dir" 0 \
    "exact:$all_conform" -- tree

  mkdir -p "$dir/design/mockups/broken-app"
  cp "$FX/invalid-examples/several-problems.js" "$dir/design/mockups/broken-app/mockup-manifest.js"
  check "T-tree-one-fails" "$dir" 1 "line:TREE_RESULT=does_not_conform" "line:MANIFEST_COUNT=3" \
    "line:MANIFEST_1_PATH=design/mockups/broken-app/mockup-manifest.js" "line:MANIFEST_1_RESULT=does_not_conform" \
    "line:MANIFEST_1_PROBLEM_COUNT=6" "line:MANIFEST_2_RESULT=conforms" "line:MANIFEST_3_RESULT=conforms" \
    "noprefix:MANIFEST_2_PROBLEM=" "noprefix:MANIFEST_3_PROBLEM=" "line:UNREADABLE_FOLDER_COUNT=0" \
    -- tree --repo-root "$dir"

  dir="$(new_case)"
  tree_repo "$dir" "$OPTED_IN"
  cp -R "$FX/design" "$dir/design"
  if [ "$IS_ROOT" = 1 ]; then
    skip "T-tree-unreadable - running as root, where mode 000 does not deny reads"
  else
    mkdir -p "$dir/design/mockups/locked"
    chmod 000 "$dir/design/mockups/locked"
    check "T-tree-unreadable" "$dir" 1 "line:TREE_RESULT=does_not_conform" "line:UNREADABLE_FOLDER_COUNT=1" \
      "line:UNREADABLE_FOLDER=design/mockups/locked" "line:MANIFEST_COUNT=2" \
      "line:MANIFEST_1_PATH=$INTENT" "line:MANIFEST_1_RESULT=conforms" \
      "line:MANIFEST_2_PATH=$REPRO" "line:MANIFEST_2_RESULT=conforms" -- tree --repo-root "$dir"
    chmod 755 "$dir/design/mockups/locked"
    rmdir "$dir/design/mockups/locked"
  fi

  ln -s intent-app "$dir/design/mockups/alias-app"
  check "T-tree-symlinked-folder" "$dir" 1 "line:TREE_RESULT=does_not_conform" \
    "line:UNREADABLE_FOLDER=design/mockups/alias-app" "line:MANIFEST_COUNT=2" -- tree --repo-root "$dir"
  rm "$dir/design/mockups/alias-app"

  mkdir -p "$dir/design/mockups/ghost-app"
  ln -s does-not-exist.js "$dir/design/mockups/ghost-app/mockup-manifest.js"
  check "T-tree-dangling-manifest" "$dir" 1 "line:TREE_RESULT=does_not_conform" "line:MANIFEST_COUNT=3" \
    "line:MANIFEST_1_PATH=design/mockups/ghost-app/mockup-manifest.js" "line:MANIFEST_1_RESULT=does_not_conform" \
    "prefix:MANIFEST_1_PROBLEM=BR1 manifest: manifest file not found or unreadable" -- tree --repo-root "$dir"
  rm -r "$dir/design/mockups/ghost-app"

  mkdir -p "$dir/design/mockups/fifo-app"
  mkfifo "$dir/design/mockups/fifo-app/mockup-manifest.js"
  check "T-tree-fifo-manifest" "$dir" 1 "line:TREE_RESULT=does_not_conform" "line:MANIFEST_COUNT=3" \
    "line:MANIFEST_1_PATH=design/mockups/fifo-app/mockup-manifest.js" "line:MANIFEST_1_RESULT=does_not_conform" \
    "line:MANIFEST_2_RESULT=conforms" "line:MANIFEST_3_RESULT=conforms" -- tree --repo-root "$dir"

  dir="$(new_case)"
  tree_repo "$dir" $'design:\n  root: ui/\n  home: knowledge\n  kind: design-intent\n'
  cp -R "$FX/design" "$dir/ui"
  check "T-tree-custom-root" "$dir" 0 "line:TREE_RESULT=conforms" "line:DESIGN_ROOT=ui/" \
    "line:MOCKUPS_FOLDER=ui/mockups" "line:MANIFEST_COUNT=2" "line:MANIFEST_1_PATH=ui/mockups/intent-app/mockup-manifest.js" \
    -- tree --repo-root "$dir"

  dir="$(new_case)"
  tree_repo "$dir" "$OPTED_IN"
  mkdir -p "$dir/design/mockups/shared"
  cp "$FX/design/tokens.json" "$dir/design/"
  cp -R "$FX/design/mockups/intent-app/." "$dir/design/mockups/"
  cp "$FX/design/mockups/shared/mockup-manifest.js" "$dir/design/mockups/shared/"
  check "T-tree-single-app" "$dir" 0 "line:TREE_RESULT=conforms" "line:MANIFEST_COUNT=1" \
    "line:MANIFEST_1_PATH=design/mockups/mockup-manifest.js" "line:MANIFEST_1_RESULT=conforms" \
    -- tree --repo-root "$dir"
  edit_text "$dir/design/tokens.json" '"8px"' '"9px"'
  check "T-tree-single-app (mirroring reads design/tokens.json)" "$dir" 1 "line:TREE_RESULT=does_not_conform" \
    'prefix:MANIFEST_1_PROBLEM=BR10 token space.sm: --space-sm in index.html <style> #1 line 11: found "8px"; expected "9px"' \
    -- tree --repo-root "$dir"

  # T-tree-opt-in-failed: the module refuses input without a DESIGN_OPT_IN= first line.
  dir="$(new_case)"
  for cfg in "${!CFG_SHELL[@]}"; do
    local input
    for input in 'garbage' ''; do
      OUT="$(printf '%s' "$input" | PATH="${CFG_PATH[$cfg]:+${CFG_PATH[$cfg]}:}$PATH" \
        python3 -I -B "$MODULE" tree --repo-root "$dir" 2>/dev/null)" && RC=0 || RC=$?
      if [ "$RC" = 2 ] && [ -z "$OUT" ]; then
        pass "T-tree-opt-in-failed (input '${input}') [${CFG_LABEL[$cfg]}]"
      else
        fail "T-tree-opt-in-failed (input '${input}') [${CFG_LABEL[$cfg]}]: rc=$RC out=$OUT"
      fi
    done
  done

  # T-tree-opt-in-helper-fails: a helper that prints a valid block, then fails.
  stub="$WORK_DIR/helper-fails"
  mkdir -p "$stub"
  cp "$TOOL" "$MODULE" "$stub/"
  cat >"$stub/workflow-lib.sh" <<'EOF'
workflow_design_opt_in() {
  printf '%s\n' 'DESIGN_OPT_IN=opted_in' 'DESIGN_OPT_IN_LABEL=Opted in' 'DESIGN_ROOT=design/' \
    'DESIGN_ROOT_SOURCE=default' 'DESIGN_HOME=product' 'DESIGN_HOME_LABEL=Product repository' \
    'DESIGN_KIND=design-intent' 'DESIGN_KIND_LABEL=Design intent'
  return 1
}
EOF
  dir="$(new_case)"
  tree_repo "$dir" "$OPTED_IN"
  cp -R "$FX/design" "$dir/design"
  CASE_TOOL="$stub/mockup-manifest-verify.sh" check "T-tree-opt-in-helper-fails" "$dir" 2 "empty" \
    -- tree --repo-root "$dir"
}

run_template_case() {
  if [ "$(bash -c 'source "$1/workflow-lib.sh" && workflow_template_is_template "$2"' _ "$SCRIPTS_DIR" "$REPO_ROOT/.ai-dev-workflow.yaml")" != "true" ]; then
    skip "T-template - not the template repository"
    return 0
  fi
  CASE_CWD="$REPO_ROOT" check "T-template (this repository is not opted in)" "$REPO_ROOT" 0 \
    "exact:$(printf '%s\n' 'TREE_RESULT=not_opted_in' 'TREE_RESULT_LABEL=Not opted in')" -- tree
}

# ── Inventory and citations (AC13, AC14) and usage ──────────────────────────

run_inventory_cases() {
  local dir expected
  dir="$(new_case)"
  copy_fixture "$dir"
  expected="$(printf '%s\n' 'INVENTORY_RESULT=listed' 'INVENTORY_RESULT_LABEL=Listed' 'SCREEN_COUNT=4' \
    'SCREEN_1_ID=login-email' 'SCREEN_1_LINK=#screen=login-email' 'SCREEN_1_STATE_COUNT=3' \
    'SCREEN_1_STATE_1_ID=empty' 'SCREEN_1_STATE_1_INITIAL=true' 'SCREEN_1_STATE_1_LINK=#screen=login-email&state=empty' \
    'SCREEN_1_STATE_2_ID=filled' 'SCREEN_1_STATE_2_INITIAL=false' 'SCREEN_1_STATE_2_LINK=#screen=login-email&state=filled' \
    'SCREEN_1_STATE_3_ID=invalid' 'SCREEN_1_STATE_3_INITIAL=false' 'SCREEN_1_STATE_3_LINK=#screen=login-email&state=invalid' \
    'SCREEN_2_ID=login-code' 'SCREEN_2_LINK=#screen=login-code' 'SCREEN_2_STATE_COUNT=2' \
    'SCREEN_2_STATE_1_ID=empty' 'SCREEN_2_STATE_1_INITIAL=true' 'SCREEN_2_STATE_1_LINK=#screen=login-code&state=empty' \
    'SCREEN_2_STATE_2_ID=resend-ready' 'SCREEN_2_STATE_2_INITIAL=false' 'SCREEN_2_STATE_2_LINK=#screen=login-code&state=resend-ready' \
    'SCREEN_3_ID=home' 'SCREEN_3_LINK=#screen=home' 'SCREEN_3_STATE_COUNT=0' \
    'SCREEN_4_ID=onboarding-illustration' 'SCREEN_4_LINK=#screen=onboarding-illustration' 'SCREEN_4_STATE_COUNT=0')"
  check "T-inventory" "$dir" 0 "exact:$expected" -- inventory "$dir/$INTENT" --repo-root "$dir"
  check "T-inventory-cannot-check" "$dir" 1 "line:INVENTORY_RESULT=cannot_check" \
    "line:INVENTORY_RESULT_LABEL=Cannot check" "line:MANIFEST_RESULT=does_not_conform" "line:PROBLEM_COUNT=6" \
    "nocontains:SCREEN_" -- inventory "$dir/invalid-examples/several-problems.js" --repo-root "$dir"

  check "T-resolve-screen" "$dir" 0 "exact:$(printf '%s\n' 'CITATION_RESULT=resolves' 'CITATION_RESULT_LABEL=Resolves' \
    'CITATION_REASON=none' 'CITATION_LINK=#screen=home')" -- resolve "$dir/$INTENT" --screen home --repo-root "$dir"
  check "T-resolve-state" "$dir" 0 "exact:$(printf '%s\n' 'CITATION_RESULT=resolves' 'CITATION_RESULT_LABEL=Resolves' \
    'CITATION_REASON=none' 'CITATION_LINK=#screen=login-email&state=invalid')" \
    -- resolve "$dir/$INTENT" --screen login-email --state invalid --repo-root "$dir"
  check "T-resolve-unknown-screen" "$dir" 1 "exact:$(printf '%s\n' 'CITATION_RESULT=does_not_resolve' \
    'CITATION_RESULT_LABEL=Does not resolve' 'CITATION_REASON=unknown_screen')" \
    -- resolve "$dir/$INTENT" --screen ghost --repo-root "$dir"
  check "T-resolve-other-screens-state" "$dir" 1 "exact:$(printf '%s\n' 'CITATION_RESULT=does_not_resolve' \
    'CITATION_RESULT_LABEL=Does not resolve' 'CITATION_REASON=unknown_state')" \
    -- resolve "$dir/$INTENT" --screen login-code --state invalid --repo-root "$dir"
  check "T-resolve-other-screens-state (screen without states)" "$dir" 1 "line:CITATION_REASON=unknown_state" \
    -- resolve "$dir/$INTENT" --screen home --state empty --repo-root "$dir"
  check "T-resolve-cannot-check" "$dir" 1 "line:CITATION_RESULT=cannot_check" "line:CITATION_RESULT_LABEL=Cannot check" \
    "line:CITATION_REASON=manifest_does_not_conform" "line:MANIFEST_RESULT=does_not_conform" "noprefix:CITATION_LINK=" \
    -- resolve "$dir/invalid-examples/several-problems.js" --screen home --repo-root "$dir"
  check "T-resolve-cannot-check (missing manifest)" "$dir" 1 "line:CITATION_RESULT=cannot_check" \
    "prefix:PROBLEM=BR1 manifest: manifest file not found or unreadable: absent" \
    -- resolve "$dir/design/mockups/none/mockup-manifest.js" --screen home --repo-root "$dir"
}

run_usage_cases() {
  local dir m empty_path
  dir="$(new_case)"
  copy_fixture "$dir"
  m="$dir/$INTENT"
  check "T-usage (no subcommand)" "$dir" 2 "empty" --
  check "T-usage (unknown subcommand)" "$dir" 2 "empty" -- frobnicate "$m"
  check "T-usage (manifest without a path)" "$dir" 2 "empty" -- manifest
  check "T-usage (two manifest paths)" "$dir" 2 "empty" -- manifest "$m" "$m"
  check "T-usage (unknown option)" "$dir" 2 "empty" -- manifest "$m" --bogus x
  check "T-usage (resolve without --screen)" "$dir" 2 "empty" -- resolve "$m"
  check "T-usage (empty --screen)" "$dir" 2 "empty" -- resolve "$m" --screen ""
  check "T-usage (empty --state)" "$dir" 2 "empty" -- resolve "$m" --screen home --state ""
  check "T-usage (--repo-root without a value)" "$dir" 2 "empty" -- manifest "$m" --repo-root
  check "T-usage (--repo-root not a directory)" "$dir" 2 "empty" -- manifest "$m" --repo-root "$dir/no-such-dir"
  check "T-usage (tree with another argument)" "$dir" 2 "empty" -- tree --screen home
  if git -C "$dir" rev-parse --show-toplevel >/dev/null 2>&1; then
    skip "T-usage (tree outside Git) - the temporary directory is inside a Git repository"
  else
    CASE_CWD="$dir" check "T-usage (tree outside Git without --repo-root)" "$dir" 2 "empty" -- tree
  fi
  empty_path="$WORK_DIR/empty-path"
  mkdir -p "$empty_path"
  CASE_PATH="$empty_path" check "T-usage (python3 missing)" "$dir" 2 "empty" -- manifest "$m"
}

for cfg_index in "${!CFG_SHELL[@]}"; do
  printf '== configuration %d: %s\n' "$((cfg_index + 1))" "${CFG_LABEL[$cfg_index]}"
done

run_valid_cases
run_ac6_file_form_cases
run_ac6_field_cases
run_ac6_mirroring_cases
run_safety_cases
run_form_cases
run_css_cases
run_tree_cases
run_template_case
run_inventory_cases
run_usage_cases

printf '\nResults: %d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ]

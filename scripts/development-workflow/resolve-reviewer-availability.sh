#!/usr/bin/env bash
# Read-only Step 7a capability determination. Never dispatches a review.
# Output values use print_kv_escaped; aggregate reviewer lists are display-only.
SECONDS=0
AVAILABILITY_BUDGET_SECONDS=8
CONFIG_RESOLVE_CAP_SECONDS=2
LOCAL_PROBE_CAP_SECONDS=3
HOSTED_PROBE_CAP_SECONDS=4
set -euo pipefail

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }
if [ "${WORKFLOW_REVIEWER_AVAILABILITY_TEST_MODE:-0}" = 1 ]; then
  case "${WORKFLOW_REVIEWER_AVAILABILITY_BUDGET_SECONDS:-8}" in
    [1-8]) AVAILABILITY_BUDGET_SECONDS=${WORKFLOW_REVIEWER_AVAILABILITY_BUDGET_SECONDS:-8} ;;
    *) fail 'test budget must be an integer from 1 through 8' ;;
  esac
fi
DEADLINE=$AVAILABILITY_BUDGET_SECONDS
repo_root= owner= repo= runner_kind=${WORKFLOW_RUNNER_KIND:-unknown}
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo-root|--owner|--repo|--runner-kind)
      [ "$#" -ge 2 ] && [ -n "$2" ] || fail "missing value for $1"
      case "$1" in
        --repo-root) repo_root=$2 ;; --owner) owner=$2 ;;
        --repo) repo=$2 ;; --runner-kind) runner_kind=$2 ;;
      esac
      shift 2 ;;
    --help) printf 'Usage: %s --repo-root <path> --owner <owner> --repo <repo> [--runner-kind claude|cursor|codex|unknown]\n' "$0"; exit 0 ;;
    *) fail "unknown argument: $1" ;;
  esac
done
[ -n "$repo_root" ] && [ -n "$owner" ] && [ -n "$repo" ] || fail 'repo-root, owner and repo are required'
[ -d "$repo_root" ] && [ -r "$repo_root" ] && [ -x "$repo_root" ] || fail 'repo-root must be a readable directory'
case "$owner/$repo" in *[!a-zA-Z0-9_./-]*) fail 'invalid owner or repo' ;; esac
case "$owner" in */*|.|..) fail 'invalid owner' ;; esac
case "$repo" in */*|.|..) fail 'invalid repo' ;; esac
case "$runner_kind" in claude|cursor|codex|unknown) ;; *) fail 'unsupported runner-kind' ;; esac
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"
for dependency in python3 jq mktemp rm sleep cat; do
  have_cmd "$dependency" || fail "missing dependency: $dependency"
done
launch_kind=
if have_cmd setsid; then launch_kind=setsid
elif have_cmd perl; then launch_kind=perl
elif have_cmd timeout; then launch_kind=timeout
else fail 'bounded launch requires timeout, setsid, or perl'
fi
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/reviewer-availability.XXXXXX") || fail 'cannot create temporary directory'
active_pid=
cleanup() {
  local rc=$?
  if [ -n "$active_pid" ]; then
    kill -KILL -- "-$active_pid" 2>/dev/null || true
    kill -KILL "$active_pid" 2>/dev/null || true
    wait "$active_pid" 2>/dev/null || true
  fi
  if [ -n "$work_dir" ]; then rm -rf -- "$work_dir"; fi
  return "$rc"
}
trap cleanup EXIT
trap 'exit 2' INT TERM

# Linux PID 1 may not reap adopted children (notably in containers). Keep a
# subreaper outside the probe's own process group so killing that group cannot
# kill the process responsible for waiting for its descendants. The existing
# launcher remains an outer watchdog, including for a hung Python executable.
linux_probe_supervisor=$(cat <<'PY_SUPERVISOR'
# Step 7a Linux probe supervisor
import ctypes, os, pathlib, signal, subprocess, sys, time
libc = ctypes.CDLL(None, use_errno=True)
if libc.prctl(36, 1, 0, 0, 0) != 0:  # PR_SET_CHILD_SUBREAPER
    raise OSError(ctypes.get_errno(), "cannot enable probe child subreaper")
children_path = pathlib.Path(f"/proc/self/task/{os.getpid()}/children")
force_status_scan = (os.environ.get("WORKFLOW_REVIEWER_AVAILABILITY_TEST_MODE") == "1"
                     and os.environ.get("WORKFLOW_REVIEWER_AVAILABILITY_TEST_NO_PROC_CHILDREN") == "1")
def adopted_children():
    if not force_status_scan:
        try:
            return list(map(int, children_path.read_text().split()))
        except (FileNotFoundError, PermissionError):
            pass
    # Some kernels/sandboxes omit task/<pid>/children. PPid in process status
    # exposes the same adoption relationship without that optional entry.
    pathlib.Path("/proc/self/status").read_text()
    children = []
    for status_path in pathlib.Path("/proc").glob("[0-9]*/status"):
        try:
            lines = status_path.read_text().splitlines()
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            continue
        if any(line.startswith("PPid:") and int(line.split()[1]) == os.getpid() for line in lines):
            children.append(int(status_path.parent.name))
    return children
adopted_children()  # Check child discovery before launching a probe.
interrupted = False
def interrupt(_signum, _frame):
    global interrupted
    interrupted = True
signal.signal(signal.SIGTERM, interrupt)
signal.signal(signal.SIGINT, interrupt)
deadline = time.monotonic() + max(0.05, float(sys.argv[1]) - 0.5)
child = subprocess.Popen(sys.argv[2:], start_new_session=True)
timed_out = False
try:
    while child.poll() is None:
        if interrupted or time.monotonic() >= deadline:
            timed_out = True
            break
        time.sleep(0.01)
finally:
    # Always clean up: a successfully exited leader may leave children behind.
    try:
        os.killpg(child.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    child.wait()
    while True:
        # A descendant can escape killpg by starting a new session. The
        # subreaper adopts it; only signal our own still-unreaped children.
        for pid in adopted_children():
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        try:
            reaped, _status = os.waitpid(-1, os.WNOHANG)
        except InterruptedError:
            continue
        except ChildProcessError:
            break
        if reaped == 0:
            time.sleep(0.01)
raise SystemExit(124 if timed_out or interrupted else (child.returncode if child.returncode >= 0 else 128 - child.returncode))
PY_SUPERVISOR
)

# Each child writes to files, never a pipe held open by a surviving descendant.
# Timeout fallback owns a fresh process group, including on macOS without setsid.
run_bounded() {
  local bound=$1 output=$2 error=$3 finish rc=0
  shift 3
  [ "$bound" -gt 0 ] || return 124
  if [[ "$OSTYPE" == linux* ]]; then
    set -- python3 -B -c "$linux_probe_supervisor" "$bound" "$@"
  fi
  if [ "$launch_kind" = timeout ]; then
    # GNU timeout owns a group but can exit when its monitored leader exits
    # on TERM, before --kill-after reaches a TERM-ignoring descendant.
    timeout --kill-after=1 "$bound" "$@" >"$output" 2>"$error" &
    active_pid=$!
    wait "$active_pid" || rc=$?
    kill -KILL -- "-$active_pid" 2>/dev/null || true
    active_pid=
    case "$rc" in 124|137) return 124 ;; *) return "$rc" ;; esac
  fi
  finish=$((SECONDS + bound))
  if [ "$launch_kind" = setsid ]; then
    setsid "$@" >"$output" 2>"$error" &
  else
    perl -e 'setpgrp(0,0) or die "setpgrp: $!"; exec @ARGV; die "exec: $!"' -- "$@" >"$output" 2>"$error" &
  fi
  active_pid=$!
  while kill -0 "$active_pid" 2>/dev/null; do
    if [ "$SECONDS" -ge "$finish" ]; then
      kill -TERM -- "-$active_pid" 2>/dev/null || true
      sleep 1
      # Unconditional: the group can outlive its leader after TERM.
      kill -KILL -- "-$active_pid" 2>/dev/null || true
      wait "$active_pid" 2>/dev/null || true
      active_pid=
      return 124
    fi
    sleep 0.05
  done
  wait "$active_pid" || rc=$?
  kill -KILL -- "-$active_pid" 2>/dev/null || true
  active_pid=
  return "$rc"
}
clamp_bound() {
  bound=$((DEADLINE - SECONDS))
  [ "$bound" -le "$1" ] || bound=$1
}

# A binary named timeout is not necessarily GNU timeout (e.g. BusyBox).
# Identify it under a bound; prefer an owned-group fallback for this check.
# A host with only timeout must successfully prove its GNU self-bounding path.
if have_cmd timeout; then
  clamp_bound 1
  timeout_check=0
  run_bounded "$bound" "$work_dir/timeout-version" "$work_dir/timeout-error" timeout --version || timeout_check=$?
  if [ "$timeout_check" = 0 ] && [[ "$(cat "$work_dir/timeout-version")" == *'GNU coreutils'* ]]; then
    launch_kind=timeout
  elif [ "$launch_kind" = timeout ]; then
    fail 'GNU timeout, setsid, or perl is required for bounded launch'
  fi
fi

policy= policy_input= policy_source= policy_state=not-evaluated
unreadable_file= unreadable_detail= list_state=not-evaluated list_source=
local_state=none configured= excluded= reachable= unreachable=
fallback=false outcome=blocked block_cause=none count=0 reachable_count=0 unavailable_count=0
names=() statuses=() reasons=() remedies=() details=()
add_record() {
  names[$count]=$1 statuses[$count]=$2 reasons[$count]=$3 details[$count]=$4
  case "$3" in
    runtime-absent) remedies[$count]="Install the reviewer's runtime on this machine, or remove the reviewer from review.on_draft.runner in .ai-dev-workflow.local.yaml." ;;
    prerequisite-missing) remedies[$count]='Install or enable the review service for this repository, or remove the reviewer from review.on_draft.runner in .ai-dev-workflow.local.yaml.' ;;
    check-inconclusive) remedies[$count]='Repair .coderabbit.yaml using the reported detail if it has a read or syntax error. Otherwise, re-run the gate. If it recurs, run the named command by hand and confirm gh is authenticated for this repository.' ;;
    value-not-supported) remedies[$count]='Correct the configured value to one of the supported reviewer values, or remove it from review.on_draft.runner.' ;;
    '') remedies[$count]= ;;
    *) fail 'invalid internal reason' ;;
  esac
  count=$((count + 1))
  local display=$1
  if ! [[ "$display" =~ ^[a-z][a-z0-9-]*$ ]]; then display="<entry $count>"; fi
  case "$2" in
    reachable) reachable="${reachable:+$reachable,}$display"; reachable_count=$((reachable_count + 1)) ;;
    unreachable) unreachable="${unreachable:+$unreachable,}$display"; unavailable_count=$((unavailable_count + 1)) ;;
    override-excluded) excluded="${excluded:+$excluded,}$display" ;;
  esac
  if [ "$2" != override-excluded ]; then configured="${configured:+$configured,}$display"; fi
}
report() {
  local i=0 n
  # Include temporary-file cleanup in the reported determination duration.
  rm -rf -- "$work_dir"
  work_dir=
  print_kv_escaped REVIEWER_COUNT "$count"
  while [ "$i" -lt "$count" ]; do
    n=$((i + 1))
    print_kv_escaped "REVIEWER_${n}_NAME" "${names[$i]}"
    print_kv_escaped "REVIEWER_${n}_STATUS" "${statuses[$i]}"
    print_kv_escaped "REVIEWER_${n}_REASON" "${reasons[$i]}"
    print_kv_escaped "REVIEWER_${n}_REMEDY" "${remedies[$i]}"
    print_kv_escaped "REVIEWER_${n}_DETAIL" "${details[$i]}"
    i=$((i + 1))
  done
  print_kv_escaped RUNNER_KIND "$runner_kind"
  print_kv_escaped BUDGET_SECONDS "$AVAILABILITY_BUDGET_SECONDS"
  print_kv_escaped POLICY "$policy"
  print_kv_escaped POLICY_INPUT "$policy_input"
  print_kv_escaped POLICY_SOURCE "$policy_source"
  print_kv_escaped POLICY_STATE "$policy_state"
  print_kv_escaped UNREADABLE_FILE "$unreadable_file"
  print_kv_escaped UNREADABLE_DETAIL "$unreadable_detail"
  print_kv_escaped CONFIG_LIST_STATE "$list_state"
  print_kv_escaped CONFIG_LIST_SOURCE "$list_source"
  print_kv_escaped LOCAL_OVERRIDE_STATE "$local_state"
  print_kv_escaped CONFIGURED "$configured"
  print_kv_escaped OVERRIDE_EXCLUDED "$excluded"
  print_kv_escaped REACHABLE "$reachable"
  print_kv_escaped UNREACHABLE "$unreachable"
  print_kv_escaped FALLBACK_APPLIED "$fallback"
  print_kv_escaped OUTCOME "$outcome"
  print_kv_escaped BLOCK_CAUSE "$block_cause"
  print_kv_escaped ELAPSED_SECONDS "$SECONDS.0"
}
block() { block_cause=$1; report; exit 1; }
clamp_bound "$CONFIG_RESOLVE_CAP_SECONDS"
config_rc=0
run_bounded "$bound" "$work_dir/config.json" "$work_dir/config.err" \
  python3 "$SCRIPT_DIR/workflow-config-resolver.py" review-effective --repo-root "$repo_root" || config_rc=$?
if [ "$config_rc" = 124 ]; then block config-resolution-inconclusive; fi
if [ "$config_rc" != 0 ]; then cat "$work_dir/config.err" >&2; fail "review-effective failed (exit $config_rc)"; fi
# Validate before reading: malformed helper output is execution failure, not configuration data.
jq -e 'type == "object" and
  ([.effective_runner,.override_excluded,.shipped_runner] | all(.[]; type == "array" and all(.[]; type == "string" and (contains("\u0000")|not)))) and
  ([.effective_runner_state,.effective_runner_source,.effective_policy,.effective_policy_state,.effective_policy_source,.unreadable_file,.unreadable_detail,.local_override_file,.local_override_origin,.main_clone_local_override_file] | all(.[]; type == "string")) and
  (.local_review_override_applied | type == "boolean")' \
  "$work_dir/config.json" >/dev/null || fail 'invalid review-effective JSON contract'
jq -j '[.effective_policy_state,.effective_policy_source,
  (if .policy_input == null then "" elif (.policy_input|type)=="string" then .policy_input else (.policy_input|tojson) end),
  .unreadable_file,.unreadable_detail,.local_override_file,.local_override_origin,.main_clone_local_override_file,.effective_policy,.effective_runner_state,.effective_runner_source][] | . + "\u0000"' \
  "$work_dir/config.json" >"$work_dir/fields" || fail 'cannot decode config fields'
fields=()
while IFS= read -r -d '' field; do fields+=("$field"); done <"$work_dir/fields"
local_review_override_applied=$(jq -r '.local_review_override_applied' "$work_dir/config.json") || fail 'cannot decode local override state'
policy_state=${fields[0]} policy_source=${fields[1]} policy_input=${fields[2]}
unreadable_file=${fields[3]} unreadable_detail=${fields[4]}
if [ "$local_review_override_applied" = true ] && [ -n "${fields[5]}" ]; then local_state="${fields[5]} (${fields[6]}), applied"
elif [ -z "${fields[5]}" ] && [ -n "${fields[7]}" ]; then local_state="present but unpropagated: ${fields[7]}"
fi
case "$policy_state" in
  unreadable) block policy-unreadable ;; unsupported) block policy-unsupported ;;
  absent|empty) policy=warn; policy_source=default ;;
  defined) policy=${fields[8]}; case "$policy" in warn|fail-if-any-unavailable) ;; *) fail 'invalid defined policy' ;; esac ;;
  *) fail 'invalid policy state' ;;
esac
list_state=${fields[9]} list_source=${fields[10]}
case "$list_state" in
  malformed) block list-malformed ;; absent|empty) fallback=true ;; defined) ;; *) fail 'invalid runner list state' ;;
esac
jq -j '.override_excluded[] | . + "\u0000"' "$work_dir/config.json" >"$work_dir/excluded" || fail 'cannot decode exclusions'
while IFS= read -r -d '' entry; do add_record "$entry" override-excluded '' 'removed by local override'; done <"$work_dir/excluded"
if [ "$fallback" = true ]; then
  [ "$runner_kind" != unknown ] || block no-driving-runner
  outcome=proceeded
  report
  exit 0
fi

probe_local() {
  local entry=$1 binary=$1 rc=0
  [ "$entry" != cursor ] || binary='cursor-agent'
  if ! have_cmd "$binary"; then reason=runtime-absent; detail="$binary is not on PATH"; return; fi
  clamp_bound "$LOCAL_PROBE_CAP_SECONDS"
  run_bounded "$bound" "$work_dir/probe.out" "$work_dir/probe.err" "$binary" --version || rc=$?
  if [ "$rc" = 0 ]; then verdict=reachable; reason=; detail="$binary --version succeeded"
  elif [ "$rc" = 124 ]; then detail="check exceeded its ${bound}s bound"
  else detail="$binary --version exited $rc"
  fi
}
probe_hosted() {
  local entry=$1 login rc=0 signal host_deadline=$((SECONDS + HOSTED_PROBE_CAP_SECONDS))
  have_cmd gh || { detail='gh is not on PATH'; return; }
  if [ "$entry" = coderabbit ]; then
    clamp_bound "$HOSTED_PROBE_CAP_SECONDS"
    run_bounded "$bound" "$work_dir/enabled" "$work_dir/probe.err" python3 -B -c '
import pathlib, re, sys

path = pathlib.Path(sys.argv[1])

def scalar_before_comment(value):
    for index, char in enumerate(value):
        if char == "#" and (index == 0 or value[index - 1].isspace()):
            return value[:index].rstrip()
    return value.rstrip()

def fields(text):
    block_indent = None
    flow = []
    quote = None
    def consume_flow(value, number):
        nonlocal quote
        index = 0
        while index < len(value):
            char = value[index]
            if quote is not None:
                if char == "\\" and quote == chr(34):
                    index += 2
                    continue
                if char == quote:
                    if quote == chr(39) and value[index:index + 2] == quote * 2:
                        index += 2
                        continue
                    quote = None
            elif char == "#" and (index == 0 or value[index - 1].isspace()):
                break
            elif char in (chr(34), chr(39)):
                quote = char
            elif char in "[{":
                flow.append(char)
            elif char in "]}":
                if not flow or flow.pop() != {"]": "[", "}": "{"}[char]:
                    raise ValueError(f"mismatched flow delimiter on line {number}")
                if not flow:
                    if scalar_before_comment(value[index + 1:]).strip():
                        raise ValueError(f"unexpected text after flow value on line {number}")
                    return
            index += 1
    for number, line in enumerate(text.splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if flow:
            consume_flow(line, number)
            continue
        leading = len(line) - len(line.lstrip(" \t"))
        if block_indent is not None:
            if leading > block_indent:
                continue
            block_indent = None
        if "\t" in line[:leading]:
            raise ValueError(f"tab indentation on line {number}")
        # Keys outside the target path can be quoted or contain punctuation.
        # A sequence item containing a colon is still a sequence, not a field.
        match = None if re.match(r"^\s*-(?:\s|$)", line) else re.match(
            r"^( *)(\"(?:\\.|[^\"\\])*\"|\x27(?:\x27\x27|[^\x27])*\x27|[^\s:#][^:]*):(?:[ \t]+(.*)|$)", line)
        if match:
            key = match.group(2).strip()
            if key.startswith((chr(34), chr(39))):
                key = key[1:-1]
            raw_value = (match.group(3) or "").lstrip()
            value = raw_value.rstrip() if raw_value.startswith(("[", "{")) else scalar_before_comment(raw_value)
            if value.startswith(("[", "{")):
                consume_flow(value, number)
            if re.fullmatch(r"[|>][1-9+-]*", value):
                block_indent = len(match.group(1))
            yield number, len(match.group(1)), key, value
        else:
            # Preserve nonmapping tokens so malformed target containers cannot
            # disappear. Unrelated sequence contents are handled by their scope.
            yield number, leading, None, line.lstrip()
    if flow:
        raise ValueError("unterminated flow collection")

try:
    if not path.is_file():
        print("false")
        raise SystemExit(0)
    reviews_indent = reviews_children = auto_indent = auto_children = None
    reviews_closed = auto_closed = False
    reviews_list_allowed = auto_list_allowed = False
    enabled = None
    for number, indent, key, value in fields(path.read_text(encoding="utf-8")):
        if reviews_indent is None:
            if indent == 0 and key == "reviews":
                if value:
                    raise ValueError(f"reviews must be a mapping on line {number}")
                reviews_indent = indent
            continue
        if indent <= reviews_indent:
            if not reviews_closed and key is None and re.match(r"-(?:\s|$)", value):
                raise ValueError(f"reviews must be a mapping on line {number}")
            if key == "reviews":
                raise ValueError(f"duplicate reviews mapping on line {number}")
            reviews_closed = True
            continue
        if reviews_closed:
            continue
        if reviews_children is None:
            reviews_children = indent
        if indent == reviews_children:
            if key is None:
                # YAML allows an indentless sequence as the value of a sibling
                # field such as path_filters; it cannot be the reviews mapping.
                if reviews_list_allowed and re.match(r"-(?:\s|$)", value):
                    continue
                raise ValueError(f"expected reviews mapping field on line {number}")
            reviews_list_allowed = key != "auto_review" and not value
        if indent == reviews_children and key == "auto_review":
            if auto_indent is not None:
                raise ValueError(f"duplicate auto_review mapping on line {number}")
            if value:
                raise ValueError(f"auto_review must be a mapping on line {number}")
            auto_indent = indent
            continue
        if auto_indent is None:
            continue
        if indent <= auto_indent:
            auto_closed = True
            continue
        if auto_closed:
            continue
        if auto_children is None:
            auto_children = indent
        if indent == auto_children:
            if key is None:
                if auto_list_allowed and re.match(r"-(?:\s|$)", value):
                    continue
                raise ValueError(f"expected auto_review mapping field on line {number}")
            auto_list_allowed = key != "enabled" and not value
        if indent == auto_children and key == "enabled":
            if enabled is not None:
                raise ValueError(f"duplicate enabled value on line {number}")
            if value not in ("true", "false"):
                raise ValueError(f"enabled must be a boolean on line {number}")
            enabled = value == "true"
    print("true" if enabled is True else "false")
except (OSError, UnicodeDecodeError, ValueError) as error:
    print(str(error), file=sys.stderr)
    sys.exit(3)
' "$repo_root/.coderabbit.yaml" || rc=$?
    if [ "$rc" = 3 ]; then
      detail=".coderabbit.yaml could not be read: $(cat "$work_dir/probe.err")"
      return
    fi
    if [ "$rc" != 0 ]; then detail='CodeRabbit enablement check did not complete'; return; fi
    if [ "$(cat "$work_dir/enabled")" != true ]; then reason=prerequisite-missing; detail='reviews.auto_review.enabled is not true'; return; fi
    login='coderabbitai[bot]'
  else login=${CODEX_GITHUB_BOT_LOGIN:-chatgpt-codex-connector[bot]}
  fi
  clamp_bound "$HOSTED_PROBE_CAP_SECONDS"
  [ "$bound" -le "$((host_deadline - SECONDS))" ] || bound=$((host_deadline - SECONDS))
  rc=0
  run_bounded "$bound" "$work_dir/activity.json" "$work_dir/probe.err" gh api \
    "repos/$owner/$repo/issues/comments?per_page=100&sort=created&direction=desc" || rc=$?
  if [ "$rc" != 0 ]; then
    if [ "$rc" = 124 ]; then detail="check exceeded its ${bound}s bound"; else detail="gh api exited $rc"; fi
    return
  fi
  if ! signal=$(jq -er --arg login "${login%\[bot\]}" '
    if type != "array" or any(.[]; (.user.login|type) != "string") then error("invalid comments response")
    elif any(.[]; (.user.login | sub("\\[bot\\]$"; "")) == $login) then "present"
    elif length >= 100 then "incomplete" else "absent" end' "$work_dir/activity.json"); then
    detail='gh api returned invalid comments JSON'; return
  fi
  case "$signal" in
    present) verdict=reachable; reason=; detail='repository issue-comment activity found (installation proxy)' ;;
    incomplete) detail='activity coverage incomplete' ;;
    absent) reason=prerequisite-missing; detail='no matching repository issue-comment activity' ;;
  esac
}
jq -j '.effective_runner[] | . + "\u0000"' "$work_dir/config.json" >"$work_dir/entries" || fail 'cannot decode reviewers'
while IFS= read -r -d '' entry; do
  verdict=unreachable reason=check-inconclusive detail=
  case "$entry" in
    claude|cursor|codex)
      if [ "$entry" = "$runner_kind" ]; then
        verdict=reachable; reason=; detail='native reviewer in the driving session'
      elif [ "$SECONDS" -ge "$DEADLINE" ]; then detail='availability budget exhausted before this check started'
      else probe_local "$entry"
      fi ;;
    coderabbit|codex-github)
      if [ "$SECONDS" -ge "$DEADLINE" ]; then detail='availability budget exhausted before this check started'
      else probe_hosted "$entry"
      fi ;;
    *) reason='value-not-supported'; detail='value is not a supported reviewer' ;;
  esac
  add_record "$entry" "$verdict" "$reason" "$detail"
done <"$work_dir/entries"
[ "$reachable_count" -gt 0 ] || block zero-reachable
if [ "$unavailable_count" -gt 0 ]; then
  [ "$policy" != fail-if-any-unavailable ] || block policy-forbids-reduced-coverage
  outcome=proceeded-reduced
else outcome=proceeded
fi
report

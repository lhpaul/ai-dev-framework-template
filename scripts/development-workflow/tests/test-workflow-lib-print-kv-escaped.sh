#!/usr/bin/env bash
# test-workflow-lib-print-kv-escaped.sh — print_kv_escaped stays byte-identical
# to the original four-pass implementation and linear in the input size.
#
# Issue #1539: on bash 3.2 (macOS /bin/bash) each ${var//pattern/repl} pass is
# quadratic in the string length, so a 58 KB value took 18 s and 117 KB did not
# finish in two minutes. print_kv_escaped now streams bounded chunks.
#
# Every case runs under each available bash: the invoking one, /bin/bash and
# Homebrew bash. On macOS /bin/bash is 3.2, the shell that exposed the blowup.
#
# Usage: bash scripts/development-workflow/tests/test-workflow-lib-print-kv-escaped.sh
# covers: scripts/development-workflow/workflow-lib.sh
# duration: 30

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
LIB="$REPO_ROOT/scripts/development-workflow/workflow-lib.sh"

# Runtime bound for the 117 KB payload from the issue. The linear version
# finishes in well under a second; the quadratic one took more than 100 s on
# bash 3.2. The margin absorbs slow CI runners without hiding a regression.
RUNTIME_BOUND_SECONDS=5
# Structural bound: no full-string expansion pass may see more than one chunk
# (512 bytes, plus one carried byte that keeps a UTF-8 C1 pair whole). This
# catches a return to whole-string passes even on bash versions where it is
# not slow.
MAX_CHUNK_BYTES=513
# Scaling bound: escaping 8x the input may cost at most this many times as
# much. Linear work scores about 8; slicing or accumulating the whole string
# per chunk scored above 20 at these sizes, and whole-string passes time out.
SCALING_INPUT_FACTOR=8
SCALING_RATIO_BOUND=14
SCALING_TIMEOUT_SECONDS=60

PASS=0
FAIL=0
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }

SHELLS=()
add_shell() {
  local candidate="$1" existing
  [ -n "$candidate" ] && [ -x "$candidate" ] || return 0
  for existing in ${SHELLS[@]+"${SHELLS[@]}"}; do
    [ "$existing" = "$candidate" ] && return 0
  done
  SHELLS+=("$candidate")
}
add_shell "${BASH:-}"
add_shell /bin/bash
add_shell /opt/homebrew/bin/bash

# The original implementation (workflow-lib.sh before #1539), kept verbatim as
# the byte-for-byte reference.
cat >"$WORK_DIR/legacy.sh" <<'LEGACY'
legacy_print_kv_escaped() {
  local value="$2" control escaped code octal
  local LC_ALL=C
  value="${value//\\/\\\\}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\t'/\\t}"
  if [[ "$value" == *[$'\001'-$'\037'$'\177']* ]]; then
    for ((code=1; code<=127; code++)); do
      [ "$code" -le 31 ] || [ "$code" -eq 127 ] || continue
      printf -v octal '\\%03o' "$code"
      printf -v control '%b' "$octal"
      printf -v escaped '\\x%02x' "$code"
      value="${value//$control/$escaped}"
    done
  fi
  if [[ "$value" == *$'\302'[$'\200'-$'\237']* ]]; then
    for ((code=128; code<=159; code++)); do
      printf -v octal '\\302\\%03o' "$code"
      printf -v control '%b' "$octal"
      printf -v escaped '\\u%04x' "$code"
      value="${value//$control/$escaped}"
    done
  fi
  printf '%s=%s\n' "$1" "$value"
}
LEGACY

# Runs a command with stdout to a file and a hard timeout; prints the elapsed
# seconds, or "timeout" (exit 1) when the bound is hit.
cat >"$WORK_DIR/timed.py" <<'PY'
import subprocess
import sys
import time

bound, output, command = float(sys.argv[1]), sys.argv[2], sys.argv[3:]
start = time.monotonic()
try:
    with open(output, "wb") as handle:
        result = subprocess.run(command, stdout=handle, timeout=bound)
except subprocess.TimeoutExpired:
    print("timeout")
    sys.exit(1)
print("%.3f" % (time.monotonic() - start))
sys.exit(result.returncode)
PY

# Reads a fixture file into $value without losing trailing newlines.
cat >"$WORK_DIR/read-value.sh" <<'READ'
read_value() { value="$(cat "$1"; printf x)"; value="${value%x}"; }
READ

# ── Fixtures (no NUL: bash values cannot hold one) ──────────────────────────
FIXTURES="$WORK_DIR/fixtures"
mkdir -p "$FIXTURES"
python3 - "$FIXTURES" <<'PY'
import random
import sys
from pathlib import Path

out = Path(sys.argv[1])
cases = {
    "empty": b"",
    "plain": b"plain ascii value",
    "all-four": b"a\\b\rc\nd\te",
    "adjacent": b"\\\\\r\r\n\n\t\t\\\r\n\t\t\n\r\\",
    "repeated": b"\\\\\\\\\\" + b"\n" * 7 + b"\t" * 5 + b"\r" * 3,
    "leading-backslash": b"\\leading",
    "trailing-backslash": b"trailing\\",
    "only-backslash": b"\\",
    "escape-lookalikes": b"\\n\\r\\t\\x01\\u0085 literal",
    "trailing-newlines": b"value\n\n\n",
    "c0-and-del": bytes(range(1, 32)) + b"\x7f",
    "c1-pairs": b"".join(b"\xc2" + bytes([c]) for c in range(0x80, 0xa0)),
    "c2-not-c1": b"\xc2\xa0 nbsp \xc2\xc2\x85 \xc2",
    "utf8": "señal — ünïcode ✓ 日本".encode(),
    "invalid-utf8": b"\xff\xfe\x80\x9f\xc2",
}
# Chunk boundaries: a C1 pair, a lone \302 and a run of \302 at every offset
# around 512 and 1024, so a split pair would be visible.
for size in (510, 511, 512, 513, 1023, 1024, 1025):
    for tail in (b"\xc2\x85", b"\xc2\xc2\x85", b"\xc2A", b"\xc2", b"\\\n", b"\x1b["):
        cases[f"boundary-{size}-{tail.hex()}"] = b"x" * (size - 1) + tail + b"y" * 3
cases["boundary-all-c2"] = b"\xc2" * 1500 + b"\x85"
cases["boundary-all-c1"] = b"\xc2\x9b" * 800
rng = random.Random(1539)
alphabet = [bytes([b]) for b in range(1, 256)] + [b"\xc2\x85", b"\\", b"\n", b"\r", b"\t"] * 20
for index in range(24):
    length = rng.randint(1, 2600)
    cases[f"fuzz-{index:02d}"] = b"".join(rng.choice(alphabet) for _ in range(length))
for name, data in cases.items():
    (out / name).write_bytes(data)
PY

# AC-1: byte-identical to the original across every fixture, in every shell.
for shell in ${SHELLS[@]+"${SHELLS[@]}"}; do
  version="$("$shell" -c 'printf %s "$BASH_VERSION"')"
  mismatches=""
  for fixture in "$FIXTURES"/*; do
    name="$(basename "$fixture")"
    "$shell" -c 'source "$1"; source "$2"; source "$3"; read_value "$4"; print_kv_escaped KEY "$value"' \
      synthetic "$LIB" "$WORK_DIR/legacy.sh" "$WORK_DIR/read-value.sh" "$fixture" >"$WORK_DIR/new.out"
    "$shell" -c 'source "$1"; source "$2"; source "$3"; read_value "$4"; legacy_print_kv_escaped KEY "$value"' \
      synthetic "$LIB" "$WORK_DIR/legacy.sh" "$WORK_DIR/read-value.sh" "$fixture" >"$WORK_DIR/old.out"
    cmp -s "$WORK_DIR/new.out" "$WORK_DIR/old.out" || mismatches="$mismatches $name"
  done
  if [ -z "$mismatches" ]; then
    pass "bash $version: byte-identical to the original on every fixture"
  else
    fail "bash $version: output differs from the original for:$mismatches"
  fi
done

# AC-4: each output is one KEY=value line that decodes back to the input, so
# line-oriented callers still read the value they were given.
decode_check="$WORK_DIR/decode.py"
cat >"$decode_check" <<'PY'
import re
import sys

source = open(sys.argv[1], "rb").read()
line = open(sys.argv[2], "rb").read()
if not line.startswith(b"KEY=") or not line.endswith(b"\n") or line.count(b"\n") != 1:
    sys.exit("not a single KEY=value line")
body = line[4:-1]
if any(byte < 0x20 or byte == 0x7F for byte in body) or re.search(rb"\xc2[\x80-\x9f]", body):
    sys.exit("raw control byte left in the escaped value")
simple = {b"\\": b"\\", b"r": b"\r", b"n": b"\n", b"t": b"\t"}

def decode(match):
    token = match.group(0)
    if token[1:2] in simple:
        return simple[token[1:2]]
    if token[1:2] == b"x":
        return bytes([int(token[2:], 16)])
    return chr(int(token[2:], 16)).encode()

decoded = re.sub(rb"\\(?:[\\rnt]|x[0-9a-f]{2}|u00[89][0-9a-f])", decode, body)
if decoded != source:
    sys.exit("decoded value differs from the input")
PY
for shell in ${SHELLS[@]+"${SHELLS[@]}"}; do
  version="$("$shell" -c 'printf %s "$BASH_VERSION"')"
  failures=""
  for fixture in "$FIXTURES"/*; do
    "$shell" -c 'source "$1"; source "$2"; read_value "$3"; print_kv_escaped KEY "$value"' \
      synthetic "$LIB" "$WORK_DIR/read-value.sh" "$fixture" >"$WORK_DIR/new.out"
    python3 "$decode_check" "$fixture" "$WORK_DIR/new.out" 2>/dev/null || failures="$failures $(basename "$fixture")"
  done
  if [ -z "$failures" ]; then
    pass "bash $version: every output is one line that decodes back to its input"
  else
    fail "bash $version: round trip failed for:$failures"
  fi
done

# ── Large payload: the 117 KB case from the issue ───────────────────────────
LARGE="$WORK_DIR/large"
python3 - "$LARGE" <<'PY'
import sys

line = b"review finding line %d: path\\to\\file\tcol\r with \x1b[31mcolour\x1b[0m and \xc2\x85 C1\n"
data = b"".join(line % index for index in range(1, 2000))
data = data[:117 * 1024]
open(sys.argv[1], "wb").write(data)
PY
large_bytes="$(wc -c <"$LARGE" | tr -d ' ')"

# AC-2 / AC-3: runtime bound in every shell. The run is killed at the bound so
# a quadratic regression fails here instead of hanging the suite.
for shell in ${SHELLS[@]+"${SHELLS[@]}"}; do
  version="$("$shell" -c 'printf %s "$BASH_VERSION"')"
  timing_status=0
  elapsed="$(python3 "$WORK_DIR/timed.py" "$RUNTIME_BOUND_SECONDS" "$WORK_DIR/large.out" "$shell" -c \
    'source "$1"; source "$2"; read_value "$3"; print_kv_escaped KEY "$value"' \
    synthetic "$LIB" "$WORK_DIR/read-value.sh" "$LARGE")" || timing_status=$?
  if [ "$timing_status" -eq 0 ]; then
    pass "bash $version: ${large_bytes}-byte value escaped in ${elapsed}s (bound ${RUNTIME_BOUND_SECONDS}s)"
  else
    fail "bash $version: ${large_bytes}-byte value did not finish within ${RUNTIME_BOUND_SECONDS}s (${elapsed:-error})"
    continue
  fi
  if python3 "$decode_check" "$LARGE" "$WORK_DIR/large.out"; then
    pass "bash $version: large value round-trips"
  else
    fail "bash $version: large value does not round-trip"
  fi
done

# AC-3: structural bound. Wrap the chunk escaper and record the largest input
# it sees; a rewrite that goes back to whole-string passes exceeds the bound.
max_chunk="$(bash -c '
  source "$1"; source "$2"
  _max=0
  eval "_orig_$(declare -f _workflow_kv_escape_chunk)"
  _workflow_kv_escape_chunk() {
    local LC_ALL=C
    [ "${#1}" -gt "$_max" ] && _max=${#1}
    _orig__workflow_kv_escape_chunk "$1"
  }
  read_value "$3"
  print_kv_escaped KEY "$value" >/dev/null
  printf %s "$_max"
' synthetic "$LIB" "$WORK_DIR/read-value.sh" "$LARGE")"
if [ "$max_chunk" -gt 0 ] && [ "$max_chunk" -le "$MAX_CHUNK_BYTES" ]; then
  pass "no escape pass sees more than $MAX_CHUNK_BYTES bytes (largest: $max_chunk)"
else
  fail "an escape pass saw $max_chunk bytes (bound $MAX_CHUNK_BYTES)"
fi

# AC-2 / AC-3: scaling. Time an empty value (shell start-up), the large value
# and SCALING_INPUT_FACTOR copies of it; the escaping cost must grow linearly.
# A fixed total bound alone cannot tell linear from quadratic work.
SCALED="$WORK_DIR/scaled"
python3 - "$LARGE" "$SCALED" "$SCALING_INPUT_FACTOR" <<'PY'
import sys

data = open(sys.argv[1], "rb").read()
open(sys.argv[2], "wb").write(data * int(sys.argv[3]))
PY
: >"$WORK_DIR/empty"
for shell in ${SHELLS[@]+"${SHELLS[@]}"}; do
  version="$("$shell" -c 'printf %s "$BASH_VERSION"')"
  scaling_failed=0
  timings=""
  for input in "$WORK_DIR/empty" "$LARGE" "$SCALED"; do
    timing_status=0
    elapsed="$(python3 "$WORK_DIR/timed.py" "$SCALING_TIMEOUT_SECONDS" "$WORK_DIR/scaled.out" "$shell" -c \
      'source "$1"; source "$2"; read_value "$3"; print_kv_escaped KEY "$value"' \
      synthetic "$LIB" "$WORK_DIR/read-value.sh" "$input")" || timing_status=$?
    if [ "$timing_status" -ne 0 ]; then
      scaling_failed=1
      fail "bash $version: $(basename "$input") value did not finish within ${SCALING_TIMEOUT_SECONDS}s (${elapsed:-error})"
      break
    fi
    timings="$timings $elapsed"
  done
  [ "$scaling_failed" -eq 0 ] || continue
  # shellcheck disable=SC2086 # timings is a list of three numbers
  if ratio="$(python3 - "$SCALING_RATIO_BOUND" $timings <<'PY'
import sys

bound, base, small, big = (float(value) for value in sys.argv[1:])
# Floor the small cost so timer noise on a fast machine cannot inflate the ratio.
ratio = max(big - base, 0.0) / max(small - base, 0.05)
print("%.1f" % ratio)
sys.exit(0 if ratio < bound else 1)
PY
  )"; then
    pass "bash $version: ${SCALING_INPUT_FACTOR}x input costs ${ratio}x (bound ${SCALING_RATIO_BOUND}x; timings:$timings s)"
  else
    fail "bash $version: ${SCALING_INPUT_FACTOR}x input costs ${ratio}x (bound ${SCALING_RATIO_BOUND}x; timings:$timings s)"
  fi
done

# AC-4: the BLOCKING_<n>_BODY emitters in pr-review-loop.sh use
# workflow_diagnostic_kv_escaped. Its output must stay identical to
# print_kv_escaped for a large reviewer body with nothing to redact. The value
# is read the way those call sites read it, through command substitution
# ("$(... | jq -r '.body')"), which drops trailing newlines.
if diagnostic_out="$(bash -c 'source "$1"; value="$(cat "$2")"; workflow_diagnostic_kv_escaped BLOCKING_1_BODY "$value"' \
      synthetic "$LIB" "$LARGE" 2>/dev/null)"; then
  direct_out="$(bash -c 'source "$1"; value="$(cat "$2")"; print_kv_escaped BLOCKING_1_BODY "$value"' \
    synthetic "$LIB" "$LARGE")"
  if [ "$diagnostic_out" = "$direct_out" ]; then
    pass "BLOCKING_<n>_BODY diagnostic emitter matches print_kv_escaped on the large body"
  else
    fail "BLOCKING_<n>_BODY diagnostic emitter differs from print_kv_escaped on the large body"
  fi
else
  fail "workflow_diagnostic_kv_escaped failed on the large body"
fi

printf '\nResults: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

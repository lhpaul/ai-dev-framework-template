#!/usr/bin/env python3
"""Verify Linear release completion from an operator-supplied read-back (#2009).

The shell release cleanup helper cannot read Linear. The release operator reads
every in-scope item through the Linear integration the workflow already
documents, normalizes each read into the ``linear_release_readback.v1`` shape,
and passes the file to ``prepare-release-post-merge-cleanup.sh
--linear-readback``. This evaluator compares those reads with the release scope
and prints one stable key=value line per fact. It never contacts Linear and
never mutates tracker state.

Usage:
  linear-release-verification.py evaluate --state-dir DIR --release-branch B \
    --release-version V --release-label L --released-status S \
    --run-started-at TS --now TS [--readback PATH] --scope ID [--scope ID ...]

Exit codes: 0 complete, 1 incomplete, 2 usage error, 3 unavailable (state or
record cannot be kept, or an unexpected error). On 3 only one
``LINEAR_RELEASE_VERIFICATION_UNAVAILABLE reason=<reason>`` line is printed.

Read-back schema (``linear_release_readback.v1``)::

  {"schemaVersion": "linear_release_readback.v1",
   "reads": [{"suppliedFor": "LEA-1", "provider": "linear", "issue": "LEA-1",
              "team": "LEA", "releaseVersion": "v1.2.3",
              "labels": ["release/v1.2.3"], "statusName": "Released",
              "observedAt": "2026-11-13T10:00:00Z", "readRequestId": "r-1",
              "mutationRequestId": "m-1"}]}

``mutationRequestId`` is optional. Unknown extra fields are ignored.
"""

import argparse
import json
import os
import re
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

SCHEMA_VERSION = "linear_release_readback.v1"
STATE_SCHEMA_VERSION = "linear_release_first_run.v1"
RECORD_SCHEMA_VERSION = "linear_release_verification_record.v1"
# Same Linear identifier pattern the cleanup script accepts (one '-').
LINEAR_ID = re.compile(r"^[A-Za-z][A-Za-z0-9_]*-[0-9]+$")
# Scope identifiers the cleanup script can pass: Linear IDs or numeric IDs.
SCOPE_TOKEN = re.compile(r"^[A-Za-z0-9_-]+$")
PLAIN_ARG = re.compile(r"^[^\s\x00-\x1f\x7f]+$")
REASON_ORDER = ("unreadable", "mismatch", "stale")
RESULT_ORDER = (
    "verified",
    "missing_label",
    "not_released",
    "missing_label_and_not_released",
    "not_verified",
)
REQUIRED_STRINGS = ("issue", "team", "releaseVersion", "statusName", "readRequestId")


class Unavailable(Exception):
    """Verification cannot produce a trustworthy outcome."""

    def __init__(self, reason):
        super().__init__(reason)
        self.reason = reason


class UsageError(Exception):
    pass


def encode(value):
    """JSON-encode a value on one ASCII line so it cannot forge output lines."""
    return json.dumps(value, ensure_ascii=True, separators=(",", ":"), sort_keys=True)


def parse_instant(value):
    """Return an aware UTC datetime, or None when the value is not an instant."""
    if not isinstance(value, str) or "T" not in value:
        return None
    text = value.strip()
    if text.endswith(("Z", "z")):
        text = text[:-1] + "+00:00"
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        return None
    return parsed.astimezone(timezone.utc)


def format_instant(value):
    if value.microsecond:
        return value.strftime("%Y-%m-%dT%H:%M:%S.%fZ")
    return value.strftime("%Y-%m-%dT%H:%M:%SZ")


def owning_team(identifier):
    """Team key of a Linear identifier, or None for unsupported identifiers."""
    if not LINEAR_ID.match(identifier):
        return None
    return identifier.split("-", 1)[0]


def same_id(left, right):
    return left.upper() == right.upper()


def state_key(release_branch):
    key = release_branch.replace("/", "__")
    key = re.sub(r"[^A-Za-z0-9._-]", "_", key)
    if key in ("", ".", ".."):
        raise UsageError("release branch cannot form a state key")
    return key


def write_json_atomically(path, payload):
    """Write a complete temporary file, then rename it into place."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".tmp-", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, ensure_ascii=True, indent=2, sort_keys=True)
            handle.write("\n")
        os.replace(temporary, str(path))
    except BaseException:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise


def read_first_run(path, release_branch):
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError, UnicodeDecodeError) as exc:
        raise Unavailable("state_unreadable") from exc
    if not isinstance(data, dict) or data.get("releaseBranch") != release_branch:
        raise Unavailable("state_unreadable")
    started = parse_instant(data.get("firstRunStartedAt"))
    if started is None:
        raise Unavailable("state_unreadable")
    return started


def first_run_started_at(directory, release_branch, release_version, run_started_at):
    """Keep exactly one first-run record per release branch; never move it."""
    path = directory / "first-run.json"
    if path.exists():
        return read_first_run(path, release_branch)
    payload = {
        "schemaVersion": STATE_SCHEMA_VERSION,
        "releaseBranch": release_branch,
        "releaseVersion": release_version,
        "firstRunStartedAt": format_instant(run_started_at),
    }
    temporary = None
    try:
        directory.mkdir(parents=True, exist_ok=True)
        fd, temporary = tempfile.mkstemp(prefix=".first-run-", dir=str(directory))
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, ensure_ascii=True, indent=2, sort_keys=True)
            handle.write("\n")
        try:
            # os.link fails when the name exists, so a concurrent first run
            # keeps the record it published first and never sees a partial one.
            os.link(temporary, str(path))
        except FileExistsError:
            return read_first_run(path, release_branch)
    except OSError as exc:
        raise Unavailable("state_unwritable") from exc
    finally:
        if temporary is not None:
            try:
                os.unlink(temporary)
            except OSError:
                pass
    return run_started_at


def load_readback(path):
    """Return (reads, raw_text, shape_error). Shape errors leave reads empty."""
    if path is None:
        return [], None, None
    try:
        raw = Path(path).read_bytes().decode("utf-8", errors="replace")
    except OSError:
        return [], None, "readback_unreadable"
    try:
        document = json.loads(raw)
    except ValueError:
        return [], raw, "readback_not_json"
    if not isinstance(document, dict):
        return [], raw, "readback_not_object"
    if document.get("schemaVersion") != SCHEMA_VERSION:
        return [], raw, "readback_schema_version"
    reads = document.get("reads")
    if not isinstance(reads, list):
        return [], raw, "readback_reads_not_array"
    return reads, raw, None


def attribute(read, scope_lookup):
    """Return (item, ignored_reason, shown_issue)."""
    if not isinstance(read, dict):
        return None, "unattributable", None
    target = None
    for field in ("suppliedFor", "issue"):
        value = read.get(field)
        if isinstance(value, str) and LINEAR_ID.match(value):
            target = value
            break
    if target is None:
        shown = read.get("suppliedFor", read.get("issue"))
        return None, "unattributable", shown if isinstance(shown, str) else None
    item = scope_lookup.get(target.upper())
    if item is None:
        return None, "out_of_scope", target
    return item, None, target


def check_read(read, item, release_version, now, starting_point):
    """Return (reason, detail, observed). reason None means usable."""
    if read.get("provider") != "linear":
        return "unreadable", "provider_not_linear", None
    for field in REQUIRED_STRINGS:
        value = read.get(field)
        if not isinstance(value, str) or not value:
            return "unreadable", "invalid_" + field, None
    labels = read.get("labels")
    if not isinstance(labels, list) or not all(isinstance(label, str) for label in labels):
        return "unreadable", "invalid_labels", None
    observed = parse_instant(read.get("observedAt"))
    if observed is None:
        return "unreadable", "invalid_observedAt", None
    if observed.replace(microsecond=0) > now:
        return "unreadable", "future_observedAt", observed
    mutation = read.get("mutationRequestId")
    if mutation is not None:
        if not isinstance(mutation, str):
            return "unreadable", "invalid_mutationRequestId", observed
        if mutation == read["readRequestId"]:
            return "unreadable", "echoed_write", observed
    if not same_id(read["issue"], item):
        return "mismatch", "other_item", observed
    if read["releaseVersion"] != release_version:
        return "mismatch", "other_release_version", observed
    if not same_id(read["team"], owning_team(item)):
        return "mismatch", "other_team", observed
    if observed <= starting_point:
        return "stale", "before_first_run", observed
    return None, None, observed


def classify(label_present, released):
    if label_present and released:
        return "verified"
    if released:
        return "missing_label"
    if label_present:
        return "not_released"
    return "missing_label_and_not_released"


def evaluate(args):
    now = parse_instant(args.now)
    run_started_at = parse_instant(args.run_started_at)
    if now is None or run_started_at is None:
        raise UsageError("--now and --run-started-at must be ISO 8601 instants with an offset")
    for name in ("release_branch", "release_version", "release_label", "released_status"):
        value = getattr(args, name)
        if not value or ("\n" in value or "\r" in value):
            raise UsageError("--%s must be a non-empty single-line value" % name.replace("_", "-"))
    for name in ("release_branch", "release_version", "release_label"):
        if not PLAIN_ARG.match(getattr(args, name)):
            raise UsageError("--%s must not contain whitespace" % name.replace("_", "-"))
    scope = []
    seen = set()
    for identifier in args.scope:
        if not SCOPE_TOKEN.match(identifier):
            raise UsageError("invalid --scope identifier")
        if identifier.upper() not in seen:
            seen.add(identifier.upper())
            scope.append(identifier)
    if not scope:
        raise UsageError("at least one --scope identifier is required")

    directory = Path(args.state_dir) / state_key(args.release_branch)
    starting_point = first_run_started_at(
        directory, args.release_branch, args.release_version, run_started_at)

    reads, raw_text, shape_error = load_readback(args.readback)
    supported = {item.upper(): item for item in scope if owning_team(item) is not None}

    attributed = {item: [] for item in scope}
    ignored = []
    if shape_error is None:
        for index, read in enumerate(reads):
            item, ignored_reason, shown = attribute(read, supported)
            if item is None:
                ignored.append({"index": index, "issue": shown, "reason": ignored_reason})
                continue
            reason, detail, observed = check_read(
                read, item, args.release_version, now, starting_point)
            attributed[item].append({
                "index": index,
                "read": read,
                "reason": reason,
                "detail": detail,
                "observed": observed,
            })

    label_observed = False
    items = []
    for item in scope:
        entry = {"issue": item}
        if owning_team(item) is None:
            entry.update(result="not_verified", reasons=["unsupported_identifier"])
            items.append(entry)
            continue
        if shape_error is not None:
            entry.update(result="not_verified", reasons=["unreadable"], detail=shape_error)
            items.append(entry)
            continue
        candidates = attributed[item]
        usable = [c for c in candidates if c["reason"] is None]
        for candidate in usable:
            if args.release_label in candidate["read"]["labels"]:
                label_observed = True
        if not candidates:
            entry.update(result="not_verified", reasons=["no_read"])
        elif not usable:
            reasons = {c["reason"] for c in candidates}
            entry.update(result="not_verified",
                         reasons=[r for r in REASON_ORDER if r in reasons])
        else:
            latest = max(c["observed"] for c in usable)
            group = [c for c in usable if c["observed"] == latest]
            states = {(args.release_label in c["read"]["labels"], c["read"]["statusName"])
                      for c in group}
            if len(states) > 1:
                entry.update(result="not_verified", reasons=["conflicting"])
            else:
                label_present, status_name = states.pop()
                decided = group[0]
                entry.update(
                    result=classify(label_present, status_name == args.released_status),
                    label_present=label_present,
                    status=status_name,
                    labels_read=decided["read"]["labels"],
                    read_at=format_instant(latest),
                    decided_by=decided["index"],
                )
        if entry["result"] == "not_verified" and candidates:
            entry["reads"] = [{
                "index": c["index"],
                "reason": c["reason"] or "usable",
                "detail": c["detail"],
                "statusName": c["read"].get("statusName"),
                "observedAt": c["read"].get("observedAt"),
            } for c in candidates]
        items.append(entry)

    counts = {result: 0 for result in RESULT_ORDER}
    for entry in items:
        counts[entry["result"]] += 1
    outcome = "complete" if counts["verified"] == len(items) else "incomplete"
    unverified = [entry["issue"] for entry in items if entry["result"] != "verified"]
    action = None
    if not label_observed:
        teams = sorted({owning_team(item).upper() for item in scope if owning_team(item)})
        action = {"label": args.release_label, "teams": teams}

    record_path = directory / "runs" / ("%s-%d.json" % (
        run_started_at.strftime("%Y%m%dT%H%M%SZ"), os.getpid()))
    record = {
        "schemaVersion": RECORD_SCHEMA_VERSION,
        "releaseBranch": args.release_branch,
        "releaseVersion": args.release_version,
        "releaseLabel": args.release_label,
        "requiredStatus": args.released_status,
        "firstRunStartedAt": format_instant(starting_point),
        "runStartedAt": format_instant(run_started_at),
        "evaluatedAt": format_instant(now),
        "scope": scope,
        "readback": None if args.readback is None else {
            "path": str(args.readback),
            "shapeError": shape_error,
            "text": raw_text,
        },
        "items": [{k: v for k, v in entry.items()} for entry in items],
        "ignored": ignored,
        "labelAction": action,
        "counts": counts,
        "outcome": outcome,
    }
    try:
        write_json_atomically(record_path, record)
    except OSError as exc:
        raise Unavailable("record_unwritable") from exc

    lines = ["LINEAR_RELEASE_VERIFICATION release_version=%s release_label=%s "
             "required_status=%s first_run_started_at=%s run_started_at=%s readback=%s" % (
                 args.release_version, args.release_label, encode(args.released_status),
                 format_instant(starting_point), format_instant(run_started_at),
                 "none" if args.readback is None else "supplied")]
    for entry in items:
        line = "LINEAR_RELEASE_ITEM issue=%s result=%s" % (entry["issue"], entry["result"])
        if entry["result"] == "not_verified":
            line += " reasons=%s" % ",".join(entry["reasons"])
            if "detail" in entry:
                line += " detail=%s" % entry["detail"]
            if "reads" in entry:
                line += " reads=%s" % encode(entry["reads"])
        else:
            line += " label=%s status=%s labels_read=%s read_at=%s" % (
                "present" if entry["label_present"] else "absent",
                encode(entry["status"]), encode(entry["labels_read"]), entry["read_at"])
        lines.append(line)
    for entry in ignored:
        lines.append("LINEAR_RELEASE_READ_IGNORED issue=%s reason=%s" % (
            encode(entry["issue"]), entry["reason"]))
    if action is not None:
        lines.append("LINEAR_RELEASE_LABEL_ACTION label=%s teams=%s "
                     "action=create_label_in_owning_team_if_missing_then_apply" % (
                         action["label"], ",".join(action["teams"]) or "none"))
    lines.append("LINEAR_RELEASE_COUNTS " + " ".join(
        "%s=%d" % (result, counts[result]) for result in RESULT_ORDER))
    lines.append("LINEAR_RELEASE_VERIFICATION_RECORD path=%s" % encode(str(record_path)))
    lines.append("LINEAR_RELEASE_OUTCOME=%s" % outcome)
    if outcome == "incomplete":
        lines.append("TRACKER_ISSUES_UNVERIFIED=%s" % ",".join(unverified))
    sys.stdout.write("\n".join(lines) + "\n")
    return 0 if outcome == "complete" else 1


def build_parser():
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    commands = parser.add_subparsers(dest="command")
    command = commands.add_parser("evaluate")
    command.add_argument("--state-dir", required=True)
    command.add_argument("--release-branch", required=True)
    command.add_argument("--release-version", required=True)
    command.add_argument("--release-label", required=True)
    command.add_argument("--released-status", required=True)
    command.add_argument("--run-started-at", required=True)
    command.add_argument("--now", required=True)
    command.add_argument("--readback")
    command.add_argument("--scope", action="append", default=[])
    return parser


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.command != "evaluate":
        parser.print_usage(sys.stderr)
        return 2
    try:
        return evaluate(args)
    except UsageError as exc:
        print("linear-release-verification: %s" % exc, file=sys.stderr)
        return 2
    except Unavailable as exc:
        print("LINEAR_RELEASE_VERIFICATION_UNAVAILABLE reason=%s" % exc.reason)
        return 3
    except Exception:  # noqa: BLE001 - fail closed on any unexpected error
        print("LINEAR_RELEASE_VERIFICATION_UNAVAILABLE reason=internal_error")
        return 3


if __name__ == "__main__":
    sys.exit(main())

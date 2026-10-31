#!/usr/bin/env python3
"""Canonical review evidence identity and explicit verification matching.

No network or configuration reads. Callers collect complete GitHub responses and
select authenticated reviewer requests; this module never grants that authority.
"""

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path


CONTEXT_SCHEMA = "review_evidence_context.v1"
PROOF_SCHEMA = "review_evidence_verification.v1"
BOOKKEEPING = (
    "### Automated Reviewer Loop Summary",
    "### Step 7a Internal Review Gate Summary",
    "## Document Quality Gate",
    "<!-- run-epic:pr-disposition -->",
    "<!-- run-epic:epic-ledger -->",
    "<!-- run-epic:checkpoint-status -->",
    "<!-- documentation-stage-alignment -->",
)


def positive_int(value):
    return type(value) is int and value > 0


def bookkeeping(body):
    """Only an exact opening marker/heading is excluded, never a substring."""
    first = body.strip().split("\n", 1)[0].rstrip("\r")
    return first in BOOKKEEPING


def snapshot(raw):
    if not isinstance(raw, dict):
        raise ValueError("snapshot must be an object")
    repo = raw.get("repository")
    pr = raw.get("pr_number")
    head = raw.get("head_sha")
    if not isinstance(repo, str) or not re.fullmatch(r"[\w.-]+/[\w.-]+", repo):
        raise ValueError("invalid repository identity")
    if not positive_int(pr) or not isinstance(head, str) or not re.fullmatch(r"[0-9a-f]{40}", head):
        raise ValueError("invalid PR/head identity")
    if raw.get("available") is not True:
        return {"schema": CONTEXT_SCHEMA, "repository": repo.lower(),
                "pr_number": pr, "head_sha": head, "body": "", "comments": [], "review_comments": [],
                "available": False, "snapshot_sha256": ""}
    body, comments = raw.get("body"), raw.get("comments")
    if not isinstance(body, str) or not isinstance(comments, list):
        raise ValueError("incomplete evidence response")
    eligible = []
    review_comments = []
    seen = set()
    for comment in comments:
        if not isinstance(comment, dict):
            raise ValueError("invalid comment record")
        ident, text, revision = (comment.get(k) for k in ("id", "body", "updated_at"))
        if (not positive_int(ident) or ident in seen or not isinstance(text, str)
                or not isinstance(revision, str) or not revision):
            raise ValueError("invalid comment identity/revision")
        seen.add(ident)
        record = {"id": ident, "body": text, "updated_at": revision}
        review_comments.append(record)
        if not bookkeeping(text):
            eligible.append(record)
    content = {"repository": repo.lower(), "pr_number": pr, "head_sha": head,
               "body": body, "comments": sorted(eligible, key=lambda c: c["id"])}
    encoded = json.dumps(content, ensure_ascii=False, sort_keys=True,
                         separators=(",", ":")).encode("utf-8")
    return {"schema": CONTEXT_SCHEMA, **content, "available": True,
            "review_comments": sorted(review_comments, key=lambda c: c["id"]),
            "snapshot_sha256": hashlib.sha256(encoded).hexdigest()}


def verify(context, result, request_id):
    """A matching explicit proof is necessary in addition to an ordinary clean."""
    def refused(reason):
        return {"verified": False, "reason": reason}

    if not isinstance(context, dict) or context.get("schema") != CONTEXT_SCHEMA:
        return refused("context_unavailable")
    try:
        canonical = snapshot(context)
    except ValueError:
        return refused("context_unavailable")
    if (not canonical["available"]
            or canonical["snapshot_sha256"] != context.get("snapshot_sha256")):
        return refused("context_unavailable")
    if not positive_int(request_id):
        return refused("request_unavailable")
    comments = {c["id"]: c["body"] for c in canonical["comments"]}
    if request_id not in comments:
        return refused("request_unavailable")
    if (not isinstance(result, dict) or result.get("result") != "clean"
            or result.get("reviewed_head") != canonical["head_sha"]):
        return refused("review_not_current_clean")
    proof = result.get("evidence_verification")
    if not isinstance(proof, dict) or proof.get("schema") != PROOF_SCHEMA:
        return refused("proof_missing")
    if (proof.get("status") != "verified"
            or type(proof.get("request_id")) is not int
            or proof["request_id"] != request_id
            or proof.get("snapshot_sha256") != canonical["snapshot_sha256"]):
        return refused("proof_mismatch")
    sources = proof.get("sources")
    if (not isinstance(sources, list) or not sources
            or any(not isinstance(s, str) for s in sources)
            or len(set(sources)) != len(sources)):
        return refused("proof_sources_invalid")
    for source in sources:
        if source == "body" and canonical["body"].strip():
            continue
        match = re.fullmatch(r"comment:([1-9][0-9]*)", source)
        ident = int(match[1]) if match else None
        if ident == request_id or not comments.get(ident, "").strip():
            return refused("proof_sources_invalid")
    return {"verified": True, "reason": "current_explicit_verification",
            "evidence_verification": proof}


def read_json(path):
    if path == "-":
        return json.load(sys.stdin)
    return json.loads(Path(path).read_text(encoding="utf-8"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    snap = commands.add_parser("snapshot")
    snap.add_argument("--input", required=True)
    check = commands.add_parser("verify")
    check.add_argument("--context", required=True)
    check.add_argument("--result", required=True)
    check.add_argument("--request-id", required=True, type=int)
    args = parser.parse_args()
    try:
        if args.command == "snapshot":
            output = snapshot(read_json(args.input))
        else:
            output = verify(read_json(args.context), read_json(args.result), args.request_id)
    except (ValueError, OSError, TypeError, OverflowError, RecursionError):
        # Never include remote content or a source file's bytes in diagnostics.
        print("review evidence: invalid or unavailable input", file=sys.stderr)
        return 2
    print(json.dumps(output, ensure_ascii=False, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

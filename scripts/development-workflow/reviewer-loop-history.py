#!/usr/bin/env python3
"""Reconcile immutable reviewer-loop snapshots without changing entry objects."""
import collections
import json
import re
import sys

HEADER = "### Automated Reviewer Loop Summary"
FOOTER = "*Posted automatically by `pr-review-loop.sh`.*"
MARKER = "<!-- reviewer-loop-history:v1 -->"
SCHEMA = "reviewer_loop_history.v1"
BLOCK = re.compile(re.escape(MARKER) + r"\s*```json\s*\n(.*?)\n```", re.S)
UUID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}")
HEAD = re.compile(r"[0-9a-f]{40}")


def reconcile(pages):
    comments = []
    for page in pages:
        if not isinstance(page, list) or any(
                not isinstance(c, dict) or not isinstance(c.get("body"), str) for c in page):
            raise ValueError("invalid comment page")
        comments.extend(page)
    summaries = sorted((c for c in comments
                        if isinstance(c.get("body"), str)
                        and c["body"].startswith(HEADER + "\n")
                        and FOOTER in c["body"]),
                       key=lambda c: (c.get("created_at", ""), int(c.get("id", 0))))
    if not summaries:
        return {"id": "", "body": ""}
    latest = summaries[-1]
    entries, multiplicities, sources = [], collections.Counter(), []
    unavailable, bindings = False, {}
    payload = None
    for comment in summaries:
        body = comment["body"]
        if MARKER not in body:
            continue  # Pre-ledger summaries retain their existing zero-count semantics.
        sources.append(comment.get("id"))
        matches = list(BLOCK.finditer(body))
        try:
            data = json.loads(matches[-1].group(1)) if matches else None
            if (not isinstance(data, dict) or data.get("schema") != SCHEMA
                    or not isinstance(data.get("entries"), list)
                    or any(not isinstance(e, dict) for e in data["entries"])):
                raise ValueError("invalid history")
            if data.get("history_status", "available") != "available":
                unavailable = True
            # Exact objects are immutable. Keep the maximum multiplicity from
            # any snapshot, so copied prefixes do not multiply entries and
            # repeated identical objects within an original block survive.
            seen = collections.Counter()
            for entry in data["entries"]:
                if "local_review_retry_attempt" in entry:
                    attempt = entry["local_review_retry_attempt"]
                    if (not isinstance(attempt, dict)
                            or not isinstance(attempt.get("id"), str)
                            or not UUID.fullmatch(attempt["id"])
                            or not isinstance(attempt.get("head_sha"), str)
                            or not HEAD.fullmatch(attempt["head_sha"])
                            or not isinstance(attempt.get("run_id"), str)
                            or not attempt["run_id"]
                            or attempt["run_id"] != entry.get("run_id")
                            or attempt["head_sha"] != (entry.get("classification_head") if entry.get("classification_head") is not None else entry.get("head_sha"))):
                        unavailable = True
                    else:
                        binding = (attempt["head_sha"], attempt["run_id"])
                        if bindings.setdefault(attempt["id"], binding) != binding:
                            unavailable = True
                key = json.dumps(entry, sort_keys=True, separators=(",", ":"))
                seen[key] += 1
                if seen[key] > multiplicities[key]:
                    entries.append(entry)
                    multiplicities[key] = seen[key]
            payload = data
        except (ValueError, IndexError):
            unavailable = True
    if payload is None and not sources:
        return {"id": latest.get("id", ""), "body": latest["body"]}
    payload = dict(payload or {"schema": SCHEMA})
    payload.update(entries=entries, reconciled_comment_ids=sources)
    if unavailable:
        payload.update(history_status="unavailable",
                       history_unavailable_reason="reconciliation_unavailable")
    rendered = MARKER + "\n```json\n" + json.dumps(payload, ensure_ascii=False) + "\n```"
    body = latest["body"]
    matches = list(BLOCK.finditer(body))
    if matches:
        match = matches[-1]
        body = body[:match.start()] + rendered + body[match.end():]
    else:
        body += "\n" + rendered + "\n"
    return {"id": latest.get("id", ""), "body": body}


def main():
    # gh --paginate emits multiple top-level JSON arrays, not one slurped array.
    raw, decoder, pages = sys.stdin.read(), json.JSONDecoder(), []
    while raw.strip():
        raw = raw.lstrip()
        page, end = decoder.raw_decode(raw)
        pages.append(page)
        raw = raw[end:]
    if not pages:
        raise ValueError("missing comment pages")
    print(json.dumps(reconcile(pages), ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, TypeError, KeyError):
        print("review history: reconciliation unavailable", file=sys.stderr)
        sys.exit(1)

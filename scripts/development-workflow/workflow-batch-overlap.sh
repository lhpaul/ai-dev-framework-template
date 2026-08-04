#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/development-workflow/workflow-batch-overlap.sh --input <json-file> [--decision-file <jsonl-file>] [--json]

Classifies pairwise implementation overlap for batch proposals from a
provider-neutral item snapshot. The helper is read-only and performs no tracker,
GitHub, branch, label, or filesystem mutations.
EOF
}

input_file=""
decision_file=""
json_output=0

require_value() {
  local option="$1"
  if [ "$#" -lt 2 ] || [ -z "${2:-}" ] || [ "${2#--}" != "$2" ]; then
    echo "$option requires a value." >&2
    usage >&2
    exit 64
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --input)
      require_value "$@"
      input_file="$2"
      shift 2
      ;;
    --decision-file)
      require_value "$@"
      decision_file="$2"
      shift 2
      ;;
    --json)
      json_output=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

if [ -z "$input_file" ]; then
  echo "ERROR: --input is required." >&2
  usage >&2
  exit 64
fi

python3 - "$input_file" "$decision_file" "$json_output" <<'PYEOF'
import hashlib
import json
import re
import sys
from pathlib import PurePosixPath

input_file, decision_file, json_output = sys.argv[1], sys.argv[2], sys.argv[3] == "1"

IMPLEMENTATION_ACTIONS = {"implement", "resolve-development-pr"}
PRIORITY_RANK = {"urgent": 0, "high": 1, "normal": 2, "medium": 2, "low": 3}
GENERIC_TERMS = {
    "workflow",
    "review",
    "reviewer",
    "batch",
    "item",
    "plan",
    "implementation",
    "development",
    "feature",
    "fix",
    "fallback",
    "protocol",
}


def fail(message: str, code: int = 1) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(code)


def load_json_file(path: str) -> dict:
    try:
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except FileNotFoundError:
        fail(f"input file not found: {path}")
    except json.JSONDecodeError as error:
        fail(f"input file is not valid JSON: {path}: {error}")
    if not isinstance(data, dict):
        fail("input JSON must be an object")
    return data


def stable_json(value) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def sha256(value) -> str:
    return "sha256:" + hashlib.sha256(stable_json(value).encode("utf-8")).hexdigest()


def normalize_id(value) -> str:
    text = str(value or "").strip()
    if not text:
      fail("each item requires a non-empty id")
    return text


def normalize_path(value: str) -> str:
    text = value.strip().strip("`'\"“”‘’.,;:)")
    text = text.replace("\\", "/")
    text = re.sub(r"^\./+", "", text)
    return str(PurePosixPath(text)).lower()


def normalize_route(value: str) -> str:
    text = value.strip().strip("`'\"“”‘’.,;)")
    text = re.sub(r"[?#].*$", "", text)
    if not text.startswith("/"):
        text = "/" + text
    text = re.sub(r"/+", "/", text)
    return text.rstrip("/") if text != "/" else text


def normalize_identifier(value: str) -> str:
    return value.strip().strip("`'\"“”‘’.,;:)(").replace("_", "-").lower()


def parse_file_set(value):
    if value is None:
        return []
    if isinstance(value, str):
        if value.strip().lower() in {"", "unknown", "none", "-"}:
            return []
        parts = re.split(r"[,;\n]", value)
    elif isinstance(value, list):
        parts = value
    else:
        return []
    normalized = []
    for part in parts:
        text = normalize_path(str(part))
        if text and text not in {"unknown", "none", "-"}:
            normalized.append(text)
    return sorted(set(normalized))


def add_signal(signals: set[tuple[str, str]], kind: str, value: str) -> None:
    value = value.strip()
    if not value:
        return
    if kind in {"function", "module"}:
        value = normalize_identifier(value)
        if value in GENERIC_TERMS or len(value) < 2:
            return
    elif kind == "route":
        value = normalize_route(value)
    elif kind == "file":
        value = normalize_path(value)
        if "/" not in value and "." not in value:
            return
    signals.add((kind, value))


def extract_signals(title: str, brief: str) -> list[dict]:
    text = f"{title or ''}\n{brief or ''}"
    signals: set[tuple[str, str]] = set()

    for match in re.finditer(r"(?<![A-Za-z0-9_./-])([A-Za-z0-9_.-]+(?:[\\/][A-Za-z0-9_.:@{}()[\\]-]+)+)", text):
        add_signal(signals, "file", match.group(1))

    for match in re.finditer(r"\b(?:GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)\s+(/[A-Za-z0-9_:@{}()[\].~!$&'*+,;=%/-]+)", text, re.I):
        add_signal(signals, "route", match.group(1))
    for match in re.finditer(r"(?<![A-Za-z0-9_])(/[A-Za-z0-9_:@{}()[\].~!$&'*+,;=%/-]+)", text):
        route = match.group(1)
        if "." not in route.rsplit("/", 1)[-1]:
            add_signal(signals, "route", route)

    for match in re.finditer(r"\b([A-Za-z_][A-Za-z0-9_]*)\s*\(\)", text):
        add_signal(signals, "function", match.group(1))
    for match in re.finditer(r"\b(?:function|method|resolver|handler)\s+[`'\"]?([A-Za-z_][A-Za-z0-9_]*)[`'\"]?", text, re.I):
        add_signal(signals, "function", match.group(1))

    module_cue = r"(?:module|package|component|helper|script|service)"
    for match in re.finditer(rf"\b{module_cue}\s+[`'\"]([^`'\"\n]+)[`'\"]", text, re.I):
        add_signal(signals, "module", match.group(1))
    for match in re.finditer(rf"\b{module_cue}\s+([A-Za-z][A-Za-z0-9_.-]{{2,}})", text, re.I):
        add_signal(signals, "module", match.group(1))

    return [{"type": kind, "value": value} for kind, value in sorted(signals)]


def signal_set(signals: list[dict]) -> set[tuple[str, str]]:
    return {(signal["type"], signal["value"]) for signal in signals}


def basename_without_ext(path: str) -> str:
    name = path.rstrip("/").rsplit("/", 1)[-1]
    return re.sub(r"\.[^.]+$", "", name).lower()


def related_signals(left: list[dict], right: list[dict]) -> list[dict]:
    related = []
    for l_signal in left:
        for r_signal in right:
            l_type, l_value = l_signal["type"], l_signal["value"]
            r_type, r_value = r_signal["type"], r_signal["value"]
            if l_type == r_type == "route":
                l_route = l_value.rstrip("/")
                r_route = r_value.rstrip("/")
                if l_route != r_route and (l_route.startswith(r_route + "/") or r_route.startswith(l_route + "/")):
                    related.append({"left": l_signal, "right": r_signal, "reason": "one route is a parent of the other"})
            elif {l_type, r_type} == {"file", "module"}:
                file_value = l_value if l_type == "file" else r_value
                module_value = l_value if l_type == "module" else r_value
                base = basename_without_ext(file_value)
                if base and (base == module_value or base in module_value or module_value in base):
                    related.append({"left": l_signal, "right": r_signal, "reason": "module signal is related to a path basename"})
    return related


def pair_id(left_id: str, right_id: str) -> str:
    return "--".join(sorted([left_id, right_id]))


def item_sort_key(item: dict):
    priority = PRIORITY_RANK.get(str(item.get("priority", "")).lower(), 2)
    created = str(item.get("createdAt") or item.get("created_at") or "")
    branch = str(item.get("branch") or item.get("branchName") or item.get("branch_name") or item["id"])
    return (priority, created, branch, item["id"])


def classify_pair(left: dict, right: dict) -> dict:
    pair = pair_id(left["id"], right["id"])
    shared_files = sorted(set(left["planFiles"]) & set(right["planFiles"]))
    left_signals = left["signals"]
    right_signals = right["signals"]
    shared_signals = [{"type": kind, "value": value} for kind, value in sorted(signal_set(left_signals) & signal_set(right_signals))]
    related = related_signals(left_signals, right_signals)
    has_plan_evidence = bool(left["planFiles"] or right["planFiles"])

    if shared_files:
        classification = "concrete"
        source = "plan"
        explanation = "Plan-derived file sets intersect exactly."
        evidence = {"sharedFiles": shared_files}
    elif shared_signals:
        classification = "concrete"
        source = "brief"
        explanation = "Brief-derived typed implementation targets match exactly."
        evidence = {"sharedSignals": shared_signals}
    elif related:
        classification = "suspected"
        source = "mixed" if has_plan_evidence else "brief"
        explanation = "Brief-derived targets are related but not identical."
        evidence = {"relatedSignals": related}
    elif has_plan_evidence and (left_signals or right_signals):
        classification = "suspected"
        source = "mixed"
        explanation = "Plan-derived and brief-derived evidence do not prove independence; require pair-scoped disposition."
        evidence = {"leftSignals": left_signals, "rightSignals": right_signals}
    else:
        classification = "no_actionable_overlap"
        source = "none"
        explanation = "No actionable overlap found; this is not proof of independence."
        evidence = {"leftSignals": left_signals, "rightSignals": right_signals}

    requires_confirmation = classification == "suspected"
    default_dispatch = "serial" if classification in {"concrete", "suspected"} else "parallel_eligible"
    required_next_action = (
        "serialize_pair_until_prior_item_merges"
        if classification == "concrete"
        else "require_pair_scoped_parallel_decision_or_serialize"
        if classification == "suspected"
        else "continue_other_gates"
    )
    evidence_hash = sha256({
        "pairId": pair,
        "classification": classification,
        "source": source,
        "evidence": evidence,
        "explanation": explanation,
    })

    return {
        "pairId": pair,
        "itemIds": [left["id"], right["id"]],
        "classification": classification,
        "source": source,
        "confidence": "high" if classification == "concrete" else "medium" if classification == "suspected" else "none",
        "signals": evidence,
        "explanation": explanation,
        "defaultDispatch": default_dispatch,
        "confirmationRequired": requires_confirmation,
        "requiredNextAction": required_next_action,
        "evidenceHash": evidence_hash,
        "decision": {"status": "not_required" if not requires_confirmation else "missing"},
    }


def load_decisions(path: str) -> list[dict]:
    if not path:
        return []
    decisions = []
    try:
        with open(path, "r", encoding="utf-8") as handle:
            for line_number, line in enumerate(handle, 1):
                line = line.strip()
                if not line:
                    continue
                try:
                    value = json.loads(line)
                except json.JSONDecodeError:
                    decisions.append({"status": "invalid_json", "line": line_number})
                    continue
                if isinstance(value, dict):
                    decisions.append(value)
    except FileNotFoundError:
        return []
    return decisions


def apply_decisions(pairs: list[dict], batch_fingerprint: str, decisions: list[dict]) -> list[dict]:
    stale = []
    for pair in pairs:
        if pair["classification"] != "suspected":
            continue
        accepted = None
        for decision in decisions:
            if decision.get("status") == "invalid_json":
                stale.append(decision)
                continue
            normalized_pair = pair_id(str(decision.get("itemIds", ["", ""])[0]), str(decision.get("itemIds", ["", ""])[1])) if isinstance(decision.get("itemIds"), list) and len(decision.get("itemIds")) == 2 else str(decision.get("pairId", ""))
            if normalized_pair != pair["pairId"]:
                continue
            if decision.get("batchFingerprint") != batch_fingerprint:
                stale.append({**decision, "status": "stale_batch"})
                continue
            if decision.get("evidenceHash") != pair["evidenceHash"]:
                stale.append({**decision, "status": "stale_evidence"})
                continue
            if decision.get("decision") not in {"allow_parallel", "serialize"}:
                stale.append({**decision, "status": "invalid_decision"})
                continue
            instruction = str(decision.get("recordedHumanInstruction", decision.get("instruction", ""))).strip()
            if decision.get("decision") == "allow_parallel" and not instruction:
                stale.append({**decision, "status": "missing_human_instruction"})
                continue
            accepted = decision
        if accepted:
            pair["decision"] = {
                "status": "accepted",
                "decision": accepted["decision"],
                "recordedInstruction": str(accepted.get("recordedHumanInstruction", accepted.get("instruction", ""))).strip(),
            }
            if accepted["decision"] == "allow_parallel":
                pair["defaultDispatch"] = "parallel_eligible"
                pair["requiredNextAction"] = "continue_other_gates_with_pair_decision"
            else:
                pair["defaultDispatch"] = "serial"
        else:
            pair["decision"] = {"status": "missing", "decision": "serialize"}
    return stale


def serial_groups(items_by_id: dict, pairs: list[dict]) -> list[dict]:
    parent = {item_id: item_id for item_id in items_by_id}

    def find(value):
        while parent[value] != value:
            parent[value] = parent[parent[value]]
            value = parent[value]
        return value

    def union(left, right):
        l_root, r_root = find(left), find(right)
        if l_root != r_root:
            parent[r_root] = l_root

    serial_pairs = [
        pair for pair in pairs
        if pair["defaultDispatch"] == "serial" and pair["classification"] in {"concrete", "suspected"}
    ]
    for pair in serial_pairs:
        union(pair["itemIds"][0], pair["itemIds"][1])

    grouped: dict[str, list[str]] = {}
    for pair in serial_pairs:
        for item_id in pair["itemIds"]:
            grouped.setdefault(find(item_id), [])
    for item_id in parent:
        root = find(item_id)
        if root in grouped:
            grouped[root].append(item_id)

    groups = []
    for group_items in grouped.values():
        unique_items = sorted(set(group_items), key=lambda item_id: item_sort_key(items_by_id[item_id]))
        group_pairs = [pair["pairId"] for pair in serial_pairs if set(pair["itemIds"]).issubset(set(unique_items))]
        if len(unique_items) > 1:
            groups.append({
                "groupId": "--".join(unique_items),
                "itemIds": unique_items,
                "keepItemId": unique_items[0],
                "heldItemIds": unique_items[1:],
                "pairs": sorted(group_pairs),
                "reason": "brief/plan overlap serialization; held items start after the prior item merges into the approved base",
            })
    return sorted(groups, key=lambda group: group["groupId"])


data = load_json_file(input_file)
raw_items = data.get("items")
if not isinstance(raw_items, list) or not raw_items:
    fail("input JSON requires a non-empty items array")

items = []
seen = set()
for raw in raw_items:
    if not isinstance(raw, dict):
        fail("each item must be an object")
    item_id = normalize_id(raw.get("id"))
    if item_id in seen:
        fail(f"duplicate item id: {item_id}")
    seen.add(item_id)
    next_action = str(raw.get("nextAction") or raw.get("next_action") or "").strip()
    if not next_action:
        fail(f"item {item_id} requires nextAction")
    item = {
        "id": item_id,
        "title": str(raw.get("title") or ""),
        "brief": str(raw.get("brief") or raw.get("description") or ""),
        "priority": str(raw.get("priority") or "Normal"),
        "createdAt": str(raw.get("createdAt") or raw.get("created_at") or ""),
        "branch": str(raw.get("branch") or raw.get("branchName") or raw.get("branch_name") or ""),
        "nextAction": next_action,
        "planFiles": parse_file_set(raw.get("fileSet", raw.get("file_set"))),
    }
    item["signals"] = extract_signals(item["title"], item["brief"])
    items.append(item)

implementation_items = [item for item in items if item["nextAction"] in IMPLEMENTATION_ACTIONS]
items_by_id = {item["id"]: item for item in implementation_items}
batch_fingerprint = sha256({
    "items": [
        {
            "id": item["id"],
            "title": item["title"],
            "brief": item["brief"],
            "fileSet": item["planFiles"],
            "priority": item["priority"],
            "createdAt": item["createdAt"],
            "branch": item["branch"],
            "nextAction": item["nextAction"],
        }
        for item in sorted(implementation_items, key=lambda item: item["id"])
    ]
})

pairs = []
sorted_items = sorted(implementation_items, key=lambda item: item["id"])
for left_index, left in enumerate(sorted_items):
    for right in sorted_items[left_index + 1:]:
        pairs.append(classify_pair(left, right))

stale_decisions = apply_decisions(pairs, batch_fingerprint, load_decisions(decision_file))
groups = serial_groups(items_by_id, pairs)
result = {
    "batchFingerprint": batch_fingerprint,
    "itemCount": len(implementation_items),
    "pairs": pairs,
    "serialGroups": groups,
    "staleDecisions": stale_decisions,
    "readOnlyGuarantee": "No tracker reads, tracker writes, GitHub calls, branch changes, labels, comments, files, or dispatch state were mutated.",
}

if json_output:
    print(json.dumps(result, indent=2, sort_keys=True))
else:
    print(f"BATCH_FINGERPRINT={batch_fingerprint}")
    print(f"PAIR_COUNT={len(pairs)}")
    print(f"SERIAL_GROUP_COUNT={len(groups)}")
    for pair in pairs:
        print(f"PAIR={pair['pairId']}")
        print(f"PAIR_CLASSIFICATION={pair['classification']}")
        print(f"PAIR_SOURCE={pair['source']}")
        print(f"PAIR_DEFAULT_DISPATCH={pair['defaultDispatch']}")
        print(f"PAIR_EVIDENCE_HASH={pair['evidenceHash']}")
    for group in groups:
        print(f"SERIAL_GROUP={group['groupId']}")
        print(f"SERIAL_GROUP_KEEP={group['keepItemId']}")
        print(f"SERIAL_GROUP_HELD={','.join(group['heldItemIds'])}")
PYEOF

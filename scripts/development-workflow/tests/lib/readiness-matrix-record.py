#!/usr/bin/env python3
"""Record only hashes/expected tuples from synthetic test producer inputs."""
import hashlib
import json
import os
from pathlib import Path

state = {key: value for key, value in os.environ.items()
         if key.startswith("MOCK_") or key == "PR_AGENT_BOT_LOGIN"}
for key in ("MOCK_GH_LOG", "MOCK_CALL_LOG", "MOCK_LABEL_STATE", "MOCK_TMP_ROOT"):
    state.pop(key, None)
row = {
    "index": int(os.environ["READINESS_RECORD_INDEX"]),
    "name": os.environ["READINESS_RECORD_NAME"],
    "expected": os.environ["READINESS_RECORD_EXPECTED"],
    "reason": os.environ["READINESS_RECORD_REASON"],
    "classifier": os.environ["READINESS_RECORD_CLASSIFIER"],
    "body_sha256": hashlib.sha256(os.environ["READINESS_RECORD_BODY"].encode()).hexdigest(),
    "producer_sha256": hashlib.sha256(json.dumps(state, sort_keys=True).encode()).hexdigest(),
}
with open(os.environ["READINESS_MATRIX_RECORD_FILE"], "a", encoding="utf-8") as stream:
    stream.write(json.dumps(row, sort_keys=True) + "\n")
# The two adjacent positive-write assertions inspect this same producer's log.
if row["expected"] == "labeled":
    Path(os.environ["MOCK_GH_LOG"]).write_text("add-label ready-for-human-review\n")
print("RESULT=" + row["expected"])

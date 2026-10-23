#!/usr/bin/env python3
"""Check the expanded original expected tuples and actual producer inputs."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--part", type=int, choices=range(1, 5))
    args = parser.parse_args()
    tests = Path(__file__).resolve().parent
    manifest = json.loads((tests / "lib/readiness-label-matrix-manifest.json").read_text())
    # Probe the same PATH-resolved child interpreter that runs every wrapper.
    bash_version = subprocess.check_output(
        ["bash", "-c", 'printf "%s.%s" "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}"'],
        text=True,
    )
    parts = [args.part] if args.part else range(1, 5)
    for context in ("standalone", "consumer"):
        records = []
        adjacent = []
        for part in parts:
            with tempfile.TemporaryDirectory() as temporary:
                record_file = Path(temporary) / "cases.jsonl"
                env = dict(os.environ, READINESS_MATRIX_RECORD_FILE=str(record_file))
                name = ("test-readiness-label-matrix-part-" if context == "standalone"
                        else "test-consumer-readiness-matrix-part-") + str(part) + ".sh"
                child = subprocess.Popen(["bash", str(tests / name)], env=env,
                                         stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                         text=True, start_new_session=True)
                try:
                    output, _ = child.communicate(timeout=120)
                except subprocess.TimeoutExpired:
                    os.killpg(child.pid, signal.SIGKILL)
                    child.communicate()
                    raise AssertionError("partition inventory timeout") from None
                assert child.returncode == 0, "partition inventory rejected"
                rows = [json.loads(line) for line in record_file.read_text().splitlines()]
                expected_indices = list(range(part, 565, 4))
                assert [row["index"] for row in rows] == expected_indices, "partition membership/order changed"
                for row in rows:
                    digest = hashlib.sha256(json.dumps(row, sort_keys=True).encode()).hexdigest()
                    expected_digest = manifest["case_tuple_sha256"][row["index"] - 1]
                    if bash_version == "3.2":
                        expected_digest = manifest["bash32_original_case_tuple_sha256"].get(
                            str(row["index"]), expected_digest)
                    assert digest == expected_digest, "fixture/body/expectation/producer state changed"
                records.extend(rows)
                adjacent.extend(line[6:] for line in output.splitlines()
                                if line.startswith("PASS: 1946_conservative_html"))
                assert not any(line.startswith("FAIL:") for line in output.splitlines()), "adjacent assertion failed"
        indices = [row["index"] for row in records]
        assert len(indices) == len(set(indices)), "duplicate fixture execution"
        expected_adjacent = sorted(name for index, name in manifest["adjacent_assertions"].items()
                                   if (int(index) - 1) % 4 + 1 in parts)
        assert sorted(adjacent) == expected_adjacent, "adjacent positive-write controls changed"
        print("PASS: " + context + " partition tuples/state/order/adjacent controls")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

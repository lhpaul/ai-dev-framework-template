#!/usr/bin/env python3
"""Remove ONLY the `validate` job's fork guard from a copy of the workflow.

The point of planting it this narrowly: the file-global assertion cannot see
this change, because `resolve-targets` still carries a guard. That is exactly
why the job-scoped assertion exists, and a proof that removed both guards would
not have demonstrated it.

Operates on the path given, which must always be a COPY — never the shipped
workflow.
"""
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
start = text.index("\n  validate:\n")
head, tail = text[:start], text[start:]
tail, count = re.subn(r"\n    if: >-\n(?:      [^\n]*\n)+", "\n", tail, count=1)
if count != 1:
    sys.stderr.write("expected exactly one `if: >-` block in the validate job\n")
    sys.exit(3)
path.write_text(head + tail, encoding="utf-8")

#!/usr/bin/env python3
"""Extract the fan-out selection program from closing-keyword-scope.yml.

The suite executes the program the workflow ships rather than a copy of it: a
copy would keep passing after the workflow regressed, which is the whole reason
the #1593 suite extracts its recipes from the protocols instead of restating
them.

This lives in a file rather than inline in the suite because the program it
hunts for is itself full of quotes, and nesting those through a shell heredoc
is how quoting bugs get written.
"""
import re
import sys
from pathlib import Path

OPEN = "jq -r --arg issue \"$issue\" --arg self \"$PR_NUMBER\" '"
CLOSE = "' 2>/dev/null"

text = Path(sys.argv[1]).read_text(encoding="utf-8")
try:
    start = text.index(OPEN) + len(OPEN)
    end = text.index(CLOSE, start)
except ValueError:
    sys.stderr.write("could not find the fan-out jq program in the workflow\n")
    sys.exit(3)
sys.stdout.write(text[start:end])

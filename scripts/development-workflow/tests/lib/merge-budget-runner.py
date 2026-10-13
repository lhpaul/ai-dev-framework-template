#!/usr/bin/env python3
"""Partition the complete merge-budget regression enumeration for CI suites."""
import argparse
import importlib.util
from pathlib import Path
import os
import sys
import unittest

sys.dont_write_bytecode = True
PARTITIONS = 8


def names(suite):
    for test in suite:
        if isinstance(test, unittest.TestSuite):
            yield from names(test)
        else:
            yield test.id().split('.', 1)[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--partition', type=int, choices=range(PARTITIONS))
    mode.add_argument('--all', action='store_true', help='serial full run, including shared evidence output')
    args = parser.parse_args()
    path = Path(__file__).resolve().parents[1] / 'test_workflow_merge_budget.py'
    spec = importlib.util.spec_from_file_location('budget_tests', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    tests = sorted(names(unittest.defaultTestLoader.loadTestsFromModule(module)))
    groups = [tests[index::PARTITIONS] for index in range(PARTITIONS)]
    if not tests or len(tests) != len(set(tests)) or sorted(sum(groups, [])) != tests:
        parser.error('regression enumeration must be nonempty, unique and fully partitioned')
    selected = tests if args.all else groups[args.partition]
    print('TEST_COUNT=' + str(len(tests)))
    print('PARTITION_COUNT=' + str(PARTITIONS))
    print('PARTITION=' + ('all' if args.all else str(args.partition)))
    print('SELECTED_TEST_COUNT=' + str(len(selected)))
    for name in selected:
        print('TEST_ID=' + name)
    sys.stdout.flush()
    if not selected:
        return 0
    # unittest runs every selected case and returns failure if any case fails.
    # Replace this process so the CI supervisor owns the entire test lifetime.
    os.execv(sys.executable, [sys.executable, str(path), '-v', *selected])


if __name__ == '__main__':
    sys.exit(main())

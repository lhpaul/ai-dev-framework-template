#!/usr/bin/env python3
"""Read-only My Machines hub preflight and current-run evidence verifier."""

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import subprocess
import sys
import uuid

sys.dont_write_bytecode = True
SCRIPT_DIR = Path(__file__).resolve().parent
RESOLVER = SCRIPT_DIR / "workflow-config-resolver.py"
TIMEOUT_SECONDS = 20
SLUG = re.compile(r"^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+$")
HEX = re.compile(r"^[0-9a-f]{64}$")


class Failure(Exception):
    def __init__(self, check, guidance, ordinal=None):
        super().__init__(check)
        self.check, self.guidance, self.ordinal = check, guidance, ordinal


def fail(check, guidance, ordinal=None):
    raise Failure(check, guidance, ordinal)


def digest(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def command(args, check, guidance, ordinal=None, github=False):
    env = os.environ.copy()
    env.update({"GIT_TERMINAL_PROMPT": "0", "GH_PROMPT_DISABLED": "1", "PYTHONDONTWRITEBYTECODE": "1"})
    if github:
        env["GH_HOST"] = "github.com"
    try:
        result = subprocess.run(args, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=TIMEOUT_SECONDS, env=env,
                                check=False, text=True, encoding="utf-8")
    except (OSError, subprocess.TimeoutExpired, UnicodeError, ValueError):
        fail(check, guidance, ordinal)
    if result.returncode:
        fail(check, guidance, ordinal)
    return result.stdout


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key")
        result[key] = value
    return result


def decode(raw, expected_type, check, guidance, ordinal=None):
    try:
        value = json.loads(raw, object_pairs_hook=unique_object)
    except (ValueError, TypeError):
        fail(check, guidance, ordinal)
    if not isinstance(value, expected_type):
        fail(check, guidance, ordinal)
    return value


def root(path, check, ordinal=None):
    guidance = "Select an existing non-bare Git checkout root and retry."
    if not isinstance(path, str) or not path.strip():
        fail(check, guidance, ordinal)
    try:
        physical = Path(path).resolve(strict=True)
        if not physical.is_dir():
            fail(check, guidance, ordinal)
    except (OSError, RuntimeError, ValueError):
        fail(check, guidance, ordinal)
    actual = command(["git", "-C", str(physical), "rev-parse", "--show-toplevel"], check, guidance, ordinal).strip()
    bare = command(["git", "-C", str(physical), "rev-parse", "--is-bare-repository"], check, guidance, ordinal).strip()
    try:
        if bare != "false" or Path(actual).resolve(strict=True) != physical:
            fail(check, guidance, ordinal)
    except (OSError, RuntimeError, ValueError):
        fail(check, guidance, ordinal)
    return physical


def resolver(hub, action, ordinal=None, name=None):
    args = [sys.executable, str(RESOLVER), action, "--repo-root", str(hub), "--json"]
    if name is not None:
        args.extend(["--repo=" + name, "--require-local"])
    raw = command(args, "configuration", "Correct the hub product configuration and local mappings, then retry.", ordinal)
    return decode(raw, list if action == "list-product-repos" else dict, "configuration",
                  "Correct the hub product configuration and local mappings, then retry.", ordinal)


def identity(url, normalize, check, ordinal=None):
    slug = normalize(url)
    if not isinstance(slug, str) or not SLUG.fullmatch(slug):
        fail(check, "Configure a supported GitHub origin without credentials and retry.", ordinal)
    return slug.lower()


def origin(path, normalize, check, ordinal=None):
    raw = command(["git", "-C", str(path), "remote", "get-url", "origin"], check,
                  "Configure a supported GitHub origin without credentials and retry.", ordinal)
    return identity(raw.strip(), normalize, check, ordinal)


def configuration(hub_arg, worker_arg=None):
    hub = root(hub_arg, "hub_directory")
    if worker_arg is not None and root(worker_arg, "worker_directory") != hub:
        fail("worker_directory", "Select the same hub checkout as the worker directory and retry.")
    mode = resolver(hub, "mode")
    if mode.get("WORKFLOW_MODE") != "workflow_hub":
        fail("configuration", "Select a configured workflow hub checkout and retry.")
    names = resolver(hub, "list-product-repos")
    if not names or any(not isinstance(name, str) or not name for name in names) or len(names) != len(set(names)):
        fail("configuration", "Configure at least one uniquely named product and retry.")
    # Reuse the shipped normalizer; the stricter slug grammar above is a separate safety check.
    try:
        normalize = runpy.run_path(str(RESOLVER), run_name="worker_resolver")["github_repo_from_url"]
    except (OSError, ImportError, KeyError, SyntaxError):
        fail("configuration", "Restore the workflow resolver and retry.")
    hub_slug = origin(hub, normalize, "hub_origin")
    products = []
    for ordinal, name in enumerate(names, 1):
        context = resolver(hub, "validate", ordinal, name)
        local = context.get("TARGET_LOCAL_PATH")
        configured = context.get("TARGET_GITHUB_REPO")
        if not isinstance(local, str) or not local or not isinstance(configured, str) or not SLUG.fullmatch(configured):
            fail("product_configuration", "Inspect this product's shared entry and local mapping privately, then retry.", ordinal)
        checkout = root(local, "product_checkout", ordinal)
        configured = configured.lower()
        if origin(checkout, normalize, "product_origin", ordinal) != configured:
            fail("product_origin", "Correct this product checkout's GitHub origin and retry.", ordinal)
        products.append({"name": name, "repo": configured, "path_id": digest(str(checkout)), "ordinal": ordinal})
    tuples = sorted((p["name"], p["repo"], p["path_id"]) for p in products)
    config_id = digest(json.dumps(tuples, ensure_ascii=True, separators=(",", ":")))
    return hub, hub_slug, products, config_id


def utc(value):
    if not isinstance(value, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z", value):
        fail("timestamp", "Provide unambiguous UTC timestamps for this run and retry.")
    try:
        return dt.datetime.fromisoformat(value[:-1] + "+00:00")
    except ValueError:
        fail("timestamp", "Provide unambiguous UTC timestamps for this run and retry.")


def run_id(value):
    try:
        if str(uuid.UUID(value)) != value:
            raise ValueError
    except (ValueError, TypeError, AttributeError):
        fail("run_id", "Provide a canonical UUID for this run and retry.")
    return value


def github_probe(slug, ordinal=None):
    raw = command(["gh", "repo", "view", "github.com/" + slug, "--json", "nameWithOwner"],
                  "github_access", "Check the worker's GitHub repository access and retry.", ordinal, github=True)
    result = decode(raw, dict, "github_access", "Check the worker's GitHub repository access and retry.", ordinal)
    value = result.get("nameWithOwner")
    if not isinstance(value, str) or value.lower() != slug:
        fail("github_access", "Check the worker's GitHub repository access and retry.", ordinal)


def preflight(args, invoked_at):
    rid = run_id(args.run_id)
    hub, hub_slug, products, config_id = configuration(args.hub_dir, args.worker_dir)
    command(["gh", "auth", "status", "--hostname", "github.com"], "github_auth",
            "Authenticate the worker for github.com and retry.", github=True)
    github_probe(hub_slug)
    for product in products:
        github_probe(product["repo"], product["ordinal"])
    return {"schema": "hub_worker_preflight.v1", "result": "pass", "run_id": rid,
            "started_at": invoked_at.isoformat().replace("+00:00", "Z"),
            "checked_at": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
            "hub_repo_id": digest(hub_slug), "hub_checkout_id": digest(str(hub)),
            "config_id": config_id, "worker": "pass", "hub_github": "pass",
            "products": [{"product_id": digest(p["name"]), "repo_id": digest(p["repo"]),
                          "checkout": "pass", "github": "pass"} for p in products]}


def verify(args):
    rid = run_id(args.run_id)
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z", args.hub_selected_at):
        fail("timestamp", "Record hub selection in UTC with microsecond precision and retry.")
    start, selected = utc(args.run_start), utc(args.hub_selected_at)
    try:
        with open(args.result_file, encoding="utf-8") as stream:
            evidence = json.load(stream, object_pairs_hook=unique_object)
    except (OSError, ValueError, UnicodeError):
        fail("result", "Provide the current successful preflight result and retry.")
    keys = {"schema", "result", "run_id", "started_at", "checked_at", "hub_repo_id", "hub_checkout_id",
            "config_id", "worker", "hub_github", "products"}
    if not isinstance(evidence, dict) or set(evidence) != keys:
        fail("result", "Provide a complete current preflight result and retry.")
    checked = utc(evidence["checked_at"])
    invoked = utc(evidence["started_at"])
    now = dt.datetime.now(dt.timezone.utc)
    if not start <= selected <= invoked <= checked <= now:
        fail("timestamp", "Run preflight after selecting the hub for this run and retry.")
    if (evidence["schema"] != "hub_worker_preflight.v1" or evidence["result"] != "pass"
            or evidence["run_id"] != rid or evidence["worker"] != "pass" or evidence["hub_github"] != "pass"):
        fail("result", "Provide a successful result for this run and retry.")
    entries = evidence["products"]
    if not isinstance(entries, list) or not entries:
        fail("result", "Provide all product outcomes and retry.")
    actual = []
    for entry in entries:
        if (not isinstance(entry, dict) or set(entry) != {"product_id", "repo_id", "checkout", "github"}
                or not isinstance(entry["product_id"], str) or not HEX.fullmatch(entry["product_id"])
                or not isinstance(entry["repo_id"], str) or not HEX.fullmatch(entry["repo_id"])
                or entry["checkout"] != "pass" or entry["github"] != "pass"):
            fail("result", "Provide complete successful product outcomes and retry.")
        actual.append((entry["product_id"], entry["repo_id"]))
    if len({p[0] for p in actual}) != len(actual):
        fail("result", "Provide unique product outcomes and retry.")
    hub, hub_slug, products, config_id = configuration(args.hub_dir)
    expected = [(digest(p["name"]), digest(p["repo"])) for p in products]
    if (evidence["hub_repo_id"] != digest(hub_slug) or evidence["hub_checkout_id"] != digest(str(hub))
            or evidence["config_id"] != config_id or sorted(actual) != sorted(expected)):
        fail("result", "Run preflight again for the selected hub and current configuration.")
    return {"schema": "hub_worker_preflight_verification.v1", "result": "pass"}


class SafeArgumentParser(argparse.ArgumentParser):
    def error(self, message):
        self.exit(2, "ERROR: invalid or missing arguments; see --help.\n")


def main():
    invoked_at = dt.datetime.now(dt.timezone.utc)
    parser = SafeArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    for action in ("check", "verify"):
        p = sub.add_parser(action)
        p.add_argument("--hub-dir", required=True)
        p.add_argument("--run-id", required=True)
        if action == "check":
            p.add_argument("--worker-dir", required=True)
        else:
            p.add_argument("--result-file", required=True)
            p.add_argument("--run-start", required=True)
            p.add_argument("--hub-selected-at", required=True)
    args = parser.parse_args()
    try:
        result = preflight(args, invoked_at) if args.action == "check" else verify(args)
    except Failure as error:
        result = {"schema": "hub_worker_preflight.v1", "result": "fail",
                  "check": error.check, "guidance": error.guidance}
        if error.ordinal is not None:
            result["product_ordinal"] = error.ordinal
        print(json.dumps(result, sort_keys=True))
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Invocation-scoped heuristic admission and durable merge recovery.

GitHub quota is not reserved. The journal protects execution bookkeeping only.
All external evidence is fetched by gh (or the existing trusted Linear bridge).
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import fcntl
from functools import cmp_to_key
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import time
import uuid

SCRIPT = Path(__file__).resolve().parent
SCHEMA = 1
TERMINAL = {"Deferred", "Waiting", "Interrupted", "Completed"}
PHASES = {"audit", "local_merge", "base_push", "merge_api", "merge_verify",
          "remote_delete", "local_cleanup", "issue_close", "tracker", "cleanup",
          "recheck", "hold", "policy_skip"}


PR_QUERY = """query MergeBudgetPR($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      number state headRefName headRefOid baseRefName isInMergeQueue
      autoMergeRequest { enabledAt }
    }
  }
}"""


class Stop(RuntimeError):
    def __init__(self, reason, evidence=None):
        super().__init__(reason)
        self.evidence = evidence



def pairs(values):
    result = {}
    for key, value in values:
        if key in result:
            raise Stop("duplicate JSON key: " + key)
        result[key] = value
    return result


def decode(text):
    try:
        return json.loads(text, object_pairs_hook=pairs,
                          parse_constant=lambda value: (_ for _ in ()).throw(Stop("nonfinite JSON")))
    except (ValueError, TypeError) as exc:
        raise Stop("unreadable JSON evidence") from exc


def call(argv, cwd=None, env=None):
    result = subprocess.run(argv, cwd=cwd, env=env, text=True, capture_output=True)
    if result.returncode:
        # Error wording is diagnostic, never an input to state classification.
        raise Stop("external evidence unavailable (exit %s)" % result.returncode, {"exitCode": result.returncode, "stderrPresent": bool(result.stderr), "source": Path(argv[0]).name})
    return result.stdout.strip()


def gh(*argv, cwd=None):
    result = subprocess.run(["gh", *map(str, argv)], cwd=cwd, text=True, capture_output=True)
    if result.returncode:
        evidence = {"exitCode": result.returncode, "stderrPresent": bool(result.stderr), "source": "gh"}
        try:
            parsed = decode(result.stdout)
            if isinstance(parsed, dict):
                for field in ("errors", "message", "status"):
                    if field in parsed:
                        evidence[field] = parsed[field]
        except Stop:
            pass
        raise Stop("external GitHub evidence unavailable", evidence)
    value = decode(result.stdout)
    if isinstance(value, dict) and value.get("errors"):
        raise Stop("partial/error GitHub evidence", {"errors": value["errors"]})
    return value


def integer(value, name, positive=False):
    if isinstance(value, str) and re.fullmatch(r"[0-9]+", value):
        value = int(value)
    if type(value) is not int or value < (1 if positive else 0):
        raise Stop("invalid " + name)
    return value


def repo(value):
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", value):
        raise Stop("unresolved repository identity")
    return value.lower()


def now():
    return datetime.now(timezone.utc).isoformat()



def timestamp(value):
    if not isinstance(value, str):
        raise Stop("provider observation time unavailable")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise Stop("malformed provider observation time") from exc
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise Stop("provider observation time must include UTC offset")
    return parsed.astimezone(timezone.utc)


def newer(observed, *cutoffs):
    try:
        value = timestamp(observed)
        return value <= datetime.now(timezone.utc) and all(value > timestamp(cutoff) for cutoff in cutoffs if cutoff)
    except Stop:
        return False


def root(path):
    return Path(call(["git", "-C", str(path), "rev-parse", "--show-toplevel"])).resolve()


def common(path):
    value = Path(call(["git", "-C", str(path), "rev-parse", "--git-common-dir"]))
    return (value if value.is_absolute() else Path(path) / value).resolve()


def config(path):
    spec = importlib.util.spec_from_file_location("merge_budget_config", SCRIPT / "workflow-config-resolver.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    try:
        shared, local, _, _ = module.load_configs(Path(path))
    except (ValueError, OSError, module.ConfigError) as exc:
        raise Stop("owning configuration unreadable") from exc
    return shared, local


def reserve(path, override):
    shared, local = config(path)
    selected = 1000
    for source in (shared, local):
        if "merge_budget" in source:
            section = source["merge_budget"]
            if not isinstance(section, dict):
                raise Stop("invalid merge_budget configuration")
            if "graphql_reserve" in section:
                selected = section["graphql_reserve"]
    if override is not None:
        selected = override
    return integer(selected, "resolved reserve")


def budget():
    response = gh("api", "rate_limit")
    resources = response.get("resources") if isinstance(response, dict) else None
    value = resources.get("graphql") if isinstance(resources, dict) else None
    if not isinstance(value, dict):
        raise Stop("GraphQL quota unavailable; REST core is not a substitute")
    readable = {k: value.get(k) for k in ("remaining", "reset", "limit")}
    for field in ("remaining", "reset", "limit"):
        if type(value.get(field)) is not int or value[field] < 0:
            raise Stop("malformed GraphQL quota " + field, readable)
    if value["limit"] <= 0 or value["remaining"] > value["limit"] or value["reset"] <= time.time():
        raise Stop("inconsistent GraphQL quota window", readable)
    return {**{k: value[k] for k in ("remaining", "reset", "limit")}, "observedAt": now()}



def checkout_repo(path):
    environment = dict(os.environ)
    environment.pop("GH_REPO", None)
    evidence = decode(call(["gh", "repo", "view", "--json", "nameWithOwner"], cwd=path, env=environment))
    if not isinstance(evidence, dict):
        raise Stop("checkout repository identity unavailable")
    return repo(evidence.get("nameWithOwner"))


def pr_read(target):
    owner, name = target["repo"].split("/")
    response = gh("api", "graphql", "-f", "owner=" + owner, "-f", "name=" + name,
                  "-F", "number=" + str(target["pr"]), "-f", "query=" + PR_QUERY)
    data = response.get("data") if isinstance(response, dict) else None
    repository = data.get("repository") if isinstance(data, dict) else None
    value = repository.get("pullRequest") if isinstance(repository, dict) else None
    if not isinstance(value, dict) or type(value.get("number")) is not int or value.get("number") != target["pr"] or value.get("state") not in {"OPEN", "CLOSED", "MERGED"}:
        raise Stop("PR live identity/state unavailable")
    if not isinstance(value.get("headRefName"), str) or not value["headRefName"] or not isinstance(value.get("headRefOid"), str) or not re.fullmatch(r"[0-9a-f]{40}", value["headRefOid"]):
        raise Stop("PR head identity unavailable")
    if "autoMergeRequest" not in value or type(value.get("isInMergeQueue")) is not bool or (value.get("autoMergeRequest") is not None and not isinstance(value["autoMergeRequest"], dict)):
        raise Stop("PR queue evidence unavailable")
    if isinstance(value.get("autoMergeRequest"), dict):
        timestamp(value["autoMergeRequest"].get("enabledAt"))
    if value.get("baseRefName") != target["base"]:
        raise Stop("selected PR base changed")
    if value["state"] != "MERGED" and value.get("headRefOid") != target["head"]:
        raise Stop("selected reviewed PR head changed")
    return value


def inspect(target, owner):
    argv = ["bash", str(SCRIPT / "post-merge-cleanup.sh"), "--inspect-targets",
            "--repo-root", str(owner), "--cleanup-repo-root", target["root"]]
    if common(owner) != common(target["root"]):
        resolver = str(SCRIPT / "workflow-config-resolver.py")
        names = decode(call([sys.executable, resolver, "list-product-repos", "--repo-root", str(owner), "--json"]))
        if not isinstance(names, list):
            raise Stop("owning hub product identities unavailable")
        matches = []
        for name in names:
            resolved = decode(call([sys.executable, resolver, "resolve", "--repo-root", str(owner), "--repo", name, "--json"]))
            if str(resolved.get("TARGET_GITHUB_REPO", "")).lower() == target["repo"].lower():
                matches.append(name)
        if len(matches) != 1:
            raise Stop("selected checkout has no unique owning hub product route")
        argv += ["--repo", matches[0]]
    environment = dict(os.environ)
    environment.pop("GH_REPO", None)
    environment.pop("WORKFLOW_TARGET_GITHUB_REPO", None)
    response = decode(call([*argv, "--pr", str(target["pr"]), "--base", target["base"], target["branch"]], env=environment))
    if not isinstance(response, dict) or not isinstance(response.get("issues"), list):
        raise Stop("owned cleanup target projection unavailable")
    for issue in response["issues"]:
        if isinstance(issue, dict) and issue.get("repo"):
            issue["repo"] = repo(issue["repo"])
    return response


RELEASE_ITEMS_QUERY = """query ReleaseBudgetItems($projectId: ID!, $after: String) {
  node(id: $projectId) {
    ... on ProjectV2 {
      items(first: 100, after: $after) {
        nodes {
          content { __typename ... on Issue { number repository { nameWithOwner } } }
          status: fieldValueByName(name: "Status") {
            ... on ProjectV2ItemFieldSingleSelectValue { name }
          }
        }
        pageInfo { hasNextPage endCursor }
      }
    }
  }
}"""

RELEASE_CLOSERS_QUERY = """query ReleaseBudgetClosers($owner: String!, $name: String!, $number: Int!, $after: String) {
  repository(owner: $owner, name: $name) {
    issue(number: $number) {
      timelineItems(first: 100, after: $after, itemTypes: [CLOSED_EVENT]) {
        nodes {
          ... on ClosedEvent {
            closer {
              __typename
              ... on PullRequest { number merged repository { nameWithOwner } mergeCommit { oid } }
            }
          }
        }
        pageInfo { hasNextPage endCursor }
      }
    }
  }
}"""


def release_pages(query, variables, connection, limit):
    """Never turn missing pages, partial responses or cursor cycles into empty scope."""
    cursor, seen = None, set()
    for _ in range(limit):
        argv = ["api", "graphql", "-f", "query=" + query]
        for key, value in variables.items():
            argv += ["-F" if type(value) is int else "-f", key + "=" + str(value)]
        if cursor is not None:
            argv += ["-f", "after=" + cursor]
        response = gh(*argv)
        try:
            page = connection(response["data"])
        except (KeyError, TypeError) as exc:
            raise Stop("release scope connection unavailable") from exc
        if (not isinstance(page, dict) or not isinstance(page.get("nodes"), list)
                or not isinstance(page.get("pageInfo"), dict)
                or type(page["pageInfo"].get("hasNextPage")) is not bool):
            raise Stop("malformed release scope page")
        yield page["nodes"]
        if not page["pageInfo"]["hasNextPage"]:
            return
        cursor = page["pageInfo"].get("endCursor")
        if not isinstance(cursor, str) or not cursor or cursor in seen:
            raise Stop("release scope pagination cursor unavailable or repeated")
        seen.add(cursor)
    raise Stop("release scope pagination truncated")


def release_ancestor(checkout, commit, head):
    if not isinstance(commit, str) or not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise Stop("release membership merge commit unavailable")
    result = subprocess.run(["git", "-C", str(checkout), "merge-base", "--is-ancestor", commit, head], capture_output=True)
    if result.returncode not in {0, 1}:
        raise Stop("release membership ancestry unavailable")
    return result.returncode == 0


def release_omitted(checkout, head, issue_repo, project_id, merged_status, known):
    candidates, read_cost = set(), 0
    for nodes in release_pages(RELEASE_ITEMS_QUERY, {"projectId": project_id}, lambda data: data["node"]["items"], 500):
        read_cost += 1
        for node in nodes:
            if not isinstance(node, dict) or "status" not in node or "content" not in node:
                raise Stop("release project item evidence unavailable")
            status = node["status"]
            if status is not None and (not isinstance(status, dict) or not isinstance(status.get("name"), str)):
                raise Stop("release project status evidence malformed")
            if not status or status["name"] != merged_status:
                continue
            content = node["content"]
            if not isinstance(content, dict) or not isinstance(content.get("__typename"), str):
                raise Stop("Merged item content unavailable")
            if content["__typename"] != "Issue":
                continue
            number = str(integer(content.get("number"), "release candidate issue", True))
            owning_repo = content.get("repository")
            if not isinstance(owning_repo, dict):
                raise Stop("release candidate repository unavailable")
            if repo(owning_repo.get("nameWithOwner")) == issue_repo and number not in known:
                candidates.add(number)
    owner, name = issue_repo.split("/")
    included = []
    for number in sorted(candidates, key=int):
        commits = set()
        for nodes in release_pages(RELEASE_CLOSERS_QUERY, {"owner": owner, "name": name, "number": int(number)},
                                   lambda data: data["repository"]["issue"]["timelineItems"], 20):
            read_cost += 1
            for node in nodes:
                if not isinstance(node, dict) or "closer" not in node:
                    raise Stop("release closing evidence malformed")
                closer = node["closer"]
                if closer is None:
                    continue
                if not isinstance(closer, dict) or not isinstance(closer.get("__typename"), str):
                    raise Stop("release closing identity malformed")
                if closer["__typename"] != "PullRequest":
                    continue
                if type(closer.get("merged")) is not bool:
                    raise Stop("release closing merge state unavailable")
                if not closer["merged"]:
                    continue
                if repo((closer.get("repository") or {}).get("nameWithOwner")) != issue_repo:
                    raise Stop("release closing PR repository mismatch")
                commit = (closer.get("mergeCommit") or {}).get("oid")
                if not isinstance(commit, str) or not re.fullmatch(r"[0-9a-f]{40}", commit):
                    raise Stop("release closing merge commit unavailable")
                commits.add(commit)
        if not commits:
            raise Stop("Merged candidate has no independently known closing merge: " + number)
        membership = {release_ancestor(checkout, commit, head) for commit in commits}
        if len(membership) != 1:
            raise Stop("release candidate membership ambiguous: " + number)
        if True in membership:
            included.append(number)
    return included, read_cost


def project_release(args):
    checkout = root(args.target_root or args.repo_root or Path.cwd())
    if not isinstance(args.version, str) or not re.fullmatch(r"v?[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.-]+)?(?:\+[A-Za-z0-9.-]+)?", args.version):
        raise Stop("release version unavailable or malformed")
    for value in (args.branch, args.base):
        if not isinstance(value, str) or not value:
            raise Stop("release branch/base unavailable")
        call(["git", "check-ref-format", "--branch", value])
    head = args.head
    if not isinstance(head, str) or not re.fullmatch(r"[0-9a-f]{40}", head):
        raise Stop("reviewed release head required")
    if call(["git", "-C", str(checkout), "rev-parse", head + "^{commit}"]) != head:
        raise Stop("reviewed release commit unavailable")
    if args.provider not in {"github_projects", "github_issues", "linear", "none"}:
        raise Stop("unsupported owning release provider")
    issue_repo = repo(args.issue_repo)
    ids = list(dict.fromkeys(args.scope_issue or []))
    for identifier in ids:
        valid = (re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*-[1-9][0-9]*", identifier)
                 if args.provider == "linear" and not identifier.isdigit()
                 else re.fullmatch(r"[1-9][0-9]*", identifier))
        if not valid:
            raise Stop("invalid release scope issue")
    read_cost = 0
    if args.provider == "github_projects":
        if not args.project_id:
            raise Stop("owning release project unavailable")
        omitted, read_cost = release_omitted(checkout, head, issue_repo, args.project_id, args.merged_status, set(ids))
        ids += omitted
    if not ids:
        raise Stop("finalized release issue scope unavailable")
    issues = []
    for identifier in ids:
        if args.provider in {"github_projects", "github_issues"}:
            live = gh("api", "repos/%s/issues/%s" % (issue_repo, identifier))
            if (not isinstance(live, dict) or live.get("number") != int(identifier)
                    or live.get("state") not in {"open", "closed"} or "pull_request" in live):
                raise Stop("finalized release issue identity unavailable")
            read_cost += 1
        issues.append({"id": identifier, "repo": issue_repo, "provider": args.provider,
                       "close": False, "tracker": args.provider in {"github_projects", "linear"},
                       "status": args.released_status, "statusPolicy": "exact",
                       "releaseStamp": args.provider != "none"})
    projection = {"schemaVersion": 1, "repo": repo(args.repo), "root": str(checkout),
            "version": args.version, "branch": args.branch, "head": head, "base": args.base,
            "issues": issues, "scopeReadCost": read_cost,
            "markerRepo": issue_repo, "markerProvider": args.provider,
            "changelogDigest": hashlib.sha256(call(["git", "-C", str(checkout), "show", head + ":CHANGELOG.md"]).encode()).hexdigest()}
    if args.evidence:
        evidence = decode(Path(args.evidence).read_text())
        if not isinstance(evidence, dict) or not isinstance(evidence.get("target_binding"), dict):
            raise Stop("component release binding unavailable")
        projection["componentBinding"] = evidence["target_binding"]
    return projection


def estimate(state):
    pieces = [{"kind": "shared", "count": 1, "weight": 25}]
    outstanding = [p for p in state["prs"] if any(s["status"] not in {"completed", "skipped_by_policy"} for s in p["steps"].values())]
    pieces.append({"kind": "pr", "count": len(outstanding), "weight": 50})
    for provider, weight in (("github_projects", 250), ("github_issues", 15), ("linear", 15)):
        count = sum(1 for p in outstanding for entry in p["steps"].values()
                    if entry["status"] not in {"completed", "skipped_by_policy"}
                    and entry["phase"] == ("issue_close" if provider == "github_issues" else "tracker")
                    and any(i["provider"] == provider and str(i["id"]) == str(entry.get("issue")) for i in p["issues"]))
        pieces.append({"kind": provider, "count": count, "weight": weight})
    remaining = sum(p["verifiedState"] == "unmerged" for p in state["prs"])
    pieces.append({"kind": "recheck", "count": remaining * (remaining - 1) // 2, "weight": 5})
    raw = sum(p["count"] * p["weight"] for p in pieces)
    margin = max(50, (raw + 1) // 2)
    return {"version": 1, "heuristic": True, "components": pieces,
            "rawCost": raw, "estimationMargin": margin, "projectedCost": raw + margin}


def safe_path(path):
    if ".." in Path(path).parts:
        raise Stop("session storage traversal refused")
    path = Path(os.path.abspath(path))
    for part in [path, *path.parents]:
        if part.is_symlink():
            raise Stop("symlinked session storage refused")
    return path


def check_storage(path):
    path = safe_path(path)
    if path.name != "state.json" or path.parent.parent.name != "workflow-merge-budget":
        raise Stop("session outside owner storage")
    for item in (path, path.parent, path.parent.parent):
        if not item.exists() or item.stat().st_uid != os.getuid() or item.stat().st_mode & 0o077:
            raise Stop("session storage is missing, foreign-owned, or not private")
    return path


def publish(path, state):
    fd, temporary = tempfile.mkstemp(prefix=".state-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(state, stream, sort_keys=True, allow_nan=False)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        fd = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


@contextmanager
def _journal_unmasked(path, write=True):
    path = check_storage(path)
    lockpath = safe_path(path.parent / "lock")
    fd = os.open(lockpath, os.O_RDWR | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0), 0o600)
    try:
        lockstat = os.fstat(fd)
        if lockstat.st_uid != os.getuid() or lockstat.st_mode & 0o077:
            raise Stop("lock storage is foreign-owned or not private")
        fcntl.flock(fd, fcntl.LOCK_EX)
        state = decode(path.read_text())
        if not isinstance(state, dict) or type(state.get("schemaVersion")) is not int or state.get("schemaVersion") != SCHEMA:
            raise Stop("unknown session schema; use retained compatible recovery reader")
        if str(path) != state.get("session") or path.parent.parent.parent != Path(state["ownerCommonDir"]):
            raise Stop("session owner binding mismatch")
        yield state
        if write:
            state["revision"] += 1
            publish(path, state)
    finally:
        os.close(fd)


@contextmanager
def journal(path, write=True):
    # A cancellation handler writes the journal before forwarding the signal.
    # Defer those handlers while this same thread owns its short file lock.
    previous = signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGTERM, signal.SIGINT})
    try:
        with _journal_unmasked(path, write) as state:
            yield state
    finally:
        signal.pthread_sigmask(signal.SIG_SETMASK, previous)



def snapshot(path):
    with journal(path, write=False) as state:
        return decode(json.dumps(state))


def checked_snapshot(path):
    state = snapshot(path)
    context(state)  # git inspection happens outside the journal lock
    return state


def complete_if_ready(state):
    if state["outcome"] == "Admitted" and all(
            s["status"] in {"completed", "skipped_by_policy"}
            for p in state["prs"] for s in p["steps"].values()):
        state["outcome"] = "Completed"


def target_for(state, args):
    matches = [p for p in state["prs"] if repo(p["repo"]) == repo(args.repo) and p["pr"] == args.pr]
    if len(matches) != 1:
        raise Stop("step not in frozen selected set")
    return matches[0]


def context(state):
    current = str(root(Path.cwd()))
    claimed_owner = os.environ.get("WORKFLOW_MERGE_BUDGET_OWNER_ROOT")
    if claimed_owner:
        if Path(claimed_owner).is_dir():
            if str(root(claimed_owner)) not in state["participants"] or str(common(claimed_owner)) != state["ownerCommonDir"]:
                raise Stop("executor owning configuration differs from durable owner")
        elif claimed_owner != state["ownerRoot"] or str(common(current)) != state["ownerCommonDir"]:
            raise Stop("removed owner is not the frozen owner with a surviving owning checkout")
    if current not in state["participants"]:
        raise Stop("current checkout is not a declared session participant")


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def group_alive(group):
    try:
        os.killpg(group, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def executor_alive(active):
    if not active:
        return False
    executions = active.get("children", [])
    return alive(active["pid"]) or any(alive(item["pid"]) or group_alive(item["group"]) for item in executions) or (
        bool(active.get("childPid")) and alive(active["childPid"])) or (
        bool(active.get("childGroup")) and group_alive(active["childGroup"]))


def admission(state):
    state["estimate"] = estimate(state)
    try:
        sample = budget()
        state["initialSample"] = sample
        if sample["remaining"] < state["estimate"]["projectedCost"] + state["reserve"]:
            raise Stop("insufficient GraphQL quota for entire outstanding selection")
    except (Stop, OSError) as exc:
        state["outcome"], state["reason"] = "Deferred", str(exc)
        state["quotaEvidence"] = getattr(exc, "evidence", None)
        return False
    state["outcome"], state["reason"] = "Admitted", ""
    return True


def begin(args):
    declaration_error = None
    if args.input:
        try:
            declaration = decode(Path(args.input).read_text())
        except (Stop, OSError) as exc:
            declaration, declaration_error = {"prs": None}, str(exc)
    else:
        declaration = {
        "ownerRoot": args.repo_root or str(Path.cwd()), "prs": [{
            "repo": args.repo, "pr": args.pr, "head": args.head, "base": args.base, "branch": getattr(args, "branch", None),
            "root": getattr(args, "target_root", None) or args.repo_root or str(Path.cwd()),
            "phases": (["remote_delete", "local_cleanup", "cleanup"] if getattr(args, "followup_only", False) else ["local_merge", "base_push", "merge_api", "remote_delete", "local_cleanup", "cleanup"])}]}
    if not isinstance(declaration, dict):
        declaration = {"prs": None}
    owner_decl = args.repo_root or declaration.get("ownerRoot")
    malformed_owner = owner_decl is not None and not isinstance(owner_decl, str)
    owner = root(Path.cwd() if malformed_owner else owner_decl or Path.cwd())
    state = {"schemaVersion": SCHEMA, "revision": 0, "createdAt": now(), "ownerRoot": str(owner),
             "ownerCommonDir": str(common(owner)), "participants": [str(owner)], "prs": [],
             "outcome": "Deferred", "reason": "", "started": False, "active": None,
             "attempt": 1, "policy": declaration.get("policy", {}), "history": [],
             "projectionComplete": False,
             "selectedSet": [{k: item.get(k) for k in ("repo", "pr", "head", "base", "root")}
                             if isinstance(item, dict) else {"unknown": True}
                             for item in declaration.get("prs", [])] if isinstance(declaration.get("prs"), list) else []}
    store = safe_path(common(owner) / "workflow-merge-budget")
    store.mkdir(mode=0o700, exist_ok=True)
    if store.stat().st_mode & 0o077 or store.stat().st_uid != os.getuid():
        raise Stop("owner session store must be private")
    directory = store / str(uuid.uuid4())
    directory.mkdir(mode=0o700)
    path = directory / "state.json"
    state["session"] = str(path)
    seen = set()
    try:
        if declaration_error:
            raise Stop(declaration_error)
        if malformed_owner or not isinstance(declaration.get("policy", {}), dict):
            raise Stop("malformed owner or policy declaration")
        state["reserve"] = reserve(owner, args.reserve)
        selected = declaration.get("prs")
        if not isinstance(selected, list) or not selected:
            raise Stop("unknown selected work projection")
        for item in selected:
            if not isinstance(item, dict):
                raise Stop("malformed selected PR identity")
            identity = (repo(item.get("repo")).lower(), integer(item.get("pr"), "PR", True))
            if identity in seen:
                raise Stop("duplicate selected PR")
            seen.add(identity)
            head = item.get("head")
            if not isinstance(head, str) or not re.fullmatch(r"[0-9a-f]{40}", head):
                raise Stop("invalid reviewed head")
            base = item.get("base")
            if not isinstance(base, str) or not base or any(c in base for c in " ?^~:\\\n"):
                raise Stop("invalid approved base")
            if not isinstance(item.get("root", str(owner)), str):
                raise Stop("malformed selected checkout path")
            target = {"repo": identity[0], "pr": identity[1], "head": head, "base": base,
                      "root": str(root(item.get("root", owner))), "steps": {}, "issues": [],
                      "verifiedState": "uncertain", "lastVerifiedAt": None}
            target["commonDir"] = str(common(target["root"]))
            if checkout_repo(target["root"]).lower() != target["repo"].lower():
                raise Stop("selected PR repository differs from checkout ownership")
            state["prs"].append(target)
            state["participants"].append(target["root"])
            live = pr_read(target)
            target["branch"] = live["headRefName"]
            if item.get("branch") is not None and item["branch"] != target["branch"]:
                raise Stop("PR branch differs from cleanup target; refusing cleanup and tracker updates")
            target["verifiedState"] = "merged" if live["state"] == "MERGED" else "unmerged"
            target["lastVerifiedAt"] = now()
            inspected = inspect(target, owner)
            target["issues"] = inspected["issues"]
            target["worktrees"] = inspected.get("worktrees", [])
            target["remoteCleanup"] = inspected.get("remoteCleanup", True)
            for participant in inspected.get("participants", []):
                participant = root(participant)
                if common(participant) != common(target["root"]):
                    raise Stop("cleanup participant belongs to another repository")
                state["participants"].append(str(participant))
            for issue in target["issues"]:
                if not isinstance(issue, dict) or type(issue.get("close")) is not bool or type(issue.get("tracker")) is not bool:
                    raise Stop("malformed owned follow-up duties")
                if issue.get("provider") not in {"github_projects", "github_issues", "linear", "none"}:
                    raise Stop("unknown tracker provider projection")
                if issue.get("close") and not isinstance(issue.get("closeComment"), str):
                    raise Stop("unknown owned closure comment")
                if not issue.get("id") or not issue.get("status") or not issue.get("repo"):
                    raise Stop("unknown owned issue projection")
            phases = item.get("phases", ["merge_api", "cleanup"])
            if not isinstance(phases, list) or any(not isinstance(phase, str) for phase in phases):
                raise Stop("malformed planned phases")
            definitions = item.get("steps", [{"id": phase, "phase": phase} for phase in phases])
            if not isinstance(definitions, list) or any(not isinstance(definition, dict) or not isinstance(definition.get("phase"), str) for definition in definitions):
                raise Stop("malformed planned step definitions")
            if isinstance(definitions, list) and any(d.get("phase") in {"local_merge", "base_push", "merge_api"} for d in definitions if isinstance(d, dict)) and not any(d.get("phase") == "cleanup" for d in definitions if isinstance(d, dict)):
                definitions = [*definitions, {"id": "cleanup", "phase": "cleanup"}]
            if isinstance(definitions, list) and any(d.get("phase") == "merge_api" for d in definitions if isinstance(d, dict)) and not any(d.get("phase") == "merge_verify" for d in definitions if isinstance(d, dict)):
                definitions = [*definitions, {"id": "merge_verify", "phase": "merge_verify"}]
            if isinstance(definitions, list) and any(d.get("phase") == "cleanup" for d in definitions if isinstance(d, dict)):
                for required in ("remote_delete", "local_cleanup"):
                    if not any(d.get("phase") == required for d in definitions if isinstance(d, dict)):
                        definitions = [*definitions, {"id": required, "phase": required}]
            if not isinstance(definitions, list) or not definitions:
                raise Stop("empty or unknown planned steps")
            for definition in definitions:
                if not isinstance(definition, dict):
                    raise Stop("malformed planned step")
                phase, key = definition.get("phase"), definition.get("id")
                if phase == "remote_delete" and inspected.get("remoteCleanup") is False:
                    continue
                if not isinstance(phase, str) or phase not in PHASES or not isinstance(key, str) or not re.fullmatch(r"[A-Za-z0-9_.:-]+", key) or key in target["steps"]:
                    raise Stop("unknown or duplicate planned phase/step")
                if set(definition) - {"id", "phase", "auditTarget", "auditRepo", "marker", "issue"}:
                    raise Stop("unsupported planned step fields; proof is journal-owned")
                entry = dict(definition, status="pending")
                if phase == "issue_close":
                    owned = [issue for issue in target["issues"] if str(issue["id"]) == str(entry.get("issue")) and issue.get("close")]
                    if len(owned) != 1:
                        raise Stop("closure step has no exact frozen owning issue")
                    entry["expectedComment"] = owned[0]["closeComment"]
                if target["verifiedState"] == "merged" and phase in {"local_merge", "base_push", "merge_api", "merge_verify"}:
                    entry.update(status="completed", verifiedAt=now(), existingMerge=True)
                if phase in {"audit", "hold"}:
                    if not isinstance(entry.get("marker"), str) or not entry["marker"] or type(entry.get("auditTarget")) is not int or entry["auditTarget"] <= 0:
                        raise Stop("audit step requires frozen target and stable marker")
                    entry["auditRepo"] = repo(entry.get("auditRepo", target["repo"]))
                target["steps"][key] = entry
            for issue in target["issues"] if any(d.get("phase") == "cleanup" for d in definitions) else []:
                if issue.get("tracker"):
                    for suffix in (("pre", "post") if issue.get("close") else ("pre",)):
                        key = "tracker:" + str(issue["id"]) + ":" + suffix
                        target["steps"].setdefault(key, {"status": "pending", "phase": "tracker", "issue": issue["id"]})
                if issue.get("close"):
                    key = "issue_close:" + str(issue["id"])
                    target["steps"].setdefault(key, {"status": "pending", "phase": "issue_close", "issue": issue["id"], "expectedComment": issue["closeComment"]})
            target["policySkipped"] = item.get("policySkipped", [])
            if not isinstance(target["policySkipped"], list) or any(not isinstance(x, str) or x not in {"remote_delete", "local_cleanup"} for x in target["policySkipped"]):
                raise Stop("invalid cleanup policy declaration")
            for phase in target["policySkipped"]:
                for entry in target["steps"].values():
                    if entry["phase"] == phase:
                        entry.update(phase="policy_skip", skippedPhase=phase)
        state["participants"] = sorted(set(state["participants"]))
        state["manifestFingerprint"] = hashlib.sha256(json.dumps(declaration, sort_keys=True).encode()).hexdigest()
        state["projectionComplete"] = True
        admission(state)
    except (Stop, OSError) as exc:
        state["outcome"], state["reason"] = "Deferred", str(exc)
    publish(path, state)
    return summary(state)


def step_key(args):
    return args.step or args.phase + (":" + str(args.issue) if args.issue is not None else "")


def before(args):
    image = checked_snapshot(args.session)
    target = target_for(image, args)
    key = step_key(args)
    if not image.get("projectionComplete"):
        raise Stop("frozen selected projection remains incomplete")
    if args.phase not in {"audit", "hold", "recheck"}:
        preceding = image["prs"][:image["prs"].index(target)]
        if any(step["status"] not in {"completed", "skipped_by_policy"} for prior in preceding for step in prior["steps"].values()):
            raise Stop("preceding selected PR follow-up remains incomplete")
    old = target["steps"].get(key)
    if not old or old.get("phase") != args.phase:
        raise Stop("unknown step or phase outside frozen manifest")
    if args.phase in target.get("policySkipped", []):
        raise Stop("cleanup forbidden by declared existing policy")
    if args.phase in {"tracker", "issue_close"} and not any(
            str(i["id"]) == str(args.issue) and i["status"] == args.status for i in target["issues"]):
        raise Stop("tracker target/status not in frozen ownership")
    if old.get("issue") is not None and str(old["issue"]) != str(args.issue):
        raise Stop("step issue differs from frozen intent")
    pid = args.executor_pid or os.getppid()
    supplied = os.environ.get("WORKFLOW_MERGE_BUDGET_TOKEN")
    token = supplied or str(uuid.uuid4())
    if getattr(args, "continue_intent", False):
        active = image.get("active")
        if args.phase not in {"cleanup", "local_cleanup"} or old["status"] != "in_flight" or not active or pid not in {active["pid"], *[child["pid"] for child in active.get("children", [])]} or active["token"] != supplied or old.get("token") != supplied:
            raise Stop("cleanup reentry has no same-process durable intent")
        return {"token": supplied, "step": key, "session": args.session}
    if image.get("active") and not alive(image["active"]["pid"]):
        with journal(args.session) as state:
            if state["revision"] != image["revision"]:
                raise Stop("session changed; retry current report")
            state["outcome"], state["reason"] = "Interrupted", "stale execution requires explicit live-verified resume"
        raise Stop("stale execution requires explicit live-verified resume")
    # Claim before remote reads so concurrent callers cannot both admit a mutation.
    with journal(args.session) as state:
        if state["revision"] != image["revision"]:
            raise Stop("session changed; retry after reading current report")
        if state["outcome"] != "Admitted":
            raise Stop("session requires explicit live-verified resume: " + state["outcome"])
        active = state.get("active")
        if active:
            if not executor_alive(active):
                raise Stop("stale execution requires explicit resume")
            if supplied != active["token"]:
                raise Stop("another executor is active")
        if old["status"] != "pending":
            raise Stop("step requires live recovery rather than repeat")
        state["active"] = active or {"pid": pid, "token": token}
    image = snapshot(args.session)
    target = target_for(image, args)
    failure = None
    try:
        if not image["started"]:
            for selected in image["prs"]:
                selected_root = proof_root(image, selected["commonDir"], selected["root"])
                if checkout_repo(selected_root).lower() != selected["repo"].lower():
                    raise Stop("frozen participant repository identity changed")
                current = pr_read(selected)
                selected["verifiedState"] = "merged" if current["state"] == "MERGED" else "unmerged"
                selected["lastVerifiedAt"] = now()
                current_targets = inspect(dict(selected, root=selected_root), proof_root(image, image["ownerCommonDir"], image["ownerRoot"]))["issues"]
                if current_targets != selected["issues"]:
                    raise Stop("owned follow-up targets changed since frozen projection")
            if not admission(image):
                raise Stop(image["reason"])
        current_root = proof_root(image, target["commonDir"], target["root"])
        if checkout_repo(current_root).lower() != target["repo"].lower():
            raise Stop("checkout repository identity changed")
        live = pr_read(target)
        target["verifiedState"] = "merged" if live["state"] == "MERGED" else "unmerged"
        target["lastVerifiedAt"] = now()
        if args.phase in {"remote_delete", "local_cleanup", "cleanup", "issue_close", "tracker"} and target["verifiedState"] != "merged":
            raise Stop("merge-dependent follow-up requires verified MERGED")
        expected = Path(args.expected_file).read_text() if args.expected_file else None
        if args.phase in {"audit", "hold"}:
            if old.get("retryVerifiedAt") and expected != old.get("expectedBody"):
                raise Stop("retry content differs from independently outstanding frozen audit intent")
            if not expected or not old.get("marker") or old["marker"] not in expected:
                raise Stop("audit content lacks frozen stable marker")
        if args.phase == "issue_close":
            owned_issue = next(issue for issue in target["issues"] if str(issue["id"]) == str(args.issue))
            current_issue = issue_read(owned_issue)
            old.setdefault("issueStateBefore", current_issue["state"])
            old.setdefault("commentRequired", old["issueStateBefore"] == "OPEN")
            closure_read(owned_issue, old, current_issue)
        if args.phase in {"local_merge", "base_push"}:
            old["expectedCommit"] = old.get("expectedCommit") if old.get("retryVerifiedAt") and args.phase == "base_push" else call(["git", "-C", current_root, "rev-parse", "HEAD"])
    except (Stop, OSError) as exc:
        failure = str(exc)
    with journal(args.session) as state:
        if state["revision"] != image["revision"] or state.get("active", {}).get("token") != token:
            raise Stop("session changed during admission evidence collection")
        for selected in state["prs"]:
            fresh = next(p for p in image["prs"] if p["repo"] == selected["repo"] and p["pr"] == selected["pr"])
            selected["verifiedState"], selected["lastVerifiedAt"] = fresh["verifiedState"], fresh["lastVerifiedAt"]
        for field in ("estimate", "initialSample", "quotaEvidence"):
            if field in image:
                state[field] = image[field]
        if failure:
            state["outcome"] = "Interrupted" if state["started"] else "Deferred"
            state["reason"] = failure
            if not any(entry["status"] == "in_flight" for target in state["prs"] for entry in target["steps"].values()):
                state["active"] = None
        else:
            state["initialSample"] = image.get("initialSample")
            state["estimate"] = image.get("estimate")
            state["outcome"], state["reason"] = "Admitted", ""
            state["started"] = True
            current = target_for(state, args)
            for selected in state["prs"]:
                fresh = next(p for p in image["prs"] if p["repo"] == selected["repo"] and p["pr"] == selected["pr"])
                selected["verifiedState"], selected["lastVerifiedAt"] = fresh["verifiedState"], fresh["lastVerifiedAt"]
            entry = dict(old, status="in_flight", intentAt=now(), intentRevision=state["revision"] + 1, issue=args.issue,
                         expectedStatus=args.status, token=token)
            entry.pop("supersededBy", None)  # A newly issued intent owns its own read-back duty.
            if expected is not None:
                entry["expectedBody"] = expected
            current["steps"][key] = entry
    if failure:
        raise Stop(failure)
    args.execution_token = token
    return {"token": token, "step": key, "session": args.session}


def issue_read(issue):
    value = gh("issue", "view", issue["id"], "--repo", issue["repo"], "--json", "number,state")
    if not isinstance(value, dict) or type(value.get("number")) is not int or value.get("number") != int(issue["id"]) or value.get("state") not in {"OPEN", "CLOSED"}:
        raise Stop("owned issue state unavailable")
    return value



def comments_read(endpoint):
    pages = gh("api", "--paginate", "--slurp", endpoint)
    if not isinstance(pages, list) or any(not isinstance(page, list) for page in pages):
        raise Stop("comment pages evidence malformed")
    comments = [comment for page in pages for comment in page]
    if any(not isinstance(comment, dict) or not isinstance(comment.get("body"), str) for comment in comments):
        raise Stop("comment content evidence malformed")
    return comments


def closure_read(issue, entry, live=None):
    live = live or issue_read(issue)
    required = entry.get("commentRequired", entry.get("issueStateBefore") != "CLOSED")
    entry["commentRequired"] = required
    entry["currentIssueState"] = live["state"]
    comment = "not_required"
    if required:
        comments = comments_read("repos/%s/issues/%s/comments?per_page=100" % (issue["repo"], issue["id"]))
        comment = "completed" if any(item["body"] == entry.get("expectedComment") for item in comments) else "pending"
    entry["effects"] = {"closure": "completed" if live["state"] == "CLOSED" else "pending", "comment": comment}
    return entry["effects"]["closure"] == "completed" and comment in {"completed", "not_required"}


def proof_root(state, expected_common, preferred):
    for candidate in [preferred, *state["participants"]]:
        if Path(candidate).is_dir():
            try:
                if str(common(candidate)) == expected_common:
                    return candidate
            except Stop:
                pass
    raise Stop("no surviving declared checkout can verify owned git resources")


def tracker_read(state, issue):
    if issue["provider"] == "linear":
        proofs = [entry.get("providerEvidence", {}) for target in state["prs"] for entry in target["steps"].values()
                  if entry.get("phase") == "tracker" and str(entry.get("issue")) == str(issue["id"])]
        return any(proof.get("repo") == issue["repo"] and proof.get("issue") == issue["id"]
                   and proof.get("statusName") == issue["status"] and proof.get("statusId")
                   and newer(proof.get("observedAt"), state.get("recoveryStartedAt")) for proof in proofs)
    if issue["provider"] in {"none", "github_issues"}:
        return issue_read(issue)["state"] == "CLOSED"
    script = 'source "$1/workflow-lib.sh"; cd "$2"; value=$(get_tracker_status_for_issue "$3"); printf "%s\n%s\n%s" "$value" "$(workflow_status_order "$value")" "$(workflow_status_order "$4")"'
    owner = proof_root(state, state["ownerCommonDir"], state["ownerRoot"])
    environment = dict(os.environ, WORKFLOW_MERGE_BUDGET_SESSION=state["session"], WORKFLOW_MERGE_BUDGET_OWNER_ROOT=owner,
                       WORKFLOW_TARGET_GITHUB_REPO=issue["repo"])
    environment.pop("GH_REPO", None)
    value = call(["bash", "-c", script, "budget-read", str(SCRIPT), owner, str(issue["id"]), issue["status"]], env=environment).splitlines()
    if len(value) != 3 or not value[0] or any(re.fullmatch(r"[0-9]+", rank) is None for rank in value[1:]):
        raise Stop("tracker read-back/order evidence unavailable")
    if value[0] == issue["status"]:
        return True
    return issue.get("statusPolicy") == "at_least" and re.fullmatch(r"[0-9]+", value[1]) is not None and re.fullmatch(r"[0-9]+", value[2]) is not None and int(value[1]) >= int(value[2])


def comment_scope(target, entry):
    if entry["phase"] not in {"audit", "hold"} or type(entry.get("auditTarget", target["pr"])) is not int or not isinstance(entry.get("marker"), str) or not entry["marker"]:
        raise Stop("invalid frozen comment scope")
    return (entry["phase"], repo(entry.get("auditRepo", target["repo"])),
            entry.get("auditTarget", target["pr"]), entry.get("marker"))


def comment_order(left, right):
    for entry in (left, right):
        timestamp(entry.get("intentAt"))
        if "intentRevision" in entry and (type(entry["intentRevision"]) is not int or entry["intentRevision"] <= 0):
            raise Stop("invalid comment intent revision")
    if "intentRevision" in left and "intentRevision" in right:
        a, b = left["intentRevision"], right["intentRevision"]
    else:
        a, b = timestamp(left["intentAt"]), timestamp(right["intentAt"])
    return (a > b) - (a < b)


def ordered_comment_group(group):
    for _, _, entry in group:
        comment_order(entry, entry)
    ordered = sorted(group, key=cmp_to_key(lambda a, b: comment_order(a[2], b[2])), reverse=True)
    # Mixed older timestamp/newer revision evidence must form one consistent order.
    for index, (_, _, later) in enumerate(ordered):
        for _, _, earlier in ordered[index + 1:]:
            if comment_order(later, earlier) <= 0:
                raise Stop("ambiguous comment execution chronology")
    return ordered


def supersede_verified_comment(state, target, key):
    latest = target["steps"][key]
    if latest["phase"] not in {"audit", "hold"} or latest["status"] != "completed":
        return
    timestamp(latest.get("verifiedAt"))
    comment_order(latest, latest)
    group = [(p, k, e) for p in state["prs"] for k, e in p["steps"].items()
             if e["phase"] in {"audit", "hold"} and e.get("intentAt")
             and comment_scope(p, e) == comment_scope(target, latest)]
    for previous_target, previous_key, previous in ordered_comment_group(group):
        if previous is not latest and comment_order(previous, latest) < 0:
            previous["supersededBy"] = {"repo": target["repo"], "pr": target["pr"], "step": key}


def supersession_target(state, target, entry):
    reference = entry["supersededBy"]
    if isinstance(reference, str):  # compatible earlier same-PR journal reference
        selected, key = target, reference
    elif isinstance(reference, dict) and set(reference) == {"repo", "pr", "step"} and type(reference["pr"]) is int:
        matches = [p for p in state["prs"] if p["repo"] == repo(reference["repo"]) and p["pr"] == reference["pr"]]
        if len(matches) != 1 or not isinstance(reference["step"], str):
            raise Stop("superseding intent has no frozen owner")
        selected, key = matches[0], reference["step"]
    else:
        raise Stop("invalid superseding intent reference")
    successor = selected["steps"].get(key)
    if (not successor or entry["phase"] not in {"audit", "hold"}
            or comment_scope(target, entry) != comment_scope(selected, successor)
            or successor["status"] != "completed" or not successor.get("verifiedAt")
            or comment_order(entry, successor) >= 0):
        raise Stop("superseding comment is not a later verified owning intent")
    timestamp(successor["verifiedAt"])
    return selected, successor


def verify(state, target, entry, seen=None):
    phase = entry["phase"]
    git_root = proof_root(state, target["commonDir"], target["root"]) if phase in {"local_merge", "base_push", "remote_delete", "local_cleanup", "policy_skip"} else target["root"]
    if entry.get("supersededBy"):
        seen = set() if seen is None else seen
        identity = (target["repo"], target["pr"], next((k for k, v in target["steps"].items() if v is entry), None))
        if identity in seen:
            raise Stop("cyclic comment supersession")
        seen.add(identity)
        selected, successor = supersession_target(state, target, entry)
        return verify(state, selected, successor, seen)
    if phase in {"merge_api", "merge_verify", "cleanup", "remote_delete", "local_cleanup", "issue_close", "tracker", "policy_skip"}:
        live = pr_read(target)
        target["verifiedState"] = "merged" if live["state"] == "MERGED" else "unmerged"
        target["lastVerifiedAt"] = now()
        if phase in {"merge_api", "merge_verify"}:
            if live["state"] == "MERGED":
                return True
            if live["state"] == "OPEN" and (live.get("isInMergeQueue") is True or isinstance(live.get("autoMergeRequest"), dict)):
                state["outcome"], state["reason"] = "Waiting", "verified queued/auto-merge submission; resume after live MERGED"
                entry["submission"] = {"observedAt": now(), "state": live["state"], "head": live["headRefOid"]}
                return False
            if live["state"] == "OPEN" and entry.get("exitCode") is not None and entry["exitCode"] != 0:
                raise Stop("failed merge API remains independently OPEN without submission", {"knownOutstanding": True})
            raise Stop("merge outcome not verified")
        if live["state"] != "MERGED":
            raise Stop("follow-up requires verified MERGED")
    if entry.get("existingMerge") and phase in {"local_merge", "base_push"}:
        return pr_read(target)["state"] == "MERGED"
    if phase == "local_merge":
        recorded = entry.get("commit")
        if recorded and entry["status"] in {"completed", "uncertain", "in_flight"}:
            call(["git", "-C", git_root, "merge-base", "--is-ancestor", target["head"], recorded])
            return True
        call(["git", "-C", git_root, "merge-base", "--is-ancestor", target["head"], "HEAD"])
        if call(["git", "-C", git_root, "branch", "--show-current"]) != target["base"]:
            raise Stop("local merge is not on approved base")
        entry["commit"] = call(["git", "-C", git_root, "rev-parse", "HEAD"])
        return True
    if phase == "base_push":
        commit = entry.get("commit") or entry.get("expectedCommit")
        if not isinstance(commit, str) or not re.fullmatch(r"[0-9a-f]{40}", commit):
            raise Stop("base push has no durable intended commit")
        remote = call(["git", "-C", git_root, "ls-remote", "origin", "refs/heads/" + target["base"]])
        match = re.fullmatch(r"([0-9a-f]{40})\trefs/heads/" + re.escape(target["base"]), remote)
        if not match:
            raise Stop("approved remote base evidence unavailable")
        remote_commit = match[1]
        if remote_commit != commit:
            present = subprocess.run(["git", "-C", git_root, "cat-file", "-e", remote_commit + "^{commit}"], capture_output=True)
            if present.returncode:
                call(["git", "-C", git_root, "fetch", "--no-write-fetch-head", "origin", remote_commit])
            ancestry = subprocess.run(["git", "-C", git_root, "merge-base", "--is-ancestor", commit, remote_commit],capture_output=True)
            if ancestry.returncode:
                behind = subprocess.run(["git", "-C", git_root, "merge-base", "--is-ancestor", remote_commit, commit],capture_output=True)
                if entry.get("exitCode") is not None and entry["exitCode"] != 0 and behind.returncode == 0:
                    raise Stop("failed push remains independently behind durable intended commit", {"knownOutstanding": True})
                raise Stop("durable pushed commit is not verified on current remote base")
        entry["commit"], entry["verifiedRemoteCommit"] = commit, remote_commit
        return True
    if phase in {"audit", "hold"}:
        endpoint = "repos/%s/issues/%s/comments?per_page=100" % (entry.get("auditRepo", target["repo"]), entry.get("auditTarget", target["pr"]))
        comments = comments_read(endpoint)
        expected = entry.get("expectedBody")
        if not expected or not any(c["body"] == expected for c in comments):
            raise Stop("audit body not independently verified", {"knownOutstanding": True})
        return True
    if phase == "remote_delete":
        value = call(["git", "-C", git_root, "ls-remote", "--heads", "origin", target["branch"]])
        return not value
    if phase == "local_cleanup":
        if entry.get("policySkip") == "caller_worktree_detach_failed":
            callers = [item for item in target.get("worktrees", []) if item["caller"]]
            return bool(call(["git", "-C", git_root, "branch", "--list", target["branch"]])) and any(
                Path(item["root"]).is_dir() and call(["git", "-C", item["root"], "branch", "--show-current"]) == target["branch"]
                and (entry.get("status") == "skipped_by_policy" or bool(call(["git", "-C", item["root"], "status", "--porcelain"]))) for item in callers)
        listing = call(["git", "-C", git_root, "worktree", "list", "--porcelain"])
        for item in target.get("worktrees", []):
            if item["caller"]:
                if not Path(item["root"]).is_dir() or "worktree " + item["root"] not in listing:
                    raise Stop("caller-owned worktree was not retained")
                if call(["git", "-C", item["root"], "branch", "--show-current"]) == target["branch"]:
                    raise Stop("caller-owned worktree still holds deleted branch", {"knownOutstanding": True})
            elif Path(item["root"]).exists() or "worktree " + item["root"] in listing:
                raise Stop("non-caller merged worktree cleanup not verified", {"knownOutstanding": True})
        return not call(["git", "-C", git_root, "branch", "--list", target["branch"]])
    if phase == "policy_skip":
        if entry.get("skippedPhase") == "remote_delete":
            return bool(call(["git", "-C", git_root, "ls-remote", "--heads", "origin", target["branch"]]))
        return bool(call(["git", "-C", git_root, "branch", "--list", target["branch"]]))
    if phase in {"tracker", "issue_close"}:
        matches = [i for i in target["issues"] if str(i["id"]) == str(entry["issue"])]
        if len(matches) != 1:
            raise Stop("unknown owning issue")
        if phase == "tracker":
            if matches[0]["provider"] == "linear":
                proof = entry.get("providerEvidence", {})
                valid = (proof.get("repo") == matches[0]["repo"] and proof.get("issue") == matches[0]["id"]
                         and proof.get("statusName") == matches[0]["status"] and bool(proof.get("statusId"))
                         and newer(proof.get("observedAt"), entry.get("intentAt"), state.get("recoveryStartedAt")))
                if not valid:
                    raise Stop("current owning Linear bridge read-back required")
                return True
            return tracker_read(state, matches[0])
        return closure_read(matches[0], entry)
    if phase == "cleanup":
        for issue in target["issues"]:
            if issue.get("tracker") and not tracker_read(state, issue):
                raise Stop("owned tracker follow-up remains pending", {"knownOutstanding": True})
            if issue.get("close") and issue_read(issue)["state"] != "CLOSED":
                raise Stop("owned closure follow-up remains pending", {"knownOutstanding": True})
        if any(entry["status"] not in {"completed", "skipped_by_policy"} for entry in target["steps"].values()
               if entry["phase"] in {"issue_close", "tracker", "remote_delete", "local_cleanup", "policy_skip"}):
            raise Stop("individual owned follow-up duties remain unverified", {"knownOutstanding": True})
        for related in target["steps"].values():
            if related["phase"] in {"tracker", "issue_close", "remote_delete", "local_cleanup", "policy_skip"} and not verify(state, target, related):
                raise Stop("completed individual duty no longer verifies")
        return True
    if phase == "recheck":
        pr_read(target)
        return True
    raise Stop("unverifiable phase")


def after(args):
    image = checked_snapshot(args.session)
    target = target_for(image, args)
    key = step_key(args)
    entry = target["steps"].get(key)
    if not entry or entry["status"] != "in_flight":
        raise Stop("completion without durable intent")
    supplied = getattr(args, "execution_token", None) or os.environ.get("WORKFLOW_MERGE_BUDGET_TOKEN")
    active = image.get("active")
    entry["exitCode"] = args.exit_code
    if args.phase != entry["phase"] or str(args.issue) != str(entry.get("issue")) or args.status != entry.get("expectedStatus"):
        raise Stop("completion differs from exact durable intent")
    if not active or supplied != entry.get("token") or supplied != active["token"]:
        raise Stop("completion has no owning execution token")
    if getattr(args, "policy_skip", None):
        if args.phase != "local_cleanup" or args.policy_skip != "caller_worktree_detach_failed":
            raise Stop("undeclared existing cleanup policy")
        entry["policySkip"] = args.policy_skip
    if getattr(args, "no_op", False):
        if args.phase not in {"tracker", "issue_close"}:
            raise Stop("no-op verification unavailable for this phase")
        entry["verifiedNoOp"] = args.phase != "issue_close" or entry.get("issueStateBefore") == "CLOSED"
    failure = None
    try:
        completed = verify(image, target, entry)
        if args.exit_code and image["outcome"] != "Waiting" and args.phase not in {"merge_api", "base_push", "issue_close", "tracker", "audit", "hold", "remote_delete"}:
            raise Stop("command failed; completion cannot follow zero-exit assumptions")
        if not completed and image["outcome"] != "Waiting":
            raise Stop("required follow-up pending or mismatched")
        entry["status"] = ("skipped_by_policy" if entry.get("skippedPhase") or entry.get("policySkip") else "completed") if completed else "pending"
        entry["verifiedAt"] = now()
    except (Stop, OSError) as exc:
        entry["status"] = "uncertain"
        image["outcome"], image["reason"] = "Interrupted", str(exc)
        failure = str(exc)
    with journal(args.session) as state:
        cancellation = state.get("cancellation")
        cancelled = bool(cancellation and cancellation.get("attempt") == image["attempt"])
        cancellation_only = (cancelled and state["revision"] == image["revision"] + 1
                             and cancellation.get("revisionBefore") == image["revision"]
                             and target_for(state, args)["steps"][key].get("token") == supplied)
        if state["revision"] != image["revision"] and not cancellation_only:
            raise Stop("session changed during independent verification")
        if cancelled:
            image["outcome"], image["reason"] = "Interrupted", "execution cancelled; explicit live-verified resume required"
        current = target_for(state, args)
        current["steps"] = target["steps"]
        current["steps"][key] = entry
        try:
            supersede_verified_comment(state, current, key)
        except Stop as exc:
            image["outcome"], image["reason"] = "Interrupted", str(exc)
            failure = str(exc)

        current["verifiedState"], current["lastVerifiedAt"] = target["verifiedState"], target["lastVerifiedAt"]
        state["outcome"], state["reason"] = image["outcome"], image["reason"]
        if not getattr(args, "retain_executor", False) and not any(s["status"] == "in_flight" for p in state["prs"] for s in p["steps"].values()):
            state["active"] = None
        complete_if_ready(state)
        if state["outcome"] in {"Interrupted", "Waiting"}:
            failure = state["reason"]
    if failure:
        raise Stop(failure)
    return {"step": key, "status": "completed"}


def resume(args):
    image = checked_snapshot(args.session)
    active = image.get("active")
    if executor_alive(active):
        raise Stop("recorded executor still active")
    if not image.get("projectionComplete"):
        return summary(image)
    linear_entries = [entry for target in image["prs"] for entry in target["steps"].values()
                      if entry["phase"] == "tracker" and any(issue["provider"] == "linear" and str(issue["id"]) == str(entry.get("issue")) for issue in target["issues"])]
    continuation = bool(image.get("recoveryAwaitingProvider") and linear_entries and all(
        entry.get("providerEvidence", {}).get("recoveryGeneration") == image.get("recoveryGeneration")
        and newer(entry.get("providerEvidence", {}).get("observedAt"), image.get("recoveryStartedAt"))
        for entry in linear_entries if entry.get("intentAt")))
    if not continuation:
        image["recoveryGeneration"] = image.get("recoveryGeneration", 0) + 1
        image["recoveryStartedAt"] = now()
    image["recoveryAwaitingProvider"] = False
    def recover_entry(target, key, entry):
        try:
            verified = verify(image, target, entry)
        except Stop as exc:
            if exc.evidence and exc.evidence.get("knownOutstanding") and entry["status"] in {"pending", "in_flight", "uncertain"} and entry["phase"] in {"local_cleanup", "cleanup", "audit", "hold", "merge_api", "base_push"}:
                entry.update(status="pending", retryVerifiedAt=now())
                return
            raise
        if not verified:
            if entry["status"] in {"in_flight", "uncertain"} and entry["phase"] in {"remote_delete", "local_cleanup", "tracker", "issue_close"}:
                entry.update(status="pending", retryVerifiedAt=now())
                return
            raise Stop("outstanding or previously completed action cannot be verified")
        entry["status"] = "skipped_by_policy" if entry.get("skippedPhase") or entry.get("policySkip") else "completed"
        entry["verifiedAt"] = now()
        supersede_verified_comment(image, target, key)
    try:
        groups = {}
        for target in image["prs"]:
            for key, entry in target["steps"].items():
                if entry["phase"] in {"audit", "hold"} and (entry.get("intentAt") or entry["status"] != "pending"):
                    groups.setdefault(comment_scope(target, entry), []).append((target, key, entry))
        for group in groups.values():
            for target, key, entry in ordered_comment_group(group):
                recover_entry(target, key, entry)
        for target in image["prs"]:
            live = pr_read(target)
            target["verifiedState"] = "merged" if live["state"] == "MERGED" else "unmerged"
            target["lastVerifiedAt"] = now()
            if live["state"] == "OPEN" and (live.get("isInMergeQueue") is True or isinstance(live.get("autoMergeRequest"), dict)):
                image["outcome"], image["reason"] = "Waiting", "submission remains queued; do not repeat"
                break
            for key, entry in target["steps"].items():
                if entry["phase"] in {"audit", "hold"}:
                    continue
                if entry["status"] in {"in_flight", "uncertain", "completed", "skipped_by_policy"} or entry.get("submission"):
                    recover_entry(target, key, entry)
        else:
            image["active"], image["started"] = None, False
            image["attempt"] += 1
            admission(image)
            if image["outcome"] == "Admitted":
                image.pop("cancellation", None)
            complete_if_ready(image)
    except (Stop, OSError) as exc:
        image["outcome"], image["reason"] = "Deferred", "unknown outstanding work: " + str(exc)
        image["recoveryAwaitingProvider"] = bool(linear_entries)
    with journal(args.session) as state:
        if state["revision"] != image["revision"]:
            raise Stop("session changed during recovery evidence collection")
        image["history"].append({"outcome": state["outcome"], "at": now(), "initialSample": state.get("initialSample"), "cancellation": state.get("cancellation")})
        if "cancellation" not in image and image["outcome"] in {"Admitted", "Completed"}:
            state.pop("cancellation", None)
        state.update(image)
    return summary(snapshot(args.session))


def summary(state, final=False):
    result = {k: state.get(k) for k in ("schemaVersion", "session", "revision", "outcome", "reason", "reserve", "estimate", "initialSample", "quotaEvidence", "selectedSet", "projectionComplete", "prs")}
    if result.get("prs") is not None:
        result["prs"] = decode(json.dumps(result["prs"]))
        for target in result["prs"]:
            for entry in target["steps"].values():
                entry.pop("token", None)
    if state["outcome"] == "Admitted" and state.get("active") and not alive(state["active"]["pid"]):
        result["outcome"], result["reason"] = "Interrupted", "stale execution claim; explicit live-verified resume required"
    result["recoveryAction"] = "python3 scripts/development-workflow/workflow-merge-budget.py resume --session " + state["session"]
    result["observedSpend"] = None
    result["spendReason"] = "final evidence unavailable"
    result["concurrentConsumption"] = "sample difference may include other consumers; quota is not reserved"
    if final:
        try:
            last = budget()
            result["finalSample"] = last
            first = state.get("initialSample")
            if not first:
                result["spendReason"] = "initial evidence unavailable"
            elif first["reset"] != last["reset"]:
                result["spendReason"] = "quota window reset"
            elif first["limit"] != last["limit"]:
                result["spendReason"] = "quota limit changed"
            elif last["remaining"] > first["remaining"]:
                result["spendReason"] = "remaining balance increased"
            else:
                result["observedSpend"] = first["remaining"] - last["remaining"]
                result["spendReason"] = None
        except (Stop, OSError) as exc:
            result["finalSample"] = None
            result["finalEvidence"] = getattr(exc, "evidence", None)
            result["spendReason"] = str(exc)
    return result


def provider(args):
    evidence = decode(Path(args.evidence).read_text())
    if not isinstance(evidence, dict):
        raise Stop("malformed provider evidence")
    checked_snapshot(args.session)
    with journal(args.session) as state:
        target = target_for(state, args)
        entry = target["steps"].get(step_key(args))
        issue = next((i for i in target["issues"] if str(i["id"]) == str(args.issue)), None)
        if (not entry or not issue or issue["provider"] != "linear" or args.phase != "tracker"
                or entry.get("phase") != "tracker" or str(entry.get("issue")) != str(args.issue)
                or entry.get("expectedStatus") != issue["status"]
                or entry.get("status") not in {"in_flight", "uncertain", "completed"}):
            raise Stop("provider proof has no declared intent/owner")
        active = state.get("active") or {}
        if any(alive(child["pid"]) or group_alive(child["group"]) for child in active.get("children", [])):
            raise Stop("recorded mutating child still active; provider proof cannot release execution claim")
        valid = (evidence.get("provider") == "linear" and evidence.get("issue") == issue["id"] and
                 evidence.get("repo") == issue["repo"] and evidence.get("statusName") == issue["status"] and
                 all(isinstance(evidence.get(field), str) and evidence[field] for field in ("statusId", "mutationRequestId", "readRequestId")) and
                 evidence["mutationRequestId"] != evidence["readRequestId"] and
                 newer(evidence.get("observedAt"), entry.get("intentAt"), state.get("recoveryStartedAt")))
        if not valid:
            entry["status"] = "uncertain"
            state["outcome"], state["reason"] = "Interrupted", "provider read-back unavailable or mismatched"
        else:
            entry["providerEvidence"] = {k: evidence[k] for k in ("provider", "issue", "repo", "statusName", "statusId", "mutationRequestId", "readRequestId", "observedAt")}
            entry["providerEvidence"]["recoveryGeneration"] = state.get("recoveryGeneration", 0)
            entry["status"] = "completed"
            if not any(s["status"] == "in_flight" for p in state["prs"] for s in p["steps"].values()):
                state["active"] = None
            complete_if_ready(state)
    if not valid:
        raise Stop("provider read-back unavailable or mismatched")
    return {"status": "completed"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["begin", "before-step", "after-step", "run-step", "resume", "report", "check", "record-provider-result", "project-release"])
    parser.add_argument("--input")
    parser.add_argument("--repo-root")
    parser.add_argument("--target-root")
    parser.add_argument("--reserve")
    parser.add_argument("--session")
    parser.add_argument("--step")
    parser.add_argument("--repo")
    parser.add_argument("--pr", type=int)
    parser.add_argument("--phase", choices=sorted(PHASES))
    parser.add_argument("--issue")
    parser.add_argument("--status")
    parser.add_argument("--head")
    parser.add_argument("--base")
    parser.add_argument("--branch")
    parser.add_argument("--audit-repo")
    parser.add_argument("--audit-target", type=int)
    parser.add_argument("--marker")
    parser.add_argument("--expected-file")
    parser.add_argument("--exit-code", type=int, default=0)
    parser.add_argument("--executor-pid", type=int)
    parser.add_argument("--evidence")
    parser.add_argument("--version")
    parser.add_argument("--provider")
    parser.add_argument("--issue-repo")
    parser.add_argument("--project-id")
    parser.add_argument("--merged-status", default="Merged")
    parser.add_argument("--released-status", default="Released")
    parser.add_argument("--scope-issue", action="append")
    parser.add_argument("--followup-only", action="store_true")
    parser.add_argument("--require-merge-scope", action="store_true")
    parser.add_argument("--policy-skip", choices=["caller_worktree_detach_failed"])
    parser.add_argument("--no-op", action="store_true")
    parser.add_argument("--retain-executor", action="store_true")
    parser.add_argument("--continue-intent", action="store_true")
    parser.add_argument("--final", action="store_true")
    raw = sys.argv[1:]
    argv = raw[raw.index("--") + 1:] if "--" in raw else []
    args = parser.parse_args(raw[:raw.index("--")] if "--" in raw else raw)
    previous_signals = {}
    cancelled_signal = None
    try:
        if args.repo is not None:
            args.repo = repo(args.repo)
        if args.audit_repo is not None:
            args.audit_repo = repo(args.audit_repo)
        if args.command == "project-release":
            result = project_release(args)
        elif args.command == "begin":
            if not args.input and not (args.repo and args.pr and args.head and args.base):
                raise Stop("begin requires selected manifest or explicit single PR/repo/head/base")
            result = begin(args)
        elif args.command in {"resume", "report", "check"}:
            if not args.session:
                raise Stop("session required")
            if args.command == "resume":
                result = resume(args)
            else:
                state = snapshot(args.session)
                if args.command == "check":
                    context(state)
                    if args.repo_root is not None and (str(root(args.repo_root)) not in state["participants"] or str(common(args.repo_root)) != state["ownerCommonDir"]):
                        raise Stop("owner checkout differs from durable session binding")
                    if args.pr is None and args.phase == "audit":
                        candidates = [p for p in state["prs"] if any(
                            v["phase"] == "audit" and (args.step is None or v.get("id") == args.step) and v.get("auditTarget") == args.audit_target
                            and (args.audit_repo is None or repo(v.get("auditRepo")) == args.audit_repo)
                            and (args.marker is None or v.get("marker") == args.marker)
                            for v in p["steps"].values())]
                        if len(candidates) != 1:
                            raise Stop("audit destination does not have a unique frozen owner")
                        selected = candidates[0]
                    else:
                        selected = target_for(state, args)
                    if args.require_merge_scope:
                        phases = {entry["phase"] for entry in selected["steps"].values()}
                        if not state.get("projectionComplete") or not {"merge_api", "merge_verify", "cleanup"}.issubset(phases):
                            raise Stop("session has no complete frozen merge and mandatory follow-up scope")
                    if args.head is not None and args.head != selected["head"]:
                        raise Stop("reviewed head differs from frozen selection")
                    if args.branch is not None and args.branch != selected["branch"]:
                        raise Stop("cleanup branch differs from frozen selected PR")
                    if args.base is not None and args.base != selected["base"]:
                        raise Stop("approved base differs from frozen selection")
                    if args.phase is not None:
                        matches = [(k, v) for k, v in selected["steps"].items()
                                   if v["phase"] == args.phase
                                   and (args.step is None or k == args.step)
                                   and (args.audit_repo is None or repo(v.get("auditRepo")) == args.audit_repo)
                                   and (args.audit_target is None or v.get("auditTarget") == args.audit_target)
                                   and (args.marker is None or v.get("marker") == args.marker)
                                   and (args.issue is None or str(v.get("issue")) == str(args.issue))]
                        if args.phase == "tracker" and args.step is None:
                            active = state.get("active") or {}
                            owned = [x for x in matches if x[1]["status"] == "in_flight"
                                     and any(args.executor_pid == child["pid"] and child["step"] == x[0] for child in active.get("children", []))
                                     and os.environ.get("WORKFLOW_MERGE_BUDGET_TOKEN") == active.get("token") == x[1].get("token")]
                            matches = owned if len(owned) == 1 else [x for x in matches if x[1]["status"] == "pending"][:1]
                        if len(matches) != 1:
                            raise Stop("operation not uniquely frozen in manifest")
                result = summary(state, args.final)
                if args.command == "check" and args.phase is not None:
                    result["step"] = result["stepId"] = matches[0][0]
                    result["selectedRepo"], result["selectedPR"] = selected["repo"], selected["pr"]
                    resolved = matches[0][1]
                    active = state.get("active") or {}
                    result["stepStatus"] = resolved["status"]
                    result["nestedExecutionAuthorized"] = bool(
                        resolved["status"] == "in_flight"
                        and os.environ.get("WORKFLOW_MERGE_BUDGET_TOKEN") == active.get("token") == resolved.get("token")
                        and any(args.executor_pid == child["pid"] and child["step"] == matches[0][0] and child["repo"] == selected["repo"] and child["pr"] == selected["pr"] for child in active.get("children", []))
                        and (args.expected_file is None or Path(args.expected_file).read_text() == resolved.get("expectedBody")))
                if args.command == "check":
                    result["admissionValid"] = result["outcome"] == "Admitted"
                    result["definitiveAdmission"] = bool(state["started"])
        else:
            if not args.session or not args.repo or not args.pr or not args.phase:
                raise Stop("session and selected repo/PR/phase required")
            if args.command == "before-step":
                result = before(args)
            elif args.command == "after-step":
                result = after(args)
            elif args.command == "record-provider-result":
                result = provider(args)
            else:
                if not argv:
                    raise Stop("run-step requires argv after --")
                args.executor_pid = os.getpid()
                intent = before(args)
                child = None
                def interrupted(signum, frame):
                    nonlocal cancelled_signal
                    previous_mask = signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGTERM, signal.SIGINT})
                    try:
                        if cancelled_signal is None:
                            with journal(args.session) as state:
                                entry = target_for(state, args)["steps"][step_key(args)]
                                if entry.get("token") != intent["token"]:
                                    raise Stop("cancelled execution lost its durable intent")
                                state["cancellation"] = {"signal": signum, "at": now(), "attempt": state["attempt"],
                                    "revisionBefore": state["revision"]}
                                state["outcome"], state["reason"] = "Interrupted", "execution cancelled; explicit live-verified resume required"
                            cancelled_signal = signum
                        if child is not None:
                            try:
                                os.killpg(child.pid, signum)
                            except ProcessLookupError:
                                pass
                    finally:
                        signal.pthread_sigmask(signal.SIG_SETMASK, previous_mask)
                for signum in (signal.SIGTERM, signal.SIGINT):
                    previous_signals[signum] = signal.signal(signum, interrupted)
                env = dict(os.environ, WORKFLOW_MERGE_BUDGET_SESSION=args.session,
                           WORKFLOW_MERGE_BUDGET_TOKEN=intent["token"])
                env.pop("GH_REPO", None)
                env.pop("WORKFLOW_TARGET_GITHUB_REPO", None)
                read_fd, write_fd = os.pipe()
                gate = ('import os,sys; fd=int(sys.argv[1]); permission=os.read(fd,1); '
                        'os.close(fd); '
                        'sys.exit(2) if permission != b"1" else os.execvpe(sys.argv[2],sys.argv[2:],os.environ)')
                try:
                    owner_binding = snapshot(args.session)
                    selected = target_for(owner_binding, args)
                    child_cwd = None
                    if args.phase in {"local_merge", "base_push", "merge_api", "merge_verify", "remote_delete"}:
                        child_cwd = proof_root(owner_binding, selected["commonDir"], selected["root"])
                        if checkout_repo(child_cwd) != selected["repo"]:
                            raise Stop("mutation checkout differs from frozen selected repository")
                        env["GH_REPO"] = selected["repo"]
                    elif args.phase in {"tracker", "issue_close"}:
                        owning_issue = next(issue for issue in selected["issues"] if str(issue["id"]) == str(args.issue))
                        env["GH_REPO"] = owning_issue["repo"]
                        env["WORKFLOW_TARGET_GITHUB_REPO"] = owning_issue["repo"]
                    elif args.phase in {"audit", "hold"}:
                        env["GH_REPO"] = repo(selected["steps"][step_key(args)]["auditRepo"])
                    env["WORKFLOW_MERGE_BUDGET_OWNER_ROOT"] = proof_root(owner_binding, owner_binding["ownerCommonDir"], owner_binding["ownerRoot"])
                    env["WORKFLOW_MERGE_BUDGET_PR"] = str(args.pr)
                    env["WORKFLOW_MERGE_BUDGET_REPO"] = selected["repo"]
                    child = subprocess.Popen([sys.executable, "-c", gate, str(read_fd), *argv],
                                             env=env, cwd=child_cwd, pass_fds=(read_fd,), start_new_session=True)
                except (Stop, OSError) as exc:
                    os.close(read_fd)
                    os.close(write_fd)
                    with journal(args.session) as state:
                        entry = target_for(state, args)["steps"][step_key(args)]
                        if entry.get("token") != intent["token"] or entry["status"] != "in_flight":
                            raise Stop("execution intent changed during failed launch")
                        entry["status"] = "uncertain"
                        state["outcome"], state["reason"] = "Interrupted", "mutation child could not launch: " + str(exc)
                        if not any(step["status"] == "in_flight" for target in state["prs"] for step in target["steps"].values()):
                            state["active"] = None
                    raise Stop("mutation child could not launch") from exc
                os.close(read_fd)
                try:
                    with journal(args.session) as state:
                        if state.get("active", {}).get("token") != intent["token"] or state["outcome"] != "Admitted":
                            raise Stop("executor claim changed or cancelled before child publication")
                        state["active"]["childPid"] = child.pid
                        state["active"]["childGroup"] = child.pid
                        state["active"].setdefault("children", []).append({"pid": child.pid, "group": child.pid,
                            "step": step_key(args), "repo": args.repo, "pr": args.pr})
                    if cancelled_signal is not None:
                        raise Stop("execution cancelled before mutation permission")
                    os.write(write_fd, b"1")
                finally:
                    os.close(write_fd)
                args.exit_code = child.wait()
                try:
                    Path.cwd()
                except FileNotFoundError:
                    retained = snapshot(args.session)
                    os.chdir(proof_root(retained, retained["ownerCommonDir"], retained["ownerRoot"]))
                if group_alive(child.pid):
                    with journal(args.session) as state:
                        state["outcome"], state["reason"] = "Interrupted", "mutating descendant still active; live verification must wait"
                        target_for(state, args)["steps"][step_key(args)]["status"] = "uncertain"
                    raise Stop("mutating descendant still active; live verification must wait")
                result = after(args)
                result["childExitCode"] = args.exit_code
        print(json.dumps(result, sort_keys=True))
        return 0 if cancelled_signal is None and (args.command == "report" or result.get("outcome") not in {"Deferred", "Waiting", "Interrupted"}) else 2
    except (Stop, OSError, KeyError, TypeError, ValueError) as exc:
        outcome = "Deferred" if args.command == "begin" else "Interrupted"
        if args.session:
            try:
                outcome = snapshot(args.session)["outcome"]
            except (Stop, OSError, KeyError):
                pass
        print(json.dumps({"outcome": outcome, "reason": str(exc), "session": args.session}), file=sys.stderr)
        return 2
    finally:
        for signum, previous in previous_signals.items():
            signal.signal(signum, previous)


if __name__ == "__main__":
    sys.exit(main())

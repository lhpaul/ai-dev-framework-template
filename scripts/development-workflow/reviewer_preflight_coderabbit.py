#!/usr/bin/env python3
"""Shared CodeRabbit own-configuration reader.

Extracted from the embedded probe that used to live inline in
``resolve-reviewer-availability.sh`` (issue #1495) so that Step 7a's
reachability probe and the reviewer preflight (#1561) read
``.coderabbit.yaml`` through one code path instead of two that could drift
apart. Behavior for the ``enabled-bool`` mode is unchanged from the original
embedded script: same stdout contract (``true``/``false``), same stderr
message text, and the same exit codes (0 success, 3 config error, 4 missing
PyYAML dependency) that ``resolve-reviewer-availability.sh`` already depends
on for ``coderabbit-config`` / ``coderabbit-dependency`` classification.
"""

from __future__ import annotations

import argparse
import contextlib
import json
import re
import signal
import sys
import time
from pathlib import Path
from typing import Any, Iterator


class ConfigError(ValueError):
    """Raised for a malformed or unreadable .coderabbit.yaml."""


class PatternTimeoutError(RuntimeError):
    """Raised when a single base_branches regex match exceeds its bounded budget.

    A ``base_branches`` entry is operator-authored regex (documented in
    .coderabbit.yaml) reused verbatim from the shared or platform config this
    preflight reads — not sanitized against catastrophic backtracking, e.g.
    ``(a+)+$``. Confirmed live: a ~30-character crafted target base name kept
    ``re.fullmatch`` running past 10 seconds against that pattern. Without a
    bound on the match itself, that one pathological pattern exhausts this
    whole classifier subprocess's outer time budget (reviewer-preflight.sh's
    own bounded launcher then kills it and reports a generic tooling
    failure), rather than degrading only the one platform's verdict to
    Undetermined/check-inconclusive the way every other bounded read in this
    preflight already does.
    """


@contextlib.contextmanager
def _bounded_regex_match(seconds: float) -> Iterator[None]:
    if not hasattr(signal, "setitimer") or not hasattr(signal, "SIGALRM"):
        # No POSIX interval timer on this platform (e.g. Windows) — signal-
        # based bounding is unavailable here. This preflight's shell layer
        # still bounds the whole classifier subprocess; the per-pattern
        # bound below is defense in depth on top of that, not the only
        # bound, so skipping it is a narrowing of protection, not a loss of
        # it, on the platforms where it is unavailable.
        yield
        return

    def _handler(signum: int, frame: Any) -> None:
        raise PatternTimeoutError("regex match exceeded its bounded time budget")

    previous_handler = signal.signal(signal.SIGALRM, _handler)
    signal.setitimer(signal.ITIMER_REAL, seconds)
    try:
        yield
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous_handler)


def _mapping(value: Any, name: str) -> dict[str, Any]:
    if value is None:
        return {}
    if not isinstance(value, dict):
        raise ConfigError(f"{name} must be a mapping")
    return value


def _build_loader():
    import yaml

    class ConfigLoader(yaml.SafeLoader):
        # Keep YAML core true/false spellings typed; quoted strings and YAML
        # 1.1 yes/no/on/off are not CodeRabbit boolean settings.
        yaml_implicit_resolvers = {
            initial: [(tag, pattern) for tag, pattern in rules if tag != "tag:yaml.org,2002:bool"]
            for initial, rules in yaml.SafeLoader.yaml_implicit_resolvers.items()
        }

        def flatten_mapping(self, node):
            # Validate explicit keys before SafeLoader expands merges.
            # Explicit values may legitimately override merged defaults;
            # duplicates may not.
            if not hasattr(self, "checked_mappings"):
                self.checked_mappings = set()
            if node not in self.checked_mappings:
                self.checked_mappings.add(node)
                seen = set()
                for key_node, _value_node in node.value:
                    key = (
                        "<<"
                        if key_node.tag == "tag:yaml.org,2002:merge"
                        else self.construct_object(key_node)
                    )
                    try:
                        duplicate = key in seen
                        seen.add(key)
                    except TypeError as error:
                        raise yaml.constructor.ConstructorError(
                            None, None, "unsupported complex mapping key", key_node.start_mark
                        ) from error
                    if duplicate:
                        raise yaml.constructor.ConstructorError(
                            None, None, "duplicate mapping key", key_node.start_mark
                        )
            super().flatten_mapping(node)

    def construct_boolean(loader, node):
        value = loader.construct_scalar(node)
        if value not in ("true", "True", "TRUE", "false", "False", "FALSE"):
            raise yaml.constructor.ConstructorError(
                None, None, "unsupported boolean spelling", node.start_mark
            )
        return value.lower() == "true"

    ConfigLoader.add_constructor("tag:yaml.org,2002:bool", construct_boolean)
    ConfigLoader.add_implicit_resolver(
        "tag:yaml.org,2002:bool",
        re.compile(r"^(?:true|True|TRUE|false|False|FALSE)$"),
        list("tTfF"),
    )
    return ConfigLoader, yaml


def parse_coderabbit_text(text: str) -> dict[str, Any]:
    """Parse .coderabbit.yaml text into a structured, cross-checkable result.

    Returns a dict with keys:
      - ``auto_review_enabled``: bool (defaults False when the key is absent,
        matching the pre-existing Step 7a interpretation).
      - ``drafts``: bool | None (None when the key is absent — no repository
        commitment either way).
      - ``base_branches``: list[str] | None (None when the key is absent —
        no restriction is configured).

    Raises ``ConfigError`` (bad schema) or the underlying ``yaml.YAMLError``
    on a malformed document. Both are ``ValueError`` subclasses.
    """
    ConfigLoader, yaml = _build_loader()
    try:
        config = _mapping(yaml.load(text, Loader=ConfigLoader), "document")
    except yaml.YAMLError:
        raise
    reviews = _mapping(config.get("reviews"), "reviews")
    auto_review = _mapping(reviews.get("auto_review"), "reviews.auto_review")

    if "enabled" not in auto_review:
        enabled = False
    else:
        enabled = auto_review["enabled"]
        if type(enabled) is not bool:
            raise ConfigError("reviews.auto_review.enabled must be a boolean")

    drafts: bool | None = None
    if "drafts" in auto_review:
        drafts = auto_review["drafts"]
        if type(drafts) is not bool:
            raise ConfigError("reviews.auto_review.drafts must be a boolean")

    base_branches: list[str] | None = None
    if "base_branches" in auto_review:
        raw = auto_review["base_branches"]
        if not isinstance(raw, list) or not all(isinstance(item, str) for item in raw):
            raise ConfigError("reviews.auto_review.base_branches must be a list of strings")
        base_branches = raw

    return {
        "auto_review_enabled": enabled,
        "drafts": drafts,
        "base_branches": base_branches,
    }


def load_coderabbit_config(path: Path) -> dict[str, Any]:
    """Read and parse ``path``. A missing file behaves like an empty document."""
    if not path.exists():
        return {"auto_review_enabled": False, "drafts": None, "base_branches": None}
    text = path.read_text(encoding="utf-8")
    return parse_coderabbit_text(text)


def base_branch_covered(
    base_branches: list[str] | None,
    target_base: str,
    *,
    per_pattern_timeout_seconds: float = 0.5,
    aggregate_timeout_seconds: float = 3.0,
) -> bool:
    """``base_branches`` entries are regexes (documented in .coderabbit.yaml).

    Raises ``PatternTimeoutError`` if a single pattern's match against
    ``target_base`` does not complete within ``per_pattern_timeout_seconds``
    (see ``PatternTimeoutError``'s docstring), OR if the combined time spent
    across every pattern in this call exceeds ``aggregate_timeout_seconds``.
    The per-pattern bound alone does not bound this function's own total
    wall-clock time: confirmed live, 30 copies of a pattern individually
    tuned to finish just under the per-pattern bound (each a near-miss
    against a catastrophic-backtracking shape, not a full timeout) together
    still exhausted the calling classifier subprocess's own outer deadline,
    which the caller (reviewer-preflight.sh) then reports as an
    undifferentiated tooling failure (exit 3) rather than this function's
    own documented check-inconclusive degrade. Each individual pattern's
    own bound is additionally clamped to whatever aggregate budget remains,
    so a pattern late in the list cannot spend the full per-pattern budget
    after earlier patterns have already consumed most of the aggregate one.

    The caller decides how to report a raised PatternTimeoutError — this
    function does not itself know whether an earlier or later pattern in
    the list would have matched, so it cannot silently substitute True or
    False for a genuinely inconclusive result.
    """
    if base_branches is None:
        return True
    deadline = time.monotonic() + aggregate_timeout_seconds
    for pattern in base_branches:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise PatternTimeoutError(
                "aggregate base_branches match budget exceeded across the pattern list"
            )
        bound = per_pattern_timeout_seconds if per_pattern_timeout_seconds < remaining else remaining
        try:
            with _bounded_regex_match(bound):
                if re.fullmatch(pattern, target_base):
                    return True
        except re.error:
            continue
    return False


def _cmd_enabled_bool(path: Path) -> int:
    """Preserve the exact stdout/stderr/exit-code contract of the original
    embedded probe in resolve-reviewer-availability.sh."""
    try:
        import yaml  # noqa: F401
    except ImportError:
        print(
            "CodeRabbit configuration validation requires PyYAML; install "
            "PyYAML==6.0.2 for the python3 used by this gate",
            file=sys.stderr,
        )
        return 4
    try:
        result = load_coderabbit_config(path)
    except (OSError, UnicodeDecodeError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 3
    except Exception as error:  # yaml.YAMLError does not subclass ValueError on all versions
        import yaml

        if isinstance(error, yaml.YAMLError):
            print(str(error), file=sys.stderr)
            return 3
        raise
    print("true" if result["auto_review_enabled"] else "false")
    return 0


def _cmd_full_json(path: Path) -> int:
    try:
        import yaml  # noqa: F401
    except ImportError:
        print(
            "CodeRabbit configuration validation requires PyYAML; install "
            "PyYAML==6.0.2 for the python3 used by this gate",
            file=sys.stderr,
        )
        return 4
    try:
        result = load_coderabbit_config(path)
    except (OSError, UnicodeDecodeError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 3
    except Exception as error:
        import yaml

        if isinstance(error, yaml.YAMLError):
            print(str(error), file=sys.stderr)
            return 3
        raise
    print(json.dumps(result, sort_keys=True))
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Read .coderabbit.yaml (shared parser)")
    parser.add_argument(
        "--mode",
        choices=["enabled-bool", "full-json"],
        default="enabled-bool",
        help="enabled-bool: print true/false (Step 7a contract). full-json: print structured JSON (preflight).",
    )
    parser.add_argument("path", help="path to .coderabbit.yaml")
    args = parser.parse_args(argv)
    path = Path(args.path)
    if args.mode == "enabled-bool":
        return _cmd_enabled_bool(path)
    return _cmd_full_json(path)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""mockup-manifest-verify.py - verify HTML Mockup Framework manifests (#2206).

Spec: docs/specs/developments/20261126075749_2206-mockup-manifest-contract/
Contract: the "Manifest" section of
docs/workflow/development-workflow/mockup-framework.md

Called by mockup-manifest-verify.sh, which owns the command-line contract:

    manifest  <manifest-path> [--repo-root <dir>]
    tree      --repo-root <dir>          (opt-in lines from workflow_design_opt_in on stdin)
    inventory <manifest-path> [--repo-root <dir>]
    resolve   <manifest-path> --screen <id> [--state <id>] [--repo-root <dir>]

Output is KEY=value lines on stdout. Exit 0 is a non-failing outcome, 1 a
failing one, 2 a caller or environment error (stderr only, empty stdout).

A manifest is read as data, never executed (D3): one plain JSON value assigned
to window.__MOCKUP_MANIFEST__, with only comments around it. Nothing here
imports, evaluates or spawns anything for a manifest; the only subprocess is
`git rev-parse --show-toplevel` for the default repository root. The module
writes no file and uses no network. Standard library only; Python 3.9+.
"""

import json
import os
import re
import stat
import subprocess
import sys
from html.parser import HTMLParser
from urllib.parse import unquote

NAME = "window.__MOCKUP_MANIFEST__"
MANIFEST_FILE = "mockup-manifest.js"
WS = " \t\n\r\f"
JS_WS = " \t\n\r\f\v"

KINDS = (("design-intent", "Design intent"), ("reproduction", "Reproduction"))
STATUSES = (("complete", "Complete"), ("skeleton", "Skeleton"))
FRAMES = (("phone", "Phone"), ("desktop", "Desktop"), ("browser", "Browser"))
SCREEN_KINDS = (("html", "HTML"), ("image", "Image"))

SLUG = re.compile(r"[a-z][a-z0-9]*(?:-[a-z0-9]+)*")
SLUG_RULE = ("a slug: lowercase ASCII letters and digits in hyphen-separated groups, "
             "starting with a letter")
TEXT_RULE = "a non-empty string"
STATE_FORBIDDEN = ("screen_id", "kind", "export", "route", "nav_screen", "dom_id",
                   "url", "design_ref", "state_label", "states")
SCREEN_TEXT_FIELDS = ("route", "nav_screen", "dom_id", "title", "url", "design_ref",
                      "state_label")
FORM_RULE = ("expected exactly one assignment window.__MOCKUP_MANIFEST__ = <JSON object>, "
             "with only comments before and after it and an optional closing semicolon")
IMPORTANT = re.compile(r"!\s*important\s*\Z", re.IGNORECASE | re.ASCII)
SCHEME = re.compile(r"[A-Za-z][A-Za-z0-9+.\-]*:")
RESULT_LABELS = {"conforms": "Conforms", "does_not_conform": "Does not conform"}
TREE_LABELS = {
    "not_opted_in": "Not opted in",
    "invalid_configuration": "Invalid configuration",
    "no_mockups_found": "No mockups found",
    "conforms": "Conforms",
    "does_not_conform": "Does not conform",
}
CITATION_LABELS = {
    "resolves": "Resolves",
    "does_not_resolve": "Does not resolve",
    "cannot_check": "Cannot check",
}
USAGE = """usage: mockup-manifest-verify.sh <subcommand> ...
  manifest  <manifest-path> [--repo-root <dir>]
  tree      [--repo-root <dir>]
  inventory <manifest-path> [--repo-root <dir>]
  resolve   <manifest-path> --screen <id> [--state <id>] [--repo-root <dir>]"""


class UsageError(Exception):
    """A caller or environment error: exit 2, stderr only."""


class NotData(Exception):
    """The text is not in the data form; the message says why, never echoes content."""


# ── Output (#2211 escaping) ─────────────────────────────────────────────────


def escape(text):
    out = []
    for char in text:
        code = ord(char)
        if char == "\\":
            out.append("\\\\")
        elif char == "\r":
            out.append("\\r")
        elif char == "\n":
            out.append("\\n")
        elif char == "\t":
            out.append("\\t")
        elif code < 32 or code == 127:
            out.append("\\x%02x" % code)
        elif 128 <= code <= 159:
            out.append("\\u%04x" % code)
        else:
            out.append(char)
    return "".join(out)


def unescape(text):
    out = []
    i = 0
    n = len(text)
    while i < n:
        char = text[i]
        if char == "\\" and i + 1 < n:
            nxt = text[i + 1]
            if nxt == "\\":
                out.append("\\")
                i += 2
                continue
            if nxt in "rnt":
                out.append({"r": "\r", "n": "\n", "t": "\t"}[nxt])
                i += 2
                continue
            if nxt == "x" and re.match(r"[0-9a-fA-F]{2}\Z", text[i + 2:i + 4]):
                out.append(chr(int(text[i + 2:i + 4], 16)))
                i += 4
                continue
            if nxt == "u" and re.match(r"[0-9a-fA-F]{4}\Z", text[i + 2:i + 6]):
                out.append(chr(int(text[i + 2:i + 6], 16)))
                i += 6
                continue
        out.append(char)
        i += 1
    return "".join(out)


def emit(pairs):
    data = "".join("%s=%s\n" % (key, escape(value)) for key, value in pairs)
    sys.stdout.buffer.write(data.encode("utf-8", "replace"))
    sys.stdout.buffer.flush()


def emit_raw(lines):
    data = "".join(line + "\n" for line in lines)
    sys.stdout.buffer.write(data.encode("utf-8", "replace"))
    sys.stdout.buffer.flush()


def describe(value):
    if value is None:
        return "null (no value)"
    if isinstance(value, bool):
        return "a boolean (%s)" % ("true" if value else "false")
    if isinstance(value, (int, float)):
        return "a number (%r)" % value
    if isinstance(value, str):
        if value == "":
            return "an empty string"
        if len(value) > 80:
            value = value[:80] + "…"
        return "\"%s\"" % value
    if isinstance(value, list):
        return "a list" if value else "an empty list"
    if isinstance(value, dict):
        return "a mapping" if value else "an empty mapping"
    return "an unsupported value"


def accepted(values):
    return ", ".join("%s (%s)" % item for item in values)


def id_list(ids):
    shown = list(ids[:8])
    if len(ids) > 8:
        shown.append("…")
    return ", ".join(shown) if shown else "none"


def ascii_lower(text):
    return text.translate(str.maketrans("ABCDEFGHIJKLMNOPQRSTUVWXYZ",
                                        "abcdefghijklmnopqrstuvwxyz"))


def is_slug(value):
    return isinstance(value, str) and SLUG.fullmatch(value) is not None


def is_text(value):
    return isinstance(value, str) and value != ""


def is_positive_int(value):
    return isinstance(value, int) and not isinstance(value, bool) and value > 0


# ── Paths ───────────────────────────────────────────────────────────────────


def inside(path, root):
    if path == root:
        return True
    return path.startswith(root.rstrip(os.sep) + os.sep)


class Context:
    def __init__(self, repo_root):
        self.repo_root = os.path.abspath(repo_root)

    def display(self, path):
        absolute = os.path.abspath(path)
        if inside(absolute, self.repo_root):
            return os.path.relpath(absolute, self.repo_root)
        real, real_root = os.path.realpath(absolute), os.path.realpath(self.repo_root)
        if inside(real, real_root):
            return os.path.relpath(real, real_root)
        return absolute


def find_design_dir(folder):
    """The parent of the nearest folder named exactly `mockups` (BR11, P6)."""
    current = folder
    while True:
        if os.path.basename(current) == "mockups":
            return os.path.dirname(current)
        parent = os.path.dirname(current)
        if parent == current:
            return None
        current = parent


def default_root(manifest_path):
    """P10: git toplevel of the manifest folder, else the folder holding the design root."""
    folder = os.path.dirname(os.path.abspath(manifest_path))
    if os.path.isdir(folder):
        try:
            done = subprocess.run(["git", "-C", folder, "rev-parse", "--show-toplevel"],
                                  stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                  stderr=subprocess.DEVNULL, timeout=30, check=False)
        except (OSError, subprocess.SubprocessError):
            done = None
        if done is not None and done.returncode == 0:
            top = done.stdout.decode("utf-8", "replace").strip("\n")
            if top and os.path.isdir(top):
                return top
    design = find_design_dir(folder)
    if design is not None:
        return os.path.dirname(design)
    return folder


# ── Reading files (P4 step 1) ───────────────────────────────────────────────


def read_regular_file(path):
    """Bytes of a regular file, or None. Never blocks on a FIFO or device."""
    try:
        info = os.stat(path)
    except (OSError, ValueError):
        return None
    if not stat.S_ISREG(info.st_mode):
        return None
    flags = os.O_RDONLY | getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_CLOEXEC", 0)
    try:
        fd = os.open(path, flags)
    except (OSError, ValueError):
        return None
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            return None
        chunks = []
        while True:
            chunk = os.read(fd, 1 << 20)
            if not chunk:
                break
            chunks.append(chunk)
        return b"".join(chunks)
    except OSError:
        return None
    finally:
        os.close(fd)


def decode_text(raw):
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        return None
    return text[1:] if text.startswith("﻿") else text


def missing_or_unreadable(path):
    try:
        exists = os.path.lexists(path)
    except ValueError:
        exists = False
    return "absent" if not exists else "found a path that is not a readable regular file"


# ── Strict JSON ─────────────────────────────────────────────────────────────


def _pairs(pairs):
    obj = {}
    for key, value in pairs:
        if key in obj:
            raise NotData("duplicate key %s in a JSON object" % describe(key))
        obj[key] = value
    return obj


def _constant(name):
    raise NotData("the non-finite number %s is not JSON" % name)


DECODER = json.JSONDecoder(object_pairs_hook=_pairs, parse_constant=_constant)


def decode_json_at(text, index):
    try:
        return DECODER.raw_decode(text, index)
    except NotData:
        raise
    except RecursionError:
        raise NotData("the JSON value is nested too deeply to read") from None
    except ValueError as exc:
        line = getattr(exc, "lineno", None)
        column = getattr(exc, "colno", None)
        if isinstance(line, int) and isinstance(column, int):
            raise NotData("the value is not valid JSON (line %d, column %d)"
                          % (line, column)) from None
        raise NotData("the value is not valid JSON") from None


def decode_json_document(text):
    index = 0
    while index < len(text) and text[index] in JS_WS:
        index += 1
    value, end = decode_json_at(text, index)
    while end < len(text) and text[end] in JS_WS:
        end += 1
    if end != len(text):
        raise NotData("text follows the JSON value")
    return value


# ── The manifest file form (BR1, verification rows 1 to 3) ─────────────────


def skip_space_and_comments(text, index):
    n = len(text)
    while index < n:
        char = text[index]
        if char in JS_WS:
            index += 1
        elif text.startswith("//", index):
            while index < n and text[index] not in "\r\n":
                index += 1
        elif text.startswith("/*", index):
            end = text.find("*/", index + 2)
            if end < 0:
                raise NotData("a /* block comment is not closed")
            index = end + 2
        else:
            break
    return index


def read_manifest(path):
    """Return (object, None) or (None, problem) for rows 1 to 3."""
    raw = read_regular_file(path)
    if raw is None:
        return None, ("BR1 manifest: manifest file not found or unreadable: %s; "
                      "expected a readable regular file" % missing_or_unreadable(path))
    text = decode_text(raw)
    if text is None:
        return None, "BR1 manifest: not readable as data: not UTF-8 text; " + FORM_RULE
    try:
        index = skip_space_and_comments(text, 0)
        if not text.startswith(NAME, index):
            raise NotData("the file does not start with the assignment to "
                          "window.__MOCKUP_MANIFEST__ (other code, or no assignment)")
        index = skip_space_and_comments(text, index + len(NAME))
        if index >= len(text) or text[index] != "=" or text.startswith("==", index):
            raise NotData("window.__MOCKUP_MANIFEST__ is not followed by =")
        index = skip_space_and_comments(text, index + 1)
        if index >= len(text):
            raise NotData("no value is assigned")
        value, index = decode_json_at(text, index)
        index = skip_space_and_comments(text, index)
        if index < len(text) and text[index] == ";":
            index = skip_space_and_comments(text, index + 1)
        if index != len(text):
            raise NotData("other code follows the assignment")
    except NotData as exc:
        return None, "BR1 manifest: not readable as data: %s; %s" % (exc, FORM_RULE)
    if not isinstance(value, dict):
        return None, ("BR1 manifest: manifest is not an object: found %s; "
                      "expected a JSON object" % describe(value))
    return value, None


# ── Field checks (row 4, P5) ────────────────────────────────────────────────


class Problems:
    def __init__(self):
        self.lines = []

    def add(self, rule, place, detail):
        self.lines.append("%s %s: %s" % (rule, place, detail))

    def absent(self, rule, place, field, expected):
        self.add(rule, place, "%s: absent; expected %s" % (field, expected))

    def found(self, rule, place, field, value, expected, why=""):
        self.add(rule, place, "%s: found %s%s; expected %s" % (field, describe(value), why, expected))

    def text(self, place, obj, field):
        if field in obj and not is_text(obj[field]):
            self.found("BR19", place, field, obj[field], TEXT_RULE)

    def enum(self, rule, place, obj, field, values):
        if field not in obj:
            self.absent(rule, place, field, accepted(values))
        elif not (isinstance(obj[field], str) and obj[field] in dict(values)):
            self.found(rule, place, field, obj[field], accepted(values))


def check_fields(manifest, problems):
    screens = manifest.get("screens")
    screen_list = screens if isinstance(screens, list) else []
    known_order = []
    for screen in screen_list:
        if isinstance(screen, dict) and isinstance(screen.get("screen_id"), str):
            if screen["screen_id"] not in known_order:
                known_order.append(screen["screen_id"])
    known = set(known_order)
    known_rule = "a screen_id that exists in screens (%s)" % id_list(known_order)
    unknown_why = ", which is not a screen_id in screens"

    # 1. Top-level fields, in BR2 table order.
    problems.enum("BR2", "manifest", manifest, "$kind", KINDS)
    problems.enum("BR2", "manifest", manifest, "$status", STATUSES)
    if "default_screen" not in manifest:
        problems.absent("BR2", "manifest", "default_screen", known_rule)
    elif not (isinstance(manifest["default_screen"], str) and manifest["default_screen"] in known):
        why = unknown_why if isinstance(manifest["default_screen"], str) else ""
        problems.found("BR2", "manifest", "default_screen", manifest["default_screen"], known_rule, why)
    problems.enum("BR2", "manifest", manifest, "frame", FRAMES)
    viewports_rule = "a non-empty list of viewports, each with id, label, width and height, or omit viewports"
    if "viewports" in manifest and not (isinstance(manifest["viewports"], list) and manifest["viewports"]):
        problems.found("BR8", "manifest", "viewports", manifest["viewports"], viewports_rule)
    navigation_rule = "a list of navigation groups, each with label and items (the list may be empty)"
    if "navigation" not in manifest:
        problems.absent("BR2", "manifest", "navigation", navigation_rule)
    elif not isinstance(manifest["navigation"], list):
        problems.found("BR7", "manifest", "navigation", manifest["navigation"], navigation_rule)
    screens_rule = "a non-empty list of screens"
    if "screens" not in manifest:
        problems.absent("BR2", "manifest", "screens", screens_rule)
    elif not (isinstance(screens, list) and screens):
        problems.found("BR2", "manifest", "screens", screens, screens_rule)

    # 2. Screens, in list order, each with its states.
    seen = {}
    for index, screen in enumerate(screen_list):
        if not isinstance(screen, dict):
            problems.found("BR19", "screens[%d]" % index, "entry", screen, "an object")
            continue
        screen_id = screen.get("screen_id")
        usable = is_slug(screen_id) and screen_id not in seen
        place = "screen %s" % screen_id if usable else "screens[%d]" % index
        if "screen_id" not in screen:
            problems.absent("BR3", place, "screen_id", SLUG_RULE + ", unique across screens")
        elif not is_slug(screen_id):
            problems.found("BR6", place, "screen_id", screen_id,
                           SLUG_RULE + "; a design-tool frame name is never a screen_id")
        elif screen_id in seen:
            problems.found("BR3", place, "screen_id", screen_id, "a screen_id unique across screens",
                           ", which duplicates screens[%d]" % seen[screen_id])
        else:
            seen[screen_id] = index
        problems.enum("BR3", place, screen, "kind", SCREEN_KINDS)
        if "export" in screen:
            problems.text(place, screen, "export")
        elif screen.get("kind") == "image":
            problems.absent("BR3", place, "export",
                            "the path of the exported image, required when kind is image")
        for field in SCREEN_TEXT_FIELDS:
            problems.text(place, screen, field)
            if field == "nav_screen" and is_text(screen.get(field)) and screen[field] not in known:
                problems.found("BR3", place, "nav_screen", screen[field], known_rule, unknown_why)
        if "states" in screen:
            states = screen["states"]
            if not (isinstance(states, list) and states):
                problems.found("BR3", place, "states", states,
                               "a non-empty list of states, or omit states")
            else:
                check_states(place, states, problems)

    # 3. Navigation, depth first (iterative).
    navigation = manifest.get("navigation")
    if isinstance(navigation, list):
        stack = [("navigation[%d]" % i, node, True) for i, node in enumerate(navigation)]
        stack.reverse()
        while stack:
            path, node, is_group = stack.pop()
            if not isinstance(node, dict):
                expected = ("an object with label and items" if is_group
                            else "an object with screen_id")
                problems.found("BR7", path, "entry", node, expected)
                continue
            if is_group:
                if "label" not in node:
                    problems.absent("BR7", path, "label", TEXT_RULE)
                else:
                    problems.text(path, node, "label")
                if "items" not in node:
                    problems.absent("BR7", path, "items", "a list of navigation entries (it may be empty)")
            else:
                if "screen_id" not in node:
                    problems.absent("BR7", path, "screen_id", known_rule)
                elif not (isinstance(node["screen_id"], str) and node["screen_id"] in known):
                    why = unknown_why if isinstance(node["screen_id"], str) else ""
                    problems.found("BR7", path, "screen_id", node["screen_id"], known_rule, why)
                problems.text(path, node, "label")
            items = node.get("items")
            if "items" in node and not isinstance(items, list):
                problems.found("BR7", path, "items", items, "a list of navigation entries (it may be empty)")
            elif isinstance(items, list):
                children = [("%s.items[%d]" % (path, i), child, False) for i, child in enumerate(items)]
                children.reverse()
                stack.extend(children)

    # 4. Viewports.
    viewports = manifest.get("viewports")
    if isinstance(viewports, list):
        seen_viewports = {}
        for index, viewport in enumerate(viewports):
            if not isinstance(viewport, dict):
                problems.found("BR19", "viewports[%d]" % index, "entry", viewport, "an object")
                continue
            viewport_id = viewport.get("id")
            usable = is_slug(viewport_id) and viewport_id not in seen_viewports
            place = "viewport %s" % viewport_id if usable else "viewports[%d]" % index
            if "id" not in viewport:
                problems.absent("BR8", place, "id", SLUG_RULE + ", unique across viewports")
            elif not is_slug(viewport_id):
                problems.found("BR6", place, "id", viewport_id, SLUG_RULE)
            elif viewport_id in seen_viewports:
                problems.found("BR8", place, "id", viewport_id, "a viewport id unique across viewports",
                               ", which duplicates viewports[%d]" % seen_viewports[viewport_id])
            else:
                seen_viewports[viewport_id] = index
            if "label" not in viewport:
                problems.absent("BR8", place, "label", TEXT_RULE)
            else:
                problems.text(place, viewport, "label")
            for field in ("width", "height"):
                if field not in viewport:
                    problems.absent("BR8", place, field, "a positive whole number")
                elif not is_positive_int(viewport[field]):
                    problems.found("BR8", place, field, viewport[field], "a positive whole number")


def check_states(screen_place, states, problems):
    seen = {}
    initial_true = []
    for index, state in enumerate(states):
        if not isinstance(state, dict):
            problems.found("BR19", "%s states[%d]" % (screen_place, index), "entry", state, "an object")
            continue
        state_id = state.get("state_id")
        usable = is_slug(state_id) and state_id not in seen
        place = ("%s state %s" % (screen_place, state_id) if usable
                 else "%s states[%d]" % (screen_place, index))
        if "state_id" not in state:
            problems.absent("BR4", place, "state_id", SLUG_RULE + ", unique within its screen")
        elif not is_slug(state_id):
            problems.found("BR6", place, "state_id", state_id, SLUG_RULE)
        elif state_id in seen:
            problems.found("BR4", place, "state_id", state_id, "a state_id unique within its screen",
                           ", which duplicates states[%d]" % seen[state_id])
        else:
            seen[state_id] = index
        if "initial" in state:
            if not isinstance(state["initial"], bool):
                problems.found("BR4", place, "initial", state["initial"], "true or false")
            elif state["initial"]:
                initial_true.append(state_id if usable else "states[%d]" % index)
        problems.text(place, state, "label")
        problems.text(place, state, "title")
        for field in STATE_FORBIDDEN:
            if field in state:
                problems.found("BR5", place, field, state[field],
                               "absent, because a state never declares a screen-level field; "
                               "a visual variant is a state of its screen")
    rule = "exactly one state of the screen with initial true"
    if not initial_true:
        problems.add("BR4", screen_place, "initial: absent (no state sets initial true); expected " + rule)
    elif len(initial_true) > 1:
        problems.add("BR4", screen_place, "initial: found true on %d states (%s); expected %s"
                     % (len(initial_true), ", ".join(initial_true), rule))


# ── Token mirroring (P6, BR10, BR11) ────────────────────────────────────────


class PageParser(HTMLParser):
    """Collects <style> text, stylesheet links and the root element's style attribute."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.items = []
        self._style = None
        self._seen_html = False

    def handle_starttag(self, tag, attrs):
        line = self.getpos()[0]
        if tag == "style":
            start = line + (self.get_starttag_text() or "").count("\n")
            self._style = (start, [])
        elif tag == "link":
            rel = href = None
            for key, value in attrs:
                if key == "rel" and rel is None:
                    rel = value or ""
                elif key == "href" and href is None:
                    href = value or ""
            rel_tokens = [ascii_lower(t) for t in re.split(r"[ \t\n\f\r]+", rel or "") if t]
            if "stylesheet" in rel_tokens and href:
                self.items.append(("link", line, href))
        elif tag == "html" and not self._seen_html:
            self._seen_html = True
            for key, value in attrs:
                if key == "style":
                    if value:
                        self.items.append(("attr", line, value))
                    break

    def handle_data(self, data):
        if self._style is not None:
            self._style[1].append(data)

    def handle_endtag(self, tag):
        if tag == "style" and self._style is not None:
            self.items.append(("style", self._style[0], "".join(self._style[1])))
            self._style = None

    def close(self):
        super().close()
        if self._style is not None:
            self.items.append(("style", self._style[0], "".join(self._style[1])))
            self._style = None


def css_chars(text, first_line):
    """Characters with each comment replaced by one space: (char, structural, line).

    A comment separates tokens, as in a browser, so `a/**/b` is `a b`, never
    `ab`.

    `structural` is False inside strings, after a backslash escape, and inside
    parentheses or brackets (except braces, which always nest)."""
    out = []
    n = len(text)
    i = 0
    line = first_line
    depth = 0
    while i < n:
        char = text[i]
        if char == "/" and text.startswith("/*", i):
            end = text.find("*/", i + 2)
            stop = n if end < 0 else end + 2
            out.append((" ", depth == 0, line))
            line += text.count("\n", i, stop)
            i = stop
            continue
        if char in "\"'":
            out.append((char, False, line))
            i += 1
            while i < n:
                inner = text[i]
                if inner == "\\" and i + 1 < n:
                    out.append((inner, False, line))
                    out.append((text[i + 1], False, line))
                    if text[i + 1] == "\n":
                        line += 1
                    i += 2
                    continue
                if inner == "\n":
                    break  # an unterminated string ends at the line break
                out.append((inner, False, line))
                i += 1
                if inner == char:
                    break
            continue
        if char == "\\" and i + 1 < n:
            out.append((char, False, line))
            out.append((text[i + 1], False, line))
            if text[i + 1] == "\n":
                line += 1
            i += 2
            continue
        if char in "([":
            depth += 1
        elif char in ")]":
            depth = max(0, depth - 1)
        elif char in "{}":
            depth = 0
        out.append((char, depth == 0, line))
        if char == "\n":
            line += 1
        i += 1
    return out


def chars_text(chars):
    return "".join(item[0] for item in chars)


def is_root_rule(prelude):
    parts = [[]]
    for item in prelude:
        if item[0] == "," and item[1]:
            parts.append([])
        else:
            parts[-1].append(item)
    return any(ascii_lower(chars_text(part).strip(WS)) == ":root" for part in parts)


def add_declaration(buffer, declarations):
    colon = None
    for index, item in enumerate(buffer):
        if item[0] == ":" and item[1]:
            colon = index
            break
    if colon is None:
        return
    name = chars_text(buffer[:colon]).strip(WS)
    if not name.startswith("--"):
        return
    rest = buffer[colon + 1:]
    value = chars_text(rest)
    important = False
    match = IMPORTANT.search(value)
    if match and all(rest[k][1] for k in range(match.start(), match.end())):
        important = True
        value = value[:match.start()]
    line = next((item[2] for item in buffer if item[0] not in WS), buffer[0][2])
    declarations.append((name, value.strip(WS), important, line))


def parse_declarations(text, first_line, declarations_only):
    """Custom-property declarations of plain `:root` rules (or of a style attribute)."""
    declarations = []
    stack = ["decl" if declarations_only else "list"]
    buffer = []
    for item in css_chars(text, first_line):
        char, structural = item[0], item[1]
        context = stack[-1]
        if not structural or char not in "{};":
            if context != "skip":
                buffer.append(item)
            continue
        if char == "{":
            prelude = chars_text(buffer).strip(WS)
            if context == "skip":
                stack.append("skip")
            elif context == "list":
                if prelude.startswith("@"):
                    stack.append("list")
                else:
                    stack.append("decl" if is_root_rule(buffer) else "skip")
            else:
                # Inside a :root rule: a nested at-rule's block holds more
                # :root declarations; a nested qualified rule is never :root.
                stack.append("decl" if prelude.startswith("@") else "skip")
            buffer = []
        elif char == "}":
            if context == "decl":
                add_declaration(buffer, declarations)
            buffer = []
            if len(stack) > 1:
                stack.pop()
        else:
            if context == "decl":
                add_declaration(buffer, declarations)
            buffer = []
    if stack[-1] == "decl" and buffer:
        add_declaration(buffer, declarations)
    return declarations


def read_tokens(path, ctx, problems):
    shown = ctx.display(path)
    expected = "expected a readable UTF-8 JSON object file"
    raw = read_regular_file(path)
    if raw is None:
        problems.add("BR11", "manifest", "token file %s: %s; %s"
                     % (shown, missing_or_unreadable(path), expected))
        return None
    text = decode_text(raw)
    if text is None:
        problems.add("BR11", "manifest", "token file %s: found text that is not UTF-8; %s" % (shown, expected))
        return None
    try:
        value = decode_json_document(text)
    except NotData as exc:
        problems.add("BR11", "manifest", "token file %s: found text that is not valid JSON (%s); %s"
                     % (shown, exc, expected))
        return None
    if not isinstance(value, dict):
        problems.add("BR11", "manifest", "token file %s: found %s; expected a JSON object"
                     % (shown, describe(value)))
        return None
    return value


def token_list(tokens, problems):
    found = []
    stack = [((key,), value) for key, value in tokens.items() if not key.startswith("$")]
    stack.reverse()
    while stack:
        path, value = stack.pop()
        if isinstance(value, dict):
            children = [(path + (key,), sub) for key, sub in value.items() if not key.startswith("$")]
            children.reverse()
            stack.extend(children)
        elif isinstance(value, str):
            found.append((path, value))
        else:
            problems.found("BR10", "token %s" % ".".join(path), "value", value,
                           "a string, mirrored as --%s in :root" % "-".join(path))
    return found


def link_target(href, folder, ctx):
    """The in-repository path a stylesheet href names, or None when not read (BR10 limitation)."""
    path = re.split(r"[?#]", href, maxsplit=1)[0]
    if not path or SCHEME.match(path) or path.startswith("/"):
        return None
    path = unquote(path)
    if not path or SCHEME.match(path) or path.startswith("/"):
        return None
    target = os.path.normpath(os.path.join(folder, path))
    if not inside(os.path.realpath(target), os.path.realpath(ctx.repo_root)):
        return None
    return target


def collect_sources(page, folder, ctx, problems):
    shown = ctx.display(page)
    expected = "expected a readable UTF-8 index.html beside the manifest"
    raw = read_regular_file(page)
    if raw is None:
        problems.add("BR11", "manifest", "page %s: %s; %s" % (shown, missing_or_unreadable(page), expected))
        return None
    text = decode_text(raw)
    if text is None:
        problems.add("BR11", "manifest", "page %s: found text that is not UTF-8; %s" % (shown, expected))
        return None
    parser = PageParser()
    try:
        parser.feed(text)
        parser.close()
    except Exception:  # html.parser is lenient; never let odd markup crash the check
        problems.add("BR11", "manifest", "page %s: found HTML that could not be read; %s" % (shown, expected))
        return None
    sources = []
    style_count = 0
    for kind, line, value in parser.items:
        if kind == "style":
            style_count += 1
            sources.append(("index.html <style> #%d" % style_count,
                            parse_declarations(value, line, False)))
        elif kind == "attr":
            sources.append(("index.html <html style>", parse_declarations(value, line, True)))
        else:
            target = link_target(value, folder, ctx)
            if target is None:
                continue
            name = ctx.display(target)
            sheet_expected = "expected a readable UTF-8 stylesheet"
            raw_sheet = read_regular_file(target)
            if raw_sheet is None:
                problems.add("BR11", "manifest", "stylesheet %s linked from index.html: %s; %s"
                             % (name, missing_or_unreadable(target), sheet_expected))
                continue
            sheet = decode_text(raw_sheet)
            if sheet is None:
                problems.add("BR11", "manifest", "stylesheet %s linked from index.html: "
                             "found text that is not UTF-8; %s" % (name, sheet_expected))
                continue
            sources.append((name, parse_declarations(sheet, 1, False)))
    return sources


def check_mirroring(manifest_path, ctx, problems):
    folder = os.path.dirname(os.path.abspath(manifest_path))
    design_dir = find_design_dir(folder)
    tokens = None
    if design_dir is None:
        problems.add("BR11", "manifest", "token file: absent, because the manifest is not inside a "
                     "mockups folder; expected the manifest inside a mockups folder whose parent "
                     "folder holds tokens.json")
    else:
        tokens = read_tokens(os.path.join(design_dir, "tokens.json"), ctx, problems)
    sources = collect_sources(os.path.join(folder, "index.html"), folder, ctx, problems)
    if tokens is None:
        return
    tokens_found = token_list(tokens, problems)
    if sources is None:
        return
    by_name = {}
    for source, declarations in sources:
        for name, value, important, line in declarations:
            by_name.setdefault(name, []).append((source, line, value, important))
    for path, raw_value in tokens_found:
        prop = "--" + "-".join(path)
        want = raw_value.strip(WS)
        place = "token %s" % ".".join(path)
        declared = by_name.get(prop, [])
        if not declared:
            problems.add("BR10", place, "%s: absent from the :root rules; expected %s: %s in a :root "
                         "rule of index.html or of a stylesheet it links inside the repository"
                         % (prop, prop, want))
        for source, line, value, important in declared:
            where = "%s in %s line %d" % (prop, source, line)
            if value != want:
                problems.found("BR10", place, where, value, describe(want))
            if important:
                problems.add("BR10", place, "%s: found !important; expected a declaration without "
                             "!important" % where)


# ── Verification ────────────────────────────────────────────────────────────


class Result:
    def __init__(self, path, shown):
        self.path = path
        self.shown = shown
        self.manifest = None
        self.kind = ""
        self.problems = []

    @property
    def conforms(self):
        return not self.problems

    @property
    def code(self):
        return "conforms" if self.conforms else "does_not_conform"


def verify(path, ctx):
    result = Result(path, ctx.display(path))
    manifest, problem = read_manifest(path)
    if problem is not None:
        result.problems = [problem]
        return result
    result.manifest = manifest
    if isinstance(manifest.get("$kind"), str):
        result.kind = manifest["$kind"]
    problems = Problems()
    check_fields(manifest, problems)
    if manifest.get("$kind") == "design-intent":
        check_mirroring(path, ctx, problems)
    result.problems = problems.lines
    return result


def manifest_pairs(result):
    pairs = [("MANIFEST_RESULT", result.code), ("MANIFEST_RESULT_LABEL", RESULT_LABELS[result.code]),
             ("MANIFEST_PATH", result.shown), ("MANIFEST_KIND", result.kind),
             ("PROBLEM_COUNT", str(len(result.problems)))]
    return pairs + [("PROBLEM", problem) for problem in result.problems]


# ── Subcommands ─────────────────────────────────────────────────────────────


def parse_args(argv, positional, options, required=()):
    values = {}
    rest = []
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg.startswith("--"):
            name, sep, inline = arg.partition("=")
            if name not in options:
                raise UsageError("unknown option: %s" % name)
            if name in values:
                raise UsageError("%s given more than once" % name)
            if sep:
                value = inline
            else:
                if i + 1 >= len(argv):
                    raise UsageError("%s needs a value" % name)
                i += 1
                value = argv[i]
            if value == "":
                raise UsageError("%s needs a non-empty value" % name)
            values[name] = value
        else:
            rest.append(arg)
        i += 1
    if len(rest) != positional:
        raise UsageError("expected %d manifest path argument(s), found %d" % (positional, len(rest)))
    for name in required:
        if name not in values:
            raise UsageError("%s is required" % name)
    root = values.get("--repo-root")
    if root is not None and not os.path.isdir(root):
        raise UsageError("--repo-root is not a directory: %s" % escape(root))
    return rest, values


def context_for(manifest_path, values):
    root = values.get("--repo-root")
    return Context(root if root is not None else default_root(manifest_path))


def cmd_manifest(argv):
    rest, values = parse_args(argv, 1, ("--repo-root",))
    result = verify(rest[0], context_for(rest[0], values))
    emit(manifest_pairs(result))
    return 0 if result.conforms else 1


def screen_states(screen):
    states = screen.get("states")
    return states if isinstance(states, list) else []


def cmd_inventory(argv):
    rest, values = parse_args(argv, 1, ("--repo-root",))
    result = verify(rest[0], context_for(rest[0], values))
    if not result.conforms:
        emit([("INVENTORY_RESULT", "cannot_check"), ("INVENTORY_RESULT_LABEL", "Cannot check")]
             + manifest_pairs(result))
        return 1
    screens = result.manifest["screens"]
    pairs = [("INVENTORY_RESULT", "listed"), ("INVENTORY_RESULT_LABEL", "Listed"),
             ("SCREEN_COUNT", str(len(screens)))]
    for n, screen in enumerate(screens, 1):
        screen_id = screen["screen_id"]
        states = screen_states(screen)
        pairs += [("SCREEN_%d_ID" % n, screen_id), ("SCREEN_%d_LINK" % n, "#screen=%s" % screen_id),
                  ("SCREEN_%d_STATE_COUNT" % n, str(len(states)))]
        for m, state in enumerate(states, 1):
            prefix = "SCREEN_%d_STATE_%d" % (n, m)
            pairs += [(prefix + "_ID", state["state_id"]),
                      (prefix + "_INITIAL", "true" if state.get("initial") is True else "false"),
                      (prefix + "_LINK", "#screen=%s&state=%s" % (screen_id, state["state_id"]))]
    emit(pairs)
    return 0


def cmd_resolve(argv):
    rest, values = parse_args(argv, 1, ("--repo-root", "--screen", "--state"), required=("--screen",))
    result = verify(rest[0], context_for(rest[0], values))
    screen_id = values["--screen"]
    state_id = values.get("--state")

    def answer(code, reason, link=None, extra=()):
        pairs = [("CITATION_RESULT", code), ("CITATION_RESULT_LABEL", CITATION_LABELS[code]),
                 ("CITATION_REASON", reason)]
        if link is not None:
            pairs.append(("CITATION_LINK", link))
        emit(pairs + list(extra))
        return 0 if code == "resolves" else 1

    if not result.conforms:
        return answer("cannot_check", "manifest_does_not_conform", extra=manifest_pairs(result))
    screen = next((s for s in result.manifest["screens"] if s["screen_id"] == screen_id), None)
    if screen is None:
        return answer("does_not_resolve", "unknown_screen")
    if state_id is None:
        return answer("resolves", "none", "#screen=%s" % screen_id)
    if not any(state["state_id"] == state_id for state in screen_states(screen)):
        return answer("does_not_resolve", "unknown_state")
    return answer("resolves", "none", "#screen=%s&state=%s" % (screen_id, state_id))


def walk_tree(mockups):
    """P8: (manifest paths, unreadable folder paths, mockups folder confirmed missing)."""
    manifests = []
    unreadable = []
    try:
        info = os.lstat(mockups)
    except (FileNotFoundError, NotADirectoryError):
        return manifests, unreadable
    except OSError:
        return manifests, [mockups]
    if not stat.S_ISDIR(info.st_mode):
        return manifests, [mockups]
    stack = [mockups]
    while stack:
        folder = stack.pop()
        try:
            with os.scandir(folder) as listing:
                entries = sorted(listing, key=lambda entry: entry.name)
        except OSError:
            unreadable.append(folder)
            continue
        subfolders = []
        for entry in entries:
            if folder == mockups and entry.name == "shared":
                continue
            try:
                real_dir = entry.is_dir(follow_symlinks=False)
                link = entry.is_symlink()
            except OSError:
                unreadable.append(entry.path)
                continue
            if entry.name == MANIFEST_FILE and not real_dir:
                manifests.append(entry.path)
            elif real_dir:
                subfolders.append(entry.path)
            elif link and os.path.isdir(entry.path):
                unreadable.append(entry.path)
        subfolders.reverse()
        stack.extend(subfolders)
    return manifests, unreadable


def cmd_tree(argv):
    _, values = parse_args(argv, 0, ("--repo-root",), required=("--repo-root",))
    ctx = Context(values["--repo-root"])
    lines = sys.stdin.buffer.read().decode("utf-8", "replace").split("\n")
    while lines and lines[-1] == "":
        lines.pop()
    if not lines or not lines[0].startswith("DESIGN_OPT_IN="):
        raise UsageError("the design opt-in check gave no DESIGN_OPT_IN= outcome")
    fields = {}
    problem_lines = []
    for line in lines:
        key, _, value = line.partition("=")
        if key in ("DESIGN_PROBLEM_COUNT", "DESIGN_PROBLEM"):
            problem_lines.append(line)
        fields.setdefault(key, value)
    state = fields["DESIGN_OPT_IN"]
    if state == "not_opted_in":
        emit([("TREE_RESULT", "not_opted_in"), ("TREE_RESULT_LABEL", TREE_LABELS["not_opted_in"])])
        return 0
    if state == "invalid":
        emit([("TREE_RESULT", "invalid_configuration"),
              ("TREE_RESULT_LABEL", TREE_LABELS["invalid_configuration"])])
        emit_raw(problem_lines)
        return 1
    if state != "opted_in" or "DESIGN_ROOT" not in fields:
        raise UsageError("the design opt-in check gave an unexpected outcome")
    design_root = unescape(fields["DESIGN_ROOT"])
    mockups = os.path.normpath(os.path.join(ctx.repo_root, design_root, "mockups"))
    manifests, unreadable = walk_tree(mockups)
    results = sorted((verify(path, ctx) for path in manifests), key=lambda r: r.shown)
    unreadable_shown = sorted(ctx.display(path) for path in unreadable)
    if unreadable_shown:
        code = "does_not_conform"
    elif not results:
        code = "no_mockups_found"
    elif all(result.conforms for result in results):
        code = "conforms"
    else:
        code = "does_not_conform"
    pairs = [("TREE_RESULT", code), ("TREE_RESULT_LABEL", TREE_LABELS[code]),
             ("DESIGN_ROOT", design_root), ("MOCKUPS_FOLDER", ctx.display(mockups)),
             ("UNREADABLE_FOLDER_COUNT", str(len(unreadable_shown)))]
    pairs += [("UNREADABLE_FOLDER", shown) for shown in unreadable_shown]
    pairs.append(("MANIFEST_COUNT", str(len(results))))
    for n, result in enumerate(results, 1):
        pairs += [("MANIFEST_%d_PATH" % n, result.shown), ("MANIFEST_%d_RESULT" % n, result.code),
                  ("MANIFEST_%d_PROBLEM_COUNT" % n, str(len(result.problems)))]
        pairs += [("MANIFEST_%d_PROBLEM" % n, problem) for problem in result.problems]
    emit(pairs)
    return 1 if code == "does_not_conform" else 0


COMMANDS = {"manifest": cmd_manifest, "tree": cmd_tree, "inventory": cmd_inventory,
            "resolve": cmd_resolve}


def main(argv):
    try:
        if not argv or argv[0] not in COMMANDS:
            raise UsageError("unknown or missing subcommand")
        return COMMANDS[argv[0]](argv[1:])
    except UsageError as exc:
        sys.stderr.write("mockup-manifest-verify: %s\n%s\n" % (exc, USAGE))
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

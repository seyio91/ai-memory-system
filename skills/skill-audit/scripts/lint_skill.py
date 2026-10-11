#!/usr/bin/env python3
"""Mechanical skill checks. Usage: lint_skill.py <skill-folder | folder-of-skills>

Each finding has a status: "fail" (deterministic), "candidate" (heuristic, the
model must confirm) or "error" (rule 0: a file could not be read; the message
names the file and the OS error).
"""
import json
import os
import re
import sys
from urllib.parse import unquote

BODY_LIMIT = 500
REF_LIMIT = 100
MIN_EVALS = 3
EXCLUDED_DIRS = ("evals", "scripts")
VENDORED_DIRS = ("node_modules", "__pycache__", "venv", "site-packages")

LINK_RE = re.compile(r"\[[^\]]*\]\(\s*(?:<([^>]+)>|([^)\s]+))[^)]*\)")
REFDEF_RE = re.compile(r"^ {0,3}\[(?!\^)[^\]]+\]:\s*(?:<([^>]+)>|(\S+))")
CODE_SPAN_RE = re.compile(r"`[^`]*`")
BACKTICK_MD_RE = re.compile(r"`([\w./-]+\.md)`")
FIRST_I_RE = re.compile(r"(?<![\w/\-])(I'm|I'll|I've|I)(?![\w/\-])")
QUOTED_RE = re.compile(r"\"[^\"]*\"|(?<!\w)'[^']*'(?!\w)|`[^`]*`")
PERSON_RE = re.compile(
    r"(?<![\w/\-.])(?:(?i:you(?:'d|'re|'ll|'ve)?|your|yours|my(?= ))|[Ww]e|[Oo]ur|[Uu]s|[Mm]e)(?![\w/\-]|\.\w)")
ROMAN_PREFIX_RE = re.compile(r"\b(act|phase|part|stage|type|tier|step|section|grade|chapter|level)\s+$", re.I)
EXEMPT_ROOT_DOCS = ("readme.md", "license.md", "changelog.md", "agents.md", "claude.md", "self-rating.md")
WIN_PATH_RE = re.compile(r"[A-Za-z]:\\(?![\\`*_{}\[\]()#+\-.!|])|\w+\\(?![\\`*_{}\[\]()#+\-.!|])\w+\.\w+")
ABS_PATH_RE = re.compile(r"/(?:Users|home)/[A-Za-z0-9._-]+/")
IMPERATIVE_RE = re.compile(r"\b(never|always|must)\b", re.I)
ECHO_RE = re.compile(
    r"think (step by step|out loud)|show (your|the) (reasoning|thinking|work)"
    r"|explain your reasoning|write out your (reasoning|thinking)|chain of thought",
    re.I,
)
CONTENTS_HEAD_RE = re.compile(r"^#+\s.*contents", re.I)
CONTENTS_ITEM_RE = re.compile(r"^\s*(?:[-*]|\d+\.)\s+\[[^\]]*\]\(")


def parse_frontmatter(lines):
    """Return (fields, line_of_each_field, body_start_index, state); state is ok/none/unclosed."""
    if not lines or lines[0].strip() != "---":
        return {}, {}, 0, "none"
    end = next((i for i in range(1, len(lines)) if lines[i].strip() == "---"), None)
    if end is None:
        return {}, {}, 0, "unclosed"
    fields, where, key = {}, {}, None
    for i in range(1, end):
        m = re.match(r"^([A-Za-z_-]+):\s*(.*)$", lines[i])
        if m:
            key = m.group(1)
            val = m.group(2).strip()
            if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
                val = val[1:-1]
            fields[key] = "" if val in (">", "|", ">-", "|-") else val
            where[key] = i + 1
        elif key and lines[i].strip():
            fields[key] = (fields[key] + " " + lines[i].strip()).strip()
    return fields, where, end + 1, "ok"


def read_lines(path):
    with open(path, encoding="utf-8-sig", errors="replace") as fh:
        return fh.read().splitlines()


def iter_lines(lines, start=0, skip_fenced=False):
    """Yield (1-based lineno, text), optionally skipping fenced code blocks."""
    fenced = False
    for i in range(start, len(lines)):
        text = lines[i]
        if text.lstrip().startswith(("```", "~~~")):
            fenced = not fenced
            continue
        if skip_fenced and fenced:
            continue
        yield i + 1, text


def clean_target(raw):
    """Decode a link target and drop its fragment; None for URLs, absolute paths and bare anchors."""
    target = unquote(raw).split("#")[0].strip()
    if not target or target.startswith("/") or re.match(r"^[A-Za-z][A-Za-z0-9+.-]*:", target):
        return None
    return target


def extract_links(path, lines, start=0):
    """(lineno, target, resolved, kind) for relative links ("link") and backticked .md paths ("tick")."""
    found = []
    base = os.path.dirname(path)
    for lineno, text in iter_lines(lines, start, skip_fenced=True):
        raws = []
        m = REFDEF_RE.match(text)
        if m:
            raws.append(m.group(1) or m.group(2))
        raws += [a or b for a, b in LINK_RE.findall(CODE_SPAN_RE.sub("", text))]
        for raw in raws:
            target = clean_target(raw)
            if target:
                found.append((lineno, target, os.path.normpath(os.path.join(base, target)), "link"))
        for target in BACKTICK_MD_RE.findall(text):
            if not target.startswith("/"):
                found.append((lineno, target, os.path.normpath(os.path.join(base, target)), "tick"))
    return found


class Skill:
    def __init__(self, root):
        self.root = os.path.abspath(root)
        self.skill_md = os.path.join(self.root, "SKILL.md")
        self.errors = {}
        self.escapes = {}
        self.real_root = os.path.realpath(self.root)
        self.cache = {}
        self.lines = self.read(self.skill_md)
        self.fm, self.fm_line, self.body_start, self.fm_state = parse_frontmatter(self.lines)
        self.name = self.fm.get("name") or os.path.basename(self.root)
        self.md_files = self._md_files()
        self.refs = [p for p in self.md_files if p != self.skill_md and not self._excluded(p)]
        self.links = {}
        for p in self.md_files:
            self.links[p] = [self._tick_fallback(p, l) for l in extract_links(
                p, self.read(p), self.body_start if p == self.skill_md else 0)]
        self.linked = self._linked_md()
        manifest = os.path.join(self.root, "evals", "evals.json")
        if self.escapes_root(manifest):
            self.escapes[manifest] = ("file", os.readlink(manifest))

    def rel(self, path):
        return os.path.relpath(path, self.root)

    def note_error(self, path, exc):
        self.errors.setdefault(path, "could not read %s: %s" % (self.rel(path), getattr(exc, "strerror", None) or exc))

    def escapes_root(self, path):
        real = os.path.realpath(path)
        return os.path.islink(path) and os.path.exists(path) and not (real == self.real_root or real.startswith(self.real_root + os.sep))

    def read(self, path):
        if path not in self.cache:
            if path != self.skill_md and self.escapes_root(path):
                self.escapes[path] = ("file", os.readlink(path))
                self.cache[path] = []
                return []
            try:
                self.cache[path] = read_lines(path)
            except OSError as exc:
                self.note_error(path, exc)
                self.cache[path] = []
        return self.cache[path]

    def inside(self, path):
        return path == self.root or path.startswith(self.root + os.sep)

    def _tick_fallback(self, path, link):
        """A backticked path may be written relative to the skill root rather than its own file."""
        lineno, target, resolved, kind = link
        if kind == "tick" and not os.path.exists(resolved):
            alt = os.path.normpath(os.path.join(self.root, target))
            if self.inside(alt) and os.path.exists(alt):
                return lineno, target, alt, kind
        return link

    def _excluded(self, path):
        parts = self.rel(path).split(os.sep)
        return len(parts) > 1 and parts[0] in EXCLUDED_DIRS

    def _md_files(self):
        out = []
        for d, _, files in self.walk(self.root):
            out += [os.path.join(d, f) for f in files if f.endswith(".md")]
        return sorted(out)

    def walk(self, top):
        """os.walk that follows symlinked dirs once, skips hidden/vendored dirs and reports unreadable ones."""
        visited = {os.path.realpath(top)}

        def onerror(exc):
            self.note_error(exc.filename, exc)

        for d, dirs, files in os.walk(top, followlinks=True, onerror=onerror):
            keep = []
            for name in sorted(dirs):
                full = os.path.join(d, name)
                real = os.path.realpath(full)
                if self.escapes_root(full):
                    self.escapes[full] = ("directory", os.readlink(full))
                    continue
                if name.startswith(".") or name in VENDORED_DIRS or real in visited:
                    continue
                visited.add(real)
                keep.append(name)
            dirs[:] = keep
            yield d, dirs, files

    def _linked_md(self):
        """SKILL.md plus every .md reachable from it by links or backticked paths, transitively."""
        seen, todo = {self.skill_md}, [self.skill_md]
        while todo:
            for _, _, target, _ in self.links.get(todo.pop(), []):
                if target.endswith(".md") and self.inside(target) and os.path.exists(target) and target not in seen:
                    seen.add(target)
                    todo.append(target)
        return sorted(seen)


def finding(rule, status, file, line, message):
    return {"rule": rule, "status": status, "file": file, "line": line, "message": message}


def rule_1_length(skill):
    n = len(skill.lines) - skill.body_start
    if n > BODY_LIMIT:
        return [finding(1, "fail", "SKILL.md", None, "SKILL.md body is %d lines, over the %d-line limit" % (n, BODY_LIMIT))]
    return []


def rule_1_missing_links(skill):
    out = []
    for path in skill.md_files:
        if path != skill.skill_md and skill._excluded(path):
            continue
        for lineno, target, resolved, kind in skill.links[path]:
            if kind == "link" and skill.inside(resolved) and not os.path.exists(resolved):
                out.append(finding(1, "fail", skill.rel(path), lineno, "linked file '%s' does not exist" % target))
    return out


def exempt_root_doc(skill, path):
    return os.path.dirname(path) == skill.root and os.path.basename(path).lower() in EXEMPT_ROOT_DOCS


def rule_1_reachability(skill):
    out = []
    from_skill = {t for _, _, t, _ in skill.links[skill.skill_md]}
    for ref in skill.refs:
        if ref in from_skill or exempt_root_doc(skill, ref):
            continue
        parents = [skill.rel(p) for p in skill.refs if p != ref and any(t == ref for _, _, t, _ in skill.links[p])]
        if parents:
            msg = "%s is linked only from %s, never from SKILL.md (chain: SKILL.md -> ... -> %s -> %s)" % (
                skill.rel(ref), ", ".join(parents), parents[0], skill.rel(ref))
        else:
            msg = "%s is unreachable: no file links to it" % skill.rel(ref)
        out.append(finding(1, "fail", skill.rel(ref), None, msg))
    return out


def has_contents(lines):
    head = lines[:20]
    if any(CONTENTS_HEAD_RE.match(text) for text in head):
        return True
    for i, text in enumerate(head):
        if re.match(r"^#\s", text):
            nxt = next((t for t in head[i + 1:] if t.strip()), "")
            return bool(CONTENTS_ITEM_RE.match(nxt))
    return False


def rule_2(skill):
    out = []
    for path in skill.refs:
        if exempt_root_doc(skill, path):
            continue
        lines = skill.read(path)
        if len(lines) > REF_LIMIT and not has_contents(lines):
            out.append(finding(2, "fail", skill.rel(path), None,
                               "%s is %d lines (over %d) with no contents list in its first 20 lines" % (skill.rel(path), len(lines), REF_LIMIT)))
    return out


def person_match(desc):
    text = QUOTED_RE.sub(" ", desc)
    for m in FIRST_I_RE.finditer(text):
        if not ROMAN_PREFIX_RE.search(text[:m.start()]):
            return m
    return PERSON_RE.search(text)


def rule_5(skill):
    if skill.fm_state == "unclosed":
        return [finding(5, "fail", "SKILL.md", 1, "frontmatter has no closing ---")]
    desc = skill.fm.get("description", "").strip()
    line = skill.fm_line.get("description")
    if not desc:
        return [finding(5, "fail", "SKILL.md", line, "frontmatter description is missing or empty")]
    m = person_match(desc)
    if m:
        return [finding(5, "fail", "SKILL.md", line, "description uses first/second person: '%s'" % m.group(0))]
    return []


def rule_9(skill):
    out = []
    for path in skill.linked + [p for p in skill.refs if p not in skill.linked]:
        rel = skill.rel(path)
        lines = skill.read(path)
        start = skill.body_start if path == skill.skill_md else 0
        for lineno, text in iter_lines(lines, start, skip_fenced=True):
            m = WIN_PATH_RE.search(CODE_SPAN_RE.sub("", text))
            if m:
                out.append(finding(9, "fail", rel, lineno, "backslash path '%s' found; use forward slashes" % m.group(0)))
        for lineno, text in enumerate(lines[start:], start + 1):
            m = ABS_PATH_RE.search(text)
            if m:
                out.append(finding(9, "fail", rel, lineno, "machine-specific absolute path '%s' found" % m.group(0)))
    return out


def rule_9_outside(skill):
    out = []
    for path, (kind, target) in sorted(skill.escapes.items()):
        out.append(finding(9, "fail", skill.rel(path), None,
                           "symlinked %s points outside the skill folder: %s -> %s" % (kind, skill.rel(path), target)))
    for path in skill.md_files:
        if path != skill.skill_md and skill._excluded(path):
            continue
        for lineno, target, resolved, _ in skill.links[path]:
            if not skill.inside(resolved):
                out.append(finding(9, "fail", skill.rel(path), lineno, "references a file outside the skill folder: %s" % target))
    return out


def scan_candidates(skill, rule, regex, label):
    out = []
    for path in skill.linked:
        start = skill.body_start if path == skill.skill_md else 0
        for lineno, text in iter_lines(skill.read(path), start, skip_fenced=True):
            if regex.search(text):
                out.append(finding(rule, "candidate", skill.rel(path), lineno, "%s: %s" % (label, text.strip()[:160])))
    return out


def rule_10(skill):
    return scan_candidates(skill, 10, IMPERATIVE_RE, "hook candidate")


def count_evals(skill, evals_dir):
    """Return (count, problem_message_or_None); count is None when unreadable."""
    manifest = os.path.join(evals_dir, "evals.json")
    if os.path.lexists(manifest):
        if skill.escapes_root(manifest):
            return None, None
        try:
            with open(manifest, encoding="utf-8-sig") as fh:
                data = json.load(fh)
        except OSError as exc:
            skill.note_error(manifest, exc)
            return None, None
        except ValueError as exc:
            return 0, "evals/evals.json is not valid JSON: %s" % exc
        if isinstance(data, dict) and isinstance(data.get("evals"), list):
            data = data["evals"]
        if not isinstance(data, list):
            found = ("object with keys [%s]" % ", ".join(sorted(data))) if isinstance(data, dict) else type(data).__name__
            return 0, 'evals/evals.json must be a list or {"evals": [...]}; found %s' % found
        return len(data), None
    n = 0
    for d, _, files in skill.walk(evals_dir):
        n += len([f for f in files if not f.startswith(".") and os.path.exists(os.path.join(d, f))])
    if evals_dir in skill.errors or any(e.startswith(evals_dir + os.sep) for e in skill.errors):
        return None, None
    return n, None


def rule_11(skill):
    evals_dir = os.path.join(skill.root, "evals")
    exists = os.path.isdir(evals_dir)
    n, problem = count_evals(skill, evals_dir) if exists else (0, None)
    if problem:
        return [finding(11, "fail", "evals/evals.json", None, problem)]
    if n is not None and n < MIN_EVALS:
        return [finding(11, "fail", "evals", None, "evals/ has %d entries (need at least %d)%s" % (
            n, MIN_EVALS, "" if exists else "; directory is missing"))]
    return []


def rule_13(skill):
    return scan_candidates(skill, 13, ECHO_RE, "reasoning-echo phrasing")


RULES = [rule_1_length, rule_1_missing_links, rule_1_reachability, rule_2, rule_5, rule_9, rule_9_outside,
         rule_10, rule_11, rule_13]


def find_skills(path):
    if os.path.lexists(os.path.join(path, "SKILL.md")):
        return [path]
    subs = sorted(os.path.join(path, d) for d in os.listdir(path))
    return [d for d in subs if os.path.isdir(d) and os.path.lexists(os.path.join(d, "SKILL.md"))]


def main(argv):
    if len(argv) != 2 or not os.path.isdir(argv[1]):
        sys.stderr.write("usage: lint_skill.py <skill-folder | folder-of-skills> (path must be an existing directory)\n")
        return 2
    try:
        paths = find_skills(argv[1])
    except OSError as exc:
        sys.stderr.write("cannot list %s: %s\n" % (argv[1], exc.strerror))
        return 2
    if not paths:
        sys.stderr.write("no skills found under %s (expected SKILL.md or subfolders containing one)\n" % argv[1])
        return 2
    report = []
    for p in paths:
        skill = Skill(p)
        findings = [] if skill.skill_md in skill.errors else [f for rule in RULES for f in rule(skill)]
        findings += [finding(0, "error", skill.rel(path), None, msg) for path, msg in skill.errors.items()]
        report.append({"skill": skill.name, "path": p, "findings": findings})
    json.dump({"skills": report}, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

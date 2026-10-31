#!/usr/bin/env python3
"""Send GitHub repository events to a Discord webhook.

Standard library only (Python 3.8+). Designed to run inside GitHub Actions.
"""

from __future__ import annotations

import collections
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone

VERSION = "2.0"
BOT_NAME = "Universal-Script Monitor"
OWN_WORKFLOW_NAME = "Discord Repository Monitor"

# Discord embed limits are: title 256, description 4096, field name 256,
# field value 1024, 25 fields and 6000 characters in total. We stay below them.
EMBED_TOTAL_LIMIT = 5800
MAX_FIELDS = 10
FIELD_NAME_LIMIT = 250
FIELD_VALUE_LIMIT = 1000
DESCRIPTION_LIMIT = 1800
DIFF_PREVIEW_LIMIT = 450
MAX_DIFF_FILES = 3
MAX_COMMITS_LISTED = 5

BLURPLE, GREEN, RED = 0x5865F2, 0x57F287, 0xED4245
YELLOW, PURPLE, GREY = 0xFEE75C, 0x9B59B6, 0x95A5A6
BLUE, GOLD, STAR = 0x3498DB, 0xF1C40F, 0xFFFF00

WEBHOOK_RE = re.compile(
    r"^https://(?:(?:ptb|canary)\.)?discord(?:app)?\.com/api/(?:v\d+/)?webhooks/\d+/[\w-]+/?(?:\?\S*)?$"
)

EVENT_ALIASES = {"pull_request_target": "pull_request"}

EVENT_TITLES = {
    "push": "🚀 Repository Push",
    "create": "🆕 Branch or Tag Created",
    "delete": "🗑️ Branch or Tag Deleted",
    "pull_request": "🔀 Pull Request Activity",
    "issues": "📌 Issue Activity",
    "issue_comment": "💬 Issue Comment Activity",
    "release": "🏷️ Release Activity",
    "fork": "🍴 Repository Forked",
    "watch": "⭐ Repository Starred",
    "discussion": "🗣️ Discussion Activity",
    "discussion_comment": "💬 Discussion Comment",
    "workflow_run": "⚙️ GitHub Actions Workflow",
    "workflow_dispatch": "🧪 Manual Workflow Trigger",
    "member": "👤 Collaborator Activity",
    "public": "🌍 Repository Made Public",
    "milestone": "🎯 Milestone Activity",
    "label": "🏷️ Label Activity",
    "deployment": "🚀 Deployment Created",
    "deployment_status": "📡 Deployment Status",
    "status": "📊 Commit Status Updated",
    "check_run": "✅ Check Run Completed",
    "check_suite": "🧪 Check Suite Completed",
    "repository_dispatch": "📨 Repository Dispatch",
}

EVENT_COLORS = {
    "push": BLURPLE, "create": GREEN, "delete": RED, "pull_request": BLURPLE,
    "issues": BLUE, "issue_comment": BLUE, "release": GOLD, "fork": PURPLE,
    "watch": STAR, "workflow_run": BLUE, "deployment": GREEN,
    "deployment_status": BLUE,
}

# --------------------------------------------------------------------------
# Redaction (best effort - never a substitute for keeping secrets out of git)
# --------------------------------------------------------------------------

_SECRET_RULES = [
    # PEM private keys: remove the whole block, even if the END line was cut off.
    (re.compile(r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY(?: BLOCK)?-----.*?"
                r"(?:-----END [A-Z0-9 ]*PRIVATE KEY(?: BLOCK)?-----|\Z)", re.S),
     "[REDACTED PRIVATE KEY]"),
    (re.compile(r"https?://(?:ptb\.|canary\.)?discord(?:app)?\.com/api/(?:v\d+/)?webhooks/\d+/[\w-]+"),
     "[REDACTED DISCORD WEBHOOK]"),
    (re.compile(r"(?<=://)[^/\s:@]+:[^/\s@]+@"), "[REDACTED]@"),
    (re.compile(r"(?i)\b(authorization\s*[:=]\s*[\"']?(?:basic|bearer|token)?\s*)[^\s\"',;]+"),
     r"\1[REDACTED]"),
    (re.compile(r"\bBearer\s+[A-Za-z0-9\-._~+/]{20,}=*"), "Bearer [REDACTED]"),
    (re.compile(r"\bgh[pousr]_[A-Za-z0-9_]{20,}"), "[REDACTED]"),
    (re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}"), "[REDACTED]"),
    (re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"), "[REDACTED]"),
    (re.compile(r"\bxox[abeoprs]-[A-Za-z0-9-]{10,}"), "[REDACTED]"),
    (re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b"), "[REDACTED]"),
    (re.compile(r"\b[sr]k_(?:live|test)_[0-9A-Za-z]{16,}"), "[REDACTED]"),
    (re.compile(r"\bnpm_[A-Za-z0-9]{36}\b"), "[REDACTED]"),
    (re.compile(r"\bsk-[A-Za-z0-9_-]{20,}"), "[REDACTED]"),
    (re.compile(r"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"), "[REDACTED JWT]"),
    # key: value, key=value, "key": "value" (values may be quoted).
    (re.compile(
        r"(?i)\b([\w.-]*(?:password|passwd|passphrase|secret|token|api[_-]?key|"
        r"access[_-]?key|private[_-]?key)[\w.-]*)([\"']?\s*[:=]\s*)"
        r"(?!\$|%|<|\{\{|\"?\[REDACTED|(?:None|null|true|false)\b|os\.|process\.env|getenv)"
        r"(\"[^\"\n]*\"|'[^'\n]*'|[^\s,;]+)"),
     r"\1\2[REDACTED]"),
]

_SENSITIVE_PATH_RULES = [re.compile(p, re.I) for p in (
    r"(^|/)\.env(\.|$)",
    r"(^|/)\.(npmrc|pypirc|netrc|htpasswd|git-credentials|envrc)$",
    r"(^|/)id_(rsa|dsa|ecdsa|ed25519)(\.pub)?$",
    r"\.(pem|key|p12|pfx|jks|keystore|kdbx|ovpn|tfvars|tfstate|gpg)$",
    r"secret|credential|private[_-]?key|passw(or)?d",
    r"(^|/)(kubeconfig|service[-_]?account[^/]*\.json)$",
)]

_NOISY_PATH = re.compile(
    r"(^|/)(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|poetry\.lock|Pipfile\.lock|"
    r"Cargo\.lock|composer\.lock|Gemfile\.lock|go\.sum|uv\.lock|bun\.lockb)$|\.min\.(js|css)$|\.map$",
    re.I,
)


def redact(value):
    value = str(value)
    for pattern, replacement in _SECRET_RULES:
        value = pattern.sub(replacement, value)
    return value


def is_sensitive_path(path):
    return any(rule.search(path) for rule in _SENSITIVE_PATH_RULES)


# --------------------------------------------------------------------------
# Small helpers
# --------------------------------------------------------------------------

def dig(data, *keys, default=None):
    """Safe nested lookup that tolerates missing keys and JSON nulls."""
    for key in keys:
        if not isinstance(data, dict):
            return default
        data = data.get(key)
        if data is None:
            return default
    return data


def clip(value, limit, suffix="…"):
    text = "" if value is None else str(value)
    if len(text) <= limit:
        return text
    return text[: max(limit - len(suffix), 0)] + suffix


def safe_text(value, limit):
    """Redact first, then clip, so a secret is never cut in half and leaked."""
    return clip(redact(value), limit)


def escape_md(value):
    return re.sub(r"([\\`*_~|>\[\]()])", r"\\\1", str(value))


def fence(text, lang=""):
    text = str(text).replace("```", "`\u200b``")
    return f"```{lang}\n{text}\n```"


def first_line(value):
    return (str(value or "").strip().splitlines() or [""])[0]


def short_sha(sha):
    return (sha or "")[:7]


def is_zero_sha(sha):
    return not sha or set(sha) == {"0"}


def safe_url(url, fallback=None):
    if isinstance(url, str) and len(url) <= 2000 and re.match(r"^https?://\S+$", url):
        return url
    return fallback


def describe_ref(ref):
    ref = ref or ""
    if ref.startswith("refs/heads/"):
        return ref[len("refs/heads/"):], "branch"
    if ref.startswith("refs/tags/"):
        return ref[len("refs/tags/"):], "tag"
    return ref, "ref"


def conclusion_color(value):
    value = (value or "").lower()
    if value in ("success", "completed", "active"):
        return GREEN
    if value in ("failure", "error", "timed_out", "startup_failure", "action_required"):
        return RED
    if value in ("cancelled", "skipped", "neutral", "stale", "inactive"):
        return GREY
    if value in ("pending", "queued", "in_progress", "waiting", "requested"):
        return YELLOW
    return None


def names(items, key="name"):
    return ", ".join(str(i.get(key)) for i in (items or []) if isinstance(i, dict) and i.get(key))


# --------------------------------------------------------------------------
# Git helpers (push events)
# --------------------------------------------------------------------------

class GitError(RuntimeError):
    pass


Change = collections.namedtuple("Change", "kind path old_path")


def git(*args):
    # core.quotepath=false keeps non-ASCII file names readable and usable as pathspecs.
    proc = subprocess.run(
        ["git", "-c", "core.quotepath=false", *args],
        capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=60,
    )
    if proc.returncode != 0:
        raise GitError(proc.stderr.strip() or f"git {args[0]} failed")
    return proc.stdout


def commit_exists(sha):
    try:
        git("cat-file", "-e", f"{sha}^{{commit}}")
        return True
    except GitError:
        return False


def resolve_range(event):
    """Return (mode, base, after).

    mode "range": compare base..after; "root": show the tip commit on its own;
    "none": the ref points at an already-known commit (nothing new).
    """
    before = event.get("before") or ""
    after = event.get("after") or os.getenv("GITHUB_SHA", "")
    after = git("rev-parse", f"{after}^{{commit}}").strip()

    if not is_zero_sha(before):
        if not commit_exists(before):
            raise GitError("previous commit is no longer available (force push?)")
        return "range", before, after

    # New branch or tag: compare against the default branch, not just the tip commit.
    default_branch = dig(event, "repository", "default_branch")
    if default_branch and event.get("ref") != f"refs/heads/{default_branch}":
        try:
            base = git("merge-base", f"refs/remotes/origin/{default_branch}", after).strip()
        except GitError:
            base = ""
        if base:
            return ("none", base, after) if base == after else ("range", base, after)
    return "root", "", after


def parse_name_status(output):
    tokens = output.split("\0")
    changes, i = [], 0
    while i < len(tokens):
        status = tokens[i]
        i += 1
        if not status:
            continue
        kind = status[0]
        if kind in "RC":
            if i + 1 >= len(tokens):
                break
            changes.append(Change(kind, tokens[i + 1], tokens[i]))
            i += 2
        else:
            if i >= len(tokens):
                break
            changes.append(Change(kind, tokens[i], ""))
            i += 1
    return changes


def list_changes(mode, base, after):
    if mode == "none":
        return []
    if mode == "range":
        out = git("diff", "--no-ext-diff", "--no-textconv", "--find-renames",
                  "--name-status", "-z", base, after)
    else:
        out = git("diff-tree", "--root", "--no-commit-id", "--no-ext-diff",
                  "--name-status", "-z", "-r", "-M", after)
    return parse_name_status(out)


def count_commits(mode, base, after, fallback):
    if mode == "range":
        try:
            return int(git("rev-list", "--count", f"{base}..{after}").strip())
        except (GitError, ValueError):
            pass
    return fallback


def tidy_diff(raw):
    lines = raw.splitlines()
    for index, line in enumerate(lines):
        if line.startswith("@@"):
            return "\n".join(lines[index:])
    if any(l.startswith(("Binary files", "GIT binary patch")) for l in lines):
        return "[Binary file changed]"
    return "[No text changes to display]"


def file_diff(mode, base, after, change):
    paths = [p for p in (change.path, change.old_path) if p]
    if any(is_sensitive_path(p) for p in paths):
        return "[Diff preview hidden for a potentially sensitive file.]"
    if _NOISY_PATH.search(change.path):
        return "[Diff preview skipped for a lockfile or generated file.]"
    try:
        common = ["--no-ext-diff", "--no-textconv", "--find-renames", "--unified=2"]
        if mode == "range":
            out = git("diff", *common, base, after, "--", *paths)
        else:
            out = git("show", "--format=", *common, after, "--", *paths)
    except (GitError, subprocess.TimeoutExpired, OSError):
        return "[Diff preview is unavailable. Open the comparison link to inspect the changes.]"
    return tidy_diff(out.strip())


# --------------------------------------------------------------------------
# Notification model
# --------------------------------------------------------------------------

class Notification:
    def __init__(self, event_name, event, env):
        self.event_name = event_name
        self.event = event
        self.env = env
        self.action = event.get("action")
        self.repository = env.get("GITHUB_REPOSITORY", "unknown/unknown")
        self.server = env.get("GITHUB_SERVER_URL", "https://github.com").rstrip("/")
        self.repo_url = f"{self.server}/{self.repository}"
        run_id = env.get("GITHUB_RUN_ID", "")
        self.run_url = f"{self.repo_url}/actions/runs/{run_id}" if run_id else self.repo_url
        self.lines = []
        self.fields = []
        self.link = None
        self.color = None

    def line(self, label, value):
        if value not in (None, ""):
            self.lines.append(f"**{label}:** {value}")

    def add(self, name, value, inline=False, limit=FIELD_VALUE_LIMIT):
        if len(self.fields) >= MAX_FIELDS or value is None:
            return
        value = str(value)
        if not value.strip():
            return
        self.fields.append({
            "name": safe_text(name, FIELD_NAME_LIMIT),
            "value": safe_text(value, limit),
            "inline": bool(inline),
        })


HANDLERS = {}


def handles(*event_names):
    def decorator(func):
        for name in event_names:
            HANDLERS[name] = func
        return func
    return decorator


# --------------------------------------------------------------------------
# Event handlers
# --------------------------------------------------------------------------

@handles("push")
def handle_push(n, event):
    ref_name, ref_kind = describe_ref(event.get("ref"))
    after = event.get("after") or n.env.get("GITHUB_SHA", "")
    flags = [f for f, on in (("new " + ref_kind, event.get("created")),
                             ("force push", event.get("forced")),
                             ("deleted", event.get("deleted"))) if on]
    n.line("Ref", f"`{ref_name}` ({ref_kind})" + (f" — {', '.join(flags)}" if flags else ""))

    if event.get("deleted"):
        n.color, n.link = RED, n.repo_url
        return

    n.line("Commit", f"`{after[:12]}`")
    head = event.get("head_commit") or {}
    commits = event.get("commits") or []
    n.link = event.get("compare") if not event.get("created") else head.get("url")
    n.link = n.link or head.get("url") or f"{n.repo_url}/commit/{after}"

    analysis_note = None
    try:
        mode, base, resolved_after = resolve_range(event)
        changes = list_changes(mode, base, resolved_after)
        total = count_commits(mode, base, resolved_after, len(commits))
    except (GitError, subprocess.TimeoutExpired, OSError) as error:
        mode, base, resolved_after, changes = None, "", after, []
        total = len(commits)
        analysis_note = (f"File analysis is unavailable: {clip(first_line(error), 150)}. "
                         "Open the comparison link instead.")

    # Commit list
    lines = []
    for commit in commits[:MAX_COMMITS_LISTED]:
        author = dig(commit, "author", "username") or dig(commit, "author", "name") or "unknown"
        subject = escape_md(clip(first_line(commit.get("message")), 70)) or "(no message)"
        url = safe_url(commit.get("url"))
        sha = f"`{short_sha(commit.get('id'))}`"
        lines.append(f"{f'[{sha}]({url})' if url else sha} {subject} — {escape_md(author)}")
    if total > len(lines) and lines:
        lines.append(f"…and {total - len(lines)} more commit(s)")
    if not lines and head.get("message"):
        lines.append(escape_md(clip(first_line(head["message"]), 120)))
    if commits:
        n.add(f"Commits ({total})", "\n".join(lines))
    else:
        n.add("Latest Commit", "\n".join(lines) or "No commit information")

    if mode is None:
        n.add("File Analysis", analysis_note)
        return

    counts = collections.Counter(c.kind for c in changes)
    if mode == "none":
        n.add("File Change Summary", "No new file changes (the ref points to an existing commit).")
        return
    n.add("File Change Summary",
          f"🆕 Added: {counts['A'] + counts['C']}\n"
          f"✏️ Modified: {counts['M'] + counts['T']}\n"
          f"🗑️ Deleted: {counts['D']}\n"
          f"🔀 Renamed: {counts['R']}")

    # Prefer files whose diff is useful; lockfiles and generated files go last.
    ordered = sorted(changes, key=lambda c: bool(_NOISY_PATH.search(c.path)))
    labels = {"A": "🆕 ADDED", "M": "✏️ MODIFIED", "D": "🗑️ DELETED",
              "R": "🔀 RENAMED", "C": "🆕 COPIED", "T": "✏️ TYPE CHANGED"}
    for change in ordered[:MAX_DIFF_FILES]:
        label = labels.get(change.kind, f"📄 {change.kind}")
        shown = f"{change.old_path} → {change.path}" if change.old_path else change.path
        preview = safe_text(file_diff(mode, base, resolved_after, change), DIFF_PREVIEW_LIMIT)
        n.add(f"{label} | {clip(shown, 200)}", fence(preview, "diff"))
    if len(changes) > MAX_DIFF_FILES:
        n.add("Additional Files",
              f"{len(changes) - MAX_DIFF_FILES} additional file(s) changed. "
              "Open the comparison link to view the complete change list.")


@handles("create", "delete")
def handle_create_delete(n, event):
    ref, kind = event.get("ref"), event.get("ref_type")
    n.add("Reference Type", kind, inline=True)
    n.add("Reference", ref, inline=True)
    n.color = GREEN if n.event_name == "create" else RED
    if n.event_name == "create" and ref:
        quoted = urllib.parse.quote(ref, safe="/")
        n.link = f"{n.repo_url}/releases/tag/{quoted}" if kind == "tag" else f"{n.repo_url}/tree/{quoted}"


@handles("pull_request")
def handle_pull_request(n, event):
    pr = event.get("pull_request") or {}
    if pr.get("merged"):
        state = "merged"
    elif pr.get("draft") and pr.get("state") == "open":
        state = "draft"
    else:
        state = pr.get("state")
    n.add("Title", escape_md(pr.get("title") or ""))
    n.add("Number", f"#{pr.get('number')}" if pr.get("number") else None, inline=True)
    n.add("State", state, inline=True)
    n.add("Author", dig(pr, "user", "login"), inline=True)

    head_ref, base_ref = dig(pr, "head", "ref"), dig(pr, "base", "ref")
    if head_ref and base_ref:
        head_repo = dig(pr, "head", "repo", "full_name")
        source = f"{head_repo}:{head_ref}" if head_repo and head_repo != n.repository else head_ref
        n.add("Branches", f"`{source}` → `{base_ref}`")
    if pr.get("changed_files") is not None:
        n.add("Changes", f"{pr.get('changed_files')} file(s), "
                         f"+{pr.get('additions', 0)} / −{pr.get('deletions', 0)}", inline=True)
    n.add("Labels", names(pr.get("labels")), inline=True)
    if n.action in ("opened", "reopened", "ready_for_review"):
        n.add("Description", pr.get("body"), limit=500)

    n.link = pr.get("html_url")
    n.color = {"merged": PURPLE, "draft": GREY}.get(state) or (
        GREEN if state == "open" else RED if state == "closed" else BLURPLE)


@handles("issues")
def handle_issues(n, event):
    issue = event.get("issue") or {}
    n.add("Title", escape_md(issue.get("title") or ""))
    n.add("Number", f"#{issue.get('number')}" if issue.get("number") else None, inline=True)
    n.add("State", issue.get("state"), inline=True)
    n.add("Author", dig(issue, "user", "login"), inline=True)
    n.add("Label", dig(event, "label", "name"), inline=True)
    n.add("Assignee", dig(event, "assignee", "login"), inline=True)
    n.add("Labels", names(issue.get("labels")), inline=True)
    if n.action == "opened":
        n.add("Description", issue.get("body"), limit=500)
    n.link = issue.get("html_url")
    n.color = {"opened": GREEN, "reopened": GREEN, "closed": RED, "deleted": RED}.get(n.action, BLUE)


@handles("issue_comment")
def handle_issue_comment(n, event):
    issue, comment = event.get("issue") or {}, event.get("comment") or {}
    kind = "Pull Request" if issue.get("pull_request") else "Issue"
    n.add(kind, f"#{issue.get('number')} {issue.get('title') or ''}".strip())
    n.add("Comment", comment.get("body"), limit=900)
    n.add("Comment Author", dig(comment, "user", "login"))
    n.link = comment.get("html_url") or issue.get("html_url")


@handles("discussion")
def handle_discussion(n, event):
    item = event.get("discussion") or {}
    n.add("Title", escape_md(item.get("title") or ""))
    n.add("Category", dig(item, "category", "name"), inline=True)
    n.add("Author", dig(item, "user", "login"), inline=True)
    n.add("Answered", "Yes" if item.get("answer_html_url") else None, inline=True)
    if n.action == "created":
        n.add("Description", item.get("body"), limit=500)
    n.link = item.get("html_url")


@handles("discussion_comment")
def handle_discussion_comment(n, event):
    discussion, comment = event.get("discussion") or {}, event.get("comment") or {}
    n.add("Discussion", discussion.get("title"))
    n.add("Comment", comment.get("body"), limit=900)
    n.add("Comment Author", dig(comment, "user", "login"))
    n.link = comment.get("html_url") or discussion.get("html_url")


@handles("release")
def handle_release(n, event):
    release = event.get("release") or {}
    n.add("Release Name", release.get("name") or release.get("tag_name"))
    n.add("Tag", release.get("tag_name"), inline=True)
    n.add("Type", "Pre-release" if release.get("prerelease") else
          "Draft" if release.get("draft") else "Stable", inline=True)
    n.add("Author", dig(release, "author", "login"), inline=True)
    n.add("Release Notes", release.get("body"), limit=900)
    n.link = release.get("html_url")
    n.color = RED if n.action == "deleted" else GOLD


@handles("fork")
def handle_fork(n, event):
    forkee = event.get("forkee") or {}
    n.add("Fork", forkee.get("full_name"))
    n.add("Total Forks", dig(event, "repository", "forks_count"), inline=True)
    n.link = forkee.get("html_url")


@handles("watch")
def handle_watch(n, event):
    n.add("Total Stars", dig(event, "repository", "stargazers_count"), inline=True)


@handles("workflow_run")
def handle_workflow_run(n, event):
    run = event.get("workflow_run") or {}
    n.add("Workflow", run.get("name"))
    n.add("Conclusion", run.get("conclusion"), inline=True)
    n.add("Run Number", run.get("run_number"), inline=True)
    n.add("Branch", run.get("head_branch"), inline=True)
    n.add("Triggered By", run.get("event"), inline=True)
    n.add("Commit", short_sha(run.get("head_sha")), inline=True)
    n.link = run.get("html_url")
    n.color = conclusion_color(run.get("conclusion"))


@handles("workflow_dispatch")
def handle_workflow_dispatch(n, event):
    n.add("Branch", describe_ref(event.get("ref"))[0], inline=True)
    inputs = event.get("inputs") or {}
    if inputs:
        n.add("Inputs", fence("\n".join(f"{k}: {v}" for k, v in inputs.items())))
    n.link = n.run_url


@handles("repository_dispatch")
def handle_repository_dispatch(n, event):
    n.add("Event Type", event.get("action"), inline=True)
    n.add("Branch", event.get("branch"), inline=True)
    payload = event.get("client_payload")
    if payload:
        n.add("Client Payload", fence(clip(json.dumps(payload, indent=2, ensure_ascii=False), 600), "json"))
    n.link = n.run_url


@handles("member")
def handle_member(n, event):
    member = event.get("member") or {}
    n.add("Collaborator", member.get("login"), inline=True)
    n.add("New Permission", dig(event, "changes", "permission", "to"), inline=True)
    n.link = member.get("html_url")
    n.color = RED if n.action == "deleted" else GREEN if n.action == "added" else None


@handles("public")
def handle_public(n, event):
    n.add("Visibility", dig(event, "repository", "visibility") or "public", inline=True)
    n.color = GOLD


@handles("milestone")
def handle_milestone(n, event):
    item = event.get("milestone") or {}
    n.add("Title", item.get("title"))
    n.add("State", item.get("state"), inline=True)
    n.add("Due", (item.get("due_on") or "")[:10] or None, inline=True)
    n.add("Progress", f"{item.get('closed_issues', 0)} closed / {item.get('open_issues', 0)} open", inline=True)
    n.add("Description", item.get("description"), limit=400)
    n.link = item.get("html_url")


@handles("label")
def handle_label(n, event):
    label = event.get("label") or {}
    n.add("Label", label.get("name"), inline=True)
    n.add("Color", f"#{label.get('color')}" if label.get("color") else None, inline=True)
    n.add("Description", label.get("description"), limit=300)
    n.link = f"{n.repo_url}/labels"


@handles("deployment")
def handle_deployment(n, event):
    item = event.get("deployment") or {}
    n.add("Environment", item.get("environment"), inline=True)
    n.add("Ref", item.get("ref"), inline=True)
    n.add("Commit", short_sha(item.get("sha")), inline=True)
    n.add("Creator", dig(item, "creator", "login"), inline=True)
    n.add("Description", item.get("description"), limit=300)
    n.link = f"{n.repo_url}/deployments"


@handles("deployment_status")
def handle_deployment_status(n, event):
    status = event.get("deployment_status") or {}
    n.add("Deployment State", status.get("state"), inline=True)
    n.add("Environment", status.get("environment") or dig(event, "deployment", "environment"), inline=True)
    n.add("Description", status.get("description"), limit=300)
    n.link = status.get("target_url") or status.get("log_url") or f"{n.repo_url}/deployments"
    n.color = conclusion_color(status.get("state"))


@handles("status")
def handle_status(n, event):
    n.add("State", event.get("state"), inline=True)
    n.add("Context", event.get("context"), inline=True)
    n.add("Commit", short_sha(event.get("sha")), inline=True)
    n.add("Branches", names(event.get("branches")))
    n.add("Description", event.get("description"), limit=300)
    n.link = event.get("target_url") or f"{n.repo_url}/commit/{event.get('sha', '')}"
    n.color = conclusion_color(event.get("state"))


@handles("check_run")
def handle_check_run(n, event):
    run = event.get("check_run") or {}
    n.add("Check", run.get("name"))
    n.add("Conclusion", run.get("conclusion"), inline=True)
    n.add("App", dig(run, "app", "name"), inline=True)
    n.add("Commit", short_sha(run.get("head_sha")), inline=True)
    n.add("Summary", dig(run, "output", "title"), limit=300)
    n.link = run.get("html_url")
    n.color = conclusion_color(run.get("conclusion"))


@handles("check_suite")
def handle_check_suite(n, event):
    suite = event.get("check_suite") or {}
    n.add("Conclusion", suite.get("conclusion"), inline=True)
    n.add("App", dig(suite, "app", "name"), inline=True)
    n.add("Branch", suite.get("head_branch"), inline=True)
    n.add("Commit", short_sha(suite.get("head_sha")), inline=True)
    n.link = f"{n.repo_url}/commit/{suite.get('head_sha')}/checks" if suite.get("head_sha") else None
    n.color = conclusion_color(suite.get("conclusion"))


def handle_generic(n, event):
    for key in ("ref", "ref_type", "title", "number", "state", "conclusion"):
        if event.get(key) is not None:
            n.add(key.replace("_", " ").title(), event[key])


# --------------------------------------------------------------------------
# Payload assembly
# --------------------------------------------------------------------------

def skip_reason(event_name, event, env):
    """Return a reason string when this event should not produce a notification."""
    if event_name == "workflow_run":
        own = env.get("GITHUB_WORKFLOW") or OWN_WORKFLOW_NAME
        if dig(event, "workflow_run", "name") in (own, OWN_WORKFLOW_NAME):
            return "Skipping this monitor's own workflow run."
    if event_name == "pull_request" and event.get("action") == "synchronize":
        head = dig(event, "pull_request", "head", "repo", "full_name")
        base = dig(event, "pull_request", "base", "repo", "full_name")
        if head and head == base:
            return "Skipping PR synchronize: the push event already reports these commits."
    return None


def build_payload(event_name, event, env):
    event_name = EVENT_ALIASES.get(event_name, event_name)
    n = Notification(event_name, event, env)
    sender = dig(event, "sender", "login") or env.get("GITHUB_ACTOR", "Unknown")

    n.line("Repository", f"`{n.repository}`")
    n.line("Action", f"`{n.action}`" if n.action else None)
    HANDLERS.get(event_name, handle_generic)(n, event)

    embed = {
        "title": clip(EVENT_TITLES.get(event_name, "📡 Repository Activity"), 256),
        "url": safe_url(n.link, n.repo_url),
        "description": safe_text("\n".join(n.lines), DESCRIPTION_LIMIT),
        "color": n.color if n.color is not None else EVENT_COLORS.get(event_name, BLURPLE),
        "fields": n.fields,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "footer": {"text": f"{BOT_NAME} • {event_name}"},
        "author": {"name": clip(sender, 256), "url": f"{n.server}/{urllib.parse.quote(sender)}"},
    }
    avatar = safe_url(dig(event, "sender", "avatar_url"))
    if avatar:
        embed["author"]["icon_url"] = avatar

    # Stay under Discord's 6000-character total embed limit.
    def size():
        return (len(embed["title"]) + len(embed["description"]) + len(embed["footer"]["text"])
                + len(embed["author"]["name"])
                + sum(len(f["name"]) + len(f["value"]) for f in embed["fields"]))
    while embed["fields"] and size() > EMBED_TOTAL_LIMIT:
        embed["fields"].pop()

    return {"username": BOT_NAME, "embeds": [embed], "allowed_mentions": {"parse": []}}


def fallback_payload(event_name, env, reason):
    repository = env.get("GITHUB_REPOSITORY", "unknown/unknown")
    return {
        "username": BOT_NAME,
        "embeds": [{
            "title": clip(EVENT_TITLES.get(event_name, "📡 Repository Activity"), 256),
            "description": clip(
                f"**Repository:** `{repository}`\n**Actor:** `{env.get('GITHUB_ACTOR', 'Unknown')}`\n"
                f"Details could not be generated ({clip(reason, 200)}).", DESCRIPTION_LIMIT),
            "color": GREY,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "footer": {"text": f"{BOT_NAME} • {event_name}"},
        }],
        "allowed_mentions": {"parse": []},
    }


# --------------------------------------------------------------------------
# Delivery
# --------------------------------------------------------------------------

class NotifyError(RuntimeError):
    pass


def post_webhook(url, payload, env=None, attempts=4):
    env = env or os.environ
    # Discord's CDN rejects urllib's default User-Agent with HTTP 403 (error 1010).
    headers = {
        "Content-Type": "application/json",
        "User-Agent": f"DiscordBot ({env.get('GITHUB_SERVER_URL', 'https://github.com')}/"
                      f"{env.get('GITHUB_REPOSITORY', 'repo')}, {VERSION})",
    }
    data = json.dumps(payload).encode("utf-8")
    for attempt in range(1, attempts + 1):
        request = urllib.request.Request(url, data=data, headers=headers, method="POST")
        try:
            with urllib.request.urlopen(request, timeout=20) as response:
                return response.status
        except urllib.error.HTTPError as error:
            body = error.read().decode("utf-8", "replace")
            retryable = error.code == 429 or error.code >= 500
            if retryable and attempt < attempts:
                delay = 2 ** attempt
                if error.code == 429:
                    try:
                        delay = float(json.loads(body).get("retry_after", delay))
                    except (ValueError, AttributeError, TypeError):
                        delay = float(error.headers.get("Retry-After") or delay)
                print(f"Discord returned HTTP {error.code}; retrying in {min(delay, 30):.1f}s "
                      f"(attempt {attempt}/{attempts}).")
                time.sleep(min(delay, 30))
                continue
            raise NotifyError(f"Discord webhook returned HTTP {error.code}: {clip(body, 300)}")
        except (urllib.error.URLError, TimeoutError, OSError) as error:
            if attempt < attempts:
                time.sleep(2 ** attempt)
                continue
            raise NotifyError(f"Could not reach Discord: {error}")
    raise NotifyError("Unreachable")


def main():
    env = os.environ
    webhook = env.get("DISCORD_WEBHOOK", "").strip()
    if not webhook:
        print("::warning::DISCORD_WEBHOOK is not configured; notification skipped.")
        return 0
    if not WEBHOOK_RE.match(webhook):
        print("::error::DISCORD_WEBHOOK is not a valid Discord webhook URL "
              "(expected https://discord.com/api/webhooks/<id>/<token>).")
        return 1

    event_name = env.get("GITHUB_EVENT_NAME", "unknown")
    try:
        with open(env["GITHUB_EVENT_PATH"], encoding="utf-8") as handle:
            event = json.load(handle)
    except (KeyError, OSError, ValueError) as error:
        print(f"::error::Could not read the GitHub event payload: {error}")
        return 1

    reason = skip_reason(EVENT_ALIASES.get(event_name, event_name), event, env)
    if reason:
        print(reason)
        return 0

    try:
        payload = build_payload(event_name, event, env)
    except Exception as error:  # a malformed payload must not lose the notification
        print(f"::warning::Could not build the detailed notification: {error!r}")
        payload = fallback_payload(event_name, env, repr(error))

    try:
        status = post_webhook(webhook, payload, env)
    except NotifyError as error:
        print(f"::error::{error}")
        return 1
    print(f"Discord notification sent successfully (HTTP {status}).")
    return 0


if __name__ == "__main__":
    sys.exit(main())

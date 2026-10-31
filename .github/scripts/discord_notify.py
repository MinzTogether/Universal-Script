import json
import os
import re
import subprocess
import urllib.error
import urllib.request
from datetime import datetime, timezone

WEBHOOK = os.getenv("DISCORD_WEBHOOK", "")
EVENT_NAME = os.getenv("GITHUB_EVENT_NAME", "unknown")
REPOSITORY = os.getenv("GITHUB_REPOSITORY", "unknown/unknown")
ACTOR = os.getenv("GITHUB_ACTOR", "Unknown")
SHA = os.getenv("GITHUB_SHA", "")
SERVER_URL = os.getenv("GITHUB_SERVER_URL", "https://github.com")
RUN_ID = os.getenv("GITHUB_RUN_ID", "")

if not WEBHOOK:
    print("DISCORD_WEBHOOK is not configured; notification skipped.")
    raise SystemExit(0)

with open(os.environ["GITHUB_EVENT_PATH"], encoding="utf-8") as file:
    event = json.load(file)

# Avoid an endless workflow_run notification loop.
if EVENT_NAME == "workflow_run":
    workflow_name = event.get("workflow_run", {}).get("name", "")
    if workflow_name == "Discord Repository Monitor":
        print("Skipping this monitor's own workflow run.")
        raise SystemExit(0)

def clip(value, limit):
    value = str(value or "")
    return value if len(value) <= limit else value[:limit - 18] + "\n...[truncated]"

def redact(value):
    patterns = [
        r"(?i)(password|secret|token|api[_-]?key)\s*[:=]\s*\S+",
        r"gh[pousr]_[A-Za-z0-9_]{20,}",
        r"github_pat_[A-Za-z0-9_]{20,}",
        r"-----BEGIN [A-Z ]*PRIVATE KEY-----",
    ]
    for pattern in patterns:
        value = re.sub(pattern, "[REDACTED]", value)
    return value

def run_git(*args):
    return subprocess.run(
        ["git", *args],
        capture_output=True,
        text=True,
        check=True,
    ).stdout

def add_field(fields, name, value, inline=False):
    if len(fields) >= 8:
        return
    fields.append({
        "name": clip(name, 256),
        "value": clip(value or "Not provided", 900),
        "inline": inline,
    })

def get_push_changes():
    before = event.get("before", "")
    after = event.get("after", SHA)
    if not after:
        return []

    if before and set(before) != {"0"}:
        output = run_git("diff", "--find-renames", "--name-status", before, after)
    else:
        output = run_git(
            "diff-tree", "--root", "--no-commit-id",
            "--name-status", "-r", "-M", after
        )

    result = []
    for line in output.splitlines():
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        status = parts[0]
        if status.startswith("R") and len(parts) >= 3:
            result.append((status, parts[2], parts[1]))
        else:
            result.append((status, parts[1], ""))
    return result

def get_diff(before, after, path, old_path=""):
    if re.search(r"(?i)(^|/)(\.env|.*secret.*|.*credential.*|.*private.*key.*)$", path):
        return "[Diff preview hidden for a potentially sensitive file.]"
    try:
        if before and set(before) != {"0"}:
            paths = [path]
            if old_path:
                paths.append(old_path)
            output = run_git(
                "diff", "--no-ext-diff", "--unified=2",
                before, after, "--", *paths
            )
        else:
            output = run_git(
                "show", "--format=", "--no-ext-diff",
                "--unified=2", after, "--", path
            )
        return clip(redact(output.strip()) or "No text diff is available.", 450)
    except Exception:
        return "Diff preview is unavailable. Open the commit to inspect the changes."

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

COLORS = {
    "push": 5793266, "create": 5763719, "delete": 15548997,
    "pull_request": 5793266, "issues": 3447003,
    "issue_comment": 3447003, "release": 15844367,
    "fork": 10181046, "watch": 16776960,
    "workflow_run": 3447003, "deployment": 5763719,
    "deployment_status": 3447003,
}

action = event.get("action", "updated")
sender = event.get("sender", {}).get("login", ACTOR)
title = EVENT_TITLES.get(EVENT_NAME, "📡 Repository Activity")
fields = []
description = [
    f"**Repository:** `{REPOSITORY}`",
    f"**Actor:** `{sender}`",
    f"**Event:** `{EVENT_NAME}`",
    f"**Action:** `{action}`",
]
link = f"{SERVER_URL}/{REPOSITORY}"

if EVENT_NAME == "push":
    before = event.get("before", "")
    after = event.get("after", SHA)
    branch = event.get("ref", "")
    head = event.get("head_commit") or {}
    commits = event.get("commits", [])

    description.extend([
        f"**Ref:** `{branch}`",
        f"**Commit:** `{after[:12]}`",
    ])
    add_field(fields, "Commit Message", head.get("message", "No commit message"))
    add_field(fields, "Commit Count", str(len(commits)), True)

    try:
        changes = get_push_changes()
        counts = {"A": 0, "M": 0, "D": 0, "R": 0}
        for status, _, _ in changes:
            key = status[0]
            if key in counts:
                counts[key] += 1

        add_field(
            fields,
            "File Change Summary",
            f"🆕 Added: {counts['A']}\n"
            f"✏️ Modified: {counts['M']}\n"
            f"🗑️ Deleted: {counts['D']}\n"
            f"🔀 Renamed: {counts['R']}",
        )

        for status, path, old_path in changes[:3]:
            kind = status[0]
            label = {
                "A": "🆕 ADDED",
                "M": "✏️ MODIFIED",
                "D": "🗑️ DELETED",
                "R": "🔀 RENAMED",
            }.get(kind, f"📄 {status}")
            display_path = f"{old_path} → {path}" if old_path else path
            preview = get_diff(before, after, path, old_path)
            add_field(fields, f"{label} | {display_path}", f"```diff\n{preview}\n```")

        if len(changes) > 3:
            add_field(
                fields,
                "Additional Files",
                f"{len(changes) - 3} additional file(s) changed. "
                "Open the comparison link to view the complete change list.",
            )
    except Exception as error:
        add_field(fields, "File Analysis", f"File analysis failed: {error}")

    link = (
        f"{SERVER_URL}/{REPOSITORY}/compare/{before}...{after}"
        if before and set(before) != {"0"}
        else f"{SERVER_URL}/{REPOSITORY}/commit/{after}"
    )

elif EVENT_NAME in ("create", "delete"):
    add_field(fields, "Reference Type", event.get("ref_type"))
    add_field(fields, "Reference", event.get("ref"))

elif EVENT_NAME in ("pull_request", "issues"):
    item = event.get(EVENT_NAME, {})
    add_field(fields, "Title", item.get("title"))
    add_field(fields, "Number", item.get("number"), True)
    add_field(fields, "Author", item.get("user", {}).get("login"))
    link = item.get("html_url", link)

elif EVENT_NAME in ("issue_comment", "discussion_comment"):
    item = event.get("comment", {})
    add_field(fields, "Comment", item.get("body", ""))
    add_field(fields, "Comment Author", item.get("user", {}).get("login"))
    link = item.get("html_url", link)

elif EVENT_NAME == "release":
    item = event.get("release", {})
    add_field(fields, "Release Name", item.get("name"))
    add_field(fields, "Tag", item.get("tag_name"))
    add_field(fields, "Release Notes", item.get("body", ""))
    link = item.get("html_url", link)

elif EVENT_NAME == "discussion":
    item = event.get("discussion", {})
    add_field(fields, "Title", item.get("title"))
    add_field(fields, "Category", item.get("category", {}).get("name"))
    link = item.get("html_url", link)

elif EVENT_NAME == "workflow_run":
    item = event.get("workflow_run", {})
    add_field(fields, "Workflow", item.get("name"))
    add_field(fields, "Conclusion", item.get("conclusion"))
    add_field(fields, "Run Number", item.get("run_number"), True)
    link = item.get("html_url", link)

elif EVENT_NAME == "deployment_status":
    item = event.get("deployment_status", {})
    add_field(fields, "Deployment State", item.get("state"))
    add_field(fields, "Environment", item.get("environment"))

else:
    for key in ("ref", "ref_type", "title", "number", "state", "conclusion"):
        if event.get(key) is not None:
            add_field(fields, key.replace("_", " ").title(), event[key])

run_url = (
    f"{SERVER_URL}/{REPOSITORY}/actions/runs/{RUN_ID}"
    if RUN_ID else link
)

embed = {
    "title": clip(title, 256),
    "url": link,
    "description": clip("\n".join(description), 1800),
    "color": COLORS.get(EVENT_NAME, 5793266),
    "fields": fields,
    "timestamp": datetime.now(timezone.utc).isoformat(),
    "footer": {"text": f"Universal-Script Monitor • {EVENT_NAME}"},
}

payload = {
    "username": "Universal-Script Monitor",
    "embeds": [embed],
    "allowed_mentions": {"parse": []},
}

request = urllib.request.Request(
    WEBHOOK,
    data=json.dumps(payload).encode("utf-8"),
    headers={"Content-Type": "application/json"},
    method="POST",
)

try:
    with urllib.request.urlopen(request, timeout=20) as response:
        print(f"Discord notification sent successfully (HTTP {response.status}).")
except urllib.error.HTTPError as error:
    print(f"Discord webhook returned HTTP {error.code}: {error.read().decode('utf-8', 'replace')}")
    raise

# Universal-Script Discord Repository Monitor

Sends GitHub repository activity to a Discord channel as rich embeds.
All notification titles, labels, descriptions, and status text are written in English (US).

## Installation

1. Upload the `.github` directory to the root of `MinzTogether/Universal-Script`
   (the workflow must exist on the **default branch**).
2. In GitHub, open Settings → Secrets and variables → Actions.
3. Create a repository secret named `DISCORD_WEBHOOK`.
4. Set its value to your Discord webhook URL (`https://discord.com/api/webhooks/<id>/<token>`).
5. Open Actions → Discord Repository Monitor → Run workflow to test.

No third-party actions other than `actions/checkout` are used, and the script depends only on
the Python standard library.

## Monitored events

Pushes to all branches and tags, branch/tag creation and deletion, pull requests
(including pull requests from forks), issues and comments, releases, forks, stars,
discussions and comments, workflow runs, collaborator changes, milestones, labels,
deployments, commit statuses, check runs, check suites, and repository dispatch events.

Every event type has its own layout (for example pull requests show state, branches, and
change size; workflow runs, checks, and statuses are colored by result).

## Push details

- Commit list (up to five) with links, authors, and the real commit count.
- File-change summary and up to three file previews. Lockfiles and minified files are
  deprioritized, and the complete comparison is linked from the embed.
- New branches and tags are compared against the default branch, so the summary covers the
  whole branch instead of only the tip commit.
- Force pushes whose previous commit no longer exists are reported without a file preview.
- Diff previews of potentially sensitive files (`.env*`, keys, certificates, `*secret*`,
  `*credential*`, and similar) are hidden.
- Common credential patterns are redacted from **all** notification text (diffs, commit
  messages, comments, release notes): GitHub/AWS/Slack/Stripe/Google tokens, JWTs, private key
  blocks, Discord webhook URLs, `Authorization` headers, URL credentials, and
  `password`/`secret`/`token`/`api_key` assignments. Redaction is best-effort and is not a
  substitute for keeping secrets out of commits.

## Delivery

- Retries automatically on Discord rate limits (HTTP 429) and temporary server errors.
- Sends a Discord-friendly `User-Agent` (Discord's CDN can reject Python's default one).
- Falls back to a minimal notification if an unusual payload cannot be formatted.
- Mentions (`@everyone`, `@here`, roles, users) are always disabled.

## Security

- Never commit the Discord webhook URL; store it only as the `DISCORD_WEBHOOK` secret.
- Pull requests use `pull_request_target` so fork pull requests can trigger notifications.
  This is safe here because the workflow never checks out or runs pull request code. If you
  add steps to this workflow, do not check out `github.event.pull_request.head`.
- The workflow token is limited to `contents: read`.
- Review third-party action versions periodically.

## Behavior notes

- Events created by the workflow `GITHUB_TOKEN` (for example check runs created by Actions)
  do not trigger new workflow runs; this is a GitHub limitation.
- Creating a branch or tag usually produces two notifications: one `create` and one `push`.
  Remove `create:` from the workflow if you only want the push notification.
- `pull_request` `synchronize` events from branches in the same repository are skipped
  because the push notification already reports them. Fork pull requests are still reported.
- The monitor ignores its own `workflow_run` events to avoid loops.

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| Run skipped with a warning | `DISCORD_WEBHOOK` secret is missing or empty. |
| `not a valid Discord webhook URL` | The secret is not an `https://discord.com/api/webhooks/...` URL. |
| `HTTP 404 ... Unknown Webhook` | The webhook was deleted; create a new one. |
| `HTTP 403 ... 1010` | The request was blocked by Discord's CDN; check for a proxy or custom runner network. |

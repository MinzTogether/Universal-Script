# Universal-Script Discord Repository Monitor

All notification titles, labels, descriptions, and status text are written in English (US).

## Installation

1. Upload the `.github` directory to the root of `MinzTogether/Universal-Script`.
2. In GitHub, open Settings → Secrets and variables → Actions.
3. Create a repository secret named `DISCORD_WEBHOOK`.
4. Set its value to your Discord webhook URL.
5. Open Actions → Discord Repository Monitor → Run workflow to test.

## Monitored events

Pushes to all branches and tags, branch/tag creation and deletion, pull requests,
issues and comments, releases, forks, stars, discussions and comments, workflow
runs, collaborator changes, milestones, labels, deployments, commit statuses,
check runs, check suites, and repository dispatch events.

## Push details

The notification includes a file-change summary and up to three file previews.
The complete comparison is linked from the embed. Potentially sensitive file
diffs are suppressed, and common credential patterns are redacted. Redaction
is best-effort and is not a substitute for keeping secrets out of commits.

## Security

- Never commit the Discord webhook URL.
- Store it only as the `DISCORD_WEBHOOK` GitHub Actions repository secret.
- Fork pull request workflows do not receive repository secrets.
- Review workflow permissions and third-party action versions periodically.

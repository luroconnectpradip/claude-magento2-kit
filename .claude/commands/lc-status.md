---
description: Check or wait on a running luroConnect build or deploy
argument-hint: <taskid>
---

Report the status of luroConnect task `$1`.

Run `.claude/skills/luroconnect-m2/scripts/lc-status.sh $1`. It is read-only.

Then tell me in plain language:
- whether it is still running, succeeded, or failed
- if it succeeded and it was a build, the git commit id
- if it failed, what went wrong — match the log against
  `references/build-failures.md` from the `luroconnect-m2` skill and propose a fix in git

If I did not give a taskid, ask me for one, or offer to look at the most recent build
if you can tell which it was from our conversation.

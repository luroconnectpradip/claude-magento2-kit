---
description: Build this repo on luroConnect and wait for the result
argument-hint: [staging|prod]
---

Start a luroConnect build of this repository and wait for it to finish.

Target environment: `$1` — if empty, use `staging`.

Use the `luroconnect-m2` skill, Procedure A. In short:

1. Run `.claude/skills/luroconnect-m2/scripts/lc-build.sh --target <target>` and
   stream the progress back to me.
2. On success, report the **git commit id**. That is the release identifier.
   Do **not** deploy; deploying is a separate, explicit step.
3. On failure, diagnose it using `references/build-failures.md` and propose a fix that
   is a change in git. Never propose running something on the server.

---
description: Deploy a built release to a luroConnect environment
argument-hint: <commit-id> [staging|prod]
---

Deploy release `$1` to environment `$2` (default `staging`).

Use the `luroconnect-m2` skill, Procedure A, and `references/deploy-options.md`.

Before running anything:

1. Tell me whether this release needs `--upgrade`. Check whether the diff since the
   currently deployed release touches `db_schema.xml`, `Setup/Patch/`, or bumps
   `setup_version` in any `module.xml`. **`--upgrade` puts the site in full maintenance
   for the whole of `setup:upgrade` and is not undone by a rollback**, so do not add it
   unless the release genuinely needs it.
2. **Ask me to confirm** before running the deploy. Never deploy in the same turn you
   were asked to build.
3. Never target production unless I named production. `--prod-confirm` is mine to ask
   for; do not pass it on your own initiative.

Then run `.claude/skills/luroconnect-m2/scripts/lc-deploy.sh` with the flags we agreed.

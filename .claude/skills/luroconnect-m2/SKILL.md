---
name: luroconnect-m2
description: Use when working in a Magento 2 repo hosted by luroConnect - starting a build or deploy from the terminal instead of the dashboard, checking or waiting on a running build, reading a build log, diagnosing a failed build, rolling back, or questions about app/etc/config.php, config.php.build and what belongs in git for the luroConnect pipeline.
---

# luroConnect Magento 2 build & deploy

**What this gives the developer: build and deploy without leaving the terminal.**
Everything the luroConnect CI/CD dashboard does — start a build, watch it, read the
log, deploy a release — is available here over the REST API. The dashboard still
works exactly as before; this is an addition, not a replacement.

Four slash commands front this skill: `/lc-build`, `/lc-status`, `/lc-deploy` and
`/lc-check`. They route into the procedures below. Plain-English requests reach the
same place, so treat both identically.

The always-on rules are in the repo's `CLAUDE.md`. This skill has the procedures.
Read the `CLAUDE.md` CONFIGURATION block first — you need `LC_ENV_NAME` for anything
involving the REST API.

## Route by what the developer is asking

| They ask | Do this |
|---|---|
| "build this", "deploy to staging", "is my build done?" | **Procedure A** — the main one |
| "my build failed", pastes a build log | **Procedure B** |
| "enable a module", "change theme/scope", "turn on minify", conflict error | **Procedure C** → `references/config-php.md` |
| "is my repo set up right?", onboarding a new project | **Procedure D** |
| "what has to be in git?", "can I gitignore X?" | `references/repo-contract.md` |
| "what do the deploy checkboxes do?", "how do I roll back?" | `references/deploy-options.md` |

## The model in one paragraph

luroConnect clones the repo at a branch, merges `config.php.build` into
`app/etc/config.php` if there is one, runs `composer install`, `setup:di:compile` and
`setup:static-content:deploy` **in Docker with no database**, and packages the result
as a release tarball named after the abbreviated git commit id. Deploy untars that
release into its own folder on the server, overlays the environment-specific
`app/etc/env.php` and the shared `media`/`var` directories, then swaps the docroot
symlink and reloads PHP-FPM across the app servers. Nothing about a release folder is
edited in place.

---

## Procedure A — building and deploying

This is what the kit is for.

### Building

You may run `scripts/lc-build.sh` without asking. A build never touches the live site —
it produces a release tarball on the server and nothing else. Report the resulting
**git commit id**; that is the release identifier for deploy.

### Deploying

- **Always ask before deploying.** Never run `scripts/lc-deploy.sh` in the same turn
  as the build unless the developer's request explicitly asked you to deploy too.
- **Never deploy to production** unless the developer named production in that turn.
  `lc-deploy.sh` enforces this with a separate `--prod-confirm` flag; do not pass it
  on your own initiative.
- Before proposing a deploy with `--upgrade`, tell the developer it puts the site in
  **full maintenance for the duration of `setup:upgrade`**. See
  `references/deploy-options.md`.

### Both

The endpoints, payloads and status semantics are in `references/rest-api.md`.
`LC_TOKEN` must be in the environment; if it is not set, say so and stop — do not ask
the developer to paste a token into the chat or into a file.

A build takes several minutes. `lc-build.sh` waits and streams progress; don't start a
second build of the same environment while one is running.

## Procedure B — a build failed

1. Get the log. If `LC_TOKEN` is set and you have the taskid, run
   `.claude/skills/luroconnect-m2/scripts/lc-status.sh <taskid>`. Otherwise ask the
   developer to paste the build output from the dashboard.
2. Match the failure against `references/build-failures.md`. That table maps the exact
   error strings the pipeline emits to their cause.
3. **Propose a fix that is a change in git.** Never propose running a command on the
   server to work around a build failure — the build will fail identically next time.
4. If the log shows a failure not in the table, say so plainly rather than guessing,
   and point the developer at luroConnect support with the taskid.

## Procedure C — changing modules, themes, scopes or build settings

Read `references/config-php.md` before answering. The one-line version:

- **modules** → `app/etc/config.php`, changed by running `bin/magento module:enable X`
  **locally** and committing the diff. This file is always in git.
- **themes, scopes, system config that affects static content** → `config.php.build`.
- The same key must not appear in both with different values.

**`config.php.build` is usually maintained by luroConnect on the server, not in the
repo.** In that case it is correctly absent from git — never treat that as a defect
and never create one. A server-side copy also silently overwrites a committed one, so
committing a change to it can appear to do nothing.

- **Not in git** (the common case): the developer asks luroConnect to make the change.
- **In git**: they own it; use the recipes in `references/config-php.md`.

You cannot tell which applies by looking at the repo. If it matters for the question
being asked, say so and have the developer confirm with luroConnect — don't guess.

Both files are Magento's own `config.php` format (a PHP file returning an array), so
edit them with `bin/magento` locally rather than by hand where possible.

## Procedure D — verify the repo is set up correctly

Run these and report a pass/fail line for each. They are all read-only.

```bash
# 1. config.php must be tracked
git ls-files --error-unmatch app/etc/config.php

# 2. config.php.build - INFORMATIONAL ONLY. Empty output is a normal, correct result:
#    luroConnect commonly maintains this file on the server instead of in git.
#    Report which arrangement appears to be in use. Never report absence as a failure.
git ls-files config.php.build app/etc/config.php.build

# 3. env.php and auth.json must NOT be tracked
git ls-files app/etc/env.php auth.json id_rsa

# 4. generated artifacts must be ignored
git check-ignore -v vendor generated pub/static var pub/media

# 5. anything generated that slipped into the index
git ls-files vendor generated pub/static var pub/media | head

# 6. lock file in sync (needs composer locally)
composer validate --no-check-all --no-check-publish --check-lock
```

Expected: 1 prints the path; 2 may print nothing (fine — see above); 3 and 5 print
nothing; 4 prints an ignore rule for each; 6 says the lock file is up to date.
`references/repo-contract.md` explains each.

Do **not** propose creating a `config.php.build` as a remedy. If the developer needs
build settings changed and there is no committed file, the answer is to ask
luroConnect, not to create one — see `references/config-php.md`.

## Things to never do in this repo

- Never edit or propose editing files under a release folder on the server.
- Never propose `app:config:dump` as a fix on the server — it rewrites `config.php`
  on a machine whose changes are about to be discarded.
- Never add generated directories to git to "make the build faster".
- Never put credentials in `config.php.build`, whoever owns it. Secrets belong in
  `env.php`, which luroConnect manages.


# luroConnect build & deploy for Claude Code (Magento 2)

Build and deploy your luroConnect-hosted Magento 2 site from
[Claude Code](https://claude.com/claude-code), without leaving your terminal.

Ask Claude to build, watch the log, diagnose a failure, and deploy — in the same
session where you are writing the code. Your luroConnect dashboard keeps working
exactly as it does now; this is an addition, not a replacement.

## What you get

Four commands inside your Magento repository:

| Command | |
|---|---|
| `/lc-build [staging\|prod]` | build this repo and wait for the result |
| `/lc-status <taskid>` | check or wait on a running build or deploy |
| `/lc-deploy <commit-id> [staging\|prod]` | deploy a build |
| `/lc-check` | verify your repo is set up correctly for the pipeline |

Plain English works too — *"build staging and tell me the commit id"*.

Claude also picks up how the luroConnect pipeline actually works, so it stops
suggesting things that quietly break it — running `bin/magento module:enable` on the
server, adding `app/etc/config.php` to `.gitignore`, `chmod -R 777 var`, or treating
`setup:upgrade` as a routine step.

## Requirements

- Claude Code
- A Magento 2 site hosted by luroConnect, checked out locally
- `curl` and `jq`
- A luroConnect API token — see below

## Get an API token

**The token comes from your luroConnect dashboard, not from this repository.**

In the luroConnect dashboard you already use for builds, go to
**CI/CD → your environment → Build from Claude Code**. You will also find your
**environment name** there — a short string like `M2_4` that you need during install.

Click **Generate token**. It is shown once, so copy it straight away. Tokens are
valid for one year and carry the same permissions as your dashboard login, so treat
one like a password:

```bash
echo "export LC_TOKEN='<paste your token>'" >> ~/.zshrc   # or ~/.bashrc
source ~/.zshrc
```

Never put the token in a file inside your repository.

> The dashboard also offers a download with your environment name already filled in.
> If you have dashboard access, that route is one step shorter than installing from
> here.

## Install

From the root of your Magento 2 repository:

```bash
git clone --depth 1 https://github.com/luroconnectpradip/claude-magento2-kit /tmp/lc-kit

# the skill, slash commands and permission profile
cp -r /tmp/lc-kit/.claude .
cp .claude/settings.json.sample .claude/settings.json

# the rules Claude always sees
cat /tmp/lc-kit/CLAUDE.md.snippet >> CLAUDE.md

# the .gitignore entries the build needs -- read these before you keep them
cat /tmp/lc-kit/gitignore.sample >> .gitignore
```

If you have no `CLAUDE.md` yet, that `cat` creates one. If you do, the kit is appended
and nothing existing is disturbed.

Then **edit `CLAUDE.md`** and set your environment name:

```diff
-- `LC_ENV_NAME`: **TODO** — your environment name from the luroConnect CI/CD
+- `LC_ENV_NAME`: `M2_4` — this repo's luroConnect environment
```

Commit all of it, so your whole team gets the same setup:

```bash
git add CLAUDE.md .gitignore .claude
git commit -m "Add luroConnect build & deploy kit for Claude Code"
```

## Check it works

In Claude Code, from your repository:

```
/lc-check
```

This runs read-only checks against the luroConnect build contract and reports anything
that is off. A common one it catches: `app/etc/config.php` being gitignored, which
several public Magento `.gitignore` templates do and which breaks luroConnect builds —
the module list ends up empty.

Then try a build:

```
/lc-build staging
```

## What Claude will and will not do on its own

The boundary is build versus deploy, not read versus write:

- **Builds run without asking.** A build never touches your live site. It clones,
  builds in Docker, and leaves a release tarball on the server — no symlink change, no
  PHP-FPM reload, no maintenance window.
- **Deploys always ask first.** Claude tells you whether the release needs
  `setup:upgrade` — which puts the site in full maintenance for its duration and is
  *not* undone by a rollback — and waits for you to confirm.
- **Production deploys need a second explicit confirmation** beyond that.

If you would rather Claude never triggered anything at all, do not install the kit and
keep using the dashboard.

## What is in here

```
CLAUDE.md.snippet       always-on rules, appended to your CLAUDE.md
gitignore.sample        the .gitignore entries the pipeline requires
.claude/
  commands/             the four slash commands
  settings.json.sample
  skills/luroconnect-m2/
    SKILL.md            how to build, deploy, and triage failures
    references/         repo contract, config.php vs config.php.build,
                        REST API, build-failure table, deploy options
    scripts/            the REST wrappers the commands call
```

Nothing here phones home. The scripts talk only to `rest.luroconnect.com`, using the
token in your environment.

## Using the scripts directly

The slash commands are thin wrappers. You can run the scripts yourself:

```bash
./.claude/skills/luroconnect-m2/scripts/lc-build.sh  --name M2_4 --target staging
./.claude/skills/luroconnect-m2/scripts/lc-status.sh <taskid>
./.claude/skills/luroconnect-m2/scripts/lc-deploy.sh --name M2_4 --release <commit> --yes
```

`lc-build.sh` prints the git commit id on success — that is the release identifier for
`lc-deploy.sh`. Add `--upgrade` only when the release carries database schema or data
changes. Deploying to production also needs `--prod-confirm`.

## Updating

```bash
cd /tmp/lc-kit && git pull && cd -
cp -r /tmp/lc-kit/.claude .
```

`.claude/settings.json` is yours and is not overwritten by that copy — compare it
against `settings.json.sample` if a release mentions permission changes. For
`CLAUDE.md`, replace the existing luroConnect block rather than appending a second
copy: it starts at `# luroConnect build & deploy (Magento 2)` and runs to the end.

## Contributing and support

**This repository is published from luroConnect's internal source. It is a mirror.**
Pull requests opened here cannot be merged — the next publish would overwrite them.
That is not a judgement on the change, just how this repo is produced.

- **Something wrong or missing in the kit?** Open an issue here, or tell luroConnect
  support. Either reaches us, and the fix flows back out in the next release.
- **A build or deploy failed?** Contact luroConnect support with the **taskid** — it
  identifies the run on our side, and a pasted log fragment usually does not.

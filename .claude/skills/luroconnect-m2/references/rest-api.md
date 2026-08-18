# The luroConnect REST API

`https://rest.luroconnect.com` is luroConnect's REST (webhook) interface for build and
deploy. **It is beta.**

## Authentication

- JWT bearer token: `Authorization: Bearer $LC_TOKEN`
- Generate one yourself from the luroConnect dashboard: **CI/CD → your environment →
  Build from Claude Code → Generate token**. It is displayed once and cannot be
  retrieved afterwards.
- Lifetime: **1 year**. Revoke from the same page.
- A token has **the same permissions as a luroConnect dashboard user**. Treat it as a
  password: keep it in your shell environment (`export LC_TOKEN=...` in `~/.zshrc`),
  never in a file inside the repository, never in CI logs, never pasted into a chat.

## Environments

Build and deploy always happen with reference to an *environment*, which has a **name**
and a **type** (`staging` or `prod`). The name is the `name` column on the CI/CD
dashboard — e.g. `M2_4`. Put it in your `CLAUDE.md` as `LC_ENV_NAME`.

**All Magento 2 builds run on `staging`**, even when the target is production —
production and staging builds both happen in Docker on the staging environment. That
is why the build payload has both `environment.use` (always `staging`) and `target`
(what you are building *for*). Deploys use the environment matching the target.

## Endpoints

Only these three are documented and verified. If you need something else (listing
environments, listing releases, deploy history), ask luroConnect rather than guessing
at a URL.

### 1. Start a build

```
POST https://rest.luroconnect.com/rest/command/SysCodeBuild
Content-Type: application/json
Authorization: Bearer $LC_TOKEN
```

```json
{
  "environment": { "use": "staging", "name": "M2_4" },
  "target":   "staging",
  "patch":    false,
  "notifyme": true,
  "notify":   "me@company.com,you@company.com"
}
```

| Field | Meaning |
|---|---|
| `environment.use` | Always `staging` for M2 builds. |
| `environment.name` | Your `LC_ENV_NAME`. |
| `target` | `staging` or `prod` — what this build is for. |
| `patch` | `false` for a normal full build. Patch (incremental) builds exist but their payload is not documented here — ask luroConnect. |
| `notifyme` | Email the user who owns the token when the build finishes. |
| `notify` | Optional comma-separated list of extra recipients, notified on success. |

Response, **immediately** — the call does not wait for the build:

```json
{ "status": true, "taskid": "6863e8bb5a3aa52c8ea2a02e", "message": "Command saved" }
```

If `status` is not `true`, the build was not queued. Stop and report the message.

### 2. Deploy a release

```
POST https://rest.luroconnect.com/rest/command/SysCodeDeploy
```

```json
{
  "environment": { "use": "staging", "name": "M2_4" },
  "release":     "241727b3b",
  "upgrade":     true
}
```

| Field | Meaning |
|---|---|
| `environment.use` | The **target** environment type — `staging` or `prod`. Unlike build, this is where the deploy happens. |
| `environment.name` | Your environment name. |
| `release` | The abbreviated git commit id of a successful build. |
| `upgrade` | `true` runs `setup:upgrade`, which puts the site in **full maintenance for its whole duration**. See `deploy-options.md`. |

Same immediate `{status, taskid, message}` response shape.

### 3. Poll a command's status

```
GET https://rest.luroconnect.com/rest/commandstatus/{taskid}?brief=true
Authorization: Bearer $LC_TOKEN
```

```json
{
  "state": "Executing",
  "returnval": -1,
  "message": "$ cloning git@bitbucket.org:xxx.git\n$ building\n$ composer validate & install\n..."
}
```

| Field | Meaning |
|---|---|
| `state` | `Scheduled` → queued; `Executing` → running; `Success` → finished OK; anything else → finished, look at `returnval` and `message`. |
| `returnval` | `-1` while still running. `0` on success. Non-zero is the failing exit code. |
| `message` | The command's output. With `brief=true` this is a tail of the log, not the whole thing. |

**Done** = `state` is neither `Scheduled` nor `Executing`.
**Succeeded** = `state == "Success"` **and** `returnval == 0`.

A successful build's message ends with a block like:

```
$ packaging release
Build Details
  Git Commit : 241727b3b
  Git Branch : staging

Done. In 608.578 seconds.
```

The `Git Commit` value is the release id to pass to `SysCodeDeploy`.

## Scripts

The kit ships three scripts under `.claude/skills/luroconnect-m2/scripts/`. They all
read `LC_TOKEN` from the environment and exit non-zero on failure.

```bash
# Poll a task to completion and print state / returnval / log
./scripts/lc-status.sh <taskid>

# Start a build, wait for it, print the git commit id on success
./scripts/lc-build.sh --name M2_4 --target staging

# Deploy a release. Requires --yes. Requires --prod-confirm as well for prod.
./scripts/lc-deploy.sh --name M2_4 --target staging --release 241727b3b --yes
```

`lc-status.sh` and `lc-build.sh` are allowed to run without prompting.
`lc-deploy.sh` is not: it prompts every time, refuses without `--yes`, and refuses
production without `--prod-confirm`.

## Rate and etiquette

Builds are queued on luroConnect's side; a `Scheduled` state means yours is waiting
behind another. Poll every 5–10 seconds, not in a tight loop. Don't start a second
build of the same environment while one is still executing.

## Escalating

If a build fails with something not covered in `build-failures.md`, or the API returns
`status: false` with an unclear message, contact luroConnect with the **taskid** — it
identifies the run on our side. `info@luroConnect.com`.

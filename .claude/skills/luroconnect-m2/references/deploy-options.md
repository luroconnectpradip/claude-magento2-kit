# Deploying, and what each option costs

## What a deploy does

1. Untars the release into its own folder, named after the git commit id.
2. Symlinks `pub/media` and `var` to the shared per-environment directories, and
   overlays `app/etc/env.php` from the server's deployment directory.
3. **Swaps the docroot symlink** to the new release folder. This is the cutover.
4. Kills the hosting user's PHP processes (including running crons) so no worker keeps
   serving the old release.
5. Verifies every application server is actually serving the new release before
   continuing, retrying for up to ~2 minutes. If they never converge, the deploy
   fails and asks you to roll back rather than leaving the fleet split.
6. Reloads PHP-FPM on every application server and warms opcache.
7. Then, and only if requested, runs the optional steps below.

Steps 1–6 do not take the site down. That is the "~0-downtime" part.

## The options

| Option | What it does | Cost |
|---|---|---|
| **Upgrade** (`upgrade: true`) | Runs `bin/magento setup:upgrade --keep-generated` | **Site in full maintenance for the entire duration.** Crons are stopped and restarted around it. |
| **DB backup** (`-w`) | Takes a database backup before the deploy | Site goes into maintenance *before* the deploy and **stays in maintenance afterwards** so you can verify before opening up. |
| **Cache clear** (`-f`) | Flushes Magento cache and the full-page cache / Varnish | A cold cache — expect elevated load and slower pages until it refills. |
| **Reindex** (`-i`) | Runs a full reindex | Heavy on the database. Usually unnecessary; Magento's own indexers handle routine changes. |

The deploy log reports the maintenance window explicitly, e.g.
`During setup upgrade site was in maintenance for 1 minutes and 47 seconds.`

## When you actually need Upgrade

Use it when the release adds or changes:

- a new module with schema or data scripts (`Setup/`, `db_schema.xml`),
- a module version bump that carries a data patch,
- anything else that must write to the database before the code can run.

Do **not** tick it for template, CSS, JS, or plain PHP logic changes. It is the only
option that takes the site down, and it takes it down for as long as your slowest data
patch runs.

Because the window is proportional to the work, **batch schema changes**: three
deploys with upgrade cost three maintenance windows; one deploy carrying all three
changes costs one.

If you are unsure whether a release needs it, check whether the diff touches
`db_schema.xml`, `Setup/Patch/`, or bumps `setup_version` in any `module.xml`.

## Order of operations if you need several

A release that adds a module with schema *and* changes static content:

1. Deploy **with** Upgrade. That covers the schema.
2. Cache clear in the same deploy if the change affects cached output.

There is no need to deploy twice.

## Rollback

Rollback is a redeploy of the previous commit id. The previous release folder is still
on disk, so it is fast — the symlink swaps back.

1. Find the previous commit id in the dashboard's release dropdown, or in the deploy
   history.
2. Deploy it. **Leave Upgrade off** unless the release you are rolling back *from* ran
   schema changes.

The important caveat: **`setup:upgrade` is not reversible.** If the bad release ran
schema or data patches, rolling the code back does not roll the database back. If the
old code cannot run against the new schema, you need a database restore, not a
rollback — contact luroConnect immediately rather than redeploying repeatedly.

This is the practical reason to keep Upgrade off unless a release genuinely needs it:
a deploy without it is trivially reversible.

## Production

- Builds for production still run on the staging environment, in Docker. The build
  itself has no production impact.
- The **deploy** is what touches production. Do it deliberately, at a time you can
  watch it.
- luroConnect's recommendation is that production deploys are triggered by a person,
  not automated end-to-end. Automating build-on-merge is fine; automating
  deploy-to-production means an unattended `setup:upgrade` maintenance window.

## Doing it over REST

See `rest-api.md` for the payloads. The short form:

```bash
# build
./scripts/lc-build.sh --name "$LC_ENV_NAME" --target staging

# deploy what it produced, without an upgrade
./scripts/lc-deploy.sh --name "$LC_ENV_NAME" --target staging --release <commit> --yes

# with an upgrade (maintenance window!)
./scripts/lc-deploy.sh --name "$LC_ENV_NAME" --target staging --release <commit> --upgrade --yes

# production needs a second, explicit confirmation
./scripts/lc-deploy.sh --name "$LC_ENV_NAME" --target prod --release <commit> --yes --prod-confirm
```

### A note on the example script in luroConnect's REST documentation

luroConnect publishes a gist that builds and then deploys in one go. **It is an
illustration of how to call the API, not a recommended workflow.** luroConnect does
not expect deploys to run automatically. Two things about it in particular should not
be copied:

- It always passes `upgrade: true`, because a script has no way to tell whether a
  release needs it. Decide that per release, as above.
- It deploys immediately on a successful build, unattended. Automating
  build-on-merge is sensible; automating deploy means an unsupervised maintenance
  window on a site you are not watching.

Build automatically if you like. Deploy deliberately.

# Diagnosing a failed build

Read the build log from the bottom up. The pipeline runs `set -eo pipefail`, so the
first command that fails aborts the build — the last real error in the log is the
cause.

**Every fix here is a change committed to git.** If a fix requires running something on
the staging or production server, it is the wrong fix: the build runs on a clean clone
and will fail identically next time.

## Stage order

Knowing where the log stopped narrows it immediately:

```
git clone                    "$ cloning ..."
config.php merge             (silent unless it fails)
composer validate & install  "$ composer validate & install"
vendor patches
setup:di:compile             "$ Magento compile"
theme builds (Hyva/Scandi)   "$ Waiting for builds to complete : ..."
setup:static-content:deploy  "$ Magento static content deploy"
packaging                    "$ packaging release"
scp to the server            "Build Details" then "Done. In N seconds."
```

## Decision table

### `ERROR: Conflicts found between config.php and config.php.build:`

Followed by dotted paths. A key exists in both files with different values.
→ Fix: remove that key from `app/etc/config.php`, which should hold only `modules`.
This works whether or not you can see `config.php.build` — luroConnect often maintains
it on the server, and you do not need its contents to resolve the conflict. Almost
always caused by an `app:config:dump` where `git checkout -- app/etc/config.php` was
skipped. Full detail in `config-php.md`, Recipe 4.

### `The lock file is not up to date with the latest changes in composer.json`

`composer validate --check-lock` failed.
→ Locally: `composer update --lock` (updates only the lock's hash, not your
dependencies), commit `composer.lock`. If you changed dependencies, use
`composer require`/`composer update <package>` instead and commit both files.

### `Could not authenticate against repo.magento.com` / HTTP 401 from a private repo

The build writes `auth.json` from credentials luroConnect holds.
→ Not fixable in your repo. If the package is a **new** private repository you added
to `composer.json`, luroConnect needs its credentials — contact us with the repository
URL. Never commit an `auth.json`.

### `Your requirements could not be resolved to an installable set of packages`

A dependency conflict that also reproduces locally.
→ Resolve locally with `composer update`, commit `composer.json` + `composer.lock`.
Check the PHP version constraint: the build container's PHP version is fixed per
environment and may be older than your laptop's.

### `Allowed memory size of N bytes exhausted`

During `composer install`.
→ The build already runs composer with `memory_limit=3096M` and Magento commands with
`memory_limit=-1`. If composer itself exhausts memory, the dependency graph is the
problem — simplify it, or contact luroConnect.

### Errors during `$ Magento compile` (`setup:di:compile`)

The build compiles **with no database**. The common causes, in order:

- **Code that queries the DB at compile time** — a constructor, a `di.xml` virtual
  type argument, or a plugin that reaches for a repository/config value while
  compiling. Fix: make it lazy (inject a factory or proxy, resolve in the method that
  uses it, not the constructor).
- **A plugin or preference on a class that does not exist** — usually a module
  disabled in `config.php` while another module still declares a plugin on its class.
  Fix: enable it locally and commit `config.php`, or remove the plugin declaration.
- **Circular dependency** — the log names the chain. Break it with a `Proxy`.
- **Incompatible/absent module** — a module listed in `config.php` whose code is not
  in `composer.json`. Fix: add the dependency, or disable the module locally and
  commit `config.php`.

### Errors during `$ Magento static content deploy`

- **`Unable to resolve the source file for ...`** — a LESS/CSS `@import` or a template
  referencing an asset that is not in the repo. Fix: commit the missing asset, or
  correct the path. Case sensitivity matters: the build runs on Linux.
- **`The theme ... does not exist`** — a theme assigned in `config.php.build`'s
  `scopes` but not present in the repo. Fix: commit the theme, or correct the
  assignment.
- **Missing locale output** — a locale is deployed only if it is configured. Locales
  come from the build's static-content parameters, which luroConnect configures per
  environment. If a locale is missing from the site, ask us rather than changing code.
- **A setting you changed has no effect** — two possible causes. If it affects
  generated static content (minify, merge, bundling, theme), it must be in
  `config.php.build`, not set in the admin. And if you *did* put it in a committed
  `config.php.build`, a luroConnect-managed copy on the server may be overwriting your
  file entirely. See `config-php.md`, "Who owns it".

### Theme build failures (`npm ci` / `npm run build` / `yarn build`)

Hyva and ScandiPWA themes are built with node in parallel with the PHP build.

- `npm ci` requires `package-lock.json` (or `yarn.lock` for yarn) to be **committed
  and in sync with `package.json`**. Fix locally: `npm install`, commit the lock file.
- Out-of-memory in node: the build sets `NODE_OPTIONS=--max_old_space_size=8192` by
  default. If your theme needs more, ask luroConnect.
- `*** ERROR: package.json not found in <dir>` / `*** ERROR: Hyva tailwind dir not
  found: <dir>` — the configured theme directory does not match the repo. Either the
  theme moved (tell luroConnect the new path) or the directory was never committed.
- `*** ERROR: expected build output <path>/web/css/styles.css not found` — the node
  build ran but produced nothing. Look further up the log for the real npm error.

### `*** ERROR: Full build references files that do not exist on disk.`

The packaging step found a directory it was told to ship is missing. This is almost
always a **symptom, not the cause** — an earlier step failed quietly. Scroll up: the
real failure is in compile, static-content, or a hook script. If everything above
looks clean, contact luroConnect with the taskid.

### `*** ERROR: Patch build references files that do not exist on disk.` / `Patch build has no files to package`

A patch (incremental) build selected a file list that no build action produced. Patch
builds are configured on the luroConnect side — contact us with the taskid.

### `Build not setup - check env`

Required build configuration is missing on the luroConnect side. Nothing in your repo
causes this. Contact luroConnect with the taskid.

### `.Build.<env>_BRANCH is not same as BRANCH in env_<env>` / `Shallow repository - set .Build.clonefull to false`

Branch configuration mismatch on the luroConnect side. Contact us.

### `php should be in the path` / `composer not found` / `env file not found` / `build env generation from customer.json failed`

Build environment problems on the luroConnect side. Contact us with the taskid.

## Reproducing a build failure locally

Most compile and static-content failures reproduce with:

```bash
# emulate the build's no-database compile
mv app/etc/env.php app/etc/env.php.bak
php -d memory_limit=-1 bin/magento setup:di:compile -n
mv app/etc/env.php.bak app/etc/env.php

php -d memory_limit=-1 bin/magento setup:static-content:deploy -f -n
```

Run these in a scratch clone, not in a working install you care about — the first
command removes your generated code, and you will need `setup:di:compile` again
afterwards.

## When to escalate

Contact `info@luroConnect.com` with the **taskid** when the failure is in the
luroConnect-side configuration (branch, credentials, locales, theme paths, patch
builds), or when the log's last error is not in this table. The taskid identifies the
run on our side; a pasted log fragment often does not.

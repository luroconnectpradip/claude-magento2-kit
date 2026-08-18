# `config.php` and `config.php.build`

## Why there are two files

Magento's `app/etc/config.php` mixes two very different kinds of information:

- the **module list** — which modules exist and whether each is on or off, and
- **themes, scopes and locked system configuration** — settings that
  `setup:static-content:deploy` must know about at build time.

Developers change the first constantly. The second changes rarely and is really a
handover from development to devops. If both live in one file, every developer branch
churns the same file and every merge conflicts.

luroConnect splits them:

| File | Holds | Who edits it |
|---|---|---|
| `app/etc/config.php` | `modules` | developers, via `bin/magento module:enable/disable` locally |
| `config.php.build` | `themes`, `scopes`, `system` | see "Who owns it" below — often luroConnect |

`app/etc/config.php` is **always committed to git**. `config.php.build` may or may not
be — read the next section before assuming.

## Who owns `config.php.build`

There are two arrangements, and **you cannot tell which one you are on by looking at
the repository.** Ask luroConnect if you don't know.

### luroConnect-managed (the common case)

The file lives on the server at `/etc/lc/config.php.build` and luroConnect maintains
it. It is **not in your git repo, and that is correct** — its absence from the repo is
not a problem to fix and not something to "add for completeness".

At build time it is copied into the build workspace and merged as described below.

To change a build setting under this arrangement, **ask luroConnect**. Tell us the
setting path and value (e.g. "set `dev/css/minify_files` to `1` for staging") rather
than sending a file.

### Customer-owned

The file is committed at the repository root as `config.php.build` (or at
`app/etc/config.php.build`) and you maintain it. Use the recipes below.

### If both exist, the server's copy wins

`SysCodeBuild.sh` copies `/etc/lc/config.php.build` over the build workspace
unconditionally, after cloning:

```sh
if [ -f /etc/lc/config.php.build ]; then
  sudo cp /etc/lc/config.php.build $HOMEDIR
fi
```

So a committed `config.php.build` is **silently overwritten** whenever a
luroConnect-managed one exists. If you commit a change to `config.php.build` and the
build behaves as though nothing changed, this is almost certainly why — ask
luroConnect whether a server-side override is in place. Do not keep re-committing.

### If neither exists

No merge runs at all and your `app/etc/config.php` is used exactly as committed. That
is a valid setup for a project with no build-specific configuration.

## What the build actually does

At build time, before `composer install`, the pipeline resolves `config.php.build` —
server copy if present, otherwise the committed one — and if it found one, runs a
merge (`config_merge.php`):

1. `$build = include('app/etc/config.php.build')`
2. **`unset($build['modules'])`** — the `modules` key in `config.php.build` is thrown
   away. Putting modules there does nothing.
3. It walks both arrays and collects every key that exists in **both** with a
   **different** value. If there is at least one, it prints

   ```
   ERROR: Conflicts found between config.php and config.php.build:
     - system.default.web.secure.base_url
   ```

   and exits non-zero, **failing the build**.
4. Otherwise it deep-merges with `config.php` winning
   (`array_replace_recursive($build, $main)`) and writes the result back to
   `app/etc/config.php` for the rest of the build to use.

Two consequences worth internalising:

- The merged `config.php` exists only inside the build. Your committed `config.php` is
  not modified.
- Because `config.php` wins, a value that has drifted into *both* files but happens to
  be *equal* passes silently. It is the *different* values that fail.

---

# Recipes

**Recipes 1 and 2 apply only when `config.php.build` is customer-owned.** If
luroConnect manages it, ask us to make the change instead — editing or committing a
copy will have no effect, because the server's file overwrites it.

Recipes 3 and 4 apply either way.

## Recipe 1 — first-time creation of `config.php.build` (customer-owned only)

Only do this if you have agreed with luroConnect that you own the file. If we manage
it, creating one in git does nothing.

Run this **locally**, against a working Magento install with a database.

```bash
# 1. Dump build-relevant configuration into app/etc/config.php
bin/magento app:config:dump themes scopes system

# 2. That dump is what belongs in config.php.build
cp app/etc/config.php app/etc/config.php.build

# 3. Restore config.php so it goes back to holding only `modules`
git checkout -- app/etc/config.php

# 4. Commit
git add app/etc/config.php.build
git commit -m "Add config.php.build for luroConnect build"
```

Step 3 is the one people skip, and skipping it is the single most common cause of the
`Conflicts found` build failure: `app:config:dump` writes `themes`/`scopes`/`system`
into `config.php` as well, so both files now carry them and they drift apart on the
next change.

> The luroConnect training PDF (p8) shows this as `bin/magento config:dump themes
> scopes groups`. That is a typo — the command is `app:config:dump` and there is no
> `groups` section. Use the form above.

Valid sections for `app:config:dump` are `scopes`, `themes`, `system` and `i18n`.
Passing none dumps everything, which is usually more than you want here.

## Recipe 2 — change a build-affecting setting (customer-owned only)

Anything that changes generated static content — CSS/JS minification, merging,
bundling, theme assignment — must end up in `config.php.build`, because the build has
no database to read it from. Setting it in the admin will not survive a build.

If luroConnect manages the file, stop here and send us the setting path and value.
Otherwise, example for enabling CSS minification:

```bash
# 1. Put the current build config where bin/magento can modify it
cp app/etc/config.php.build app/etc/config.php

# 2. Make the change. --lock-config writes it into config.php rather than the DB
bin/magento config:set --lock-config dev/css/minify_files 1

# 3. Copy it back and restore config.php
cp app/etc/config.php app/etc/config.php.build
git checkout -- app/etc/config.php

# 4. Commit config.php.build only
git add app/etc/config.php.build
git commit -m "Enable CSS minification for builds"
```

Do the same for `dev/js/minify_files`, `dev/js/enable_js_bundling`,
`dev/template/minify_html`, and theme assignment under `scopes`.

## Recipe 3 — enable or disable a module

```bash
# locally
bin/magento module:enable Vendor_Module      # or module:disable
git diff app/etc/config.php                  # should show only the modules array
git add app/etc/config.php
git commit -m "Enable Vendor_Module"
```

Then build and deploy. If the module adds DB schema or data, the deploy needs the
upgrade option — see `deploy-options.md`.

Never run `module:enable` on the staging or production server. The release folder it
writes into is replaced by the next deploy.

## Recipe 4 — fix `ERROR: Conflicts found between config.php and config.php.build`

The error lists dotted paths, e.g. `system.default.web.secure.base_url`. Each is a key
that exists in **both** files with **different** values.

**The fix is almost always on your side, and it is the same either way: take the key
out of `config.php`.** `config.php` should hold `modules` and nothing else. Keys under
`themes`, `scopes` or `system` do not belong in it.

1. Look at what your `config.php` has at that path:

   ```bash
   php -r '$c = include "app/etc/config.php"; var_export($c["system"]["default"]["web"] ?? null);'
   ```

   If you have a local `config.php.build`, compare it:

   ```bash
   php -r '$c = include "app/etc/config.php.build"; var_export($c["system"]["default"]["web"] ?? null);'
   ```

   If luroConnect manages `config.php.build`, you cannot see the other side. You do
   not need to — see step 2.

2. Remove the conflicting section from `app/etc/config.php` and commit. Whatever
   `config.php.build` holds becomes the value used, which is the intended
   arrangement: build settings are owned by `config.php.build`, not by `config.php`.

3. Re-run the build.

The usual root cause is an `app:config:dump` run at some point without the
`git checkout -- app/etc/config.php` cleanup, which left `themes`/`scopes`/`system`
sections in `config.php`. Removing them entirely, so `config.php` returns to holding
only `modules`, fixes this class of failure permanently.

**When to escalate instead:** if the conflicting value in `config.php` is one you
genuinely need and removing it changes behaviour, the two sides disagree about
intent — send luroConnect the conflict paths and what you need the value to be. Don't
resolve it by changing the value in `config.php` to match, because a matching value
passes the check silently today and re-breaks the next time either side changes.

## What must never go in `config.php.build`

It is a build-configuration file, not a secret store — and when it is customer-owned
it is committed to git and readable by everyone with repo access. Never put in it,
under either ownership arrangement:

- the Magento crypt key
- database, Redis, RabbitMQ or search credentials or hosts
- API keys, payment gateway credentials, SMTP passwords

All of those belong in `app/etc/env.php`, which luroConnect manages per environment
and which is never in git. If you need a new secret in `env.php`, ask luroConnect.

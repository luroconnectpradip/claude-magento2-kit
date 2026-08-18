#!/usr/bin/env bash
#
# lc-deploy.sh -- deploy a built release to a luroConnect environment.
#
# Usage:
#   lc-deploy.sh --release <commit> --yes [options]
#
#   --release COMMIT   the git commit id printed by a successful build (required)
#   --name NAME        environment name, e.g. M2_4. Defaults to $LC_ENV_NAME.
#   --target ENV       staging (default) or prod -- where to deploy
#   --upgrade          run setup:upgrade. THIS PUTS THE SITE IN FULL MAINTENANCE
#                      FOR THE WHOLE DURATION. Only for releases with DB schema or
#                      data changes. See references/deploy-options.md.
#   --yes              required. Confirms you intend to deploy.
#   --prod-confirm     additionally required when --target prod.
#   --no-wait          queue the deploy, print the taskid, exit 0 without waiting
#
# Requires LC_TOKEN in the environment.
# Exits 0 on success, 1 on failure, 2 if still running when the poll timed out.

set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=lc-common.sh
. ./lc-common.sh

usage() { awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; exit "${1:-1}"; }

name="${LC_ENV_NAME:-}"
target="staging"
release=""
upgrade=false
yes=false
prod_confirm=false
wait=true

while [ $# -gt 0 ]; do
  case "$1" in
    --release)      release="${2:?--release needs a value}"; shift 2 ;;
    --name)         name="${2:?--name needs a value}"; shift 2 ;;
    --target)       target="${2:?--target needs a value}"; shift 2 ;;
    --upgrade)      upgrade=true; shift ;;
    --yes)          yes=true; shift ;;
    --prod-confirm) prod_confirm=true; shift ;;
    --no-wait)      wait=false; shift ;;
    -h|--help)      usage 0 ;;
    *)              lc_die "Unknown option: $1" ;;
  esac
done

[ -n "$release" ] || lc_die "--release is required: the git commit id of a successful build."
[ -n "$name" ] || lc_die "No environment name. Pass --name or set LC_ENV_NAME."
case "$target" in
  staging|prod) ;;
  *) lc_die "--target must be 'staging' or 'prod', got '$target'." ;;
esac

[ "$yes" = true ] || lc_die \
"Refusing to deploy without --yes.

A deploy changes what is live on '${target}'. Re-run with --yes once you have
confirmed the release id (${release}) is the one you want."

if [ "$target" = "prod" ] && [ "$prod_confirm" != true ]; then
  lc_die \
"Refusing to deploy to PRODUCTION without --prod-confirm.

This deploys ${release} to the live site. If that is what you want, re-run with
both --yes and --prod-confirm."
fi

lc_require_deps
lc_require_token

if [ "$upgrade" = true ]; then
  printf '\n!! --upgrade is set: the site will be in FULL MAINTENANCE for the entire\n' >&2
  printf '!! duration of setup:upgrade, and setup:upgrade is not reversible by a\n' >&2
  printf '!! rollback. See references/deploy-options.md.\n\n' >&2
fi

body=$(jq -nc \
  --arg use "$target" --arg name "$name" \
  --arg release "$release" --argjson upgrade "$upgrade" \
  '{environment: {use: $use, name: $name}, release: $release, upgrade: $upgrade}')

printf 'Deploying %s to %s (%s), upgrade=%s\n' "$release" "$name" "$target" "$upgrade" >&2
taskid=$(lc_submit "/rest/command/SysCodeDeploy" "$body")
printf 'taskid: %s\n' "$taskid" >&2

if [ "$wait" = false ]; then
  printf '%s\n' "$taskid"
  exit 0
fi

printf 'Deploying' >&2
set +e
resp=$(lc_poll "$taskid")
rc=$?
set -e

lc_report "$resp"

case "$rc" in
  0) printf '\nDeploy of %s to %s succeeded.\n' "$release" "$target" ;;
  2) printf '\nDeploy still running after %ss. Watch it with: ./lc-status.sh %s\n' "$LC_POLL_TIMEOUT" "$taskid" >&2 ;;
  *) printf '\nDeploy failed. taskid: %s\n' "$taskid" >&2
     printf 'If the site is in maintenance, contact luroConnect with this taskid.\n' >&2 ;;
esac
exit "$rc"

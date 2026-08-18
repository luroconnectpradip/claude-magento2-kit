#!/usr/bin/env bash
#
# lc-build.sh -- start a luroConnect Magento 2 build and wait for it to finish.
#
# Usage:
#   lc-build.sh --name <env name> [--target staging|prod] [options]
#
#   --name NAME        environment name from the CI/CD dashboard, e.g. M2_4.
#                      Defaults to $LC_ENV_NAME.
#   --target ENV       what this build is for: staging (default) or prod.
#                      The build itself always runs on the staging environment.
#   --notify EMAILS    comma-separated extra recipients on success
#   --no-notifyme      do not email the token owner
#   --no-wait          queue the build, print the taskid, exit 0 without waiting
#
# Requires LC_TOKEN in the environment.
#
# On success prints the built git commit id on the last line -- that is the release
# identifier to pass to lc-deploy.sh. Exits 0 on success, 1 on failure, 2 if the
# build was still running when the poll timed out.

set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=lc-common.sh
. ./lc-common.sh

usage() { awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; exit "${1:-1}"; }

name="${LC_ENV_NAME:-}"
target="staging"
notify=""
notifyme=true
wait=true

while [ $# -gt 0 ]; do
  case "$1" in
    --name)        name="${2:?--name needs a value}"; shift 2 ;;
    --target)      target="${2:?--target needs a value}"; shift 2 ;;
    --notify)      notify="${2:?--notify needs a value}"; shift 2 ;;
    --no-notifyme) notifyme=false; shift ;;
    --no-wait)     wait=false; shift ;;
    -h|--help)     usage 0 ;;
    *)             lc_die "Unknown option: $1" ;;
  esac
done

[ -n "$name" ] || lc_die "No environment name. Pass --name or set LC_ENV_NAME.
It is the 'name' column on the luroConnect CI/CD dashboard, e.g. M2_4."
case "$target" in
  staging|prod) ;;
  *) lc_die "--target must be 'staging' or 'prod', got '$target'." ;;
esac

lc_require_deps
lc_require_token

# environment.use is always "staging" for M2: prod and staging builds both run
# in docker on the staging environment. target says what the build is for.
body=$(jq -nc \
  --arg name "$name" --arg target "$target" \
  --arg notify "$notify" --argjson notifyme "$notifyme" \
  '{environment: {use: "staging", name: $name},
    target: $target,
    patch: false,
    notifyme: $notifyme}
   + (if $notify == "" then {} else {notify: $notify} end)')

printf 'Starting %s build of environment %s\n' "$target" "$name" >&2
taskid=$(lc_submit "/rest/command/SysCodeBuild" "$body")
printf 'taskid: %s\n' "$taskid" >&2

if [ "$wait" = false ]; then
  printf '%s\n' "$taskid"
  exit 0
fi

printf 'Building' >&2
set +e
resp=$(lc_poll "$taskid")
rc=$?
set -e

lc_report "$resp"

if [ "$rc" -ne 0 ]; then
  [ "$rc" -eq 2 ] \
    && printf '\nBuild still running after %ss. Watch it with: ./lc-status.sh %s\n' "$LC_POLL_TIMEOUT" "$taskid" >&2 \
    || printf '\nBuild failed. See references/build-failures.md. taskid: %s\n' "$taskid" >&2
  exit "$rc"
fi

commit=$(lc_commit_id "$resp")
if [ -z "$commit" ]; then
  printf '\nBuild succeeded but no "Git Commit :" line was found in the log.\n' >&2
  printf 'Get the release id from the dashboard. taskid: %s\n' "$taskid" >&2
  exit 1
fi

printf '\nBuild succeeded. Release id (git commit):\n'
printf '%s\n' "$commit"

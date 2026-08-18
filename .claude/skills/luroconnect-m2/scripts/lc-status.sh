#!/usr/bin/env bash
#
# lc-status.sh -- read the status and log of a luroConnect build or deploy task.
#
# READ ONLY. This script never POSTs and cannot start or change anything.
#
# Usage:
#   lc-status.sh <taskid>            wait for the task to finish, then print the log
#   lc-status.sh --once <taskid>     print the current status and exit immediately
#
# Requires LC_TOKEN in the environment. Exits 0 if the task succeeded, 1 if it
# failed, 2 if it was still running when the poll timed out (LC_POLL_TIMEOUT,
# default 3600s), and 1 on any usage or transport error.

set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=lc-common.sh
. ./lc-common.sh

usage() { awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; exit "${1:-1}"; }

once=false
taskid=""
while [ $# -gt 0 ]; do
  case "$1" in
    --once)    once=true; shift ;;
    -h|--help) usage 0 ;;
    -*)        lc_die "Unknown option: $1" ;;
    *)         [ -z "$taskid" ] || lc_die "Unexpected argument: $1"; taskid="$1"; shift ;;
  esac
done
[ -n "$taskid" ] || usage 1

lc_require_deps
lc_require_token

if [ "$once" = true ]; then
  resp=$(lc_get "/rest/commandstatus/${taskid}?brief=true") \
    || lc_die "Could not read status for ${taskid}: ${resp:-no response}"
  lc_report "$resp"
  state=$(printf '%s' "$resp" | jq -r '.state // "unknown"')
  case "$state" in
    Scheduled|Executing) exit 2 ;;
    Success) [ "$(printf '%s' "$resp" | jq -r '.returnval')" = "0" ] && exit 0; exit 1 ;;
    *) exit 1 ;;
  esac
fi

printf 'Watching task %s' "$taskid" >&2
set +e
resp=$(lc_poll "$taskid")
rc=$?
set -e

lc_report "$resp"

case "$rc" in
  0) printf '\nTask %s succeeded.\n' "$taskid" ;;
  2) printf '\nStill running after %ss. Re-run to keep watching.\n' "$LC_POLL_TIMEOUT" >&2 ;;
  *) printf '\nTask %s did not succeed.\n' "$taskid" >&2 ;;
esac
exit "$rc"

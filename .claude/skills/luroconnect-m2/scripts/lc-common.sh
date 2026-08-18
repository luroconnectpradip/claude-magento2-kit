#!/usr/bin/env bash
# Shared helpers for the luroConnect REST scripts. Sourced, not run.

LC_API="${LC_API:-https://rest.luroconnect.com}"
LC_POLL_INTERVAL="${LC_POLL_INTERVAL:-5}"
LC_POLL_TIMEOUT="${LC_POLL_TIMEOUT:-3600}"

lc_die() { printf '%s\n' "$*" >&2; exit 1; }

lc_require_deps() {
  command -v curl >/dev/null 2>&1 || lc_die "curl is required but not installed."
  command -v jq   >/dev/null 2>&1 || lc_die "jq is required but not installed."
}

lc_require_token() {
  [ -n "${LC_TOKEN:-}" ] || lc_die \
"LC_TOKEN is not set.

Set it in your shell (not in a file in this repository):
    export LC_TOKEN='<jwt token from luroConnect>'

Ask luroConnect for a token if you do not have one."
}

# lc_get <path> -> body on stdout
lc_get() {
  curl --no-progress-meter --fail-with-body \
    --header "Content-Type: application/json" \
    --header "Authorization: Bearer ${LC_TOKEN}" \
    "${LC_API}$1"
}

# lc_post <path> <json body> -> body on stdout
lc_post() {
  curl --no-progress-meter --fail-with-body \
    --header "Content-Type: application/json" \
    --header "Authorization: Bearer ${LC_TOKEN}" \
    --request POST --data "$2" \
    "${LC_API}$1"
}

# lc_submit <path> <json body> -> taskid on stdout
# Exits non-zero if the command was not accepted.
lc_submit() {
  local resp status taskid
  resp=$(lc_post "$1" "$2") || lc_die "Request to $1 failed: ${resp:-no response}"
  status=$(printf '%s' "$resp" | jq -r '.status // false')
  if [ "$status" != "true" ]; then
    lc_die "luroConnect did not accept the command: $(printf '%s' "$resp" | jq -r '.message // .' )"
  fi
  taskid=$(printf '%s' "$resp" | jq -r '.taskid // empty')
  [ -n "$taskid" ] || lc_die "No taskid in response: $resp"
  printf '%s\n' "$taskid"
}

# lc_poll <taskid> -> full status JSON on stdout, progress dots on stderr.
# Returns 0 if the task succeeded, 1 if it failed, 2 if it timed out.
lc_poll() {
  local taskid="$1" waited=0 state resp
  while :; do
    resp=$(lc_get "/rest/commandstatus/${taskid}?brief=true") \
      || { printf '\n' >&2; lc_die "Could not read status for ${taskid}: ${resp:-no response}"; }
    state=$(printf '%s' "$resp" | jq -r '.state // "unknown"')
    case "$state" in
      Scheduled|Executing) ;;
      *) printf '\n' >&2
         printf '%s' "$resp"
         [ "$(printf '%s' "$resp" | jq -r '.state')" = "Success" ] \
           && [ "$(printf '%s' "$resp" | jq -r '.returnval')" = "0" ] && return 0
         return 1 ;;
    esac
    if [ "$waited" -ge "$LC_POLL_TIMEOUT" ]; then
      printf '\n' >&2
      printf '%s' "$resp"
      return 2
    fi
    printf '.' >&2
    sleep "$LC_POLL_INTERVAL"
    waited=$(( waited + LC_POLL_INTERVAL ))
  done
}

# lc_report <status json> -- print state, returnval and the log to stdout
lc_report() {
  printf 'state     : %s\n' "$(printf '%s' "$1" | jq -r '.state // "unknown"')"
  printf 'returnval : %s\n' "$(printf '%s' "$1" | jq -r '.returnval // "unknown"')"
  printf -- '--- log ---\n%s\n' "$(printf '%s' "$1" | jq -r '.message // ""')"
}

# lc_commit_id <status json> -- the built git commit id, from the "Git Commit :" line
lc_commit_id() {
  printf '%s' "$1" | jq -r '.message // ""' | awk '/Git Commit[[:space:]]*:/ {print $NF; exit}'
}

#!/usr/bin/env bash
# read-schema.sh - read the project's observed IKG data schema via
# GET /data-schema/v1/ (Data Schema API).
#
# Required env vars:
#   API_URL   IndyKite regional API base (no trailing slash). Must be one of
#             https://eu.api.indykite.com or https://us.api.indykite.com.
#   API_KEY   AppAgent credentials token (X-IK-ClientKey)
#
# The endpoint takes no parameters - the project is derived from the credential.
#
# Usage:
#   ./read-schema.sh
#   ./read-schema.sh --print   # print the curl (token redacted), don't run it

set -euo pipefail

endpoint="/data-schema/v1/"

print_only=0
if [[ "${1:-}" == "--print" ]]; then
    print_only=1
    shift
fi

if [[ "${#}" -ne 0 ]]; then
    printf 'usage: %s [--print]\n' "${0}" >&2
    exit 2
fi

: "${API_URL:?set API_URL}"
: "${API_KEY:?set API_KEY}"

# Pin the destination to known IndyKite API hosts. This call sends an AppAgent
# credential; restricting the host here means it can never be sent to an
# arbitrary, caller-supplied URL.
API_URL="${API_URL%/}"
case "${API_URL}" in
https://eu.api.indykite.com | https://us.api.indykite.com) ;;
*)
    printf '%s: refusing to send credentials to non-IndyKite host: %s\n' "${0##*/}" "${API_URL}" >&2
    exit 2
    ;;
esac

args=(
    -sS "${API_URL}${endpoint}"
    -H "X-IK-ClientKey: ${API_KEY}"
)

if [[ "${print_only}" == "1" ]]; then
    printf 'curl'
    for a in "${args[@]}"; do
        # Redact the credential value so --print never emits a live token.
        case "${a}" in
        "X-IK-ClientKey: "*) a="X-IK-ClientKey: \$API_KEY" ;;
        *) ;;
        esac
        printf ' %q' "${a}"
    done
    printf '\n'
else
    curl "${args[@]}"
fi

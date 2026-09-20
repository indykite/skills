#!/usr/bin/env bash
# whoami.sh - resolve the end-user token to its IKG subject via
# GET /contx-iq/v1/whoami (ContX IQ).
#
# Required env vars:
#   API_URL       IndyKite regional API base (no trailing slash). Must be one of
#                 https://eu.api.indykite.com or https://us.api.indykite.com.
#   API_KEY       AppAgent credentials token (X-IK-ClientKey). The agent must
#                 hold the ContXIQ API permission.
#   BEARER_TOKEN  User OAuth access token (Authorization: Bearer). Required -
#                 whoami has no _Application form.
#
# The endpoint takes no body and no parameters.
#
# Usage:
#   ./whoami.sh
#   ./whoami.sh --print   # print the curl (tokens redacted), don't run it

set -euo pipefail

endpoint="/contx-iq/v1/whoami"

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
: "${BEARER_TOKEN:?set BEARER_TOKEN (whoami requires the end-user token)}"

# Pin the destination to known IndyKite API hosts. This call sends an AppAgent
# credential and a bearer token; restricting the host here means they can
# never be sent to an arbitrary, caller-supplied URL.
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
    -H "Authorization: Bearer ${BEARER_TOKEN}"
)

if [[ "${print_only}" == "1" ]]; then
    printf 'curl'
    for a in "${args[@]}"; do
        # Redact credential values so --print never emits a live token.
        case "${a}" in
        "X-IK-ClientKey: "*) a="X-IK-ClientKey: \$API_KEY" ;;
        "Authorization: Bearer "*) a="Authorization: Bearer \$BEARER_TOKEN" ;;
        *) ;;
        esac
        printf ' %q' "${a}"
    done
    printf '\n'
else
    curl "${args[@]}"
fi

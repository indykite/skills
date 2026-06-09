#!/usr/bin/env bash
# search-action.sh - list the actions a subject may perform on a resource via
# POST /access/v1/search/action (AuthZEN).
#
# Required env vars:
#   API_URL       IndyKite regional API base (no trailing slash). Must be one of
#                 https://eu.api.indykite.com or https://us.api.indykite.com.
#   API_KEY       AppAgent credentials token (X-IK-ClientKey)
#
# Optional env vars:
#   BEARER_TOKEN  User OAuth access token. Optional - applies only in some cases.
#
# Arguments:
#   $1            Path to a JSON file with the search request body
#                 (subject / resource / optional context), e.g.
#                 assets/search-action-request.json. Use "-" for stdin.
#
# Usage:
#   ./search-action.sh assets/search-action-request.json
#   cat req.json | ./search-action.sh -
#   ./search-action.sh --print assets/search-action-request.json   # print the curl (tokens redacted), don't run it

set -euo pipefail

endpoint="/access/v1/search/action"

print_only=0
if [[ "${1:-}" == "--print" ]]; then
    print_only=1
    shift
fi

: "${API_URL:?set API_URL}"
: "${API_KEY:?set API_KEY}"

# Pin the destination to known IndyKite API hosts. This call sends an AppAgent
# credential (and optionally a user bearer token); restricting the host here
# means those secrets can never be POSTed to an arbitrary, caller-supplied URL.
API_URL="${API_URL%/}"
case "${API_URL}" in
https://eu.api.indykite.com | https://us.api.indykite.com) ;;
*)
    printf '%s: refusing to send credentials to non-IndyKite host: %s\n' "${0##*/}" "${API_URL}" >&2
    exit 2
    ;;
esac

if [[ "${#}" -ne 1 ]]; then
    printf 'usage: %s [--print] <search-request.json | ->\n' "${0}" >&2
    exit 2
fi

if [[ "${1}" == "-" ]]; then
    body="$(cat)"
elif [[ -f "${1}" ]]; then
    body="$(cat "${1}")"
else
    printf '%s: request file not found: %s\n' "${0##*/}" "${1}" >&2
    exit 2
fi

# Forward only well-formed JSON; never pipe arbitrary unvalidated input to the API.
if ! printf '%s' "${body}" | jq -e . >/dev/null 2>&1; then
    printf '%s: request body is not valid JSON\n' "${0##*/}" >&2
    exit 2
fi

args=(
    -sS -X POST "${API_URL}${endpoint}"
    -H "Content-Type: application/json"
    -H "X-IK-ClientKey: ${API_KEY}"
    --data "${body}"
)

if [[ -n "${BEARER_TOKEN:-}" ]]; then
    args+=(-H "Authorization: Bearer ${BEARER_TOKEN}")
fi

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

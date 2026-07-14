#!/usr/bin/env bash
# capture.sh - batch delete nodes via POST /capture/v1/nodes/delete (Capture API).
#
# Required env vars:
#   API_URL   IndyKite regional API base (no trailing slash). Must be one of
#             https://eu.api.indykite.com or https://us.api.indykite.com.
#   API_KEY   AppAgent credentials token (X-IK-ClientKey)
#
# Arguments:
#   $1        Path to a JSON file with the request body, e.g.
#             assets/delete-nodes.json. Use "-" for stdin.
#
# Usage:
#   ./capture.sh assets/delete-nodes.json
#   cat body.json | ./capture.sh -
#   ./capture.sh --print assets/delete-nodes.json   # print the curl (token redacted), don't run it

set -euo pipefail

ENDPOINT="/capture/v1/nodes/delete"

print_only=0
if [[ "${1:-}" == "--print" ]]; then
    print_only=1
    shift
fi

: "${API_URL:?set API_URL}"
: "${API_KEY:?set API_KEY}"

# Pin the destination to known IndyKite API hosts. This call sends an AppAgent
# credential; restricting the host here means it can never be POSTed to an
# arbitrary, caller-supplied URL.
API_URL="${API_URL%/}"
case "${API_URL}" in
https://eu.api.indykite.com | https://us.api.indykite.com) ;;
*)
    printf 'capture.sh: refusing to send credentials to non-IndyKite host: %s\n' "${API_URL}" >&2
    exit 2
    ;;
esac

if [[ "${#}" -ne 1 ]]; then
    printf 'usage: %s [--print] <request-body.json | ->\n' "${0}" >&2
    exit 2
fi

if [[ "${1}" == "-" ]]; then
    body="$(cat)"
elif [[ -f "${1}" ]]; then
    body="$(cat "${1}")"
else
    printf 'capture.sh: request file not found: %s\n' "${1}" >&2
    exit 2
fi

# Forward only a well-formed JSON object; never pipe arbitrary unvalidated input to the API.
if ! printf '%s' "${body}" | jq -e 'type == "object"' >/dev/null 2>&1; then
    printf 'capture.sh: request body must be a JSON object\n' >&2
    exit 2
fi

args=(
    -sS -X POST "${API_URL}${ENDPOINT}"
    -H "Content-Type: application/json"
    -H "X-IK-ClientKey: ${API_KEY}"
    --data-raw "${body}"
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

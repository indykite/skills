#!/usr/bin/env bash
# evaluate.sh - ask for a KBAC decision via POST /access/v1/evaluation (AuthZEN).
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
#   $1            Path to a JSON file with the evaluation request body
#                 (subject / resource / action / context), e.g.
#                 assets/evaluation-can-buy-car.json. Use "-" for stdin.
#
# Usage:
#   ./evaluate.sh assets/evaluation-can-buy-car.json
#   cat req.json | ./evaluate.sh -
#   ./evaluate.sh --print assets/evaluation-can-buy-car.json   # print the curl (tokens redacted), don't run it

set -euo pipefail

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
    printf 'evaluate.sh: refusing to send credentials to non-IndyKite host: %s\n' "${API_URL}" >&2
    exit 2
    ;;
esac

if [[ "${#}" -ne 1 ]]; then
    printf 'usage: %s [--print] <evaluation-request.json | ->\n' "${0}" >&2
    exit 2
fi

if [[ "${1}" == "-" ]]; then
    body="$(cat)"
elif [[ -f "${1}" ]]; then
    body="$(cat "${1}")"
else
    printf 'evaluate.sh: request file not found: %s\n' "${1}" >&2
    exit 2
fi

# Forward only well-formed JSON; never pipe arbitrary unvalidated input to the API.
if ! printf '%s' "${body}" | jq -e . >/dev/null 2>&1; then
    printf 'evaluate.sh: request body is not valid JSON\n' >&2
    exit 2
fi

args=(
    -sS -X POST "${API_URL}/access/v1/evaluation"
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

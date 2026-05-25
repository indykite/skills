#!/usr/bin/env bash
# evaluate.sh - ask for a KBAC decision via POST /access/v1/evaluation (AuthZEN).
#
# Required env vars:
#   API_URL       e.g. https://us.api.indykite.com  (no trailing slash)
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
#   ./evaluate.sh --print assets/evaluation-can-buy-car.json   # print the curl, don't run it

set -euo pipefail

print_only=0
if [[ "${1:-}" == "--print" ]]; then
    print_only=1
    shift
fi

: "${API_URL:?set API_URL}"
: "${API_KEY:?set API_KEY}"

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
        printf ' %q' "${a}"
    done
    printf '\n'
else
    curl "${args[@]}"
fi

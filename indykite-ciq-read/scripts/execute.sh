#!/usr/bin/env bash
# execute.sh — call POST /contx-iq/v1/execute with the right headers.
#
# Required env vars:
#   API_URL       e.g. https://us.api.indykite.com  (no trailing slash)
#   API_KEY       AppAgent credentials token (X-IK-ClientKey)
#   QUERY_ID      Knowledge Query GID or name
#
# Optional env vars:
#   BEARER_TOKEN  User OAuth access token. Required when the policy's
#                 subject.type is NOT _Application; omit otherwise.
#   IK_TOKEN      Delegation token from the Token Service (X-IK-Token). Optional.
#
# Arguments:
#   $1            Path to a JSON file containing input_params, e.g.
#                 { "person_external_id": "alice" }
#                 Use "-" to read from stdin.
#
# Usage:
#   ./execute.sh input_params.json
#   echo '{"person_external_id":"alice"}' | ./execute.sh -

set -euo pipefail

print_only=0
if [[ "${1:-}" == "--print" ]]; then
    print_only=1
    shift
fi

: "${API_URL:?set API_URL}"
: "${API_KEY:?set API_KEY}"
: "${QUERY_ID:?set QUERY_ID}"

if [[ "${#}" -ne 1 ]]; then
    printf 'usage: %s [--print] <input_params.json | ->\n' "${0}" >&2
    exit 2
fi

if [[ "${1}" == "-" ]]; then
    input_params="$(cat)"
elif [[ -f "${1}" ]]; then
    input_params="$(cat "${1}")"
else
    printf 'execute.sh: input file not found: %s\n' "${1}" >&2
    exit 2
fi

body="$(printf '{"id":"%s","input_params":%s}' "${QUERY_ID}" "${input_params}")"

args=(
    -sS -X POST "${API_URL}/contx-iq/v1/execute"
    -H "Content-Type: application/json"
    -H "X-IK-ClientKey: ${API_KEY}"
    --data "${body}"
)

if [[ -n "${BEARER_TOKEN:-}" ]]; then
    args+=(-H "Authorization: Bearer ${BEARER_TOKEN}")
fi

if [[ -n "${IK_TOKEN:-}" ]]; then
    args+=(-H "X-IK-Token: ${IK_TOKEN}")
fi

if [[ "${print_only}" == "1" ]]; then
    printf 'curl'
    for a in "${args[@]}"; do
        # --print shows placeholders instead of header values.
        case "${a}" in
        "X-IK-ClientKey: "*) a="X-IK-ClientKey: \$API_KEY" ;;
        "Authorization: Bearer "*) a="Authorization: Bearer \$BEARER_TOKEN" ;;
        "X-IK-Token: "*) a="X-IK-Token: \$IK_TOKEN" ;;
        *) ;;
        esac
        printf ' %q' "${a}"
    done
    printf '\n'
else
    curl "${args[@]}"
fi

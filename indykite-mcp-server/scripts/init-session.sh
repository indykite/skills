#!/usr/bin/env bash
# init-session.sh — initialize an IndyKite MCP session and print the Mcp-Session-Id.
#
# Required env vars:
#   MCP_URL       e.g. https://us.mcp.indykite.com  (no trailing slash)
#   PROJECT_GID   IndyKite project GID
#   API_KEY       AppAgent credentials token (X-IK-ClientKey)
#   BEARER_TOKEN  User OAuth access token   (Authorization: Bearer)
#
# Usage:
#   SESSION_ID=$(./init-session.sh)
#   ./init-session.sh --print          # print the equivalent curl command instead of running it
#
# On failure (non-print mode) the script writes the response to stderr and exits non-zero.

set -euo pipefail

print_only=0
if [[ "${1:-}" == "--print" ]]; then
    print_only=1
    shift
fi

: "${MCP_URL:?set MCP_URL}"
: "${PROJECT_GID:?set PROJECT_GID}"
: "${API_KEY:?set API_KEY}"
: "${BEARER_TOKEN:?set BEARER_TOKEN}"

body='{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": "2025-11-25",
    "capabilities": {},
    "clientInfo": {"name": "init-session.sh", "version": "1.0"}
  }
}'

args=(
    -sS -i -X POST "${MCP_URL}/mcp/v1/${PROJECT_GID}"
    -H "Content-Type: application/json"
    -H "Authorization: Bearer ${BEARER_TOKEN}"
    -H "X-IK-ClientKey: ${API_KEY}"
    -d "${body}"
)

if [[ "${print_only}" == "1" ]]; then
    printf 'curl'
    for a in "${args[@]}"; do
        printf ' %q' "${a}"
    done
    printf '\n'
    exit 0
fi

response="$(curl "${args[@]}")"

session_id="$(printf '%s' "${response}" |
    awk 'BEGIN{IGNORECASE=1} /^Mcp-Session-Id:/{sub(/^[^:]*:[ \t]*/, ""); sub(/[\r\n]+$/, ""); print; exit}')"

if [[ -z "${session_id}" ]]; then
    printf 'init-session.sh: no Mcp-Session-Id in response. Full response:\n%s\n' "${response}" >&2
    exit 1
fi

printf '%s\n' "${session_id}"

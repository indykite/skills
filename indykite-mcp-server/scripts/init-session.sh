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
#
# On failure the script writes the response to stderr and exits non-zero.

set -euo pipefail

: "${MCP_URL:?set MCP_URL}"
: "${PROJECT_GID:?set PROJECT_GID}"
: "${API_KEY:?set API_KEY}"
: "${BEARER_TOKEN:?set BEARER_TOKEN}"

response="$(
  curl -sS -i -X POST "${MCP_URL}/mcp/v1/${PROJECT_GID}" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${BEARER_TOKEN}" \
    -H "X-IK-ClientKey: ${API_KEY}" \
    -d '{
          "jsonrpc": "2.0",
          "id": 1,
          "method": "initialize",
          "params": {
            "protocolVersion": "2025-11-25",
            "capabilities": {},
            "clientInfo": {"name": "init-session.sh", "version": "1.0"}
          }
        }'
)"

session_id="$(printf '%s' "$response" \
  | awk 'BEGIN{IGNORECASE=1} /^Mcp-Session-Id:/{sub(/^[^:]*:[ \t]*/, ""); sub(/[\r\n]+$/, ""); print; exit}')"

if [ -z "$session_id" ]; then
  printf 'init-session.sh: no Mcp-Session-Id in response. Full response:\n%s\n' "$response" >&2
  exit 1
fi

printf '%s\n' "$session_id"

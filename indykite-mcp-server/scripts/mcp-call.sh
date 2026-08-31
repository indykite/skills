#!/usr/bin/env bash
# mcp-call.sh — make one stateless IndyKite MCP call (protocol revision 2026-07-28).
#
# Builds the params._meta object and the Mcp-Protocol-Version / Mcp-Method /
# Mcp-Name headers the stateless protocol requires, then POSTs the request.
# No session is created and no Mcp-Session-Id is involved.
#
# Required env vars:
#   MCP_URL       e.g. https://us.mcp.indykite.com  (no trailing slash)
#   PROJECT_GID   IndyKite project GID
#   BEARER_TOKEN  User OAuth access token   (Authorization: Bearer)
#
# The AppAgent the server uses at runtime is resolved server-side from the
# project's MCP server configuration (app_agent_id); no X-IK-ClientKey is sent.
#
# Usage:
#   ./mcp-call.sh server/discover
#   ./mcp-call.sh tools/list
#   ./mcp-call.sh resources/list
#   ./mcp-call.sh resources/read 'indykite://knowledge-queries/'
#   ./mcp-call.sh tools/call authzen_evaluate '{"subject_type":"Person","subject_id":"alice","resource_type":"Car","resource_id":"cadillacv16","action_name":"CAN_DRIVE"}'
#   ./mcp-call.sh --print tools/list   # print the equivalent curl command instead of running it
#
# The raw response body is written to stdout. Responses may arrive as an SSE
# stream; the JSON-RPC message is then on the `data:` line of the event.

set -euo pipefail

protocol_version="2026-07-28"

print_only=0
if [[ "${1:-}" == "--print" ]]; then
    print_only=1
    shift
fi

if [[ $# -lt 1 ]]; then
    printf 'usage: %s [--print] <jsonrpc-method> [tool-name|resource-uri|prompt-name] [arguments-json]\n' "$0" >&2
    exit 2
fi

method="$1"
name="${2:-}"
arguments="${3:-}"
[[ -n "${arguments}" ]] || arguments='{}'

# method and name are interpolated into the JSON body and the Mcp-* headers,
# so reject characters that would break either.
if [[ ! "${method}" =~ ^[A-Za-z0-9._/-]+$ ]]; then
    printf 'mcp-call.sh: invalid jsonrpc method: %q\n' "${method}" >&2
    exit 2
fi
if [[ -n "${name}" ]] && [[ ! "${name}" =~ ^[A-Za-z0-9:._/@-]+$ ]]; then
    printf 'mcp-call.sh: invalid name: %q\n' "${name}" >&2
    exit 2
fi

: "${MCP_URL:?set MCP_URL}"
: "${PROJECT_GID:?set PROJECT_GID}"
: "${BEARER_TOKEN:?set BEARER_TOKEN}"

meta='"_meta": {
      "io.modelcontextprotocol/protocolVersion": "'"${protocol_version}"'",
      "io.modelcontextprotocol/clientCapabilities": {},
      "io.modelcontextprotocol/clientInfo": {"name": "mcp-call.sh", "version": "1.0"}
    }'

name_header=""
case "${method}" in
tools/call)
    [[ -n "${name}" ]] || {
        printf 'mcp-call.sh: tools/call needs a tool name\n' >&2
        exit 2
    }
    params='{"name": "'"${name}"'", "arguments": '"${arguments}"', '"${meta}"'}'
    name_header="${name}"
    ;;
resources/read)
    [[ -n "${name}" ]] || {
        printf 'mcp-call.sh: resources/read needs a resource URI\n' >&2
        exit 2
    }
    params='{"uri": "'"${name}"'", '"${meta}"'}'
    name_header="${name}"
    ;;
prompts/get)
    [[ -n "${name}" ]] || {
        printf 'mcp-call.sh: prompts/get needs a prompt name\n' >&2
        exit 2
    }
    params='{"name": "'"${name}"'", '"${meta}"'}'
    name_header="${name}"
    ;;
*)
    params='{'"${meta}"'}'
    ;;
esac

body='{"jsonrpc": "2.0", "id": 1, "method": "'"${method}"'", "params": '"${params}"'}'

args=(
    -sS -X POST "${MCP_URL}/mcp/v1/${PROJECT_GID}"
    -H "Content-Type: application/json"
    -H "Accept: application/json, text/event-stream"
    -H "Authorization: Bearer ${BEARER_TOKEN}"
    -H "Mcp-Protocol-Version: ${protocol_version}"
    -H "Mcp-Method: ${method}"
)
if [[ -n "${name_header}" ]]; then
    args+=(-H "Mcp-Name: ${name_header}")
fi
args+=(-d "${body}")

if [[ "${print_only}" == "1" ]]; then
    printf 'curl'
    for a in "${args[@]}"; do
        printf ' %q' "${a}"
    done
    printf '\n'
    exit 0
fi

curl "${args[@]}"

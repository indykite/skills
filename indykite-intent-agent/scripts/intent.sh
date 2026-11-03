#!/usr/bin/env bash
# intent.sh - send one prompt to a self-hosted IndyKite Intent Agent as an A2A
# SendMessage (JSON-RPC) and print the task it answers with.
#
# Required env vars:
#   INTENT_AGENT_URL  The agent's JSON-RPC base URL, http or https, no trailing
#                     slash (e.g. http://localhost:6003, or the ingress host).
#   BEARER_TOKEN      The caller's access token (Authorization: Bearer); it must
#                     be active at the agent's introspection endpoint and carry
#                     the agent's audience (intent_agent by default).
#   SUBJECT_TYPE      The user's node type in the graph (message.metadata).
#   SUBJECT_ID        The user's external_id (message.metadata).
#
# Usage:
#   ./intent.sh "Can I retrieve the quote stock_quote?"
#   echo "Which invoices can I view?" | ./intent.sh -
#   ./intent.sh --request-id req-42 "Who can access the document refund_policy?"
#   ./intent.sh --print "Can I retrieve the quote stock_quote?"   # print the curl, don't run it
#
# The raw JSON-RPC response is written to stdout. The intent is the text of the
# artifact named "result":  jq -r '.result.task.artifacts[0].parts[0].text' | jq .

set -euo pipefail

print_only=0
request_id=""
while [[ $# -gt 0 ]]; do
    case "${1}" in
    --print)
        print_only=1
        shift
        ;;
    --request-id)
        [[ $# -ge 2 ]] || {
            printf 'intent.sh: --request-id needs a value\n' >&2
            exit 2
        }
        request_id="${2}"
        shift 2
        ;;
    --)
        shift
        break
        ;;
    -)
        break
        ;;
    -*)
        printf 'intent.sh: unknown option: %s\n' "${1}" >&2
        exit 2
        ;;
    *)
        break
        ;;
    esac
done

if [[ $# -ne 1 ]]; then
    printf 'usage: %s [--print] [--request-id <id>] <prompt | ->\n' "${0}" >&2
    exit 2
fi

if [[ "${1}" == "-" ]]; then
    prompt="$(cat)"
else
    prompt="${1}"
fi
if [[ -z "${prompt//[[:space:]]/}" ]]; then
    printf 'intent.sh: the prompt is empty\n' >&2
    exit 2
fi

if [[ -n "${request_id}" ]]; then
    # The agent keeps X-Request-ID only when it is at most 40 characters; it is
    # also a header value, so keep it to plain printable characters.
    if [[ ${#request_id} -gt 40 ]] || [[ ! "${request_id}" =~ ^[A-Za-z0-9._:@/-]+$ ]]; then
        printf 'intent.sh: --request-id must be 1-40 characters of [A-Za-z0-9._:@/-]\n' >&2
        exit 2
    fi
fi

: "${INTENT_AGENT_URL:?set INTENT_AGENT_URL}"
: "${BEARER_TOKEN:?set BEARER_TOKEN}"
: "${SUBJECT_TYPE:?set SUBJECT_TYPE}"
: "${SUBJECT_ID:?set SUBJECT_ID}"

INTENT_AGENT_URL="${INTENT_AGENT_URL%/}"
case "${INTENT_AGENT_URL}" in
http://* | https://*) ;;
*)
    printf 'intent.sh: INTENT_AGENT_URL must start with http:// or https://: %s\n' "${INTENT_AGENT_URL}" >&2
    exit 2
    ;;
esac

if ! command -v jq >/dev/null 2>&1; then
    printf 'intent.sh: jq is required to build the request body\n' >&2
    exit 2
fi

message_id="msg-$(date +%s)-$$"

# jq builds the body, so the prompt and the subject values are JSON-escaped
# whatever characters they contain.
body="$(jq -cn \
    --arg prompt "${prompt}" \
    --arg message_id "${message_id}" \
    --arg subject_type "${SUBJECT_TYPE}" \
    --arg subject_id "${SUBJECT_ID}" \
    '{
      jsonrpc: "2.0",
      id: "1",
      method: "SendMessage",
      params: {
        message: {
          role: "ROLE_USER",
          messageId: $message_id,
          parts: [{text: $prompt}],
          metadata: {subject_type: $subject_type, subject_id: $subject_id}
        }
      }
    }')"

args=(
    -sS -X POST "${INTENT_AGENT_URL}/"
    -H "Content-Type: application/json"
    -H "A2A-Version: 1.0"
    -H "Authorization: Bearer ${BEARER_TOKEN}"
)
if [[ -n "${request_id}" ]]; then
    args+=(-H "X-Request-ID: ${request_id}")
fi
args+=(-d "${body}")

if [[ "${print_only}" == "1" ]]; then
    printf 'curl'
    for a in "${args[@]}"; do
        # --print shows a placeholder instead of the header value.
        case "${a}" in
        "Authorization: Bearer "*) a="Authorization: Bearer \$BEARER_TOKEN" ;;
        *) ;;
        esac
        printf ' %q' "${a}"
    done
    printf '\n'
else
    curl "${args[@]}"
fi

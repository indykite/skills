#!/usr/bin/env bash
# audit-logs.sh - read a project's tamper-proof audit trail through the IndyKite
# Audit Log API (GET /audit/v1/logs, /audit/v1/manifests, /audit/v1/checkpoints)
# or fetch the public signature-verification keys (GET /audit/.well-known/jwks.json).
#
# Required env vars:
#   API_URL      IndyKite regional API base (no trailing slash). Must be one of
#                https://eu.api.indykite.com or https://us.api.indykite.com.
#   PROJECT_GID  Project (application space) GID, e.g. gid:AAAAAxxxx. Every
#                endpoint takes it as ?project_id=.
#   API_KEY      AppAgent credentials token (X-IK-ClientKey). The agent must hold
#                the `Audit` API permission and belong to PROJECT_GID. Not read
#                for `jwks`, which is public.
#
# Arguments:
#   $1   One of: logs | manifests | checkpoints | jwks
#   --cursor <c>     Opaque page cursor copied from a previous response's next_cursor.
#   --pagesize <n>   Items per page, 1-50 (the API default and maximum are both 50).
#   --all            Follow next_cursor until has_more is false and print every
#                    item as one JSON array, streamed page by page (needs jq).
#                    A cursor the API hands out twice stops the export with an
#                    error instead of looping. Not for jwks.
#   --jsonl          With --all: print one item per line instead of one array,
#                    for exports too large to hold in memory downstream.
#
# Usage:
#   ./audit-logs.sh logs
#   ./audit-logs.sh manifests --pagesize 10
#   ./audit-logs.sh manifests --cursor "$(jq -r .next_cursor page1.json)"
#   ./audit-logs.sh manifests --all > manifests.json
#   ./audit-logs.sh logs --all --jsonl > logs.jsonl
#   ./audit-logs.sh checkpoints
#   ./audit-logs.sh jwks > jwks.json
#   ./audit-logs.sh --print logs        # print the curl (token redacted), don't run it

set -euo pipefail

usage() {
    printf 'usage: %s [--print] <logs|manifests|checkpoints|jwks> [--cursor <c>] [--pagesize <1-50>] [--all [--jsonl]]\n' "${0}" >&2
    exit 2
}

print_only=0
if [[ "${1:-}" == "--print" ]]; then
    print_only=1
    shift
fi

[[ "${#}" -ge 1 ]] || usage
resource="${1}"
shift

case "${resource}" in
logs) endpoint="/audit/v1/logs" ;;
manifests) endpoint="/audit/v1/manifests" ;;
checkpoints) endpoint="/audit/v1/checkpoints" ;;
jwks) endpoint="/audit/.well-known/jwks.json" ;;
*) usage ;;
esac

cursor=""
pagesize=""
all=0
jsonl=0
while [[ "${#}" -gt 0 ]]; do
    case "${1}" in
    --jsonl)
        jsonl=1
        shift
        ;;
    --cursor)
        [[ "${#}" -ge 2 ]] || usage
        cursor="${2}"
        shift 2
        ;;
    --pagesize)
        [[ "${#}" -ge 2 ]] || usage
        pagesize="${2}"
        shift 2
        ;;
    --all)
        all=1
        shift
        ;;
    *) usage ;;
    esac
done

: "${API_URL:?set API_URL}"
: "${PROJECT_GID:?set PROJECT_GID}"
if [[ "${resource}" != "jwks" ]]; then
    : "${API_KEY:?set API_KEY}"
fi

# Pin the destination to known IndyKite API hosts. The listing calls send an
# AppAgent credential; restricting the host here means it can never be sent to
# an arbitrary, caller-supplied URL.
API_URL="${API_URL%/}"
case "${API_URL}" in
https://eu.api.indykite.com | https://us.api.indykite.com) ;;
*)
    printf '%s: refusing to send credentials to non-IndyKite host: %s\n' "${0##*/}" "${API_URL}" >&2
    exit 2
    ;;
esac

# The query values are validated against the shapes the API accepts rather than
# URL-encoded, so nothing but a GID, a cursor, and a small integer can reach the URL.
if [[ ! "${PROJECT_GID}" =~ ^gid:[A-Za-z0-9_-]{1,255}$ ]]; then
    printf '%s: PROJECT_GID must be a project GID (gid:...): %s\n' "${0##*/}" "${PROJECT_GID}" >&2
    exit 2
fi
if [[ -n "${cursor}" && ! "${cursor}" =~ ^[A-Za-z0-9_-]{1,512}$ ]]; then
    printf '%s: --cursor must be a next_cursor value from a previous response\n' "${0##*/}" >&2
    exit 2
fi
if [[ -n "${pagesize}" && ! "${pagesize}" =~ ^([1-9]|[1-4][0-9]|50)$ ]]; then
    printf '%s: --pagesize must be an integer from 1 to 50\n' "${0##*/}" >&2
    exit 2
fi
if [[ "${resource}" == "jwks" && (-n "${cursor}" || -n "${pagesize}" || "${all}" == "1") ]]; then
    printf '%s: jwks takes no --cursor, --pagesize, or --all\n' "${0##*/}" >&2
    exit 2
fi
if [[ "${all}" == "1" ]] && ! command -v jq >/dev/null; then
    printf '%s: --all needs jq\n' "${0##*/}" >&2
    exit 2
fi
if [[ "${jsonl}" == "1" && "${all}" == "0" ]]; then
    printf '%s: --jsonl only applies with --all\n' "${0##*/}" >&2
    exit 2
fi

build_args() {
    # $1 = cursor for this page
    local url="${API_URL}${endpoint}?project_id=${PROJECT_GID}"
    [[ -z "${1}" ]] || url="${url}&cursor=${1}"
    [[ -z "${pagesize}" ]] || url="${url}&pagesize=${pagesize}"
    args=(-sS "${url}" -H "Accept: application/json")
    if [[ "${resource}" != "jwks" ]]; then
        args+=(-H "X-IK-ClientKey: ${API_KEY}")
    fi
}

if [[ "${print_only}" == "1" ]]; then
    build_args "${cursor}"
    printf 'curl'
    for a in "${args[@]}"; do
        # --print shows placeholders instead of header values.
        case "${a}" in
        "X-IK-ClientKey: "*) a="X-IK-ClientKey: \$API_KEY" ;;
        *) ;;
        esac
        printf ' %q' "${a}"
    done
    printf '\n'
    exit 0
fi

if [[ "${all}" == "0" ]]; then
    build_args "${cursor}"
    curl "${args[@]}"
    exit 0
fi

# --all: follow next_cursor. Pages land in a temp file on disk, one page per line,
# so a failed page never leaves a half-printed array behind; the output is then
# streamed from that file one page at a time, so memory stays bounded by one page.
pages="$(mktemp)"
trap 'rm -f "${pages}"' EXIT
declare -A seen
next="${cursor}"
while :; do
    # A cursor handed out twice would loop forever; the API must always advance.
    if [[ -n "${seen[_${next}]:-}" ]]; then
        printf '%s: the API returned cursor %q a second time; stopping the export\n' "${0##*/}" "${next}" >&2
        exit 1
    fi
    seen["_${next}"]=1
    build_args "${next}"
    # On an HTTP error the API's JSON error body goes to stderr and the export stops,
    # rather than being swallowed into the page buffer.
    if ! page="$(curl --fail-with-body "${args[@]}")"; then
        printf '%s: page request failed: %s\n' "${0##*/}" "${page}" >&2
        exit 1
    fi
    # Types matter, not just key presence: a page with "has_more": null would otherwise
    # read as the last page and end the export silently short.
    if ! jq -e 'type == "object" and (.items | type) == "array" and (.has_more | type) == "boolean"
        and (.next_cursor | type) == "string"' <<<"${page}" >/dev/null 2>&1; then
        printf '%s: response is not an audit page envelope: %s\n' "${0##*/}" "${page:0:200}" >&2
        exit 1
    fi
    printf '%s\n' "${page}" >>"${pages}"
    has_more="$(jq -r '.has_more' <<<"${page}")"
    if [[ "${has_more}" != "true" ]]; then
        break
    fi
    next="$(jq -r '.next_cursor' <<<"${page}")"
    if [[ ! "${next}" =~ ^[A-Za-z0-9_-]{1,512}$ ]]; then
        printf '%s: response carried has_more without a usable next_cursor\n' "${0##*/}" >&2
        exit 1
    fi
done

if [[ "${jsonl}" == "1" ]]; then
    jq -c '.items[]' "${pages}"
    exit 0
fi
printf '['
sep=''
jq -c '.items[]' "${pages}" | while IFS= read -r item; do
    printf '%s%s' "${sep}" "${item}"
    sep=','
done
printf ']\n'

#!/usr/bin/env bash
# create-policy.sh - create a KBAC authorization policy via
# POST /configs/v1/authorization-policies (Config API).
#
# Takes a create envelope whose `policy` field is a JSON *object* and whose
# `project_id` is a placeholder; sets project_id from PROJECT_GID and stringifies
# the `policy` field (the Config API expects `policy` as a JSON string) before
# POSTing.
#
# Required env vars:
#   API_URL                IndyKite regional API base (no trailing slash). Must be one of
#                          https://eu.api.indykite.com or https://us.api.indykite.com.
#   SERVICE_ACCOUNT_TOKEN  Service Account token with Config API write access (Bearer).
#   PROJECT_GID            Project GID; written into the envelope's project_id.
#
# Arguments:
#   $1                     Path to the create-envelope JSON (policy as an object,
#                          project_id placeholder), e.g. assets/policy-provision-server.json.
#                          Use "-" for stdin.
#
# Usage:
#   ./create-policy.sh assets/policy-provision-server.json
#   cat envelope.json | ./create-policy.sh -
#   ./create-policy.sh --print assets/policy-provision-server.json   # print the curl (token redacted), don't run it

set -euo pipefail

print_only=0
if [[ "${1:-}" == "--print" ]]; then
    print_only=1
    shift
fi

: "${API_URL:?set API_URL}"
: "${SERVICE_ACCOUNT_TOKEN:?set SERVICE_ACCOUNT_TOKEN}"
: "${PROJECT_GID:?set PROJECT_GID}"

# Pin the destination to known IndyKite API hosts. This call sends a Service
# Account credential; restricting the host here means it can never be POSTed to
# an arbitrary, caller-supplied URL.
API_URL="${API_URL%/}"
case "${API_URL}" in
https://eu.api.indykite.com | https://us.api.indykite.com) ;;
*)
    printf '%s: refusing to send credentials to non-IndyKite host: %s\n' "${0##*/}" "${API_URL}" >&2
    exit 2
    ;;
esac

if [[ "${#}" -ne 1 ]]; then
    printf 'usage: %s [--print] <create-envelope.json | ->\n' "${0}" >&2
    exit 2
fi

if [[ "${1}" == "-" ]]; then
    envelope="$(cat)"
elif [[ -f "${1}" ]]; then
    envelope="$(cat "${1}")"
else
    printf '%s: envelope file not found: %s\n' "${0##*/}" "${1}" >&2
    exit 2
fi

# Set project_id and stringify only the `policy` field; this also validates JSON.
if ! body="$(printf '%s' "${envelope}" |
    jq --arg pid "${PROJECT_GID}" -c '.project_id = $pid | .policy |= tojson' 2>/dev/null)"; then
    printf '%s: envelope is not valid JSON (or missing a .policy field)\n' "${0##*/}" >&2
    exit 2
fi

args=(
    -sS -X POST "${API_URL}/configs/v1/authorization-policies"
    -H "Content-Type: application/json"
    -H "Authorization: Bearer ${SERVICE_ACCOUNT_TOKEN}"
    --data "${body}"
)

if [[ "${print_only}" == "1" ]]; then
    printf 'curl'
    for a in "${args[@]}"; do
        # Redact the credential value so --print never emits a live token.
        case "${a}" in
        "Authorization: Bearer "*) a="Authorization: Bearer \$SERVICE_ACCOUNT_TOKEN" ;;
        *) ;;
        esac
        printf ' %q' "${a}"
    done
    printf '\n'
else
    curl "${args[@]}"
fi

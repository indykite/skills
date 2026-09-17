#!/usr/bin/env bash
# list-policies.sh - list the ACTIVE KBAC policies of the calling app agent's
# project via GET /access/v1/policies (AuthZEN).
#
# Required env vars:
#   API_URL   IndyKite regional API base (no trailing slash). Must be one of
#             https://eu.api.indykite.com or https://us.api.indykite.com.
#   API_KEY   AppAgent credentials token (X-IK-ClientKey). The agent must hold
#             the ReadAuthZConfigs API permission.
#
# Arguments:
#   $1        Optional subject type (e.g. Person, _Application). When given it
#             is sent as ?subject_type=<value> and only the policies written
#             for that subject type are returned.
#
# Usage:
#   ./list-policies.sh                    # every ACTIVE KBAC policy
#   ./list-policies.sh Person             # only policies whose subject.type is Person
#   ./list-policies.sh --print [Person]   # print the curl (token redacted), don't run it

set -euo pipefail

endpoint="/access/v1/policies"

print_only=0
if [[ "${1:-}" == "--print" ]]; then
    print_only=1
    shift
fi

if [[ "${#}" -gt 1 ]]; then
    printf 'usage: %s [--print] [subject_type]\n' "${0}" >&2
    exit 2
fi

: "${API_URL:?set API_URL}"
: "${API_KEY:?set API_KEY}"

# Pin the destination to known IndyKite API hosts. This call sends an AppAgent
# credential; restricting the host here means it can never be sent to an
# arbitrary, caller-supplied URL.
API_URL="${API_URL%/}"
case "${API_URL}" in
https://eu.api.indykite.com | https://us.api.indykite.com) ;;
*)
    printf '%s: refusing to send credentials to non-IndyKite host: %s\n' "${0##*/}" "${API_URL}" >&2
    exit 2
    ;;
esac

url="${API_URL}${endpoint}"
if [[ "${#}" -eq 1 ]]; then
    subject_type="${1}"
    # A node type is a plain label (letters, digits, underscore); refuse
    # anything else rather than URL-encoding arbitrary input into the query.
    if [[ ! "${subject_type}" =~ ^[A-Za-z_][A-Za-z0-9_]{1,63}$ ]]; then
        printf '%s: subject_type must be a node label (2-64 chars: letters, digits, _): %s\n' "${0##*/}" "${subject_type}" >&2
        exit 2
    fi
    url="${url}?subject_type=${subject_type}"
fi

args=(
    -sS "${url}"
    -H "X-IK-ClientKey: ${API_KEY}"
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

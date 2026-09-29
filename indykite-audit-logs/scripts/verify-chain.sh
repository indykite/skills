#!/usr/bin/env bash
# verify-chain.sh - verify a project's tamper-proof audit trail offline, from
# files saved with audit-logs.sh: manifests (chain linkage + signatures),
# optionally checkpoints (signatures + the chain still holding the recorded head)
# and logs (batch hashes, chain position and signatures).
#
# Nothing here talks to the network. It reproduces the integrity checks the
# platform itself performs on the trail, with jq and openssl only:
#
#   head_hash  = sha256("<project_id>|<sequence>|<prev_hash>|<data_hash>|<batch_id>")
#   signature  = base64(ECDSA P-256 over the 32-byte digest, ASN.1 DER)  -- alg ES256-DER
#   checkpoint = sha256("project-checkpoint|<project_id>|<sequence>|<head_hash>|<created_at>")
#
# Inputs (JSON files; a page response {items:[...]} or a plain array as --all writes):
#   --jwks <file>          Output of `audit-logs.sh jwks` (required).
#   --manifests <file>     Output of `audit-logs.sh manifests [--all]` (required).
#   --checkpoints <file>   Output of `audit-logs.sh checkpoints` (optional).
#   --logs <file>          Output of `audit-logs.sh logs [--all]` (optional).
#   --allow-partial        Accept a manifests file that starts above sequence 1. The
#                          trail before its first entry is then not verified, and the
#                          final line says so instead of reporting the whole chain.
#
# The manifests file must start at sequence 1 (or --allow-partial must be given) and cover
# every sequence the checkpoints and logs files name: a checkpoint or batch the manifests do
# not reach is reported as a failed check, not skipped. Every entry must belong to the same
# project as the first manifest. The files are treated as untrusted input; nothing in them
# is evaluated as code.
#
# Usage:
#   ./verify-chain.sh --jwks jwks.json --manifests manifests.json
#   ./verify-chain.sh --jwks jwks.json --manifests manifests.json --checkpoints cps.json --logs logs.json
#   ./verify-chain.sh --jwks jwks.json --manifests page7.json --allow-partial
#
# Exit status: 0 when every check passed, 1 when any check failed, 2 on usage errors.
# Requires: bash 4+, jq, openssl (1.1+ or 3.x).

set -euo pipefail

usage() {
    printf 'usage: %s --jwks <file> --manifests <file> [--checkpoints <file>] [--logs <file>] [--allow-partial]\n' "${0}" >&2
    exit 2
}

jwks=""
manifests=""
checkpoints=""
logs=""
allow_partial=0
while [[ "${#}" -gt 0 ]]; do
    case "${1}" in
    --allow-partial)
        allow_partial=1
        shift
        ;;
    --jwks)
        [[ "${#}" -ge 2 ]] || usage
        jwks="${2}"
        shift 2
        ;;
    --manifests)
        [[ "${#}" -ge 2 ]] || usage
        manifests="${2}"
        shift 2
        ;;
    --checkpoints)
        [[ "${#}" -ge 2 ]] || usage
        checkpoints="${2}"
        shift 2
        ;;
    --logs)
        [[ "${#}" -ge 2 ]] || usage
        logs="${2}"
        shift 2
        ;;
    *) usage ;;
    esac
done
[[ -n "${jwks}" && -n "${manifests}" ]] || usage
for f in "${jwks}" "${manifests}" "${checkpoints}" "${logs}"; do
    if [[ -n "${f}" && ! -r "${f}" ]]; then
        printf '%s: cannot read %s\n' "${0##*/}" "${f}" >&2
        exit 2
    fi
done
for tool in jq openssl; do
    if ! command -v "${tool}" >/dev/null; then
        printf '%s: %s is required\n' "${0##*/}" "${tool}" >&2
        exit 2
    fi
done

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

failures=0
fail() {
    failures=$((failures + 1))
    printf 'FAIL  %s\n' "$*"
}
ok() { printf 'ok    %s\n' "$*"; }
warn() { printf 'warn  %s\n' "$*"; }

# Fields are joined with the ASCII unit separator, not tabs: `read` with a
# whitespace IFS collapses consecutive tabs, which would swallow the empty
# prev_hash of sequence 1 and shift every field after it.
us=$'\x1f'

# items <file> - normalise a page response or an array into one JSON array.
items() {
    jq -c 'if type == "array" then . else .items end' "${1}"
}

# hex_to_bin <hex> <out-file>
hex_to_bin() {
    local hex="${1}" out="${2}" escaped
    escaped="$(printf '%s' "${hex}" | sed 's/../\\x&/g')"
    # shellcheck disable=SC2059 # the format string is the escaped hex we just built
    printf "${escaped}" >"${out}"
}

# b64url_to_hex <base64url>
b64url_to_hex() {
    local s="${1//-/+}"
    s="${s//_//}"
    while [[ $((${#s} % 4)) -ne 0 ]]; do s="${s}="; done
    printf '%s' "${s}" | openssl base64 -d -A | od -An -v -tx1 | tr -d ' \n'
}

sha256_hex() {
    printf '%s' "${1}" | openssl dgst -sha256 -r | cut -d' ' -f1
}

# --- 1. Load the verification keys ------------------------------------------
# The JWKS carries EC P-256 keys. Build a SubjectPublicKeyInfo DER from x and y
# (the fixed P-256 prefix followed by the uncompressed point 04||X||Y) so openssl
# can read it; the key carries no "alg" on purpose (see the reference).
p256_spki_prefix="3059301306072a8648ce3d020106082a8648ce3d030107034200"
declare -A keyfile
jq -r --arg us "${us}" '.keys[] | [.kid, .kty, .crv, .x, .y] | map(tostring) | join($us)' "${jwks}" >"${work}/keys.txt"
while IFS="${us}" read -r kid kty crv x y; do
    if [[ "${kty}" != "EC" || "${crv}" != "P-256" ]]; then
        warn "key ${kid}: not an EC P-256 key (kty=${kty} crv=${crv}), skipped"
        continue
    fi
    xh="$(b64url_to_hex "${x}")"
    yh="$(b64url_to_hex "${y}")"
    if [[ "${#xh}" -ne 64 || "${#yh}" -ne 64 ]]; then
        warn "key ${kid}: x/y are not 32-byte coordinates, skipped"
        continue
    fi
    hex_to_bin "${p256_spki_prefix}04${xh}${yh}" "${work}/key-${kid}.der"
    if openssl pkey -pubin -inform DER -in "${work}/key-${kid}.der" -out "${work}/key-${kid}.pem" 2>/dev/null; then
        keyfile["${kid}"]="${work}/key-${kid}.pem"
        ok "key ${kid}: loaded"
    else
        warn "key ${kid}: openssl could not parse it, skipped"
    fi
done <"${work}/keys.txt"
if [[ "${#keyfile[@]}" -eq 0 ]]; then
    fail "no usable key in ${jwks}"
    exit 1
fi

# verify_sig <what> <kid> <alg> <hex-digest> <base64-signature>
verify_sig() {
    local what="${1}" kid="${2}" alg="${3}" digest="${4}" sig="${5}"
    if [[ "${alg}" != "ES256-DER" ]]; then
        fail "${what}: alg is ${alg}, expected ES256-DER"
        return 0
    fi
    if [[ -z "${keyfile[${kid}]:-}" ]]; then
        fail "${what}: signed with unknown kid ${kid} (not in JWKS)"
        return 0
    fi
    if [[ ! "${digest}" =~ ^[0-9a-f]{64}$ ]]; then
        fail "${what}: digest ${digest} is not a hex SHA-256"
        return 0
    fi
    hex_to_bin "${digest}" "${work}/digest.bin"
    if ! printf '%s' "${sig}" | openssl base64 -d -A >"${work}/sig.der" 2>/dev/null; then
        fail "${what}: signature is not base64"
        return 0
    fi
    if openssl pkeyutl -verify -pubin -inkey "${keyfile[${kid}]}" -in "${work}/digest.bin" \
        -sigfile "${work}/sig.der" >/dev/null 2>&1; then
        ok "${what}: signature verifies under ${kid}"
    else
        fail "${what}: signature does NOT verify under ${kid}"
    fi
    return 0
}

# --- 2. Manifests: linkage and signatures ----------------------------------
declare -A head_at data_hash_at batch_at manifest_at
prev_head=""
prev_seq=""
first=1
# chain_project is the project the first manifest names; every later manifest, checkpoint
# and batch must name the same one. A batch's outer project_id is not under its signature
# (only the chain hash covers the project), so this is the check that catches it being edited.
chain_project=""
partial_from=""
items "${manifests}" | jq -r --arg us "${us}" 'sort_by(.sequence)[] |
    [.sequence, .project_id, .prev_hash, .head_hash, .data_hash, .batch_id, .manifest_id, .kid, .alg, .signature] |
    map(tostring) | join($us)' >"${work}/manifests.txt"
while IFS="${us}" read -r seq project prev head data_hash batch_id manifest_id kid alg sig; do
    # The files are untrusted input: a sequence is used in arithmetic below, so it must be a
    # plain positive decimal before anything evaluates it.
    if [[ ! "${seq}" =~ ^[1-9][0-9]*$ ]]; then
        fail "manifest with sequence ${seq}: sequence must be a positive integer"
        continue
    fi
    what="manifest ${seq}"
    if [[ "${first}" == "1" ]]; then
        first=0
        chain_project="${project}"
        if [[ -z "${chain_project}" ]]; then
            fail "${what}: project_id is empty"
        fi
        if [[ "${seq}" == "1" ]]; then
            if [[ -z "${prev}" ]]; then
                ok "${what}: first link, prev_hash empty"
            else
                fail "${what}: first link must have an empty prev_hash, got ${prev}"
            fi
        elif [[ "${allow_partial}" == "1" ]]; then
            partial_from="${seq}"
            warn "${what}: file starts mid-chain (--allow-partial), its prev_hash (${prev}) is taken on trust and sequences 1-$((seq - 1)) are not verified"
        else
            fail "${what}: file starts mid-chain at sequence ${seq}; sequence 1 is required for full-chain verification (fetch with --all, or pass --allow-partial to verify only from here)"
        fi
    else
        if [[ "${project}" != "${chain_project}" ]]; then
            fail "${what}: project_id ${project} differs from the chain's ${chain_project}"
        fi
        if [[ "${seq}" -ne $((prev_seq + 1)) ]]; then
            fail "${what}: sequence gap, expected $((prev_seq + 1))"
        fi
        if [[ "${prev}" == "${prev_head}" ]]; then
            ok "${what}: prev_hash links to head of ${prev_seq}"
        else
            fail "${what}: prev_hash ${prev} does not match head of ${prev_seq} (${prev_head})"
        fi
    fi
    recomputed="$(sha256_hex "${project}|${seq}|${prev}|${data_hash}|${batch_id}")"
    if [[ "${recomputed}" == "${head}" ]]; then
        ok "${what}: head_hash recomputes"
    else
        fail "${what}: head_hash recomputes to ${recomputed}, manifest records ${head}"
    fi
    verify_sig "${what}" "${kid}" "${alg}" "${head}" "${sig}"
    head_at["${seq}"]="${head}"
    data_hash_at["${seq}"]="${data_hash}"
    batch_at["${seq}"]="${batch_id}"
    manifest_at["${seq}"]="${manifest_id}"
    prev_head="${head}"
    prev_seq="${seq}"
done <"${work}/manifests.txt"
[[ -n "${prev_seq}" ]] || warn "no manifests in ${manifests} (empty chain?)"

# --- 3. Checkpoints: signatures and agreement with the chain ---------------
if [[ -n "${checkpoints}" ]]; then
    items "${checkpoints}" | jq -r --arg us "${us}" '.[] |
        [.checkpoint_id, .project_id, .sequence, .head_hash, .created_at, .kid, .alg, .signature] |
        map(tostring) | join($us)' >"${work}/checkpoints.txt"
    while IFS="${us}" read -r cid project seq head created kid alg sig; do
        if [[ ! "${seq}" =~ ^[1-9][0-9]*$ ]]; then
            fail "checkpoint ${cid}: sequence ${seq} must be a positive integer"
            continue
        fi
        what="checkpoint ${cid} (sequence ${seq})"
        if [[ "${project}" != "${chain_project}" ]]; then
            fail "${what}: project_id ${project} differs from the chain's ${chain_project}"
        fi
        digest="$(sha256_hex "project-checkpoint|${project}|${seq}|${head}|${created}")"
        verify_sig "${what}" "${kid}" "${alg}" "${digest}" "${sig}"
        if [[ -n "${head_at[${seq}]:-}" ]]; then
            if [[ "${head_at[${seq}]}" == "${head}" ]]; then
                ok "${what}: chain head at ${seq} matches"
            else
                fail "${what}: chain head at ${seq} is ${head_at[${seq}]}, checkpoint records ${head}"
            fi
        else
            # A checkpoint that the manifests file does not reach cannot be confirmed, and an
            # unconfirmed checkpoint must not count as a passed truncation check.
            fail "${what}: sequence ${seq} is not in the manifests file, head cannot be cross-checked (fetch the manifests to at least that sequence)"
        fi
    done <"${work}/checkpoints.txt"
fi

# --- 4. Logs: batch hashes, chain position, signatures ---------------------
if [[ -n "${logs}" ]]; then
    items "${logs}" | jq -c '.[]' >"${work}/logs.txt"
    while IFS= read -r entry; do
        IFS="${us}" read -r seq project hash chain_hash batch_id manifest_id kid alg sig < <(
            jq -r --arg us "${us}" '[.sequence, .project_id, .hash, .chain_hash, .batch_id, .manifest_id, .kid, .alg, .signature] |
                map(tostring) | join($us)' <<<"${entry}"
        ) || true
        if [[ ! "${seq}" =~ ^[1-9][0-9]*$ ]]; then
            fail "batch ${batch_id}: sequence ${seq} must be a positive integer"
            continue
        fi
        what="batch ${seq}"
        if [[ "${project}" != "${chain_project}" ]]; then
            fail "${what}: project_id ${project} differs from the chain's ${chain_project}"
        fi
        if [[ -n "${data_hash_at[${seq}]:-}" ]]; then
            if [[ "${hash}" == "${data_hash_at[${seq}]}" ]]; then
                ok "${what}: hash matches manifest data_hash"
            else
                fail "${what}: hash ${hash} differs from manifest data_hash ${data_hash_at[${seq}]}"
            fi
            if [[ "${chain_hash}" == "${head_at[${seq}]}" ]]; then
                ok "${what}: chain_hash matches manifest head_hash"
            else
                fail "${what}: chain_hash ${chain_hash} differs from manifest head_hash ${head_at[${seq}]}"
            fi
            if [[ "${batch_id}" == "${batch_at[${seq}]}" && "${manifest_id}" == "${manifest_at[${seq}]}" ]]; then
                ok "${what}: ids cross-reference the manifest"
            else
                fail "${what}: batch_id/manifest_id do not match manifest ${seq}"
            fi
        else
            # A batch the manifests file does not cover cannot be placed in the chain; the
            # signature check below still runs, but the batch is not a verified one.
            fail "${what}: sequence ${seq} is not in the manifests file, batch cannot be cross-checked (fetch the manifests to at least that sequence)"
        fi
        # The recorded hash covers the exact bytes the platform stored: compact JSON in
        # which the platform's encoder writes <, > and & as <, >, &, and the
        # line/paragraph separators U+2028 / U+2029 as \u2028 / \u2029. jq's compact output
        # is otherwise byte-identical, so both spellings are tried.
        data="$(jq -cj '.data' <<<"${entry}")"
        plain="$(printf '%s' "${data}" | openssl dgst -sha256 -r | cut -d' ' -f1)"
        data="${data//</\\u003c}"
        data="${data//>/\\u003e}"
        data="${data//&/\\u0026}"
        data="${data//$'\xe2\x80\xa8'/\\u2028}"
        data="${data//$'\xe2\x80\xa9'/\\u2029}"
        escaped="$(printf '%s' "${data}" | openssl dgst -sha256 -r | cut -d' ' -f1)"
        if [[ "${plain}" == "${hash}" || "${escaped}" == "${hash}" ]]; then
            ok "${what}: data re-hashes to the recorded hash"
        else
            fail "${what}: data hashes to ${plain} (or ${escaped} HTML-escaped), recorded ${hash} - the events differ from what was signed, or carry a number/escape the re-serialisation changed: compare on the raw response bytes"
        fi
        verify_sig "${what}" "${kid}" "${alg}" "${hash}" "${sig}"
    done <"${work}/logs.txt"
fi

if [[ "${failures}" -eq 0 ]]; then
    if [[ -n "${partial_from}" ]]; then
        printf '\nall checks passed for the partial chain from sequence %s (sequences before it were not verified)\n' "${partial_from}"
    else
        printf '\nall checks passed\n'
    fi
    exit 0
fi
printf '\n%d check(s) FAILED\n' "${failures}"
exit 1

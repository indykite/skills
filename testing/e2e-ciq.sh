#!/usr/bin/env bash
# e2e-ciq.sh - end-to-end smoke test for every skill in the repo.
#
# Three modes, each strictly more thorough than the last:
#
#   ./testing/e2e-ciq.sh
#       Structural only. Runs the checks documented in
#       CONTRIBUTING.md § Validating your skill against every skill:
#       skills-ref validate + loader dry-run + bash -n + jq empty +
#       file hygiene. No env vars required, no network calls.
#
#   ./testing/e2e-ciq.sh --dry-run
#       Above, plus exercises the --print flag on each helper
#       script with a fixture input. Confirms the constructed
#       curl looks well-formed without hitting the live API.
#       Requires the dummy env vars set inside this script - no
#       real credentials needed.
#
#   ./testing/e2e-ciq.sh --live
#       Above, plus a printed checklist for a live walk-through.
#       Requires real env vars (API_URL, API_KEY, …). Nothing is
#       sent - the script prints the steps and commands for you
#       to run yourself.
#
# Run from the repo root.

# SC2312 is an info-level warning about commands inside $(...) / <(...)
# masking their return codes from `set -e`. Our discovery and validation
# patterns deliberately swallow non-zero exit codes (e.g. `grep -c` returns
# 1 when nothing matches and we want that to mean "0 occurrences"). Silence
# the info noise at the file level rather than peppering individual lines.
# shellcheck disable=SC2312

set -euo pipefail

mode="${1:-structural}"
case "${mode}" in
structural | --structural) mode=structural ;;
--dry-run) mode=dry-run ;;
--live) mode=live ;;
-h | --help | help)
    sed -n '2,25p' "${0}"
    exit 0
    ;;
*)
    printf 'unknown mode: %s\n' "${mode}" >&2
    printf 'try: %s --help\n' "${0}" >&2
    exit 2
    ;;
esac

# Discover skills (any directory at repo root with a SKILL.md).
mapfile -t skills < <(for d in */; do
    [[ -f "${d}/SKILL.md" ]] && printf '%s\n' "${d%/}"
done | sort)

if [[ "${#skills[@]}" -eq 0 ]]; then
    printf 'no skills found at repo root - are you in the right directory?\n' >&2
    exit 1
fi

printf 'discovered %d skills: %s\n\n' "${#skills[@]}" "${skills[*]}"

# ---------------------------------------------------------------------------
# Mode 1: structural validation (always runs).
# ---------------------------------------------------------------------------

structural_pass=0
structural_fail=0

for s in "${skills[@]}"; do
    printf '== [%s] structural ==\n' "${s}"
    ok=1

    # 1a. Spec-compliance check (canonical, agentskills.io).
    if command -v skills-ref >/dev/null 2>&1; then
        if ! skills-ref validate "./${s}" >/dev/null 2>&1; then
            printf '  skills-ref validate: FAIL\n'
            ok=0
        else
            printf '  skills-ref validate: ok\n'
        fi
    else
        printf '  skills-ref validate: SKIP (skills-ref not installed; pipx install <agentskills>/skills-ref)\n'
    fi

    # 1b. Loader dry-run (skills.sh ecosystem consumer).
    # Capture exit code AND output. The CLI may emit ANSI colour codes
    # around the number (e.g. "Found \x1b[32m1\x1b[39m skill") in environments
    # that look TTY-ish to it, which would defeat a plain `grep "Found N
    # skill"`. We force colours off via env vars and strip any escape
    # sequences that slip through. On failure, dump the actual output so
    # CI runs are debuggable.
    # NB: capture the exit code with `|| loader_rc=$?` - a bare assignment
    # followed by `loader_rc=$?` would abort the whole run under `set -e`
    # before the FAIL branch ever reports the error.
    loader_rc=0
    loader_raw=$(NO_COLOR=1 FORCE_COLOR=0 \
        npx --yes skills add "./${s}" --list 2>&1) || loader_rc=$?
    loader_out=$(printf '%s\n' "${loader_raw}" | sed 's/\x1b\[[0-9;]*m//g')
    if [[ ${loader_rc} -ne 0 ]]; then
        printf '  loader: FAIL (npx exited %d)\n' "${loader_rc}"
        printf '%s\n' "${loader_out}" | sed 's/^/    /' | head -20 || true
        ok=0
    elif ! grep -qE "Found [0-9]+ skill" <<<"${loader_out}"; then
        printf '  loader: FAIL (no "Found <N> skill" in CLI output)\n'
        printf '%s\n' "${loader_out}" | sed 's/^/    /' | head -20 || true
        ok=0
    else
        printf '  loader: ok\n'
    fi

    # 2. bash -n on scripts (if any).
    if compgen -G "${s}/scripts/*.sh" >/dev/null; then
        if ! bash -n "${s}"/scripts/*.sh 2>/dev/null; then
            printf '  bash -n: FAIL\n'
            ok=0
        else
            printf '  bash -n: ok\n'
        fi
    else
        printf '  bash -n: n/a (no scripts/)\n'
    fi

    # 3. jq empty on JSON assets (if any).
    if compgen -G "${s}/assets/*.json" >/dev/null; then
        if ! jq empty "${s}"/assets/*.json 2>/dev/null; then
            printf '  jq empty: FAIL\n'
            ok=0
        else
            printf '  jq empty: ok\n'
        fi
    else
        printf '  jq empty: n/a (no JSON assets)\n'
    fi

    # 4. File hygiene: UTF-8, LF, no BOM.
    bom=$(head -c 3 "${s}/SKILL.md" | od -An -tx1 | tr -d ' ')
    crlf=$(grep -c $'\r' "${s}/SKILL.md" || true)
    if [[ "${bom}" == "efbbbf" ]]; then
        printf '  file hygiene: FAIL (UTF-8 BOM present)\n'
        ok=0
    elif [[ "${crlf}" -gt 0 ]]; then
        printf '  file hygiene: FAIL (CRLF lines)\n'
        ok=0
    else
        printf '  file hygiene: ok\n'
    fi

    if [[ "${ok}" == "1" ]]; then
        structural_pass=$((structural_pass + 1))
    else
        structural_fail=$((structural_fail + 1))
    fi
    printf '\n'
done

printf 'structural summary: %d passed, %d failed (of %d)\n\n' \
    "${structural_pass}" "${structural_fail}" "${#skills[@]}"

if [[ "${mode}" == "structural" ]]; then
    [[ "${structural_fail}" == "0" ]] || exit 1
    exit 0
fi

# ---------------------------------------------------------------------------
# Mode 2: dry-run - exercise --print on every helper script.
# ---------------------------------------------------------------------------

if [[ "${mode}" == "dry-run" ]] || [[ "${mode}" == "live" ]]; then
    printf '== --print smoke test ==\n\n'

    if [[ "${mode}" == "live" ]]; then
        # Live mode runs against caller-supplied values - validate them
        # BEFORE the dummy exports below could mask a missing one, and
        # keep them so the live checklist prints the real API_URL.
        : "${API_URL:?set API_URL (e.g. https://us.api.indykite.com)}"
        : "${API_KEY:?set API_KEY (AppAgent credential)}"
        export API_URL API_KEY
    else
        # Dummy env so --print can construct the request (kept
        # unconditional so dry-run output is deterministic in CI).
        export API_URL="https://us.api.indykite.com"
        export API_KEY="DUMMY_AGENT_TOKEN"
    fi
    export QUERY_ID="dummy-kq-gid"
    export BEARER_TOKEN="DUMMY_USER_TOKEN"
    export MCP_URL="https://us.mcp.indykite.com"
    export PROJECT_GID="DUMMY_PROJECT_GID"

    # One fixture per skill that ships an execute.sh.
    # NB: array keys MUST be quoted so shfmt does not reformat the hyphens
    # as arithmetic operators (which silently collapses every key to 0 and
    # makes only the last fixture survive).
    declare -A fixtures
    fixtures["indykite-ciq-read"]='{"person_external_id":"alice"}'
    fixtures["indykite-ciq-create-node"]='{"track_external_id":"track-99","track_title":"X","track_loudness":-7.5}'
    fixtures["indykite-ciq-create-relationship"]='{"track_external_id":"track-99","venue_external_id":"venue-1"}'
    fixtures["indykite-ciq-add-property"]='{"new_music_mood":"Acoustic Sadness","new_dance_skill":0.67}'
    fixtures["indykite-ciq-add-relationship-property"]='{"track_external_id":"track-99","venue_external_id":"venue-1","first_played_at":"2026-04-22T19:00:00Z"}'
    fixtures["indykite-ciq-delete"]='{}'
    fixtures["indykite-ciq-create-node-with-link"]='{"vehicleID":"car2","personID":"ryan","contract_external_id":"ct853","contractNumber":"rbjh853"}'

    dry_pass=0
    dry_fail=0

    for s in "${!fixtures[@]}"; do
        helper="${s}/scripts/execute.sh"
        if [[ ! -r "${helper}" ]]; then
            printf '  [%s] SKIP (missing or unreadable execute.sh)\n' "${s}"
            continue
        fi
        printed="$(printf '%s' "${fixtures[${s}]}" | bash "${helper}" --print - 2>/dev/null || true)"
        if [[ "${printed}" == curl\ * ]] && [[ "${printed}" == *"${API_URL}"* ]] && [[ "${printed}" == *"contx-iq/v1/execute"* ]]; then
            printf '  [%s] --print: ok\n' "${s}"
            dry_pass=$((dry_pass + 1))
        else
            printf '  [%s] --print: FAIL\n    output: %s\n' "${s}" "${printed}"
            dry_fail=$((dry_fail + 1))
        fi
    done

    # MCP init-session.sh (different shape).
    if [[ -r "indykite-mcp-server/scripts/init-session.sh" ]]; then
        printed="$(bash indykite-mcp-server/scripts/init-session.sh --print 2>/dev/null || true)"
        if [[ "${printed}" == curl\ * ]] && [[ "${printed}" == *"${MCP_URL}"* ]] && [[ "${printed}" == *"${PROJECT_GID}"* ]]; then
            printf '  [indykite-mcp-server/init-session.sh] --print: ok\n'
            dry_pass=$((dry_pass + 1))
        else
            printf '  [indykite-mcp-server/init-session.sh] --print: FAIL\n    output: %s\n' "${printed}"
            dry_fail=$((dry_fail + 1))
        fi
    fi

    # AuthZEN evaluate.sh - /access/v1/evaluation endpoint.
    if [[ -r "indykite-authzen-evaluation/scripts/evaluate.sh" ]] &&
        [[ -r "indykite-authzen-evaluation/assets/evaluation-provision-server.json" ]]; then
        printed="$(bash indykite-authzen-evaluation/scripts/evaluate.sh --print indykite-authzen-evaluation/assets/evaluation-provision-server.json 2>/dev/null || true)"
        if [[ "${printed}" == curl\ * ]] && [[ "${printed}" == *"${API_URL}"* ]] && [[ "${printed}" == *"access/v1/evaluation"* ]]; then
            printf '  [indykite-authzen-evaluation/evaluate.sh] --print: ok\n'
            dry_pass=$((dry_pass + 1))
        else
            printf '  [indykite-authzen-evaluation/evaluate.sh] --print: FAIL\n    output: %s\n' "${printed}"
            dry_fail=$((dry_fail + 1))
        fi
    fi

    # Capture API capture.sh helpers - each prints a curl command for its skill's example asset.
    for s in indykite-capture-upsert-nodes indykite-capture-upsert-relationships \
        indykite-capture-delete-nodes indykite-capture-delete-node-properties \
        indykite-capture-delete-node-property-metadata indykite-capture-delete-relationships \
        indykite-capture-delete-relationship-properties; do
        helper="${s}/scripts/capture.sh"
        if [[ ! -r "${helper}" ]]; then
            printf '  [%s] SKIP (missing or unreadable capture.sh)\n' "${s}"
            continue
        fi
        asset="$(compgen -G "${s}/assets/*.json" | head -1 || true)"
        [[ -n "${asset}" ]] || {
            printf '  [%s] SKIP (no assets/*.json)\n' "${s}"
            continue
        }
        printed="$(bash "${helper}" --print "${asset}" 2>/dev/null || true)"
        if [[ "${printed}" == curl\ * ]] && [[ "${printed}" == *"${API_URL}"* ]] && [[ "${printed}" == *"capture/v1/"* ]]; then
            printf '  [%s/capture.sh] --print: ok\n' "${s}"
            dry_pass=$((dry_pass + 1))
        else
            printf '  [%s/capture.sh] --print: FAIL\n    output: %s\n' "${s}" "${printed}"
            dry_fail=$((dry_fail + 1))
        fi
    done

    printf '\ndry-run summary: %d passed, %d failed\n\n' "${dry_pass}" "${dry_fail}"

    [[ "${mode}" == "dry-run" ]] && {
        # Gate on BOTH phases - a structural failure must fail the run even
        # when every smoke test passes.
        [[ "${structural_fail}" == "0" ]] || exit 1
        [[ "${dry_fail}" == "0" ]] || exit 1
        exit 0
    }
fi

# ---------------------------------------------------------------------------
# Mode 3: live - guided walk-through (interactive, prints first).
# ---------------------------------------------------------------------------

if [[ "${mode}" == "live" ]]; then
    printf '== --live mode ==\n\n'

    # API_URL / API_KEY were validated as caller-supplied at the start of
    # the smoke-test phase, before any dummy values could mask them.

    printf 'live mode prints a checklist - it sends nothing itself. Run the\n'
    printf 'printed commands yourself once you have reviewed each one.\n\n'

    printf 'Step 1: confirm the API_URL and API_KEY are valid.\n'
    printf '  Sample probe: GET %s/configs/v1/projects (replace with real path)\n' "${API_URL}"
    printf 'Step 2: pick one CIQ skill to exercise (e.g. indykite-ciq-read).\n'
    printf '  Then create the policy + KQ via Config API using its assets/*.json.\n'
    printf '  Capture the returned policy_id and query_id.\n'
    printf 'Step 3: set QUERY_ID, BEARER_TOKEN (if needed), and run:\n'
    printf '    QUERY_ID=<gid> BEARER_TOKEN=<token> ./<skill>/scripts/execute.sh \\\n'
    printf '      <(echo %s) | jq\n' "'"'{"...":"..."}'"'"
    printf '\nFor a documented full sequence, see testing/README.md.\n'
    exit 0
fi

# Testing the skills

This guide covers two distinct activities: **structural validation** (does the skill conform to the [Agent Skills specification](https://agentskills.io/specification)?) and **live verification** (does the skill actually do what it claims against a real IndyKite project?). They have different prerequisites and different value.

For *authoring*-time guidance — the rules every skill must satisfy — see [`CONTRIBUTING.md`](../CONTRIBUTING.md). This document is for *exercising* skills end-to-end.

## Structural validation

No env vars, no network calls. Run from the repo root:

```bash
./testing/e2e-ciq.sh
```

Discovers every skill in the repo and runs the checks documented in [`CONTRIBUTING.md` § Validating your skill](../CONTRIBUTING.md#validating-your-skill) against each: **`skills-ref validate`** (the canonical [Agent Skills specification](https://agentskills.io/specification) checker — install once with `pipx install <agentskills-repo>/skills-ref`), loader dry-run via the `skills` CLI, `bash -n` on scripts, `jq empty` on JSON assets, and file hygiene (UTF-8 / LF / no BOM). Prints a per-skill summary and an overall pass/fail count. Exits non-zero if any skill fails any check.

If `skills-ref` is not installed, the harness still runs the loader + script + asset + hygiene checks; the spec check is reported as `SKIP`.

This is what you should run before opening a PR. It catches both spec violations (`skills-ref`) and loader-discovery issues (`npx skills`).

## Dry-run smoke test

Includes structural validation, plus exercises the `--print` flag on every helper script with a fixture input:

```bash
./testing/e2e-ciq.sh --dry-run
```

This confirms each helper script — the CIQ `execute.sh` scripts, the MCP `init-session.sh`, the AuthZEN `evaluate.sh`, and the Capture `capture.sh` helpers — constructs a well-formed `curl` command, without sending it. Useful for verifying the script logic in isolation. Exits non-zero if any structural check or any smoke test fails.

The `--print` flag is also available on every helper directly:

```bash
echo '{"person_external_id":"alice"}' | \
  API_URL="https://us.api.indykite.com" \
  API_KEY="<agent-token>" \
  QUERY_ID="<kq-gid>" \
  BEARER_TOKEN="<user-token>" \
  ./indykite-ciq-read/scripts/execute.sh --print -
```

Output is a paste-runnable `curl` invocation with everything shell-quoted. Drop `--print` to actually send it.

## Live verification

Requires a real IndyKite project, real credentials, and seeded test data. The script's `--live` mode is a guided walk-through:

```bash
./testing/e2e-ciq.sh --live
```

It prints each step and what to set, but does not auto-execute live API calls — token shapes vary too much across projects to safely automate. Use it as a runbook.

### Where each token comes from

| Env var                  | What it is                                                              | How to obtain                                                                                                          |
|--------------------------|-------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------|
| `API_URL`                | Regional REST API base                                                   | `https://eu.api.indykite.com` or `https://us.api.indykite.com`                                                          |
| `API_KEY`                | AppAgent credentials token (goes into `X-IK-ClientKey`)                  | `POST /configs/v1/application-agent-credentials` against the Config API. See the [Credentials guide](https://developer.indykite.com/guides/guide-credentials). The Hub UI ([eu.hub.indykite.com](https://eu.hub.indykite.com/) / [us.hub.indykite.com](https://us.hub.indykite.com/)) can mint these too. |
| `BEARER_TOKEN`           | User OAuth access token (goes into `Authorization: Bearer …`)            | Issued by your project's IdP. The token's `sub` claim must match a seeded `Person` `external_id`. The music-dataset tutorial uses Auth0 with seeded users `cornelius` / `marmaduke` / `rebecca` — see [Chapter 5 of the music-dataset tutorial](https://developer.indykite.com/tutorials/tutorial-music-dataset). |
| `SERVICE_ACCOUNT_TOKEN`  | Token with Config API write access (goes into `Authorization: Bearer …` for policy / KQ creation) | Issued through the Hub UI under the project's service accounts. Required only for *creating* policies and Knowledge Queries; not for executing them. |
| `MCP_URL`                | Regional MCP server base                                                 | `https://eu.mcp.indykite.com` or `https://us.mcp.indykite.com`                                                          |
| `PROJECT_GID`            | Project identifier                                                       | Visible in the Hub UI on the project settings page; appears in the URL path of REST calls.                              |
| `QUERY_ID`               | Knowledge Query GID or name                                               | Returned by `POST /configs/v1/knowledge-queries` when you create one. Each skill's `assets/*.json` is the body of that POST. |

### Canonical test environment

The IndyKite developer hub ships a [music-dataset tutorial](https://developer.indykite.com/tutorials/tutorial-music-dataset) that walks through provisioning a project end-to-end and seeding ~16k nodes / ~31k relationships. It includes:

- A Postman collection that creates the Application, AppAgent, AppAgent credentials, Token Introspect, and seeds the graph.
- Pre-defined test users (`cornelius`, `marmaduke`, `rebecca`) with Auth0 tokens you can mint for `BEARER_TOKEN`.
- Pre-built CIQ policies and Knowledge Queries for read / write / delete variants.

If you want a known-good environment to exercise this repo's skills against, replay that collection first. The skill assets in this repo are designed to be drop-in compatible with the music-dataset graph (`Track`, `Venue`, `Person` labels) — load a skill's JSON into the existing collection and the read/write paths will work immediately.

### Sample end-to-end sequence

Once `API_URL`, `API_KEY`, and `BEARER_TOKEN` are set against a populated project, you can exercise the CIQ family in a single sequence using the same `external_id` throughout. The flow assumes you've already created each operation's policy and Knowledge Query (see each skill's Steps section); this snippet just executes them.

```bash
# Set per-step
export API_URL="https://us.api.indykite.com"
export API_KEY="<your AppAgent token>"
export BEARER_TOKEN="<your user token, e.g. cornelius's>"

# 1. Read own profile (cornelius's)
QUERY_ID="<read-kq-gid>" \
  ./indykite-ciq-read/scripts/execute.sh <(echo '{}') | jq .

# 2. Update a property
QUERY_ID="<add-property-kq-gid>" \
  ./indykite-ciq-add-property/scripts/execute.sh \
    <(echo '{"new_music_mood":"Acoustic Sadness","new_dance_skill":0.67}') | jq .

# 3. Read again — confirm the property changed
QUERY_ID="<read-kq-gid>" \
  ./indykite-ciq-read/scripts/execute.sh <(echo '{}') | jq .

# 4. Delete the property
QUERY_ID="<delete-kq-gid>" \
  ./indykite-ciq-delete/scripts/execute.sh <(echo '{}') | jq .

# 5. Read once more — confirm it's gone
QUERY_ID="<read-kq-gid>" \
  ./indykite-ciq-read/scripts/execute.sh <(echo '{}') | jq .
```

Every helper supports `--print` instead of executing — useful for checking the request shape before making real calls.

## Caveats

- **Loader dry-run validates structure only.** It parses YAML and walks the directory but does not exercise the live API. A skill can pass structural validation and still fail at runtime because of a misconfigured project, missing seed data, or the wrong subject type.
- **Bearer tokens are short-lived.** If a live test fails with `401`, refresh the token before assuming the skill is broken.
- **`_Application` flows don't need a Bearer.** Don't pass one. The reserved `$_appId` is auto-filled from the AppAgent.
- **Re-running write operations is upsert, not error.** A second create with the same `external_id` overwrites; a second delete on already-missing data returns `200` with empty `data`. Test for the *effect*, not for a specific HTTP response.
- **Cleanup is your responsibility.** This guide doesn't auto-tear-down test data. To delete a policy or Knowledge Query, use the Config API (`DELETE /configs/v1/authorization-policies/<gid>`, etc.).

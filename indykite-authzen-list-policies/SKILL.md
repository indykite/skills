---
name: indykite-authzen-list-policies
description: List the ACTIVE KBAC authorization policies of the calling application agent's project at runtime via the IndyKite AuthZEN REST API (`GET /access/v1/policies`) - each policy returned as stored (inlined JSON object) with its tags, optionally narrowed with `?subject_type=`. Needs the `ReadAuthZConfigs` API permission on the AppAgent; no Service Account token, no user token. Use to show which rules currently apply, discover the actions / resource types / tags that exist for a subject type before asking for decisions, or pick `context.policy_tags` - "which policies apply to Person right now?", "what actions exist for Server?", "why 401 on /access/v1/policies?". Not for making decisions (indykite-authzen-evaluation / -evaluations), enumerating allowed actions / resources / subjects for a specific subject (indykite-authzen-search-*), or creating / updating / deleting policies (indykite-authzen-kbac-policies, Config API). Never lists ContX IQ policies.
license: Apache-2.0
compatibility: Requires curl, bash 4+, and jq. Network access to the regional IndyKite REST API (eu.api.indykite.com or us.api.indykite.com) is required at runtime.
---

# IndyKite AuthZEN - list the project's active KBAC policies

`GET /access/v1/policies` lets an **application agent** read the ACTIVE KBAC (Knowledge-Based Access Control) policies of its own project at runtime. Each policy comes back exactly as it was stored through the Config API, inlined as a JSON object, together with its `tags`. It is a **read-only runtime view** of the rules the decision endpoints evaluate: no Service Account credentials, no policy IDs, no lifecycle operations.

It sits next to the other runtime AuthZEN endpoints under `/access/v1`, but answers a different question:

| Question                                              | Endpoint                     | Skill                                                                  |
|-------------------------------------------------------|------------------------------|-----------------------------------------------------------------------|
| Which **rules** apply in this project right now?      | `GET /policies`              | this skill                                                            |
| Can X do Y on Z? (one / many)                         | `POST /evaluation(s)`        | [`indykite-authzen-evaluation`](../indykite-authzen-evaluation/SKILL.md) / [`-evaluations`](../indykite-authzen-evaluations/SKILL.md) |
| Which actions / resources / subjects are allowed?     | `POST /search/*`             | [`indykite-authzen-search-action`](../indykite-authzen-search-action/SKILL.md) / [`-resource`](../indykite-authzen-search-resource/SKILL.md) / [`-subject`](../indykite-authzen-search-subject/SKILL.md) |
| Create, update, publish, or delete a policy           | Config API                   | [`indykite-authzen-kbac-policies`](../indykite-authzen-kbac-policies/SKILL.md) |

## When to use

Activate this skill when the user wants to:

- see **which KBAC policies are active** in the project, from an application (not an admin) credential - "which rules apply to `Person` right now?";
- **discover the vocabulary** a subject type can be asked about - the `actions` and `resource.type` values present in policies for `Person` - before building evaluation or search requests, e.g. for an AI agent that must not guess action names;
- pick the **`policy_tags`** to send under `context` on an evaluation, from the tags that actually exist;
- debug a **`401` on `/access/v1/policies`** - almost always the missing `ReadAuthZConfigs` API permission.

Do **not** activate this skill when the user wants to:

- **make a decision** - [`indykite-authzen-evaluation`](../indykite-authzen-evaluation/SKILL.md) / [`indykite-authzen-evaluations`](../indykite-authzen-evaluations/SKILL.md);
- **enumerate what a specific subject may do** (actions, resources, subjects under current graph state) - the [`indykite-authzen-search-*`](../README.md) skills; this listing shows the rules, not their outcome for a given node;
- **author, update, activate, or delete** a policy, or needs policy IDs, names, ETags, `INACTIVE` / `DRAFT` policies, or CIQ policies - [`indykite-authzen-kbac-policies`](../indykite-authzen-kbac-policies/SKILL.md) (Config API, Service Account token);
- read the **graph schema** rather than the policies - [`indykite-data-schema`](../indykite-data-schema/SKILL.md).

## Prerequisites

- An IndyKite **project** with an **AppAgent** and AppAgent **credentials** (the token that goes into `X-IK-ClientKey`) - see the [Credentials guide](https://developer.indykite.com/guides/guide-credentials).
- The AppAgent holds the **`ReadAuthZConfigs` API permission**. It is a separate permission from `Authorization` and is **not** granted to existing agents automatically: add it to the agent's `api_permissions` (`POST` / `PUT /configs/v1/application-agents`, Service Account token, or the Hub UI). The full permission-to-endpoint map is in the [Environment guide](https://developer.indykite.com/guides/guide-environment).
- At least one **ACTIVE KBAC policy** in the project - otherwise the listing is an empty `results` array, which is a normal `200`.

If a prerequisite is missing, say so - an empty listing looks the same whether no policy exists or the wrong project's credential was used.

## Steps

### 1. Call the endpoint

```text
GET <API_URL>/access/v1/policies
GET <API_URL>/access/v1/policies?subject_type=Person
```

where `API_URL` is `https://eu.api.indykite.com` or `https://us.api.indykite.com`, matching the project's region. Authentication is the AppAgent credential in the `X-IK-ClientKey` header, as is, without any prefix. No request body, no user token - the project is derived from the credential.

The only parameter is the optional query `subject_type`: keep only the policies whose `subject.type` equals this node type (a valid node label such as `Person` or `_Application`, 2-64 characters, case-sensitive). Omit it to get every policy. A subject type no policy uses is not an error - it returns `{"results": []}`.

A runnable shell helper builds the authenticated request: [`scripts/list-policies.sh`](scripts/list-policies.sh) - pass the subject type as the optional argument, run with `--print` to preview the `curl` (host-pinned; token redacted).

### 2. Read the response

```json
{
  "results": [
    {
      "policy": {
        "meta": { "policy_version": "2.0-kbac" },
        "subject": { "type": "Person" },
        "actions": ["CAN_DRIVE"],
        "resource": { "type": "Car" },
        "condition": { "cypher": "MATCH (subject:Person)-[:DRIVES]->(resource:Car)" }
      },
      "tags": []
    },
    {
      "policy": {
        "meta": { "policy_version": "2.0-kbac" },
        "subject": { "type": "_Application" },
        "actions": ["CAN_READ"],
        "resource": { "type": "Car" },
        "condition": { "cypher": "MATCH (subject) MATCH (resource:Car)" }
      },
      "tags": ["fleet"]
    }
  ]
}
```

- `results[]` - one entry per policy; empty when nothing matches.
- `results[].policy` - the policy definition **as stored**: the `policy` string given to `POST /configs/v1/authorization-policies`, parsed back into an object (no escaping to undo). Its shape follows `meta.policy_version` - `meta`, `subject`, `actions`, `resource`, `condition` (with `cypher` and an optional `filter`) appear exactly as authored.
- `results[].tags` - the policy's tags, the values matched by `context.policy_tags` on evaluation. Always an array, `[]` when the policy has none.

What is (and is not) listed:

- KBAC policies (`2.0-kbac` and `3.0-kbac`) with status **ACTIVE** only - the same set the decision endpoints evaluate.
- Only the **calling agent's project**; there is no project parameter.
- **No** ContX IQ (`1.0-ciq`) policies, **no** policy `id` / `name` / timestamps / ETag - those live on the Config API.

The full field reference, error table, and `jq` recipes are in [`references/list-policies-reference.md`](references/list-policies-reference.md).

### 3. Use what it tells you

- **Build requests from real values.** Take `actions[]`, `resource.type`, and `subject.type` verbatim into [`indykite-authzen-evaluation`](../indykite-authzen-evaluation/SKILL.md) / search requests instead of guessing action names.
- **Choose `policy_tags` from `tags`.** Only tags that appear here can select anything on an evaluation.
- **Spot required `input_params`.** A `$name` inside `condition.cypher` is a partial parameter the decision call must supply under `context.input_params`.
- **Don't mistake it for a decision.** A policy being listed says nothing about whether a given subject passes its condition - ask the evaluation or search endpoints for that.

## Outcome

When this skill has been applied successfully:

- `GET /access/v1/policies` (optionally with `?subject_type=`) returns a `results` array of the project's ACTIVE KBAC policies, each with its stored `policy` object and `tags`, or an empty array when none match.
- The AppAgent used holds `ReadAuthZConfigs`, and downstream evaluation / search requests use action names, resource types, subject types, and tags taken from the listing.

## Files in this skill

- [`references/list-policies-reference.md`](references/list-policies-reference.md) - endpoint, auth and permission, query parameter, response fields, error codes, troubleshooting, and `jq` recipes.
- [`scripts/list-policies.sh`](scripts/list-policies.sh) - Bash helper that GETs `/access/v1/policies` with the right header and an optional `subject_type` (host-pinned; `--print` to preview).

## Agent-specific notes

This skill uses generic markdown instructions and works across all agents listed in the [README](../README.md). The agent needs to be able to issue HTTP requests (`curl` or an HTTP client). No Claude Code hooks, Cursor `@`-mentions, or Copilot workspace context are required.

## References

- [AuthZEN guide (developer hub)](https://developer.indykite.com/guides/guide-authzen) - "How do I read the policies behind the decisions?"
- [Environment guide (developer hub)](https://developer.indykite.com/guides/guide-environment) - Application Agent API permissions
- [IndyKite REST API documentation (Authorization API)](https://openapi.indykite.com/api-documentation)
- [Credentials guide](https://developer.indykite.com/guides/guide-credentials)

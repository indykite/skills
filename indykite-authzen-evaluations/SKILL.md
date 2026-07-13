---
name: indykite-authzen-evaluations
description: Run many KBAC authorization decisions in one call via the IndyKite AuthZEN REST API (`POST /access/v1/evaluations`), with top-level subject/action/resource/context as defaults overridden per entry; returns one `decision` per entry, in order. Use when checking a known, fixed set of checks at once - one subject against many resources, one action across many subjects, or any mix of triples - e.g. "of these servers, which can grace provision?", "for each of these users, can they deploy gpu-node-7?". For a single check use indykite-authzen-evaluation; to enumerate ALL allowed actions/resources/subjects (open-ended, not a fixed list) use indykite-authzen-search-action / -search-resource / -search-subject; to author the policy use indykite-authzen-kbac-policies.
license: Apache-2.0
compatibility: Requires curl, bash 4+, and jq. Network access to the regional IndyKite REST API (eu.api.indykite.com or us.api.indykite.com) is required at runtime.
---

# IndyKite AuthZEN - batch evaluations

Batch evaluation makes **many KBAC decisions in one request**. You supply top-level `subject` / `action` / `resource` / `context` as **defaults** and an `evaluations[]` array where each entry overrides only the parts it specifies; the response carries one boolean `decision` per entry, in order.

This skill covers building and sending the batch request and reading the results. It does **not** author policies - the `2.0-kbac` policies every entry is evaluated against are authored with [`indykite-authzen-kbac-policies`](../indykite-authzen-kbac-policies/SKILL.md).

## When to use

Activate this skill when the user wants to:

- check **one subject against many resources** (e.g. "of these 20 servers, which can `grace` `PROVISION`?");
- check **one action across many subjects** (e.g. "which of these people can deploy `gpu-node-7`?");
- evaluate a **heterogeneous mix** of `(subject, action, resource)` triples in a single call.

Do **not** activate this skill to make a **single** yes/no decision ([`indykite-authzen-evaluation`](../indykite-authzen-evaluation/SKILL.md)), to enumerate **all** instances for one probe (the search skills [`indykite-authzen-search-action`](../indykite-authzen-search-action/SKILL.md) / [`-search-resource`](../indykite-authzen-search-resource/SKILL.md) / [`-search-subject`](../indykite-authzen-search-subject/SKILL.md)), or to **author a policy** or **read/write graph data** (batch evaluation only renders decisions).

## Prerequisites

- One or more **ACTIVE KBAC policies** covering the triples in the batch. If none exist, author them first with [`indykite-authzen-kbac-policies`](../indykite-authzen-kbac-policies/SKILL.md).
- An **AppAgent** and its **credentials token** (the `X-IK-ClientKey` value).
- The **IKG populated** with the subject and resource nodes (and any relationships the conditions match).
- Every **partial parameter** the matched policies reference, ready to pass under `context.input_params`.

## Steps

### 1. Choose defaults, then vary per entry

Decide which parts are constant across the batch (put them at the top level) and which vary (put them in each `evaluations[]` entry). An entry inherits every top-level part it does not override.

> Running example: one action (`PROVISION`) and one resource (`gpu-node-7`) are the defaults; the **subject** varies per entry, and one entry also overrides the resource.

### 2. Build the batch request body

```json
{
  "action":   { "name": "PROVISION" },
  "resource": { "type": "Server", "id": "gpu-node-7" },
  "evaluations": [
    { "subject": { "type": "Person", "id": "linus" } },
    { "subject": { "type": "Person", "id": "grace" } },
    { "subject": { "type": "Person", "id": "grace" }, "resource": { "type": "Server", "id": "edge-box-2" } },
    { "subject": { "type": "Person", "id": "dennis" } }
  ],
  "context": { "input_params": { "max_price": 80000 } }
}
```

`subject.id` / `resource.id` are node `external_id`s; `action.name` is case-sensitive; `context.input_params` keys are written **without** the `$` and keep their types. A ready body: [`assets/evaluations-provision-servers.json`](assets/evaluations-provision-servers.json).

### 3. Send the batch

```text
POST <API_URL>/access/v1/evaluations
```

Authentication:

- **Always**: `X-IK-ClientKey: <AppAgent-credentials-token>`.
- **Optional**: `Authorization: Bearer <user-access-token>` - applies only in some cases (e.g. a condition references a token claim/scope), where it can flip claim-gated entries.

A runnable shell helper: [`scripts/evaluate-batch.sh`](scripts/evaluate-batch.sh) — run with `--print` to preview the `curl` (host-pinned; tokens redacted).

### 4. Read the decisions - one per entry, in order

```json
{
  "evaluations": [
    { "decision": false },
    { "decision": true },
    { "decision": false },
    { "decision": true }
  ]
}
```

The array is positional: `evaluations[i]` is the decision for request entry `i`.

### 5. Watch the missing-parameter difference

A **single** `/evaluation` that omits a required partial parameter returns **`422`**. A **batch** call does **not** fail wholesale - it returns `200`, and each entry whose matched policy needed the missing parameter comes back as `decision: false` with a `context.reason`:

```json
{ "decision": false, "context": { "reason": "invalid_argument: missing or wrong input params, 'max_price'" } }
```

So always distinguish a genuine deny (`decision: false`, no `context`) from a missing-input deny (`decision: false` **with** `context.reason`) before concluding access is denied.

## Outcome

When this skill has been applied successfully:

- `POST /access/v1/evaluations` returns an `evaluations[]` array with one `decision` per request entry, in order, with top-level parts correctly applied as defaults.
- Missing-parameter entries are read as `decision: false` + `context.reason` (a `200`), not mistaken for a request failure.
- Each batch decision matches what the single-decision skill ([`indykite-authzen-evaluation`](../indykite-authzen-evaluation/SKILL.md)) would return for the same triple.

## Files in this skill

- [`references/evaluations-reference.md`](references/evaluations-reference.md) - `/evaluations`: request/response shapes, defaults-and-override semantics, the missing-parameter behaviour, error codes.
- [`assets/evaluations-provision-servers.json`](assets/evaluations-provision-servers.json) - runnable batch request body for the `PROVISION` example.
- [`scripts/evaluate-batch.sh`](scripts/evaluate-batch.sh) - Bash helper that posts a batch request to `/access/v1/evaluations` (host-pinned; `--print` to preview).

## Agent-specific notes

This skill uses generic markdown instructions and works across all agents listed in the [README](../README.md). The agent needs to be able to issue HTTP requests (`curl`, an HTTP client, or the IndyKite Terraform provider). No Claude Code hooks, Cursor `@`-mentions, or Copilot workspace context are required.

## References

- [AuthZEN guide (developer hub)](https://developer.indykite.com/guides/guide-authzen)
- [Config API documentation - authorization policies](https://openapi.indykite.com/api-documentation-config#tag/authorization-policies)
- [Credentials guide](https://developer.indykite.com/guides/guide-credentials)

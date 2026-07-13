---
name: indykite-authzen-evaluation
description: Make a single KBAC authorization decision via the IndyKite AuthZEN REST API (`POST /access/v1/evaluation`) - returns a boolean `decision` for one (subject, action, resource) triple, optionally with per-request `context.input_params`. Use for a single yes/no question - "can ada PROVISION gpu-node-7?", "is this user allowed to delete this document?", "gate this operation on a live check", or debugging why one decision is false. Not for many checks at once (use indykite-authzen-evaluations), not for enumerating which actions/resources/subjects are allowed (use indykite-authzen-search-action / -search-resource / -search-subject), and not for authoring the policy behind the decision (use indykite-authzen-kbac-policies). For the same decision over MCP/JSON-RPC see indykite-mcp-server (`authzen_evaluate`).
license: Apache-2.0
compatibility: Requires curl, bash 4+, and jq. Network access to the regional IndyKite REST API (eu.api.indykite.com or us.api.indykite.com) is required at runtime.
---

# IndyKite AuthZEN - single authorization decision

A KBAC decision asks the AuthZEN endpoint one question - *may this subject perform this action on this resource?* - and gets back a boolean `decision`. The decision is rendered by evaluating the project's currently ACTIVE `2.0-kbac` policies against the IKG.

This skill covers making that **single** decision: framing the `(subject, action, resource, context)` request, sending it, and reading the boolean. It does **not** author policies - the policy whose `subject` / `actions` / `resource` / `condition.cypher` the decision is evaluated against is authored with [`indykite-authzen-kbac-policies`](../indykite-authzen-kbac-policies/SKILL.md).

It is the single-call member of the AuthZEN family:

| Need                                            | Endpoint                     | Skill                                                                  |
|-------------------------------------------------|------------------------------|-----------------------------------------------------------------------|
| **One** yes/no decision                         | `/access/v1/evaluation`      | this skill                                                            |
| Many decisions at once                          | `/access/v1/evaluations`     | [`indykite-authzen-evaluations`](../indykite-authzen-evaluations/SKILL.md) |
| Actions a subject may perform on a resource     | `/access/v1/search/action`   | [`indykite-authzen-search-action`](../indykite-authzen-search-action/SKILL.md) |
| Resources a subject may act on, given an action | `/access/v1/search/resource` | [`indykite-authzen-search-resource`](../indykite-authzen-search-resource/SKILL.md) |
| Subjects allowed an action on a resource        | `/access/v1/search/subject`  | [`indykite-authzen-search-subject`](../indykite-authzen-search-subject/SKILL.md) |
| Author / manage the KBAC policy                 | Config API                   | [`indykite-authzen-kbac-policies`](../indykite-authzen-kbac-policies/SKILL.md)          |

## When to use

Activate this skill when the user wants to:

- decide whether **one subject may perform one action on one resource** (e.g. "can `ada` `PROVISION` the server `gpu-node-7` within a budget of 120000?");
- gate an operation in an application on a live authorization check;
- debug why a single decision comes back `true` or `false`.

Do **not** activate this skill to **author or modify** the policy behind the decision ([`indykite-authzen-kbac-policies`](../indykite-authzen-kbac-policies/SKILL.md)), to make **many** decisions in one call ([`indykite-authzen-evaluations`](../indykite-authzen-evaluations/SKILL.md)), to **enumerate** the allowed actions/resources/subjects rather than test one triple (the search skills [`-search-action`](../indykite-authzen-search-action/SKILL.md) / [`-search-resource`](../indykite-authzen-search-resource/SKILL.md) / [`-search-subject`](../indykite-authzen-search-subject/SKILL.md)), or to **return or modify graph data** (a decision is yes/no, not a data read or write).

## Prerequisites

- One or more **ACTIVE KBAC policies** whose `subject.type` / `actions` / `resource.type` cover the triple. If none exist, author them first with [`indykite-authzen-kbac-policies`](../indykite-authzen-kbac-policies/SKILL.md); a decision with no matching policy is simply `false`.
- An **AppAgent** with credentials configured for the calling application ([Credentials guide](https://developer.indykite.com/guides/guide-credentials)).
- The **IKG populated** with the subject and resource nodes (and any relationships the condition matches). Evaluation reads the graph; it does not seed it.
- Every **partial parameter** the matched policy references, ready to pass under `context.input_params`.

If a prerequisite is missing, say so - fixing it first is far cheaper than debugging an opaque `false` decision.

## Steps

### 1. Frame the triple and its context

Pin the three parts of the question, plus any per-request values:

| Part      | Field                          | Example                  |
|-----------|--------------------------------|--------------------------|
| subject   | `subject.type` + `subject.id`  | `Person` / `ada`       |
| action    | `action.name`                  | `PROVISION`                |
| resource  | `resource.type` + `resource.id`| `Server` / `gpu-node-7`           |
| context   | `context.input_params`         | `{ "max_price": 120000 }`|

`subject.id` / `resource.id` are the nodes' `external_id`s; `action.name` is case-sensitive.

### 2. Build the request body

```json
{
  "subject":  { "type": "Person", "id": "ada" },
  "resource": { "type": "Server",    "id": "gpu-node-7"  },
  "action":   { "name": "PROVISION" },
  "context":  { "input_params": { "max_price": 120000 } }
}
```

Supply `context.input_params` only when the matched policy's condition references a `$name` partial parameter; write each key **without** the leading `$`, keeping its type (numbers stay numbers). A ready body: [`assets/evaluation-provision-server.json`](assets/evaluation-provision-server.json).

### 3. Send the decision request

```text
POST <API_URL>/access/v1/evaluation
```

The endpoint authenticates the **calling application** (its AppAgent credentials - always required) and **optionally the user** (an access token - applies only in some cases, e.g. a condition references a token claim/scope). Which credential goes in which request header is covered by the [Credentials guide](https://developer.indykite.com/guides/guide-credentials).

A runnable shell helper builds the authenticated request: [`scripts/evaluate.sh`](scripts/evaluate.sh) — run with `--print` to preview the `curl` (host-pinned; tokens redacted).

### 4. Read the decision

```json
{ "decision": true }
```

`true` means at least one ACTIVE policy granted the `(subject, action, resource)` triple with its condition satisfied. `false` means no policy granted it - either no policy matched the triple, or the matching policy's condition did not hold for the supplied `input_params` and graph data. A `false` decision is a normal `200`, not an error.

### 5. Verify

If the decision is not what you expected, walk this checklist before changing anything:

1. **Policy ACTIVE?** A draft/inactive policy is ignored.
2. **Triple matches?** `subject.type`, `action.name`, and `resource.type` must match the policy's `subject.type`, `actions`, and `resource.type` exactly (case-sensitive verbs).
3. **Variables named `subject` / `resource`?** The condition binds the request's subject/resource only through those reserved names.
4. **IDs are `external_id`s?** `subject.id` / `resource.id` are matched against node `external_id`. A wrong id silently matches nothing → `false`.
5. **Every `$param` supplied?** A missing `input_params` key the condition needs yields a `422` (`errors: ["missing or wrong input params, '<name>'"]`), not a silent `false`.
6. **Data actually in the IKG?** Confirm the subject node, resource node, and any matched relationship exist.

Full request/response schema, error table, and a deeper troubleshooting walk-through: [`references/evaluation-reference.md`](references/evaluation-reference.md) and [`references/troubleshooting.md`](references/troubleshooting.md).

## Outcome

When this skill has been applied successfully:

- `POST /access/v1/evaluation` returns `{"decision": true}` for an allowed `(subject, action, resource)` triple with valid `input_params`, and `{"decision": false}` for a denied one.
- A missing required `input_params` key is surfaced as a `422` and corrected, not mistaken for a denial.
- The same triple can be fanned out through [`indykite-authzen-evaluations`](../indykite-authzen-evaluations/SKILL.md) or invoked through the [`indykite-mcp-server`](../indykite-mcp-server/SKILL.md) `authzen_evaluate` tool with identical decision semantics.

## Files in this skill

- [`references/evaluation-reference.md`](references/evaluation-reference.md) - the `/evaluation` endpoint: base path, auth, request/response shape, error codes, and pointers to the batch and search sibling skills.
- [`references/troubleshooting.md`](references/troubleshooting.md) - why a decision is unexpectedly `true`/`false` and how to isolate the responsible policy.
- [`assets/evaluation-provision-server.json`](assets/evaluation-provision-server.json) - runnable single-evaluation request body for the `Person PROVISION Server` example.
- [`scripts/evaluate.sh`](scripts/evaluate.sh) - Bash helper that posts a decision request to `/access/v1/evaluation` (host-pinned; `--print` to preview).

## Agent-specific notes

This skill uses generic markdown instructions and works across all agents listed in the [README](../README.md). The agent needs to be able to issue HTTP requests (`curl`, an HTTP client, or the IndyKite Terraform provider). No Claude Code hooks, Cursor `@`-mentions, or Copilot workspace context are required.

## References

- [AuthZEN guide (developer hub)](https://developer.indykite.com/guides/guide-authzen)
- [Dynamic authorization with Knowledge Graphs (developer hub)](https://developer.indykite.com/guides/guide-dynamic-authz)
- [KBAC: Relationship-Based Authorization with the AuthZEN API](https://developer.indykite.com/resources/authz-1)
- [KBAC: Parameterized Authorization with Input Params (`max_price`)](https://developer.indykite.com/resources/authz-4)
- [Music dataset tutorial (worked KBAC + AuthZEN example)](https://developer.indykite.com/tutorials/tutorial-music-dataset)
- [Credentials guide](https://developer.indykite.com/guides/guide-credentials)

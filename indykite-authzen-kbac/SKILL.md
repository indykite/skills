---
name: indykite-authzen-kbac
description: Author an IndyKite KBAC (Knowledge-Based Access Control) authorization policy - subject, actions, resource, and a Cypher condition over the IKG - then evaluate it via the AuthZEN REST API (`POST /access/v1/evaluation`). Use when deciding whether a subject may perform an action on a resource, running batch decisions, or searching the actions a subject is allowed on a resource. Not for reading, returning, or modifying graph data - KBAC only renders a yes/no decision.
license: Apache-2.0
compatibility: Requires curl, bash 4+, and jq. Network access to the regional IndyKite REST API (eu.api.indykite.com or us.api.indykite.com) is required at runtime.
---

# IndyKite KBAC - authorization policy + AuthZEN evaluation

KBAC (Knowledge-Based Access Control) is IndyKite's graph-driven authorization model. A KBAC **policy** declares *who* (`subject`) may perform *which* operations (`actions`) on *what* (`resource`), gated by a Cypher **condition** evaluated against the IKG. At runtime you ask the **AuthZEN** endpoint a question - "can this subject do this action on this resource?" - and get back a boolean `decision`.

This skill covers the full loop:

- A **policy** with `meta.policy_version: "2.0-kbac"`, a single `subject.type`, an `actions` list, a single `resource.type`, and a `condition.cypher` that binds the reserved variables `subject` and `resource`.
- Creating the policy through the Config API (`POST /configs/v1/authorization-policies`).
- A **decision** call - single (`/access/v1/evaluation`), batch (`/access/v1/evaluations`), or action search (`/access/v1/search/action`).

KBAC answers a yes/no authorization question - it does not return or modify graph data, only renders a decision about whether an action is allowed.

## When to use

Activate this skill when the user:

- wants to decide whether a **subject may perform an action on a resource** (e.g. "can this Person `CAN_BUY` this Car?");
- is authoring or debugging a **KBAC authorization policy** (`policy_version: 2.0-kbac`, `actions`, `resource`, `condition.cypher`);
- needs to run **many decisions at once** (`/access/v1/evaluations`) or **search the actions** a subject is allowed on a resource (`/access/v1/search/action`);
- is wiring AuthZEN decisions behind the [`indykite-mcp-server`](../indykite-mcp-server/SKILL.md) `authzen_evaluate` tool and needs the policy that backs it.

Do **not** activate this skill when the user:

- wants to **return graph data** (rows, properties, aggregates) rather than a yes/no decision;
- wants to **create / update / delete** nodes or relationships - KBAC evaluates the graph, it does not write to it;
- is enforcing **agent-to-agent / workflow** access in front of A2A calls - use [`indykite-agent-gateway`](../indykite-agent-gateway/SKILL.md).

## Prerequisites

- An IndyKite **project**, an **AppAgent**, and AppAgent **credentials** (the token that goes into `X-IK-ClientKey` at evaluation time).
- A **Service Account token** with Config API write access, and the project's GID in `PROJECT_GID` - both used to *create* the policy.
- The **IKG already populated** with the subject and resource nodes (and any relationships the condition matches). KBAC evaluates the graph; it does not seed it.
- A **subject type** for the policy - the node type making the request (`Person`, `Track`, `Playlist`, etc.). A policy is restricted to a single subject type; if two subject types need the same action, write two policies.

If any of these are missing, stop and tell the user - fixing them first is far cheaper than debugging an opaque `false` decision.

## Credential and execution safety

This skill calls authenticated IndyKite endpoints, so treat secrets and writes deliberately:

- **Secrets stay in the environment.** `SERVICE_ACCOUNT_TOKEN` (policy creation), the AppAgent credentials token in `X-IK-ClientKey`, and any user `BEARER_TOKEN` are read from environment variables only. Never hardcode, echo, log, or paste them into chat, and never write them to a file. Use the env-var placeholders shown in this skill as-is - do not invent, guess, or ask the user to paste a raw secret value.
- **Confirm before writing.** Creating a policy (`POST /configs/v1/authorization-policies`) mutates project configuration with the Service Account token - confirm with the user before running it. Decision calls (`/access/v1/evaluation`, `/evaluations`, `/search/*`) are read-only and safe to run once the request shape is clear.
- **Show the request first.** State the target endpoint and request body before executing any `curl`, so the user can confirm the host and payload.
- **Fixed hosts only.** Every call targets the regional IndyKite API (`eu`/`us.api.indykite.com`); [`scripts/evaluate.sh`](scripts/evaluate.sh) enforces this and refuses any other host.

## Steps

### 1. Frame the question as (subject, action, resource, condition)

Every KBAC policy answers one shape of question. Pin down all four parts before writing JSON:

| Part        | What it is                                                        | Example            |
|-------------|------------------------------------------------------------------|--------------------|
| `subject`   | The single node type making the request.                          | `Person`           |
| `actions`   | One or more uppercase verbs the policy grants.                     | `["CAN_BUY"]`      |
| `resource`  | The single node type being acted on.                              | `Car`              |
| `condition` | A Cypher pattern + `WHERE` that must hold for the decision `true`. | price within budget |

Working example used throughout this skill:

> A `Person` (subject) may `CAN_BUY` a `Car` (resource) when the car's price is within a budget supplied at evaluation time.

### 2. Write the Cypher condition

The condition is a single `cypher` string. Two hard rules:

- It **must** bind a variable literally named `subject` (matching `subject.type`) and a variable literally named `resource` (matching `resource.type`). The AuthZEN request's `subject.id` / `resource.id` are matched against each node's `external_id`.
- Anything that varies per request is a **partial parameter** written `$name` in the `WHERE` clause; the evaluation call supplies it under `context.input_params` (without the `$`).

```cypher
MATCH (subject:Person), (resource:Car)
WHERE resource.property.price <= $max_price
```

The request identifies the subject directly by `subject.id` (its `external_id`).

For relationship-based rules, match the relationship instead of (or in addition to) a property check:

```cypher
MATCH (subject:Person)-[:CAN_AFFORD]->(resource:Car)
```

### 3. Author the KBAC policy

Build the policy JSON. A KBAC policy has exactly these top-level keys:

- `meta.policy_version` - `"2.0-kbac"`.
- `subject.type` - the single subject node type.
- `actions` - array of action names this policy grants.
- `resource.type` - the single resource node type.
- `condition.cypher` - the pattern + `WHERE` from step 2.

A complete policy for the running example: see [`assets/policy-can-buy-car.json`](assets/policy-can-buy-car.json). The asset is the full create request - the policy above sits in its `policy` field, alongside `name`, `status`, and an optional `display_name` / `description`.

Create it through the Config API:

```bash
# set the current project_id, and stringify only the `policy` field, before POSTing
jq --arg pid "$PROJECT_GID" '.project_id = $pid | .policy |= tojson' assets/policy-can-buy-car.json \
  | curl -X POST "$API_URL/configs/v1/authorization-policies" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $SERVICE_ACCOUNT_TOKEN" \
      -d @-
```

A `201 Created` returns the policy's `id` (GID). The policy must be **ACTIVE** to affect decisions.

For the full schema (every field, multi-action and relationship variants) see [`references/policy-reference.md`](references/policy-reference.md).

### 4. Ask for a decision

The single-decision endpoint:

```text
POST <API_URL>/access/v1/evaluation
```

Authentication:

- **Always**: `X-IK-ClientKey: <AppAgent-credentials-token>` - authenticates the calling application.
- **Optional**: `Authorization: Bearer <user-access-token>` - applies only in some cases; not required otherwise.

Request:

```json
{
  "subject":  { "type": "Person", "id": "alice" },
  "resource": { "type": "Car",    "id": "kitt"  },
  "action":   { "name": "CAN_BUY" },
  "context":  { "input_params": { "max_price": 150000 } }
}
```

`subject.id` / `resource.id` are the nodes' `external_id`s. `context.input_params` supplies every `$name` partial parameter the condition references (keys without the `$`). A runnable helper: [`scripts/evaluate.sh`](scripts/evaluate.sh).

### 5. Read the decision and verify

The response is a boolean decision:

```json
{ "decision": true }
```

`true` means at least one ACTIVE policy granted the `(subject, action, resource)` triple with its condition satisfied. `false` means no policy granted it - either no policy matched the triple, or the matching policy's condition did not hold for the supplied `input_params` and graph data.

If the decision is not what you expected, walk this checklist before changing the policy:

1. **Policy ACTIVE?** A draft/inactive policy is ignored.
2. **Triple matches?** `subject.type`, every `action.name`, and `resource.type` in the request must match the policy's `subject.type`, `actions`, and `resource.type` exactly (case-sensitive verbs).
3. **Variables named `subject` / `resource`?** The condition binds the request's subject/resource only through those reserved names.
4. **IDs are `external_id`s?** `subject.id` / `resource.id` are matched against node `external_id`. A wrong id silently matches nothing → `false`.
5. **Every `$param` supplied?** A missing `input_params` key the condition needs yields a `400`, not a silent `false` - see the evaluation reference.
6. **Data actually in the IKG?** Confirm the subject node, resource node, and any matched relationship exist.

For batch decisions, action search, the full request/response schema, and error semantics, see [`references/evaluation-reference.md`](references/evaluation-reference.md).

## Outcome

When this skill has been applied successfully:

- A KBAC policy exists and is ACTIVE in the project, with `policy_version: "2.0-kbac"`, a single `subject.type`, an `actions` list, a single `resource.type`, and a `condition.cypher` binding `subject` and `resource`.
- `POST /access/v1/evaluation` returns `{"decision": true}` for an allowed `(subject, action, resource)` triple with valid `input_params`, and `{"decision": false}` for a denied one.
- The same policy backs batch decisions (`/access/v1/evaluations`) and action search (`/access/v1/search/action`), and can be invoked through the [`indykite-mcp-server`](../indykite-mcp-server/SKILL.md) `authzen_evaluate` tool without changes.

## Files in this skill

- [`references/policy-reference.md`](references/policy-reference.md) - KBAC policy schema: `meta`, `subject`, `actions`, `resource`, `condition.cypher`, partial parameters, multi-action and relationship variants.
- [`references/evaluation-reference.md`](references/evaluation-reference.md) - AuthZEN endpoints: single `/evaluation`, batch `/evaluations`, `/search/action`; request/response shapes, auth, error codes.
- [`references/troubleshooting.md`](references/troubleshooting.md) - why a decision is unexpectedly `true`/`false` and how to isolate it.
- [`assets/policy-can-buy-car.json`](assets/policy-can-buy-car.json) - runnable KBAC policy for the `Person CAN_BUY Car` example.
- [`assets/evaluation-can-buy-car.json`](assets/evaluation-can-buy-car.json) - matching single-evaluation request body.
- [`scripts/evaluate.sh`](scripts/evaluate.sh) - Bash helper that posts a decision request to `/access/v1/evaluation`.

## Agent-specific notes

This skill uses generic markdown instructions and works across all agents listed in the [README](../README.md). The agent needs to be able to issue HTTP requests (`curl`, an HTTP client, or the IndyKite Terraform provider - see References). No Claude Code hooks, Cursor `@`-mentions, or Copilot workspace context are required.

## References

- [AuthZEN guide (developer hub)](https://developer.indykite.com/guides/guide-authzen)
- [Dynamic authorization with Knowledge Graphs (developer hub)](https://developer.indykite.com/guides/guide-dynamic-authz)
- [Config API documentation - authorization policies](https://openapi.indykite.com/api-documentation-config#tag/authorization-policies)
- [IndyKite Terraform provider - `indykite_authorization_policy`](https://registry.terraform.io/providers/indykite/indykite/latest/docs)
- [Credentials guide](https://developer.indykite.com/guides/guide-credentials)

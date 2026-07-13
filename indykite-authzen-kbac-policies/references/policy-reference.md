# KBAC Policy Reference

This reference covers every field of a KBAC (Knowledge-Based Access Control) authorization policy - the `policy_version: "2.0-kbac"` shape evaluated by the AuthZEN endpoints.

## Top-level structure

A KBAC policy has five top-level keys, all siblings:

| Key         | Use                                                                    |
|-------------|-----------------------------------------------------------------------|
| `meta`      | Set `policy_version: "2.0-kbac"`.                                      |
| `subject`   | Set `type` to the single node type making the request.                |
| `actions`   | Array of uppercase action verbs this policy grants.                   |
| `resource`  | Set `type` to the single node type being acted on.                    |
| `condition` | A Cypher pattern (with optional `WHERE`) that must hold.              |

When adapting to a new domain, the structure stays the same - only the `subject.type`, `actions`, `resource.type`, and `condition` contents change.

## Skeleton

```json
{
  "meta":     { "policy_version": "2.0-kbac" },
  "subject":  { "type": "<Person | Service | Namespace | ...>" },
  "actions":  [ "<ACTION_VERB>", "..." ],
  "resource": { "type": "<ResourceNodeType>" },
  "condition": {
    "cypher": "<MATCH … WHERE …>"
  }
}
```

The condition is expressed as a single Cypher string - the pattern plus an optional `WHERE`.

## `meta.policy_version`

`"2.0-kbac"`. The policy version for a KBAC authorization policy. IndyKite rejects unknown versions.

## `subject.type`

The node type making the request - e.g. `Person`, `Service`, `Namespace`. **Exactly one** type per policy. The AuthZEN request's `subject.id` is matched against the subject node's `external_id`; the subject is identified this way, not by the caller's credentials.

If two subject types need the same action on the same resource, write two policies.

## `actions`

An array of action names the policy grants. Conventionally uppercase verbs (`PROVISION`, `ENTER`, `PLAY`, `VIEW`, `SHARE`). A single policy can grant several actions that share the same subject, resource, and condition:

```json
"actions": ["VIEW", "SHARE"]
```

The AuthZEN request's `action.name` must match one of these exactly (case-sensitive). If different actions need different conditions, split them into separate policies.

## `resource.type`

The node type being acted on. **Exactly one** type per policy. The AuthZEN request's `resource.id` is matched against the resource node's `external_id`.

## `condition.cypher`

The graph pattern plus optional `WHERE` that must hold for the decision to be `true`.

Two hard rules:

1. Bind a variable literally named **`subject`** whose label is `subject.type`, and a variable literally named **`resource`** whose label is `resource.type`. The request's `subject.id` / `resource.id` (each an `external_id`) bind to these.
2. Per-request values are **partial parameters**: write `$name` in the `WHERE` clause and supply the value at evaluation time under `context.input_params` (key without the `$`).

Property comparison:

```cypher
MATCH (subject:Person), (resource:Server)
WHERE resource.property.price <= $max_price
```

Relationship requirement:

```cypher
MATCH (subject:Person)-[:CAN_AFFORD]->(resource:Server)
```

Combined (relationship + property + per-request param):

```cypher
MATCH (subject:Person)-[:CAN_AFFORD]->(resource:Server)
WHERE resource.property.price <= $max_price
```

Multi-hop (e.g. access via a teammate who owns the resource):

```cypher
MATCH (subject:Person)-[:TEAMMATE_OF|MANAGES]-(peer:Person)-[:OWNS]->(resource:Namespace)
```

### Attribute references in the condition

Inside the `WHERE` clause, reference node attributes with these forms:

| Pattern                 | Meaning                    | Example                    |
|-------------------------|----------------------------|----------------------------|
| `<var>.property.<name>` | A named property on a node | `resource.property.price`  |
| `<var>.external_id`     | A node's external id       | `subject.external_id`      |

`<var>` is a variable bound in the `MATCH` pattern. A typo silently matches nothing → a `false` decision. Use standard Cypher comparison operators (`=`, `<>`, `<`, `<=`, `>`, `>=`, `IN`, `STARTS WITH`, …) and `AND` / `OR` / `NOT` to combine clauses.

### Partial parameters

A value that varies per request is written `$name` in the `WHERE` clause (e.g. `$max_price`). The evaluation call must supply it under `context.input_params` with the key written **without** the leading `$`. If a policy references a partial parameter and is used in a decision, the request must include it or the call returns an error.

## Config API lifecycle

All policy operations live under one path and use a **Service Account** Bearer token (`Authorization: Bearer <SERVICE_ACCOUNT_TOKEN>`):

```text
<API_URL>/configs/v1/authorization-policies
```

The same endpoint serves both KBAC and ContX IQ policies; KBAC policies are `policy_version: "2.0-kbac"` and are filtered with `type=kbac` when listing (CIQ uses `type=ciq` and the [`indykite-ciq-*`](../../README.md) skills).

### The create / update envelope

The Config API never takes the policy object directly - it takes an **envelope** in which `policy` is a **stringified** JSON value:

| Field          | Use                                                                      |
|----------------|--------------------------------------------------------------------------|
| `name`         | Stable machine name, unique within the project.                          |
| `display_name` | Human label (optional).                                                  |
| `description`  | Free text (optional).                                                    |
| `project_id`   | The project GID the policy belongs to.                                   |
| `policy`       | The policy object from this reference, **JSON-stringified**.            |
| `status`       | One of `ACTIVE` (validated, participates in decisions), `INACTIVE` (validated, ignored), or `DRAFT` (may be saved even if invalid; ignored). |
| `tags`         | Optional string array; can scope decisions via `context.policy_tags`.   |

The asset [`assets/policy-provision-server.json`](../assets/policy-provision-server.json) keeps `policy` as an object and `project_id` as a placeholder for readability. Before POSTing, set `project_id` and stringify just the `policy` field:

```bash
jq --arg pid "$PROJECT_GID" '.project_id = $pid | .policy |= tojson'
```

### Create

```text
POST /configs/v1/authorization-policies
```

Body: the envelope above. A `201 Created` returns the stored record - `id` (a `gid:…`), `create_time`, `created_by`, `update_time`, `updated_by` - and an **ETag** response header. Keep the `id` and ETag: update and delete need them.

### Read

```text
GET /configs/v1/authorization-policies/{id}
GET /configs/v1/authorization-policies/{name}?location={project_id}
```

Returns the full record: `id`, `name`, `display_name`, `description`, `create_time`, `created_by`, `update_time`, `updated_by`, `organization_id`, `project_id`, `policy` (the stringified policy JSON - parse it to inspect), `status`, `tags`, plus the current ETag header.

### List

```text
GET /configs/v1/authorization-policies?project_id={project_id}&type=kbac
```

Returns `{ "data": [ … ] }`, one record per policy. **In list responses the `policy` field is an empty string** - read a policy by `id` to get its body. List responses carry no ETag. Use `type=kbac` to exclude CIQ policies.

### Update

```text
PUT /configs/v1/authorization-policies/{id}
If-Match: <current-etag>
```

Body carries the fields to change - `display_name`, `description`, `policy` (stringified), `status`, `tags`. This is how you **publish** (`status: "ACTIVE"`), **deactivate** (`status: "INACTIVE"`), or hold a policy as `DRAFT`, or revise its condition. The update uses optimistic concurrency: a missing or stale `If-Match` ETag is rejected. A successful `200` returns a **new** ETag - keep it for the next write.

### Delete

```text
DELETE /configs/v1/authorization-policies/{id}
If-Match: <current-etag>
```

Also ETag-guarded. The response echoes the deleted policy's `id`.

The IndyKite Terraform provider's `indykite_authorization_policy` resource manages the same entity declaratively (it handles the envelope, stringification, and ETag for you).

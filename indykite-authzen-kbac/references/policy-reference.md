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
  "subject":  { "type": "<Person | Track | Playlist | ...>" },
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

The node type making the request - e.g. `Person`, `Track`, `Playlist`. **Exactly one** type per policy. The AuthZEN request's `subject.id` is matched against the subject node's `external_id`; the subject is identified this way, not by the caller's credentials.

If two subject types need the same action on the same resource, write two policies.

## `actions`

An array of action names the policy grants. Conventionally uppercase verbs (`CAN_BUY`, `ENTER`, `PLAY`, `VIEW`, `SHARE`). A single policy can grant several actions that share the same subject, resource, and condition:

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
MATCH (subject:Person), (resource:Car)
WHERE resource.property.price <= $max_price
```

Relationship requirement:

```cypher
MATCH (subject:Person)-[:CAN_AFFORD]->(resource:Car)
```

Combined (relationship + property + per-request param):

```cypher
MATCH (subject:Person)-[:CAN_AFFORD]->(resource:Car)
WHERE resource.property.price <= $max_price
```

Multi-hop (e.g. access via a family member who owns the resource):

```cypher
MATCH (subject:Person)-[:MARRIED_TO|PARENT_OF]-(family:Person)-[:CREATED]->(resource:Playlist)
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

## Creating the policy

The asset [`assets/policy-can-buy-car.json`](../assets/policy-can-buy-car.json) is the create-request envelope - `{ name, display_name, description, project_id, policy: {…}, status }` - where `project_id` is a placeholder and `policy` is kept as an object for readability. Before POSTing, set `project_id` to the current value and stringify just the `policy` field - `jq --arg pid "$PROJECT_GID" '.project_id = $pid | .policy |= tojson'` - then POST to `/configs/v1/authorization-policies` with a Service Account Bearer token. A `201 Created` returns the policy's `id` (GID); it must be **ACTIVE** to participate in decisions. The IndyKite Terraform provider's `indykite_authorization_policy` resource manages the same entity declaratively.

# KBAC Policy Reference

This reference covers every field of a KBAC (Knowledge-Based Access Control) authorization policy - the shape evaluated by the AuthZEN endpoints. Two policy versions exist, selected by `meta.policy_version`: `"2.0-kbac"` (platform-rewritten Cypher, the default) and `"3.0-kbac"` (raw Cypher, usable on any IKG, with optional composite-database routing - see [3.0-kbac: raw Cypher and location routing](#30-kbac-raw-cypher-and-location-routing)). The JSON schema is identical for both; only the condition semantics differ.

## Top-level structure

A KBAC policy has five top-level keys, all siblings:

| Key         | Use                                                                    |
|-------------|-----------------------------------------------------------------------|
| `meta`      | Set `policy_version`: `"2.0-kbac"` or `"3.0-kbac"`.                    |
| `subject`   | Set `type` to the single node type making the request.                |
| `actions`   | Array of action names this policy grants (conventionally uppercase verbs). |
| `resource`  | Set `type` to the single node type being acted on.                    |
| `condition` | A Cypher pattern (with optional `WHERE`) that must hold; optionally a `filter` evaluated against the token claims and `input_params`. |

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

`"2.0-kbac"` or `"3.0-kbac"`. IndyKite rejects unknown versions.

| Aspect | `2.0-kbac` | `3.0-kbac` |
|--------|-----------|-----------|
| Condition Cypher handling | Rewritten by the platform into evaluation and search variants; always runs against the default database | **Raw**: runs as authored; the platform only pins `subject`/`resource` and appends the projection |
| Composite-database routing (data residency) | None | `USE graph.byName(...)` clauses, static or via **location parameters** supplied in `context.input_params` |
| `USE` clause | Rejected (`USE clause is not allowed`) | Allowed, top-level or per `CALL { }` subquery |
| `CALL { }` subqueries / inner `RETURN` | Rejected (`Cypher contains forbidden clauses: [CALL]`) | Allowed; each subquery can carry its own `USE` clause |
| Mutating clauses (`CREATE`, `MERGE`, `SET`, `DELETE`, …) | Blocked | Blocked |
| Top-level `RETURN` | Blocked | Blocked - the platform appends the projection itself |
| Subject node requirement | Must be an **identity node** (`is_identity: true` at ingest) | Any node - matched by type and external ID |
| User (OAuth bearer) token at decision time | Optional; binds the subject to the token's identity (internal-node-ID pin, exposed as `$subject_id`) | Optional; the token's subject must equal the request's `subject` or the call is denied |
| External (resolver-backed) properties in the condition | Allowed | Rejected at creation |
| Policy JSON schema | Identical - only `meta.policy_version` differs | Identical - only `meta.policy_version` differs |

A valid `2.0-kbac` condition is also a valid `3.0-kbac` condition: a policy can be carried over by switching `meta.policy_version`, provided it references neither `$subject_id` nor external properties (both rejected in `3.0-kbac` - see below).

## `subject.type`

The node type making the request - e.g. `Person`, `Service`, `Namespace`. **Exactly one** type per policy, 2-64 characters, a valid IKG node type name. The AuthZEN request's `subject.id` is matched against the subject node's `external_id`; the subject is identified this way, not by the caller's credentials.

In a `2.0-kbac` policy the subject nodes must additionally be **identity nodes** - ingested with `is_identity: true` (see [`indykite-capture-upsert-nodes`](../../indykite-capture-upsert-nodes/SKILL.md)). A subject node ingested as a plain entity is never matched by a `2.0-kbac` condition: the decision is `false` with no error, which makes this the first thing to check when a correct-looking policy always denies. `3.0-kbac` matches the subject by type and external ID only and does not require `is_identity`.

If two subject types need the same action on the same resource, write two policies.

## `actions`

An array of action names the policy grants - **1 to 5 per policy**, each at least 2 characters long, built from letters, digits, and the punctuation characters `.`, `:`, `_`, `-`, and `/` (no spaces). Conventionally uppercase verbs (`PROVISION`, `ENTER`, `PLAY`, `VIEW`, `SHARE`). A single policy can grant several actions that share the same subject, resource, and condition:

```json
"actions": ["VIEW", "SHARE"]
```

The AuthZEN request's `action.name` must match one of these exactly (case-sensitive). If different actions need different conditions, split them into separate policies.

## `resource.type`

The node type being acted on. **Exactly one** type per policy, 2-64 characters, a valid IKG node type name. The AuthZEN request's `resource.id` is matched against the resource node's `external_id`. The resource does not need to be an identity node in either policy version.

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

### `$subject_id` and the user token (`2.0-kbac` only)

Decision calls always authenticate with the AppAgent token; the end user's OAuth token can be sent along with it. When a user token is present, a `2.0-kbac` decision **additionally pins the subject to the token's identity**: on top of the type and `external_id` match against the request's `subject.id`, the subject must be the graph node the token resolves to (pinned by its internal node ID). Presenting one user's token while asking about a different subject therefore cannot yield `true`.

The reserved parameter **`$subject_id`** names this binding. A `2.0-kbac` `WHERE` clause can reference it, but the standard partial-parameter rule then applies - the request must carry `subject_id` under `context.input_params` - and a user token on the request **overrides** the supplied value with the token identity's internal node ID. Since the subject pin already happens automatically, conditions rarely need to reference it.

`3.0-kbac` rejects `$subject_id` at creation - an internal node ID is not stable across the locations of a composite IKG - and enforces the same token-to-subject binding outside the query instead; see [Subject identity at decision time](#subject-identity-at-decision-time).

## `condition.filter` (optional)

Next to `cypher`, the `condition` object accepts an optional **`filter`**: a boolean expression tree evaluated **without touching the graph**, against the request's `context.input_params` and the user token's claims. The policy grants only when **both** the Cypher condition and the filter hold; a filter that evaluates to `false` denies regardless of what the graph contains. It works identically on `2.0-kbac` and `3.0-kbac`.

Each node of the tree is either a **branch** or a **leaf**:

| Kind   | Keys                                      | Rules                                                                 |
|--------|-------------------------------------------|-----------------------------------------------------------------------|
| Branch | `operator`, `operands`                    | `AND` / `OR` (two or more operands) or `NOT` (exactly one operand).   |
| Leaf   | `operator`, `attribute`, `value`, `advice` | Comparison operators: `=`, `<>`, `<`, `<=`, `>`, `>=`, `IN`, `=~` (regex), `STARTS WITH`, `ENDS WITH`, `CONTAINS`, `IS NULL`, `IS NOT NULL`. `value` is required except for `IS NULL` / `IS NOT NULL`; for `IN` it must be an array. |

How `attribute` and `value` entries resolve:

- `"$token.<claim>"` - a claim from the user (OAuth bearer) token, e.g. `"$token.email"`.
- `"$<name>"` - a value from `context.input_params` (key without the `$`); dot paths reach into object params, e.g. `"$order.total"`.
- Any other JSON value is a literal. `attribute` must be a string (in practice a `$…` reference); `value` can be a scalar or an array.
- For date/time comparisons, wrap the side in `{ "type": "datetime", "value": "<RFC3339 timestamp or $param>" }`. Plain values need no wrapper.

A leaf may carry an **`advice`** object - a map of string key/values. When the filter denies, the advice maps of the failing leaves are returned in the decision response under `context.advice` (alongside `context.reason`), giving the caller a machine-readable hint about which check failed.

Example - the graph relationship must exist **and** the token's plan must be `premium` **and** the request must name an allowed channel:

```json
"condition": {
  "cypher": "MATCH (subject:Person)-[:CAN_AFFORD]->(resource:Server)",
  "filter": {
    "operator": "AND",
    "operands": [
      { "operator": "=", "attribute": "$token.plan", "value": "premium" },
      {
        "operator": "IN",
        "attribute": "$channel",
        "value": ["web", "mobile"],
        "advice": { "error": "unsupported_channel" }
      }
    ]
  }
}
```

Like partial parameters in the Cypher, every `$<name>` the filter references must be supplied in `context.input_params` at decision time, and `$token.…` references require the request to carry a user token.

## 3.0-kbac: raw Cypher and location routing

`3.0-kbac` is the **raw-Cypher** policy version: the condition runs as authored, on any IKG - a composite database is **not** required unless the condition actually routes with `USE`. Its headline feature is location routing for **composite IKGs** (data residency): one logical graph spanning multiple constituent databases, so individual nodes can be stored in a specific location. Composite databases are available on customer-hosted deployments; the project setup (constituent databases, `alias_mapping` of logical location names to constituents) is covered by the [Data Residency guide](https://developer.indykite.com/guides/guide-data-residency). Residency support is **opt-in per policy** - `2.0-kbac` policies are unchanged and always evaluate against the default database, where located nodes exist only as property-less proxy nodes. A `3.0-kbac` policy without a `USE` clause also evaluates against the default database, with all the raw-Cypher semantics of this section but no residency prerequisite.

The two hard rules of [`condition.cypher`](#conditioncypher) apply unchanged: bind `subject` and `resource`, and pass per-request values as partial parameters.

### Routing forms

**Static** - the whole condition evaluates inside one named constituent:

```cypher
USE graph.byName('ikcomposite.db2') MATCH (subject:Person)-[:OWNS]->(resource:Car)
```

**Dynamic** - the `graph.byName()` argument is a single parameter, which becomes a **location parameter**:

```cypher
USE graph.byName($region) MATCH (subject:Person)-[:OWNS]->(resource:Car)
```

At decision time the caller supplies the **logical location** - a key of the project's `alias_mapping`, e.g. `"east"` - under `context.input_params` (key without the `$`), and IndyKite translates it to the physical constituent database just before execution. Callers never see or supply physical database names. This works identically on `/access/v1/evaluation`, `/access/v1/evaluations`, and the three search endpoints.

**`CALL { }` subquery** - each subquery can carry its own `USE` clause, so one condition can combine matches from several constituents. The explicit variable-scope form `CALL () { … }` lists the outer variables imported into the subquery (empty parentheses = none); the inner `RETURN` hands rows back to the enclosing query:

```cypher
CALL () { USE graph.byName('ikcomposite.db2') MATCH (subject:Person)-[:OWNS]->(resource:Car) RETURN subject, resource }
```

### Authoring rules

- The `graph.byName()` argument must be a **string literal or a single parameter** - expressions such as `coalesce($region, 'eu')` are rejected at creation.
- A location parameter **cannot be referenced anywhere else** in the Cypher: its value is rewritten to the physical alias at request time.
- `$subject_external_id`, `$subject_type`, `$resource_external_id`, and `$resource_type` are bound by the platform - never supply them in `input_params` and never use them as routing parameters.
- `$subject_id` (available to `2.0-kbac` conditions - see [`$subject_id` and the user token](#subject_id-and-the-user-token-20-kbac-only)) **must not be referenced at all**: on a composite IKG the same logical subject has a different internal node ID per location, so `3.0-kbac` identifies subjects by type and external ID only. Creating a policy that references it fails with `422 Unprocessable Entity` (`parameter "$subject_id" is reserved and cannot be referenced`). No replacement is needed - the platform already pins the subject.
- **External (resolver-backed) properties cannot be used in the condition**: creating the policy fails with `external properties cannot be used in data-residency policies`. A `2.0-kbac` condition that relies on them cannot be carried over to `3.0-kbac`.
- Mutating clauses (`CREATE`, `MERGE`, `SET`, `DELETE`, …) and a top-level `RETURN` remain blocked, exactly as in `2.0-kbac`.

### Subject identity at decision time

A `3.0-kbac` subject is matched by **type and external ID** - the subject node does not need `is_identity: true` (unlike `2.0-kbac`, see [`subject.type`](#subjecttype)). When the decision request also carries a user (OAuth bearer) token, the token's subject must be the same identity as the request's `subject`; a mismatch (or a token without a resolvable graph subject) is denied with `bearer token subject differs from requested subject`. Calls authenticated with the AppAgent token alone are unaffected.

### Decision-time failures

Errors surfaced by the AuthZEN endpoints when a `3.0-kbac` policy's routing goes wrong:

| Situation | Result |
|-----------|--------|
| Required location parameter missing from `context.input_params`, or not a non-empty string | `422 Unprocessable Entity` |
| Location is not a key of the project's `alias_mapping` | `422 Unprocessable Entity` (unknown location) |
| Policy routes with `USE` (static or via a location parameter) but the app space has no composite database | `422 Unprocessable Entity` (`policy requires a composite database, but the app space has none configured`) |
| Request carries a user (bearer) token whose subject differs from the request's `subject` | Denied - `bearer token subject differs from requested subject` |

## Config API lifecycle

All policy operations live under one path and use a **Service Account** Bearer token (`Authorization: Bearer <SERVICE_ACCOUNT_TOKEN>`):

```text
<API_URL>/configs/v1/authorization-policies
```

The same endpoint serves both KBAC and ContX IQ policies; KBAC policies (`2.0-kbac` and `3.0-kbac` alike) are filtered with `type=kbac` when listing (CIQ uses `type=ciq` and the [`indykite-ciq-*`](../../README.md) skills). The lifecycle below is identical for both KBAC versions - only the stringified policy JSON differs.

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

# CIQ Policy Reference (create-node focused)

This reference covers the fields a *create-only* CIQ policy uses, plus the parts of the schema you need to recognise even if you do not write them (so you can tell whether an existing policy permits creates, updates, or both).

For the read-focused variant, see [`indykite-ciq-read/references/policy-reference.md`](../../indykite-ciq-read/references/policy-reference.md).

## Top-level structure

The policy has four top-level keys, all siblings:

| Key                | Use                                                                                        |
|--------------------|--------------------------------------------------------------------------------------------|
| `meta`             | Set `policy_version: "1.0-ciq"`.                                                            |
| `subject`          | Set `type` to the authenticating entity (e.g. `_Application`, `Person`).                    |
| `condition`        | Anchor the subject with a `MATCH` clause and pin it with a filter.                          |
| `allowed_upserts`  | Use `nodes.node_types` to whitelist the labels the Knowledge Query may create as new nodes. |

When adapting to a new domain, only the *contents* of `condition` and `allowed_upserts.nodes.node_types` change; the four-key structure stays the same.

## Skeleton

```json
{
  "meta":      { "policy_version": "1.0-ciq" },
  "subject":   { "type": "<_Application | Person | User | …>" },
  "condition": {
    "cypher": "<MATCH … (anchor to the subject)>",
    "filter": [ { ... } ]
  },
  "allowed_upserts": {
    "nodes": {
      "node_types": [ "<Label>", "<AnotherLabel>" ]
    }
  }
}
```

For a create-only policy: include `meta`, `subject`, `condition`, and `allowed_upserts.nodes.node_types`. **Omit** `allowed_reads`, `allowed_deletes`, and the other `allowed_upserts` sub-fields. Omitting a block is the supported way to forbid that operation.

## `meta.policy_version`

Currently `1.0-ciq`. IndyKite rejects unknown versions.

## `subject.type`

Exactly one type per policy.

- **`_Application`** — system-side writes (catalog ingestion, ETL pipelines). At execute time, only `X-IK-ClientKey` is required; the reserved `$_appId` parameter is auto-filled from the AppAgent's `external_id`. Filter on `subject.external_id = $_appId`.
- **`Person` / `User`** — user-driven writes (user creates a Playlist, a Document, etc.). Requires both `X-IK-ClientKey` and `Authorization: Bearer <user-token>` at execute time. Filter on `subject.external_id = $token.sub` so only the authenticated user's identity is in scope.

If two subject types need to create the same node label, write two policies.

## `condition.cypher`

Even a write-only policy needs a `MATCH` clause that anchors to the subject. The new node is **not** declared here — it is declared in the Knowledge Query's `upsert_nodes`.

Minimal anchors:

```cypher
MATCH (subject:_Application)
```

```cypher
MATCH (subject:Person)
```

If the new node should be linked to an existing element (e.g. created under a `Project` the subject can already see), add that to the cypher:

```cypher
MATCH (subject:_Application)-[:OWNS]->(catalog:Catalog)
```

Variables defined here are referenceable in `condition.filter`, `allowed_reads`, and `allowed_upserts` — but **not** as the `name` of an `upsert_nodes` entry that creates a new node (that name must be fresh).

### Performance: pin the subject before high-fan-in hops

On a large graph, a `MATCH` chain whose only selective filters sit at its *endpoints* can execute slowly. If one endpoint is a high-fan-in node — a brand, tenant, or category that a large share of records points to — the query planner may anchor there and traverse its entire fan-in before the subject filter prunes anything, so execution time grows linearly with the dataset.

A minimal condition that only anchors the subject (`MATCH (subject:_Application)`) has nothing to traverse and is **not** affected. When the condition gates creation on a shared node (e.g. a catalog every record points at), bind that node in its own `MATCH`, pinned inline by `external_id`, and check the link as a pattern predicate:

```cypher
MATCH (catalog:Catalog {external_id: $catalog_id})
MATCH (subject:_Application {external_id: $_appId})
WHERE (subject)-[:OWNS]->(catalog)
```

Server-populated in-cypher parameters make this safe without extra caller input: `$token.<claim>` (e.g. `$token.sub`) carries the Bearer token's claims for user subjects, `$ik_token.<claim>` (e.g. `$ik_token.act.sub`) the claims of the delegation token sent in `X-IK-Token`, and `$_appId` carries the application id for `_Application` subjects. `token` and `ik_token` are reserved names: the platform binds both claim sets, ignores caller values sent under either name in `input_params`, and binds an empty set for a token that did not arrive, so a comparison against it is `null` and the query matches nothing rather than erroring. Any other `$param` in the cypher must be supplied by the caller via `input_params`.

If the chain cannot be restructured, the fallback is a planning barrier: pin the subject with an in-cypher `WHERE` and `WITH subject LIMIT 1`, then continue the chain from the bound subject (safe because `(type, external_id)` is unique in the IKG). Three rules make the barrier correct: the pinning equality must be an in-cypher `WHERE` placed *before* the `LIMIT 1` — `condition.filter` is applied after the whole pattern, so a `LIMIT 1` after an unpinned `MATCH` grabs an arbitrary node and silently returns zero rows; every `WITH` must keep carrying `subject` (the validator rejects one that drops it: `missing required variables in WITH statement`); and a plain `WITH` without `LIMIT` is flattened by the planner and changes nothing. `USING INDEX` planner hints are rejected by the policy parser, and extra Knowledge Query filter values narrow the result without changing which end the planner anchors on.

### Labels the condition cannot match, and `skip_resource_label`

When the policy is saved, the platform rewrites the condition so that every named node also carries the `Resource` system label and the subject the `DigitalTwin` label: `MATCH (subject:Person)-[:OWNS]->(car:Car)` runs as `MATCH (subject:Person:DigitalTwin:Resource)-[:OWNS]->(car:Car:Resource)`. Two consequences:

- **Blocked labels.** A condition that names a platform label is refused at save time with ``invalid node type `<label>` in cypher for node `<var>` ``. The blocked labels are `_AppAgent`, `_API`, `_TrustScore`, `Source`, and the four data-schema labels `_DataSchemaNode`, `_DataSchemaProperty`, `_DataSchemaRelationship`, `_DataSchemaMetadata`. The observed schema is read through the Data Schema API ([`indykite-data-schema`](../../indykite-data-schema/SKILL.md)), never through a query.
- **`condition.skip_resource_label`** (optional, default `false`). For some conditions the added `Resource` label leads the planner to a poor plan, because the `id` and `external_id` indexes are defined on `Resource` and it may prefer them over the node type's own index. Setting `"skip_resource_label": true` inside `condition` leaves `Resource` out, so each lookup uses the indexes of the node type's label; only the subject's `DigitalTwin` label is still added, and the results are the same either way. Use it only when a condition that is already anchored and bounded (above) is still slow, and measure before and after - the default plan is right for most conditions. Accepted on `1.0-ciq`; a policy version that does not support it refuses the save with `skip_resource_label is not allowed for this policy version`.

```json
"condition": {
  "cypher": "MATCH (subject:Person)-[owns:OWNS]->(bus:Bus)-[:HAS]->(ln:LicenseNumber)",
  "skip_resource_label": true,
  "filter": [ { "attribute": "subject.external_id", "operator": "=", "value": "$token.sub" } ]
}
```

## `condition.filter`

Constrains the match. Same operator and attribute conventions as the read-side policy schema.

For `_Application` subjects, the canonical filter is:

```json
[
  {
    "operator":  "=",
    "attribute": "subject.external_id",
    "value":     "$_appId"
  }
]
```

`$_appId` is reserved — the platform substitutes it with the calling AppAgent's `external_id`. Do **not** pass it in `input_params` yourself.

For `Person` subjects:

```json
[
  {
    "operator":  "=",
    "attribute": "subject.external_id",
    "value":     "$token.sub"
  }
]
```

Without this clause, `MATCH (subject:Person)` matches every Person in the graph — not just the caller. `$token.sub` is the verified `sub` claim from the Bearer token.

## `allowed_upserts.nodes`

This is the only `allowed_upserts` sub-field a create-only policy uses.

### `node_types` — what this skill is about

```json
"allowed_upserts": {
  "nodes": {
    "node_types": ["Track"]
  }
}
```

`node_types` is an array of node labels the Knowledge Query may **create as new nodes**. Each `upsert_nodes[].type` in the Knowledge Query must appear here, otherwise the create is rejected.

### `existing_nodes` — out of scope

```json
"allowed_upserts": {
  "nodes": {
    "existing_nodes": ["subject"]
  }
}
```

`existing_nodes` whitelists variables from `cypher` whose properties may be **updated** in place. This is the *update existing node* path, which this skill does not cover. If both creates and in-place updates are wanted under the same policy, both keys can co-exist.

## What the other blocks would do (and why we omit them)

For completeness — out of scope here:

- `allowed_upserts.relationships.relationship_types` — `[{type, source_node_label, target_node_label}]` triples for **creating** new relationships.
- `allowed_upserts.relationships.existing_relationships` — variables from `cypher` whose relationships' properties can be updated in place.
- `allowed_deletes.nodes` / `allowed_deletes.relationships` — variables that can be deleted.
- `allowed_reads.nodes` / `relationships` / `aggregate_values` — what the Knowledge Query may project back. Useful even on a create-only policy if you want to read other context alongside the create — but if you only need the new node echoed back, the Knowledge Query's own `nodes` array (referencing the `upsert_nodes[].name`) is sufficient.

Omitting these blocks means the corresponding Knowledge Query arrays (`upsert_relationships`, `delete_nodes`, `delete_relationships`, projections of cypher-matched data) will be rejected at execute time as not allowed.

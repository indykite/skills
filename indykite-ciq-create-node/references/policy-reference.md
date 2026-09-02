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

Server-populated in-cypher parameters make this safe without extra caller input: `$token.<claim>` (e.g. `$token.sub`) carries the Bearer token's claims for user subjects, and `$_appId` carries the application id for `_Application` subjects. Any other `$param` in the cypher must be supplied by the caller via `input_params`.

If the chain cannot be restructured, the fallback is a planning barrier: pin the subject with an in-cypher `WHERE` and `WITH subject LIMIT 1`, then continue the chain from the bound subject (safe because `(type, external_id)` is unique in the IKG). Three rules make the barrier correct: the pinning equality must be an in-cypher `WHERE` placed *before* the `LIMIT 1` — `condition.filter` is applied after the whole pattern, so a `LIMIT 1` after an unpinned `MATCH` grabs an arbitrary node and silently returns zero rows; every `WITH` must keep carrying `subject` (the validator rejects one that drops it: `missing required variables in WITH statement`); and a plain `WITH` without `LIMIT` is flattened by the planner and changes nothing. `USING INDEX` planner hints are rejected by the policy parser, and extra Knowledge Query filter values narrow the result without changing which end the planner anchors on.

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

# CIQ Policy Reference (create-relationship focused)

This reference covers the fields a *relationship-create-only* CIQ policy uses, plus the parts of the schema you need to recognise even if you do not write them.

For node creation see [`indykite-ciq-create-node/references/policy-reference.md`](../../indykite-ciq-create-node/references/policy-reference.md). For reads see [`indykite-ciq-read/references/policy-reference.md`](../../indykite-ciq-read/references/policy-reference.md).

## Top-level structure

The policy has four top-level keys, all siblings:

| Key                | Use                                                                                                                         |
|--------------------|-----------------------------------------------------------------------------------------------------------------------------|
| `meta`             | Set `policy_version: "1.0-ciq"`.                                                                                             |
| `subject`          | Set `type` to the authenticating entity (e.g. `_Application`, `Person`).                                                     |
| `condition`        | Match the subject AND both endpoint nodes the new relationship will connect; pin the endpoints with `external_id` filters.   |
| `allowed_upserts`  | Use `relationships.relationship_types` to whitelist `(source_node_label, type, target_node_label)` triples that may be created. |

When adapting to a new domain, only the *contents* of `condition` and `allowed_upserts.relationships.relationship_types` change; the four-key structure stays the same.

## Skeleton

```json
{
  "meta":      { "policy_version": "1.0-ciq" },
  "subject":   { "type": "<_Application | Person | User | …>" },
  "condition": {
    "cypher": "<MATCH (subject:…) MATCH (source:…) MATCH (target:…)>",
    "filter": [ { ... } ]
  },
  "allowed_upserts": {
    "relationships": {
      "relationship_types": [
        {
          "type":              "<RELATIONSHIP_LABEL>",
          "source_node_label": "<SourceLabel>",
          "target_node_label": "<TargetLabel>"
        }
      ]
    }
  }
}
```

For a relationship-create-only policy: include `meta`, `subject`, `condition`, and `allowed_upserts.relationships.relationship_types`. **Omit** `allowed_reads`, `allowed_deletes`, and the other `allowed_upserts` sub-fields. Omitting a block is the supported way to forbid that operation.

## `meta.policy_version`

Currently `1.0-ciq`. IndyKite rejects unknown versions.

## `subject.type`

Exactly one type per policy.

- **`_Application`** — system-side wiring (catalog ingestion, ETL pipelines, batch linking). At execute time, only `X-IK-ClientKey` is required; the reserved `$_appId` parameter is auto-filled. Filter on `subject.external_id = $_appId`.
- **`Person` / `User`** — user-driven linking (a user marks a Track as a favourite, accepts a Contract, etc.). Requires both `X-IK-ClientKey` and `Authorization: Bearer <user-token>`. Filter on `subject.external_id = $token.sub`.

If two subject types need to create the same relationship, write two policies.

## `condition.cypher`

Must `MATCH` the subject **and** the source and target endpoint nodes. The new relationship is **not** declared here; it's declared in the Knowledge Query's `upsert_relationships`.

Use disjoint `MATCH` clauses (separated by spaces) when the endpoints don't need to be connected by an existing path:

```cypher
MATCH (subject:_Application)
MATCH (track:Track)
MATCH (venue:Venue)
```

Use a connected pattern when they do. For example, requiring a pre-existing `:CATALOGED_BY` link before allowing a `PLAYED_AT` link:

```cypher
MATCH (subject:_Application)-[:HAS_AGREEMENT_WITH]->(:Catalog)<-[:CATALOGED_BY]-(track:Track)
MATCH (venue:Venue)
```

The connectivity you express in the cypher is the gate the platform enforces before the new edge can be added.

Each variable name (`subject`, `track`, `venue`, …) is a **string identifier** the Knowledge Query's `upsert_relationships` will use as `source` / `target`. Do **not** confuse variable names with node labels — the policy's cypher binds the label to the variable; the KQ uses only the variable.

### Performance: pin the subject before high-fan-in hops

On a large graph, a `MATCH` chain whose only selective filters sit at its *endpoints* can execute slowly. If one endpoint is a high-fan-in node — a brand, tenant, or category that a large share of records points to — the query planner may anchor there and traverse its entire fan-in before the subject filter prunes anything, so execution time grows linearly with the dataset.

The connected-pattern gate is where this bites: in the `:Catalog` example above, every track in the catalog points at the same `Catalog` node. Reach the catalog from the pinned subject, pin the endpoints inline by `external_id`, and check catalog membership as a pattern predicate instead of a chain hop:

```cypher
MATCH (subject:_Application {external_id: $_appId})-[:HAS_AGREEMENT_WITH]->(catalog:Catalog)
MATCH (track:Track {external_id: $track_external_id}) WHERE (track)-[:CATALOGED_BY]->(catalog)
MATCH (venue:Venue {external_id: $venue_external_id})
```

Server-populated in-cypher parameters make this safe without extra caller input: `$token.<claim>` (e.g. `$token.sub`) carries the Bearer token's claims for user subjects, and `$_appId` carries the application id for `_Application` subjects. Any other `$param` in the cypher must be supplied by the caller via `input_params`.

If the chain cannot be restructured, the fallback is a planning barrier: pin the subject with an in-cypher `WHERE` and `WITH subject LIMIT 1`, then continue the chain from the bound subject (safe because `(type, external_id)` is unique in the IKG). Three rules make the barrier correct: the pinning equality must be an in-cypher `WHERE` placed *before* the `LIMIT 1` — `condition.filter` is applied after the whole pattern, so a `LIMIT 1` after an unpinned `MATCH` grabs an arbitrary node and silently returns zero rows; every `WITH` must keep carrying `subject` (the validator rejects one that drops it: `missing required variables in WITH statement`); and a plain `WITH` without `LIMIT` is flattened by the planner and changes nothing. `USING INDEX` planner hints are rejected by the policy parser, and extra Knowledge Query filter values narrow the result without changing which end the planner anchors on.

## `condition.filter`

Constrains the match to specific endpoint nodes. Same operator and attribute conventions as the read-side policy schema.

For `_Application` subjects, the canonical filter pins all three identifiers:

```json
[
  {
    "operator": "AND",
    "operands": [
      { "operator": "=", "attribute": "subject.external_id", "value": "$_appId" },
      { "operator": "=", "attribute": "track.external_id",   "value": "$track_external_id" },
      { "operator": "=", "attribute": "venue.external_id",   "value": "$venue_external_id" }
    ]
  }
]
```

`$_appId` is reserved (do not pass it in `input_params`). The other two `$param`s become required keys in the execute call's `input_params`.

For `Person` subjects, replace the `$_appId` clause with `subject.external_id = $token.sub` and keep the endpoint clauses.

## `allowed_upserts.relationships`

The only `allowed_upserts` sub-field a relationship-create-only policy uses.

### `relationship_types` — what this skill is about

```json
"allowed_upserts": {
  "relationships": {
    "relationship_types": [
      {
        "type":              "PLAYED_AT",
        "source_node_label": "Track",
        "target_node_label": "Venue"
      }
    ]
  }
}
```

Each triple is an entry in the array. The Knowledge Query's `upsert_relationships` may create only relationships matching one of these triples — `type`, `source_node_label`, **and** `target_node_label` must all match. Direction matters: `(Track)-[:PLAYED_AT]->(Venue)` and `(Venue)-[:PLAYED_AT]->(Track)` are *different* triples and need two entries (or two policies) to permit both.

You may declare multiple triples in a single policy when one Knowledge Query needs to write more than one relationship in the same call (e.g. one `(Person)-[:ACCEPTED]->(Contract)` plus one `(Contract)-[:COVERS]->(Vehicle)`).

### `existing_relationships` — out of scope

```json
"allowed_upserts": {
  "relationships": {
    "existing_relationships": ["r1"]
  }
}
```

`existing_relationships` whitelists relationship variables from `cypher` whose properties may be **updated** in place. This is the *update-existing-relationship* path and is not covered by this skill. Both keys can co-exist if the policy needs to allow both creation of new edges and property updates on already-matched edges.

## What the other blocks would do (and why we omit them)

For completeness — out of scope here:

- `allowed_upserts.nodes.node_types` — labels that may be created as **new nodes**. Use [`indykite-ciq-create-node`](../../indykite-ciq-create-node/SKILL.md) for that.
- `allowed_upserts.nodes.existing_nodes` — variables from `cypher` whose properties can be updated.
- `allowed_deletes.nodes` / `allowed_deletes.relationships` — variables that can be deleted.
- `allowed_reads` — what may be projected. Useful even on a write-only policy if you need to read other context alongside the create — but if you only need the new relationship and its endpoints echoed back, the Knowledge Query's `nodes` and `relationships` arrays are sufficient.

Omitting these blocks means the corresponding Knowledge Query arrays will be rejected at execute time as not allowed.

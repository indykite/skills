# CIQ Policy Reference (add-relationship-property focused)

This reference covers the fields a *relationship-property-write-only* CIQ policy uses, plus the parts of the schema you need to recognise even if you do not write them.

For the node-property variant see [`indykite-ciq-add-property/references/policy-reference.md`](../../indykite-ciq-add-property/references/policy-reference.md). For relationship creation see [`indykite-ciq-create-relationship/references/policy-reference.md`](../../indykite-ciq-create-relationship/references/policy-reference.md).

## Skeleton

```json
{
  "meta":      { "policy_version": "1.0-ciq" },
  "subject":   { "type": "<_Application | Person | User | …>" },
  "condition": {
    "cypher": "<MATCH that resolves the relationship to update>",
    "filter": [ { ... } ]
  },
  "allowed_upserts": {
    "relationships": {
      "existing_relationships": [ "<cypher-variable-name>" ]
    }
  }
}
```

For a relationship-property-write-only policy: include `meta`, `subject`, `condition`, and `allowed_upserts.relationships.existing_relationships`. **Omit** `allowed_reads`, `allowed_deletes`, and the other `allowed_upserts` sub-fields.

## `meta.policy_version`

Currently `1.0-ciq`.

## `subject.type`

Exactly one type per policy.

- **`_Application`** — system-side annotation passes (audit fields, `verified` flags, score updates). Filter on `subject.external_id = $_appId`.
- **`Person` / `User`** — user-driven property writes on edges they own. Filter on `subject.external_id = $token.sub`.

## `condition.cypher`

The `MATCH` clause must bind the existing relationship to a variable. Pin both endpoints (and any path constraints) so the relationship is uniquely identified at execute time.

```cypher
MATCH (subject:_Application)
MATCH (track:Track)-[r:PLAYED_AT]->(venue:Venue)
```

Variable names: `subject`, `track`, `r`, `venue`. The relationship variable `r` is what `existing_relationships` and the Knowledge Query's `upsert_relationships[].name` reference. The endpoints (`track`, `venue`) are not strictly required to be variables, but pinning them in `condition.filter` is how you ensure the right edge is updated.

## `condition.filter`

Constrains the match. For `_Application` subjects, the canonical filter pins all three identifiers (subject + both endpoints):

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

For Person subjects, replace the `$_appId` clause with `subject.external_id = $token.sub`.

## `allowed_upserts.relationships`

The only `allowed_upserts` sub-field a relationship-property-write-only policy uses.

### `existing_relationships` — what this skill is about

```json
"allowed_upserts": {
  "relationships": {
    "existing_relationships": ["r"]
  }
}
```

Lists relationship variables from `cypher` whose properties may be **set**. Each `upsert_relationships[].name` in the KQ must appear here.

You can list multiple variables when one Knowledge Query needs to write properties on more than one matched relationship.

### `relationship_types` — out of scope

`relationship_types` whitelists `{type, source_node_label, target_node_label}` triples for **creating new relationships**. Different operation, different KQ shape (fresh `name` plus `source`/`target`/`type`). See [`indykite-ciq-create-relationship`](../../indykite-ciq-create-relationship/SKILL.md). Both keys can co-exist if a single policy needs to allow both creates and in-place property writes.

## What the other blocks would do (and why we omit them)

For completeness:

- `allowed_upserts.nodes.existing_nodes` — variables from `cypher` whose **node** properties can be updated. Different skill: [`indykite-ciq-add-property`](../../indykite-ciq-add-property/SKILL.md). Both keys can co-exist (write properties on both the relationship and one of its endpoints in a single policy).
- `allowed_upserts.nodes.node_types` — labels for **brand-new node creation**. See [`indykite-ciq-create-node`](../../indykite-ciq-create-node/SKILL.md).
- `allowed_deletes.relationships` — variables that can be deleted, including `<var>.<property>` paths for deleting individual relationship properties. Different skill: [`indykite-ciq-delete`](../../indykite-ciq-delete/SKILL.md).
- `allowed_reads` — what may be projected. Often combined with `existing_relationships` in real policies; kept out of the runnable asset for clarity.

Omitting these blocks means the corresponding Knowledge Query arrays will be rejected at execute time.

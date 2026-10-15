# CIQ Policy Reference (add-relationship-property focused)

This reference covers the fields a *relationship-property-write-only* CIQ policy uses, plus the parts of the schema you need to recognise even if you do not write them.

For the node-property variant see [`indykite-ciq-add-property/references/policy-reference.md`](../../indykite-ciq-add-property/references/policy-reference.md). For relationship creation see [`indykite-ciq-create-relationship/references/policy-reference.md`](../../indykite-ciq-create-relationship/references/policy-reference.md).

## Top-level structure

The policy has four top-level keys, all siblings:

| Key                | Use                                                                                                                |
|--------------------|--------------------------------------------------------------------------------------------------------------------|
| `meta`             | Set `policy_version: "1.0-ciq"`.                                                                                    |
| `subject`          | Set `type` to the authenticating entity (e.g. `_Application`, `Person`).                                            |
| `condition`        | Match the subject and bind the existing relationship to a variable; pin both endpoints with `external_id` filters.  |
| `allowed_upserts`  | Use `relationships.existing_relationships` to whitelist the cypher relationship variables whose properties the KQ may set. |

When adapting to a new domain, only the *contents* of `condition` and `allowed_upserts.relationships.existing_relationships` change; the four-key structure stays the same.

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

### Performance: pin the subject before high-fan-in hops

On a large graph, a `MATCH` chain whose only selective filters sit at its *endpoints* can execute slowly. If one endpoint is a high-fan-in node — a brand, tenant, or category that a large share of records points to — the query planner may anchor there and traverse its entire fan-in before the subject filter prunes anything, so execution time grows linearly with the dataset.

This skill's canonical disjoint shape avoids the problem outright when both endpoints are pinned inline by `external_id`:

```cypher
MATCH (subject:_Application {external_id: $_appId})
MATCH (track:Track {external_id: $track_external_id})-[r:PLAYED_AT]->(venue:Venue {external_id: $venue_external_id})
```

Reach for the pattern-predicate form (bind the fan-in node in its own `MATCH` and check membership with a `WHERE (x)-[:REL]->(fanin)` predicate) only when the pattern must chain through a node that a large share of records points to.

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

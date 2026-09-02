# CIQ Policy Reference (delete focused)

This reference covers the fields a *delete-only* CIQ policy uses, plus the parts of the schema you need to recognise even if you do not write them.

For other CIQ operations see the matching skills' policy references.

## Top-level structure

The policy has four top-level keys, all siblings:

| Key               | Use                                                                                                          |
|-------------------|--------------------------------------------------------------------------------------------------------------|
| `meta`            | Set `policy_version: "1.0-ciq"`.                                                                              |
| `subject`         | Set `type` to the authenticating entity (e.g. `Person`, `_Application`).                                       |
| `condition`       | Match the subject and the element(s) to delete; pin them with a filter.                                       |
| `allowed_deletes` | Use `nodes` and/or `relationships` to whitelist what may be deleted (variables, properties, or wildcards).    |

When adapting to a new domain, only the *contents* of `condition` and `allowed_deletes` change; the four-key structure stays the same.

## Skeleton

```json
{
  "meta":      { "policy_version": "1.0-ciq" },
  "subject":   { "type": "<_Application | Person | User | …>" },
  "condition": {
    "cypher": "<MATCH that resolves the element to delete>",
    "filter": [ { ... } ]
  },
  "allowed_deletes": {
    "nodes":         [ "<entry>", "<entry>", ... ],
    "relationships": [ "<entry>", "<entry>", ... ]
  }
}
```

For a delete-only policy: include `meta`, `subject`, `condition`, and `allowed_deletes` (with `nodes` and/or `relationships`). **Omit** `allowed_reads` and `allowed_upserts`.

## `meta.policy_version`

Currently `1.0-ciq`.

## `subject.type`

Exactly one type per policy. The standard `_Application` / `Person` patterns from the read and write skills apply unchanged.

## `condition.cypher`

Must `MATCH` the element you want to delete, binding it to a variable. Three common shapes:

- **Whole node delete** — `MATCH (subject:Person)` (or whatever the target is).
- **Whole relationship delete** — `MATCH (a:A)-[r:REL]->(b:B)` and reference `r` in `allowed_deletes.relationships`.
- **Property delete** — same `MATCH` as for a property write, but reference the property path in `allowed_deletes`.

Pin the target by `external_id` in the filter so the right element is deleted.

### Performance: pin the subject before high-fan-in hops

On a large graph, a `MATCH` chain whose only selective filters sit at its *endpoints* can execute slowly. If one endpoint is a high-fan-in node — a brand, tenant, or category that a large share of records points to — the query planner may anchor there and traverse its entire fan-in before the subject filter prunes anything, so execution time grows linearly with the dataset.

This matters when the element being deleted sits at the end of a chain (the property-delete and deep-node shapes). The fix is to take the fan-in node out of the connected chain: bind it in its own `MATCH`, pinned inline by `external_id`, and check membership with a pattern predicate in `WHERE`:

```cypher
MATCH (brand:Brand {external_id: $brand_id})
MATCH (subject:Person {external_id: $token.sub})-[:OWNS]->(car:Car)-[:HAS]->(ln:LicenseNumber)
WHERE (car)-[:MADE_BY]->(brand)
```

Server-populated in-cypher parameters make this safe without extra caller input: `$token.<claim>` (e.g. `$token.sub`) carries the Bearer token's claims for user subjects, and `$_appId` carries the application id for `_Application` subjects. Any other `$param` in the cypher must be supplied by the caller via `input_params`.

If the chain cannot be restructured, the fallback is a planning barrier: pin the subject with an in-cypher `WHERE` and `WITH subject LIMIT 1`, then continue the chain from the bound subject (safe because `(type, external_id)` is unique in the IKG). Three rules make the barrier correct: the pinning equality must be an in-cypher `WHERE` placed *before* the `LIMIT 1` — `condition.filter` is applied after the whole pattern, so a `LIMIT 1` after an unpinned `MATCH` grabs an arbitrary node and silently returns zero rows; every `WITH` must keep carrying `subject` (the validator rejects one that drops it: `missing required variables in WITH statement`); and a plain `WITH` without `LIMIT` is flattened by the planner and changes nothing. `USING INDEX` planner hints are rejected by the policy parser, and extra Knowledge Query filter values narrow the result without changing which end the planner anchors on.

## `condition.filter`

Standard. For Person subjects use `subject.external_id = $token.sub`. For `_Application` use `$_appId`.

## `allowed_deletes`

The core of this skill. Two sub-fields, each accepting **four kinds of entry**:

### `allowed_deletes.nodes`

```json
"allowed_deletes": {
  "nodes": [
    "car",                      // delete the whole Car node
    "car.*",                    // wildcard: delete any property of car
    "car.property.color",       // delete only the `color` property
    "car.property.year"         // delete only the `year` property
  ]
}
```

| Entry form               | Meaning                                                                                                      |
|--------------------------|--------------------------------------------------------------------------------------------------------------|
| `<var>`                  | The KQ may delete the whole node bound to `<var>` in the cypher.                                              |
| `<var>.*`                | Wildcard — the KQ may delete any property of `<var>`. Useful when you don't want to enumerate property names. |
| `<var>.property.<name>`  | The KQ may delete only the named property. Other properties are not affected.                                |

### `allowed_deletes.relationships`

```json
"allowed_deletes": {
  "relationships": [
    "r1",            // delete the whole relationship bound to r1
    "r1.*",          // wildcard: delete any property of r1
    "r1.status"      // delete only the `status` property
  ]
}
```

Same four-form structure. Note that for relationships, the property syntax is `<var>.<property>` (no `.property.` segment) — that's a documented quirk in the schema.

## What the other blocks would do (and why we omit them)

- `allowed_reads` — what may be projected. Sometimes combined with `allowed_deletes` so the caller can confirm what they deleted in the response. Out of scope for the runnable asset.
- `allowed_upserts.nodes.existing_nodes` / `node_types` — write paths. See the create / add-property skills.
- `allowed_upserts.relationships.existing_relationships` / `relationship_types` — write paths.

Omitting these blocks means the corresponding Knowledge Query arrays will be rejected at execute time.

## Protected property names — cannot be deleted

The platform-managed properties that cannot be set *or* deleted:

- `_service`
- `create_time`
- `external_id` *(deleting a whole node deletes its `external_id` along with it; you cannot delete just the `external_id` while keeping the node)*
- `id`
- `type`
- `update_time`

Attempting to include any of these in `allowed_deletes` (e.g. `"car.property.id"`) is rejected at policy creation.

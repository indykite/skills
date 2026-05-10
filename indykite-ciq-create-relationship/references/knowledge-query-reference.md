# CIQ Knowledge Query Reference (create-relationship focused)

A Knowledge Query references a CIQ policy and declares what to do at runtime. This reference covers the relationship-create fields in detail and one-lines the rest.

## Skeleton (relationship-create-only)

```json
{
  "upsert_relationships": [
    {
      "name":   "<fresh-variable-name>",
      "source": "<cypher-variable-name>",
      "target": "<cypher-variable-name>",
      "type":   "<RELATIONSHIP_LABEL>",
      "properties": [
        { "type": "<property_name>", "value": "$<param-or-hardcoded>" }
      ]
    }
  ],
  "nodes":         [ "<source-or-target-projection>" ],
  "relationships": [ "<fresh-variable-name>" ]
}
```

For a relationship-create-only Knowledge Query, only these fields appear. Other arrays (`filter`, `aggregate_values`, `upsert_nodes`, `delete_*`, `batch_read`) are listed at the bottom for context but should be **omitted**.

## `upsert_relationships`

Array of relationship-create entries. One entry creates one edge.

### `name`

Variable name for the new relationship. Two rules:

- **Creating a new relationship** (this skill): use a **fresh** name not present in the policy's `cypher`. Convention: prefix with `new` or use a compact noun (`r1`, `r2` … if you're following the constants-file convention; `newPlayedAt`, `newAccepted` if you prefer descriptive names).
- **Updating an existing relationship** (different skill): use the variable name from the policy's `cypher` (e.g. `r1` if the cypher includes `[r1:HAS_AGREEMENT_WITH]`). Out of scope here.

If you accidentally re-use a cypher relationship variable name when creating, the request will be interpreted as an update on that match — usually rejected because `existing_relationships` was not declared.

### `source` and `target`

**Variable names from the policy's cypher**, naming the existing endpoint nodes. These must:

- Be present in the policy's `cypher` (i.e. there must be a `MATCH (track:Track)` clause for `"source": "track"`).
- Resolve to nodes whose labels match the policy's `relationship_types[]` triple — `source_node_label` for `source`, `target_node_label` for `target`.

A common confusion: `source` and `target` are **variable names**, not labels. `"source": "Track"` (the label) is wrong; `"source": "track"` (the cypher variable) is right.

### `type`

The relationship label. **Must** equal one of the `type` values in the policy's `allowed_upserts.relationships.relationship_types`. The same triple — `(type, source_node_label, target_node_label)` — must match exactly.

### `properties` (optional)

Array of property entries on the new relationship. Same shape as node properties:

- `type` — property name. **Must be hardcoded** (no `$param`).
- `value` — property value. May be hardcoded or `$param`.
- `metadata` — optional. Array of `{type, value}` items for property metadata. Same rules.

Example with two properties on the new relationship:

```json
"upsert_relationships": [
  {
    "name":   "newPlayedAt",
    "source": "track",
    "target": "venue",
    "type":   "PLAYED_AT",
    "properties": [
      { "type": "first_played_at", "value": "$performance_timestamp" },
      { "type": "verified",        "value": true }
    ]
  }
]
```

Omit `properties` entirely when the new relationship has no properties of its own (often the case for simple linking edges).

### Protected property names

Same set as for nodes — these cannot be set on a relationship's `properties`:

- `_service`
- `create_time`
- `id`
- `type` *(this is the relationship label, set via the dedicated field above)*
- `update_time`

(`external_id` is not protected on relationships in the same way it is on nodes; relationships are identified by their endpoints and type, not by an `external_id`.)

## `nodes`

Top-level array. List endpoint projections you want echoed in the response, e.g. `track.external_id`, `venue.external_id`. Optional but useful for confirming which nodes the new edge connects.

## `relationships`

Top-level array. List the `upsert_relationships[].name` here to **echo the new relationship's identifiers in the response**:

```json
"relationships": ["newPlayedAt"]
```

Without this, the create still happens but the response carries no projection of the new edge.

## Out-of-scope fields

These appear in the full Knowledge Query schema; **omit them entirely for relationship-create-only** flows:

- `filter` — additional filters for the query (same shape as policy filter). Useful if you want the KQ to enforce more constraints than the policy.
- `aggregate_values` — read-side concern.
- `upsert_nodes` — array of nodes to create or update. See [`indykite-ciq-create-node`](../../indykite-ciq-create-node/SKILL.md), or combine with this skill (see "Adapting for a fresh endpoint" in `SKILL.md`).
- `delete_nodes` / `delete_relationships` — deletion arrays.
- `batch_read` — read-timeout extender.

## Whitelist intersections

A relationship-create Knowledge Query succeeds only when **all** of these are true:

1. The policy's `condition.cypher` matches (subject + both endpoints resolve).
2. The policy's `condition.filter` (and `token_filter` if any) match.
3. Every `upsert_relationships[]` triple `(source-label, type, target-label)` is in the policy's `allowed_upserts.relationships.relationship_types`.
4. `source` and `target` in the KQ are **variable names** that exist in the policy's cypher.
5. `name` does not collide with an existing cypher variable.
6. No property in `upsert_relationships[].properties` is a protected name.
7. Every `$param` referenced in property values or metadata is present in the execute call's `input_params`.

If you are getting `403` or `422`, walk this list — items 3 and 4 cover the majority of cases.

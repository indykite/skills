# CIQ Knowledge Query Reference (add-relationship-property focused)

A Knowledge Query references a CIQ policy and declares what to do at runtime. This reference covers the relationship-property-write fields in detail and one-lines the rest.

## Skeleton (relationship-property-write-only)

```json
{
  "upsert_relationships": [
    {
      "name": "<cypher-variable-name>",
      "properties": [
        {
          "type":  "<property_name>",
          "value": "$<param-or-hardcoded-or-$token.claim>",
          "metadata": [ { "type": "<meta_name>", "value": "<value>" } ]
        }
      ]
    }
  ],
  "relationships": [ "<cypher-variable-name>" ]
}
```

What's **not** there compared with create-relationship: no `source`, no `target`, no `type` on the upsert entry. That's the structural difference that flips the operation from "create" to "set properties on the matched relationship".

## `upsert_relationships`

Array of relationship-update entries. One entry updates one matched relationship.

### `name`

**Must match a relationship variable from the policy's `cypher`** (e.g. `r`, `r1`, `r2`). The variable must also be in the policy's `allowed_upserts.relationships.existing_relationships`.

If you accidentally use a *fresh* name, the platform interprets the entry as a create — usually rejected because the matching `relationship_types` whitelist isn't there.

### `source` / `target` / `type` — omit for property writes

When updating an existing relationship, the endpoints and label are whatever the matched edge already has. Specifying any of these here flips the operation to "create" semantics.

### `properties`

Array of property entries on the matched relationship. Same shape as for nodes:

- `type` — property name. **Must be hardcoded** (no `$param`).
- `value` — property value. May be hardcoded, `$param`, or a `$token.<claim>` reference.
- `metadata` — *optional*. Array of `{type, value}` items for property-level metadata. Same rules.

Example with two properties:

```json
"upsert_relationships": [
  {
    "name": "r",
    "properties": [
      { "type": "verified",        "value": true },
      { "type": "first_played_at", "value": "$first_played_at",
        "metadata": [
          { "type": "source", "value": "$token.iss" },
          { "type": "assurance_level", "value": 2 }
        ]
      }
    ]
  }
]
```

### Property-set semantics

Setting a property is **upsert**:

- If the property doesn't exist on the relationship yet, it is added.
- If it exists, the value is overwritten.
- Metadata follows the same rule.

There is no separate "create property" vs "update property" call.

### Protected property names

These cannot be set as relationship properties — they are managed by the platform:

- `_service`
- `create_time`
- `id`
- `type` *(this is the relationship label, set on create only)*
- `update_time`

(`external_id` is not protected on relationships in the same way it is on nodes; relationships are identified by their endpoints and type, not by an `external_id`.)

## `relationships`

Top-level array. List the relationship variable name(s) here to **echo the relationship's `Props` in the response**:

```json
"relationships": ["r"]
```

You can also project specific properties via `<var>.<property>` paths.

## `nodes`

Top-level array. Optional — list endpoint property paths here if you want them echoed alongside the relationship update. Useful for confirming which endpoints the updated edge connects.

## Out-of-scope fields

These appear in the full Knowledge Query schema; **omit them entirely for relationship-property-write-only** flows:

- `filter` — additional KQ-level filters.
- `aggregate_values` — read-side concern.
- `upsert_nodes` — see [`indykite-ciq-add-property`](../../indykite-ciq-add-property/SKILL.md) (existing-node properties) or [`indykite-ciq-create-node`](../../indykite-ciq-create-node/SKILL.md) (new node).
- `delete_nodes` / `delete_relationships` — deletion arrays. See [`indykite-ciq-delete`](../../indykite-ciq-delete/SKILL.md).
- `batch_read` — read-timeout extender.

## Whitelist intersections

A relationship-property-write Knowledge Query succeeds only when **all** of these are true:

1. The policy's `condition.cypher` matches at least one relationship.
2. The policy's `condition.filter` (and `token_filter` if any) match.
3. Every `upsert_relationships[].name` is in the policy's `allowed_upserts.relationships.existing_relationships`.
4. No property in `upsert_relationships[].properties` is a protected name.
5. Every `$param` referenced in property values, metadata, or KQ-level filters is present in the execute call's `input_params`.

If you are getting `403`, walk items 3 and 4. If you are getting `200` with empty `data`, walk item 1.

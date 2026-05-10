# CIQ Knowledge Query Reference (add-property focused)

A Knowledge Query references a CIQ policy and declares what to do at runtime. This reference covers the property-write fields in detail and one-lines the rest.

## Skeleton (property-write-only)

```json
{
  "upsert_nodes": [
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
  "nodes": [ "<cypher-variable-name>.property.<property_name>" ]
}
```

Notice what's **not** there compared with create-node: no `type`, no `external_id` on the upsert entry. That's the structural difference that flips the operation from "create" to "set properties on the matched node".

## `upsert_nodes`

Array of node-update entries. One entry updates one matched node.

### `name`

**Must match a variable from the policy's `cypher`** (e.g. `subject`, `car`, `ln`). The variable must also be in the policy's `allowed_upserts.nodes.existing_nodes`.

If you accidentally use a *fresh* name (one not in cypher), the platform interprets the entry as a create — usually rejected because the matching `node_types` whitelist isn't there.

### `type` — omit for property writes

When updating an existing node, the label is whatever the matched node already has. Specifying `type` here (a la create) is unnecessary and can cause confusion.

### `external_id` — omit for property writes

`external_id` is required for *creating* a new node. For property writes on an already-matched node, omit it. Including it flips the operation to "create" semantics, which is rejected unless `node_types` covers the requested label.

### `properties`

Array of property entries. Each:

- `type` — property name. **Must be hardcoded** (no `$param`). Examples: `music_mood`, `dance_skill`, `status`, `license`.
- `value` — property value. May be hardcoded, `$param`, or a `$token.<claim>` reference (e.g. `$token.iss` for the issuer claim — used in the music-dataset metadata example to attribute provenance to the IdP that issued the caller's token).
- `metadata` — *optional*. Array of `{type, value}` items for property-level metadata. Same rules.

A real example from `knowledgeQueryMetaData` in the developer-hub resources data:

```json
"upsert_nodes": [
  {
    "name": "ln",
    "properties": [
      {
        "type":  "status",
        "value": "$status",
        "metadata": [
          { "type": "source",          "value": "$token.iss" },
          { "type": "assurance_level", "value": 2 },
          { "type": "somethingImportant", "value": "supercoolvalue" }
        ]
      },
      {
        "type":  "license",
        "value": "$ln_number",
        "metadata": [
          { "type": "source", "value": "The government" }
        ]
      }
    ]
  }
]
```

Two properties on the same matched `ln` node, each with its own metadata block. Some metadata values are `$param`, some are `$token.iss`, some are hardcoded. The variable `ln` comes from the policy's `MATCH (subject:Person)-[:OWNS]->(car:Car)-[:HAS]->(ln:LicenseNumber)` cypher.

### Property-set semantics

Setting a property is **upsert**:

- If the property doesn't exist on the node yet, it is added.
- If it exists, the value is overwritten.
- Metadata follows the same rule: a metadata key supplied here overwrites the previous metadata value for that key on that property.

There is no separate "create property" vs "update property" call.

### Protected property names

These cannot be set as properties — they are managed by the platform:

- `_service`
- `create_time`
- `external_id` *(protected on writes — set it via the dedicated field on the create path, not via `properties`)*
- `id`
- `type` *(this is the node label, set via the dedicated field on the create path)*
- `update_time`

Attempting to include any of these in `properties` is rejected. They appear in read responses inside the node's `Props` block alongside your custom properties — that's how you can tell the platform owns them.

## `nodes`

Top-level array. List the `<var>.property.<name>` paths you want to **echo in the response**, e.g. `subject.property.music_mood`. This is how you confirm in the response payload that the value was actually written.

You can also project the entire node by listing just the variable name (e.g. `["subject"]`); the response then includes the node's full `Props` block, including platform-managed fields.

## `filter` (Knowledge Query level — optional)

A KQ may add its own `filter` clause that further constrains the policy's match. Useful when a single policy authorises a class of writes but a specific KQ needs to lock onto one particular instance:

```json
"filter": {
  "attribute": "ln.external_id",
  "operator":  "=",
  "value":     "$ln_external_id"
}
```

This is what `knowledgeQueryMetaData` uses on top of `policyMetaData` to pin the LicenseNumber to update.

## Out-of-scope fields

These appear in the full Knowledge Query schema; **omit them entirely for property-write-only** flows:

- `relationships` / `aggregate_values` — read-side concerns.
- `upsert_relationships` — different skill ([`indykite-ciq-create-relationship`](../../indykite-ciq-create-relationship/SKILL.md)).
- `delete_nodes` / `delete_relationships` — deletion arrays.
- `batch_read` — read-timeout extender.

## Whitelist intersections

A property-write Knowledge Query succeeds only when **all** of these are true:

1. The policy's `condition.cypher` resolves to at least one node.
2. The policy's `condition.filter` (and `token_filter` if any) match.
3. Every `upsert_nodes[].name` is in the policy's `allowed_upserts.nodes.existing_nodes`.
4. No property in `upsert_nodes[].properties` is a protected name.
5. Every `$param` referenced in property values, metadata, or the KQ's `filter` is present in the execute call's `input_params`.

If you are getting `403`, walk items 3 and 4. If you are getting `200` with empty `data`, walk item 1.

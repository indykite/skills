# CIQ Knowledge Query Reference (create-node focused)

A Knowledge Query references a CIQ policy and declares what to do at runtime. This reference covers the create-relevant fields in detail and one-lines the rest.

For the read-focused variant, see [`indykite-ciq-read/references/knowledge-query-reference.md`](../../indykite-ciq-read/references/knowledge-query-reference.md).

## Skeleton (create-only)

```json
{
  "upsert_nodes": [
    {
      "name":        "<fresh-variable-name>",
      "type":        "<NodeLabel>",
      "external_id": "$<param>",
      "properties": [
        {
          "type":  "<property_name>",
          "value": "$<param-or-hardcoded>",
          "metadata": [ { "type": "<meta_name>", "value": "<value>" } ]
        }
      ]
    }
  ],
  "nodes": [ "<fresh-variable-name>" ]
}
```

For a create-only Knowledge Query, only these fields appear. The other arrays (`filter`, `relationships`, `aggregate_values`, `upsert_relationships`, `delete_*`) are listed at the bottom for context but should be **omitted**.

## `upsert_nodes`

Array of node-create entries. One entry creates one node.

### `name`

Variable name for the node. Two rules:

- **Creating a new node** (this skill): use a **fresh** name not present in the policy's `cypher`. Convention: prefix with `new`, e.g. `newTrack`, `newCustomer`, or use a domain-specific noun like `track` if it's not already a cypher variable.
- **Updating an existing node** (different skill): use the variable name from the policy's `cypher` (e.g. `subject`). Out of scope here.

If you accidentally re-use a cypher variable name when creating, the request will be interpreted as an in-place update on that match — usually rejected because `existing_nodes` was not declared.

### `type`

The node label. **Must** appear in the policy's `allowed_upserts.nodes.node_types`. If the policy whitelists `["Track"]` and the Knowledge Query says `"type": "Album"`, the request is rejected.

### `external_id`

The new node's stable identifier in the IKG.

- **Required for creation.** Omit only when updating an existing node.
- Hardcode the value (`"track-99"`) for one-off writes — rare, and means the Knowledge Query can only be executed once per `external_id`.
- Use `$param` (`"$track_external_id"`) for the common case so the caller supplies the value at execute time.

If the same `external_id` is supplied a second time, the request is treated as an **upsert** (update) on the existing node — not a duplicate-create error.

### `properties`

Array of property entries. Each:

- `type` — property name. **Must be hardcoded** (no `$param`). Example: `"title"`, `"loudness"`.
- `value` — property value. May be hardcoded or `$param`. Type matches the IKG schema for that property (string, number, boolean, etc.).
- `metadata` — optional. Array of `{type, value}` items for property metadata (e.g. source, confidence, timestamp). Same rules: `type` hardcoded, `value` may be `$param`.

Example:

```json
"properties": [
  { "type": "title",    "value": "$track_title" },
  { "type": "loudness", "value": "$track_loudness" },
  { "type": "imported_at",
    "value": "$import_timestamp",
    "metadata": [ { "type": "source", "value": "etl-pipeline-v3" } ]
  }
]
```

### Protected property names

These cannot be set as properties — they are managed by the platform:

- `_service`
- `create_time`
- `external_id` *(already set via the dedicated field above; not via `properties`)*
- `id`
- `type` *(this is the node label, set via the dedicated field above)*
- `update_time`

Attempting to include any of these in `properties` is rejected.

## `nodes`

Top-level array. List the `upsert_nodes[].name` here to **echo the newly-created node back in the response**. Without it, the response will succeed but contain no projection of the new node.

```json
"nodes": ["newTrack"]
```

You can also list specific properties (`"newTrack.property.title"`) to slim the response payload.

## Out-of-scope fields (writes-of-other-kinds)

These appear in the full Knowledge Query schema; **omit them entirely for create-only-node** flows:

- `filter` — additional filters for the query (same shape as policy filter). Useful when you want one Knowledge Query to apply more constraints than the policy alone.
- `relationships` — relationship variables from policy `cypher` to project. Read-side concern.
- `aggregate_values` — aggregate variables from policy `cypher`. Read-side concern.
- `upsert_relationships` — array of relationships to create or update. Different skill (relationship-write).
- `delete_nodes` / `delete_relationships` — deletion arrays. Different skill (delete).
- `batch_read` — extends the read timeout. Read-side concern.

## Whitelist intersections

A create-node Knowledge Query succeeds only when **all** of these are true:

1. The policy's `condition.cypher` matches (the subject anchor resolves).
2. The policy's `condition.filter` (and `token_filter` if any) match.
3. Every `upsert_nodes[].type` is in the policy's `allowed_upserts.nodes.node_types`.
4. No property in `upsert_nodes[].properties` is a protected name.
5. Every `$param` referenced in `external_id`, `value`, or metadata `value` is present in the execute call's `input_params`.

If you are getting `403` or `422`, walk this list — items 3 and 5 cover the majority of cases.

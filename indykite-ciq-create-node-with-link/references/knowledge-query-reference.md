# CIQ Knowledge Query Reference (create-node-with-link focused)

A combined-create Knowledge Query uses **both** `upsert_nodes` and `upsert_relationships` arrays. The platform processes them as one atomic operation: every entry must succeed, or none do.

For the single-operation variants see [`indykite-ciq-create-node`](../../indykite-ciq-create-node/references/knowledge-query-reference.md) and [`indykite-ciq-create-relationship`](../../indykite-ciq-create-relationship/references/knowledge-query-reference.md).

## Skeleton

```json
{
  "upsert_nodes": [
    {
      "name":        "<fresh-name>",
      "type":        "<NewLabel>",
      "external_id": "$<param>",
      "properties":  [ { "type": "<prop>", "value": "$<param>" } ]
    }
  ],
  "upsert_relationships": [
    {
      "name":   "<fresh-name>",
      "source": "<cypher-variable OR upsert_nodes name>",
      "target": "<cypher-variable OR upsert_nodes name>",
      "type":   "<RELATIONSHIP_LABEL>"
    }
  ],
  "nodes":         [ "<projection>" ],
  "relationships": [ "<projection>" ]
}
```

## `upsert_nodes`

Same shape as in the create-node skill. Each entry creates one node:

- `name` — fresh variable name (not in cypher, not used elsewhere in `upsert_nodes`).
- `type` — new node label, in the policy's `allowed_upserts.nodes.node_types`.
- `external_id` — required for new nodes; usually `$param`.
- `labels` — optional array of additional labels attached alongside `type`.
  - **Identity nodes:** `"labels": ["DigitalTwin"]` creates the node as an **identity node** — the same result as `is_identity: true` in the Capture API, which is shorthand for adding this label at ingest. Required whenever the node will act as a `2.0-kbac` authorization subject; a non-identity subject makes every `2.0-kbac` decision silently `false` (`3.0-kbac` matches by type and `external_id` and does not need it).
  - Labels are **not** checked against the policy's `node_types` whitelist — only `type` is.
- `properties` — array of `{type, value, metadata?}` items. `type` (property name) hardcoded; `value` may be `$param`.

## `upsert_relationships`

Same shape as in the create-relationship skill, with one important enhancement: `source` and `target` may reference **either**:

- a variable name from the policy's `cypher` (an existing node), **or**
- a `name` from this Knowledge Query's `upsert_nodes` (a node being created in the same execute).

This is what makes the combined operation atomic — you can wire the new node up to existing context in one call.

The running example creates one new `Contract` and two new relationships:

```json
"upsert_nodes": [
  {
    "name":        "contract",
    "type":        "Contract",
    "external_id": "$contract_external_id",
    "properties":  [
      { "type": "number", "value": "$contractNumber" },
      { "type": "status", "value": "Active" }
    ]
  }
],
"upsert_relationships": [
  {
    "name":   "r3",
    "source": "contract",   // ← from upsert_nodes — the new node
    "target": "vehicle",    // ← from cypher — the existing Vehicle
    "type":   "COVERS"
  },
  {
    "name":   "r4",
    "source": "person",     // ← from cypher — the existing Person
    "target": "contract",   // ← from upsert_nodes — the new node
    "type":   "ACCEPTED"
  }
]
```

`r3` connects `contract` (new) to `vehicle` (existing). `r4` connects `person` (existing) to `contract` (new). Both directions are valid as long as the policy whitelists the matching `(source-label, type, target-label)` triple.

### Cross-reference rules

- The string in `upsert_relationships[].source` (or `target`) must match **exactly** one of:
  - a variable name in the policy's `cypher` (then the relationship goes to that existing node), or
  - a `name` in `upsert_nodes` (then the relationship goes to the just-created node).
- A typo here is the most common silent failure mode. The platform may accept the call but produce wiring you didn't intend.

### Multiple new relationships referencing the same new node

Common pattern: one new node linked to several existing nodes. Each `upsert_relationships` entry independently references the new node by its `name`:

```json
"upsert_nodes": [
  { "name": "contract", "type": "Contract", "external_id": "$cid", "properties": [...] }
],
"upsert_relationships": [
  { "name": "r3", "source": "contract", "target": "vehicle", "type": "COVERS" },
  { "name": "r4", "source": "person",   "target": "contract", "type": "ACCEPTED" },
  { "name": "r5", "source": "company",  "target": "contract", "type": "ISSUED_BY" }
]
```

All three new relationships are created in one execute, alongside the new `contract`. Each must match a triple in the policy's `relationship_types`.

## `nodes` and `relationships`

Top-level projection arrays. Echo the new node and new relationships back in the response for confirmation:

```json
"nodes":         ["contract.external_id", "contract.property.number"],
"relationships": ["r3", "r4"]
```

You can also project existing endpoints (`vehicle.external_id`, `person.external_id`) for a richer audit trail — they don't need to be in the policy's `allowed_reads` if they're already in the cypher (but check; some configurations do require it).

## Atomicity

The platform applies all `upsert_nodes` and `upsert_relationships` in one transaction. If any single entry fails (e.g. one `relationship_types` triple isn't whitelisted), the whole call fails — none of the writes happen.

## Out-of-scope fields

Omit for a pure combined-create:

- `delete_nodes` / `delete_relationships`
- `aggregate_values`
- `batch_read`
- `filter` (unless you genuinely need an additional KQ-level filter on top of the policy's)

## Whitelist intersections

A combined-create succeeds only when **all** of these are true:

1. The policy's cypher matches all required existing endpoints.
2. The policy's filter (and `token_filter` if any) match.
3. Every `upsert_nodes[].type` is in `allowed_upserts.nodes.node_types`.
4. Every `upsert_relationships[]` triple is in `allowed_upserts.relationships.relationship_types`.
5. Every `source` / `target` string in `upsert_relationships` resolves to either a cypher variable or an `upsert_nodes` `name`.
6. No property in either array is a protected name (`_service`, `create_time`, `external_id`, `id`, `type`, `update_time`).
7. Every `$param` referenced is in `input_params`.

If any of these fails, the entire transaction fails.

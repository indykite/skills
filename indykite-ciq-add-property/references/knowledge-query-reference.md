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

**Checked metadata values.** Three metadata types have a fixed value shape: `assurance_level` must be `1`, `2` or `3`; `verified_time` must be an RFC 3339 timestamp string; `source` must be a string. Other metadata types are not checked. A hardcoded value of the wrong shape is refused when the Knowledge Query is saved (`invalid <type> for node <name>`). A `$param` value is checked on execute, before anything is written: a wrong value writes nothing and answers `422` with `invalid_argument: invalid <type> metadata value in input params, '$<param>'`. (Since platform release 2.86.2; before, such a value failed with `500` or was stored unchecked.)

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

This is what `knowledgeQueryMetaData` uses on top of `policyMetaData` to pin the LicenseNumber to update. Under a `2.0-ciq` policy the attribute is written `"@ln.external_id"` - see [`policy-reference.md`](policy-reference.md#metapolicy_version).

## v2 only: copying graph values with `@` references

With a `2.0-ciq` policy ([`policy-reference.md`](policy-reference.md#metapolicy_version)), a property `value` in `upsert_nodes` or `upsert_relationships` may be an **`@` reference** to a value the policy's Cypher matched, instead of a literal or a `$param`. The platform reads every referenced value first, for the rows the condition matched, then writes; each upserted element gets the value found for its row.

| Form | Example |
|------|---------|
| `@<var>.<attr>` - an attribute of a node or relationship variable | `@subject.external_id`, `@owns.since` |
| `@<var>.property.<name>` - a property of a node | `@subject.property.email` |
| `@<var>.property.<name>.metadata.<field>` - metadata of that property | `@subject.property.country.metadata.source` |
| `@<var>.trust_score.<field>` - a trust score of a node | `@subject.trust_score._final_score` |
| `@<alias>` - an aggregate value projected with `AS` | `@numContracts` |

A policy that lets a person stamp their own node with values the graph already holds, and the query that does it:

```json
{
  "meta": { "policy_version": "2.0-ciq" },
  "subject": { "type": "Person" },
  "condition": {
    "cypher": "MATCH (subject:Person)-[:MEMBER_OF]->(group:Group) WITH subject, group",
    "filter": [ { "attribute": "@subject.external_id", "operator": "=", "value": "$token.sub" } ]
  },
  "allowed_upserts": { "nodes": { "existing_nodes": ["subject"] } },
  "allowed_reads": { "nodes": ["subject.*"] }
}
```

```json
{
  "nodes": ["subject.property.level", "subject.property.source"],
  "upsert_nodes": [
    {
      "name": "subject",
      "properties": [
        { "type": "level", "value": "@group.property.level" },
        { "type": "source", "value": "@subject.property.country.metadata.source" },
        { "type": "verified_by", "value": "$token.cname" }
      ]
    }
  ]
}
```

Rules, checked when the Knowledge Query is saved:

- A reference points at a variable of the policy's Cypher that is in scope at its end - never at a node or relationship the query itself creates, since the values are read before anything is written: `upsert value @<ref> must reference a variable of the policy cypher`.
- A bare variable is allowed only for an aggregate alias; a node or relationship needs an attribute, property, metadata or trust-score path: `upsert value @<ref> must reference an attribute, a property, a trust score or an aggregate value`. A path of another shape is `invalid upsert value @<ref>: …`, and every name in the path must be a letter or underscore followed by letters, digits or underscores: `invalid upsert value @<ref>: invalid name <name>`.
- A token claim is not read from the graph: write `$token.<claim>`, or the save is refused with `upsert value @token.<claim> references a token claim, use token.<claim> instead`.
- When a query uses `@` references, no Cypher variable and no upserted node or relationship `name` may start with `__ref_`: `name <name> must not start with __ref_ when upsert values use @ references`.
- Only property `value`s take a reference; `external_id`, `type`, metadata values and `external_value` do not. A literal that starts with `@` or `$` is written `\@…` or `\$…` (inside a JSON string `"\\@…"`); the escape is dropped.

At execute time a reference whose value is null for a row - for example a property the matched node lacks - writes nothing for that property: a node property is left out, a relationship property left as it was. When several matched rows feed one upserted element, the first value found is written.

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

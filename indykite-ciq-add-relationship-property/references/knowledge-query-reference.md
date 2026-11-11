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
          "value": "$<param-or-hardcoded-or-$token.claim>"
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

Array of property entries on the matched relationship:

- `type` — property name. **Must be hardcoded** (no `$param`).
- `value` — property value. May be hardcoded, `$param`, or a `$token.<claim>` reference.

Relationship properties carry **no `metadata`** — property metadata exists only on node properties. A relationship property with a `metadata` key is refused as an unknown field when the Knowledge Query is saved. To record provenance (`source`, `assurance_level`, …), put it on a node property instead (see [`indykite-ciq-add-property`](../../indykite-ciq-add-property/SKILL.md)).

Example with two properties:

```json
"upsert_relationships": [
  {
    "name": "r",
    "properties": [
      { "type": "verified",        "value": true },
      { "type": "first_played_at", "value": "$first_played_at" }
    ]
  }
]
```

### Property-set semantics

Setting a property is **upsert**:

- If the property doesn't exist on the relationship yet, it is added.
- If it exists, the value is overwritten.

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
- A token claim is not read from the graph: write `$token.<claim>`, and an `@` in front of it is refused when the query is saved, with `upsert value @$token.<claim> references a token claim, use $token.<claim> instead` (the same for `$ik_token`).
- When a query uses `@` references, no Cypher variable and no upserted node or relationship `name` may start with `__ref_`: `name <name> must not start with __ref_ when upsert values use @ references`.
- A variable-length relationship (`-[r:REL*1..2]->`) cannot be referenced: the execute answers `424` (see [`policy-reference.md`](policy-reference.md#metapolicy_version)).
- Only property `value`s take a reference; `external_id`, `type`, metadata values and `external_value` do not. A literal that starts with `@` or `$` is written `\@…` or `\$…` (inside a JSON string `"\\@…"`); the escape is dropped.

At execute time a reference whose value is null for a row - for example a property the matched node lacks - writes nothing for that property: a node property is left out, a relationship property left as it was. When several matched rows feed one upserted element, the first value found is written.

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
4. No property in `upsert_relationships[].properties` is a protected name or carries `metadata`.
5. Every `$param` referenced in property values or KQ-level filters is present in the execute call's `input_params`.

If you are getting `403`, walk items 3 and 4. If you are getting `200` with empty `data`, walk item 1.

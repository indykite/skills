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
- `is_identity` — optional boolean. `true` creates the node as an **identity node** — the same flag as in the Capture API; it adds the `DigitalTwin` label. Prefer it over `"labels": ["DigitalTwin"]`, which gives the same result but stores a misspelt label silently, while a misspelt key is refused when the Knowledge Query is saved.
- `labels` — optional array of additional labels attached alongside `type`.
  - **Identity nodes:** `"is_identity": true` (or `"labels": ["DigitalTwin"]`) is required whenever the node will act as a `2.0-kbac` authorization subject; a non-identity subject makes every `2.0-kbac` decision silently `false` (`3.0-kbac` matches by type and `external_id` and does not need it).
  - Labels are **not** checked against the policy's `node_types` whitelist — only `type` is.
- `properties` — array of `{type, value, metadata?}` items. `type` (property name) hardcoded; `value` may be `$param`.

**Checked metadata values.** Three metadata types have a fixed value shape: `assurance_level` must be `1`, `2` or `3`; `verified_time` must be an RFC 3339 timestamp string; `source` must be a string. Other metadata types are not checked. A hardcoded value of the wrong shape is refused when the Knowledge Query is saved (`invalid <type> for node <name>`). A `$param` value is checked on execute, before anything is written: a wrong value writes nothing and answers `422` with `invalid_argument: invalid <type> metadata value in input params, '$<param>'`.

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

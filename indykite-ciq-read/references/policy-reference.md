# CIQ Policy Reference (read-focused)

This reference covers the fields a read-only CIQ policy uses, plus the parts of the schema you need to recognize even if you do not write them (so you can tell whether an existing policy is read-only or not).

## Skeleton

```json
{
  "meta":      { "policy_version": "1.0-ciq" },
  "subject":   { "type": "<Person | User | _Application | ...>" },
  "condition": {
    "cypher": "<MATCH … WHERE …>",
    "filter": [ { ... } ],
    "token_filter": { ... }
  },
  "allowed_reads": {
    "nodes":             [ "<var>", "<var>.*", "<var>.property.<name>" ],
    "relationships":     [ "<var>", "<var>.*" ],
    "aggregate_values":  [ "<aggregate-var>" ]
  }
}
```

For a read-only policy: include `meta`, `subject`, `condition`, `allowed_reads`. **Omit** `allowed_upserts` and `allowed_deletes` — that is the supported way to forbid writes.

## `meta.policy_version`

Currently `1.0-ciq`. IndyKite rejects unknown versions.

## `subject.type`

The node type that authenticates the request. **Exactly one** type per policy. Examples:

- `Person` / `User` — the request is on behalf of a human; `subject_id` is the Bearer token's `sub` claim.
- `_Application` — the request is on behalf of an application. Add a filter `attribute: subject.external_id`, `value: $_appId` (reserved). `$_appId` is auto-filled from the AppAgent at execution time.

If two subject types need read access to the same shape, write two policies.

## `condition.cypher`

The graph pattern. Supports `MATCH`, `OPTIONAL MATCH`, `WHERE`, `WITH`, aggregate functions, and inline property filters. Every node and relationship the policy or Knowledge Query references must have a **variable name** here.

```cypher
MATCH (subject:Person)-[r:OWNS]->(car:Car)
```

Variables: `subject`, `r`, `car`. These names are what `condition.filter`, `allowed_reads`, and the Knowledge Query's `nodes` / `relationships` keys reference.

Aggregate example:

```cypher
MATCH (subject:Person)-[:OWNS]->(car:Car)
WITH subject, COLLECT({ plate: car.property.license_plate.value }) AS plates
```

`plates` is an `aggregate_values` variable; it can be returned but cannot appear in `nodes` / `relationships`.

## `condition.filter`

Optional array of filters that constrain the match. Each filter is an object with:

- `operator` — one of the operators in the table below.
- `attribute` — the attribute being compared. Omit for boolean operators (`AND`, `OR`, `NOT`).
- `value` — the comparison value, hard-coded or `$varname` for a partial filter. Omit for boolean operators.
- `operands` — array of nested filters. Used with boolean operators.

### Supported operators

| Operator       | Meaning                                                | Operands                |
|----------------|--------------------------------------------------------|-------------------------|
| `NOT`          | Negates the nested filter                              | exactly 1 nested filter |
| `AND`          | All nested filters must match                          | 1 or more               |
| `OR`           | Any nested filter must match                           | 1 or more               |
| `=`            | `attribute` equals `value`                              | —                       |
| `<>`           | `attribute` does not equal `value`                      | —                       |
| `>`, `<`       | greater than / less than                               | —                       |
| `>=`, `<=`     | greater than or equal / less than or equal             | —                       |
| `IN`           | `attribute` is in `value` array                         | —                       |
| `=~`           | `attribute` matches regex `value`                       | —                       |
| `STARTS WITH`  | `attribute` starts with `value`                         | —                       |
| `ENDS WITH`    | `attribute` ends with `value`                           | —                       |
| `IS NULL`      | `attribute` is missing or null                          | —                       |
| `IS NOT NULL`  | `attribute` is present and not null                     | —                       |

### Attribute naming conventions

| Pattern                                       | Meaning                                  | Example                                |
|-----------------------------------------------|------------------------------------------|----------------------------------------|
| `$token.<property>`                           | Property on the requestor token          | `$token.acr`                           |
| `<var>.<attr>`                                | Attribute on a node or relationship      | `subject.external_id`                  |
| `<var>.property.<name>`                       | Named property on a node                  | `subject.property.email`               |
| `<var>.property.<name>.metadata.<meta>`       | Metadata on a property                    | `subject.property.email.metadata.source` |

`<var>` is the variable from `cypher`. Typos here silently match nothing.

### Static vs. partial filters

- **Static filter** — `value` is hard-coded (e.g. `"value": "active"`). Burned into the policy.
- **Partial filter** — `value` starts with `$` (e.g. `"value": "$person_external_id"`). The execution call must supply this in `input_params` (without the `$`).

## `condition.token_filter`

Same shape as `filter` but only references `$token.*` attributes. When a `token_filter` does not match, the response includes a `WWW-Authenticate: insufficient_user_authentication` header carrying the `advice.error` and `advice.error_description` you set on the failing leaf — useful for OAuth step-up flows.

Omit `token_filter` if you have no token-related conditions.

## `allowed_reads`

Whitelists what the **Knowledge Query** is allowed to return. Three keys:

- `nodes` — node variables. `<var>` returns the node identity; `<var>.*` allows any property of the node; `<var>.property.<name>` allows one specific property.
- `relationships` — relationship variables; same wildcard rules.
- `aggregate_values` — variables produced by aggregate functions in `cypher`.

If `allowed_reads` does not list a variable, the Knowledge Query cannot return it — `nodes` / `relationships` / `aggregate_values` in the Knowledge Query are intersected against this whitelist before the query runs.

Example matching the running `Person -[:OWNS]-> Car` use case:

```json
"allowed_reads": {
  "nodes": ["subject", "subject.*", "car", "car.*"],
  "relationships": ["r"]
}
```

## What `allowed_upserts` / `allowed_deletes` would do (and why we omit them)

For completeness — these are out of scope for read-only:

- `allowed_upserts.nodes.existing_nodes` — variables from `cypher` whose properties may be updated.
- `allowed_upserts.nodes.node_types` — node labels the Knowledge Query may **create**.
- `allowed_upserts.relationships.existing_relationships` — relationship variables whose properties may be updated.
- `allowed_upserts.relationships.relationship_types` — `[{type, source_node_label, target_node_label}]` triples that may be created.
- `allowed_deletes.nodes` — variables (or `<var>.*`) the Knowledge Query may delete.
- `allowed_deletes.relationships` — same for relationships.

Omitting these blocks is the supported way to enforce read-only — the Knowledge Query's `upsert_*` / `delete_*` arrays must intersect with these whitelists, and an empty intersection means writes are rejected at execute time.

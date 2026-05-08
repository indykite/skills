# CIQ Knowledge Query Reference (read-focused)

A Knowledge Query references a CIQ policy and declares what to do at runtime. This reference covers the read-relevant fields in detail and one-lines the rest so you can recognize them in existing queries.

## Skeleton (read-only)

```json
{
  "filter": { ... },
  "nodes":            [ "<var>", "<var>.property.<name>", ... ],
  "relationships":    [ "<var>", ... ],
  "aggregate_values": [ "<aggregate-var>", ... ],
  "batch_read":       false
}
```

For a read-only Knowledge Query, only these fields appear. The `upsert_*` and `delete_*` arrays are listed below for context but **must be omitted** in the read case.

## `filter`

Optional. Same structure as the policy's `condition.filter` (operators, attribute conventions, `$variable` partial filters). Use this for filters that belong to a *specific Knowledge Query* rather than the policy as a whole.

A common pattern is to put the structural filter (`subject.external_id = $person_external_id`) in the **policy** and use the Knowledge Query's `filter` for query-specific shaping (e.g. limiting by `car.property.year > $min_year`). But putting all filters in the policy is also valid — there is no functional difference if only one query references the policy.

Omit if empty.

## `nodes`

Array of node variable names (or `<var>.property.<name>`) to include in the response. Each entry must:

- Match a node variable from the **policy's** `condition.cypher` (or a `name` from `upsert_nodes`, which we are not using here).
- Be allowed by the **policy's** `allowed_reads.nodes`. The intersection is what gets returned.

Example: `["subject", "car"]` returns both nodes; `["subject.property.email", "car.property.license_plate"]` returns only those two property values.

## `relationships`

Same as `nodes`, but for relationship variables. Must intersect with `allowed_reads.relationships`.

## `aggregate_values`

Array of variable names from aggregate functions defined in the policy's `condition.cypher` (e.g. `WITH subject, COLLECT({plate: car.property.license_plate.value}) AS plates` → `["plates"]`). Must intersect with `allowed_reads.aggregate_values`.

Aggregate variables cannot appear in `nodes` or `relationships`.

## `batch_read`

Optional boolean, default `false`.

- `false` — default timeout applies (a few seconds).
- `true` — timeout raised to **5 minutes (300 seconds)**.

When to set `true`:

- Large result sets that risk the default timeout.
- Complex graph traversals with significant Cypher work.

When **not** to set `true`:

- Small, fast queries — there is no benefit and the longer ceiling masks regressions.

## Out of scope (write fields)

These appear in the full Knowledge Query schema; **omit them entirely for read-only**.

- `upsert_nodes` — array of nodes to create or update. Each item: `{ name, type, external_id, properties: [{ type, value, metadata }] }`.
- `upsert_relationships` — array of relationships to create or update. Each item: `{ name, source, target, type, properties }`.
- `delete_nodes` — array of node variable names to delete (e.g. `"car"`, `"car.property.model"`).
- `delete_relationships` — array of relationship variable names to delete (e.g. `"r"`, `"r.status"`).

Protected properties that cannot be deleted at all: `_service`, `create_time`, `external_id`, `id`, `type`, `update_time`.

## Whitelist intersections (worth re-reading)

A read-only Knowledge Query returns rows that satisfy **all** of these:

1. The policy's `condition.cypher` matches.
2. The policy's `condition.filter` (and `token_filter`, if any) match.
3. The Knowledge Query's `filter` (if present) matches.
4. Every variable named in the Knowledge Query's `nodes` / `relationships` / `aggregate_values` is also listed in the policy's `allowed_reads`.

If you are getting unexpected empty results, walk this list — most often it is item 4 (a variable in the Knowledge Query that isn't whitelisted in the policy).

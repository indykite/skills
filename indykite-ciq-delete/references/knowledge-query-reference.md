# CIQ Knowledge Query Reference (delete focused)

A Knowledge Query references a CIQ policy and declares what to do at runtime. This reference covers the delete-relevant fields in detail.

## Skeleton (delete-only)

```json
{
  "delete_nodes":         [ "<entry>", "<entry>", ... ],
  "delete_relationships": [ "<entry>", "<entry>", ... ]
}
```

A delete KQ may include either or both arrays. Other arrays (`filter`, `nodes`, `relationships`, `aggregate_values`, `upsert_nodes`, `upsert_relationships`, `batch_read`) should be **omitted** for a delete-only flow.

## `delete_nodes`

Array of entries. Each entry is one of:

- `<var>` — delete the whole node bound to that variable in the policy's `cypher`.
- `<var>.property.<name>` — delete only the named property on that node.
- `<var>.*` — wildcard: delete *every* property of that node (the node itself stays). Use sparingly; combine with a tight `condition.filter`.

Each entry must appear (or be implied by a wildcard) in the policy's `allowed_deletes.nodes`.

## `delete_relationships`

Array of entries. Each entry is one of:

- `<var>` — delete the whole relationship bound to that variable.
- `<var>.<property>` — delete only the named property on that relationship. (Note: no `.property.` segment in the relationship form — `r.status`, not `r.property.status`.)
- `<var>.*` — wildcard for all properties.

Each entry must appear (or be implied by a wildcard) in the policy's `allowed_deletes.relationships`.

## Multi-delete in one execute

A single Knowledge Query may delete several things at once. For example, a "right to be forgotten" KQ might delete several properties on the user's Person node *and* one relationship in the same call:

```json
{
  "delete_nodes": [
    "subject.property.music_mood",
    "subject.property.dance_skill"
  ],
  "delete_relationships": [
    "r"
  ]
}
```

Provided the policy whitelists every entry, the platform applies all deletes atomically as part of a single execute.

## Protected property names — cannot be deleted

| Field            | Why                                                                            |
|------------------|--------------------------------------------------------------------------------|
| `_service`       | Platform-managed identifier of the service that owns the node.                  |
| `create_time`    | Platform-managed timestamp.                                                     |
| `external_id`    | Stable identifier; deleting it would orphan the node. Delete the whole node instead. |
| `id`             | Internal graph identifier.                                                       |
| `type`           | Node label / relationship type. Inseparable from the element.                    |
| `update_time`    | Platform-managed timestamp.                                                     |

Including any of these in `delete_nodes` or `delete_relationships` is rejected.

## Idempotence

Deleting an already-missing property is **not** an error. The KQ returns `200` and the `data` array reflects what was actually deleted (often empty or near-empty). This makes deletes safe to retry.

Deleting a node also deletes all relationships incident to that node — you don't need to enumerate them. The same idempotence applies.

## Out-of-scope fields

`filter`, `nodes`, `relationships`, `aggregate_values`, `upsert_nodes`, `upsert_relationships`, `batch_read` — all read or write fields. Omit them in a delete-only KQ.

## Whitelist intersections

A delete KQ succeeds only when **all** of these are true:

1. The policy's `condition.cypher` resolves to at least one element.
2. The policy's `condition.filter` (and `token_filter` if any) match.
3. Every entry in `delete_nodes` is in the policy's `allowed_deletes.nodes` (literally or via a wildcard).
4. Every entry in `delete_relationships` is in the policy's `allowed_deletes.relationships`.
5. No entry targets a protected property.
6. Every `$param` referenced in the policy filter is in `input_params`.

If you are getting `403`, walk items 3, 4, and 5. If you are getting `200` with empty `data`, walk item 1.

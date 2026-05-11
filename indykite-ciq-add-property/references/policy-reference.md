# CIQ Policy Reference (add-property focused)

This reference covers the fields a *property-write-only* CIQ policy uses, plus the parts of the schema you need to recognise even if you do not write them.

For node creation see [`indykite-ciq-create-node/references/policy-reference.md`](../../indykite-ciq-create-node/references/policy-reference.md). For relationship creation see [`indykite-ciq-create-relationship/references/policy-reference.md`](../../indykite-ciq-create-relationship/references/policy-reference.md). For reads see [`indykite-ciq-read/references/policy-reference.md`](../../indykite-ciq-read/references/policy-reference.md).

## Top-level structure

The policy has four top-level keys, all siblings:

| Key                | Use                                                                                                       |
|--------------------|-----------------------------------------------------------------------------------------------------------|
| `meta`             | Set `policy_version: "1.0-ciq"`.                                                                           |
| `subject`          | Set `type` to the authenticating entity (e.g. `Person`, `_Application`).                                   |
| `condition`        | Match the subject and the node whose properties will change; pin it with a filter.                          |
| `allowed_upserts`  | Use `nodes.existing_nodes` to whitelist the cypher variables whose node properties the KQ may set.          |

When adapting to a new domain, only the *contents* of `condition` and `allowed_upserts.nodes.existing_nodes` change; the four-key structure stays the same.

## Skeleton

```json
{
  "meta":      { "policy_version": "1.0-ciq" },
  "subject":   { "type": "<Person | _Application | …>" },
  "condition": {
    "cypher": "<MATCH that resolves the node to update>",
    "filter": [ { ... } ]
  },
  "allowed_upserts": {
    "nodes": {
      "existing_nodes": [ "<cypher-variable-name>" ]
    }
  }
}
```

For a property-write-only policy: include `meta`, `subject`, `condition`, and `allowed_upserts.nodes.existing_nodes`. **Omit** `allowed_reads`, `allowed_deletes`, and the other `allowed_upserts` sub-fields. Omitting a block is the supported way to forbid that operation.

It is **common** in real deployments to combine `existing_nodes` with `allowed_reads.nodes` so the same policy lets a caller read and update the same node — that's exactly what music-dataset `ciqpolicy4` does ("Read and Update Own Profile"). This skill keeps the runnable example write-only for clarity; combining is straightforward (just add the `allowed_reads` block).

## `meta.policy_version`

Currently `1.0-ciq`. IndyKite rejects unknown versions.

## `subject.type`

Exactly one type per policy. Two patterns dominate:

### Person / User — "update own data"

```json
"subject": { "type": "Person" },
"condition": {
  "cypher": "MATCH (subject:Person)",
  "filter": [
    { "operator": "=", "attribute": "subject.external_id", "value": "$token.sub" }
  ]
}
```

The Bearer token's `sub` claim is the only identity input — there is no client-supplied `subject_external_id`. Without the `$token.sub` clause, `MATCH (subject:Person)` would match every Person in the graph; pinning it to the verified token claim ensures the caller can only write to their own data. This is the music-dataset `ciqpolicy4` pattern.

For deeper updates (e.g. update a property on a Car owned by the caller), extend the cypher:

```cypher
MATCH (subject:Person)-[:OWNS]->(car:Car)-[:HAS]->(ln:LicenseNumber)
```

…and add filters constraining the specific Car or LicenseNumber, e.g. `ln.external_id = $ln_external_id`. `existing_nodes` then names whichever variable should be writable: `["car"]` or `["ln"]`.

### `_Application` — system-side property writes

```json
"subject": { "type": "_Application" },
"condition": {
  "cypher": "MATCH (subject:_Application)",
  "filter": [
    { "operator": "=", "attribute": "subject.external_id", "value": "$_appId" }
  ]
}
```

`$_appId` is reserved — the platform substitutes the calling AppAgent's `external_id`. Do **not** pass it in `input_params`. `_Application` requires only the `X-IK-ClientKey` header at execute time; no Bearer.

If two subject types should both be allowed to update the same node, write two policies.

## `condition.cypher`

The `MATCH` clause must resolve the **node you want to update**. The variable name you use here is what `existing_nodes` and the Knowledge Query's `upsert_nodes[].name` will reference.

Three common shapes:

```cypher
MATCH (subject:Person)
```

— update the subject node itself (own profile).

```cypher
MATCH (subject:_Application)-[:USES]->(car:Car)
```

— update a node connected to the subject by an existing relationship.

```cypher
MATCH (subject:Person)-[:OWNS]->(car:Car)-[:HAS]->(ln:LicenseNumber)
```

— update a node deeper in the graph; usually paired with a filter on the deeper variable's `external_id` to disambiguate.

Each variable defined here is a **string identifier** the Knowledge Query's `upsert_nodes` will use as `name`. Do **not** confuse variable names with node labels.

## `condition.filter`

Standard operator set (`=`, `<>`, `>`, `<`, `>=`, `<=`, `IN`, `=~`, `STARTS WITH`, `ENDS WITH`, `IS NULL`, `IS NOT NULL`, plus `AND`/`OR`/`NOT`). Same attribute-naming conventions as the read-side schema. Use `$param` for partial filters and `$token.<claim>` for token-driven values.

## `allowed_upserts.nodes`

This is the only `allowed_upserts` sub-field a property-write-only policy uses.

### `existing_nodes` — what this skill is about

```json
"allowed_upserts": {
  "nodes": {
    "existing_nodes": ["subject"]
  }
}
```

Lists variables from `cypher` whose properties may be **set** by the Knowledge Query. Each `upsert_nodes[].name` in the KQ must appear here. If you only declare `existing_nodes: ["subject"]`, then a KQ entry with `"name": "car"` is rejected.

You can list multiple variables when one Knowledge Query needs to write properties on more than one matched node — e.g. `existing_nodes: ["subject", "car"]` allows updating both the Person *and* the Car they own in the same call.

### `node_types` — out of scope

```json
"allowed_upserts": {
  "nodes": {
    "node_types": ["Document"]
  }
}
```

`node_types` whitelists labels for **brand-new node creation**. Different operation, different KQ shape (fresh `name`, required `external_id`). Out of scope here. See [`indykite-ciq-create-node`](../../indykite-ciq-create-node/SKILL.md). Both keys can co-exist if a single policy needs to allow both creates and in-place property writes.

## What the other blocks would do (and why we omit them)

For completeness:

- `allowed_upserts.relationships.relationship_types` — `[{type, source_node_label, target_node_label}]` triples for **creating new relationships**. Different skill: [`indykite-ciq-create-relationship`](../../indykite-ciq-create-relationship/SKILL.md).
- `allowed_upserts.relationships.existing_relationships` — variables from `cypher` whose relationship properties can be updated. Out of scope (the corresponding "update relationship property" skill doesn't exist yet).
- `allowed_deletes.nodes` — variables that can be deleted, including `<var>.property.<name>` paths for deleting individual properties. Different skill (delete property).
- `allowed_reads` — what may be projected back to the caller. Often combined with `existing_nodes` in real policies (read-and-update patterns); kept out of this skill's runnable asset for clarity.

Omitting these blocks means the corresponding Knowledge Query arrays will be rejected at execute time.

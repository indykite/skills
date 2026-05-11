# CIQ Policy Reference (create-node-with-link focused)

This reference covers the fields a *combined-create* CIQ policy uses (creating a new node *and* one or more new relationships in one operation).

For the single-operation variants see [`indykite-ciq-create-node`](../../indykite-ciq-create-node/references/policy-reference.md) and [`indykite-ciq-create-relationship`](../../indykite-ciq-create-relationship/references/policy-reference.md).

## Top-level structure

The policy has four top-level keys, all siblings:

| Key                | Use                                                                                                                       |
|--------------------|---------------------------------------------------------------------------------------------------------------------------|
| `meta`             | Set `policy_version: "1.0-ciq"`.                                                                                           |
| `subject`          | Set `type` to the authenticating entity (e.g. `_Application`).                                                              |
| `condition`        | Match the subject AND every existing endpoint the new node will link to; pin them with filters.                              |
| `allowed_upserts`  | Use `nodes.node_types` to whitelist the new node's label *and* `relationships.relationship_types` for each new edge's triple. |

When adapting to a new domain, only the *contents* of `condition` and the two `allowed_upserts` sub-blocks change; the four-key structure stays the same.

## Skeleton

```json
{
  "meta":      { "policy_version": "1.0-ciq" },
  "subject":   { "type": "<_Application | Person | User | …>" },
  "condition": {
    "cypher": "<MATCH (subject) MATCH (existing endpoints…)>",
    "filter": [ { ... } ]
  },
  "allowed_upserts": {
    "nodes": {
      "node_types": [ "<NewLabel>" ]
    },
    "relationships": {
      "relationship_types": [
        { "type": "<REL>", "source_node_label": "<Source>", "target_node_label": "<Target>" }
      ]
    }
  }
}
```

The two halves of `allowed_upserts` are **independent whitelists**:

- `node_types` constrains *what new node label is allowed* in `upsert_nodes[].type`.
- `relationship_types` constrains *which `(source-label, type, target-label)` triples* are allowed in `upsert_relationships`.

The Knowledge Query must satisfy both to succeed.

## `meta.policy_version`

Currently `1.0-ciq`.

## `subject.type` and `condition.cypher`

Same patterns as the simpler create skills. The cypher must match the subject *and* every existing endpoint the new node will link to. The new node itself is not matched in `cypher` — it's declared in the Knowledge Query.

Use connected `MATCH` clauses when the existing endpoints share a path you want to enforce, or disjoint `MATCH` clauses when they don't. The `policyAllowWriteContract` example uses **both** in a single cypher (the subject + Company + Vehicle are connected; Person is matched separately):

```cypher
MATCH (subject:_Application)-[r1:HAS_AGREEMENT_WITH]->(company:Company)-[r2:OWNS]->(vehicle:Vehicle)
MATCH (person:Person)
```

## `condition.filter`

Pin the subject and every existing endpoint by `external_id`. For the running example:

```json
[
  {
    "operator": "AND",
    "operands": [
      { "operator": "=", "attribute": "subject.external_id", "value": "$_appId" },
      { "operator": "=", "attribute": "vehicle.external_id", "value": "$vehicleID" },
      { "operator": "=", "attribute": "person.external_id",  "value": "$personID" }
    ]
  }
]
```

`$_appId` is reserved (auto-filled). The other two `$param`s become required keys in the execute call's `input_params`.

## `allowed_upserts.nodes.node_types`

Array of node labels the Knowledge Query may create. For a single-new-node skill, this typically has one entry:

```json
"node_types": ["Contract"]
```

A combined-create policy can list more than one label, allowing the Knowledge Query to create *several* new nodes in one execute. Use sparingly — most ingestion flows benefit from being predictable about what gets created.

## `allowed_upserts.relationships.relationship_types`

Array of triples. Each triple is one new relationship the Knowledge Query may create. The example creates two:

```json
"relationship_types": [
  { "type": "COVERS",   "source_node_label": "Contract", "target_node_label": "Vehicle" },
  { "type": "ACCEPTED", "source_node_label": "Person",   "target_node_label": "Contract" }
]
```

Each triple's labels must match what the Knowledge Query says — both for the new node (matched against `node_types`) and for any existing endpoint (matched against the cypher variable's bound label).

**Direction matters**: `(Contract)-[:COVERS]->(Vehicle)` and `(Vehicle)-[:COVERS]->(Contract)` are different triples. List both if both directions should be allowed.

## Optional: `allowed_upserts.nodes.existing_nodes` and `existing_relationships`

If your combined-create flow also needs to update properties on an *existing* element in the same execute (e.g. set a `last_contracted_at` timestamp on the existing Vehicle), add `existing_nodes` and/or `existing_relationships` alongside `node_types` and `relationship_types`. The Knowledge Query then has matching `upsert_nodes` / `upsert_relationships` entries that reference the cypher variables.

This combined-create-and-update is a power-user pattern; this skill's runnable example keeps it create-only for clarity.

## Why we omit `allowed_reads` and `allowed_deletes`

For a pure combined-create flow, neither is needed. If you want the response to project richer data than just the newly-created elements, add an `allowed_reads` block. `allowed_deletes` has no role in a create flow.

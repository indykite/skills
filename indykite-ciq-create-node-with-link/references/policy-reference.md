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

### Performance: pin the subject before high-fan-in hops

On a large graph, a `MATCH` chain whose only selective filters sit at its *endpoints* can execute slowly. If one endpoint is a high-fan-in node — a brand, tenant, or category that a large share of records points to — the query planner may anchor there and traverse its entire fan-in before the subject filter prunes anything, so execution time grows linearly with the dataset.

The fix is to pin the subject and any shared gate node inline by `external_id` — a pinned mid-chain node stops the planner from entering the chain through its fan-in; disjoint `MATCH` clauses (like `person`) are unaffected:

```cypher
MATCH (subject:_Application {external_id: $_appId})-[r1:HAS_AGREEMENT_WITH]->(company:Company {external_id: $company_id})-[r2:OWNS]->(vehicle:Vehicle)
MATCH (person:Person)
```

Server-populated in-cypher parameters make this safe without extra caller input: `$token.<claim>` (e.g. `$token.sub`) carries the Bearer token's claims for user subjects, `$ik_token.<claim>` (e.g. `$ik_token.act.sub`) the claims of the delegation token sent in `X-IK-Token`, and `$_appId` carries the application id for `_Application` subjects. From the delegation token the platform also derives two lists, oldest hop first: `$ik_token.act_chain` (the `sub` of every hop of its `act` chain) and `$ik_token.act_chain_types` (the `type` of every hop, `null` for a hop without one), so the cypher can compare the whole chain with a graph path, ids and types both - `[r IN rels | endNode(r).external_id] = $ik_token.act_chain AND [r IN rels | endNode(r).type] = $ik_token.act_chain_types`. `token` and `ik_token` are reserved names: the platform binds both claim sets (the derived lists included, so an `input_params.act_chain` never changes `$ik_token.act_chain`), ignores caller values sent under either name in `input_params`, and binds an empty set for a token that did not arrive, so a comparison against it is `null` and the query matches nothing rather than erroring. Any other `$param` in the cypher must be supplied by the caller via `input_params`.

If the chain cannot be restructured, the fallback is a planning barrier: pin the subject with an in-cypher `WHERE` and `WITH subject LIMIT 1`, then continue the chain from the bound subject (safe because `(type, external_id)` is unique in the IKG). Three rules make the barrier correct: the pinning equality must be an in-cypher `WHERE` placed *before* the `LIMIT 1` — `condition.filter` is applied after the whole pattern, so a `LIMIT 1` after an unpinned `MATCH` grabs an arbitrary node and silently returns zero rows; every `WITH` must keep carrying `subject` (the validator rejects one that drops it: `missing required variables in WITH statement`); and a plain `WITH` without `LIMIT` is flattened by the planner and changes nothing. `USING INDEX` planner hints are rejected by the policy parser, and extra Knowledge Query filter values narrow the result without changing which end the planner anchors on.

### Labels the condition cannot match, and `skip_resource_label`

When the policy is saved, the platform rewrites the condition so that every named node also carries the `Resource` system label and the subject the `DigitalTwin` label: `MATCH (subject:Person)-[:OWNS]->(car:Car)` runs as `MATCH (subject:Person:DigitalTwin:Resource)-[:OWNS]->(car:Car:Resource)`. Two consequences:

- **Blocked labels.** A condition that names a platform label is refused at save time with ``invalid node type `<label>` in cypher for node `<var>` ``. The blocked labels are `_AppAgent`, `_API`, `_TrustScore`, `Source`, and the four data-schema labels `_DataSchemaNode`, `_DataSchemaProperty`, `_DataSchemaRelationship`, `_DataSchemaMetadata`. The observed schema is read through the Data Schema API ([`indykite-data-schema`](../../indykite-data-schema/SKILL.md)), never through a query.
- **`condition.skip_resource_label`** (optional, default `false`). For some conditions the added `Resource` label leads the planner to a poor plan, because the `id` and `external_id` indexes are defined on `Resource` and it may prefer them over the node type's own index. Setting `"skip_resource_label": true` inside `condition` leaves `Resource` out, so each lookup uses the indexes of the node type's label; only the subject's `DigitalTwin` label is still added, and the results are the same either way. Use it only when a condition that is already anchored and bounded (above) is still slow, and measure before and after - the default plan is right for most conditions. Accepted on `1.0-ciq`; a policy version that does not support it refuses the save with `skip_resource_label is not allowed for this policy version`.

```json
"condition": {
  "cypher": "MATCH (subject:Person)-[owns:OWNS]->(bus:Bus)-[:HAS]->(ln:LicenseNumber)",
  "skip_resource_label": true,
  "filter": [ { "attribute": "subject.external_id", "operator": "=", "value": "$token.sub" } ]
}
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

---
name: indykite-ciq-create-node-with-link
description: Author an IndyKite ContX IQ (CIQ) policy plus its Knowledge Query that creates a brand-new node AND links it to one or more existing nodes via new relationships in a single `POST /contx-iq/v1/execute` call. Use when ingesting a new entity that must be wired into the IKG atomically - combines node creation and relationship creation in one operation.
license: Apache-2.0
compatibility: Requires curl, bash 4+, and jq. Network access to the regional IndyKite REST API (eu.api.indykite.com or us.api.indykite.com) is required at runtime.
---

# IndyKite ContX IQ - create a new node + link it to existing nodes

Create a brand-new node in the IndyKite Graph (IKG) and wire it to one or more existing nodes in a single atomic `POST /contx-iq/v1/execute` call. The policy whitelists both a node label and one or more relationship triples, and the Knowledge Query carries both `upsert_nodes` (for the new node) and `upsert_relationships` (for the new edge(s)); the new node's variable `name` from `upsert_nodes` is referenced as the `source` or `target` in `upsert_relationships`. It combines the patterns from [`indykite-ciq-create-node`](../indykite-ciq-create-node/SKILL.md) and [`indykite-ciq-create-relationship`](../indykite-ciq-create-relationship/SKILL.md).

This is the **canonical "ingest a new entity into the graph" pattern** - used in the IndyKite developer-hub resources for the insurance Contract example (`policyAllowWriteContract` + `knowledgeQueryAllowWriteContract`), where one execute creates a new `Contract` node and wires it via two relationships (`COVERS` to a Vehicle, `ACCEPTED` from a Person).

Other paths are deliberately out of scope:

- **Just creating a node, no link** - use [`indykite-ciq-create-node`](../indykite-ciq-create-node/SKILL.md).
- **Just linking two existing nodes** - use [`indykite-ciq-create-relationship`](../indykite-ciq-create-relationship/SKILL.md).
- **Updating an existing node's properties or relationship's properties** - different operations entirely.

## When to use

Activate this skill when the user:

- wants to **ingest a new entity** through CIQ in one atomic operation (create the node *and* its relationships to existing nodes);
- is implementing the canonical insurance/contract pattern: a new `Contract` node linked to an existing `Vehicle` and an existing `Person`;
- is building an "add a comment to a document" flow: a new `Comment` node linked to an existing `Document`;
- is parameterising both the new node's `external_id` and the source/target endpoints from `input_params`;
- is debugging a `403` / `422` from a combined create execute that should have wired the new node up.

Do **not** activate this skill when the user:

- only needs to **create a node** - use [`indykite-ciq-create-node`](../indykite-ciq-create-node/SKILL.md);
- only needs to **link two existing nodes** - use [`indykite-ciq-create-relationship`](../indykite-ciq-create-relationship/SKILL.md);
- needs to write properties on existing elements - use the property-write skills.

## Prerequisites

- An IndyKite **project**, **AppAgent**, and AppAgent **credentials**.
- A **Service Account token** with Config API access, and the project's GID in `PROJECT_GID` - both used to *create* the policy and Knowledge Query.
- The **endpoint nodes** the new node will link to **already in the IKG**.
- The **node label and relationship label(s)** the operation will use, allowed by the project's data model.
- A **plan for the new node's `external_id`** - usually parameterised via `$param`.

## Steps

### 1. Pick the subject and the cypher pattern

**Subject type** - pick one. The schema is identical across both choices; only `subject.type`, the filter, and the execute-time auth differ:

| Subject           | Use when                                                       | Auth at execute time                                | Filter convention                              |
|-------------------|----------------------------------------------------------------|------------------------------------------------------|------------------------------------------------|
| `_Application`    | System-side / ETL / catalog work; no user in the loop.          | `X-IK-ClientKey` only.                               | `subject.external_id = $_appId` (reserved).    |
| `Person` / `User` | The authenticated user is performing the operation themselves.  | `X-IK-ClientKey` + `Authorization: Bearer <token>`.  | `subject.external_id = $token.sub`.            |

A policy is restricted to a single subject type - if both should be allowed, write two policies. The runnable example below uses `_Application` (insurance-contract ingestion); a `Person` variant - for example, a user posting a new `Comment` linked to an existing `Document` they own - differs only in `subject.type`, the filter, and the execute headers.

**Cypher pattern** - must `MATCH` the subject **and** every existing endpoint the new node will link to. The new node itself is **not** matched; it's declared in `upsert_nodes`.

Working example (used throughout this skill, taken verbatim from the developer-hub `policyAllowWriteContract` resource):

> An `_Application` creates a new `Contract` node and links it via `:COVERS` to an existing `Vehicle` (owned by an existing `Company`) and via `:ACCEPTED` from an existing `Person`.

```cypher
MATCH (subject:_Application)-[r1:HAS_AGREEMENT_WITH]->(company:Company)-[r2:OWNS]->(vehicle:Vehicle)
MATCH (person:Person)
```

Variables: `subject`, `r1`, `company`, `r2`, `vehicle`, `person`. The new `Contract` node will be declared as a fresh `name` in `upsert_nodes`; the two new relationships will reference `vehicle`, `person`, and the fresh `name` as endpoints.

### 2. Author the policy with both `node_types` and `relationship_types`

Build the policy JSON with five blocks:

- `meta.policy_version` - currently `1.0-ciq`.
- `subject.type` - `_Application` for the running example.
- `condition.cypher` and `condition.filter` - the cypher matches the subject and existing endpoints; the filter pins them by `external_id` (`$_appId` plus `$vehicleID`, `$personID`).
- `allowed_upserts.nodes.node_types` - the new node's label (e.g. `["Contract"]`).
- `allowed_upserts.relationships.relationship_types` - one triple per new relationship, matching the directions and labels.

A complete combined-create policy for the running example: see [`assets/policy-create-contract.json`](assets/policy-create-contract.json).

Create it through the Config API:

```bash
# set the current project_id, and stringify only the `policy` field, before POSTing
jq --arg pid "$PROJECT_GID" '.project_id = $pid | .policy |= tojson' indykite-ciq-create-node-with-link/assets/policy-create-contract.json \
  | curl -X POST "$API_URL/configs/v1/authorization-policies" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $SERVICE_ACCOUNT_TOKEN" \
      -d @-
```

A `201 Created` returns the policy's `id` (GID). Export it as `POLICY_ID` - the Knowledge Query create injects it into `policy_id`.

For the schema deep-dive (how `node_types` and `relationship_types` interact, why direction matters, what `existing_nodes` would add) see [`references/policy-reference.md`](references/policy-reference.md).

### 3. Create the Knowledge Query with both `upsert_nodes` and `upsert_relationships`

The Knowledge Query has two write arrays:

**`upsert_nodes`** - declares the new node. Same shape as in [`indykite-ciq-create-node`](../indykite-ciq-create-node/SKILL.md):

- `name` - fresh variable name (not in cypher), e.g. `contract`.
- `type` - node label, must match `allowed_upserts.nodes.node_types`.
- `external_id` - required for new nodes; usually `$param`.
- `properties` - array of `{type, value, metadata?}` items.

**`upsert_relationships`** - declares each new relationship. Same shape as in [`indykite-ciq-create-relationship`](../indykite-ciq-create-relationship/SKILL.md), with one important twist:

- `name` - fresh variable name for each new relationship (e.g. `r3`, `r4`).
- `source` - variable name. **Can be a cypher variable** (existing node) **or the `name` of an `upsert_nodes` entry** (the just-created node).
- `target` - same: cypher variable or `upsert_nodes` `name`.
- `type` - must match the policy's `relationship_types`.

That `source`/`target` flexibility is what makes the combined operation work: `r3` connects the just-created `contract` to the existing `vehicle`; `r4` connects the existing `person` to the just-created `contract`.

A complete combined-create Knowledge Query for the running example: see [`assets/knowledge-query-create-contract.json`](assets/knowledge-query-create-contract.json).

Create it through the Config API:

```bash
# set the current project_id and policy_id, and stringify only the `query` field, before POSTing
jq --arg pid "$PROJECT_GID" --arg polid "$POLICY_ID" '.project_id = $pid | .policy_id = $polid | .query |= tojson' indykite-ciq-create-node-with-link/assets/knowledge-query-create-contract.json \
  | curl -X POST "$API_URL/configs/v1/knowledge-queries" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $SERVICE_ACCOUNT_TOKEN" \
      -d @-
```

A `201 Created` returns the Knowledge Query's `id` (GID).

Schema details (which arrays interact, response shape covering both new nodes and new relationships) live in [`references/knowledge-query-reference.md`](references/knowledge-query-reference.md).

### 4. Authenticate and execute

The execute endpoint is the same as for every other CIQ operation:

```text
POST <API_URL>/contx-iq/v1/execute
```

For the `_Application` subject:

- `X-IK-ClientKey: <AppAgent-credentials-token>` - required.
- `Authorization: Bearer …` - omit.

Request:

```json
{
  "id": "<knowledge_query_gid_or_name>",
  "input_params": {
    "vehicleID": "car2",
    "personID":  "ryan",
    "contract_external_id": "ct853",
    "contractNumber":       "rbjh853"
  }
}
```

A runnable shell helper: [`scripts/execute.sh`](scripts/execute.sh).

Full execute reference: [`references/execution-reference.md`](references/execution-reference.md).

### 5. Verify the response and confirm the wiring

A successful combined-create returns the new node's projection plus the new relationships' identifiers:

```json
{
  "data": [
    {
      "nodes": {
        "contract.external_id":     "ct853",
        "contract.property.number": "rbjh853"
      },
      "relationships": {
        "r3": { "Id": …, "ElementId": "…", "StartId": …, "EndId": … },
        "r4": { "Id": …, "ElementId": "…", "StartId": …, "EndId": … }
      }
    }
  ]
}
```

If the response is **not** what you expected, walk this list:

1. **Both whitelist entries present.** The KQ's `upsert_nodes[].type` must be in `allowed_upserts.nodes.node_types`, and each `upsert_relationships[]` triple must be in `allowed_upserts.relationships.relationship_types`. Either mismatch → `403`.
2. **Endpoints exist.** Every cypher variable the relationships reference (`vehicle`, `person`) must resolve to a real node. If `MATCH` finds no rows, the operation has nothing to wire - `200` with empty `data`.
3. **Cross-references match.** The new node's `name` in `upsert_nodes` (e.g. `contract`) must be exactly the same string used in `upsert_relationships[].source` or `target`. Typos here silently produce wiring failures.
4. **Direction matches.** Relationship triples encode direction. `(Contract)-[:COVERS]->(Vehicle)` is different from `(Vehicle)-[:COVERS]->(Contract)`.
5. **All `$param`s present.** The `contract_external_id`, `contractNumber`, `vehicleID`, `personID` all need to be in `input_params`.

For other failure modes see [`references/troubleshooting.md`](references/troubleshooting.md).

## Outcome

When this skill has been applied successfully:

- A combined-create CIQ policy exists; it has a single `subject.type`, a Cypher pattern matching the subject and existing endpoint nodes, partial filters, and *both* `allowed_upserts.nodes.node_types` *and* `allowed_upserts.relationships.relationship_types` populated.
- A Knowledge Query references the policy and lists the new node in `upsert_nodes` and one or more new relationships in `upsert_relationships` (with the new node's `name` referenced as a `source` or `target`).
- One `POST /contx-iq/v1/execute` returns the new node's projection plus the new relationships' identifiers.
- A follow-up read confirms the new entity is wired into the graph.

## Files in this skill

- [`references/policy-reference.md`](references/policy-reference.md) - combined `node_types` + `relationship_types`, optional `existing_nodes` for hybrid create-and-update flows.
- [`references/knowledge-query-reference.md`](references/knowledge-query-reference.md) - `upsert_nodes` + `upsert_relationships` interaction, `source`/`target` cross-referencing, multi-relationship patterns.
- [`references/execution-reference.md`](references/execution-reference.md) - request/response, atomicity guarantees, idempotence on rerun.
- [`references/troubleshooting.md`](references/troubleshooting.md) - `403` / empty-data / wiring-mismatch / cross-reference patterns.
- [`assets/policy-create-contract.json`](assets/policy-create-contract.json) - the canonical insurance-Contract example, lifted from `policyAllowWriteContract` in the developer-hub resources.
- [`assets/knowledge-query-create-contract.json`](assets/knowledge-query-create-contract.json) - matching Knowledge Query.
- [`scripts/execute.sh`](scripts/execute.sh) - Bash helper.

## Agent-specific notes

This skill uses generic markdown instructions and works across all agents listed in the [README](../README.md). The agent needs to be able to issue HTTP requests. No Claude Code hooks, Cursor `@`-mentions, or Copilot workspace context are required.

## References

- [ContX IQ guide (developer hub)](https://developer.indykite.com/guides/guide-contx-iq) - full schema, including how `upsert_nodes` and `upsert_relationships` cross-reference.
- [Developer-hub resources - `policyAllowWriteContract` and `knowledgeQueryAllowWriteContract`](https://developer.indykite.com/resources) - the canonical insurance-Contract example this skill is built around.
- [Music dataset tutorial - Chapter 9 "Knowledge Queries"](https://developer.indykite.com/tutorials/tutorial-music-dataset) - `kqb` write variants for context-aware ingestion patterns.
- [Config API documentation](https://openapi.indykite.com/api-documentation-config)
- [Cypher query language manual (Neo4j; openCypher)](https://neo4j.com/docs/cypher-manual/current/) - the graph query language used in CIQ policy and Knowledge Query conditions over the IndyKite Knowledge Graph.
- [IndyKite Terraform provider](https://registry.terraform.io/providers/indykite/indykite/latest/docs)

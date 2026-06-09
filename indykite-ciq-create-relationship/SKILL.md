---
name: indykite-ciq-create-relationship
description: Author an IndyKite ContX IQ (CIQ) policy plus its Knowledge Query that creates a brand-new relationship between two existing nodes in the IndyKite Graph (IKG), then run it via `POST /contx-iq/v1/execute`. Use when wiring two existing entities together through CIQ - no new nodes, no relationship updates, no deletes.
license: Apache-2.0
compatibility: Requires curl, bash 4+, and jq. Network access to the regional IndyKite REST API (eu.api.indykite.com or us.api.indykite.com) is required at runtime.
---

# IndyKite ContX IQ - create a new relationship

A CIQ relationship-create policy declares an `allowed_upserts.relationships.relationship_types` whitelist of `{type, source_node_label, target_node_label}` triples; the Knowledge Query's `upsert_relationships` array names the new relationship and references **variables from the policy's `cypher`** as `source` and `target`. The two endpoint nodes are matched in the policy's cypher - they must already exist in the IKG. The new relationship is what's created.

This skill covers exactly that - relationship creation between two pre-existing nodes. Other paths are deliberately out of scope:

- **Creating a new node** uses `allowed_upserts.nodes.node_types` and `upsert_nodes` - see [`indykite-ciq-create-node`](../indykite-ciq-create-node/SKILL.md).
- **Creating a relationship to a brand-new node** combines both: an `upsert_nodes` entry for the new node plus an `upsert_relationships` entry that points its `source` or `target` at the fresh `name`. The schema supports this; this skill keeps the example tight to two existing endpoints for clarity. See "Adapting for a fresh endpoint" near the bottom.
- **Updating an existing relationship's properties** uses `allowed_upserts.relationships.existing_relationships`.
- **Deletes** use `allowed_deletes.relationships`.

For reads, see [`indykite-ciq-read`](../indykite-ciq-read/SKILL.md).

## When to use

Activate this skill when the user:

- wants to **link two existing nodes** with a new relationship (e.g. `Person -[:ACCEPTED]-> Contract`, `Track -[:PLAYED_AT]-> Venue`, `User -[:OWNS]-> Document`);
- is authoring an `_Application`-subject "catalog wiring" policy + Knowledge Query for system-side relationship ingestion;
- is parameterising the source/target `external_id`s and (optionally) the new relationship's properties from execute-time `input_params`;
- is debugging a `403` / `422` from a `POST /contx-iq/v1/execute` call that should have created a relationship but didn't.

Do **not** activate this skill when the user:

- wants to **create a new node** (with or without a relationship from another node) - use [`indykite-ciq-create-node`](../indykite-ciq-create-node/SKILL.md);
- wants to **read** data from the IKG - use [`indykite-ciq-read`](../indykite-ciq-read/SKILL.md);
- wants to **update an existing relationship's properties** - different policy field (`existing_relationships`) and KQ shape;
- wants to **delete** a relationship - different policy field (`allowed_deletes.relationships`) and KQ array;
- is using the Capture API (`POST /capture/v1/relationships`) or Terraform to ingest relationships instead of CIQ - those are separate ingestion paths.

## Prerequisites

- An IndyKite **project**, **AppAgent**, and AppAgent **credentials** (the AppAgent token goes into `X-IK-ClientKey` at execute time).
- A **Service Account token** with Config API access, and the project's GID in `PROJECT_GID` - both used to *create* the policy and Knowledge Query.
- **Both endpoint nodes already in the IKG** with stable `external_id`s. CIQ doesn't seed them; this policy authorises wiring two existing nodes.
- A **relationship label** (`PLAYED_AT`, `ACCEPTED`, `OWNS`, etc.) and the source/target node labels it connects. Both must match what the IKG schema already permits.
- For non-`_Application` subjects, the **subject's** node also already in the IKG.

If any of these are missing, stop and tell the user - fixing them first is much cheaper than debugging a vague `403` or `422`.

## Steps

### 1. Pick the subject and the cypher pattern

**Subject type** - pick one. The schema is identical across both choices; only `subject.type`, the filter, and the execute-time auth differ:

| Subject           | Use when                                                       | Auth at execute time                                | Filter convention                              |
|-------------------|----------------------------------------------------------------|------------------------------------------------------|------------------------------------------------|
| `_Application`    | System-side / ETL / catalog work; no user in the loop.          | `X-IK-ClientKey` only.                               | `subject.external_id = $_appId` (reserved).    |
| `Person` / `User` | The authenticated user is performing the operation themselves.  | `X-IK-ClientKey` + `Authorization: Bearer <token>`.  | `subject.external_id = $token.sub`.            |

A policy is restricted to a single subject type - if both should be allowed, write two policies. The runnable example below uses `_Application` (system-side wiring); a `Person` variant - for example, a user accepting a Contract - differs only in `subject.type`, the filter, and the execute headers.

**Cypher pattern** - must `MATCH` both endpoint nodes, **plus** the subject. Use disjoint `MATCH` clauses (separated by spaces) when the endpoints aren't connected through any other path you need.

Working example (used throughout this skill):

> Music-dataset domain: an `_Application` adds a `PLAYED_AT` relationship from an existing `Track` to an existing `Venue`, given both `external_id`s.

```cypher
MATCH (subject:_Application)
MATCH (track:Track)
MATCH (venue:Venue)
```

Variables the rest of the policy and KQ will reference: `subject`, `track`, `venue`. The new relationship does **not** appear in the cypher - it's declared in the KQ.

If you need to constrain the endpoints to be reachable along an existing path before the new edge can be added, use a connected pattern instead - for example, you might require the Track and Venue to share an existing `:CATALOGED_BY` relationship before allowing the `PLAYED_AT` link. That decision belongs in the cypher.

### 2. Author the policy with `allowed_upserts.relationships.relationship_types`

Build the policy JSON with four blocks:

- `meta.policy_version` - currently `1.0-ciq`.
- `subject.type` - `_Application` for the running example.
- `condition.cypher` and `condition.filter` - anchor the subject and pin the endpoints by `external_id`. For `_Application`, filter on `subject.external_id = $_appId` (reserved, auto-filled). For each endpoint, filter on its `external_id` against a `$param`.
- `allowed_upserts.relationships.relationship_types` - array of `{type, source_node_label, target_node_label}` triples the Knowledge Query may **create** as new relationships.

**Omit** `allowed_reads`, `allowed_deletes`, and the other `allowed_upserts` sub-fields if this policy only creates relationships. Omitting a block is the supported way to forbid that operation.

A complete relationship-create policy for the running example: see [`assets/policy-create-played-at.json`](assets/policy-create-played-at.json).

Create it through the Config API:

```bash
# set the current project_id, and stringify only the `policy` field, before POSTing
jq --arg pid "$PROJECT_GID" '.project_id = $pid | .policy |= tojson' indykite-ciq-create-relationship/assets/policy-create-played-at.json \
  | curl -X POST "$API_URL/configs/v1/authorization-policies" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $SERVICE_ACCOUNT_TOKEN" \
      -d @-
```

A `201 Created` returns the policy's `id` (GID). Export it as `POLICY_ID` - the Knowledge Query create injects it into `policy_id`.

For the full schema (the `relationship_types` triple, why we omit `existing_relationships` and `node_types`) see [`references/policy-reference.md`](references/policy-reference.md).

### 3. Create the Knowledge Query with `upsert_relationships`

The Knowledge Query references the policy and lists what to write. Each entry in `upsert_relationships` describes one new relationship:

- `name` - a **distinct** variable name not used in the policy's `cypher`. Convention: prefix with `new` or use a domain-specific noun. The response uses this name as the key for the new relationship's identifiers.
- `source` - the variable name of the **source endpoint** from the policy's cypher. Must match what `relationship_types[].source_node_label` declares.
- `target` - the variable name of the **target endpoint** from the policy's cypher. Must match `target_node_label`.
- `type` - the relationship label. Must equal the `relationship_types[].type` in the policy.
- `properties` - *optional*. Same `{type, value, metadata?}` shape as node properties - see [`references/knowledge-query-reference.md`](references/knowledge-query-reference.md).

Echo the new relationship back in the response by listing its variable name in the top-level `relationships` array.

A complete Knowledge Query for the running example: see [`assets/knowledge-query-create-played-at.json`](assets/knowledge-query-create-played-at.json).

Create it through the Config API:

```bash
# set the current project_id and policy_id, and stringify only the `query` field, before POSTing
jq --arg pid "$PROJECT_GID" --arg polid "$POLICY_ID" '.project_id = $pid | .policy_id = $polid | .query |= tojson' indykite-ciq-create-relationship/assets/knowledge-query-create-played-at.json \
  | curl -X POST "$API_URL/configs/v1/knowledge-queries" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $SERVICE_ACCOUNT_TOKEN" \
      -d @-
```

A `201 Created` returns the Knowledge Query's `id` (GID).

### 4. Authenticate and execute

The execute endpoint is the same as for reads and node-creates:

```text
POST <API_URL>/contx-iq/v1/execute
```

Authentication for the running `_Application`-subject example:

- `X-IK-ClientKey: <AppAgent-credentials-token>` - required.
- `Authorization: Bearer …` - **omit** for `_Application`. The reserved `$_appId` is auto-filled from the application's `external_id`.

For Person-subject linking flows, add `Authorization: Bearer <user-access-token>` and the policy's filter on `subject.external_id = $token.sub`.

Request:

```json
{
  "id": "<knowledge_query_gid_or_name>",
  "input_params": {
    "track_external_id": "track-99",
    "venue_external_id": "venue-1"
  }
}
```

A runnable shell helper: [`scripts/execute.sh`](scripts/execute.sh).

Full execute reference (auth, request/response, error semantics): [`references/execution-reference.md`](references/execution-reference.md).

### 5. Verify the response and confirm the new relationship

A successful create-relationship execute returns the projected nodes plus a `relationships` block keyed by the variable name with internal graph identifiers:

```json
{
  "data": [
    {
      "nodes": {
        "track.external_id": "track-99",
        "venue.external_id": "venue-1"
      },
      "relationships": {
        "newPlayedAt": {
          "Id": 1152932499723124700,
          "ElementId": "5:3a2b09d5-…:1152932499723124736",
          "StartId": 0,
          "StartElementId": "4:3a2b09d5-…:0",
          "EndId": 15
        }
      }
    }
  ]
}
```

The `Id` / `ElementId` are the platform's internal identifiers for the new edge; you don't need to use them but they confirm the edge was written.

If the response is **not** what you expected, walk this list before changing the policy or KQ:

1. **Both endpoints exist.** The policy's cypher needs to actually match - if `track.external_id` or `venue.external_id` isn't seeded, the cypher returns no rows and there's nothing for `upsert_relationships` to attach to.
2. **Triple matches.** The KQ's `(source, target, type)` must align with the policy's `relationship_types[]` triple - same labels (via the cypher variables) and same `type`.
3. **Variables exist in cypher.** `source` and `target` are **cypher variable names**, not labels. If you write `"source": "Track"` (the label) instead of `"source": "track"` (the variable), the request fails.
4. **`name` is fresh.** The new relationship's `name` must not collide with an existing variable in the policy's cypher.
5. **The relationship didn't already exist.** Re-running with the same source/target pair upserts (matches the existing edge) instead of creating a duplicate.

For other failure modes (auth shape wrong, missing input_params, malformed JSON) see [`references/troubleshooting.md`](references/troubleshooting.md).

## Adapting for a fresh endpoint

If you need to create the **target node and the relationship in one execute** - say, create a new `Comment` and link it to an existing `Document` - combine this skill's pattern with [`indykite-ciq-create-node`](../indykite-ciq-create-node/SKILL.md):

- Policy: include both `allowed_upserts.nodes.node_types` (for the new node label) and `allowed_upserts.relationships.relationship_types` (for the new edge).
- Knowledge Query: an `upsert_nodes` entry for the new node, plus an `upsert_relationships` entry whose `source` or `target` is the fresh node's `name`.

The two skills cover the parts; combining is just one extra `upsert_*` array entry on each side. Each operation must be whitelisted in the policy.

## Outcome

When this skill has been applied successfully:

- A relationship-create CIQ policy exists; it has a single `subject.type`, a Cypher pattern matching both endpoint nodes, partial filters pinning them by `external_id`, and an `allowed_upserts.relationships.relationship_types` whitelist - no `node_types`, no `existing_relationships`, no `allowed_reads` (unless intentionally added), no `allowed_deletes`.
- A Knowledge Query references that policy and lists exactly one new relationship in `upsert_relationships` with a fresh `name`, source/target variables from cypher, and the right `type`.
- `POST /contx-iq/v1/execute` returns `data` with the projected nodes and the new relationship's internal identifiers.
- A follow-up read (e.g. via [`indykite-ciq-read`](../indykite-ciq-read/SKILL.md)) finds the new edge in the IKG.

## Files in this skill

- [`references/policy-reference.md`](references/policy-reference.md) - relationship-create policy schema, the `{type, source_node_label, target_node_label}` triple, why other blocks are omitted.
- [`references/knowledge-query-reference.md`](references/knowledge-query-reference.md) - `upsert_relationships` schema, optional properties, returning the new relationship.
- [`references/execution-reference.md`](references/execution-reference.md) - `POST /contx-iq/v1/execute` for relationship writes, auth combinations, response shape with `Id` / `ElementId` / `StartId` / `EndId`.
- [`references/troubleshooting.md`](references/troubleshooting.md) - symptom → cause → fix tables for `403` / `422` / no-match-on-cypher / variable-vs-label confusion.
- [`assets/policy-create-played-at.json`](assets/policy-create-played-at.json) - runnable `_Application` → `(Track)-[:PLAYED_AT]->(Venue)` policy.
- [`assets/knowledge-query-create-played-at.json`](assets/knowledge-query-create-played-at.json) - matching Knowledge Query.
- [`scripts/execute.sh`](scripts/execute.sh) - Bash helper that posts to `/contx-iq/v1/execute` with the right headers.

## Agent-specific notes

This skill uses generic markdown instructions and works across all agents listed in the [README](../README.md). The agent needs to be able to issue HTTP requests (`curl`, an HTTP client, or the IndyKite Terraform provider). No Claude Code hooks, Cursor `@`-mentions, or Copilot workspace context are required.

## References

- [ContX IQ guide (developer hub)](https://developer.indykite.com/guides/guide-contx-iq)
- [Music dataset tutorial - Chapter 8 "ContX IQ policies" and Chapter 9 "Knowledge Queries"](https://developer.indykite.com/tutorials/tutorial-music-dataset) - concrete read/write/delete variants against a real graph; the `kqb` pattern is the canonical relationship-create variant.
- [Developer-hub resources - CIQ examples](https://developer.indykite.com/resources) - runnable `policyAllowUpsertRelationships` / `knowledgeQueryUpsertRelationships` pairs in the resource samples.
- [Config API documentation](https://openapi.indykite.com/api-documentation-config)
- [Cypher query language manual (Neo4j; openCypher)](https://neo4j.com/docs/cypher-manual/current/) - the graph query language used in CIQ policy and Knowledge Query conditions over the IndyKite Knowledge Graph.
- [IndyKite Terraform provider - `indykite_authorization_policy` and `indykite_knowledge_query`](https://registry.terraform.io/providers/indykite/indykite/latest/docs)
- [Credentials guide](https://developer.indykite.com/guides/guide-credentials)

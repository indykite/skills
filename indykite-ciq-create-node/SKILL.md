---
name: indykite-ciq-create-node
description: Author an IndyKite ContX IQ (CIQ) policy plus its Knowledge Query that creates a brand-new node in the IndyKite Graph (IKG), then run it via `POST /contx-iq/v1/execute`. Use when ingesting a new entity through CIQ - no relationship creation, no updates to existing nodes, no deletes.
license: Apache-2.0
compatibility: Requires curl, bash 4+, and jq. Network access to the regional IndyKite REST API (eu.api.indykite.com or us.api.indykite.com) is required at runtime.
---

# IndyKite ContX IQ - create a new node

ContX IQ (CIQ) lets you write into the IKG through a policy + Knowledge Query pair, the same shape used for reads. To **create a brand-new node**, the policy declares an `allowed_upserts.nodes.node_types` whitelist of node labels that may be created, and the Knowledge Query's `upsert_nodes` array names the node, sets its `external_id`, and lists the properties to write.

This skill covers exactly that - node creation only. Other write paths are deliberately out of scope:

- **Updating an existing node's properties** uses `allowed_upserts.nodes.existing_nodes` and a Knowledge Query `upsert_nodes` entry that references a variable from the policy's `cypher` (no `external_id`). Different field, different KQ shape.
- **Creating relationships** uses `allowed_upserts.relationships.relationship_types` (`{type, source_node_label, target_node_label}` triples) and the Knowledge Query's `upsert_relationships` array.
- **Deletes** use `allowed_deletes` and `delete_nodes` / `delete_relationships`.

For reads, see [`indykite-ciq-read`](../indykite-ciq-read/SKILL.md).

## When to use

Activate this skill when the user:

- wants to **create** a new node in the IKG through CIQ (e.g. ingest a new `Track`, `Document`, `Account`, or other entity);
- is authoring an `_Application`-subject "catalog write" policy + Knowledge Query - the typical pattern for ETL / system-side ingestion;
- is parameterising the new node's `external_id` and properties from execute-time `input_params`;
- is debugging a `403` / `422` from a `POST /contx-iq/v1/execute` call that should have created a node but didn't.

Do **not** activate this skill when the user:

- wants to **read** data from the IKG - use [`indykite-ciq-read`](../indykite-ciq-read/SKILL.md);
- wants to **update** an existing node's properties - different policy field (`existing_nodes`) and KQ shape;
- wants to **create relationships** between nodes - different policy field (`relationship_types`) and KQ array (`upsert_relationships`);
- wants to **delete** anything - different policy field (`allowed_deletes`) and KQ array;
- is using the Capture API (`POST /capture/v1/nodes`) or Terraform to ingest data instead of CIQ - those are separate ingestion paths.

## Prerequisites

- An IndyKite **project**, **AppAgent**, and AppAgent **credentials** (the AppAgent token goes into `X-IK-ClientKey` at execute time).
- A **Service Account token** with Config API access, and the project's GID in `PROJECT_GID` - both used to *create* the policy and Knowledge Query.
- The **node label** the new node will use (`Track`, `Document`, `Customer`, etc.) - already part of the project's data model.
- For non-`_Application` subjects, the **subject's** node already in the IKG (CIQ doesn't create the subject; it authorizes against it).
- A **plan for `external_id`** - the new node's stable identifier. Two choices the caller must make every time: hard-code it in the policy/KQ (rare), or supply it as a `$param` at execute time (common).

If any of these are missing, stop and tell the user - fixing them first is much cheaper than debugging a vague `403` or `422`.

## Steps

### 1. Pick the subject and Cypher anchor

**Subject type** - pick one. The schema is identical across both choices; only `subject.type`, the filter, and the execute-time auth differ:

| Subject           | Use when                                                       | Auth at execute time                                | Filter convention                              |
|-------------------|----------------------------------------------------------------|------------------------------------------------------|------------------------------------------------|
| `_Application`    | System-side / ETL / catalog work; no user in the loop.          | `X-IK-ClientKey` only.                               | `subject.external_id = $_appId` (reserved).    |
| `Person` / `User` | The authenticated user is performing the operation themselves.  | `X-IK-ClientKey` + `Authorization: Bearer <token>`.  | `subject.external_id = $token.sub`.            |

A policy is restricted to a single subject type - if both should be allowed, write two policies. The runnable example below uses `_Application` (system-side catalog ingestion); a `Person` variant - for example, a user creating their own Playlist - differs only in `subject.type`, the filter, and the execute headers.

**Cypher anchor** - even a write-only policy needs a `MATCH` clause that anchors to the subject. The new node is *not* matched in `cypher`; it's declared in the Knowledge Query's `upsert_nodes`.

Working example (used throughout this skill):

> System-side catalog ingestion: an `_Application` creates a new `Track` node, supplying `external_id`, `title`, and `loudness` at execute time.

```cypher
MATCH (subject:_Application)
```

That's the entire `cypher` - just enough to identify the subject. The `Track` does not appear here.

### 2. Author the policy with `allowed_upserts.nodes.node_types`

Build the policy JSON with four blocks:

- `meta.policy_version` - currently `1.0-ciq`.
- `subject.type` - `_Application` for the running example.
- `condition.cypher` and `condition.filter` - anchor to the subject. For `_Application`, filter on `subject.external_id = $_appId` (a reserved value auto-filled from the AppAgent at execute time).
- `allowed_upserts.nodes.node_types` - array of node labels the Knowledge Query may **create** as new nodes.

**Omit** `allowed_reads`, `allowed_deletes`, and the other `allowed_upserts` sub-fields if this policy only creates nodes. Leaving them out is the supported way to forbid those operations.

A complete create-only policy for the running example: see [`assets/policy-create-track.json`](assets/policy-create-track.json).

Create it through the Config API:

```bash
# set the current project_id, and stringify only the `policy` field, before POSTing
jq --arg pid "$PROJECT_GID" '.project_id = $pid | .policy |= tojson' indykite-ciq-create-node/assets/policy-create-track.json \
  | curl -X POST "$API_URL/configs/v1/authorization-policies" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $SERVICE_ACCOUNT_TOKEN" \
      -d @-
```

A `201 Created` returns the policy's `id` (GID). Export it as `POLICY_ID` - the Knowledge Query create injects it into `policy_id`.

For the full schema (operators, attribute conventions, why we omit `existing_nodes` and `allowed_reads`) see [`references/policy-reference.md`](references/policy-reference.md).

### 3. Create the Knowledge Query with `upsert_nodes`

The Knowledge Query references the policy and lists what to write. Each entry in `upsert_nodes` describes one node to create:

- `name` - a **distinct** variable name not used in the policy's `cypher`. This is the variable other arrays (`nodes`, `relationships`) reference.
- `type` - the node label. Must be in the policy's `allowed_upserts.nodes.node_types`.
- `external_id` - **required for new nodes**. Hardcode for one-off writes, or use `$param` (the common case) so the caller supplies it at execute time.
- `properties` - array of `{type, value, metadata?}` items. The `type` (property name) must be hardcoded; the `value` may be hardcoded or `$param`.

Echo the new node back in the response by listing its variable name in the top-level `nodes` array.

A complete Knowledge Query for the running example: see [`assets/knowledge-query-create-track.json`](assets/knowledge-query-create-track.json).

Create it through the Config API:

```bash
# set the current project_id and policy_id, and stringify only the `query` field, before POSTing
jq --arg pid "$PROJECT_GID" --arg polid "$POLICY_ID" '.project_id = $pid | .policy_id = $polid | .query |= tojson' indykite-ciq-create-node/assets/knowledge-query-create-track.json \
  | curl -X POST "$API_URL/configs/v1/knowledge-queries" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $SERVICE_ACCOUNT_TOKEN" \
      -d @-
```

A `201 Created` returns the Knowledge Query's `id` (GID) - what `execute` and the MCP `ciq_execute` tool will reference.

Schema details for every Knowledge Query field, including the protected property names you cannot set: [`references/knowledge-query-reference.md`](references/knowledge-query-reference.md).

### 4. Authenticate and execute

The execute endpoint is the same as for reads:

```text
POST <API_URL>/contx-iq/v1/execute
```

Authentication for the running `_Application`-subject example:

- `X-IK-ClientKey: <AppAgent-credentials-token>` - required.
- `Authorization: Bearer …` - **omit** for `_Application` subjects. The AppAgent itself authenticates the subject, and `$_appId` is auto-filled from the application's `external_id`.

For Person-subject create flows, add `Authorization: Bearer <user-access-token>` and the policy's filter on `subject.external_id = $token.sub` will pin the cypher anchor to that user.

Request body:

```json
{
  "id": "<knowledge_query_gid_or_name>",
  "input_params": {
    "track_external_id": "track-99",
    "track_title": "New Hot Track",
    "track_loudness": -7.5
  }
}
```

A runnable shell helper: [`scripts/execute.sh`](scripts/execute.sh).

Full execute reference (auth combinations, response shape, error codes): [`references/execution-reference.md`](references/execution-reference.md).

### 5. Verify the response and confirm the new node

A successful create execute returns the new node's projection:

```json
{
  "data": [
    {
      "nodes": {
        "newTrack.external_id": "track-99",
        "newTrack.property.title": "New Hot Track",
        "newTrack.property.loudness": -7.5
      }
    }
  ]
}
```

If the response is **not** what you expected, walk this list before changing the policy or KQ:

1. **The label is whitelisted.** The Knowledge Query's `upsert_nodes[].type` must be in the policy's `allowed_upserts.nodes.node_types`. Mismatch → `403`.
2. **`external_id` is set.** Required for new-node creation. If you're parameterising it (`"$track_external_id"`), the caller must supply it in `input_params`. Missing → `422 invalid_argument: missing or wrong input params`.
3. **`name` doesn't collide with a cypher variable.** The variable name in `upsert_nodes[].name` should be **fresh** - not a name that already appears in the policy's `cypher`. If it collides, the policy thinks you're updating an existing match instead of creating.
4. **Property names aren't in the protected set.** `_service`, `create_time`, `external_id`, `id`, `type`, `update_time` cannot be set as properties - they're managed by the platform.
5. **The node didn't already exist.** Re-running with the same `external_id` upserts (updates) instead of creating; the response will look similar but no new node is added.

For other failure modes (auth shape wrong, malformed JSON, subject filter mismatch) see [`references/troubleshooting.md`](references/troubleshooting.md).

## Outcome

When this skill has been applied successfully:

- A create-only CIQ policy exists in the project; it has a single `subject.type`, a Cypher pattern that anchors to the subject, optional partial filters, and an `allowed_upserts.nodes.node_types` whitelist - no `allowed_reads`, no `allowed_deletes`, no `existing_nodes`.
- A Knowledge Query references that policy and lists exactly one new node in `upsert_nodes` with a distinct `name`, the right `type`, an `external_id`, and the properties to set.
- `POST /contx-iq/v1/execute` (or the MCP `ciq_execute` tool) returns the new node's projection on success.
- A follow-up read query (e.g. via [`indykite-ciq-read`](../indykite-ciq-read/SKILL.md)) finds the new node in the IKG.

## Files in this skill

- [`references/policy-reference.md`](references/policy-reference.md) - write-focused policy schema, `allowed_upserts.nodes` deep-dive (existing vs node_types), why other blocks are omitted.
- [`references/knowledge-query-reference.md`](references/knowledge-query-reference.md) - `upsert_nodes` schema, properties + metadata, protected property names, returning the new node.
- [`references/execution-reference.md`](references/execution-reference.md) - `POST /contx-iq/v1/execute` for writes, auth combinations including `_Application` reserved `$_appId`, response shape.
- [`references/troubleshooting.md`](references/troubleshooting.md) - `403` / `422` / duplicate `external_id` / missing properties patterns.
- [`assets/policy-create-track.json`](assets/policy-create-track.json) - runnable create-only policy for the `_Application` → new `Track` example.
- [`assets/knowledge-query-create-track.json`](assets/knowledge-query-create-track.json) - matching Knowledge Query.
- [`scripts/execute.sh`](scripts/execute.sh) - Bash helper that posts to `/contx-iq/v1/execute` with the right headers.

## Agent-specific notes

This skill uses generic markdown instructions and works across all agents listed in the [README](../README.md). The agent needs to be able to issue HTTP requests (`curl`, an HTTP client, or the IndyKite Terraform provider - see References). No Claude Code hooks, Cursor `@`-mentions, or Copilot workspace context are required.

## References

- [ContX IQ guide (developer hub)](https://developer.indykite.com/guides/guide-contx-iq)
- [Music dataset tutorial - Chapter 8 "ContX IQ policies" and Chapter 9 "Knowledge Queries"](https://developer.indykite.com/tutorials/tutorial-music-dataset) - concrete read/write/delete variants against a real graph.
- [Config API documentation](https://openapi.indykite.com/api-documentation-config)
- [Cypher query language manual (Neo4j; openCypher)](https://neo4j.com/docs/cypher-manual/current/) - the graph query language used in CIQ policy and Knowledge Query conditions over the IndyKite Knowledge Graph.
- [IndyKite Terraform provider - `indykite_authorization_policy` and `indykite_knowledge_query`](https://registry.terraform.io/providers/indykite/indykite/latest/docs)
- [Credentials guide](https://developer.indykite.com/guides/guide-credentials)

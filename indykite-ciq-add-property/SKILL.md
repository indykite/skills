---
name: indykite-ciq-add-property
description: Author an IndyKite ContX IQ (CIQ) policy plus its Knowledge Query that sets one or more properties on an existing node in the IndyKite Graph (IKG), then run it via `POST /contx-iq/v1/execute`. Use when adding a brand-new property, overwriting an existing one, or attaching property metadata - no node creation, no relationship writes, no deletes.
license: Apache-2.0
compatibility: Requires curl, bash 4+, and jq. Network access to the regional IndyKite REST API (eu.api.indykite.com or us.api.indykite.com) is required at runtime.
---

# IndyKite ContX IQ - add a property to an existing node

Set or overwrite one or more properties on a node that already exists in the IndyKite Graph (IKG), driven by a ContX IQ policy + Knowledge Query and run via `POST /contx-iq/v1/execute`. The policy whitelists which `cypher`-matched nodes may be modified (`allowed_upserts.nodes.existing_nodes`); the Knowledge Query's `upsert_nodes` references those variables (no `external_id`, since the node already exists) and lists the properties to set, optionally with metadata. The IKG treats this as an upsert - adding a brand-new property and overwriting an existing one are the **same operation**; the platform doesn't distinguish.

This skill covers exactly that - property writes on an existing node. Other paths are deliberately out of scope:

- **Creating a brand-new node** uses `allowed_upserts.nodes.node_types` and a Knowledge Query `upsert_nodes` entry with a fresh `name` + an `external_id` - see [`indykite-ciq-create-node`](../indykite-ciq-create-node/SKILL.md).
- **Creating a new relationship** uses `allowed_upserts.relationships.relationship_types` - see [`indykite-ciq-create-relationship`](../indykite-ciq-create-relationship/SKILL.md).
- **Updating a relationship's properties** uses `allowed_upserts.relationships.existing_relationships`.
- **Deleting a property** uses `allowed_deletes.nodes` with a `<var>.property.<name>` path.

For reads, see [`indykite-ciq-read`](../indykite-ciq-read/SKILL.md).

## When to use

Activate this skill when the user:

- wants to **set a property** on a node that already exists in the IKG (e.g. update a Person's `music_mood`, set a LicenseNumber's `status`, attach `assurance_level` metadata to a verified property);
- is authoring a `Person`-subject "update own data" policy (the canonical pattern: `MATCH (subject:Person)` + `subject.external_id = $token.sub` + `existing_nodes: ["subject"]`);
- is authoring an `_Application`-subject "system-side property write" policy that updates a node reachable from the AppAgent;
- needs to write **property metadata** (`source`, `assurance_level`, custom metadata fields);
- is debugging a `403` / `422` from a property-write execute that should have succeeded.

Do **not** activate this skill when the user:

- wants to **create a brand-new node** - use [`indykite-ciq-create-node`](../indykite-ciq-create-node/SKILL.md);
- wants to **link two existing nodes** with a new relationship - use [`indykite-ciq-create-relationship`](../indykite-ciq-create-relationship/SKILL.md);
- wants to **update a relationship's properties** - different policy field (`existing_relationships`), out of scope here;
- wants to **delete** a property or node - different policy field (`allowed_deletes`);
- wants to **read** data - use [`indykite-ciq-read`](../indykite-ciq-read/SKILL.md);
- is using the Capture API to ingest data - different ingestion path.

## Prerequisites

- An IndyKite **project**, **AppAgent**, and AppAgent **credentials** (the AppAgent token goes into `X-IK-ClientKey` at execute time).
- A **Service Account token** with Config API access, and the project's GID in `PROJECT_GID` - both used to *create* the policy and Knowledge Query.
- The **target node already in the IKG** - CIQ doesn't seed it; this policy authorises modifying its properties.
- A clear **list of property names** the policy/KQ will write. Property names must be hardcoded in the KQ; only values and metadata may be `$param`.
- For non-`_Application` subjects, the **subject's** node also already in the IKG.

If any of these are missing, stop and tell the user - fixing them first is much cheaper than debugging a vague `403` or empty result.

## Steps

### 1. Pick the subject and the cypher anchor

**Subject type** - pick one. The schema is identical across both choices; only `subject.type`, the filter, and the execute-time auth differ:

| Subject           | Use when                                                       | Auth at execute time                                | Filter convention                              |
|-------------------|----------------------------------------------------------------|------------------------------------------------------|------------------------------------------------|
| `_Application`    | System-side / ETL / catalog work; no user in the loop.          | `X-IK-ClientKey` only.                               | `subject.external_id = $_appId` (reserved).    |
| `Person` / `User` | The authenticated user is performing the operation themselves.  | `X-IK-ClientKey` + `Authorization: Bearer <token>`.  | `subject.external_id = $token.sub`.            |

A policy is restricted to a single subject type - if both should be allowed, write two policies. The runnable example below uses `Person` ("update own profile"); an `_Application` variant - for example, an ETL job that backfills `imported_at` timestamps - differs only in `subject.type`, the filter, and the execute headers.

**Cypher pattern** - the `MATCH` clause that **resolves the node you intend to update**. The variable name you use here is what `existing_nodes` and `upsert_nodes[].name` will reference. The simplest case is `MATCH (subject:Person)` (the subject node itself); the more general case walks a path to a related node, e.g. `MATCH (subject:Person)-[:OWNS]->(car:Car)-[:HAS]->(ln:LicenseNumber)`. If the exact node types, relationship types, or property spellings in the project's IKG are unknown, read them from the Data Schema API first ([`indykite-data-schema`](../indykite-data-schema/SKILL.md)) - a typoed name silently matches nothing, and a write whose pattern matches nothing is a no-op that still returns `200`.

Working example (used throughout this skill, modelled on the music-dataset Chapter 8 `ciqpolicy4`):

> A `Person` updates their own profile properties (e.g. `music_mood`, `dance_skill`).

```cypher
MATCH (subject:Person)
```

Variable: `subject`. The KQ will reference this name in `upsert_nodes`.

### 2. Author the policy with `allowed_upserts.nodes.existing_nodes`

Build the policy JSON with four blocks:

- `meta.policy_version` - currently `1.0-ciq`.
- `subject.type` - `Person` for the running example.
- `condition.cypher` and `condition.filter` - anchor the node to update. For `Person`, filter on `subject.external_id = $token.sub`.
- `allowed_upserts.nodes.existing_nodes` - array of variables from `cypher` whose properties the Knowledge Query may write. The Knowledge Query's `upsert_nodes[].name` must be in this list.

**Omit** `allowed_reads`, `allowed_deletes`, and the other `allowed_upserts` sub-fields if this policy only writes properties. Combining with `allowed_reads` is common in practice (read-and-update-own-profile patterns) but kept out of scope here for clarity.

A complete write-only policy for the running example: see [`assets/policy-update-own-profile.json`](assets/policy-update-own-profile.json).

Create it through the Config API:

```bash
# set the current project_id, and stringify only the `policy` field, before POSTing
jq --arg pid "$PROJECT_GID" '.project_id = $pid | .policy |= tojson' indykite-ciq-add-property/assets/policy-update-own-profile.json \
  | curl -X POST "$API_URL/configs/v1/authorization-policies" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $SERVICE_ACCOUNT_TOKEN" \
      -d @-
```

A `201 Created` returns the policy's `id` (GID). Export it as `POLICY_ID` - the Knowledge Query create injects it into `policy_id`.

For the full schema (why we omit `node_types`, the `_Application` variant, the metadata variant from `policyMetaData`) see [`references/policy-reference.md`](references/policy-reference.md).

### 3. Create the Knowledge Query with `upsert_nodes`

The Knowledge Query references the policy. Each entry in `upsert_nodes` describes one node-update:

- `name` - **must** match a variable from the policy's `cypher` (e.g. `subject`, `car`, `ln`). This is what differs structurally from the create-node skill; using a fresh name here would imply create.
- `type` - *omit* when updating an existing node. (For creates it would specify the new node's label; for updates the label is whatever the matched node already has.)
- `external_id` - **omit**. Required only for creates.
- `properties` - array of `{type, value, metadata?}` items. `type` (property name) is hardcoded; `value` may be hardcoded or `$param`; `metadata` is optional and follows the same rules.

Echo the result back in the response by listing properties to project in the top-level `nodes` array, e.g. `subject.property.music_mood`. This confirms the value that was written.

A complete Knowledge Query for the running example: see [`assets/knowledge-query-update-own-profile.json`](assets/knowledge-query-update-own-profile.json).

Create it through the Config API:

```bash
# set the current project_id and policy_id, and stringify only the `query` field, before POSTing
jq --arg pid "$PROJECT_GID" --arg polid "$POLICY_ID" '.project_id = $pid | .policy_id = $polid | .query |= tojson' indykite-ciq-add-property/assets/knowledge-query-update-own-profile.json \
  | curl -X POST "$API_URL/configs/v1/knowledge-queries" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $SERVICE_ACCOUNT_TOKEN" \
      -d @-
```

A `201 Created` returns the Knowledge Query's `id` (GID).

Schema details - including the protected property names you cannot set (`_service`, `create_time`, `external_id`, `id`, `type`, `update_time`), the metadata sub-array, and the rich `knowledgeQueryMetaData` example with `$token.iss` substitution - live in [`references/knowledge-query-reference.md`](references/knowledge-query-reference.md).

### 4. Authenticate and execute

The execute endpoint is the same as for reads, node-creates, and relationship-creates:

```text
POST <API_URL>/contx-iq/v1/execute
```

Authentication for the running `Person`-subject example:

- `X-IK-ClientKey: <AppAgent-credentials-token>` - required.
- `Authorization: Bearer <user-access-token>` - required. The token's `sub` claim drives `$token.sub` in the policy filter, pinning the cypher anchor to that one user.

For `_Application`-subject property writes, omit the Bearer header; the reserved `$_appId` is auto-filled from the AppAgent.

Request:

```json
{
  "id": "<knowledge_query_gid_or_name>",
  "input_params": {
    "new_music_mood":  "Acoustic Sadness",
    "new_dance_skill": 0.67
  }
}
```

A runnable shell helper: [`scripts/execute.sh`](scripts/execute.sh).

Full execute reference (auth combinations, response shape, error semantics): [`references/execution-reference.md`](references/execution-reference.md).

### 5. Verify the response and confirm the property write

A successful property-write execute echoes the projection you listed in the KQ's `nodes` array:

```json
{
  "data": [
    {
      "nodes": {
        "subject.property.music_mood":  "Acoustic Sadness",
        "subject.property.dance_skill": 0.67
      }
    }
  ]
}
```

If the response is **not** what you expected, walk this list before changing the policy or KQ:

1. **Variable in `existing_nodes`.** The KQ's `upsert_nodes[].name` must be in the policy's `allowed_upserts.nodes.existing_nodes`. Mismatch → `403`.
2. **Cypher matched a node.** If the cypher returns no rows (e.g. the user's `external_id` isn't seeded as a Person), the upsert has nothing to attach to - `200` with empty `data`.
3. **`name` matches a cypher variable.** Using a fresh name (one not in cypher) makes the platform interpret the entry as a create - usually rejected because the matching `node_types` whitelist isn't there.
4. **No `external_id` in the `upsert_nodes` entry.** Including `external_id` flips the operation to "create" semantics. For property writes on an existing match, omit it.
5. **Property names not protected.** `_service`, `create_time`, `external_id`, `id`, `type`, `update_time` cannot be set as properties - they're managed by the platform.
6. **Property value type matches the IKG schema.** Sending `"-7.5"` (string) for a numeric property is rejected.

For other failure modes (auth shape wrong, missing input_params, metadata weirdness) see [`references/troubleshooting.md`](references/troubleshooting.md).

## Outcome

When this skill has been applied successfully:

- A property-write CIQ policy exists; it has a single `subject.type`, a Cypher pattern that resolves to the node to update, optional partial filters, and an `allowed_upserts.nodes.existing_nodes` whitelist - no `node_types`, no `allowed_reads`, no `allowed_deletes`.
- A Knowledge Query references that policy and lists `upsert_nodes` entries that reuse cypher variable names, omit `external_id`, and declare the properties (and optional metadata) to set.
- `POST /contx-iq/v1/execute` returns the projected property values, confirming the write.
- A follow-up read query (e.g. via [`indykite-ciq-read`](../indykite-ciq-read/SKILL.md)) finds the new property values on the node.

## Files in this skill

- [`references/policy-reference.md`](references/policy-reference.md) - write-focused policy schema, `existing_nodes` deep-dive, the Person and `_Application` patterns, why other blocks are omitted.
- [`references/knowledge-query-reference.md`](references/knowledge-query-reference.md) - `upsert_nodes` for updates (variable from cypher, no `external_id`), properties + metadata, the `knowledgeQueryMetaData` rich example, protected property names.
- [`references/execution-reference.md`](references/execution-reference.md) - `POST /contx-iq/v1/execute` for property writes, auth combinations, response shape including the rich `Props` block.
- [`references/troubleshooting.md`](references/troubleshooting.md) - `403` / empty-`data` / type-mismatch / metadata patterns.
- [`assets/policy-update-own-profile.json`](assets/policy-update-own-profile.json) - runnable Person-subject "update own profile" policy, modelled on music-dataset Chapter 8 `ciqpolicy4`.
- [`assets/knowledge-query-update-own-profile.json`](assets/knowledge-query-update-own-profile.json) - matching Knowledge Query (sets `music_mood` and `dance_skill`).
- [`scripts/execute.sh`](scripts/execute.sh) - Bash helper that posts to `/contx-iq/v1/execute` with the right headers.

## Agent-specific notes

This skill uses generic markdown instructions and works across all agents listed in the [README](../README.md). The agent needs to be able to issue HTTP requests (`curl`, an HTTP client, or the IndyKite Terraform provider). No Claude Code hooks, Cursor `@`-mentions, or Copilot workspace context are required.

## References

- [ContX IQ guide (developer hub)](https://developer.indykite.com/guides/guide-contx-iq) - full schema, including `allowed_upserts.nodes.existing_nodes` and the `properties` / `metadata` arrays.
- [Music dataset tutorial - Chapter 8 "ContX IQ policies"](https://developer.indykite.com/tutorials/tutorial-music-dataset) - `ciqpolicy4` is the canonical Person-subject "update own data" pattern; `kq4b` is its write variant.
- [Music dataset tutorial - Chapter 9 "Knowledge Queries"](https://developer.indykite.com/tutorials/tutorial-music-dataset) - read/write/delete variant naming convention (`kq` / `kqb` / `kqc`).
- [Developer-hub resources - CIQ examples](https://developer.indykite.com/resources) - `policyMetaData` + `knowledgeQueryMetaData` show a richer property-write pattern with `$token.iss` substitution and per-property metadata.
- [Config API documentation](https://openapi.indykite.com/api-documentation-config)
- [Cypher query language manual (Neo4j; openCypher)](https://neo4j.com/docs/cypher-manual/current/) - the graph query language used in CIQ policy and Knowledge Query conditions over the IndyKite Knowledge Graph.
- [IndyKite Terraform provider](https://registry.terraform.io/providers/indykite/indykite/latest/docs)
- [Credentials guide](https://developer.indykite.com/guides/guide-credentials)

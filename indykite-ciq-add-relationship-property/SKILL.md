---
name: indykite-ciq-add-relationship-property
description: Author an IndyKite ContX IQ (CIQ) policy plus its Knowledge Query that sets one or more properties on an existing relationship in the IndyKite Graph (IKG), then run it via `POST /contx-iq/v1/execute`. Use when adding a brand-new property, overwriting an existing one, or attaching property metadata on a relationship that's already in the IKG - no relationship creation, no node writes, no deletes.
license: Apache-2.0
compatibility: Requires curl, bash 4+, and jq. Network access to the regional IndyKite REST API (eu.api.indykite.com or us.api.indykite.com) is required at runtime.
---

# IndyKite ContX IQ - add a property to an existing relationship

A CIQ relationship-property-write policy declares an `allowed_upserts.relationships.existing_relationships` whitelist of relationship variables from the policy's `cypher` whose properties may be modified. The Knowledge Query's `upsert_relationships` references those variables (no `source`/`target`/`type`, since the relationship already exists) and lists the properties to set, optionally with metadata. Adding a brand-new property and overwriting an existing one are the **same operation** - the platform doesn't distinguish.

This skill is the relationship counterpart to [`indykite-ciq-add-property`](../indykite-ciq-add-property/SKILL.md), which sets properties on existing **nodes**. The structure is symmetric; the field names are different.

Other paths are deliberately out of scope:

- **Creating a brand-new relationship** uses `allowed_upserts.relationships.relationship_types` and a Knowledge Query `upsert_relationships` entry with a fresh `name` + `source`/`target`/`type` - see [`indykite-ciq-create-relationship`](../indykite-ciq-create-relationship/SKILL.md).
- **Setting properties on a node** uses `allowed_upserts.nodes.existing_nodes` - see [`indykite-ciq-add-property`](../indykite-ciq-add-property/SKILL.md).
- **Deleting a property on a relationship** uses `allowed_deletes.relationships` with a `<var>.<property>` path - see [`indykite-ciq-delete`](../indykite-ciq-delete/SKILL.md).

For reads, see [`indykite-ciq-read`](../indykite-ciq-read/SKILL.md).

## When to use

Activate this skill when the user:

- wants to **set a property** on a relationship that already exists in the IKG (e.g. add `verified: true` to an existing `:PLAYED_AT`, set `weight` on an existing `:LIKES`, attach `confidence` metadata to an existing `:OWNS` edge);
- is annotating an existing relationship with provenance, trust score, or audit fields after the fact;
- is debugging a `403` / `422` from a relationship-property-write execute that should have succeeded.

Do **not** activate this skill when the user:

- wants to **create a new relationship** between two existing nodes - use [`indykite-ciq-create-relationship`](../indykite-ciq-create-relationship/SKILL.md);
- wants to **set properties on a node** - use [`indykite-ciq-add-property`](../indykite-ciq-add-property/SKILL.md);
- wants to **delete** a property - use [`indykite-ciq-delete`](../indykite-ciq-delete/SKILL.md);
- wants to **read** data - use [`indykite-ciq-read`](../indykite-ciq-read/SKILL.md);
- is using the Capture API to ingest data - different ingestion path.

## Prerequisites

- An IndyKite **project**, **AppAgent**, and AppAgent **credentials** (the AppAgent token goes into `X-IK-ClientKey` at execute time).
- A **Service Account token** with Config API access, and the project's GID in `PROJECT_GID` - both used to *create* the policy and Knowledge Query.
- The **target relationship already in the IKG**, plus both endpoint nodes.
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

A policy is restricted to a single subject type - if both should be allowed, write two policies. The runnable example below uses `_Application` (system-side annotation pass on existing edges); a `Person` variant - for example, a user marking their own `:LIKES` edge as `priority` - differs only in `subject.type`, the filter, and the execute headers.

**Cypher pattern** - must `MATCH` the existing relationship and bind it to a variable. The variable name is what `existing_relationships` and `upsert_relationships[].name` reference. Pin both endpoints by `external_id` in the filter so the relationship is uniquely identified.

Working example (used throughout this skill):

> An `_Application` annotates an existing `(:Track)-[:PLAYED_AT]->(:Venue)` relationship by setting a `verified` flag and a `first_played_at` timestamp.

```cypher
MATCH (subject:_Application)
MATCH (track:Track)-[r:PLAYED_AT]->(venue:Venue)
```

Variables: `subject`, `track`, `r`, `venue`. The relationship variable `r` is the one we're updating.

### 2. Author the policy with `allowed_upserts.relationships.existing_relationships`

Build the policy JSON with four blocks:

- `meta.policy_version` - currently `1.0-ciq`.
- `subject.type` - `_Application` for the running example.
- `condition.cypher` and `condition.filter` - the cypher matches the existing relationship; the filter pins `subject.external_id = $_appId` (reserved) plus the source and target endpoints by `external_id`.
- `allowed_upserts.relationships.existing_relationships` - array of relationship variables from `cypher` whose properties the Knowledge Query may write. The Knowledge Query's `upsert_relationships[].name` must be in this list.

**Omit** `allowed_reads`, `allowed_deletes`, and the other `allowed_upserts` sub-fields if this policy only writes relationship properties.

A complete write-only policy for the running example: see [`assets/policy-annotate-played-at.json`](assets/policy-annotate-played-at.json).

Create it through the Config API:

```bash
# set the current project_id, and stringify only the `policy` field, before POSTing
jq --arg pid "$PROJECT_GID" '.project_id = $pid | .policy |= tojson' indykite-ciq-add-relationship-property/assets/policy-annotate-played-at.json \
  | curl -X POST "$API_URL/configs/v1/authorization-policies" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $SERVICE_ACCOUNT_TOKEN" \
      -d @-
```

A `201 Created` returns the policy's `id` (GID). Export it as `POLICY_ID` - the Knowledge Query create injects it into `policy_id`.

For the full schema (why we omit `relationship_types`, the Person variant, the protected property names) see [`references/policy-reference.md`](references/policy-reference.md).

### 3. Create the Knowledge Query with `upsert_relationships`

The Knowledge Query references the policy. Each entry in `upsert_relationships` describes one relationship-update:

- `name` - **must** match a relationship variable from the policy's `cypher` (e.g. `r`). This is what differs structurally from the create-relationship skill; using a fresh name here would imply create.
- `source` / `target` / `type` - *omit* when updating an existing relationship. The endpoints and label come from the matched edge; specifying them is unnecessary and can confuse the platform.
- `properties` - array of `{type, value, metadata?}` items. Same shape as for nodes.

Echo the result back in the response by listing properties to project in the top-level `relationships` and/or `nodes` arrays.

A complete Knowledge Query for the running example: see [`assets/knowledge-query-annotate-played-at.json`](assets/knowledge-query-annotate-played-at.json).

Create it through the Config API:

```bash
# set the current project_id and policy_id, and stringify only the `query` field, before POSTing
jq --arg pid "$PROJECT_GID" --arg polid "$POLICY_ID" '.project_id = $pid | .policy_id = $polid | .query |= tojson' indykite-ciq-add-relationship-property/assets/knowledge-query-annotate-played-at.json \
  | curl -X POST "$API_URL/configs/v1/knowledge-queries" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $SERVICE_ACCOUNT_TOKEN" \
      -d @-
```

A `201 Created` returns the Knowledge Query's `id` (GID).

Schema details - including the protected property names you cannot set (`_service`, `create_time`, `id`, `type`, `update_time`) and the metadata sub-array - live in [`references/knowledge-query-reference.md`](references/knowledge-query-reference.md).

### 4. Authenticate and execute

The execute endpoint is the same as for reads, node-property-writes, and the create skills:

```text
POST <API_URL>/contx-iq/v1/execute
```

Authentication for the running `_Application`-subject example:

- `X-IK-ClientKey: <AppAgent-credentials-token>` - required.
- `Authorization: Bearer …` - **omit** for `_Application`.

For Person-subject relationship-property writes, add `Authorization: Bearer <user-access-token>`.

Request:

```json
{
  "id": "<knowledge_query_gid_or_name>",
  "input_params": {
    "track_external_id": "track-99",
    "venue_external_id": "venue-1",
    "first_played_at":   "2026-04-22T19:00:00Z"
  }
}
```

A runnable shell helper: [`scripts/execute.sh`](scripts/execute.sh).

Full execute reference: [`references/execution-reference.md`](references/execution-reference.md).

### 5. Verify the response and confirm the property write

A successful relationship-property write returns the projection you requested:

```json
{
  "data": [
    {
      "relationships": {
        "r": {
          "Id": 1152932499723124700,
          "ElementId": "5:3a2b09d5-…:1152932499723124736",
          "Props": {
            "verified":         true,
            "first_played_at":  "2026-04-22T19:00:00Z"
          }
        }
      }
    }
  ]
}
```

If the response is **not** what you expected, walk this list:

1. **Variable in `existing_relationships`.** The KQ's `upsert_relationships[].name` must be in the policy's `existing_relationships` list. Mismatch → `403`.
2. **Cypher matched a relationship.** If the cypher returns no rows (e.g. the source or target `external_id` isn't seeded, or the `:PLAYED_AT` edge doesn't exist), the upsert has nothing to attach to - `200` with empty `data`.
3. **`name` matches a cypher variable.** Using a fresh name implies create; rejected unless `relationship_types` is also declared.
4. **No `source` / `target` / `type` in the `upsert_relationships` entry.** Including any of these flips the operation to "create" semantics.
5. **Property names not protected.** `_service`, `create_time`, `id`, `type`, `update_time` cannot be set as relationship properties.

For other failure modes see [`references/troubleshooting.md`](references/troubleshooting.md).

## Outcome

When this skill has been applied successfully:

- A relationship-property-write CIQ policy exists; it has a single `subject.type`, a Cypher pattern that matches the relationship to update, partial filters pinning the endpoints by `external_id`, and an `allowed_upserts.relationships.existing_relationships` whitelist.
- A Knowledge Query references that policy and lists `upsert_relationships` entries that reuse cypher variable names, omit `source`/`target`/`type`, and declare the properties to set.
- `POST /contx-iq/v1/execute` returns the projected property values, confirming the write.
- A follow-up read (e.g. via [`indykite-ciq-read`](../indykite-ciq-read/SKILL.md)) finds the new property values on the relationship.

## Files in this skill

- [`references/policy-reference.md`](references/policy-reference.md) - policy schema, `existing_relationships` deep-dive, why other blocks are omitted.
- [`references/knowledge-query-reference.md`](references/knowledge-query-reference.md) - `upsert_relationships` for updates (variable from cypher, no `source`/`target`/`type`), properties + metadata, protected names.
- [`references/execution-reference.md`](references/execution-reference.md) - `POST /contx-iq/v1/execute` for relationship-property writes, response shape with the relationship's `Props` block.
- [`references/troubleshooting.md`](references/troubleshooting.md) - symptom → fix tables.
- [`assets/policy-annotate-played-at.json`](assets/policy-annotate-played-at.json) - runnable `_Application` annotates `:PLAYED_AT` policy.
- [`assets/knowledge-query-annotate-played-at.json`](assets/knowledge-query-annotate-played-at.json) - matching Knowledge Query.
- [`scripts/execute.sh`](scripts/execute.sh) - Bash helper.

## Agent-specific notes

This skill uses generic markdown instructions and works across all agents listed in the [README](../README.md). The agent needs to be able to issue HTTP requests (`curl`, an HTTP client, or the IndyKite Terraform provider). No Claude Code hooks, Cursor `@`-mentions, or Copilot workspace context are required.

## References

- [ContX IQ guide (developer hub)](https://developer.indykite.com/guides/guide-contx-iq) - full schema, including `allowed_upserts.relationships.existing_relationships`.
- [Music dataset tutorial - Chapter 8 "ContX IQ policies" and Chapter 9 "Knowledge Queries"](https://developer.indykite.com/tutorials/tutorial-music-dataset) - read/write/delete variant naming convention.
- [Developer-hub resources - CIQ examples](https://developer.indykite.com/resources) - the `policyMetaData` / `knowledgeQueryMetaData` pair shows the analogous node-property write; this skill applies the same pattern to relationship variables.
- [Config API documentation](https://openapi.indykite.com/api-documentation-config)
- [Cypher query language manual (Neo4j; openCypher)](https://neo4j.com/docs/cypher-manual/current/) - the graph query language used in CIQ policy and Knowledge Query conditions over the IndyKite Knowledge Graph.
- [IndyKite Terraform provider](https://registry.terraform.io/providers/indykite/indykite/latest/docs)

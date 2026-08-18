---
name: indykite-ciq-delete
description: Author an IndyKite ContX IQ (CIQ) policy plus its Knowledge Query that deletes a node, a relationship, or one or more properties from the IndyKite Graph (IKG), then run it via `POST /contx-iq/v1/execute`. Use when removing data through CIQ - three modes (whole node, whole relationship, individual property) sharing the same policy/KQ shape.
license: Apache-2.0
compatibility: Requires curl, bash 4+, and jq. Network access to the regional IndyKite REST API (eu.api.indykite.com or us.api.indykite.com) is required at runtime.
---

# IndyKite ContX IQ - delete a node, relationship, or property

Delete a node, a relationship, or individual properties from the IndyKite Graph (IKG), driven by a ContX IQ policy + Knowledge Query and run via `POST /contx-iq/v1/execute`. Two policy fields (`allowed_deletes.nodes`, `allowed_deletes.relationships`) and two Knowledge Query arrays (`delete_nodes`, `delete_relationships`) drive it: pass a variable name from the policy's `cypher` to delete the whole element, or `<var>.<property>` (or `<var>.property.<name>` for nodes) to delete only one property. Three modes share the same operation surface.

| Mode                          | Policy field                              | KQ array                | KQ entry shape                                     |
|-------------------------------|-------------------------------------------|-------------------------|----------------------------------------------------|
| Delete a whole **node**       | `allowed_deletes.nodes: ["car"]`           | `delete_nodes`          | `"car"` - the cypher variable                       |
| Delete a single **node property** | `allowed_deletes.nodes: ["car.property.color"]` | `delete_nodes`     | `"car.property.color"` - variable + property path   |
| Delete a whole **relationship** | `allowed_deletes.relationships: ["r"]`     | `delete_relationships`  | `"r"` - the cypher variable                         |
| Delete a single **relationship property** | `allowed_deletes.relationships: ["r.status"]` | `delete_relationships` | `"r.status"` - variable + property name      |

This skill covers all four sub-cases. The runnable example focuses on the most common case (delete a property on the caller's own Person node), with the other modes documented in the references and the policy snippets.

For creates, see [`indykite-ciq-create-node`](../indykite-ciq-create-node/SKILL.md) / [`indykite-ciq-create-relationship`](../indykite-ciq-create-relationship/SKILL.md). For property writes, see [`indykite-ciq-add-property`](../indykite-ciq-add-property/SKILL.md) / [`indykite-ciq-add-relationship-property`](../indykite-ciq-add-relationship-property/SKILL.md). For reads, see [`indykite-ciq-read`](../indykite-ciq-read/SKILL.md).

## When to use

Activate this skill when the user:

- wants to **remove** a node, relationship, or property from the IKG through CIQ;
- is implementing a "right to be forgotten" or GDPR-style data-erasure path on an authenticated user's own data;
- is unwiring a stale `:PLAYED_AT`, `:OWNS`, or other relationship that should no longer apply;
- is clearing a property that was set by mistake (with the understanding that property-writes overwrite, but only `delete_nodes` actually removes a property);
- is debugging a `403` / `200`-empty / `delete didn't happen` situation on a CIQ delete call.

Do **not** activate this skill when the user:

- wants to **create** a node or relationship - use [`indykite-ciq-create-node`](../indykite-ciq-create-node/SKILL.md) or [`indykite-ciq-create-relationship`](../indykite-ciq-create-relationship/SKILL.md);
- wants to **set** a property - use [`indykite-ciq-add-property`](../indykite-ciq-add-property/SKILL.md) or [`indykite-ciq-add-relationship-property`](../indykite-ciq-add-relationship-property/SKILL.md);
- wants to **read** data - use [`indykite-ciq-read`](../indykite-ciq-read/SKILL.md);
- needs to delete a **protected property** (`_service`, `create_time`, `external_id`, `id`, `type`, `update_time`) - those are platform-managed and cannot be deleted.

## Prerequisites

- An IndyKite **project**, **AppAgent**, and AppAgent **credentials**.
- A **Service Account token** with Config API access, and the project's GID in `PROJECT_GID` - both used to *create* the policy and Knowledge Query.
- The **target node, relationship, or property already in the IKG**.
- For non-`_Application` subjects, the **subject's** node also already in the IKG.

If any of these are missing, stop and tell the user.

## Steps

### 1. Pick the subject and the cypher anchor

**Subject type** - pick one. The schema is identical across both choices; only `subject.type`, the filter, and the execute-time auth differ:

| Subject           | Use when                                                       | Auth at execute time                                | Filter convention                              |
|-------------------|----------------------------------------------------------------|------------------------------------------------------|------------------------------------------------|
| `_Application`    | System-side / ETL / catalog work; no user in the loop.          | `X-IK-ClientKey` only.                               | `subject.external_id = $_appId` (reserved).    |
| `Person` / `User` | The authenticated user is performing the operation themselves.  | `X-IK-ClientKey` + `Authorization: Bearer <token>`.  | `subject.external_id = $token.sub`.            |

A policy is restricted to a single subject type - if both should be allowed, write two policies. The runnable example below uses `Person` (user clears their own profile property); an `_Application` variant - for example, an ETL job pruning stale `:PLAYED_AT` edges - differs only in `subject.type`, the filter, and the execute headers.

**Cypher pattern** - must `MATCH` the element you want to delete and bind it to a variable. For deleting a node or its property, match the node. For deleting a relationship or its property, match the relationship. If the exact node types, relationship types, or property spellings in the project's IKG are unknown, read them from the Data Schema API first ([`indykite-data-schema`](../indykite-data-schema/SKILL.md)) - a typoed name silently matches nothing, and a delete whose pattern matches nothing is a no-op that still returns `200`.

Working example (used throughout this skill):

> A `Person` clears their own `music_mood` profile property.

```cypher
MATCH (subject:Person)
```

Variable: `subject`. The KQ will reference this in `delete_nodes`.

### 2. Author the policy with `allowed_deletes`

Build the policy JSON with four blocks:

- `meta.policy_version` - currently `1.0-ciq`.
- `subject.type` - `Person` for the running example.
- `condition.cypher` and `condition.filter` - anchor the element. For `Person`, filter on `subject.external_id = $token.sub`.
- `allowed_deletes` - at least one of `nodes` or `relationships`. Each entry is either a bare variable name (delete the whole element) or `<var>.<property>` / `<var>.property.<name>` (delete a property only).

**Omit** `allowed_reads` and `allowed_upserts` if this policy only deletes.

A complete delete-only policy for the running example: see [`assets/policy-delete-music-mood.json`](assets/policy-delete-music-mood.json).

Create it through the Config API:

```bash
# set the current project_id, and stringify only the `policy` field, before POSTing
jq --arg pid "$PROJECT_GID" '.project_id = $pid | .policy |= tojson' indykite-ciq-delete/assets/policy-delete-music-mood.json \
  | curl -X POST "$API_URL/configs/v1/authorization-policies" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $SERVICE_ACCOUNT_TOKEN" \
      -d @-
```

A `201 Created` returns the policy's `id` (GID). Export it as `POLICY_ID` - the Knowledge Query create injects it into `policy_id`.

For the four `allowed_deletes` modes, the wildcard form (`<var>.*`), and why we omit `allowed_reads` and `allowed_upserts`, see [`references/policy-reference.md`](references/policy-reference.md).

### 3. Create the Knowledge Query with `delete_nodes` and/or `delete_relationships`

The Knowledge Query references the policy. For each thing to delete, list it:

- `delete_nodes` - array of variable names or `<var>.property.<name>` paths. Must match entries in the policy's `allowed_deletes.nodes`.
- `delete_relationships` - array of variable names or `<var>.<property>` paths. Must match entries in the policy's `allowed_deletes.relationships`.

A single KQ may delete multiple things in one execute (e.g. several properties at once, or a property *and* a relationship). Each entry is constrained by the policy's whitelist.

A complete delete-property Knowledge Query for the running example: see [`assets/knowledge-query-delete-music-mood.json`](assets/knowledge-query-delete-music-mood.json).

Create it through the Config API:

```bash
# set the current project_id and policy_id, and stringify only the `query` field, before POSTing
jq --arg pid "$PROJECT_GID" --arg polid "$POLICY_ID" '.project_id = $pid | .policy_id = $polid | .query |= tojson' indykite-ciq-delete/assets/knowledge-query-delete-music-mood.json \
  | curl -X POST "$API_URL/configs/v1/knowledge-queries" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $SERVICE_ACCOUNT_TOKEN" \
      -d @-
```

A `201 Created` returns the Knowledge Query's `id` (GID).

Schema details for all four modes - including the protected property names you cannot delete and the wildcard syntax - live in [`references/knowledge-query-reference.md`](references/knowledge-query-reference.md).

### 4. Authenticate and execute

The execute endpoint is the same as for every other CIQ operation:

```text
POST <API_URL>/contx-iq/v1/execute
```

Authentication for the running `Person`-subject example:

- `X-IK-ClientKey: <AppAgent-credentials-token>` - required.
- `Authorization: Bearer <user-access-token>` - required. The token's `sub` claim drives `$token.sub`.

For `_Application`-subject deletes, omit the Bearer header.

Request:

```json
{
  "id": "<knowledge_query_gid_or_name>",
  "input_params": {}
}
```

(For the running example, identity comes from the Bearer token, so `input_params` is empty. Other delete policies may require `$param`s for endpoint pinning - supply them as usual.)

A runnable shell helper: [`scripts/execute.sh`](scripts/execute.sh).

Full execute reference: [`references/execution-reference.md`](references/execution-reference.md).

### 5. Verify the response and confirm the delete

A successful delete execute returns an empty or near-empty `data` array:

```json
{
  "data": [
    { "nodes": {} }
  ]
}
```

The deletion happened if you reach `200`. To confirm:

1. **Re-run the same query.** A second call should return `200` again - deletes are idempotent (deleting an already-missing property is not an error).
2. **Run a paired read query** that projects the deleted property/element. The property is gone (`null`/missing) or the element is gone (empty `data`).
3. **Check the node's `update_time`** if you deleted a property from a node - the platform bumps it on every write or delete.

If the response is **not** what you expected, walk this list:

1. **Variable in the right `allowed_deletes` field.** Property paths under nodes go in `allowed_deletes.nodes` (e.g. `"car.property.color"`); under relationships in `allowed_deletes.relationships` (e.g. `"r.status"`).
2. **Cypher matched the element.** If the cypher returns no rows, the delete has nothing to act on - `200` with empty `data`. That's not an error; the delete just didn't apply.
3. **Property name not in the protected set.** `_service`, `create_time`, `external_id`, `id`, `type`, `update_time` cannot be deleted.
4. **No `external_id` confusion.** Deleting a node deletes it entirely - you cannot "delete only the `external_id`" because that's a protected field.

For other failure modes see [`references/troubleshooting.md`](references/troubleshooting.md).

## Outcome

When this skill has been applied successfully:

- A delete-only CIQ policy exists; it has a single `subject.type`, a Cypher pattern that resolves to the element(s) to delete, optional partial filters, and an `allowed_deletes` whitelist.
- A Knowledge Query references that policy and lists `delete_nodes` and/or `delete_relationships` entries that match the policy's whitelist.
- `POST /contx-iq/v1/execute` returns `200` and the targeted element(s) or property(ies) are gone.
- A follow-up read confirms the deletion.

## Files in this skill

- [`references/policy-reference.md`](references/policy-reference.md) - `allowed_deletes` deep-dive (four modes), the wildcard `<var>.*` form, why other blocks are omitted.
- [`references/knowledge-query-reference.md`](references/knowledge-query-reference.md) - `delete_nodes` and `delete_relationships` schemas, protected property names, multi-delete patterns.
- [`references/execution-reference.md`](references/execution-reference.md) - `POST /contx-iq/v1/execute` for deletes, response shape, idempotence.
- [`references/troubleshooting.md`](references/troubleshooting.md) - `403` / empty-`data` / "delete didn't happen" patterns.
- [`assets/policy-delete-music-mood.json`](assets/policy-delete-music-mood.json) - runnable Person-subject "delete own property" policy.
- [`assets/knowledge-query-delete-music-mood.json`](assets/knowledge-query-delete-music-mood.json) - matching Knowledge Query.
- [`scripts/execute.sh`](scripts/execute.sh) - Bash helper.

## Agent-specific notes

This skill uses generic markdown instructions and works across all agents listed in the [README](../README.md). The agent needs to be able to issue HTTP requests. No Claude Code hooks, Cursor `@`-mentions, or Copilot workspace context are required.

## References

- [ContX IQ guide (developer hub)](https://developer.indykite.com/guides/guide-contx-iq) - full schema for `allowed_deletes` and `delete_nodes` / `delete_relationships`.
- [Music dataset tutorial - Chapter 9 "Knowledge Queries"](https://developer.indykite.com/tutorials/tutorial-music-dataset) - `kqc` is the canonical delete variant in the read/write/delete naming convention.
- [Developer-hub resources - CIQ examples](https://developer.indykite.com/resources) - `policyDeleteProperty` and the `Cars` collection's delete patterns.
- [Config API documentation](https://openapi.indykite.com/api-documentation-config)
- [Cypher query language manual (Neo4j; openCypher)](https://neo4j.com/docs/cypher-manual/current/) - the graph query language used in CIQ policy and Knowledge Query conditions over the IndyKite Knowledge Graph.
- [IndyKite Terraform provider](https://registry.terraform.io/providers/indykite/indykite/latest/docs)

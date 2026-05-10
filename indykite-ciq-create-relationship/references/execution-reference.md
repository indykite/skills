# CIQ Execution Reference (relationship-create flows)

The execution endpoint runs a stored Knowledge Query at runtime, supplying values for any partial filters defined in the policy and any `$param`s in `upsert_relationships`.

## Endpoint

```text
POST <API_URL>/contx-iq/v1/execute
```

`<API_URL>` is the IndyKite API base URL for the project's region (e.g. `https://us.api.indykite.com` or `https://eu.api.indykite.com`).

## Authentication

Same two headers as for reads and node-creates, with the `_Application` twist.

| Subject type             | `X-IK-ClientKey`                       | `Authorization: Bearer …`                                    |
|--------------------------|----------------------------------------|--------------------------------------------------------------|
| `_Application`           | AppAgent credentials token (required)  | **Omit.** The AppAgent itself authenticates the subject.     |
| `Person` / `User` / etc. | AppAgent credentials token (required)  | User OAuth access token (required)                            |

For `_Application` subjects, the reserved `$_appId` parameter is auto-filled from the application's `external_id`. **Do not pass `_appId` in `input_params`**.

For non-`_Application` subjects, the Bearer token's `sub` claim drives `$token.sub` in the policy filter, pinning the cypher subject anchor to that one user.

## Request

```json
{
  "id": "<knowledge_query_gid_or_name>",
  "input_params": {
    "track_external_id": "track-99",
    "venue_external_id": "venue-1"
  }
}
```

Field rules:

- `id` — either the GID returned when you created the Knowledge Query, or its `name`.
- `input_params` — key/value map covering **every** `$param` referenced in:
  - the policy's `condition.filter` (most importantly the source/target `external_id`s),
  - any `upsert_relationships[].properties[].value` declared as `$param`,
  - any property `metadata[].value` declared as `$param`.

Keys are written **without** the leading `$`.

## Response (successful create)

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

The `relationships` block is keyed by the `upsert_relationships[].name`. Fields:

- `Id` / `ElementId` — internal graph identifiers for the new edge.
- `StartId` / `StartElementId` — internal identifiers for the source node.
- `EndId` (and `EndElementId` if present) — internal identifiers for the target node.

You don't need to use these identifiers; they confirm the edge was written and where it points. To reference the relationship in subsequent operations, look it up by `(source.external_id, type, target.external_id)`.

If `relationships` in the KQ is empty, the response succeeds but carries no projection of the new edge — the create still happens, but the caller has no confirmation in the response payload.

A second execute with the same `(source, target, type)` triple is **not an error** — it upserts (matches the existing edge); the response shape is the same. The IKG does not store duplicate parallel edges between the same pair with the same type unless your data model declares them; check the model before relying on this behaviour.

## Error semantics

| HTTP code             | When                                                                                                  | Likely fix                                                                                       |
|-----------------------|-------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------|
| `400 Bad Request`     | Malformed JSON, missing `id`.                                                                          | Fix the request body.                                                                            |
| `401 Unauthorized`    | Missing or invalid `X-IK-ClientKey`, or for non-`_Application` subjects, missing/invalid Bearer.        | Refresh the AppAgent token; for Person subjects, ensure the user token is present and valid.    |
| `403 Forbidden`       | Policy `condition` denied the request *or* `(source-label, type, target-label)` triple is not in `allowed_upserts.relationships.relationship_types`. | Check both the policy's filter (subject + endpoints) and the `relationship_types` whitelist. |
| `422 invalid_argument: missing or wrong input params` | A `$param` referenced in the policy filter or KQ is absent from `input_params`. | Add the missing key to `input_params` (without the leading `$`).                                  |
| `200` with empty `data` | Cypher matched no rows — usually one or both endpoint nodes don't exist with the supplied `external_id`s. | Confirm both endpoints are seeded; spot-check with a read query first.                          |
| `404 Not Found`       | Knowledge Query `id` does not exist or the project does not own it.                                    | Verify the `id` and project context.                                                              |

## Step-up advice (`token_filter`)

If the policy declares a `token_filter` that fails, the response is `403` with `WWW-Authenticate: insufficient_user_authentication` plus the `advice.error` and `advice.error_description` set in the policy. Re-authenticate with the requested factor and retry. Same mechanism as for reads.

## Calling through MCP instead of REST

The MCP server's `ciq_execute` tool wraps the same call and exposes it as a JSON-RPC tool — see [`indykite-mcp-server`](../../indykite-mcp-server/SKILL.md). The wire shape changes (JSON-RPC over HTTP, `Mcp-Session-Id`, `tools/call` envelope) but the underlying authorization, parameters, and response semantics are identical. A relationship-create Knowledge Query authored here can be invoked through MCP without any change to the policy or KQ.

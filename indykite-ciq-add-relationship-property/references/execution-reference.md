# CIQ Execution Reference (relationship-property-write flows)

The execution endpoint runs a stored Knowledge Query at runtime, supplying values for any partial filters defined in the policy and any `$param`s in `upsert_relationships[].properties`.

## Endpoint

```text
POST <API_URL>/contx-iq/v1/execute
```

`<API_URL>` is the IndyKite API base URL for the project's region (e.g. `https://us.api.indykite.com` or `https://eu.api.indykite.com`).

## Authentication

| Subject type             | `X-IK-ClientKey`                       | `Authorization: Bearer …`                                    |
|--------------------------|----------------------------------------|--------------------------------------------------------------|
| `_Application`           | AppAgent credentials token (required)  | **Omit.** The reserved `$_appId` is auto-filled.             |
| `Person` / `User` / etc. | AppAgent credentials token (required)  | User OAuth access token (required). `$token.sub` substituted. |

For non-`_Application` subjects, the Bearer token's `sub` claim drives `$token.sub` in the policy filter. Other token claims like `$token.iss` (issuer) can be used as values inside metadata.

## Request

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

Field rules:

- `id` — either the GID returned when you created the Knowledge Query, or its `name`.
- `input_params` — key/value map covering **every** `$param` referenced in the policy filter, the KQ's `properties[].value`, and any `metadata[].value`. Keys without the leading `$`.

## Response (successful relationship-property write)

The response shape mirrors the projection you requested.

### Property-only projection (when `relationships: ["r"]`)

The full relationship object including its `Props` block:

```json
{
  "data": [
    {
      "relationships": {
        "r": {
          "Id": 1152932499723124700,
          "ElementId": "5:3a2b09d5-…:1152932499723124736",
          "StartId": 0,
          "EndId": 15,
          "Props": {
            "verified":        true,
            "first_played_at": "2026-04-22T19:00:00Z",
            "create_time":     "2025-08-13T17:19:43.014Z",
            "update_time":     "2026-04-22T19:00:01.117Z"
          }
        }
      }
    }
  ]
}
```

The platform-managed `update_time` is bumped on every write — a quick way to confirm a write actually happened.

If `relationships` in the KQ is empty, the response succeeds but carries no projection of the writes — the operation still happens, but the caller has no payload confirmation.

## Error semantics

| HTTP code             | When                                                                                            | Likely fix                                                                                                       |
|-----------------------|-------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------|
| `400 Bad Request`     | Malformed JSON, missing `id`.                                                                    | Fix the request body.                                                                                            |
| `401 Unauthorized`    | Missing or invalid `X-IK-ClientKey`, or for non-`_Application` subjects, missing/invalid Bearer.  | Refresh the AppAgent token; for Person subjects, ensure the user token is present and valid.                    |
| `403 Forbidden`       | KQ's `upsert_relationships[].name` not in policy's `existing_relationships`, *or* a property name is protected. | Add the variable to `existing_relationships` (and republish), or remove the protected property.       |
| `422 invalid_argument: missing or wrong input params` | A `$param` referenced in the policy filter or KQ is absent from `input_params`. | Add the missing key to `input_params` (without the leading `$`).                                                  |
| `200` with empty `data` | Cypher matched no rows — the relationship doesn't exist between the supplied endpoints.        | Confirm the relationship is in the IKG; spot-check with a read query first.                                       |
| `404 Not Found`       | Knowledge Query `id` does not exist or the project does not own it.                              | Verify the `id` and project context.                                                                              |

## Calling through MCP instead of REST

The MCP server's `ciq_execute` tool wraps the same call — see [`indykite-mcp-server`](../../indykite-mcp-server/SKILL.md). The Knowledge Query authored here can be invoked through MCP without any change.

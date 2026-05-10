# CIQ Execution Reference (property-write flows)

The execution endpoint runs a stored Knowledge Query at runtime, supplying values for any partial filters defined in the policy and any `$param`s in `upsert_nodes[].properties`.

## Endpoint

```text
POST <API_URL>/contx-iq/v1/execute
```

`<API_URL>` is the IndyKite API base URL for the project's region (e.g. `https://us.api.indykite.com` or `https://eu.api.indykite.com`).

## Authentication

Two headers — the `_Application` rule from the read/create skills applies here unchanged.

| Subject type             | `X-IK-ClientKey`                       | `Authorization: Bearer …`                                    |
|--------------------------|----------------------------------------|--------------------------------------------------------------|
| `_Application`           | AppAgent credentials token (required)  | **Omit.** The AppAgent itself authenticates the subject.     |
| `Person` / `User` / etc. | AppAgent credentials token (required)  | User OAuth access token (required)                            |

For `_Application` subjects, the reserved `$_appId` parameter is auto-filled from the application's `external_id`. **Do not pass `_appId` in `input_params`**.

For non-`_Application` subjects, the Bearer token's `sub` claim drives `$token.sub` in the policy filter, pinning the cypher subject anchor to that one user. Other token claims like `$token.iss` (issuer) can be used as values inside `upsert_nodes[].properties[].value` or `metadata[].value` — see the music-dataset `knowledgeQueryMetaData` example.

## Request

```json
{
  "id": "<knowledge_query_gid_or_name>",
  "input_params": {
    "new_music_mood":  "Acoustic Sadness",
    "new_dance_skill": 0.67
  }
}
```

Field rules:

- `id` — either the GID returned when you created the Knowledge Query, or its `name`.
- `input_params` — key/value map covering **every** `$param` referenced in:
  - the policy's `condition.filter` (e.g. `$ln_external_id` if the policy pins a specific node),
  - any `upsert_nodes[].properties[].value` declared as `$param`,
  - any property `metadata[].value` declared as `$param`,
  - the Knowledge Query's own `filter` (if it declares one).

Keys are written **without** the leading `$`.

Values are typed: strings stay strings; numbers and booleans pass through. The IKG enforces the underlying property type on write.

## Response (successful property write)

The response shape mirrors the projection you requested in the KQ's `nodes` array.

### Property-only projection

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

### Full-node projection (when `nodes: ["subject"]`)

The response includes the matched node with its complete `Props` block — your written properties **and** the platform-managed fields (`_service`, `create_time`, `external_id`, `id`, `type`, `update_time`):

```json
{
  "data": [
    {
      "nodes": {
        "ln": {
          "Id": 58,
          "ElementId": "4:a5c213aa-…:58",
          "Labels": ["Unique", "Resource", "LicenseNumber"],
          "Props": {
            "_service":       "capture-api",
            "create_time":    "2025-08-13T17:19:43.014Z",
            "external_id":    "ln-xxx",
            "id":             "twixV9zqQniA201VtZdzxw",
            "type":           "LicenseNumber",
            "update_time":    "2025-10-22T09:18:11.001Z",
            "license":        "ln-xxx-value",
            "status":         "Valid"
          }
        }
      }
    }
  ]
}
```

The `update_time` is bumped by the platform on every write; that's a quick way to confirm a write actually happened even if your projection didn't include the property.

### Property-with-metadata projection

```json
{
  "data": [
    {
      "nodes": {
        "ln.property.license":                            "ln-xxx-value",
        "ln.property.license.metadata.source":            "The government",
        "ln.property.status":                             "Valid",
        "ln.property.status.metadata.assurance_level":    2,
        "ln.property.status.metadata.somethingImportant": "supercoolvalue",
        "ln.property.status.metadata.source":             "https://issuer_url"
      }
    }
  ]
}
```

The metadata `source` field shows the value of `$token.iss` substituted by the platform — confirming token-claim substitution worked.

If `nodes` in the KQ is empty, the response succeeds but carries no projection of the writes — the operation still happens, but the caller has no payload confirmation.

## Error semantics

| HTTP code             | When                                                                                            | Likely fix                                                                                                       |
|-----------------------|-------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------|
| `400 Bad Request`     | Malformed JSON, missing `id`.                                                                    | Fix the request body.                                                                                            |
| `401 Unauthorized`    | Missing or invalid `X-IK-ClientKey`, or for non-`_Application` subjects, missing/invalid Bearer.  | Refresh the AppAgent token; for Person subjects, ensure the user token is present and valid.                    |
| `403 Forbidden`       | KQ's `upsert_nodes[].name` not in policy's `existing_nodes`, *or* a property name is protected. | Add the variable to `existing_nodes` (and republish), or remove the protected property from the KQ.              |
| `422 invalid_argument: missing or wrong input params` | A `$param` referenced in the policy filter or KQ is absent from `input_params`. | Add the missing key to `input_params` (without the leading `$`).                                                  |
| `200` with empty `data` | Cypher matched no rows — the target node doesn't exist.                                         | Confirm the target node is seeded; spot-check with a read query first.                                            |
| `404 Not Found`       | Knowledge Query `id` does not exist or the project does not own it.                              | Verify the `id` and project context.                                                                              |

## Step-up advice (`token_filter`)

If the policy declares a `token_filter` that fails, the response is `403` with `WWW-Authenticate: insufficient_user_authentication` plus the `advice.error` and `advice.error_description` set in the policy. Re-authenticate with the requested factor and retry. Same mechanism as for reads.

## Calling through MCP instead of REST

The MCP server's `ciq_execute` tool wraps the same call and exposes it as a JSON-RPC tool — see [`indykite-mcp-server`](../../indykite-mcp-server/SKILL.md). The wire shape changes (JSON-RPC over HTTP, `Mcp-Session-Id`, `tools/call` envelope) but the underlying authorization, parameters, and response semantics are identical. A property-write Knowledge Query authored here can be invoked through MCP without any change to the policy or KQ.

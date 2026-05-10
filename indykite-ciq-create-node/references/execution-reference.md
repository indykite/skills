# CIQ Execution Reference (create flows)

The execution endpoint runs a stored Knowledge Query at runtime, supplying values for any partial filters defined in the policy and any `$param`s in `upsert_nodes`.

## Endpoint

```text
POST <API_URL>/contx-iq/v1/execute
```

`<API_URL>` is the IndyKite API base URL for the project's region (e.g. `https://us.api.indykite.com` or `https://eu.api.indykite.com`).

## Authentication

Two headers, with one twist for `_Application` subjects.

| Subject type             | `X-IK-ClientKey`                       | `Authorization: Bearer …`                                    |
|--------------------------|----------------------------------------|--------------------------------------------------------------|
| `_Application`           | AppAgent credentials token (required)  | **Omit.** The AppAgent itself authenticates the subject.     |
| `Person` / `User` / etc. | AppAgent credentials token (required)  | User OAuth access token (required)                            |

For `_Application` subjects, the reserved `$_appId` parameter is auto-filled from the application's `external_id`. **Do not pass `_appId` in `input_params`** — IndyKite ignores or rejects it.

For non-`_Application` subjects, the Bearer token's `sub` claim drives `$token.sub` in the policy filter, pinning the cypher anchor to that one user.

## Request

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

Field rules:

- `id` — either the GID returned when you created the Knowledge Query, or its `name`.
- `input_params` — key/value map covering **every** `$param` referenced in:
  - the policy's `condition.filter`,
  - the Knowledge Query's `upsert_nodes[].external_id`,
  - any `upsert_nodes[].properties[].value` declared as `$param`,
  - any property `metadata[].value` declared as `$param`.

Keys are written **without** the leading `$` (so `$track_external_id` becomes `"track_external_id"`).

Values are typed: strings stay strings; numbers and booleans pass through. The IKG enforces the underlying property type at write time.

## Response (successful create)

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

The response keys mirror the variables you listed in the Knowledge Query's `nodes` array. If the Knowledge Query's `nodes` is empty, the response succeeds but `data` carries no projection of the new node — only an indication of success.

A second execute with the same `external_id` is **not an error** — it upserts (updates the existing node's properties), and the response shape is the same.

## Error semantics

| HTTP code             | When                                                                                            | Likely fix                                                                                     |
|-----------------------|-------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------|
| `400 Bad Request`     | Malformed JSON, missing `id`.                                                                   | Fix the request body.                                                                          |
| `401 Unauthorized`    | Missing or invalid `X-IK-ClientKey`, or for non-`_Application` subjects, missing/invalid Bearer.  | Refresh the AppAgent token; for Person subjects, ensure the user token is present and valid.   |
| `403 Forbidden`       | Policy `condition` denied the request *or* `upsert_nodes[].type` is not in `allowed_upserts.nodes.node_types`. | Check both the policy's filter (subject + token) and the `node_types` whitelist.               |
| `422 invalid_argument: missing or wrong input params` | A `$param` referenced in the policy filter or KQ is absent from `input_params`. | Add the missing key to `input_params` (without the leading `$`).                                |
| `404 Not Found`       | Knowledge Query `id` does not exist or the project does not own it.                              | Verify the `id` and project context.                                                            |
| `5xx`                 | Server-side issue.                                                                               | Retry with backoff; if persistent, file with the IndyKite team.                                 |

## Step-up advice (`token_filter`)

If the policy declares a `token_filter` that fails (for example, `acr` not strong enough for a write), the response is `403` with `WWW-Authenticate: insufficient_user_authentication` plus the `advice.error` and `advice.error_description` set in the policy. Re-authenticate with the requested factor and retry. Same mechanism as for reads.

## Calling through MCP instead of REST

The MCP server's `ciq_execute` tool wraps the same call and exposes it as a JSON-RPC tool — see [`indykite-mcp-server`](../../indykite-mcp-server/SKILL.md). The wire shape changes (JSON-RPC over HTTP, `Mcp-Session-Id`, `tools/call` envelope) but the underlying authorization, parameters, and response semantics are identical. A create-node Knowledge Query authored here can be invoked through MCP without any change to the policy or KQ.

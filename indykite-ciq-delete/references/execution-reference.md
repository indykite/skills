# CIQ Execution Reference (delete flows)

The execution endpoint runs a stored Knowledge Query at runtime, supplying values for any partial filters defined in the policy.

## Endpoint

```text
POST <API_URL>/contx-iq/v1/execute
```

`<API_URL>` is the IndyKite API base URL for the project's region.

## Authentication

| Subject type             | `X-IK-ClientKey`                       | `Authorization: Bearer …`                                    |
|--------------------------|----------------------------------------|--------------------------------------------------------------|
| `_Application`           | AppAgent credentials token (required)  | **Omit.** The reserved `$_appId` is auto-filled.             |
| `Person` / `User` / etc. | AppAgent credentials token (required)  | User OAuth access token (required). `$token.sub` substituted. |

For non-`_Application` subjects, the Bearer token's `sub` claim drives `$token.sub` in the policy filter, pinning the cypher anchor to that one user.

## Request

```json
{
  "id": "<knowledge_query_gid_or_name>",
  "input_params": {}
}
```

For deletes scoped to "the caller's own data", `input_params` is often empty — identity comes from the Bearer token. For deletes that target a specific external element (e.g. delete the `:PLAYED_AT` between Track X and Venue Y), supply the relevant `$param`s.

## Response (successful delete)

The response shape mirrors any `nodes` / `relationships` projection in the KQ — but for delete-only flows where `nodes` and `relationships` are empty, the response carries an empty (or near-empty) `data`:

```json
{
  "data": [
    { "nodes": {} }
  ]
}
```

This is the "successful delete with no projection" shape. The deletion happened.

If the KQ also reads (e.g. it included an `allowed_reads`-backed `nodes` array), the response includes the projections of *what was deleted* — useful for a human-confirmable audit trail.

## Idempotence and re-runs

Deleting an already-missing property or element returns `200` again with the same shape. There's no error signal that "nothing was there to delete". To verify a delete actually happened, run a paired read query and check the property/element is gone.

The platform bumps `update_time` on the affected node when properties are deleted — that's another way to confirm.

## Error semantics

| HTTP code             | When                                                                                            | Likely fix                                                                                                       |
|-----------------------|-------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------|
| `400 Bad Request`     | Malformed JSON, missing `id`.                                                                    | Fix the request body.                                                                                            |
| `401 Unauthorized`    | Missing or invalid `X-IK-ClientKey`, or for non-`_Application` subjects, missing/invalid Bearer.  | Refresh the AppAgent token; for Person subjects, ensure the user token is present and valid.                    |
| `403 Forbidden`       | KQ's `delete_nodes` / `delete_relationships` entry not in policy's `allowed_deletes`, *or* a target is a protected property. | Add the entry to `allowed_deletes` (and republish), or remove the protected target. |
| `422 invalid_argument: missing or wrong input params` | A `$param` referenced in the policy filter is absent from `input_params`. | Add the missing key (without the `$` prefix).                                                                     |
| `200` with empty `data` | Cypher matched no rows — the target doesn't exist. Or it's already deleted (idempotence).      | If the target should exist: confirm the data is in the IKG. If you're verifying a delete: this is success.        |
| `404 Not Found`       | Knowledge Query `id` does not exist or the project does not own it.                              | Verify the `id` and project context.                                                                              |

## Calling through MCP instead of REST

The MCP server's `ciq_execute` tool wraps the same call — see [`indykite-mcp-server`](../../indykite-mcp-server/SKILL.md). A delete Knowledge Query authored here can be invoked through MCP without any change.

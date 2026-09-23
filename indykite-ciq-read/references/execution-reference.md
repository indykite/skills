# CIQ Execution Reference

The execution endpoint runs a stored Knowledge Query at runtime, supplying values for any partial filters defined in the policy or Knowledge Query.

## Endpoint

```text
POST <API_URL>/contx-iq/v1/execute
```

`<API_URL>` is the IndyKite API base URL for the project's region (e.g. `https://us.api.indykite.com` or `https://eu.api.indykite.com`).

## Authentication

Two layers, like the MCP server — but with one twist for `_Application` subjects.

| Subject type           | `X-IK-ClientKey`                              | `Authorization: Bearer …`                                |
|------------------------|-----------------------------------------------|----------------------------------------------------------|
| `Person` / `User` / etc. | AppAgent credentials token (always required) | User OAuth access token (required)                        |
| `_Application`         | AppAgent credentials token                    | Optional — the AppAgent itself authenticates the subject. |

For non-`_Application` subjects, the Bearer token's `sub` claim is what AuthZEN treats as the subject identifier. If you do not pass a token, the policy effectively has no subject and most filters match nothing.

For `_Application` subjects, the reserved input parameter `$_appId` is auto-filled from the application's `external_id` — **do not** pass it in `input_params` yourself.

**Optional delegation token.** A request that carries a user Bearer token may also carry `X-IK-Token: <delegation-token>` (no prefix), minted by the self-hosted [IndyKite Token Service](https://developer.indykite.com/guides/guide-token-service) and forwarded by the Agent Gateway. It never replaces the Bearer token; it adds the chain of agents acting for that user. The platform validates it through the project's Token Introspect configurations, requires its `sub` to equal the Bearer token's `sub`, and exposes its claims to the policy's `filter` / `token_filter` as `$ik_token` (`$ik_token.act.sub` = the calling agent, `$ik_token.act.act.sub` = the one before it). The name `ik_token` is reserved: a value sent under `input_params.ik_token` is ignored.

## Request

```json
{
  "id": "<knowledge_query_gid_or_name>",
  "input_params": {
    "person_external_id": "alice"
  }
}
```

Field rules:

- `id` — either the GID returned when you created the Knowledge Query, or its `name`.
- `input_params` — key/value map covering **every partial filter** in the policy and Knowledge Query. Keys are written **without** the leading `$` (so policy filter `$person_external_id` becomes `"person_external_id"`).

Values are typed: strings stay strings; numbers and booleans pass through.

## Response

```json
{
  "data": [
    {
      "nodes": {
        "subject.external_id": "alice",
        "car.external_id": "AL98745"
      }
    },
    {
      "relationships": {
        "r.<attr>": "<value>"
      }
    }
  ]
}
```

Each row is keyed `<var>.<attr>` matching the variables you listed in the Knowledge Query's `nodes` / `relationships` / `aggregate_values`. The shape of values depends on what the policy's `allowed_reads` permitted.

An empty `data` array means the policy ran without error but matched no rows. That is **not** an error response — verify the IKG actually contains data for the supplied parameters.

## Error semantics

| HTTP code              | When                                                                                          | Likely fix                                                                                  |
|------------------------|-----------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------|
| `400 Bad Request`      | Missing `id`, malformed JSON, or `input_params` missing a parameter that the policy requires. | Fix the request body; cross-check partial filters listed in the policy.                     |
| `401 Unauthorized`     | Missing or invalid Bearer token (for non-`_Application` subjects), or invalid `X-IK-ClientKey`. | Refresh the AppAgent token; ensure the user token is present and `sub` matches expectations. |
| `401` + `{"message": "Invalid token in X-IK-Token header"}` | The delegation token is expired, untrusted, or matches no Token Introspect configuration. | Create a Token Introspect configuration for the Token Service issuer + audience, or mint a fresh delegation token. |
| `401` + `{"message": "Token in X-IK-Token header carries a different sub than the subject token"}` (or `is missing the sub claim`) | The Bearer token and the delegation token are not about the same user. | Forward both headers exactly as received from the previous hop. |
| `403 Forbidden`        | Policy's `condition` denied the request, or `token_filter` failed.                            | Check `token_filter` `advice`, the subject's relationship to the data, and `$token.*` / `$ik_token.*` values (a referenced token that was not sent fails closed). |
| `403` + `WWW-Authenticate: insufficient_user_authentication` | A `token_filter` triggered step-up advice.                              | Re-authenticate with the requested factor and retry.                                        |
| `404 Not Found`        | Knowledge Query `id` does not exist, or the project does not own it.                          | Verify the Knowledge Query GID/name and the project context.                                |
| `408 Request Timeout`  | Query exceeded the timeout (default few seconds, 5 minutes with `batch_read: true`).          | Set `batch_read: true` if appropriate, or simplify the Cypher.                              |
| `503` + `{"message": "Unable to verify the AppAgent credential token, retry the request"}` | The credential could not be checked right now (transient); it was not judged. | Retry the same request with the same credential, with backoff. |
| `500` + `{"message": "Unable to verify the AppAgent credential token"}` | Non-transient failure of the credential check; the credential was not judged. | Report the request's trace to IndyKite support; the credential itself was not judged. |
| other `5xx`            | Server-side issue.                                                                            | Retry with backoff; if persistent, file with the IndyKite team.                              |

## Step-up advice (`token_filter`)

If a policy's `token_filter` fails, the `403` response includes:

- `WWW-Authenticate: insufficient_user_authentication` header.
- A body or header field carrying the `advice.error` and `advice.error_description` you set on the failing leaf in the policy.

Clients use this to drive an OAuth step-up — re-authenticate the user with the requested factor (e.g. higher `acr`) and retry the call with a fresh token.

## Calling through MCP instead of REST

Everything above describes the direct REST call. The MCP server's `ciq_execute` tool wraps the same call and exposes it as a JSON-RPC tool — see the [`indykite-mcp-server`](../../indykite-mcp-server/SKILL.md) skill. The wire shape changes (JSON-RPC over HTTP, `Mcp-Session-Id` header, two-layer auth, `tools/call` envelope) but the underlying authorization, parameters, and response semantics are identical.

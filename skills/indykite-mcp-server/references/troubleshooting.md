# IndyKite MCP — Troubleshooting

A symptom-first map. Walk it top-down — earlier rows are cheaper to verify.

## Symptom: `401 Unauthorized` with `.well-known/oauth-protected-resource` body

| Likely cause                                          | How to verify                                                                  | Fix                                                                  |
|-------------------------------------------------------|--------------------------------------------------------------------------------|----------------------------------------------------------------------|
| No `Authorization: Bearer` header                     | Inspect the outgoing request.                                                   | Add the header with a valid OAuth access token.                       |
| Bearer token expired or not yet active                | Decode `exp` / `nbf`. Compare with the host clock.                              | Refresh the token; sync clocks.                                       |
| Token Introspect not configured for the project       | Hub UI shows no Token Introspect, or the MCP server config's `token_introspect_id` is wrong. | Create/select the right Token Introspect (`POST /token-introspects`); update the MCP server config. |
| Project's IdPs/scopes not registered in `.well-known` | The metadata returned points clients at the wrong authorization server.        | Contact IndyKite to register the project's IdPs/scopes; confirm `scopes_supported` on the MCP server config. |

## Symptom: every request returns `401` even though a Bearer token is sent

| Likely cause                                          | How to verify                                                                  | Fix                                                                  |
|-------------------------------------------------------|--------------------------------------------------------------------------------|----------------------------------------------------------------------|
| Wrong AppAgent token in `X-IK-ClientKey`              | Token decoded does not match the AppAgent.                                      | Generate a fresh AppAgent credentials token (`POST /application-agent-credentials`). |
| AppAgent lacks Authorization API + ContX IQ permissions | Hub UI on the AppAgent.                                                       | Grant both permissions.                                              |
| Bearer token's `aud` does not match the project's expectation | Decode `aud`; compare with project config.                              | Re-mint the user token with the right audience.                      |

## Symptom: server returns `403` or "no policy match" reason

| Likely cause                                          | How to verify                                                                  | Fix                                                                  |
|-------------------------------------------------------|--------------------------------------------------------------------------------|----------------------------------------------------------------------|
| `subject_id` is not the Bearer token's `sub`          | Compare what the agent passed vs. the token's `sub` claim.                      | Pass `sub` as `subject_id` when the subject is the caller.            |
| `subject_type` is not modeled in policies             | KBAC policies in the Hub.                                                       | Use a type that has matching policies (e.g. `User`, `Person`).        |
| `CAN_X` edge between subject and resource is missing  | Inspect the IKG.                                                                | Capture the missing edge.                                            |
| KBAC policy not published                             | Hub UI shows draft state.                                                       | Publish the policy.                                                   |

## Symptom: `tools/call` returns a JSON-RPC `error`

| Likely cause                                          | How to verify                                                                  | Fix                                                                  |
|-------------------------------------------------------|--------------------------------------------------------------------------------|----------------------------------------------------------------------|
| Unknown tool name                                     | Compare against `tools/list`.                                                   | Use the exact tool name from `tools/list`.                            |
| `arguments` shape wrong (missing required field)      | The error message names the field.                                              | Add the field; cross-check with `references/tools.md`.                |
| Wrong JSON-RPC envelope (`method`, `params` keys)     | Compare the request to the canonical shape.                                     | Use `method: "tools/call"` and put tool input under `params.arguments`. |
| `Mcp-Session-Id` missing                              | Inspect headers.                                                                | Re-`initialize` and resend with the new session id.                   |

## Symptom: `ciq_execute` runs but returns nothing

| Likely cause                                          | How to verify                                                                  | Fix                                                                  |
|-------------------------------------------------------|--------------------------------------------------------------------------------|----------------------------------------------------------------------|
| Wrong Knowledge Query `id`                            | Read `indykite://knowledge-queries/`; compare ids.                              | Use the GID or name from that resource.                              |
| `input_params` keys do not match the query's filter variables | Read the query's parameter description in `indykite://knowledge-queries/`. | Rename the keys; coerce types where needed.                          |
| Query expects values that no longer exist in the IKG  | Run a smaller probe query against the same data.                                | Capture the missing data, or relax the filter values.                 |

## Symptom: every call after `initialize` is rejected

| Likely cause                                          | How to verify                                                                  | Fix                                                                  |
|-------------------------------------------------------|--------------------------------------------------------------------------------|----------------------------------------------------------------------|
| `Mcp-Session-Id` not captured from `initialize` response | Look at the *response headers*, not just the body.                            | Use `curl -i` or read `response.headers["Mcp-Session-Id"]`. The helper script in `assets/init-session.sh` does this for you. |
| Session id reused across processes after restart      | Each process must initialize.                                                   | Re-initialize on startup.                                             |

## Symptom: MCP server simply refuses to accept requests for a project

| Likely cause                                          | How to verify                                                                  | Fix                                                                  |
|-------------------------------------------------------|--------------------------------------------------------------------------------|----------------------------------------------------------------------|
| No MCP server configuration exists for the project    | `GET /configs/v1/mcp-servers` filtered by project, or check the Hub.            | Create one (`POST /configs/v1/mcp-servers`); see `configuration.md`.  |
| Configuration exists but `enabled: false`             | Same place.                                                                     | Patch the configuration to `enabled: true`.                          |

## Useful one-liners

```bash
# Decode the Bearer token's payload (needs the token in $BEARER_TOKEN)
printf '%s' "$BEARER_TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | jq

# Fetch the .well-known protected-resource doc for a project
curl -s -i "$MCP_URL/mcp/v1/$PROJECT_GID" -H "X-IK-ClientKey: $API_KEY" -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"curl","version":"1.0"}}}'
# (no Bearer header forces 401 + metadata)

# List tools (after initialize)
curl -s "$MCP_URL/mcp/v1/$PROJECT_GID" \
  -H "Authorization: Bearer $BEARER_TOKEN" -H "X-IK-ClientKey: $API_KEY" \
  -H "Mcp-Session-Id: $SESSION_ID" -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' | jq
```

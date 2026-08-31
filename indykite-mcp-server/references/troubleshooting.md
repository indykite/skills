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

The MCP server checks the token's `iss`/`aud` against the project's bound Token Introspect *before* authoritative introspection, then validates it using the configured AppAgent. A mismatch on either side fails closed.

| Likely cause                                          | How to verify                                                                  | Fix                                                                  |
|-------------------------------------------------------|--------------------------------------------------------------------------------|----------------------------------------------------------------------|
| Bearer token's `iss`/`aud` does not match the project's bound Token Introspect | Decode `iss`/`aud`; compare with the project's Token Introspect config. | Re-mint the user token with the right issuer/audience, or point the config at the right Token Introspect. |
| AppAgent named by `app_agent_id` lacks Authorization API + ContX IQ permissions | Hub UI on the AppAgent referenced by the MCP server config.            | Grant both permissions.                                              |
| `app_agent_id` on the MCP server config is wrong or the AppAgent was deleted | `GET /configs/v1/mcp-servers` for the project; check `app_agent_id`.      | Point the config at a valid AppAgent.                                |

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
| `Mcp-Method` / `Mcp-Name` header missing or not matching the body | Compare the headers with `method` and `params.name`.                | Set `Mcp-Method` to the JSON-RPC method and `Mcp-Name` to the tool name (or resource URI / prompt name); they must match the body. |
| (legacy sessions only) `Mcp-Session-Id` missing       | Inspect headers.                                                                | Re-`initialize` and resend with the new session id — or switch to the stateless protocol. |

## Symptom: `ciq_execute` runs but returns nothing

| Likely cause                                          | How to verify                                                                  | Fix                                                                  |
|-------------------------------------------------------|--------------------------------------------------------------------------------|----------------------------------------------------------------------|
| Wrong Knowledge Query `id`                            | Read `indykite://knowledge-queries/`; compare ids.                              | Use the GID or name from that resource.                              |
| `input_params` keys do not match the parameters in the query's description | Read the query's parameter description in `indykite://knowledge-queries/`. | Rename the keys; coerce types where needed.                          |
| Query expects values that no longer exist in the IKG  | Run a smaller probe query against the same data.                                | Capture the missing data, or relax the filter values.                 |

## Symptom: `404` "session not found" on a request that should be stateless

| Likely cause                                          | How to verify                                                                  | Fix                                                                  |
|-------------------------------------------------------|--------------------------------------------------------------------------------|----------------------------------------------------------------------|
| `params._meta` missing, or missing the `io.modelcontextprotocol/protocolVersion` key | Inspect the request body. Without that key the server treats the request as **session-based** and runs the session gate. | Add the full `_meta` object with `"io.modelcontextprotocol/protocolVersion": "2026-07-28"`. `scripts/mcp-call.sh` builds it for you. |
| `_meta` present but protocol version below `2026-07-28` | Check the version string in `_meta`.                                          | Use `2026-07-28` (or a later revision listed by `server/discover`).   |

## Symptom: `400` with JSON-RPC error `-32022` (unsupported protocol version)

The request asked for a protocol revision the server does not support. The error's `data.requested` names what was asked for and `data.supported` lists what is available.

| Likely cause                                          | How to verify                                                                  | Fix                                                                  |
|-------------------------------------------------------|--------------------------------------------------------------------------------|----------------------------------------------------------------------|
| Typo or future/unknown revision in `_meta` / `Mcp-Protocol-Version` | Compare against `data.supported` in the error, or call `server/discover`. | Send a supported revision, normally `2026-07-28`.                     |

## Symptom (legacy sessions): every call after `initialize` is rejected

Only applies to session-based clients (protocol revisions before `2026-07-28`). Stateless requests cannot hit these — switching to the stateless protocol removes this failure class entirely.

| Likely cause                                          | How to verify                                                                  | Fix                                                                  |
|-------------------------------------------------------|--------------------------------------------------------------------------------|----------------------------------------------------------------------|
| `Mcp-Session-Id` not captured from `initialize` response | Look at the *response headers*, not just the body.                            | Use `curl -i` or read `response.headers["Mcp-Session-Id"]`.           |
| Session id reused across processes after restart      | Each process must initialize.                                                   | Re-initialize on startup.                                             |
| Stale `Mcp-Session-Id` sent alongside a `2026-07-28` `_meta` | Not an error: the `_meta` wins and the header is ignored.                 | Drop the header; the request is handled statelessly.                  |

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
curl -s -i "$MCP_URL/mcp/v1/$PROJECT_GID" -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Mcp-Protocol-Version: 2026-07-28" -H "Mcp-Method: tools/list" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}}'
# (no Bearer header forces 401 + metadata)

# What protocol revisions does this endpoint speak?
curl -s "$MCP_URL/mcp/v1/$PROJECT_GID" \
  -H "Authorization: Bearer $BEARER_TOKEN" -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Mcp-Protocol-Version: 2026-07-28" -H "Mcp-Method: server/discover" \
  -d '{"jsonrpc":"2.0","id":1,"method":"server/discover","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}}'

# List tools (stateless — no session needed)
curl -s "$MCP_URL/mcp/v1/$PROJECT_GID" \
  -H "Authorization: Bearer $BEARER_TOKEN" -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Mcp-Protocol-Version: 2026-07-28" -H "Mcp-Method: tools/list" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}}'
# (responses may be SSE: the JSON-RPC message is on the `data:` line)
```

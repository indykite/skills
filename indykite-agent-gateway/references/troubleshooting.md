# IAG Troubleshooting

A symptom-first map from observable failure to most likely cause. Walk it top-to-bottom - earlier rows are cheaper to verify than later ones.

## Symptom: every request returns `401`

| Likely cause                                          | How to verify                                                                    | Fix                                                                |
|-------------------------------------------------------|----------------------------------------------------------------------------------|--------------------------------------------------------------------|
| Caller is not sending a token                         | Response body says `Missing bearer token`; check the inbound `Authorization` header. | Add `Bearer <token>` at the caller.                                |
| Token is expired or not yet active                    | Decode `exp` / `nbf`. Compare with IAG host clock.                                | Refresh the token; sync clocks if skewed.                          |
| IdP introspect endpoint wrong or credentials refused  | Service log shows the failed call with endpoint, status, and a sanitized preview of the IdP's response body. | Correct `JARVIS_IDENTITY_PROVIDER_INTROSPECT_ENDPOINT` or the client secret and restart IAG. |
| Token has no `sub` / no `act`                         | Body says `Invalid token, missing subject` or `Invalid token, missing act claim`. | Make the IdP issue a subject. On later hops without a Token Service, `Authorization` must carry the delegated token from the previous hop, not a bare user token; with a Token Service, keep the user token in `Authorization` and forward the delegated token in `X-IK-Token`. |
| IdP unreachable from IAG                              | `docker compose logs orchestrator-iag` shows DNS / TCP errors (response is `502`, not `401`). | Fix network path; ensure `extra_hosts` if using Docker Compose.    |

## Symptom: `401 Invalid delegated token, …` (Token Service deployments)

| Likely cause                                          | How to verify                                                                     | Fix                                                                 |
|-------------------------------------------------------|-----------------------------------------------------------------------------------|---------------------------------------------------------------------|
| `X-IK-Token` paired with a different user's access token (`subject mismatch`) | Compare `sub` of the access token and of the `X-IK-Token`; audit `reason` names it. | Forward both headers exactly as received from the previous hop; never reuse an `X-IK-Token` across callers. |
| `X-IK-Token` not signed by this Token Service, or expired | Token Service audit shows `INTROSPECTED_INACTIVE` with the reason.               | Point every gateway of the workflow at the same Token Service; raise `idp.token_ttl` only as far as the workflow needs. |
| Token Service unreachable                             | Service log shows the failed `/oauth2/introspect` call (response is `502`).        | Fix `token_service.base_url` / network path.                        |

## Symptom: second hop of a workflow is always refused

| Likely cause                                          | How to verify                                                                     | Fix                                                                 |
|-------------------------------------------------------|-----------------------------------------------------------------------------------|---------------------------------------------------------------------|
| No Token Service configured - the chain restarts from the user's token on every hop | Audit `actorsChain` on the second gateway has one entry only.        | Configure `token_service` on every gateway of the workflow and deploy the Token Service. |
| First gateway forwards the IdP delegation token, second expects `X-IK-Token` | Only some instances have `JARVIS_TOKEN_SERVICE_*` set.                   | Set the section identically on all instances.                       |
| Intermediate agent drops `X-IK-Token`                 | The downstream call lacks the header.                                             | Forward both `Authorization` and `X-IK-Token` unchanged from the incoming request. |

## Symptom: exchange refused with `invalid_target`

| Likely cause                                          | How to verify                                                                     | Fix                                                                 |
|-------------------------------------------------------|-----------------------------------------------------------------------------------|---------------------------------------------------------------------|
| A requested audience is not in the Token Service's `idp.audiences` | Token Service audit `EXCHANGE_REFUSED`; compare `protected_agent.authentication.audiences` with `idp.audiences`. | Add the audience to `idp.audiences` (and `idp.resources` for `resource` parameters). |

## Symptom: every request returns `403` regardless of caller

| Likely cause                                          | How to verify                                                                     | Fix                                                                 |
|-------------------------------------------------------|-----------------------------------------------------------------------------------|---------------------------------------------------------------------|
| Subject type not allowed                              | Audit `reason` mentions subject type / no policy match.                            | Add the type to `JARVIS_AUTHZEN_SUBJECT_TYPES`.                     |
| `CAN_TRIGGER` edge missing                            | Inspect the IKG: `(:User {external_id:"…"})-[:CAN_TRIGGER]->(:Workflow)`.          | Capture the missing edge.                                           |
| ContX IQ returns nothing                              | Audit `reason` says "no workflow matches" or chain list empty.                     | Confirm `workflow_name` on every `INVOKES` matches `Workflow.external_id`. |
| Wrong `query_id`                                      | Hub UI vs. `JARVIS_CONTX_IQ_QUERY_ID`.                                              | Set the correct `query_id`.                                         |
| Policy reads a token that is not sent                 | Policy condition references `$token` but the gateway uses the Token Service (or `$ik_token` without one). | Reference `$ik_token` with a Token Service, `$token` without. |

## Symptom: `403` only when chains include a specific agent

| Likely cause                                          | How to verify                                                                     | Fix                                                                 |
|-------------------------------------------------------|-----------------------------------------------------------------------------------|---------------------------------------------------------------------|
| `Agent.external_id` does not match the IdP client / `act` chain entry | Compare the three values side-by-side.                            | Make all three identical.                                           |
| `INVOKES` relationship missing                        | Query the IKG for the relationship.                                                | Capture the missing relationship.                                   |
| Chain skips a required intermediate agent             | Audit `reason` shows the requested chain (`actorsChain`).                          | Route through the orchestrator (or whichever agent the workflow demands). |

## Symptom: `401` / `403` on MCP calls (`protocol: mcp` instance)

| Likely cause                                          | How to verify                                                                     | Fix                                                                 |
|-------------------------------------------------------|-----------------------------------------------------------------------------------|---------------------------------------------------------------------|
| App Agent token (`IK_APP_AGENT_KEY`) not introspectable | Decode it; confirm the Token Introspect config points at the right issuer.       | Use an introspectable App Agent token.                              |
| App Agent not modeled as an allowed subject           | Audit `reason` shows subject type / no policy match - MCP agents call as the App Agent, not the chatbot user. | Override `JARVIS_AUTHZEN_ACTION` / `JARVIS_AUTHZEN_SUBJECT_TYPES` on the MCP instance to match how the App Agent is modeled. |
| Image too old for MCP proxying                        | Gateway behaves as A2A proxy / ignores `JARVIS_PROTECTED_AGENT_PROTOCOL`.          | Pin `indykite/agent-gateway` ≥ `2.0.1`.                            |
| To isolate the gateway                                | Point the agent's `MCP_SERVER_URL` back at the direct MCP server URL.             | If it works direct, the failure is auth/config on the MCP instance. |

## Symptom: `400` / `413` / `415` with a JSON-RPC error body on MCP calls (`protocol: mcp` instance)

The gateway forwards only MCP protocol revisions `2025-06-18`, `2025-11-25`, and `2026-07-28`, and refuses the request itself, before authorization, when the revision rules are not met or when it cannot read unambiguously which tool or resource the request names. The audit record is `NOT_AUTHORIZED` with `reason` = `MCP request refused: <message>`; the downstream never saw the request. The message never repeats a value the client sent, so compare the request itself with the rules below.

| Likely cause                                          | How to verify                                                                     | Fix                                                                 |
|-------------------------------------------------------|-----------------------------------------------------------------------------------|---------------------------------------------------------------------|
| Client sends no `Mcp-Protocol-Version` after `initialize` | `400`, JSON-RPC `-32020`, `Header mismatch: Mcp-Protocol-Version header is missing`. Older MCP client libraries only send the header on some calls. | Send `Mcp-Protocol-Version: <negotiated revision>` on every request (next to `Mcp-Session-Id` for session-based clients). |
| Client names a revision the gateway does not forward  | `400`, JSON-RPC `-32022`, `error.data.requested` shows what was sent, `error.data.supported` the three revisions. | Use one of the supported revisions; prefer the stateless `2026-07-28` when the server speaks it. |
| Handshake succeeded, but every later call is `-32022` | The downstream server answered `initialize` with a revision the gateway does not support (the gateway checks requests only). | Upgrade or configure the MCP server to speak `2025-06-18`, `2025-11-25`, or `2026-07-28`. |
| Client sends a JSON-RPC batch                         | `400`, `-32600`, `Invalid Request: JSON-RPC batching is not supported`.           | Send one JSON-RPC message per request.                              |
| Client compresses the body                            | `415`, `-32600`, `Invalid Request: content coding gzip is not supported`.         | Send the body with `Content-Encoding: identity` (or no header).     |
| Body is not valid UTF-8, or holds two messages or trailing text | `400`, `-32700`, `Parse error: the request body is not valid UTF-8` / `… is not one JSON value`. | Send exactly one UTF-8 JSON-RPC message per request.       |
| Message lacks `"jsonrpc": "2.0"` or has neither `method` nor `result` / `error` | `400`, `-32600`, `Invalid Request: the request body is not a JSON-RPC message`. | Send a well-formed JSON-RPC 2.0 request, notification or response. |
| A repeated key, a non-ASCII key, or a key that differs from a field the gateway reads (`jsonrpc`, `method`, `params`, `name`, `uri`, `notifications`, `resourceSubscriptions`) only in case or in `_` / `-` | `400`, `-32600`, `Invalid Request: the message has a repeated key` / `… has a key that can be read as name`. | Emit each key once, in its canonical spelling; serializers that merge duplicates hide this. |
| `tools/call` without a string `params.name`, or `resources/*` without a string `params.uri` | `400`, `-32602`, `Invalid params: tools/call names no tool` / `resources/read names no resource URI`. | Put the tool name in `params.name` (the resource URI in `params.uri`) as a non-empty string. |
| Tool name, resource URI or method contains a control character, a lone surrogate or `U+FFFD` | `400`, `-32600`, `Invalid Request: the tool name contains a control character` and similar. | Use plain tool names and URIs; `U+FFFD` usually means a client re-encoded bytes it could not decode. |
| On `2026-07-28`: `Mcp-Method` or `Mcp-Name` header differs from the body | `400`, `-32020`, `Header mismatch: Mcp-Method header does not match the method in the body` / `Mcp-Name header does not match the tool name in the body` / `Mcp-Name header is not valid Base64`. | Mirror the body exactly: `Mcp-Method` = `method`, `Mcp-Name` = `params.name` (`tools/call`) or `params.uri` (`resources/read`); a `=?base64?…?=` value must decode to the body's value. Omitting the header is allowed by the gateway and left to the server. |
| Body over 4 MiB                                       | `413`, `-32600`.                                                                  | Reduce the payload; the gateway forwards at most 4 MiB per request. |
| `initialize` with an old revision (e.g. `2025-03-26`) "changes" the version | The gateway rewrote `protocolVersion` to `2025-11-25` and the server offered it. | Expected; make the client accept `2025-11-25`, or switch to `2026-07-28`. |

## Symptom: gateway fails to start

| Message                                               | Cause                                                                             | Fix                                                                 |
|-------------------------------------------------------|-----------------------------------------------------------------------------------|---------------------------------------------------------------------|
| *invalid protected_agent protocol*                    | `protected_agent.protocol` is neither `a2a` nor `mcp`.                             | Set it to `a2a` or `mcp` (or omit it - defaults to `a2a`).          |
| `cache_update_after (…) must not exceed cache_ttl (…)` or `cache_update_after_error (…) must not exceed cache_update_after (…)` | Cache durations on `authzen` / `contx_iq` are inconsistent or negative. | Keep `cache_update_after_error ≤ cache_update_after ≤ cache_ttl`, none negative (defaults `10s` / `5m` / `5m`). |
| `missing base_url` / `missing exchange_endpoint` / `missing introspect_endpoint` | A partially filled `token_service` section (or `identity_provider`). | Fill every field of the section or remove `token_service` entirely. |
| `client_auth has invalid type "…" (want "client_secret_basic")` | Unsupported `token_service.client_auth.type`.                           | Use `client_secret_basic` with `client_id` and `client_secret`.     |

## Symptom: container reports unhealthy although requests succeed

| Likely cause                                          | How to verify                                                                     | Fix                                                                 |
|-------------------------------------------------------|-----------------------------------------------------------------------------------|---------------------------------------------------------------------|
| Older image that did not serve `/healthz`             | `curl http://localhost:9080/healthz` inside the container fails.                  | Pull a current `indykite/agent-gateway` (and `indykite/token-service`) image. |
| `service.healthcheck_port` changed without changing the probe | The image `HEALTHCHECK` probes `localhost:9080/healthz`.                   | Keep the default `9080`, or override the container health check too. |

## Symptom: `502 Bad Gateway`

| Likely cause                                          | How to verify                                                                     | Fix                                                                 |
|-------------------------------------------------------|-----------------------------------------------------------------------------------|---------------------------------------------------------------------|
| Protected agent unreachable                           | Service log shows connect / dial errors to `protected_agent.base_url`.            | Fix the network path or the URL.                                    |
| IdP or Token Service unreachable or answering unreadably | Service log shows the failed call with endpoint, status, and body preview; audit `ERROR`. | Fix the endpoint / network; this is a provider fault, not a denial. |
| Protected agent returns malformed A2A response        | Log shows JSON-RPC parse error.                                                    | Fix the agent's response shape; this is an agent-side bug, not IAG. |
| Audit webhook target down (only if it is the upstream failure surfaced) | Webhook logs / target service.                              | Restart the webhook target or change `audit.http.url`.              |

## Symptom: `500` on otherwise valid requests

| Likely cause                                          | How to verify                                                                     | Fix                                                                 |
|-------------------------------------------------------|-----------------------------------------------------------------------------------|---------------------------------------------------------------------|
| Audit file path not writable                          | Service log shows `permission denied`.                                             | Fix `audit.file.storage_path` permissions or volume mount.          |
| Unexpected internal failure                           | Service log stack trace; raise `service.log_level` to `debug`.                     | Capture `traceID` and escalate.                                     |

## Symptom: audit records never reach the configured destination

| Likely cause                                          | How to verify                                                                     | Fix                                                                 |
|-------------------------------------------------------|-----------------------------------------------------------------------------------|---------------------------------------------------------------------|
| Webhook URL wrong                                     | Service log shows HTTP error from audit subsystem.                                 | Correct `audit.http.url`.                                           |
| API-key auth header mismatch                          | Webhook target rejects with `401` / `403`.                                         | Set `audit.http.auth.api_key_header` (default `X-API-Key`).         |
| Async queue full                                      | Service log says `dropping payload, async queue is full`.                          | Raise `audit.async.buffer_size` or speed up the sink.               |
| File rotation deleting before reader consumes         | `ls -la` on `storage_path` shows churning files.                                   | Loosen rotation (`rotation_interval`, `rotation_max_bytes`).        |
| CSV consumer confused by a new column                 | Files rotated after the `tokenID` column was added carry a different header.        | Re-read the header per file; older files keep the old header.       |

## Symptom: Token Service refuses to start

| Message                                               | Cause                                                                             | Fix                                                                 |
|-------------------------------------------------------|-----------------------------------------------------------------------------------|---------------------------------------------------------------------|
| `service.base_url is required`                        | No issuer URL.                                                                     | Set the public `https` base URL; it becomes the `iss` of every token. |
| Two `jwt` configurations share an issuer + audience for the same token type, or two `opaque` ones for a token type | Overlapping `token_introspection.configurations`. | Merge or narrow the matchers.                                       |
| A configuration names no `client_auth` for `online_oauth2` | The secret file was not merged into the config directory.                      | Mount the file carrying `client_auth` into `--config-dir`.          |
| Config directory holds no loadable file               | Wrong mount or unsupported extension.                                             | Provide `.yaml` / `.yml` / `.json` / `.toml` files in the directory (subdirectories are not read). |

## Useful one-liners

```bash
# Stream the JSON service log for one IAG instance
docker compose logs -f orchestrator-iag

# Show only audit-shaped lines (rough filter; audit is a separate stream when configured)
docker compose logs orchestrator-iag | grep -E '"decision":'

# Tail a CSV audit file
tail -f /var/log/iag/audit.csv

# Count denials in the last 100 audit lines
tail -n 100 /var/log/iag/audit.csv | grep -c NOT_AUTHORIZED

# Gateway and Token Service health
curl -s http://localhost:9080/healthz

# Token Service discovery document and published keys
curl -s https://token-service.example.com/.well-known/openid-configuration | jq
curl -s https://token-service.example.com/.well-known/jwks.json | jq '.keys[].kid'
```

## When to escalate

- The error reproduces only intermittently → capture `traceID` from the audit record and the protected agent's logs, then file a ticket with both.
- IAG itself crashes (no `200`/`4xx`/`5xx`, the container exits) → grab `docker compose logs <iag>` from boot to crash and share with the IAG maintainers.
- Decision is correct but `reason` is unhelpful → that is a documentation/observability issue, not a misconfiguration; report upstream.

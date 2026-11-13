# IAG Troubleshooting

A symptom-first map from observable failure to most likely cause. Walk it top-to-bottom - earlier rows are cheaper to verify than later ones. The status alone rarely says why: read the audit record, whose `reason` does (the `decision` `ERROR` tells a provider fault from a denial).

## Symptom: every request returns `401`

| Likely cause                                          | How to verify                                                                    | Fix                                                                |
|-------------------------------------------------------|----------------------------------------------------------------------------------|--------------------------------------------------------------------|
| Caller is not sending a token                         | Body is `{"message":"Missing bearer token"}`, audit reason `no bearer token`.     | Add `Bearer <token>` at the caller (or, on a later hop with a Token Service, the `X-IK-Token`). |
| Token is expired or unknown to the IdP                | Body is `{"message":"Unauthorized","errors":["identity provider: the token is not active"]}`. | Obtain a fresh token; check `identity_provider.introspect_endpoint`. |
| Workflow started at the wrong gateway (Token Service) | Body is `{"message":"Access token not issued for this agent"}`: the user token's audience is none of `protected_agent.authentication.audiences`. | Route through the entry agent, or issue the user a token for this agent's audience and model the one-agent workflow. |
| IdP introspect endpoint wrong or credentials refused  | Service log shows the failed call with endpoint, status, and a sanitized preview of the IdP's response body. | Correct the endpoint or the client secret and restart IAG.         |
| The exchange produced no delegation                   | Body is `Invalid token, missing subject` / `missing act claim` / `act claim must be an object`. | Confirm the IdP's RFC 8693 support (it must write `act`), or run the Token Service. On later hops without a Token Service, `Authorization` must carry the previous hop's delegated token, not a bare user token. |
| No Token Introspect configuration matches the token   | Body is `{"message":"Unauthorized","errors":["ContX IQ whoami failed"]}`, audit reason `cannot resolve the subject of the access token`. Check the caller with the [`indykite-ciq-whoami`](../../indykite-ciq-whoami/SKILL.md) skill. | Add or fix a Token Introspect configuration whose `jwt_matcher` matches the token's `iss` / `aud` (or an opaque-token configuration). Without a Token Service, later hops send the previous hop's delegation token, so it needs a matching configuration too. |
| A provider refused the gateway                        | `errors` names the service: `["identity provider: token exchange failed - …"]`, `["identity provider: client credentials grant failed - …"]`, `["evaluating admission through AuthZEN failed"]`; audit decision `ERROR`. | A wrong client secret, a wrong `app_agent_credentials_token` or its API permissions, or no Token Introspect configuration for the delegation tokens (next table). |
| IdP unreachable from IAG                              | Response is `500`, not `401`; `docker compose logs <iag>` shows DNS / TCP errors. | Fix the network path; ensure `extra_hosts` if using Docker Compose. |

## Symptom: `401 Invalid delegated token, …` (Token Service deployments)

| Likely cause                                          | How to verify                                                                     | Fix                                                                 |
|-------------------------------------------------------|-----------------------------------------------------------------------------------|---------------------------------------------------------------------|
| `X-IK-Token` paired with a different user's access token (`subject mismatch`) | Compare `sub` of the access token and of the `X-IK-Token`; audit reason `invalid delegated token: subject mismatch`. | Forward both headers exactly as received from the previous hop; never reuse an `X-IK-Token` across callers. If `Authorization` legitimately carries the calling agent's service token, switch `authorization_header.same_user_check` off. |
| A user's access token presented as `X-IK-Token` (`missing act claim`) | The token has no `act` object; the issuer may mint user tokens too.         | Send the delegation token the previous gateway forwarded.           |
| `X-IK-Token` not signed by this Token Service, or expired | `["token service: the token is not active"]`; Token Service audit shows `INTROSPECTED_INACTIVE` with the reason. | Point every gateway of the workflow at the same Token Service; raise `idp.token_ttl` only as far as the workflow needs. |
| Token Service unreachable                             | Service log shows the failed `/oauth2/introspect` call (response is `500`).        | Fix `token_service.base_url` / network path.                        |

## Symptom: every request returns `403`

Always `{"message":"Authorization check failed"}` for an admission refusal (a `403` with a JSON-RPC `-31403` body on an MCP call is a capability refusal - see *Symptom: empty `tools/list`, or `403` / `-31403`* below). The audit `reason` splits two cases.

| Likely cause                                          | How to verify                                                                     | Fix                                                                 |
|-------------------------------------------------------|-----------------------------------------------------------------------------------|---------------------------------------------------------------------|
| Admission policy missing or not ACTIVE for this subject type and agent type | Reason `subject <type>/<id> may not reach <agent type>/<agent> through the delegation chain`; `<type>` is the Token Introspect configuration's `ikg_node_type`, `<agent type>` the token's `act.type` / `protected_agent.node_type` / `Agent`. List the project's active policies with [`indykite-authzen-list-policies`](../../indykite-authzen-list-policies/SKILL.md). | Create the admission policy for that subject type and resource type (`indykite-authzen-kbac-policies`), or change the configuration's `ikg_node_type`. |
| The chain is the `INVOKES` path of no workflow        | Same reason; compare `actorsChain` in the record with the workflow's path in the graph: an `Agent.external_id` differs from the token `sub`, a `workflow_name` is missing, a hop is missing because the IdP does not nest `act`, or the shape is not ingested. | Make the `external_id` values equal to the agents' client-credentials `sub`, put `workflow_name` on every `INVOKES`, ingest the one-workflow-per-shape, or run the Token Service. |
| Subject holds no `CAN_TRIGGER` on the matched workflow, or is missing / not an identity node | Same reason; inspect the IKG for `(:<whoami type> {external_id:"<whoami id>"})-[:CAN_TRIGGER]->(:Workflow)` and `is_identity`. | Capture the missing edge or node.                                   |
| Delegation token reused on another chain              | Same reason; `actorsChain` shows agents of a different workflow.                   | Mint a token per chain; do not forward one obtained for another workflow. |
| The chain cannot be read                              | Reason `the delegation chain cannot be read`: a hop has no usable `sub`, or a `type` that is not a non-empty string. | Inspect the delegation token the exchange returns; check the issuer's `act` nesting. |
| To replay the decision                                | Run the admission evaluation by hand with [`indykite-authzen-evaluation`](../../indykite-authzen-evaluation/SKILL.md): same subject, agent, the user's token in `Authorization`, the delegation token in `X-IK-Token`. | The same `false` by hand confirms the graph or the policy, not the gateway, is the cause. |

## Symptom: audit decision `ERROR` on every request

| Likely cause                                          | How to verify                                                                     | Fix                                                                 |
|-------------------------------------------------------|-----------------------------------------------------------------------------------|---------------------------------------------------------------------|
| `protected_agent.node_type` differs from the token's `act.type` | Reason `the delegated token names the protected agent <type>, protected_agent.node_type is <type>`. | Remove `protected_agent.node_type`, or make it equal to the issuer's actor type (`idp.actor_type` of the Token Service). |
| IdP refused the client credentials grant              | Reason `cannot authenticate protected agent`.                                      | Check `protected_agent.authentication` and the client at the IdP.   |
| AuthZEN could not evaluate the admission              | Reason `unable to evaluate the admission of subject <type>/<id>`; caller gets `401` / `403` with `["evaluating admission through AuthZEN failed"]` or `500`. The error is cached for `authzen.cache_update_after_error`. | Check `app_agent_credentials_token`, its `Authorization` API permission, the region base URL, and the Token Introspect configuration for the delegation tokens (issuer + audience), in both modes. |
| An admission policy reads an `input_params` value this gateway does not send | Reason `unable to evaluate the admission of subject <type>/<id>`: AuthZEN refuses the evaluation with `422` (a required input parameter is missing), which the gateway reports as an error, not a denial. The policy's Cypher names a `$param` absent from `authzen.input_params`. | Send the value in `authzen.input_params`, or tag the policy and use `authzen.policy_tags` so it does not apply to this gateway. |
| whoami failed with something other than `401`         | Reason `cannot resolve the subject of the access token` with decision `ERROR`.     | Check `contx_iq.base_url` and the `ContXIQ` API permission of the credential. |

## Symptom: second hop of a workflow is always refused

| Likely cause                                          | How to verify                                                                     | Fix                                                                 |
|-------------------------------------------------------|-----------------------------------------------------------------------------------|---------------------------------------------------------------------|
| No Token Service and the IdP does not nest `act` - the chain restarts from the user's token on every hop | Audit `actorsChain` on the second gateway has one entry only. | Configure `token_service` on every gateway of the workflow and deploy the Token Service. |
| Mixed modes: first gateway forwards the IdP delegation token, second expects `X-IK-Token` | Only some instances have `JARVIS_TOKEN_SERVICE_*` set.                   | Set the section identically on all instances.                       |
| Intermediate agent drops `X-IK-Token`                 | The downstream call lacks the header; the second gateway answers `Missing bearer token` or treats the call as a workflow start. | Forward `X-IK-Token` (and `Authorization`, if the user's token) unchanged from the incoming request. |
| Gateways ask for different audiences                  | Token Service audit `EXCHANGE_REFUSED` with `invalid_target`, or the platform cannot read the token on the second gateway. | Set the same `token_service.audience` on every gateway of the path and list it in `idp.audiences`; one Token Introspect configuration per issuer. |

## Symptom: exchange refused with `invalid_target`

| Likely cause                                          | How to verify                                                                     | Fix                                                                 |
|-------------------------------------------------------|-----------------------------------------------------------------------------------|---------------------------------------------------------------------|
| A requested audience is not in the Token Service's `idp.audiences` | Token Service audit `EXCHANGE_REFUSED`; compare `token_service.audience` / `protected_agent.authentication.audiences` with `idp.audiences`. | Add the audience to `idp.audiences` (and `idp.resources` for `resource` parameters). |

## Symptom: `401` / `403` / `404` on MCP calls (`protocol: mcp` instance)

| Likely cause                                          | How to verify                                                                     | Fix                                                                 |
|-------------------------------------------------------|-----------------------------------------------------------------------------------|---------------------------------------------------------------------|
| Client calls a path other than the endpoint path      | `404` `{"message":"Not Found"}` before any token is read.                          | Call the path of `service.base_url` exactly (trailing slash included); the gateway forwards no other path. |
| Ingress strips the path prefix                        | Every call is `404` although the client uses the public URL.                       | Keep the prefix; route `/.well-known/oauth-protected-resource<path>` to the gateway too. |
| MCP client cannot discover where to get a token       | The `401` lacks a usable `WWW-Authenticate: Bearer resource_metadata="…"`, or the metadata path is not routed. | Set `identity_provider.issuer`; route the metadata path; the client asks for its token with `resource` = the metadata's `resource`. |
| MCP client's token not matched by a Token Introspect configuration | `401` with `ContX IQ whoami failed`; check with the [`indykite-ciq-whoami`](../../indykite-ciq-whoami/SKILL.md) skill. | Add a configuration that validates it (issuer / audience for a JWT, or an opaque-token configuration). |
| MCP caller not admitted                               | Audit reason `subject <type>/<id> may not reach <agent type>/<agent> …` - MCP clients call with their own token, so the subject is that token's `sub`. | Make an admission policy name that configuration's `ikg_node_type`, and model the one-agent workflow `[mcp-agent]` (or the chain that ends at it). |
| Image too old for MCP proxying                        | Gateway behaves as A2A proxy, ignores `JARVIS_PROTECTED_AGENT_PROTOCOL`, or forwards every path. | Pin a current `indykite/agent-gateway` tag; `latest` lags.          |
| To isolate the gateway                                | Point the client at the MCP server's endpoint URL directly.                        | If it works direct, the failure is auth / config on the MCP instance. |

## Symptom: empty `tools/list`, or `403` / `-31403` on `tools/call` (`protocol: mcp` instance)

Capability checks (on by default) decide what the caller may use. Read the `DISCOVERY` / `INVOCATION` record: `permittedSet` holds what the platform returned, `discovery.listed` / `kept` how many entries the server advertised and the caller got. An empty set looks the same whether the caller is admitted nowhere, admitted with nothing permitted, or nothing is modelled.

| Likely cause                                          | How to verify                                                                     | Fix                                                                 |
|-------------------------------------------------------|-----------------------------------------------------------------------------------|---------------------------------------------------------------------|
| Gateway upgraded, nothing modelled                    | Every list empty for every user, reason `the caller may use nothing of the kind listed, answered with an empty list`, `discovery.serverCalled: false`. | Add the capability nodes and `HAS {workflow_name}` edges and one `CAN_USE` policy per label, or set `authzen.capabilities.enabled: false`. |
| No `CAN_USE` policy for the label, or an INACTIVE one | List the policies with [`indykite-authzen-list-policies`](../../indykite-authzen-list-policies/SKILL.md); the label is `authzen.capabilities.labels.*` (`Tool`, `McpResource`, `Prompt`, `Skill`). | Create the policy for that subject type and label, action `authzen.capabilities.action`. |
| Capability `external_id` differs from the protocol identifier | Compare `capabilities` of a denied `INVOCATION` with the node: a tool node must carry the tool **name**, a resource node the exact URI, a prompt node the prompt name. | Fix the `external_id`. |
| `HAS` edge without the workflow's `workflow_name`, or the caller's chain is another workflow | Replay the search with [`indykite-authzen-search-resource`](../../indykite-authzen-search-resource/SKILL.md): subject from whoami, action `CAN_USE`, resource type the label, the delegation token in `X-IK-Token`. | Put `workflow_name` = the `Workflow.external_id` on the `HAS` edge. |
| Caller not admitted at all                            | The search above is empty although the capability is modelled; the admission evaluation by hand is `false` too. | Fix the admission side (previous sections) - the capability policy repeats its condition. |
| Tool shows in a workflow it was not attached to       | The capability policy lacks `h.workflow_name = wf.external_id`.                    | Add the condition.                                                  |
| A2A extended card lists no skill                      | `DISCOVERY` record of kind `skill` with `kept: 0`.                                 | Model `Skill` nodes with `HAS` edges and a `CAN_USE` policy for `Skill`, or switch the checks off. |
| A2A extended card lists fewer skills once `ibac.enabled` is on | `IBAC_DISCOVERY` records for the card: a skill was dropped for `missing_coaz_mapping` (no mapping, with `ibac.capabilities.unmapped: deny`), for `invalid_coaz_mapping` (a mapping that cannot be read), because the card lists its id twice, or because its mappings fit no evaluation of the caller's intent. | It depends on the cause. No mapping: add `x-coaz-mappings` to the skill, or set `unmapped: allow` if permitted skills without a mapping should stay on the card. Unreadable mapping or duplicate id: fix the mapping or the card - these skills are dropped with either `unmapped` setting. No fit: compare the skill's mappings with the subject type, resource type and action of the newest intent in the token; `unmapped` does not affect a skill that has a mapping. |
| `403` / `500` with nothing forwarded, reason `the permitted set cannot be read: …` | The search failed (decision `ERROR`, the platform's status or `500`); cached for `authzen.cache_update_after_error`. | As for an admission `ERROR`: credential permissions, base URL, Token Introspect configuration for the delegation tokens, a policy reading an `input_params` value this gateway does not send. |

## Symptom: refusals that appear after switching `ibac.enabled` on

| Likely cause                                          | How to verify                                                                     | Fix                                                                 |
|-------------------------------------------------------|-----------------------------------------------------------------------------------|---------------------------------------------------------------------|
| `mcp`: `403` / `-31403` `Forbidden: the named tool has an invalid mapping` | The `IBAC_USAGE` record carries `reasonCode` `invalid_coaz_mapping`; the tool's `_meta.x-coaz-mappings` in the server's `tools/list` is not a valid list of mappings. | Fix the mapping (for an IndyKite MCP Knowledge Query tool, the JSON list after `x-coaz-mappings:` in the query's `description`). The rules are in the [IBAC engine guide](https://developer.indykite.com/guides/guide-ibac). |
| `mcp`: `403` / `-31403` `Forbidden: the named tool has no mapping` | `ibac.capabilities.unmapped: deny`, and the capability has no mapping or the server does not list it (`reasonCode` `missing_coaz_mapping`). | Declare a mapping on the capability, or set `unmapped: allow` so the permitted set alone decides. |
| `mcp`: `403` / `-31403` `Forbidden: the named tool does not match the intent` | No evaluation of the current intent matches a mapping of the tool, or the call lacks an argument a mapping reads; the `IBAC_USAGE` record has `reasonCode` `intent_mismatch` and `currentIntent` shows the intent it was checked against. | Compare `currentIntent` with the tool's `x-coaz-mappings` (subject type, resource type, action) and check that the call carries every argument a `$request` expression reads. |
| `mcp`: `403` / `-31403` `Forbidden: the caller may not access the data the named tool uses` | The intent matched, but the platform denied a resolved evaluation; the `RESOLVED_EVALUATIONS` record lists each one with `allowed`. | Check your KBAC policy for that subject type, action and resource, and its tags when `authzen.policy_tags` is set. |
| `mcp`: `502` `cannot list the capabilities of the MCP server` | The call named a capability the catalog has not seen, and the gateway's own list of the server failed; `IBAC_USAGE` record `the capabilities of the server cannot be listed: …` as `ERROR`. | Check that the server answers `tools/list` (or `resources/list`, `prompts/list`) with the request's tokens; the server never got the call. |
| `mcp`: the check never runs | `IBAC_USAGE` records say `IBAC did not run: the delegated token carries no intent`. | Expected without an intent: only an earlier `a2a` gateway with `ibac.enabled` and a Token Service writes `act.intent`. |
| `a2a`: `502` `cannot delegate the token with the intent` | The second exchange returned a token without all the intent's evaluations. | Use an issuer that knows the `intent` parameter, such as the IndyKite Token Service. |
| `a2a`: `403` on messages that used to pass, once `ibac.enabled` and a Token Service are on | The intent fits no skill of the agent the caller may use; the `IBAC_DISCOVERY` record lists every evaluation and the skills it matched, and the `INTENT` record says how many fit. | Model the agent's skills and their `CAN_USE` policy (capability checks on), give each skill `x-coaz-mappings`, or switch capability checks off for that gateway. |
| `a2a`: the agent's `X-IK-Token` carries fewer evaluations than the prompt asked for | Only the evaluations a skill covers go into the token. | Expected; add a mapping to the skill that should cover the missing evaluation. |
| `a2a`: `502` on a message, with an agent card error in the log | The gateway could not read the agent card, or its skills with their mappings, to compare the intent. | Fix the card the agent serves (valid JSON, readable `x-coaz-mappings`). |
| `mcp`: `tools/list` (or `resources/list`, `prompts/list`) comes back shorter or empty with an intent | The list is filtered by the current intent: an entry with a mapping stays only when one of its mappings fits an evaluation of the intent, and an entry without one is removed only with `ibac.capabilities.unmapped: deny`. The list's `DISCOVERY` record says the intent filtered it; `IBAC_DISCOVERY` records show what matched. | Expected; to keep an entry, give it a mapping that covers the intent, or (for unmapped entries) keep `ibac.capabilities.unmapped: allow`. |
| `a2a`: the caller gets `intent_too_large` / `The request asks for too much at once: …` | The intent has more evaluations than the Token Service's `idp.max_intent_evaluations` (`10` by default), or more than 64. | Raise `idp.max_intent_evaluations` to cover your users' prompts, or have the caller split the request. |
| `a2a`: `403` `Authorization check failed` right after an intent was found | The Token Service found the delegation token too large (with the intent added). | Raise the Token Service's `idp.max_token_bytes` (default 8000), or shorten the chain or the intent; the next hop sends the token in a header. |

## Symptom: a browser client is blocked by CORS

| Likely cause                                          | How to verify                                                                     | Fix                                                                 |
|-------------------------------------------------------|-----------------------------------------------------------------------------------|---------------------------------------------------------------------|
| Origin not listed                                     | The answer has no `Access-Control-Allow-Origin`; the gateway processed the request normally (it never answers `403` for CORS). | Add the exact origin (`scheme://host[:port]`, no path, no trailing `/`) to `cors.allowed_origins`. |
| Client sends cookies (`credentials: "include"`)       | The browser refuses: the gateway never sends `Access-Control-Allow-Credentials`.  | Send the token in `Authorization`, not a cookie.                    |
| MCP server rejects the forwarded `Origin`             | The gateway answers CORS, but the server answers `403`.                            | Let the server accept the listed origins too.                       |
| Client cannot read `WWW-Authenticate` or `Mcp-Session-Id` | Origin not allowed, so no `Access-Control-Expose-Headers`.                      | List the origin.                                                    |

## Symptom: `400` / `413` / `415` with a JSON-RPC error body on MCP calls (`protocol: mcp` instance)

The gateway forwards only MCP protocol revisions `2025-06-18`, `2025-11-25`, and `2026-07-28`, and refuses the request itself, before authorization, when the revision rules are not met or when it cannot read unambiguously which tool or resource the request names. The audit record is `NOT_AUTHORIZED` with `reason` = `MCP request refused: <message>`; the downstream never saw the request. Classification refusal messages never repeat a value the client sent; revision-check messages can include request values, such as the content coding. Compare the request itself with the rules below.

| Likely cause                                          | How to verify                                                                     | Fix                                                                 |
|-------------------------------------------------------|-----------------------------------------------------------------------------------|---------------------------------------------------------------------|
| Client sends no `Mcp-Protocol-Version` after `initialize` | `400`, JSON-RPC `-32020`, `Header mismatch: Mcp-Protocol-Version header is missing`. Older MCP client libraries only send the header on some calls. | Send `Mcp-Protocol-Version: <negotiated revision>` on every request (next to `Mcp-Session-Id` for session-based clients). |
| Client names a revision the gateway does not forward  | `400`, JSON-RPC `-32022`, `error.data.requested` shows what was sent, `error.data.supported` the three revisions. | Use one of the supported revisions; prefer the stateless `2026-07-28` when the server speaks it. |
| `initialize` answered with `-32603` `Internal error: the MCP server supports none of the protocol revisions the gateway forwards` | The downstream server offered a revision the gateway does not forward; `error.data.offered` names it (when safe to repeat), `error.data.supported` the three. `… cannot read the protocol revision the MCP server offered` means its answer was unreadable. | Upgrade or configure the MCP server to speak `2025-06-18`, `2025-11-25`, or `2026-07-28`. |
| Client sends a JSON-RPC batch                         | `400`, `-32600`, `Invalid Request: JSON-RPC batching is not supported`.           | Send one JSON-RPC message per request.                              |
| Client compresses the body                            | `415`, `-32600`, `Invalid Request: content coding gzip is not supported`.         | Send the body with `Content-Encoding: identity` (or no header).     |
| Body is not valid UTF-8, or holds two messages or trailing text | `400`, `-32700`, `Parse error: the request body is not valid UTF-8` / `… is not one JSON value`. | Send exactly one UTF-8 JSON-RPC message per request.       |
| Message lacks `"jsonrpc": "2.0"` or has neither `method` nor `result` / `error` | `400`, `-32600`, `Invalid Request: the request body is not a JSON-RPC message`. | Send a well-formed JSON-RPC 2.0 request, notification or response. |
| A repeated key, a non-ASCII key, or a key that differs from a field the gateway reads (`jsonrpc`, `method`, `params`, `name`, `uri`, `notifications`, `resourceSubscriptions`) only in case or in `_` / `-` | `400`, `-32600`, `Invalid Request: the message has a repeated key` / `… has a key that can be read as name`. | Emit each key once, in its canonical spelling; serializers that merge duplicates hide this. |
| `tools/call` or `prompts/get` without a string `params.name`, or `resources/read` / `resources/subscribe` without a string `params.uri` | `400`, `-32602`, `Invalid params: tools/call names no tool` / `prompts/get names no prompt` / `resources/read names no resource URI`. | Put the tool or prompt name in `params.name` (the resource URI in `params.uri`) as a non-empty string. |
| Tool name, resource URI or method contains a control character, a lone surrogate or `U+FFFD` | `400`, `-32600`, `Invalid Request: the tool name contains a control character` and similar. | Use plain tool names and URIs; `U+FFFD` usually means a client re-encoded bytes it could not decode. |
| On `2026-07-28`: `Mcp-Method` or `Mcp-Name` header differs from the body | `400`, `-32020`, `Header mismatch: Mcp-Method header does not match the method in the body` / `Mcp-Name header does not match the tool name in the body` / `Mcp-Name header is not valid Base64`. | Mirror the body exactly: `Mcp-Method` = `method`, `Mcp-Name` = `params.name` (`tools/call`, `prompts/get`) or `params.uri` (`resources/read`); a `=?base64?…?=` value must decode to the body's value. Omitting the header is allowed by the gateway and left to the server. |
| Body over 4 MiB                                       | `413`, `-32600`, `Invalid Request: request body exceeds 4194304 bytes`.           | Reduce the payload; the gateway forwards at most 4 MiB per request. |
| `initialize` with an old revision (e.g. `2025-03-26`) "changes" the version | The gateway rewrote `protocolVersion` to `2025-11-25` and the server offered it. | Expected; make the client accept `2025-11-25`, or switch to `2026-07-28`. |

## Symptom: gateway fails to start

The full message table is in [`configuration.md`](configuration.md#startup-errors). The ones that follow an upgrade:

| Message                                               | Cause                                                                             | Fix                                                                 |
|-------------------------------------------------------|-----------------------------------------------------------------------------------|---------------------------------------------------------------------|
| `contx_iq.allowed_workflow_id is no longer supported: …` | A configuration from before the admission policy still pins one workflow.       | Remove the key; pin with `authzen.input_params` + `authzen.policy_tags` and a tagged policy. |
| `cannot get service base_url, the public URL of the gateway` / `cannot get identity_provider openid_configuration_url` | `a2a` mode without the settings the served agent card needs. | Set `service.base_url` and `identity_provider.openid_configuration_url`. |
| `protected_agent base_url must be the full URL of the MCP endpoint of the server, …` / `cannot get identity_provider issuer` / `service base_url must be the full public URL of the MCP endpoint at the gateway, …` | `mcp` mode with the old origin-only `base_url`, a percent-encoded `gid%3A`, or no `issuer`. | Set the three endpoint settings (full URLs, unencoded) - see *Protecting an MCP server* in `configuration.md`. |
| `missing authentication.audiences in protected_agent configuration` | `token_service` present without the entry audiences.                     | List the audiences of the user tokens that may start a workflow at this gateway. |
| `intent_agent.base_url is required when ibac.enabled is on in front of an A2A agent` | `ibac.enabled` without the Intent Agent address.                | Set `intent_agent.base_url`, or switch `ibac.enabled` off.          |
| `ibac.capabilities.cache_ttl must be positive, got …` / `ibac.capabilities.unmapped must be allow or deny, got "…"` | An invalid value in the `ibac.capabilities` section. | Use a positive duration, and `allow` or `deny`. |
| Gateway stops right after a capability setting changed | `authzen.capabilities.action` or an `authzen.capabilities.labels.*` value set to an empty value. | Remove the key (defaults `CAN_USE`, `Tool` / `McpResource` / `Prompt` / `Skill`) or give it a value. |
| `cors.allowed_origins: invalid origin "…", …` / `cors.allowed_origins: "*" must be the only entry` | An entry with a path or trailing `/`, `null`, or `*` beside other entries. | List bare origins, or `*` alone.                                    |
| `invalid authorization_header.forward "…", must be one of none, correct_audience, all` | A misspelt `forward` value.                                           | Use `none`, `correct_audience` or `all`.                            |
| `invalid protected_agent protocol`                    | `protected_agent.protocol` is neither `a2a` nor `mcp`.                             | Set it to `a2a` or `mcp` (or omit it - defaults to `a2a`).          |
| `<section>.cache_update_after (…) must not exceed <section>.cache_ttl (…)` or `… cache_update_after_error (…) must not exceed … cache_update_after (…)` | Cache durations on `authzen` / `contx_iq` / `a2a` are inconsistent or negative. | Keep `cache_update_after_error ≤ cache_update_after ≤ cache_ttl`, none negative. |
| `invalid token_service configuration: missing <key>`, `client_auth has invalid type "…" (want "client_secret_basic")` | A partially filled `token_service` section.          | Fill every required field or remove `token_service` entirely.       |
| `authzen.input_params: the key "…" is reserved, the platform fills it` and the other `input_params` / `policy_tags` messages | A key or value the platform would refuse. | Rename the key (2-20 lowercase letters, digits, `_`), shorten the value, list each tag once. |

## Symptom: container reports unhealthy although requests succeed

| Likely cause                                          | How to verify                                                                     | Fix                                                                 |
|-------------------------------------------------------|-----------------------------------------------------------------------------------|---------------------------------------------------------------------|
| Older image that did not serve `/healthz`             | `curl http://localhost:9080/healthz` inside the container fails.                  | Pull a current `indykite/agent-gateway` (and `indykite/token-service`) image. |
| `service.healthcheck_port` changed without changing the probe | The image `HEALTHCHECK` probes `localhost:9080/healthz`.                   | Keep the default `9080`, or override the container health check too. |

## Symptom: `500`, `502` or `504`

| Likely cause                                          | How to verify                                                                     | Fix                                                                 |
|-------------------------------------------------------|-----------------------------------------------------------------------------------|---------------------------------------------------------------------|
| IdP, Token Service, ContX IQ, AuthZEN or an A2A agent unreachable or timed out (10 s) | `500` `{"message":"Internal Server Error"}`; service log shows connect / dial errors; audit `ERROR`. | Fix the endpoint / network path; this is a provider fault, not a denial. |
| MCP server unreachable                                | `502` `{"message":"Bad Gateway","errors":[…]}` with the transport error.           | Fix `protected_agent.base_url` or the network path.                 |
| A2A agent card cannot be used, or the agent redirected off the configured host | `502`; service log names the card or the redirect.                     | Fix the card's interface URLs (a null interface or one without a URL fails), keep redirects on the host of `base_url`. |
| Protected agent returns malformed A2A response        | `502`; log shows a JSON-RPC parse error.                                           | Fix the agent's response shape; this is an agent-side bug, not IAG. |
| IdP or Token Service answered with a malformed body   | `502`; log shows the endpoint, status and a sanitized preview of the body.          | Fix the provider's endpoint configuration.                          |
| Intent Agent cannot be asked, or answered unreadably  | `502` with `["the intent agent cannot be asked"]`, `["… answered with a message instead of a task"]`, `["… an intent that cannot be read"]`, `["… a task neither completed nor failed"]`; `INTENT` record `ERROR`. | Check `intent_agent.base_url`, the Intent Agent's logs, and the `EXPECTED_TOKEN_AUDIENCE` / `intent_agent.audience` pair. |
| `INTENT` record says `no intent: the model answered with text` | The model replied with text instead of an intent; the record leaves the text out because it can quote the prompt. | Turn on `audit.include_prompt` to record it while you diagnose, and read it as data. |
| Intent Agent too slow                                 | `504` `["the intent agent did not answer in time"]`.                               | Raise `intent_agent.timeout`, or speed up the Intent Agent.         |
| Audit file path not writable                          | `500`; service log shows `permission denied`.                                      | Make `audit.file.storage_path` writable by user `65532`.            |

## Symptom: audit records never reach the configured destination

| Likely cause                                          | How to verify                                                                     | Fix                                                                 |
|-------------------------------------------------------|-----------------------------------------------------------------------------------|---------------------------------------------------------------------|
| `audit` section only in environment variables         | No records at all although `JARVIS_AUDIT_*` is set.                                | Mount a file with at least `audit.delivery` and pass `--config`; variables only override its values. |
| Webhook URL wrong                                     | Service log shows HTTP error from audit subsystem.                                 | Correct `audit.http.url`.                                           |
| API-key / mTLS values not read                        | Webhook target rejects with `401` / `403`; the queue is `512` whatever you set.    | Write the compact keys the current releases read: `apikey`, `apikeyheader`, `mtlscertificatepath`, `mtlsprivatekeypath`, `buffersize`. |
| Async queue full                                      | Service log says `dropping payload, async queue is full`.                          | Raise `audit.async.buffer_size` (`buffersize`) or speed up the sink. |
| File rotation deleting before reader consumes         | `ls -la` on `storage_path` shows churning files.                                   | Loosen rotation (`rotation_interval`, `rotation_max_bytes`).        |
| Records split by `action` look new                    | Records written since capability checks carry `action` `ADMISSION` / `DISCOVERY` / `INVOCATION` where older ones said `noop`, plus `cached`, `capabilities`, `permittedSet`, `discovery`. | Filter on `action`; `noop` now means refused before any question was asked. |
| CSV consumer confused by new columns                  | Files rotated after `tokenID`, `prompt`, `capabilityName`, `skillID`, `reasonCode`, `skillIDs`, `evaluations`, `durationMs` were added carry a different header. | Re-read the header per file; older files keep the old header.       |

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

# Tail a JSON audit file and show decision + reason
tail -q -f /var/log/iag/audit-retriever-iag-*.json | jq -c '{decision, reason, actorsChain}'

# Count denials in the last 100 audit lines of a CSV file
tail -n 100 /var/log/iag/audit.csv | grep -c NOT_AUTHORIZED

# Gateway and Token Service health
curl -s http://localhost:9080/healthz

# Agent card served by an a2a gateway (public form)
curl -s https://retriever-iag.example.com/.well-known/agent-card.json | jq

# Protected resource metadata served by an mcp gateway
curl -s "https://agents.example.com/.well-known/oauth-protected-resource/mcp/v1/gid:AAAA" | jq

# Token Service discovery document and published keys
curl -s https://token-service.example.com/.well-known/openid-configuration | jq
curl -s https://token-service.example.com/.well-known/jwks.json | jq '.keys[].kid'
```

## When to escalate

- The error reproduces only intermittently → capture `traceID` from the audit record and the protected agent's logs, then file a ticket with both.
- IAG itself crashes (no `200`/`4xx`/`5xx`, the container exits) → grab `docker compose logs <iag>` from boot to crash and share with the IAG maintainers.
- Decision is correct but `reason` is unhelpful → that is a documentation/observability issue, not a misconfiguration; report upstream.

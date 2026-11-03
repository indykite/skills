# IAG Architecture Reference

This file is loaded by agents that need to reason about how IAG processes a single request, so they can answer questions like "why was this `403`?" or "where in the path does the failure happen?".

## Topology (iag-mcp-demo)

```text
leslie (user)
   │  login via chatbot
   ▼
chatbot:3000
   │  A2A JSON-RPC
   ▼
orchestrator-iag:8881  ── introspect / client credentials ──▶  IdP ($IDP_BASE_URL)
   │                    ── exchange / introspect           ──▶  Token Service (optional, self-hosted)
   │                    ── whoami                          ──▶  ContX IQ
   │                    ── admission (CAN_TRIGGER)         ──▶  AuthZEN (KBAC admission policy over the IKG)
   │                    ── audit webhook                   ──▶  chatbot:3000/api/push-update
   ▼
orchestrator:6001
   │  delegates
   ▼
retriever-iag:8882  ──▶  retriever:6002         (canbank questions)
weather-iag:8884    ──▶  weather:6004           (weather questions)
```

Three protected agents, three IAG instances, one shared IdP, one shared IndyKite project, and - when multi-hop chains are needed - one shared Token Service. The iag-mcp-demo also runs a fourth instance, `mcp-iag`, in MCP proxy mode (`protocol: mcp`) in front of the IndyKite MCP server; the `retriever` and `weather` agents are MCP clients routed through it, so MCP traffic gets the same introspection, admission check, and audit as the A2A flows.

Neither the gateway nor the Token Service is part of the IndyKite platform: both are deployed and operated in the customer's environment and talk to the platform's ContX IQ and AuthZEN endpoints over the public API with an AppAgent credential (`X-IK-ClientKey`, `Authorization` + `ContXIQ` API permissions).

## The decision sequence

For each incoming request, an IAG instance runs the same steps, in this order:

| #  | Step                 | What happens                                                                                                             | Service answering                          |
|----|----------------------|--------------------------------------------------------------------------------------------------------------------------|--------------------------------------------|
| 1  | Caller               | A request without `X-IK-Token` starts a workflow: the gateway reads the bearer token and introspects it (a request without one is `401 Missing bearer token`; an inactive one `401`). With `token_service`, the token must have been issued for one of `protected_agent.authentication.audiences` (from the introspection answer, or the token itself) - else `401 Access token not issued for this agent`. A request with `X-IK-Token` is a later hop: that token is introspected at the `token_service` issuer, must carry `act` and `sub`, and needs no `Authorization`; a bearer token beside it must have the same `sub` when `authorization_header.same_user_check` is on. Without `token_service`, `X-IK-Token` is ignored and every hop arrives with the previous hop's delegation token as its bearer token. | IdP (`introspect_endpoint`); Token Service (`/oauth2/introspect`) |
| 2  | Actor token          | The gateway obtains the protected agent's own token with the client credentials grant and keeps it until `identity_provider.client_credential_renew_before` (10 s) before `expires_in`; a token the issuer refuses is replaced once. | IdP (`client_credential_endpoint`)         |
| 3  | Delegation token     | Subject token (the caller's, or the incoming `X-IK-Token`) + actor token are exchanged for one delegation token (RFC 8693); on a later hop the issuer nests the incoming chain. The result must carry `sub` and an `act` object. A JWT is read directly; a token that is not a JWT is introspected at its issuer. | IdP (`exchange_endpoint`) or Token Service (`/oauth2/token`) |
| 4  | Subject              | `GET /contx-iq/v1/whoami` with the request's bearer token: `type` = the `ikg_node_type` of the Token Introspect configuration that validates it, `id` = the token's subject claim. A later hop without a bearer token sends the delegation token it just minted instead, so every subject of such a hop gets the type of the configuration for the delegation tokens. A token whoami rejects ends the request with `401`. | ContX IQ                                   |
| 5  | Admission            | One `POST /access/v1/evaluation`: subject from whoami, action `authzen.action`, resource `id` = the newest hop of the chain (this gateway's agent), resource `type` = that hop's `act.type`, else `protected_agent.node_type`, else `Agent`; `authzen.input_params` / `policy_tags` as `context`. The call carries the user's bearer token in `Authorization` (when the request had one) and the delegation token in `X-IK-Token`, **in both modes**, so the policy reads `$ik_token.act_chain`. `decision: false` is `403`. A chain that cannot be read is refused without a call; an `act.type` that differs from a set `protected_agent.node_type` is an `ERROR`. | AuthZEN / KBAC                             |
| 6  | Intent               | `a2a` with `ibac.enabled`: the text parts of a `message/send` / `message/stream` are sent to the Intent Agent with the whoami subject; a failed task is answered in place of the agent (`200`, `metadata.intent_error`), an unreachable or unreadable Intent Agent is `502`, a slow one `504`. | Intent Agent                               |
| 7  | Forward              | Without `token_service` the delegation token replaces the caller's token in `Authorization`; with it, `Authorization` stays as it arrived and the delegation token goes in `X-IK-Token`. | Protected agent / MCP server               |
| 8  | Audit                | One record per request, written before forwarding, on every outcome; plus one `INTENT` record per Intent Agent call.     | IAG itself                                 |

The gateway compares the chain with nothing itself; the admission policy does, against the graph. Facts that follow and matter when something is refused:

- **The subject is always the user.** On later hops the token's `sub` is still the user's; an agent is the subject only when it starts a workflow with its own token. The graph must hold a node of the subject type whose `external_id` equals the `id` whoami returns (the token's `sub`, or the claim named by the Token Introspect configuration's `sub_claim`) - an identity node for a `2.0-kbac` policy - or every call is `403`.
- **Every token in `Authorization` needs a Token Introspect configuration** whose `jwt_matcher` matches its `iss` and `aud`; otherwise whoami refuses it and the gateway answers `401` `{"message":"Unauthorized","errors":["ContX IQ whoami failed"]}`, audit reason `cannot resolve the subject of the access token`. Without a Token Service a later hop carries the previous hop's delegation token there, so the issuer and audience of those tokens need a configuration too.
- **The delegation tokens need a Token Introspect configuration in both modes**, because the platform reads the token in `X-IK-Token` on the admission call only through a matching configuration: the IdP's exchanged tokens without a Token Service (often the same issuer + audience as the user tokens, then one configuration covers both), the Token Service issuer and `token_service.audience` with one. Without it the admission call fails as `["evaluating admission through AuthZEN failed"]`, audit `ERROR`.
- **Agent names are the `sub` claims** the IdP writes into the agents' client-credentials tokens, as the exchange copies them into `act.sub`; the `Agent` nodes' `external_id` must equal those values.
- **The resource type selects the policy.** It comes from the token's `act.type` (the Token Service writes its `idp.actor_type`, `Agent` by default); an IdP that writes no `act.type` needs `protected_agent.node_type`, or the type is `Agent`. One admission policy covers every agent and MCP server of that type. A subject or resource type without a policy is `decision: false`, so `403`, not an error.
- **Without a Token Service the chain grows only if the IdP nests the previous `act`** when the subject token is itself a delegation token. RFC 8693 allows but does not require it; a provider that does not nest gives the second gateway a chain of one agent, which matches no two-agent workflow.
- **The whoami answer is cached** per issuer, audience and subject of the token for `contx_iq.cache_ttl` (`0` keeps none); a failed whoami is not kept. **The admission decision is cached** for `authzen.cache_ttl` per subject, resource type, chain and the claims of both tokens other than `exp`, `iat`, `nbf`, `jti`; a grant or revocation in the graph takes effect when the entry expires. A failed admission call is served from the cache until `authzen.cache_update_after_error` has passed. Introspection and the exchange run on every request.
- **Long answers.** The gateway sets no time limit on an answer, in either mode; only connecting to the downstream is bounded (10 s). The caller decides how long it waits: when it closes the connection, the gateway stops its call downstream. Where the gateway does introspect, only `active: false` refuses the request as `401`; an answer that cannot be read is reported as a fault of that provider, so an outage is not recorded as a wave of denials.

## Delegation token delivery: `$token` or `$ik_token`

What the protected downstream receives depends on who minted the delegation token:

| Minted by                                  | `Authorization` header forwarded                   | `X-IK-Token` forwarded | Downstream's own policies read the chain as | Multi-hop chains |
|--------------------------------------------|----------------------------------------------------|------------------------|---------------------------------------------|------------------|
| IdP (no `token_service` section)           | the delegation token (replaces the caller's token) | not sent               | `$token`                                    | only if the IdP nests `act` when exchanging a delegation token |
| Token Service (`token_service` configured) | the caller's access token, as it arrived (if at all) | the delegation token | `$ik_token`                                 | yes - see below  |

The **admission policy** is different: the gateway sends the delegation token in `X-IK-Token` on its own AuthZEN call in both modes, so it always reads `$ik_token.act_chain`. The gateway strips any inbound `X-IK-Token` it does not use and sets its own, so a downstream only ever sees a token minted for it.

## Multi-hop chains with the Token Service

With `token_service` configured:

1. **Entry agent.** A user's token starts a workflow only at the gateway whose `protected_agent.authentication.audiences` lists one of its audiences. Sending the token issued for the orchestrator straight to the retriever's gateway is `401 Access token not issued for this agent`, before any chain or policy check. A direct call to a later agent is allowed by issuing the user a token for that agent's audience and modelling the one-agent workflow, not by reusing the orchestrator's token.
2. **Later hop.** A request with `X-IK-Token` is validated at the Token Service - the only party that can say whether a token it signed still holds up - and must carry an `act` object (`401 Invalid delegated token, missing act claim` otherwise: an issuer may mint users' access tokens as well, and such a token cannot take the place of a delegation token). It needs no `Authorization`; when a bearer token travels beside it and `authorization_header.same_user_check` is on (default), its `sub` must equal the delegation token's (`401 Invalid delegated token, subject mismatch`). With the check off, the bearer token of a later hop is not read at all, and whoami and the admission call receive the delegation token in its place.
3. The incoming token becomes the **subject token** of this hop's exchange, so the chain it carries is nested into the `act` claim of the token minted for the next hop; the admission policy sees the whole chain.
4. Every gateway of a path should ask for the same `token_service.audience` (or the same `authentication.audiences`), listed in the Token Service's `idp.audiences`, so the delegation token is accepted at the next hop and by the platform through one Token Introspect configuration per issuer.

The Token Service keeps no record of the tokens it issued: introspection re-validates the token against the service's own signing keys, and any token it did not sign is reported inactive. Keep `idp.token_ttl` short - nothing can revoke a delegation token before it expires.

## HTTP responses and what they mean

| Code | Meaning                                                                                  |
|------|------------------------------------------------------------------------------------------|
| 200  | Authorized - request forwarded, response returned, audit `AUTHORIZED`. In `mcp` mode any downstream status is passed through. With `ibac.enabled`, also the Intent Agent's refusal answered in place of the agent (`metadata.intent_error`). |
| 400  | `a2a`: JSON-RPC request could not be parsed. `mcp`: a JSON-RPC error body for a missing `Mcp-Protocol-Version` header or a mirrored `Mcp-Method` / `Mcp-Name` header that differs from the body (`-32020`), an unsupported revision (`-32022`), a batch, a non-JSON-RPC message or an ambiguous key (`-32600`), an invocation that names no tool or resource (`-32602`), or a body that is not one valid UTF-8 JSON value (`-32700`) - see [MCP protocol revisions](#mcp-protocol-revisions) and [MCP request classification](#mcp-request-classification). |
| 401  | IAG cannot identify the caller: `Missing bearer token`, `Access token not issued for this agent`, `["identity provider: the token is not active"]` / `["token service: the token is not active"]` (the latter also for an IdP token presented as `X-IK-Token`), `Invalid token, missing subject` / `missing act claim` / `act claim must be an object`, `Invalid delegated token` / `…, missing act claim` / `…, missing subject` / `…, subject mismatch`, `["ContX IQ whoami failed"]`. A `401` / `403` of a provider is passed through with an `errors` entry naming it (`["identity provider: token exchange failed - …"]`, `["evaluating admission through AuthZEN failed"]`); the audit decision `ERROR` tells a provider fault from a denial. In `mcp` mode every `401` carries `WWW-Authenticate: Bearer resource_metadata="…"`. |
| 403  | `{"message":"Authorization check failed"}`: the admission policy answered `false`, or the chain could not be read. The audit `reason` says which. |
| 404 / 405 | `mcp` mode: any path other than the endpoint path and the two metadata paths (`{"message":"Not Found"}`, before the token is read); a method other than `GET` / `HEAD` on a metadata path (`Allow: GET, HEAD`). `a2a`: `404`, `409`, `415`, `424`, `501` are errors of the protected agent, translated. |
| 413 / 415 | `mcp` mode only - body over 4 MiB (`413`) or a `Content-Encoding` other than `identity` (`415`); JSON-RPC error `-32600`. |
| 500  | `{"message":"Internal Server Error"}`: the IdP, the Token Service, ContX IQ, AuthZEN or an A2A agent could not be reached or timed out, or one of them answered `500`. |
| 502  | `{"message":"Bad Gateway","errors":[…]}`: the MCP server could not be reached or `base_url` is not a URL; an A2A agent answered unusably, its card cannot be used, or it redirected off the configured host; the IdP or Token Service answered with a malformed body; with `ibac.enabled`, the Intent Agent could not be asked or answered unreadably. |
| 504  | `["the intent agent did not answer in time"]`: the Intent Agent exceeded `intent_agent.timeout`. |

## Protocol: A2A or MCP

The decision sequence is the same in both modes; what differs is what sits behind the gateway and, because of it, where the chain can go next. An A2A agent can itself call another gateway, so it is a link in the middle of a chain; an MCP server only answers tool calls, so it is **always the last link** - a workflow that includes an MCP server lists it last (`[retriever, mcp-agent]`), and a direct call from a user's MCP client needs its own one-agent workflow (`[mcp-agent]`).

- **`a2a`** (default) - the gateway reads the agent card from `protected_agent.base_url`, keeps the card and the client built from it for `a2a.cache_ttl`, and calls the card's JSON-RPC interface with the scheme and host of that base URL (a redirect is followed only while it stays on that host, at most 5 hops; anything else is `502`). JSON-RPC is accepted on any path: `message/send`, `message/stream` (answered as `text/event-stream` before the agent is contacted; later failures arrive as JSON-RPC error frames), `tasks/get`, `tasks/list`, `tasks/cancel`, `tasks/resubscribe`, the four `tasks/pushNotificationConfig/*` methods, and `agent/getAuthenticatedExtendedCard`, also under their SDK-style names such as `SendMessage` and `GetTask`.
- **`mcp`** - the gateway serves MCP on one path, the path of `service.base_url` (compared exactly after percent-decoding, trailing slash included), and forwards every accepted request to the endpoint URL in `protected_agent.base_url` with the request's query appended; `Mcp-Session-Id` and the response body pass through unchanged, streamed for SSE, and the server's status is returned as is. Any other path is `404` before the token is read, except the two OAuth metadata paths. Two extra checks run after step 1 and before admission: the protocol revision check and the request classification, below.

What the downstream can do with the chain follows the delivery table: with a Token Service the IndyKite MCP server validates the forwarded `X-IK-Token` itself and its policies read `$ik_token`; a third-party server just receives the headers; without a Token Service the downstream gets the delegation token in `Authorization` and reads `$token`.

Three refusals follow from the reference admission policy and look the same in both modes - `403` `{"message": "Authorization check failed"}` and, in the audit record, the one reason `subject <type>/<id> may not reach <agent type>/<agent> through the delegation chain`; which of the three it was is read from `actorsChain` and the graph:

- **A skipped hop** - the user's own token sent straight to a later gateway: the chain is `[retriever]` or `[mcp-agent]`, the path of no workflow unless that one-agent shape is modelled. With a Token Service this case is already `401` (`Access token not issued for this agent`).
- **A token reused across workflows** - a delegation token minted for `[orchestrator, notifier]` presented to the retriever's gateway: the exchange appends the retriever and `[orchestrator, notifier, retriever]` is the path of no workflow, even for an agent that is part of both.
- **The wrong user** - the chain is a workflow's path, but no `CAN_TRIGGER` links this subject to it; two users with the same chain get their own answer.

## Agent card and OAuth discovery

- **`a2a`: `GET /.well-known/agent-card.json`** - the protected agent's card reduced to its JSON-RPC interfaces, each pointing at `service.base_url`, with the security scheme of the gateway's IdP (`identity_provider.openid_configuration_url`) in place of the agent's, and without the agent's signatures. Without `Authorization` the public card (no skills, `capabilities.extendedAgentCard` set); with a bearer token the extended card, after the same authentication and admission as any other request. `agent/getAuthenticatedExtendedCard` answers with the same extended card. Both settings are required in `a2a` mode for this reason.
- **`mcp`: OAuth 2.0 Protected Resource Metadata (RFC 9728)**, describing the gateway, not the server behind it. `GET /.well-known/oauth-protected-resource<path of service.base_url>` answers without a token: `resource` = `service.base_url`, `authorization_servers` = `[identity_provider.issuer]`, `bearer_methods_supported` = `["header"]`. `GET /.well-known/oauth-protected-resource` answers the same with the origin of `service.base_url` as `resource` (when the path is `/`, this is the only address). Both answer `GET` and `HEAD`; other methods `405`. Every `401` of the endpoint links the metadata in `WWW-Authenticate: Bearer resource_metadata="…"`; a `401` / `403` of the MCP server keeps its own challenge with only `resource_metadata` replaced or added. The ingress must not strip a path prefix and must route the metadata path to the gateway; the root address can serve only one gateway per host. A client asks for its token with `resource` = the metadata's `resource`; with `token_service` the server receives that token as it arrived, so it must accept the audience the IdP writes for it (the IndyKite MCP server does with a Token Introspect configuration), and the same value goes into `protected_agent.authentication.audiences`.

## MCP protocol revisions

In front of an MCP server the gateway forwards only the MCP protocol revisions **`2025-06-18`**, **`2025-11-25`**, and **`2026-07-28`**. The checks run after introspection and before admission, so an invalid token still gets `401` first, and a refused request never costs a whoami or AuthZEN call. They read the body only far enough to enforce these rules; they do not authorize by MCP payload or per tool. In this order:

| Request                                                        | Gateway behaviour                                                                                                       |
|----------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------|
| `Content-Encoding` other than `identity`                       | `415`, `-32600`, `Invalid Request: content coding <coding> is not supported`.                                            |
| Body that cannot be read to the end                            | `400`, `-32700`, `Parse error: cannot read the request body`.                                                           |
| Body over 4 MiB                                                | `413`, `-32600`, `Invalid Request: request body exceeds 4194304 bytes`.                                                 |
| Any request with an unsupported `Mcp-Protocol-Version` header - even an `initialize`; only the body's `protocolVersion` is rewritten, never the header | `400`, `-32022`, `Unsupported protocol version`; `error.data.supported` lists the three revisions and `error.data.requested` echoes the header. |
| Any other request without `Mcp-Protocol-Version` - including a `GET` stream, a `DELETE` session teardown, notifications and client responses | `400`, `-32020`, `Header mismatch: Mcp-Protocol-Version header is missing`. |
| JSON-RPC batch (body is a JSON array)                          | `400`, `-32600`, `Invalid Request: JSON-RPC batching is not supported`.                                                 |
| `initialize` naming a supported revision                       | Forwarded unchanged.                                                                                                    |
| `initialize` naming any other revision (e.g. `2025-03-26`)     | Forwarded with `params.protocolVersion` rewritten to `2025-11-25`, the newest revision a handshake can agree on. The server then offers that revision; a client that does not speak it disconnects. An `initialize` with no readable `protocolVersion` is forwarded as is, for the server to reject. |

A refused request is never forwarded and is audited as `NOT_AUTHORIZED` with `reason` = `MCP request refused: <error message>`. The error body is a JSON-RPC response; `id` is present only when the request had one and the message could be read, so the parse errors carry none.

The gateway checks requests only. If the downstream server answers an `initialize` with a revision the gateway does not support, the handshake succeeds and every later request is refused with `-32022` - so the MCP server behind the gateway must support at least one of the three revisions. A server that speaks `2026-07-28` needs no handshake at all: clients use `server/discover` and self-contained requests, the style the [`indykite-mcp-server`](../../indykite-mcp-server/SKILL.md) skill uses. A session-based client (`2025-06-18` / `2025-11-25`) must send `Mcp-Protocol-Version` on every request after `initialize`, next to `Mcp-Session-Id`.

## MCP request classification

After the revision checks, the gateway reads what each MCP request names - the tool of a `tools/call`, the resource URI of a `resources/read`, `resources/subscribe` or `resources/unsubscribe`, every URI in `params.notifications.resourceSubscriptions` of a `subscriptions/listen` - and either forwards the request or refuses it, so that the server acts on nothing other than what the gateway read. `tools/list`, `resources/list` and `prompts/list` are discovery requests. `initialize`, notifications, client responses, `prompts/get`, a `subscriptions/listen` with no resource subscriptions, and requests without a body name nothing and are forwarded as they are. Tool `arguments` and `_meta` are not inspected. The classification does not authorize per tool or resource; the admission policy still decides on the chain. Unlike some revision-check messages, these refusal messages never repeat a value the client sent.

| Request                                                                                                        | Gateway behaviour                                                                                                                                   |
|----------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------|
| Body that is not valid UTF-8, or not exactly one JSON value (two messages, trailing text)                     | `400`, `-32700`, `Parse error: the request body is not valid UTF-8` / `… is not one JSON value`.                                                    |
| JSON that is not a JSON-RPC 2.0 message (no `"jsonrpc": "2.0"`, neither `method` nor `result` / `error`)      | `400`, `-32600`, `Invalid Request: the request body is not a JSON-RPC message`.                                                                      |
| A key that JSON readers can read in more than one way - repeated, not printable ASCII, or differing from a field the gateway reads (`jsonrpc`, `method`, `params` in the message; `name`, `uri` or `notifications` in `params`; `resourceSubscriptions` in `params.notifications`) only in letter case or in `_` / `-` | `400`, `-32600`, `Invalid Request: the message has a repeated key` / `… has a key that is not printable ASCII` / `… has a key that can be read as <field>` (`the message`, `params` or `params.notifications` names the object). |
| Method, tool name or resource URI containing a control character, a lone surrogate, or `U+FFFD`                | `400`, `-32600`, `Invalid Request: the method contains a control character` / `the tool name …` / `the resource URI contains a lone surrogate or a replacement character`. |
| `tools/call` whose `params.name` is missing, empty, or not a string                                            | `400`, `-32602`, `Invalid params: tools/call names no tool`.                                                                                        |
| `resources/read`, `resources/subscribe`, `resources/unsubscribe` whose `params.uri` is missing, empty, or not a string | `400`, `-32602`, `Invalid params: <method> names no resource URI`.                                                                           |
| `subscriptions/listen` whose `resourceSubscriptions` is not a list of non-empty strings                        | `400`, `-32602`, `Invalid params: the resource subscriptions of subscriptions/listen cannot be read`.                                              |
| Revision `2026-07-28` only: `Mcp-Method` header differs from the body's `method`                               | `400`, `-32020`, `Header mismatch: Mcp-Method header does not match the method in the body`.                                                        |
| Revision `2026-07-28` only: `Mcp-Name` header differs from the tool name of a `tools/call` or the URI of a `resources/read`; a `=?base64?…?=` value is decoded first, one that does not decode is refused | `400`, `-32020`, `Header mismatch: Mcp-Name header does not match the tool name in the body` / `… the resource URI in the body` / `Mcp-Name header is not valid Base64`. |

A missing `Mcp-Method` or `Mcp-Name` header is left to the server. Like a revision refusal, a classification refusal is never forwarded and is audited as `NOT_AUTHORIZED` with `reason` = `MCP request refused: <error message>`.

## Supported endpoints

For an A2A agent (`protocol: a2a`): JSON-RPC on any path and any method (the list above), plus `GET /.well-known/agent-card.json`. For an MCP server (`protocol: mcp`): MCP Streamable HTTP JSON-RPC on the path of `service.base_url` only, plus the two `/.well-known/oauth-protected-resource…` metadata paths (`GET` / `HEAD`). Apart from the `initialize` revision rewrite, the payload is forwarded unchanged.

Health: `GET /healthz`, `/readyz`, `/startupz` on `service.healthcheck_port` (default `9080`), separate from the request port. The unauthenticated `401` works as an external probe too, but every such probe writes an audit record and, with webhook delivery, one webhook call.

## IKG data shape

For the admission policy to admit a chain, the IKG must contain:

- The **subject** node (type = the Token Introspect configuration's `ikg_node_type`, e.g. `User`), an identity node whose `external_id` is the `id` whoami returns for the user's token (`sub`, or the claim named by `sub_claim`), linked to the workflow with the relationship the policy matches (`CAN_TRIGGER`).
- A **`Workflow`** node with `external_id` matching the workflow identifier (e.g. `wf1`).
- One **`Agent`** node per protected agent or MCP server, `external_id` = the `sub` of its client-credentials token (what the exchange writes into `act.sub`).
- **`INVOKES`** relationships from the workflow through the agents in call order, each carrying a **`workflow_name`** property equal to the `Workflow.external_id`.

Example: for the demo workflow `wf1`, two valid delegation chains exist:

```text
chatbot -> orchestrator -> retriever
chatbot -> orchestrator -> weather
```

Any chain that skips the orchestrator (e.g. `chatbot -> retriever`) or adds an agent that is not modeled in `wf1` is rejected with `403 Forbidden`.

## Common pitfalls

- **Missing `workflow_name`** - the `INVOKES` path never matches and every request is denied.
- **Identifier mismatch** - the `external_id` on each `Agent` must match the `sub` the IdP writes into that agent's client-credentials token, as it appears in `actorsChain`.
- **No subject↔workflow link, or a non-identity subject node** - even with a correct chain, the policy answers `false`.
- **Subject type mismatch** - the subject type is the `ikg_node_type` of the Token Introspect configuration that validates the caller's token; an admission policy for any other type never matches. `authzen.subject_types` is not read.
- **No Token Introspect configuration for a caller's token** - whoami refuses it and every request answers `401` with `ContX IQ whoami failed`.
- **No Token Introspect configuration for the delegation tokens** - the admission call fails (`["evaluating admission through AuthZEN failed"]`, audit `ERROR`), in both modes.
- **Admission policy missing or INACTIVE** - every request is `403`; the gateway no longer runs a Knowledge Query, so `contx_iq.query_id` does not help.
- **`protected_agent.node_type` differs from the token's `act.type`** - every request refused with an `ERROR` record naming both.
- **Second hop refused with no Token Service** - the IdP does not nest `act`, so the chain restarts on every hop; configure `token_service` on every gateway of the workflow.
- **Workflow started at the wrong gateway (Token Service)** - `401 Access token not issued for this agent`; issue the user a token for that agent's audience and model the shape, or route through the entry agent.
- **MCP client omits `Mcp-Protocol-Version` after `initialize`** - every request after the handshake is refused with `400` / `-32020` before authorization runs; send the negotiated revision on every call.
- **MCP server negotiates a revision the gateway does not forward** - the handshake succeeds and every later request is refused with `-32022`; the server must speak `2025-06-18`, `2025-11-25`, or `2026-07-28`.
- **MCP `tools/call` refused with `-32602` or `-32600` before authorization** - the gateway could not read which tool or resource the request names; fix the client, the gateway never forwards what it cannot classify.
- **MCP client calls another path of the server through the gateway** - `404`; the gateway serves the endpoint path of `service.base_url` only.

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
orchestrator-iag:8881  ── introspect / exchange ──▶  IdP ($IDP_BASE_URL)
   │                    ── (exchange / introspect)▶  Token Service (optional, self-hosted)
   │                    ── CAN_TRIGGER wf1      ──▶  AuthZEN
   │                    ── workflows / chains   ──▶  ContX IQ (IKG)
   │                    ── audit webhook        ──▶  chatbot:3000/api/push-update
   ▼
orchestrator:6001
   │  delegates
   ▼
retriever-iag:8882  ──▶  retriever:6002         (canbank questions)
weather-iag:8884    ──▶  weather:6004           (weather questions)
```

Three protected agents, three IAG instances, one shared IdP, one shared IndyKite project, and - when multi-hop chains are needed - one shared Token Service.

The iag-mcp-demo also runs a fourth instance, `mcp-iag:8886`, running in MCP proxy mode (`protocol: mcp`) in front of the IndyKite MCP server. The `retriever` and `weather` agents are MCP clients routed through `mcp-iag` instead of calling the MCP server directly, so MCP traffic gets the same introspection, AuthZEN check, and audit as the A2A flows.

Neither the gateway nor the Token Service is part of the IndyKite platform: both are deployed and operated in the customer's environment and talk to the platform's AuthZEN and ContX IQ endpoints over the public API.

## The nine-step request path

For each incoming request, an IAG instance runs the same nine steps. The example uses `orchestrator-iag`.

| #  | Step                | Question answered                                                                | Service answering                          |
|----|---------------------|-----------------------------------------------------------------------------------|--------------------------------------------|
| 1  | Receive             | (none - accept the A2A JSON-RPC / MCP request on the configured port)             | IAG itself                                 |
| 2  | Introspect          | Is the caller's access token valid and active? With a Token Service: is the incoming `X-IK-Token` one it signed, still valid, and paired with this access token? | IdP (`oauth-introspect`); Token Service (`/oauth2/introspect`) |
| 3  | Client credentials  | Can IAG authenticate as the protected agent?                                      | IdP (`oauth-token`)                        |
| 4  | Token exchange      | Can the caller (or the incoming chain) delegate to the protected agent?           | IdP (`oauth-token`) or Token Service (`/oauth2/token`) |
| 5  | ContX IQ query      | Which workflows is this agent part of, and what chains are allowed?               | ContX IQ (IKG)                             |
| 6  | AuthZEN             | Who is the subject (since 2.82.0: `GET /contx-iq/v1/whoami` on the caller's token), and can it `CAN_TRIGGER` at least one candidate workflow? | ContX IQ whoami; AuthZEN / KBAC |
| 7  | Chain check         | Does the requested `act` chain match an allowed agent chain?                      | IAG (in-process)                           |
| 8  | Forward             | (forward the request to the protected agent with the delegation token)            | Protected agent                            |
| 9  | Return + audit      | (return the response to the caller and write an audit record)                     | IAG itself                                 |

The gateway reads the claims of the delegation token it just minted rather than introspecting it a second time: the issuer handed it over TLS in answer to the gateway's own exchange call, so only `exp`, `nbf`, and `iat` are checked. A deployment on an IdP alone therefore also saves one round trip per request; a delegation token that is not a JWT is introspected at the IdP, while with the Token Service one that cannot be read is refused.

**The subject (step 6).** Since 2.82.0 the gateway asks ContX IQ `GET /contx-iq/v1/whoami` who the caller is. The subject type is the `ikg_node_type` of the project's Token Introspect configuration that validates the token, the id is the token's subject (the `sub` claim, or the claim named by that configuration's `sub_claim`); the gateway then runs one AuthZEN resource search with that subject. Consequences:

- Every token that reaches a gateway in `Authorization` needs a Token Introspect configuration that validates it (`jwt_matcher` issuer / audience matching for a JWT, or an opaque-token configuration); otherwise whoami refuses it and the gateway answers `401` `{"message":"Unauthorized","errors":["ContX IQ whoami failed"]}`, audit reason `cannot resolve the subject of the access token`. Without a Token Service, a later hop carries the previous hop's delegation token in `Authorization`, so that delegation token needs a matching configuration too; with one, `Authorization` carries the user's own token on every hop.
- The trigger policy's subject type must equal that `ikg_node_type`; a policy for another type never matches. The graph must hold a node of that type whose `external_id` equals the `id` whoami returns (`sub` by default, or the `sub_claim` claim), and it must be an identity node for a `2.0-kbac` policy.
- The whoami answer is kept per issuer, audience and subject of the token for `contx_iq.cache_ttl` (`0` keeps none); a failed whoami is not kept. A change to the Token Introspect configuration, such as its `ikg_node_type`, reaches the gateway after up to `contx_iq.cache_ttl`.
- Older images have no whoami step: they make one resource search per type in `authzen.subject_types`, with the delegation token's `sub` as the id. From 2.82.0 that key is not read.

**Long answers.** Since 2.82.4 the gateway sets no time limit on an answer, in either mode, so a long stream or a slow agent reaches the caller; older images cut an answer after one minute, and in `mcp` mode also gave up when the server's response headers took more than 30 seconds. Only connecting to the agent or the MCP server is still bounded, to 10 seconds. The caller decides how long it waits: when it closes the connection, the gateway stops its call downstream.

Where the gateway does introspect (the caller's access token, an incoming `X-IK-Token`), it reads the RFC 7662 `active` field. Only `active: false` refuses the request as `401`; an answer that cannot be read, or that never says whether the token is active, is reported as a fault of that provider (`502`), so an outage is not recorded as a wave of denials.

## Delegation token delivery: `$token` or `$ik_token`

What the protected agent receives depends on who minted the delegation token:

| Minted by                        | `Authorization` header            | `X-IK-Token` header    | Policy reads the chain as | Multi-hop chains |
|----------------------------------|-----------------------------------|------------------------|---------------------------|------------------|
| IdP (no `token_service` section) | the delegation token (replaces the caller's token) | not sent | `$token`                  | no - every hop exchanges the user's access token again, so the chain never grows and a workflow longer than one hop is refused |
| Token Service (`token_service` configured) | the caller's access token, untouched | the delegation token   | `$ik_token`               | yes - see below |

The gateway strips any inbound `X-IK-Token` before forwarding and sets its own, so a protected agent only ever sees a token minted for it.

## Multi-hop chains with the Token Service

With the Token Service configured, a request that arrives **without** `X-IK-Token` is the first hop: its chain starts from the token the gateway mints (`sub` = the caller, `act` = the protected agent). A request that arrives **with** `X-IK-Token` is a later hop:

1. The token is validated at the Token Service - the only party that can say whether a token it signed still holds up.
2. Its `sub` must equal the `sub` of the access token it arrived with; otherwise the request is refused with `401 Invalid delegated token, subject mismatch` (or `missing subject`) and a `NOT_AUTHORIZED` audit record.
3. It becomes the **subject token** of this hop's exchange, so the chain it carries is nested into the `act` claim of the token minted for the next hop.
4. Steps 5-7 then authorize this hop on the **whole** chain that led to it, and the chain check compares that chain against the workflow's modeled agent chains.

The Token Service keeps no record of the tokens it issued: introspection re-validates the token against the service's own signing keys, and any token it did not sign is reported inactive. Keep `idp.token_ttl` short - nothing can revoke a delegation token before it expires.

## HTTP responses and what they mean

| Code | Meaning                                                                                  |
|------|------------------------------------------------------------------------------------------|
| 200  | Authorized - request forwarded, response returned, audit `AUTHORIZED`.                   |
| 400  | Bad request - content cannot be processed. In `mcp` mode: a JSON-RPC error body for a missing `Mcp-Protocol-Version` header or a mirrored `Mcp-Method` / `Mcp-Name` header that differs from the body (`-32020`), an unsupported revision (`-32022`), a JSON-RPC batch, a non-JSON-RPC message or an ambiguous key (`-32600`), an invocation that names no tool or resource (`-32602`), or a body that is not one valid UTF-8 JSON value (`-32700`) - see [MCP protocol revisions](#mcp-protocol-revisions) and [MCP request classification](#mcp-request-classification). |
| 401  | Unauthorized - IAG cannot identify the caller: `Missing bearer token`, introspection says inactive, `Invalid token, missing subject`, `Invalid token, missing act claim`, or an incoming `X-IK-Token` that is invalid or not paired with the access token (`Invalid delegated token, …`). |
| 403  | Forbidden - caller is authenticated but not allowed (subject, chain, or both): `Authorization check failed`. |
| 413 / 415 | `mcp` mode only - body over 4 MiB (`413`) or a `Content-Encoding` other than `identity` (`415`); JSON-RPC error `-32600`. |
| 500  | Internal error - unexpected internal failure.                                            |
| 502  | Bad gateway - upstream or gateway-side processing issue (IdP / Token Service unreachable or answering unreadably, protected agent unreachable, etc.). |

IAG may also translate upstream errors when appropriate (for example, `404` from ContX IQ).

## Protocol: A2A or MCP

The same nine-step authorization path runs regardless of what IAG protects - only **step 8 (Forward)** differs by `protected_agent.protocol`:

- **`a2a`** (default) - IAG parses the A2A JSON-RPC method and forwards via the A2A gateway (the methods listed under *Supported endpoints* below).
- **`mcp`** - IAG proxies MCP **Streamable HTTP** JSON-RPC (`initialize`, `notifications/initialized`, `tools/list`, `tools/call`) to a downstream MCP server. It is a transparent pass-through: the `Mcp-Session-Id` header is forwarded in both directions and SSE response bodies are streamed through without being cut off. IAG mints its own token for the downstream MCP server, so the request is forwarded with the delegation token attached. `base_url` is the MCP server **origin only** - the incoming request path/query is appended on top. Requires the gateway image ≥ 2.0.1.

Steps 1–7 and 9 (introspect, exchange, ContX IQ, AuthZEN `CAN_TRIGGER`, chain check, audit) are identical for both protocols. An MCP server is gated exactly like an A2A agent. In `mcp` mode two extra checks run between step 2 and step 5, in this order: the protocol revision check and the request classification, both below.

The two protocols differ in where their link can sit in a chain. An A2A agent can be any hop; an MCP server never calls another agent, so it is **always the last link** - a workflow that includes an MCP server lists it last (`[retriever, mcp-agent]`), and a direct call from a user to the gateway in front of it needs its own one-agent workflow (`[mcp-agent]`). What the MCP server receives follows the delivery table above: with a Token Service the IndyKite MCP server validates the forwarded `X-IK-Token` itself and its policies read `$ik_token`; without one it receives the delegation token in `Authorization` and policies read `$token`.

Three chain refusals all answer `403` `{"message": "Authorization check failed"}`; only the audit record's `reason` tells them apart:

- **A skipped hop** (the chain does not match any workflow the subject can trigger) - `no workflow matches the actors chain`.
- **A token reused across workflows** (a delegation token minted for `[orchestrator, notifier, retriever]` presented on a different chain) - the same reason, since the `act` chain matches no workflow of this gateway.
- **The wrong user** (the chain matches a workflow, but the subject holds no `CAN_TRIGGER` on it) - `subject <type>/<id> is not authorized to trigger any of the workflows <workflow ids>` (before 2.82.0 without `<type>/<id>`).

## MCP protocol revisions

In front of an MCP server the gateway forwards only the MCP protocol revisions **`2025-06-18`**, **`2025-11-25`**, and **`2026-07-28`**. The check runs after token introspection (step 2) and before authorization (steps 5-7), so an invalid token still gets `401` first, and a refused request never costs a ContX IQ or AuthZEN call. It reads the body only far enough to enforce these rules; it does not authorize by MCP payload or per tool. The rules are those the `2026-07-28` revision defines for the `Mcp-Protocol-Version` header:

| Request                                                        | Gateway behaviour                                                                                                       |
|----------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------|
| `initialize` naming a supported revision                       | Forwarded unchanged.                                                                                                    |
| `initialize` naming any other revision (e.g. `2025-03-26`)     | Forwarded with `params.protocolVersion` rewritten to `2025-11-25`, the newest revision a handshake can agree on. The server then offers that revision; a client that does not speak it disconnects. An `initialize` with no readable `protocolVersion` is forwarded as is, for the server to reject. |
| Any other request without `Mcp-Protocol-Version` - including a `GET` stream or a `DELETE` session teardown, which carry no body | `400`, JSON-RPC error `-32020`, `Header mismatch: Mcp-Protocol-Version header is missing`. |
| Any request with an unsupported `Mcp-Protocol-Version` header - even an `initialize`; only the body's `protocolVersion` is rewritten, never the header | `400`, JSON-RPC error `-32022`, `Unsupported protocol version`; `error.data.supported` lists the three revisions and `error.data.requested` echoes the header. |
| JSON-RPC batch (body is a JSON array)                          | `400`, `-32600`, `Invalid Request: JSON-RPC batching is not supported`.                                                 |
| `Content-Encoding` other than `identity`                       | `415`, `-32600`, `Invalid Request: content coding <coding> is not supported`.                                            |
| Body over 4 MiB                                                | `413`, `-32600`.                                                                                                        |
| Body that cannot be read to the end                            | `400`, `-32700`, `Parse error`.                                                                                         |

A refused request is never forwarded and is audited as `NOT_AUTHORIZED` with `reason` = `MCP request refused: <error message>`. The error body is a JSON-RPC response under the request's `id` when the body was parsed (missing or unsupported header); it has no `id` when it was not (batch, unsupported encoding, oversized or unreadable body).

The gateway checks requests only. If the downstream server answers an `initialize` with a revision the gateway does not support, the handshake succeeds and every later request is refused with `-32022` - so the MCP server behind the gateway must support at least one of the three revisions. A server that speaks `2026-07-28` needs no handshake at all: clients use `server/discover` and self-contained requests, the style the [`indykite-mcp-server`](../../indykite-mcp-server/SKILL.md) skill uses. A session-based client (`2025-06-18` / `2025-11-25`) must send `Mcp-Protocol-Version` on every request after `initialize`, next to `Mcp-Session-Id`.

## MCP request classification

After the revision check, the gateway reads what each MCP request names - the tool of a `tools/call`, the resource URI of a `resources/read`, `resources/subscribe` or `resources/unsubscribe`, every URI in `params.notifications.resourceSubscriptions` of a `subscriptions/listen` - and either forwards the request or refuses it, so that the server acts on nothing other than what the gateway read. `tools/list` and `resources/list` are discovery requests. `initialize`, notifications, responses, prompt requests, a `subscriptions/listen` with no resource subscriptions, and requests without a body name nothing and are forwarded as they are. Tool `arguments` and `_meta` are not inspected. The classification does not authorize per tool or resource; AuthZEN still decides on the workflow. Unlike some revision-check messages, these refusal messages never repeat a value the client sent.

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

A missing `Mcp-Method` or `Mcp-Name` header is left to the server. Like a revision refusal, a classification refusal is never forwarded and is audited as `NOT_AUTHORIZED` with `reason` = `MCP request refused: <error message>`; the JSON-RPC error body carries the request's `id` once the method and `params` could be read in one way only, and no `id` otherwise.

## Supported endpoints

For an A2A agent (`protocol: a2a`), the gateway accepts any path and routes JSON-RPC by method (A2A v1.0): `SendMessage`, `SendStreamingMessage` (answered as `text/event-stream` SSE frames), `GetTask`, `ListTasks`, `CancelTask`, `SubscribeToTask`, `GetExtendedAgentCard`, and the push-notification config methods (`CreateTaskPushNotificationConfig`, `GetTaskPushNotificationConfig`, `ListTaskPushNotificationConfigs`, `DeleteTaskPushNotificationConfig`). The REST-style aliases `POST /v1/message:send`, `/v1/message/send`, `/v1/tasks:get`, `/v1/tasks/get` are still served.

For an MCP server (`protocol: mcp`), IAG accepts MCP Streamable HTTP JSON-RPC on any path and forwards it (`initialize`, `notifications/initialized`, `tools/list`, `tools/call`, …), provided the request is on a supported protocol revision and names its tool or resource unambiguously - see [MCP protocol revisions](#mcp-protocol-revisions) and [MCP request classification](#mcp-request-classification). Apart from the `initialize` revision rewrite, the payload is forwarded unchanged.

Health: `GET /healthz`, `/readyz`, `/startupz` on `service.healthcheck_port` (default `9080`), separate from the request port.

## IKG data shape

For chain validation to work, the IKG must contain:

- A **`Workflow`** node with `external_id` matching the workflow identifier (e.g. `wf1`).
- One **`Agent`** node per protected agent, identified by `external_id` matching the IdP-side agent identifier and the `act` chain entry.
- **`INVOKES`** relationships between agents, each carrying a **`workflow_name`** property whose value matches the `Workflow.external_id`.

Example: for the demo workflow `wf1`, two valid delegation chains exist:

```text
chatbot -> orchestrator -> retriever
chatbot -> orchestrator -> weather
```

Any chain that skips the orchestrator (e.g. `chatbot -> retriever`) or adds an agent that is not modeled in `wf1` is rejected with `403 Forbidden`.

## Common pitfalls

- **Missing `workflow_name`** - the ContX IQ query returns nothing and every request is denied.
- **Identifier mismatch** - the `external_id` on each `Agent` must match the identifier carried in the `act` chain *and* the IdP client identifier.
- **No subject↔workflow link** - even with a correct chain, the request is denied at the AuthZEN step if the subject cannot `CAN_TRIGGER` the workflow.
- **Subject type mismatch** - the subject type is the `ikg_node_type` of the Token Introspect configuration that validates the caller's token (2.82.0+); a trigger policy for any other type never matches and the call is denied. Before 2.82.0 the type had to be listed in `JARVIS_AUTHZEN_SUBJECT_TYPES`.
- **No Token Introspect configuration for a caller's token** (2.82.0+) - whoami refuses it and every request answers `401` with `ContX IQ whoami failed`.
- **Policy reads the wrong token** - `$token` with a Token Service, or `$ik_token` without one, resolves to nothing and denies.
- **Second hop refused with no Token Service** - on an IdP alone the chain restarts from the user's access token on every hop; configure `token_service` on every gateway of the workflow.
- **MCP client omits `Mcp-Protocol-Version` after `initialize`** - every request after the handshake is refused with `400` / `-32020` before authorization runs; send the negotiated revision on every call.
- **MCP server negotiates a revision the gateway does not forward** - the handshake succeeds and every later request is refused with `-32022`; the server must speak `2025-06-18`, `2025-11-25`, or `2026-07-28`.
- **MCP `tools/call` refused with `-32602` or `-32600` before authorization** - the gateway could not read which tool or resource the request names: `params.name` / `params.uri` missing or not a string, a repeated or case-variant key next to `name`, `uri` or `method`, or a `2026-07-28` request whose `Mcp-Method` / `Mcp-Name` header differs from the body (`-32020`). Fix the client; the gateway never forwards what it cannot classify.

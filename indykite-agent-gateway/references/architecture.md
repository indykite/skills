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
| 6  | AuthZEN             | Can the subject `CAN_TRIGGER` at least one candidate workflow?                    | AuthZEN / KBAC                             |
| 7  | Chain check         | Does the requested `act` chain match an allowed agent chain?                      | IAG (in-process)                           |
| 8  | Forward             | (forward the request to the protected agent with the delegation token)            | Protected agent                            |
| 9  | Return + audit      | (return the response to the caller and write an audit record)                     | IAG itself                                 |

The gateway reads the claims of the delegation token it just minted rather than introspecting it a second time: the issuer handed it over TLS in answer to the gateway's own exchange call, so only `exp`, `nbf`, and `iat` are checked. A deployment on an IdP alone therefore also saves one round trip per request; a delegation token that is not a JWT is introspected at the IdP, while with the Token Service one that cannot be read is refused.

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
| 400  | Bad request - content cannot be processed.                                               |
| 401  | Unauthorized - IAG cannot identify the caller: `Missing bearer token`, introspection says inactive, `Invalid token, missing subject`, `Invalid token, missing act claim`, or an incoming `X-IK-Token` that is invalid or not paired with the access token (`Invalid delegated token, …`). |
| 403  | Forbidden - caller is authenticated but not allowed (subject, chain, or both): `Authorization check failed`. |
| 500  | Internal error - unexpected internal failure.                                            |
| 502  | Bad gateway - upstream or gateway-side processing issue (IdP / Token Service unreachable or answering unreadably, protected agent unreachable, etc.). |

IAG may also translate upstream errors when appropriate (for example, `404` from ContX IQ).

## Protocol: A2A or MCP

The same nine-step authorization path runs regardless of what IAG protects - only **step 8 (Forward)** differs by `protected_agent.protocol`:

- **`a2a`** (default) - IAG parses the A2A JSON-RPC method and forwards via the A2A gateway (the methods listed under *Supported endpoints* below).
- **`mcp`** - IAG proxies MCP **Streamable HTTP** JSON-RPC (`initialize`, `notifications/initialized`, `tools/list`, `tools/call`) to a downstream MCP server. It is a transparent pass-through: the `Mcp-Session-Id` header is forwarded in both directions and SSE response bodies are streamed through without being cut off. IAG mints its own token for the downstream MCP server, so the request is forwarded with the delegation token attached. `base_url` is the MCP server **origin only** - the incoming request path/query is appended on top. Requires the gateway image ≥ 2.0.1.

Steps 1–7 and 9 (introspect, exchange, ContX IQ, AuthZEN `CAN_TRIGGER`, chain check, audit) are identical for both protocols. An MCP server is gated exactly like an A2A agent.

## Supported endpoints

For an A2A agent (`protocol: a2a`), the gateway accepts any path and routes JSON-RPC by method (A2A v1.0): `SendMessage`, `SendStreamingMessage` (answered as `text/event-stream` SSE frames), `GetTask`, `ListTasks`, `CancelTask`, `SubscribeToTask`, `GetExtendedAgentCard`, and the push-notification config methods (`CreateTaskPushNotificationConfig`, `GetTaskPushNotificationConfig`, `ListTaskPushNotificationConfigs`, `DeleteTaskPushNotificationConfig`). The REST-style aliases `POST /v1/message:send`, `/v1/message/send`, `/v1/tasks:get`, `/v1/tasks/get` are still served.

For an MCP server (`protocol: mcp`), IAG accepts MCP Streamable HTTP JSON-RPC on any path and forwards it unchanged (`initialize`, `notifications/initialized`, `tools/list`, `tools/call`, …).

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
- **`subject_types` mismatch** - if the caller's type is not listed in `JARVIS_AUTHZEN_SUBJECT_TYPES`, no policy matches and the call is denied.
- **Policy reads the wrong token** - `$token` with a Token Service, or `$ik_token` without one, resolves to nothing and denies.
- **Second hop refused with no Token Service** - on an IdP alone the chain restarts from the user's access token on every hop; configure `token_service` on every gateway of the workflow.

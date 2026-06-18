# IAG Architecture Reference

This file is loaded by agents that need to reason about how IAG processes a single request, so they can answer questions like "why was this `403`?" or "where in the path does the failure happen?".

## Topology (iag-demo)

```text
leslie (user)
   │  login via chatbot
   ▼
chatbot:3000
   │  A2A JSON-RPC
   ▼
orchestrator-iag:8881  ── introspect / exchange ──▶  IdP ($IDP_BASE_URL)
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

Three protected agents, three IAG instances, one shared IdP, one shared IndyKite project.

The `iag-mcp-demo` variant adds a fourth instance, `mcp-iag:8886`, running in MCP proxy mode (`protocol: mcp`) in front of the IndyKite MCP server. The `retriever` and `weather` agents are MCP clients routed through `mcp-iag` instead of calling the MCP server directly, so MCP traffic gets the same introspection, AuthZEN check, and audit as the A2A flows.

## The nine-step request path

For each incoming request, an IAG instance runs the same nine steps. The example uses `orchestrator-iag`.

| #  | Step                | Question answered                                                                | Service answering         |
|----|---------------------|-----------------------------------------------------------------------------------|---------------------------|
| 1  | Receive             | (none - accept the A2A JSON-RPC request on the configured port)                   | IAG itself                |
| 2  | Introspect          | Is the caller's token valid and active?                                           | IdP (`oauth-introspect`)  |
| 3  | Client credentials  | Can IAG authenticate as the protected agent?                                      | IdP (`oauth-token`)       |
| 4  | Token exchange      | Can the caller delegate to the protected agent?                                   | IdP (`oauth-token`)       |
| 5  | ContX IQ query      | Which workflows is this agent part of, and what chains are allowed?               | ContX IQ (IKG)            |
| 6  | AuthZEN             | Can the subject `CAN_TRIGGER` at least one candidate workflow?                    | AuthZEN / KBAC            |
| 7  | Chain check         | Does the requested `act` chain match an allowed agent chain?                      | IAG (in-process)          |
| 8  | Forward             | (forward the request to the protected agent with the delegated token)             | Protected agent           |
| 9  | Return + audit      | (return the response to the caller and write an audit record)                     | IAG itself                |

## HTTP responses and what they mean

| Code | Meaning                                                                                  |
|------|------------------------------------------------------------------------------------------|
| 200  | Authorized - request forwarded, response returned, audit `AUTHORIZED`.                   |
| 400  | Bad request - content cannot be processed.                                               |
| 401  | Unauthorized - IAG cannot identify the caller (introspect failed).                       |
| 403  | Forbidden - caller is authenticated but not allowed (subject, chain, or both).            |
| 500  | Internal error - unexpected internal failure.                                            |
| 502  | Bad gateway - upstream or gateway-side processing issue (IdP unreachable, etc.).         |

IAG may also translate upstream errors when appropriate (for example, `404` from ContX IQ).

## Protocol: A2A or MCP

The same nine-step authorization path runs regardless of what IAG protects - only **step 8 (Forward)** differs by `protected_agent.protocol`:

- **`a2a`** (default) - IAG parses the A2A JSON-RPC method and forwards via the A2A gateway (the methods listed under *Supported endpoints* below).
- **`mcp`** - IAG proxies MCP **Streamable HTTP** JSON-RPC (`initialize`, `notifications/initialized`, `tools/list`, `tools/call`) to a downstream MCP server. It is a transparent pass-through: the `Mcp-Session-Id` header is forwarded in both directions and SSE response bodies are streamed through without being cut off. IAG mints its own token for the downstream MCP server, so the request is forwarded with the delegation token attached. `base_url` is the MCP server **origin only** - the incoming request path/query is appended on top. Requires the gateway image ≥ 2.0.1.

Steps 1–7 and 9 (introspect, exchange, ContX IQ, AuthZEN `CAN_TRIGGER`, chain check, audit) are identical for both protocols. An MCP server is gated exactly like an A2A agent.

## Supported endpoints

For an A2A agent (`protocol: a2a`):

- Any method on `/` for generic JSON-RPC (`message/send`, `tasks/get`).
- `POST /v1/message:send` and `POST /v1/message/send` - A2A SendMessage.
- `POST /v1/tasks:get` and `POST /v1/tasks/get` - A2A GetTask.

For an MCP server (`protocol: mcp`), IAG accepts MCP Streamable HTTP JSON-RPC on `/` and forwards it unchanged (`initialize`, `notifications/initialized`, `tools/list`, `tools/call`, …).

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

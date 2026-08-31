---
name: indykite-mcp-server
description: Make live IndyKite authorization decisions (AuthZEN/KBAC) and run ContX IQ graph queries from an AI agent over the Model Context Protocol - self-contained Bearer-token JSON-RPC calls on the stateless protocol (revision 2026-07-28), no session handshake and no bespoke REST wiring. Use when calling the IndyKite MCP server (server/discover, tools/list, authzen_evaluate, authzen_evaluations, authzen_search_*, ciq_execute), configuring an MCP server, or debugging its single Bearer-token auth.
license: Apache-2.0
compatibility: Requires curl and bash 4+. Network access to eu.mcp.indykite.com or us.mcp.indykite.com, plus the OAuth IdP that issues Bearer tokens, is required at runtime.
---

# IndyKite MCP Server

The **IndyKite MCP server** lets an AI agent make authorization decisions - "can this subject do X on Y?" (AuthZEN/KBAC) - and read or write the IndyKite Graph (ContX IQ), directly through the [Model Context Protocol](https://modelcontextprotocol.io/) instead of bespoke REST calls. It speaks **JSON-RPC over HTTP POST**. This skill uses the **stateless protocol** (revision `2026-07-28` and later): no `initialize`/`initialized` handshake and no `Mcp-Session-Id` - every request is self-contained, carrying the protocol metadata in `params._meta` plus the standard MCP headers. Older revisions (e.g. `2025-11-25`) use a session handshake instead; that legacy style is summarized in [`references/architecture.md`](references/architecture.md).

Two regional endpoints exist:

- **EU**: `https://eu.mcp.indykite.com`
- **US**: `https://us.mcp.indykite.com`

The full URL for one project is `<MCP_REGIONAL_URL>/mcp/v1/<project_gid>`.

## When to use

Activate this skill when the user:

- needs to **call** the IndyKite MCP server (discover its capabilities, list tools/resources, or call AuthZEN/CIQ tools);
- is **configuring** an MCP server for a project (`POST /configs/v1/mcp-servers`) and needs the field set;
- is debugging a **`401`** that returned `.well-known/oauth-protected-resource` metadata - almost always a missing, expired, or wrongly-bound `Authorization: Bearer` token;
- is wiring an LLM client (Claude Code, Cursor, Goose, the [MCP Go SDK](https://github.com/modelcontextprotocol/go-sdk), etc.) into the IndyKite MCP and needs the request shape;
- is choosing between `authzen_evaluate`, `authzen_evaluations`, `authzen_search_resource`, `authzen_search_action`, and `ciq_execute`.

Do **not** activate this skill when the user:

- is asking about the IndyKite Agent Gateway (use the [`indykite-agent-gateway`](../indykite-agent-gateway/SKILL.md) skill - IAG protects A2A agents or MCP servers behind a gateway, a different product);
- is calling AuthZEN or ContX IQ over their **direct REST APIs** (no MCP involved) - different endpoints, different auth shape;
- is asking about the MCP **specification itself** rather than the IndyKite implementation.

## Prerequisites

The MCP server will reject requests for a project until all of the following exist:

- An IndyKite **project** with an **Application** and an **AppAgent** (with Authorization API + ContX IQ API permissions). The server uses this AppAgent to call IndyKite APIs at runtime, resolved server-side from the MCP server configuration's `app_agent_id` - the client no longer sends an AppAgent token.
- A **Token Introspect** configuration on the project - used to validate inbound user Bearer tokens.
- An **MCP server configuration** (`POST /configs/v1/mcp-servers`) that binds the runtime endpoint to the AppAgent (`app_agent_id`) and Token Introspect, and declares `scopes_supported`. Without this configuration, requests for the project are rejected. See [`references/configuration.md`](references/configuration.md).
- The project's **GID** (used in the URL path).
- Captured **data and policies**: KBAC and/or CIQ policies and Knowledge Queries, depending on which tools the agent will call.

If any of these are missing, stop and tell the user - fixing them first is much cheaper than debugging an opaque MCP rejection.

## The stateless request shape

Every request in this skill carries the same scaffolding; only the `method` and its payload change.

**In the body**, a `params._meta` object:

```json
"_meta": {
  "io.modelcontextprotocol/protocolVersion": "2026-07-28",
  "io.modelcontextprotocol/clientCapabilities": {},
  "io.modelcontextprotocol/clientInfo": {"name": "curl", "version": "1.0"}
}
```

The `protocolVersion` key is **required** - a request without it is treated as legacy session-based and will fail with `404 session not found`. `clientCapabilities` is required (`{}` if none); `clientInfo` is optional.

**In the headers**:

| Header                             | Value                                                                                          |
|------------------------------------|------------------------------------------------------------------------------------------------|
| `Authorization: Bearer <token>`    | The user's OAuth access token - the only auth header.                                          |
| `Content-Type`                     | `application/json`                                                                             |
| `Accept`                           | `application/json, text/event-stream` - responses may arrive as an SSE stream.                 |
| `Mcp-Protocol-Version`             | `2026-07-28`                                                                                   |
| `Mcp-Method`                       | Must equal the JSON-RPC `method` in the body; mismatch or absence is rejected.                 |
| `Mcp-Name`                         | Required for `tools/call` (tool name), `resources/read` (resource URI), `prompts/get` (prompt name); must match the body. |

No session is created and no `Mcp-Session-Id` header comes back. If a mixed-version client sends a stale `Mcp-Session-Id` alongside a `2026-07-28` `_meta`, the `_meta` wins and the header is ignored.

The helper [`scripts/mcp-call.sh`](scripts/mcp-call.sh) assembles all of this for any method.

## Steps

### 1. Resolve the URL and credentials

Build the full MCP URL: `<MCP_URL>/mcp/v1/<project_gid>` where `<MCP_URL>` is `https://eu.mcp.indykite.com` or `https://us.mcp.indykite.com`. Get the values into shell variables:

```bash
export BEARER_TOKEN="<user-OAuth-access-token>"   # → Authorization: Bearer
export MCP_URL="https://us.mcp.indykite.com"
export PROJECT_GID="<your-project-gid>"
```

A single `Authorization: Bearer` header is the only auth header on every call. The AppAgent the server uses to call IndyKite APIs at runtime is resolved **server-side** from the MCP server configuration's `app_agent_id` - clients no longer send an `X-IK-ClientKey` AppAgent token. See [`references/architecture.md`](references/architecture.md) for the rationale (the Bearer token identifies the user as the AuthZEN subject).

### 2. Probe the server with `server/discover` (optional but recommended)

The stateless protocol adds a `server/discover` method that returns the server's capabilities and the protocol revisions it accepts - use it to confirm the endpoint speaks `2026-07-28` before anything else:

```bash
curl -s -i -X POST "$MCP_URL/mcp/v1/$PROJECT_GID" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Authorization: Bearer $BEARER_TOKEN" \
  -H "Mcp-Protocol-Version: 2026-07-28" \
  -H "Mcp-Method: server/discover" \
  -d '{
        "jsonrpc": "2.0",
        "id": 1,
        "method": "server/discover",
        "params": {
          "_meta": {
            "io.modelcontextprotocol/protocolVersion": "2026-07-28",
            "io.modelcontextprotocol/clientCapabilities": {},
            "io.modelcontextprotocol/clientInfo": {"name": "curl", "version": "1.0"}
          }
        }
      }'
```

The response is `200` with `result.supportedVersions` (e.g. `["2026-07-28", "2024-11-05", …]`), `result.capabilities`, and the server's instructions - and no `Mcp-Session-Id` header. Or run `scripts/mcp-call.sh server/discover`.

### 3. Discover tools and resources

Before calling tools, ask the server what's available. Three useful methods (each a self-contained POST with the same `_meta` and headers, changing `Mcp-Method`):

- `tools/list` - what tools the agent may call (the canonical set is in [`references/tools.md`](references/tools.md), but list it to verify what *this* deployment exposes).
- `resources/list` - what resources the MCP server exposes.
- `resources/read` with `uri: "indykite://knowledge-queries/"` (also sent as the `Mcp-Name` header) - agent-friendly descriptions of every CIQ Knowledge Query, including the parameters each one expects.

The third one is especially important before any `ciq_execute` call: it tells the agent *which* `id` to pass and *what* `input_params` shape the query expects.

```bash
scripts/mcp-call.sh tools/list
scripts/mcp-call.sh resources/read 'indykite://knowledge-queries/'
```

### 4. Call AuthZEN tools

For authorization decisions, pick the right tool for the question:

| Question                                                                | Tool                       |
|-------------------------------------------------------------------------|----------------------------|
| "Can subject X do action Y on resource Z?"                              | `authzen_evaluate`         |
| "Run several of those checks at once"                                   | `authzen_evaluations`      |
| "Which resources of type T can subject X do Y on?"                      | `authzen_search_resource`  |
| "Which actions can subject X do on resource Z?"                         | `authzen_search_action`    |

Each tool is invoked through the MCP `tools/call` method with `name` and `arguments` in `params` next to `_meta`, plus the `Mcp-Method: tools/call` and `Mcp-Name: <tool name>` headers. Schemas and one-call examples are in [`references/tools.md`](references/tools.md). One non-obvious convention: when the subject is the authenticated caller, `subject_id` is the **`sub` claim of the Bearer token**, not a separately-supplied user identifier.

```bash
scripts/mcp-call.sh tools/call authzen_evaluate \
  '{"subject_type":"Person","subject_id":"alice","resource_type":"Car","resource_id":"cadillacv16","action_name":"CAN_DRIVE"}'
```

### 5. Call CIQ tools

`ciq_execute` runs a Knowledge Query against the IndyKite Graph (read or write). Two arguments:

- `id` - GID **or** name of the Knowledge Query to run.
- `input_params` - the partial parameters from the Knowledge Query **and its policy**; the exact set is documented in the query's description.

Always discover queries first via `resources/read` on `indykite://knowledge-queries/` so the agent passes the right parameters.

### 6. Read, interpret, and audit responses

Responses may arrive either as plain JSON or as an **SSE stream** (that is what the `Accept: application/json, text/event-stream` header allows) - in the SSE case the JSON-RPC message is in the `data:` line of the event. The JSON-RPC response echoes the request's `id`, with `result` on success or `error` on failure. For AuthZEN, the meaningful payload is a `text` content item in `result.content` whose body holds the JSON decision; for CIQ, it is the rows the query returned. Service-side errors (configuration broken, scopes missing) usually surface as JSON-RPC `error` objects; a protocol revision the server does not support returns `400` with error code `-32022` naming the `requested` and `supported` versions; transport problems (auth, connectivity) come back as HTTP `4xx`/`5xx` *before* JSON-RPC even runs - see [`references/troubleshooting.md`](references/troubleshooting.md).

## Legacy session-based clients

Protocol revisions **before** `2026-07-28` (e.g. `2025-11-25`) use a session handshake: `initialize` → capture the `Mcp-Session-Id` response header → `notifications/initialized` → send the header on every call. Both styles authenticate the same way and expose the same tools and resources; only use the legacy style when the client library cannot send the `_meta`-based requests. The lifecycle and rules are in [`references/architecture.md`](references/architecture.md).

## Outcome

When this skill has been applied successfully:

- An MCP server configuration exists for the project (with `app_agent_id` set) and `enabled` is `true`.
- The agent has `BEARER_TOKEN` (user OAuth access token) in scope and sends it as the sole `Authorization: Bearer` auth header.
- `server/discover` returns `2026-07-28` among `result.supportedVersions`, and no `Mcp-Session-Id` header appears on any response.
- `tools/list` and `resources/read` on `indykite://knowledge-queries/` enumerate what the agent can call.
- AuthZEN decisions and CIQ query results come back over JSON-RPC and the agent uses them in its workflow.

## Files in this skill

- [`references/architecture.md`](references/architecture.md) - protocol styles (stateless `2026-07-28` vs legacy sessions), single Bearer-token auth with server-side AppAgent resolution, RFC 9728 `401` behavior.
- [`references/configuration.md`](references/configuration.md) - `POST /configs/v1/mcp-servers` field reference and example payload.
- [`references/tools.md`](references/tools.md) - schemas and examples for every AuthZEN and CIQ tool.
- [`references/troubleshooting.md`](references/troubleshooting.md) - symptom-to-cause map.
- [`scripts/mcp-call.sh`](scripts/mcp-call.sh) - Bash helper that makes one stateless MCP call (builds the `_meta` object and MCP headers for any method). Requires `MCP_URL`, `PROJECT_GID`, `BEARER_TOKEN` in the environment, and `curl` on `PATH`.

## Agent-specific notes

This skill uses generic markdown instructions and works across all agents listed in the [README](../README.md). It assumes the agent can issue HTTP requests (Bash + `curl`, an HTTP MCP client, or an SDK such as the [MCP Go SDK](https://github.com/modelcontextprotocol/go-sdk)). No Claude Code hooks, Cursor `@`-mentions, or Copilot workspace context are required.

## References

- [How to use the MCP server (IndyKite developer hub)](https://developer.indykite.com/guides/guide-mcp)
- [Model Context Protocol specification](https://modelcontextprotocol.io/)
- [MCP Go SDK](https://github.com/modelcontextprotocol/go-sdk)
- [`POST /mcp-servers` API reference](https://openapi.indykite.com/api-documentation-config/#tag/mcp-servers/POST/mcp-servers)
- [`POST /token-introspects` API reference](https://openapi.indykite.com/api-documentation-config#POST/token-introspects)
- [`POST /application-agent-credentials` API reference](https://openapi.indykite.com/api-documentation-config#POST/application-agent-credentials)
- [RFC 9728 - Protected Resource Metadata](https://datatracker.ietf.org/doc/html/rfc9728)

---
name: indykite-mcp-server
description: Call the IndyKite MCP server to make AuthZEN authorization decisions and execute ContX IQ Knowledge Queries. Use when initializing an MCP session, calling its tools, configuring an MCP server, or debugging its two-layer auth.
license: Apache-2.0
compatibility: Requires curl and bash 4+. Network access to eu.mcp.indykite.com or us.mcp.indykite.com, plus the OAuth IdP that issues Bearer tokens, is required at runtime.
---

# IndyKite MCP Server

The **IndyKite MCP server** exposes IndyKite's authorization (AuthZEN/KBAC) and graph-data (ContX IQ) capabilities to AI agents through the [Model Context Protocol](https://modelcontextprotocol.io/). It speaks **JSON-RPC over HTTP POST** and uses the standard MCP session model (`initialize` → `Mcp-Session-Id` → subsequent calls).

Two regional endpoints exist:

- **EU**: `https://eu.mcp.indykite.com`
- **US**: `https://us.mcp.indykite.com`

The full URL for one project is `<MCP_REGIONAL_URL>/mcp/v1/<project_gid>`.

## When to use

Activate this skill when the user:

- needs to **call** the IndyKite MCP server (initialize a session, list tools/resources, or call AuthZEN/CIQ tools);
- is **configuring** an MCP server for a project (`POST /configs/v1/mcp-servers`) and needs the field set;
- is debugging a **`401`** that returned `.well-known/oauth-protected-resource` metadata — almost always a missing or invalid `Authorization: Bearer` token;
- is wiring an LLM client (Claude Code, Cursor, Goose, the [MCP Go SDK](https://github.com/modelcontextprotocol/go-sdk), etc.) into the IndyKite MCP and needs the request shape;
- is choosing between `authzen_evaluate`, `authzen_evaluations`, `authzen_search_resource`, `authzen_search_action`, and `ciq_execute`.

Do **not** activate this skill when the user:

- is asking about the IndyKite Agent Gateway (use the [`indykite-agent-gateway`](../indykite-agent-gateway/SKILL.md) skill — IAG protects A2A agents, not MCP);
- is calling AuthZEN or ContX IQ over their **direct REST APIs** (no MCP session involved) — different endpoints, different auth shape;
- is asking about the MCP **specification itself** rather than the IndyKite implementation.

## Prerequisites

The MCP server will reject requests for a project until all of the following exist:

- An IndyKite **project** with an **Application**, **AppAgent**, and AppAgent **credentials** (the AppAgent token is what goes into `X-IK-ClientKey`).
- A **Token Introspect** configuration on the project — used to validate inbound user Bearer tokens.
- An **MCP server configuration** (`POST /configs/v1/mcp-servers`) that binds the runtime endpoint to the AppAgent and Token Introspect, and declares `scopes_supported`. Without this configuration, requests for the project are rejected. See [`references/configuration.md`](references/configuration.md).
- The project's **GID** (used in the URL path).
- Captured **data and policies**: KBAC and/or CIQ policies and Knowledge Queries, depending on which tools the agent will call.

If any of these are missing, stop and tell the user — fixing them first is much cheaper than debugging an opaque MCP rejection.

## Steps

### 1. Resolve the URL and credentials

Build the full MCP URL: `<MCP_URL>/mcp/v1/<project_gid>` where `<MCP_URL>` is `https://eu.mcp.indykite.com` or `https://us.mcp.indykite.com`. Get two values into shell variables:

```bash
export API_KEY="<AppAgent-credentials-token>"     # → X-IK-ClientKey
export BEARER_TOKEN="<user-OAuth-access-token>"   # → Authorization: Bearer
export MCP_URL="https://us.mcp.indykite.com"
export PROJECT_GID="<your-project-gid>"
```

Both layers are required on every call after `initialize`. See [`references/architecture.md`](references/architecture.md) for the rationale (one identifies the application, the other identifies the user as the AuthZEN subject).

### 2. Initialize the session

Send an `initialize` request and capture the `Mcp-Session-Id` response header. This is the only call that does not need a session id, but it does need both auth headers.

```bash
curl -s -i -X POST "$MCP_URL/mcp/v1/$PROJECT_GID" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $BEARER_TOKEN" \
  -H "X-IK-ClientKey: $API_KEY" \
  -d '{
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
          "protocolVersion": "2025-11-25",
          "capabilities": {},
          "clientInfo": {"name": "curl", "version": "1.0"}
        }
      }'
```

Save the `Mcp-Session-Id` header value into `SESSION_ID`. The helper `scripts/init-session.sh` does exactly this and prints the session id on stdout.

### 3. Confirm initialization

Send the `notifications/initialized` JSON-RPC notification with the session id. This signals the server that the client is ready to issue tool/resource calls.

```bash
curl -s -X POST "$MCP_URL/mcp/v1/$PROJECT_GID" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $BEARER_TOKEN" \
  -H "X-IK-ClientKey: $API_KEY" \
  -H "Mcp-Session-Id: $SESSION_ID" \
  -d '{
        "jsonrpc": "2.0",
        "id": 2,
        "method": "notifications/initialized",
        "params": {
          "protocolVersion": "2025-11-25",
          "capabilities": {},
          "clientInfo": {"name": "curl", "version": "1.0"}
        }
      }'
```

### 4. Discover tools and resources (optional but recommended)

Before calling tools, ask the server what's available. Three useful methods:

- `resources/list` — what resources the MCP server exposes.
- `tools/list` — what tools the agent may call (the canonical set is in [`references/tools.md`](references/tools.md), but list it to verify what *this* deployment exposes).
- `resources/read` with `uri: "indykite://knowledge-queries/"` — agent-friendly descriptions of every CIQ Knowledge Query, including the parameters each one expects.

The third one is especially important before any `ciq_execute` call: it tells the agent *which* `id` to pass and *what* `input_params` shape the query expects.

### 5. Call AuthZEN tools

For authorization decisions, pick the right tool for the question:

| Question                                                                | Tool                       |
|-------------------------------------------------------------------------|----------------------------|
| "Can subject X do action Y on resource Z?"                              | `authzen_evaluate`         |
| "Run several of those checks at once"                                   | `authzen_evaluations`      |
| "Which resources of type T can subject X do Y on?"                      | `authzen_search_resource`  |
| "Which actions can subject X do on resource Z?"                         | `authzen_search_action`    |

Each tool is invoked through the MCP `tools/call` method with `name` and `arguments`. Schemas and one-call examples are in [`references/tools.md`](references/tools.md). One non-obvious convention: when the subject is the authenticated caller, `subject_id` is the **`sub` claim of the Bearer token**, not a separately-supplied user identifier.

### 6. Call CIQ tools

`ciq_execute` runs a Knowledge Query against the IndyKite Graph (read or write). Two arguments:

- `id` — GID **or** name of the Knowledge Query to run.
- `input_params` — key/value map matching the query's partial filter variables.

Always discover queries first via `resources/read` on `indykite://knowledge-queries/` so the agent passes the right parameters.

### 7. Read, interpret, and audit responses

JSON-RPC responses come back with `id` matching the request, `result` on success, or `error` on failure. For AuthZEN, the meaningful payload is the decision plus any reason; for CIQ, it is the rows the query returned. Service-side errors (configuration broken, scopes missing) usually surface as JSON-RPC `error` objects, while transport problems (auth, connectivity) come back as HTTP `4xx`/`5xx` *before* JSON-RPC even runs — see [`references/troubleshooting.md`](references/troubleshooting.md).

## Outcome

When this skill has been applied successfully:

- An MCP server configuration exists for the project and `enabled` is `true`.
- The agent has `API_KEY` (AppAgent token) and `BEARER_TOKEN` (user OAuth access token) in scope, and knows which goes in which header.
- An `initialize` call returns a usable `Mcp-Session-Id`.
- `tools/list` and `resources/read` on `indykite://knowledge-queries/` enumerate what the agent can call.
- AuthZEN decisions and CIQ query results come back over JSON-RPC and the agent uses them in its workflow.

## Files in this skill

- [`references/architecture.md`](references/architecture.md) — protocol and session model, two-layer auth, RFC 9728 `401` behavior.
- [`references/configuration.md`](references/configuration.md) — `POST /configs/v1/mcp-servers` field reference and example payload.
- [`references/tools.md`](references/tools.md) — schemas and examples for every AuthZEN and CIQ tool.
- [`references/troubleshooting.md`](references/troubleshooting.md) — symptom-to-cause map.
- [`scripts/init-session.sh`](scripts/init-session.sh) — Bash helper that initializes a session and prints the resulting `Mcp-Session-Id`. Requires `MCP_URL`, `PROJECT_GID`, `API_KEY`, `BEARER_TOKEN` in the environment, and `curl` + `awk` on `PATH`.

## Agent-specific notes

This skill uses generic markdown instructions and works across all agents listed in the [README](../README.md). It assumes the agent can issue HTTP requests (Bash + `curl`, an HTTP MCP client, or an SDK such as the [MCP Go SDK](https://github.com/modelcontextprotocol/go-sdk)). No Claude Code hooks, Cursor `@`-mentions, or Copilot workspace context are required.

## References

- [How to use the MCP server (IndyKite developer hub)](https://developer.indykite.com/guides/guide-mcp)
- [Model Context Protocol specification](https://modelcontextprotocol.io/)
- [MCP Go SDK](https://github.com/modelcontextprotocol/go-sdk)
- [`POST /mcp-servers` API reference](https://openapi.indykite.com/api-documentation-config/#tag/mcp-servers/POST/mcp-servers)
- [`POST /token-introspects` API reference](https://openapi.indykite.com/api-documentation-config#POST/token-introspects)
- [`POST /application-agent-credentials` API reference](https://openapi.indykite.com/api-documentation-config#POST/application-agent-credentials)
- [RFC 9728 — Protected Resource Metadata](https://datatracker.ietf.org/doc/html/rfc9728)

# IndyKite MCP — Architecture and Session Model

This file is loaded by agents that need to reason about *how* the MCP server processes a request, not *what* tools it exposes (that lives in `tools.md`).

## URL shape and regions

```text
<MCP_URL>/mcp/v1/<project_gid>
```

| Region | `<MCP_URL>`                          |
|--------|--------------------------------------|
| EU     | `https://eu.mcp.indykite.com`        |
| US     | `https://us.mcp.indykite.com`        |

`<project_gid>` is the IndyKite project identifier. The same MCP server instance can serve many projects; the path segment selects which one.

## Two-layer authorization

Every request after `initialize` carries **two** auth headers, answering two different questions:

| Header                          | Question                                             | Source                                              |
|---------------------------------|------------------------------------------------------|-----------------------------------------------------|
| `X-IK-ClientKey`                | "Can this **application** call the IndyKite APIs?"    | AppAgent credentials token (Authorization API + ContX IQ API permissions). |
| `Authorization: Bearer <token>` | "Who is the **user** making the request?"            | OAuth 2.0 access token from the project's IdP, validated through the configured Token Introspect. |

The Bearer token's `sub` claim becomes the **subject** in AuthZEN evaluations. That is why most AuthZEN tool invocations expect `subject_id` to be set to the Bearer token's `sub` rather than a separately-tracked identifier.

Recommendation: keep the AppAgent token's validity short and refresh it programmatically — both for blast-radius reasons and because rotation is the only reliable way to evict cached credentials.

## What happens without a Bearer token

If `Authorization` is missing or invalid, the server returns:

- HTTP **`401 Unauthorized`**, and
- the **`.well-known/oauth-protected-resource`** metadata document defined by [RFC 9728](https://datatracker.ietf.org/doc/html/rfc9728).

This metadata advertises which identity providers and scopes the resource expects. **The list is configured per project** — contact IndyKite to register your IdPs and scopes; otherwise the metadata returned will not point clients at the right authorization server. The `scopes_supported` field in your MCP server configuration is what the metadata mirrors.

## JSON-RPC over HTTP POST

The MCP server speaks JSON-RPC 2.0 (`{ "jsonrpc": "2.0", "id": …, "method": …, "params": … }`) over HTTP `POST`. The shape applies to both methods and notifications. Every response includes either `result` or `error` and echoes the request's `id`.

The MCP server is built on the official [MCP Go SDK](https://github.com/modelcontextprotocol/go-sdk), so any conforming MCP client — the SDK itself, Claude Code, Cursor, Goose, etc. — can talk to it without raw `curl`.

## Session lifecycle

```text
client ──┐
         │  POST  initialize         (no Mcp-Session-Id; both auth headers required)
         ▼
   MCP server  ─── returns Mcp-Session-Id header
         ▲
         │  POST  notifications/initialized   (Mcp-Session-Id required from now on)
         │  POST  tools/list                  (Mcp-Session-Id required)
         │  POST  resources/list              (Mcp-Session-Id required)
         │  POST  resources/read              (Mcp-Session-Id required)
         │  POST  tools/call name=…           (Mcp-Session-Id required)
         │  …
client ──┘
```

Three rules:

1. **`initialize`** is the only method that can run without a session id. It still requires both auth headers.
2. The server returns `Mcp-Session-Id` as a **response header** on the `initialize` reply; capture it before reading the JSON body.
3. **All subsequent calls** must include `Mcp-Session-Id: <captured value>`. A request that omits it after `initialize` will be rejected.

There is no documented session expiration model; treat sessions as short-lived (one task, one process). If the server returns an authentication error mid-session, re-initialize.

## Process flow

The published process diagram (`mcp-process1.png`, `mcp-process2.png` on the developer hub) shows the same lifecycle in graphical form. The textual version above is sufficient for an agent to drive the protocol.

## Discovery resources

Two MCP resources are worth knowing about specifically:

| Resource URI                            | Returns                                                                                  |
|-----------------------------------------|------------------------------------------------------------------------------------------|
| (default) `resources/list`              | All resources this server exposes.                                                        |
| `indykite://knowledge-queries/`         | A list of CIQ Knowledge Query IDs and **agent-friendly descriptions** of how to call `ciq_execute` against each one — including the input-parameter shape. Read this *before* any `ciq_execute`. |

## Why this matters for the agent

- **Auth confusion is the #1 setup failure.** If you only send a Bearer token, you authenticate the user but not the application; if you only send `X-IK-ClientKey`, you authenticate the application but the AuthZEN subject resolution has nothing to work with. Both are required.
- **`subject_id` is rarely an opaque identifier the user typed.** It is the Bearer token's `sub` claim. Reading and forwarding it correctly is what makes AuthZEN decisions match the real caller.
- **CIQ parameter shapes are not guessable.** The `indykite://knowledge-queries/` resource exists because Knowledge Queries are project-defined; without reading it first, `ciq_execute` calls usually fail on the first attempt.

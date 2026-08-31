# IndyKite MCP — Tool Reference

Five tools are exposed by the MCP server. All are invoked through the JSON-RPC `tools/call` method. On the stateless protocol (revision `2026-07-28`, the style this skill uses) the full envelope is:

```json
{
  "jsonrpc": "2.0",
  "id": <int>,
  "method": "tools/call",
  "params": {
    "name": "<tool_name>",
    "arguments": { … },
    "_meta": {
      "io.modelcontextprotocol/protocolVersion": "2026-07-28",
      "io.modelcontextprotocol/clientCapabilities": {},
      "io.modelcontextprotocol/clientInfo": {"name": "curl", "version": "1.0"}
    }
  }
}
```

Every example below assumes these headers are set on the HTTP request:

```text
Content-Type: application/json
Accept: application/json, text/event-stream
Authorization: Bearer $BEARER_TOKEN
Mcp-Protocol-Version: 2026-07-28
Mcp-Method: tools/call
Mcp-Name: <tool_name>
```

`Mcp-Method` and `Mcp-Name` must match the body's `method` and `params.name`. The HTTP method is `POST` and the URL is `$MCP_URL/mcp/v1/$PROJECT_GID`. For brevity the per-tool examples below show only `name` and `arguments` — always add the `_meta` object from the envelope above to `params`. The helper `scripts/mcp-call.sh tools/call <tool_name> '<arguments-json>'` does all of this. (Legacy session-based clients — revisions before `2026-07-28` — instead omit `_meta` and the `Mcp-*` headers and send `Mcp-Session-Id: $SESSION_ID`; see `architecture.md`.)

## AuthZEN tools

These tools make authorization decisions backed by the project's KBAC policies.

### `authzen_evaluate` — single check

> Can subject X perform action A on resource R?

```json
{
  "jsonrpc": "2.0",
  "id": 5,
  "method": "tools/call",
  "params": {
    "name": "authzen_evaluate",
    "arguments": {
      "subject_type": "Person",
      "subject_id": "alice",
      "resource_type": "Car",
      "resource_id": "cadillacv16",
      "action_name": "CAN_DRIVE"
    }
  }
}
```

`subject_id` should be the Bearer token's `sub` claim when the subject is the authenticated caller.

### `authzen_evaluations` — batch check

> Run several `authzen_evaluate`-style checks in one call.

```json
{
  "jsonrpc": "2.0",
  "id": 6,
  "method": "tools/call",
  "params": {
    "name": "authzen_evaluations",
    "arguments": {
      "subject_type": "user",
      "subject_id": "user-123",
      "evaluations": [
        {"action": {"name": "read"},  "resource": {"type": "doc", "id": "doc1"}},
        {"action": {"name": "write"}, "resource": {"type": "doc", "id": "doc2"}}
      ]
    }
  }
}
```

The subject is shared across all evaluations in the batch; each entry varies the `action` and `resource`. Use this when the agent needs the policy outcome for several resources at once and would otherwise make N round trips.

### `authzen_search_resource` — find accessible resources

> Which resources of type R can subject X do A on?

```json
{
  "jsonrpc": "2.0",
  "id": 7,
  "method": "tools/call",
  "params": {
    "name": "authzen_search_resource",
    "arguments": {
      "subject_type": "User",
      "subject_id": "user-123",
      "action_name": "READ",
      "resource_type": "Document"
    }
  }
}
```

Returns the list of resource IDs of `resource_type` that the subject is allowed to perform `action_name` on. Useful for "what does this user have access to?" UIs and for narrowing graph traversals before a CIQ query.

### `authzen_search_action` — find permitted actions

> Which actions can subject X perform on resource R?

```json
{
  "jsonrpc": "2.0",
  "id": 8,
  "method": "tools/call",
  "params": {
    "name": "authzen_search_action",
    "arguments": {
      "subject_type": "User",
      "subject_id": "user-123",
      "resource_type": "Document",
      "resource_id": "doc-456"
    }
  }
}
```

Useful for permissions inspectors and "show me everything I'm allowed to do here" interfaces.

### Choosing between the four AuthZEN tools

| If the agent needs…                                                | Tool                       |
|--------------------------------------------------------------------|----------------------------|
| One yes/no decision                                                | `authzen_evaluate`         |
| Several yes/no decisions for the same subject                      | `authzen_evaluations`      |
| The full set of resources of one type the subject can act on       | `authzen_search_resource`  |
| The full set of actions the subject can take on one resource       | `authzen_search_action`    |

## CIQ tools

### `ciq_execute` — run a Knowledge Query

> Execute a Knowledge Query (read or write) against the IndyKite Graph.

```json
{
  "jsonrpc": "2.0",
  "id": 9,
  "method": "tools/call",
  "params": {
    "name": "ciq_execute",
    "arguments": {
      "id": "<knowledge_query_id_or_name>",
      "input_params": {
        "license": "AL98745",
        "app_external_id": "applicationParking"
      }
    }
  }
}
```

| Argument        | Description                                                                       |
|-----------------|-----------------------------------------------------------------------------------|
| `id`            | The GID **or** name of the Knowledge Query to execute.                            |
| `input_params`  | The partial parameters from the Knowledge Query **and its policy**. The exact set for each query is documented in that query's description — discover it via `resources/read indykite://knowledge-queries/`. |

**Always discover the query before calling it**. The MCP server exposes (headers: `Mcp-Method: resources/read`, `Mcp-Name: indykite://knowledge-queries/`):

```http
POST /mcp/v1/<project_gid>
{
  "jsonrpc": "2.0",
  "id": 4,
  "method": "resources/read",
  "params": {
    "uri": "indykite://knowledge-queries/",
    "_meta": {
      "io.modelcontextprotocol/protocolVersion": "2026-07-28",
      "io.modelcontextprotocol/clientCapabilities": {}
    }
  }
}
```

The response lists every Knowledge Query with an agent-friendly description and the parameter shape `ciq_execute` expects. Reading this first turns the otherwise-guesswork `input_params` into a deterministic call.

## Discovery methods (not tools, but commonly chained with them)

| JSON-RPC method     | Purpose                                                                  |
|---------------------|--------------------------------------------------------------------------|
| `server/discover`   | Stateless-only: the server's capabilities and supported protocol revisions (`result.supportedVersions`). |
| `resources/list`    | Enumerate the resources this MCP server exposes.                         |
| `tools/list`        | Enumerate the tools this MCP server exposes (canonically the five above, but verify per deployment). |
| `resources/read`    | Read a specific resource — most importantly `indykite://knowledge-queries/` (its URI also goes in the `Mcp-Name` header). |

Each is a plain JSON-RPC method: set `Mcp-Method` to the method name and put the `_meta` object in `params` (for `server/discover`, `tools/list`, and `resources/list`, `_meta` is the only `params` content).

# IndyKite MCP — Server Configuration

Before the MCP runtime endpoint will accept requests for a project, an **MCP server configuration** must exist for that project. This config binds the runtime endpoint to an AppAgent and a Token Introspect, declares the OAuth `scopes_supported`, and gates whether the server is `enabled`.

## Endpoint

```text
POST <API_URL>/configs/v1/mcp-servers
```

Authenticate with a service-account token (`Authorization: Bearer $SERVICE_ACCOUNT_TOKEN`).

API reference: <https://openapi.indykite.com/api-documentation-config/#tag/mcp-servers/POST/mcp-servers>

## Required fields

| Field                | Type           | Notes                                                                                              |
|----------------------|----------------|----------------------------------------------------------------------------------------------------|
| `name`               | string         | URL-friendly identifier, unique within the project. **Immutable** after creation.                  |
| `project_id`         | string (GID)   | Project that owns this MCP server configuration.                                                   |
| `app_agent_id`       | string (GID)   | AppAgent the MCP server uses to call IndyKite APIs at runtime (becomes `X-IK-ClientKey`).          |
| `token_introspect_id`| string (GID)   | Token Introspect configuration used to validate inbound user Bearer tokens.                        |
| `enabled`            | boolean        | Whether the MCP server accepts requests for this configuration.                                    |
| `scopes_supported`   | string[]       | OAuth scopes advertised in `.well-known/oauth-protected-resource`. Must contain at least one entry. |

## Optional fields

- `display_name` — string, 2–254 chars. Human-readable name.
- `description` — string, 2–65000 chars. Free-text description.

## Example payload

```bash
curl -X POST "$API_URL/configs/v1/mcp-servers" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $SERVICE_ACCOUNT_TOKEN" \
  -d '{
        "name": "mcp-server-name",
        "display_name": "MCP Server name",
        "description": "MCP Server configuration description",
        "project_id": "gid-of-project",
        "app_agent_id": "gid-of-app-agent",
        "token_introspect_id": "gid-of-token-introspect",
        "enabled": true,
        "scopes_supported": ["name", "email"]
      }'
```

**`201 Created`** returns the new configuration's `id` (GID), `create_time`, `created_by`, and `update_time`.

## Field interactions worth knowing

- **`scopes_supported` mirrors into `.well-known/oauth-protected-resource`.** An MCP client that sees a `401` and parses the metadata only sees the scopes you list here. If you forget a scope, clients will request the wrong set.
- **Adding new IdPs to the metadata is a separate IndyKite-side action** — the IndyKite team must register your IdPs against the project so they appear in the `.well-known` document. `scopes_supported` does not control IdP listing.
- **`enabled: false`** is the supported way to take an MCP server offline without deleting the configuration. Useful while rotating credentials or migrating between AppAgents.
- **`name` is immutable.** Choose carefully; renaming requires creating a new configuration.

## Related setup

- **AppAgent credentials**: `POST /application-agent-credentials` — required to obtain the token that goes into `X-IK-ClientKey`. Use a short validity period.
- **Token introspection**: `POST /token-introspects` — required so the MCP server can validate inbound Bearer tokens against the project's IdP.
- **Environment setup walkthrough**: <https://developer.indykite.com/resources/environment-1>

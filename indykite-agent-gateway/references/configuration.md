# IAG Configuration Reference

IAG accepts either a YAML config file (`--config=/app/config.yaml`) or a set of environment variables. Keys are identical between the two forms - YAML uses dots (`service.name`), env vars use the `JARVIS_` prefix with underscores (`JARVIS_SERVICE_NAME`, `JARVIS_TOKEN_SERVICE_CLIENT_AUTH_CLIENT_ID`).

The iag-mcp-demo uses the env-var form so a single shared base service (`iag-base-docker.yaml`) can be reused across its IAG instances. Production deployments often prefer the YAML form for stricter configuration management.

## Sections

| Section             | Purpose                                                                                                |
|---------------------|--------------------------------------------------------------------------------------------------------|
| `service`           | Runtime: `name`, `port`, `environment`, `log_level`, `healthcheck_port`.                               |
| `identity_provider` | IdP `base_url` and endpoints (`introspect_endpoint`, `client_credential_endpoint`, `exchange_endpoint`). Always required. |
| `token_service`     | Optional. The self-hosted IndyKite Token Service that mints the delegation token instead of the IdP: `base_url`, `exchange_endpoint`, `introspect_endpoint`, `client_auth.{type,client_id,client_secret}`. |
| `protected_agent`   | Target `base_url`, downstream `protocol` (`a2a` default, or `mcp`), client credentials (`authentication.type=credentials`, `authentication.client_id`, `authentication.client_secret`), and with the Token Service the `authentication.audiences` to request. |
| `authzen`           | `base_url`, `action` (typically `CAN_TRIGGER`), `subject_types`, cache tuning.                        |
| `contx_iq`          | `base_url`, `query_id`, `app_agent_credentials_token`, optional `allowed_workflow_id`, cache tuning.   |
| `audit`             | Optional. `delivery: webhook` (`http.url`, `http.method`, `http.auth`) or `delivery: file` (`file.storage_path`, `file.format`, `file.rotation_strategy`), plus optional `async.buffer_size`. |

## Service

- `name` (required) - unique service name; appears as `service` in audit records.
- `port` (required) - TCP port the gateway listens on; the sample configurations use `8888`.
- `environment` (optional) - `prod`, `stg`, `rc`, `dev`, `local`, `testing`.
- `log_level` (optional) - `debug`, `info`, `warn`, `error`; defaults to `info`.
- `healthcheck_port` (optional) - port of the `/healthz`, `/readyz`, and `/startupz` endpoints. Defaults to `9080`, which the container image's `HEALTHCHECK` probes (`http://localhost:9080/healthz`); change it only together with that probe, e.g. when several gateway instances share one network namespace.

## Token Service (`token_service`)

The whole section is optional, and whether it is filled in decides how the gateway obtains and forwards the delegation token:

- **Left out** - the identity provider exchanges the tokens (RFC 8693) and its delegation token **replaces** the subject's token in the `Authorization` header. A KBAC policy reaches the delegation chain as `$token`. An incoming `X-IK-Token` header is ignored - there is nothing to validate it against.
- **Filled in** - the Token Service mints the delegation token instead. The subject's own access token travels **untouched** in `Authorization` and the delegation token beside it in **`X-IK-Token`**, which a policy reaches as `$ik_token`. A request that arrives with an `X-IK-Token` of its own is on a later hop of a workflow: that token is validated at the Token Service and becomes the subject of the exchange, so the chain it carries is nested in the token minted for the next hop.

The policy and this configuration have to agree: a reference to a token that was not sent resolves to nothing, and the decision is a denial.

| Field                       | Required | Notes                                                                                                   |
|-----------------------------|----------|---------------------------------------------------------------------------------------------------------|
| `base_url`                  | yes      | Token Service location, e.g. `https://token-service.example.com`.                                       |
| `exchange_endpoint`         | yes      | `/oauth2/token`.                                                                                        |
| `introspect_endpoint`       | yes      | `/oauth2/introspect`.                                                                                   |
| `client_auth.type`          | yes      | IANA token endpoint authentication method; only `client_secret_basic` is implemented.                    |
| `client_auth.client_id`     | yes      | What the Token Service knows the gateway as - must match the service's `idp.client_auth.client_id`.     |
| `client_auth.client_secret` | yes      | The matching secret.                                                                                    |

Env-var form: `JARVIS_TOKEN_SERVICE_BASE_URL`, `JARVIS_TOKEN_SERVICE_EXCHANGE_ENDPOINT`, `JARVIS_TOKEN_SERVICE_INTROSPECT_ENDPOINT`, `JARVIS_TOKEN_SERVICE_CLIENT_AUTH_TYPE`, `JARVIS_TOKEN_SERVICE_CLIENT_AUTH_CLIENT_ID`, `JARVIS_TOKEN_SERVICE_CLIENT_AUTH_CLIENT_SECRET`.

The `client_auth` credentials are the ones the Token Service expects on its token and introspection endpoints (its own `idp.client_auth`), **not** the identity provider credentials under `protected_agent`. The identity provider stays required either way - the Token Service neither introspects the subject's access token nor authenticates the protected agent; it exchanges tokens and validates the ones it issued itself.

The audiences the gateway requests come from `protected_agent.authentication.audiences`, and every one of them must be listed in the Token Service's `idp.audiences`, otherwise the exchange is refused with `invalid_target`. Startup fails with `missing base_url` / `missing exchange_endpoint` / `missing introspect_endpoint` / `client_auth has invalid type` when the section is present but incomplete.

## Protected agent

- `base_url` (required) - where requests are forwarded. In `mcp` mode the MCP server origin only.
- `protocol` (optional) - `a2a` (default) or `mcp`; anything else fails startup with *invalid protected_agent protocol*.
- `authentication.type` (required) - only `credentials` is supported.
- `authentication.client_id` / `authentication.client_secret` (required) - the IdP client of the protected agent, used for the client-credentials grant (the actor token).
- `authentication.audiences` (optional list) - audiences requested on the token exchange, for the IdP and for the Token Service. With the Token Service each value must be in its `idp.audiences`. Typically the audience of the protected agent (`agent.retriever`) or of the protected MCP server (`api.mcp`).

## Defaults and validation rules worth knowing

- `protected_agent.protocol` defaults to `a2a`; set it to `mcp` to put IAG in front of an MCP server. As an env var this is `JARVIS_PROTECTED_AGENT_PROTOCOL`.
- Cache tuning on `authzen` and `contx_iq`: `cache_ttl` defaults to `5m`; `cache_update_after` (background refresh interval) defaults to `cache_ttl`; `cache_update_after_error` (retry interval after a failed refresh) defaults to the smaller of `10s` and `cache_update_after`. The gateway refuses to start when any of the three is negative, when `cache_update_after` exceeds `cache_ttl`, or when `cache_update_after_error` exceeds `cache_update_after`. The background refresh runs off the request context, so a client disconnect no longer kills a refresh or poisons the cache for a full TTL.
- Audit file rotation defaults: `rotation_interval=24h`, `rotation_max_bytes=100MiB`.
- Webhook API-key auth defaults `api_key_header` to `X-API-Key`.
- `audit.async.buffer_size` defaults to `512` when `async` is present.

## Per-instance values

Each IAG instance must override these (and only these need to differ in a multi-instance deployment):

- `service.name` / `JARVIS_SERVICE_NAME`
- `service.port` / `JARVIS_SERVICE_PORT`
- `service.healthcheck_port` / `JARVIS_SERVICE_HEALTHCHECK_PORT` (only when instances share a network namespace)
- `protected_agent.base_url` / `JARVIS_PROTECTED_AGENT_BASE_URL`
- `protected_agent.protocol` / `JARVIS_PROTECTED_AGENT_PROTOCOL` (if any instance protects an MCP server)
- `protected_agent.authentication.client_id` / `JARVIS_PROTECTED_AGENT_AUTHENTICATION_CLIENT_ID`
- `protected_agent.authentication.client_secret` / `JARVIS_PROTECTED_AGENT_AUTHENTICATION_CLIENT_SECRET`
- `protected_agent.authentication.audiences` / `JARVIS_PROTECTED_AGENT_AUTHENTICATION_AUDIENCES` (with the Token Service)

Example mapping from iag-mcp-demo:

| IAG instance         | Port    | Protected agent URL          | Client-id env var              |
|----------------------|---------|------------------------------|--------------------------------|
| `orchestrator-iag`   | `8881`  | `http://orchestrator:6001`   | `ORCHESTRATOR_IDP_CLIENT_ID`   |
| `retriever-iag`      | `8882`  | `http://retriever:6002`      | `RETRIEVER_IDP_CLIENT_ID`      |
| `weather-iag`        | `8884`  | `http://weather:6004`        | `WEATHER_IDP_CLIENT_ID`        |

## Env-var form (iag-mcp-demo excerpt)

```yaml
services:
  iag-base:
    image: indykite/agent-gateway:latest
    environment:
      JARVIS_SERVICE_LOG_LEVEL: debug
      JARVIS_SERVICE_ENVIRONMENT: demo
      JARVIS_IDENTITY_PROVIDER_BASE_URL: ${IDP_BASE_URL}
      JARVIS_IDENTITY_PROVIDER_INTROSPECT_ENDPOINT: "oauth-introspect"
      JARVIS_IDENTITY_PROVIDER_CLIENT_CREDENTIAL_ENDPOINT: "oauth-token"
      JARVIS_IDENTITY_PROVIDER_EXCHANGE_ENDPOINT: "oauth-token"
      JARVIS_CONTX_IQ_BASE_URL: ${INDYKITE_BASE_URL}/contx-iq/v1
      JARVIS_CONTX_IQ_QUERY_ID: ${CIQ_QUERY_ID}
      JARVIS_CONTX_IQ_APP_AGENT_CREDENTIALS_TOKEN: ${APP_AGENT_CREDENTIALS_TOKEN}
      JARVIS_CONTX_IQ_ALLOWED_WORKFLOW_ID: ${WORKFLOW_ID}
      JARVIS_AUTHZEN_BASE_URL: ${INDYKITE_BASE_URL}/access/v1
      JARVIS_AUTHZEN_ACTION: CAN_TRIGGER
      JARVIS_AUTHZEN_SUBJECT_TYPES: User
      # Optional: mint the delegation token at a self-hosted Token Service instead of the IdP.
      # JARVIS_TOKEN_SERVICE_BASE_URL: ${TOKEN_SERVICE_BASE_URL}
      # JARVIS_TOKEN_SERVICE_EXCHANGE_ENDPOINT: /oauth2/token
      # JARVIS_TOKEN_SERVICE_INTROSPECT_ENDPOINT: /oauth2/introspect
      # JARVIS_TOKEN_SERVICE_CLIENT_AUTH_TYPE: client_secret_basic
      # JARVIS_TOKEN_SERVICE_CLIENT_AUTH_CLIENT_ID: agent-gateway
      # JARVIS_TOKEN_SERVICE_CLIENT_AUTH_CLIENT_SECRET: ${TOKEN_SERVICE_CLIENT_SECRET}
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

## Audit configuration

The demo uses a webhook pointed at the chatbot, which is why audit decisions show up in the chatbot UI in real time:

```yaml
audit:
  delivery: webhook
  http:
    url: http://chatbot:3000/api/push-update
    method: post
    auth:
      type: no-auth
```

Available `http.auth.type` values: `no-auth`, `api-key` (`api_key`, `api_key_header`), `mTLS` (`mtls_certificate_file_path`, `mtls_private_key_path`). `http.method` is `post` or `put`.

For file-based delivery, set `delivery: file` and provide under `file:`

- `storage_path` - directory IAG writes to.
- `format` - `csv`, `json`, or `txt`.
- `rotation_strategy` - `size`, `time`, or `size-and-time`.
- Optional: `rotation_interval` (default `24h`), `rotation_max_bytes` (default `100MiB`).

Either delivery can be made asynchronous:

```yaml
audit:
  delivery: file
  async:
    buffer_size: 512   # queue shared by all delivery methods; default 512
  file:
    storage_path: /var/log/iag
    format: json
    rotation_strategy: size-and-time
```

Buffered records are drained during shutdown before the sender is closed; when the queue is full a record is dropped and the service log says so.

## Protecting an MCP server (`protocol: mcp`)

Set `protected_agent.protocol: mcp` (or `JARVIS_PROTECTED_AGENT_PROTOCOL: mcp`) to switch the gateway from its default A2A proxy into MCP **Streamable HTTP** proxy mode. The authorization sequence is identical (introspect → token exchange → ContX IQ → AuthZEN `CAN_TRIGGER` → forward); only the forwarded protocol differs. MCP proxying requires `indykite/agent-gateway` **≥ 2.0.1** - older images ignore `protocol` and behave as an A2A proxy.

In MCP mode:

- `protected_agent.base_url` is the MCP server **origin only** (e.g. `https://us.mcp.indykite.com`). IAG appends the incoming request path/query (e.g. `/mcp/v1/<project_gid>`) on top of it.
- The `Mcp-Session-Id` header is forwarded transparently in both directions (no translation).
- SSE response bodies are streamed through without being cut off, so streaming responses are not truncated.
- IAG mints its own token for the downstream MCP server (from `protected_agent.authentication.client_id` / `client_secret`; in `iag-mcp-demo` these are `MCP_IDP_CLIENT_ID` / `_SECRET`) and forwards the request with that delegation token attached - in `Authorization` when the IdP mints it, in `X-IK-Token` next to the caller's access token when the Token Service does.

### iag-mcp-demo env vars (the `mcp-iag` instance)

The `iag-mcp-demo` reference app adds one MCP-mode instance, `mcp-iag` (port `8886`), in front of the IndyKite MCP server. The `retriever` and `weather` agents are MCP clients routed through it instead of calling the MCP server directly.

| Variable | Meaning |
|----------|---------|
| `MCP_SERVER_ORIGIN` | Scheme + host of the MCP server (`https://us.mcp.indykite.com` / `https://eu.mcp.indykite.com`); becomes `JARVIS_PROTECTED_AGENT_BASE_URL` for `mcp-iag`. |
| `MCP_SERVER_PATH` | MCP endpoint path, e.g. `/mcp/v1/<PROJECT_GID_URL_ENCODED>`; appended by the gateway. |
| `MCP_SERVER_URL` | Direct URL (`<ORIGIN><PATH>`). Agents call `http://mcp-iag:8886${MCP_SERVER_PATH}` through the gateway; set this back to the direct URL to bypass `mcp-iag`. |
| `MCP_IDP_CLIENT_ID` / `MCP_IDP_CLIENT_SECRET` | IdP client (e.g. `indykiteagent-mcp`) the gateway uses to authenticate to the MCP server. |

The MCP agents authenticate with an **App Agent token** (`IK_APP_AGENT_KEY`), not the chatbot user token used by the A2A flows. For `mcp-iag` to accept those calls, that token must be introspectable **and** pass the inherited AuthZEN check. If the App Agent is not modeled as a `User` subject, override `JARVIS_AUTHZEN_ACTION` / `JARVIS_AUTHZEN_SUBJECT_TYPES` on `mcp-iag` to match your graph.

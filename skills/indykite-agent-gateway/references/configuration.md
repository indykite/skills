# IAG Configuration Reference

IAG accepts either a YAML config file (`--config=/app/config.yaml`) or a set of environment variables. Keys are identical between the two forms — YAML uses dots (`service.name`), env vars use the `JARVIS_` prefix with underscores (`JARVIS_SERVICE_NAME`).

The iag-demo uses the env-var form so a single shared base service (`iag-base-docker.yaml`) can be reused across three IAG instances. Production deployments often prefer the YAML form for stricter configuration management.

## Sections

| Section             | Purpose                                                                                                |
|---------------------|--------------------------------------------------------------------------------------------------------|
| `service`           | Runtime: `name`, `port`, `environment`, `log_level`.                                                   |
| `identity_provider` | IdP `base_url` and endpoints (`introspect_endpoint`, `client_credential_endpoint`, `exchange_endpoint`). |
| `protected_agent`   | Target agent `base_url` + client credentials (`authentication.client_id`, `authentication.client_secret`, `authentication.type=credentials`). |
| `authzen`           | `base_url`, `action` (typically `CAN_TRIGGER`), `subject_types`, cache tuning.                        |
| `contx_iq`          | `base_url`, `query_id`, `app_agent_credentials_token`, optional `allowed_workflow_id`, cache tuning.   |
| `audit`             | Optional. `delivery: webhook` (`http.url`, `http.method`, `http.auth`) or `delivery: file` (`storage_path`, `format`, `rotation_strategy`). |

## Defaults worth knowing

- `cache_ttl` and `cache_update_after` default to `5m`.
- `cache_update_after_error` defaults to `10s`.
- Audit file rotation defaults: `rotation_interval=24h`, `rotation_max_bytes=100MiB`.
- Webhook API-key auth defaults `api_key_header` to `X-API-Key`.

## Per-instance values

Each IAG instance must override these (and only these need to differ in a multi-instance deployment):

- `service.name` / `JARVIS_SERVICE_NAME`
- `service.port` / `JARVIS_SERVICE_PORT`
- `protected_agent.base_url` / `JARVIS_PROTECTED_AGENT_BASE_URL`
- `protected_agent.authentication.client_id` / `JARVIS_PROTECTED_AGENT_AUTHENTICATION_CLIENT_ID`
- `protected_agent.authentication.client_secret` / `JARVIS_PROTECTED_AGENT_AUTHENTICATION_CLIENT_SECRET`

Example mapping from iag-demo:

| IAG instance         | Port    | Protected agent URL          | Client-id env var              |
|----------------------|---------|------------------------------|--------------------------------|
| `orchestrator-iag`   | `8881`  | `http://orchestrator:6001`   | `ORCHESTRATOR_IDP_CLIENT_ID`   |
| `retriever-iag`      | `8882`  | `http://retriever:6002`      | `RETRIEVER_IDP_CLIENT_ID`      |
| `weather-iag`        | `8884`  | `http://weather:6004`        | `WEATHER_IDP_CLIENT_ID`        |

## Env-var form (iag-demo excerpt)

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

Available `auth.type` values: `no-auth`, `api-key`, `basic`, `mTLS`.

For file-based delivery, set `delivery: file` and provide:

- `storage_path` — directory IAG writes to.
- `format` — `csv`, `json`, or `txt`.
- `rotation_strategy` — `size`, `time`, or `size_and_time`.
- Optional: `rotation_interval` (default `24h`), `rotation_max_bytes` (default `100MiB`).

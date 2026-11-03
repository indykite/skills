# IAG Configuration Reference

IAG reads one YAML file passed with `--config=<file>`, or a directory of `.yaml` / `.yml` / `.json` / `.toml` files merged in alphabetical order with `--config-dir=<dir>` (the two flags are mutually exclusive), and environment variables. Rules that apply to every key:

- **Environment overrides.** Upper-case the key path, replace dots with underscores, prefix `JARVIS_`: `protected_agent.authentication.client_secret` is `JARVIS_PROTECTED_AGENT_AUTHENTICATION_CLIENT_SECRET`. A variable replaces the file value. `service.port` also honours `PORT`.
- **Lists** set from the environment are split on whitespace: `JARVIS_PROTECTED_AGENT_AUTHENTICATION_AUDIENCES="aud-1 aud-2"`. `authzen.input_params` is the one map: the whole map as JSON in `JARVIS_AUTHZEN_INPUT_PARAMS`.
- **No expansion.** `${VAR}` in the file is a literal string. Put secrets in the file or in `JARVIS_` variables.
- **The `audit` section is the one exception to "everything from the environment".** Audit is enabled by the presence of `audit` in a file; variables cannot create it, only override its values.
- The gateway listens on plain HTTP; terminate TLS in front of it. It calls the IdP and the Token Service with HTTP Basic client authentication and a 10 second timeout, and the IndyKite APIs with a 10 second timeout.

## Sections

| Section                | Purpose                                                                                                |
|------------------------|--------------------------------------------------------------------------------------------------------|
| `service`              | Runtime: `name`, `port`, `base_url` (required), `environment`, `log_level`, `healthcheck_port`.        |
| `identity_provider`    | IdP `base_url` and endpoints, `client_credential_renew_before`, `openid_configuration_url` (a2a), `issuer` (mcp). Always required. |
| `token_service`        | Optional. The issuer that mints the delegation token instead of the IdP (the IndyKite Token Service, or an IdP that meets the issuer requirements): `base_url`, `exchange_endpoint`, `introspect_endpoint`, `audience`, `client_auth.*`. |
| `protected_agent`      | Target `base_url`, downstream `protocol` (`a2a` default, or `mcp`), `node_type`, client credentials (`authentication.client_id` / `client_secret`), `authentication.audiences`. |
| `a2a`                  | Optional. Agent card cache: `cache_ttl`, `cache_update_after`, `cache_update_after_error`.             |
| `authorization_header` | Optional, with `token_service`: `same_user_check`.                                                     |
| `ibac`, `intent_agent` | Optional, a2a mode: `ibac.enabled`, `intent_agent.base_url` / `audience` / `timeout`.                  |
| `authzen`              | `base_url`, `action`, `input_params`, `policy_tags`, cache tuning. `subject_types` is not read.        |
| `contx_iq`             | `base_url`, `app_agent_credentials_token`, `cache_ttl`. `query_id` is ignored; `allowed_workflow_id` stops the gateway. |
| `audit`                | Optional. `delivery: webhook` (`http.*`) or `delivery: file` (`file.*`), `async.buffer_size`, `include_prompt`. |

## Service

| Key                        | Default   | Meaning |
|----------------------------|-----------|---------|
| `service.name`             | binary name | Name of this instance, written to every audit record and audit file name. Set it. |
| `service.port`             | `8888`    | Listening port. |
| `service.base_url`         | -         | **Required in both modes.** Public URL of the gateway. In `a2a` mode every interface URL in the agent card the gateway serves is replaced with it, so callers never reach the agent directly. In `mcp` mode the full public URL of the MCP endpoint at the gateway, with its path and without a query, credentials or fragment, e.g. `https://agents.example.com/mcp/v1/gid:AAAA…` (path unencoded, `gid:` not `gid%3A`): the gateway serves MCP on that path only, and its protected resource metadata names it. It is a setting rather than the request's host because, behind an ingress, the scheme and host of a request are not the public ones. |
| `service.healthcheck_port` | `9080`    | Port of `/healthz`, `/readyz` and `/startupz`, probed by the image's `HEALTHCHECK` (`http://localhost:9080/healthz`); change it only together with that probe. |
| `service.environment`      | -         | Free label such as `prod` or `demo`. |
| `service.log_level`        | `info`    | `debug`, `info`, `warn` or `error`; JSON logs on standard output. At `debug` the log shows the chain and the platform answers per request. |

## Identity provider (`identity_provider`, required)

| Key                              | Meaning |
|----------------------------------|---------|
| `base_url`                       | Provider base URL; the endpoints below are joined to it. |
| `introspect_endpoint`            | Token introspection endpoint (RFC 7662). |
| `client_credential_endpoint`     | Token endpoint for the client credentials grant. |
| `exchange_endpoint`              | Token endpoint for the exchange grant (RFC 8693), used when no `token_service` is configured. Usually the same endpoint. |
| `client_credential_renew_before` | Optional, default `10s`: how long before its expiry a kept client credentials token is renewed. `0` takes the default; a negative value is refused at startup. |
| `openid_configuration_url`       | **Required in `a2a` mode**: the OpenID Connect discovery URL of the IdP, the security scheme the served agent card names. |
| `issuer`                         | **Required in `mcp` mode**: the issuer identifier of the IdP, exactly as it appears in its metadata and in the `iss` of its tokens (absolute URL, no query or fragment). Listed in `authorization_servers` of the gateway's protected resource metadata. |

## Token Service (`token_service`, optional)

Whether the section is filled in decides how the gateway obtains and forwards the delegation token:

- **Left out** - the IdP exchanges the tokens at `identity_provider.exchange_endpoint` and its delegation token **replaces** the caller's token in `Authorization`; the downstream's own policies reach the chain as `$token`. An incoming `X-IK-Token` is ignored and removed from the forwarded request.
- **Filled in** - the issuer named here mints the delegation token: the IndyKite Token Service, or an IdP that supports the RFC 8693 exchange with the user's token as `subject_token` and the agent's client-credentials token as `actor_token`, takes its own delegated token as `subject_token` on a later hop and nests the previous `act`, keeps the subject's `sub` and writes the actor as `act.sub`, and answers RFC 7662 introspection of its tokens with their `act` claim. The caller's token travels **as it arrived** in `Authorization` (if at all) and the delegation token beside it in **`X-IK-Token`** (`$ik_token` downstream). A workflow then starts only at the agent the user's token was issued for, a later hop needs only its `X-IK-Token`, and `protected_agent.authentication.audiences` becomes required.

In both cases the gateway sends the delegation token in `X-IK-Token` on its own admission call, so the admission policy reads `$ik_token.act_chain` either way. Two policy features depend on what the issuer writes into `act`, both of which the IndyKite Token Service writes: `act.type` on every level (without it the platform looks each actor up by `external_id` alone, and `$ik_token.act_chain_types` is null), and `act.intent`.

| Field                       | Required | Notes |
|-----------------------------|----------|-------|
| `base_url`                  | yes      | Issuer location, e.g. `https://token-service.example.com`. |
| `exchange_endpoint`         | yes      | `/oauth2/token` for the IndyKite Token Service. |
| `introspect_endpoint`       | yes      | `/oauth2/introspect` for the IndyKite Token Service. |
| `audience`                  | no       | The audience asked for in every exchange, so the audience of every delegation token; `protected_agent.authentication.audiences` when left out. The delegation token travels on to the next gateway, so every gateway of a deployment should ask for the same one, listed in the Token Service's `idp.audiences` (else `invalid_target`); the Token Introspect configuration for the delegation tokens names it. |
| `client_auth.type`          | yes      | Only `client_secret_basic`. |
| `client_auth.client_id`     | yes      | What the issuer knows the gateway as - for the IndyKite Token Service its own `idp.client_auth.client_id`, **not** the IdP credentials under `protected_agent`. |
| `client_auth.client_secret` | yes      | The matching secret. |

Env-var form: `JARVIS_TOKEN_SERVICE_BASE_URL`, `JARVIS_TOKEN_SERVICE_EXCHANGE_ENDPOINT`, `JARVIS_TOKEN_SERVICE_INTROSPECT_ENDPOINT`, `JARVIS_TOKEN_SERVICE_AUDIENCE`, `JARVIS_TOKEN_SERVICE_CLIENT_AUTH_TYPE`, `JARVIS_TOKEN_SERVICE_CLIENT_AUTH_CLIENT_ID`, `JARVIS_TOKEN_SERVICE_CLIENT_AUTH_CLIENT_SECRET`. The `identity_provider` section stays required: it introspects the caller's token and issues the actor token.

## Protected agent (`protected_agent`, required)

| Key                          | Meaning |
|------------------------------|---------|
| `base_url`                   | `a2a`: where the agent card is read; requests go to the JSON-RPC URL the card declares, on the scheme and host of this URL. `mcp`: the **full URL of the MCP endpoint of the server**, with its path, unencoded, without a fragment, and with its query when the server needs one, e.g. `http://mcp-server:8080/mcp/v1/gid:AAAA…`. Every accepted request goes to this URL with the request's query appended; the request path is not used to build it, and may differ from the path of `service.base_url`. |
| `protocol`                   | `a2a` (default) or `mcp`; anything else fails startup with *invalid protected_agent protocol*. |
| `node_type`                  | Optional, no default: the IKG node type of the protected agent, the resource type of the admission evaluation, used only when the delegation token carries no `act.type`. Without either, the type is `Agent`. When the token has `act.type` (the Token Service writes its `idp.actor_type`, `Agent` by default) that type is used; when it differs from this setting, every request is refused with an `ERROR` record naming both. |
| `authentication.type`        | Only `credentials`. |
| `authentication.client_id`, `client_secret` | The protected agent's client at the IdP, used for the client credentials grant. The `sub` of that token is the agent's name in the chain. |
| `authentication.audiences`   | Without `token_service`: optional list sent as `audience` on the exchange. With `token_service`: **required** - the audiences of user tokens this gateway accepts in `Authorization` as the start of a workflow (any other token is `401 Access token not issued for this agent`), and the audiences asked for in the exchange unless `token_service.audience` is set. Each exchange audience must be in the Token Service's `idp.audiences`. |

## A2A card cache (`a2a`, optional)

`cache_ttl` (default `5m`) is how long the protected agent's card, and the client built from it, are kept; `cache_update_after` (defaults to `cache_ttl`, must not exceed it) the age after which the card is fetched again; `cache_update_after_error` (default `10s`, must not exceed `cache_update_after`) how long a failed card fetch is returned to every call before the next attempt. A new delegation token causes no new card fetch.

## Authorization header (`authorization_header`, optional, with `token_service`)

`same_user_check` (default `true`): on a later hop, refuse a bearer token in `Authorization` whose `sub` differs from the delegation token's (`401 Invalid delegated token, subject mismatch`). Switch it off for a flow whose `Authorization` carries something other than the user's token, such as the calling agent's service token: the gateway then does not read the bearer token of a later hop at all, and whoami and the admission call receive the delegation token in its place, so the subject stays the user named in the delegation token.

## IBAC and Intent Agent (`ibac`, `intent_agent`, optional, a2a mode)

With `ibac.enabled` on, the gateway asks the [Intent Agent](https://developer.indykite.com/guides/guide-intent-agent#gateway) about every A2A message with text before forwarding it, after its own admission check. Off (default), the Intent Agent is never called and the `intent_agent` section is not read.

| Key                     | Default        | Meaning |
|-------------------------|----------------|---------|
| `ibac.enabled`          | `false`        | Switches the Intent Agent call on. On, in front of an A2A agent, `intent_agent.base_url` is required. |
| `intent_agent.base_url` | -              | Where the Intent Agent serves its agent card; an absolute `http` or `https` URL. |
| `intent_agent.audience` | `intent_agent` | Audience of the client credentials token the gateway gets for the Intent Agent; must match the Intent Agent's `EXPECTED_TOKEN_AUDIENCE`. |
| `intent_agent.timeout`  | `45s`          | How long one prompt may take, the token grant included; longer answers `504`. Must be positive. |
| `audit.include_prompt`  | `false`        | Adds the prompt, and the reason of a failed task, to the `INTENT` audit records. Off, those records carry neither, since both can quote the user. |

## AuthZEN (`authzen`, required)

| Key                        | Default | Meaning |
|----------------------------|---------|---------|
| `base_url`                 | -       | AuthZEN API of the region, e.g. `https://eu.api.indykite.com/access/v1`. |
| `action`                   | -       | The action of the admission evaluation, the one the admission policy lists, e.g. `CAN_TRIGGER`. |
| `input_params`             | -       | Optional map sent as `context.input_params` in every admission call; a policy reads a value as `$name`, and the platform refuses a request that lacks a value the policy reads. A key has 2 to 20 lowercase letters, digits or `_` and starts with a letter; a text value has 1 to 256 bytes; the keys the platform fills are refused (`token`, `ik_token`, `subject_external_id`, `subject_id`, `subject_type`, `resource_external_id`, `resource_type`). |
| `policy_tags`              | -       | Optional list sent as `context.policy_tags`, so that only policies carrying at least one of the tags apply. A tag has 1 to 20 letters or digits, listed once. When a project uses tags, every gateway of the project should send them: a call without tags also reaches the tagged policies and their required parameters. |
| `subject_types`            | -       | Not read: the subject type comes from whoami. A value left over from an older configuration is ignored. |
| `cache_ttl`                | `5m`    | How long an admission decision is kept, per subject, resource type, chain and token claims. |
| `cache_update_after`       | `cache_ttl` | Age after which the next request triggers a background re-evaluation. Must not exceed `cache_ttl`. |
| `cache_update_after_error` | smaller of `10s` and `cache_update_after` | How long a failed evaluation is served before a retry. Must not exceed `cache_update_after`. |

Example: to restrict a gateway to `wf1`, set `input_params` to `workflow_ids: ["wf1"]` and `policy_tags` to `["pinned"]`, and add `AND wf.external_id IN $workflow_ids` to a copy of the admission policy that carries the tag `pinned`.

## ContX IQ (`contx_iq`, required)

| Key                                       | Meaning |
|-------------------------------------------|---------|
| `base_url`                                | ContX IQ API of the region, e.g. `https://eu.api.indykite.com/contx-iq/v1`. |
| `app_agent_credentials_token`             | The AppAgent credential, sent as `X-IK-ClientKey` to ContX IQ whoami and to AuthZEN (`Authorization` + `ContXIQ` API permissions). |
| `cache_ttl`                               | Default `5m`: how long a whoami answer is kept, `0` keeps none; a change of a Token Introspect configuration (e.g. its `ikg_node_type`) reaches the gateway after up to `cache_ttl`. |
| `cache_update_after`, `cache_update_after_error` | Still checked at startup with the same ordering rules as under `authzen`, but without effect. |
| `query_id`, `allowed_workflow_id`         | **No longer used**: the gateway runs no Knowledge Query. `query_id` is ignored; a non-empty `allowed_workflow_id` stops the gateway at startup. Restrict a gateway through the admission policy with `authzen.input_params` and `authzen.policy_tags` instead. |

## Audit (`audit`, optional, file only)

Without an `audit` section nothing is recorded. With one, records are delivered inline, or through a background queue when an `audit.async` section is present (a full queue drops records with the log line `dropping payload, async queue is full`, and the queue is drained on shutdown). The five webhook-auth and queue keys are documented with their snake_case names; the compact name in parentheses is the one the current releases read.

| Key | Meaning |
|-----|---------|
| `delivery` | `file` or `webhook`; the matching sub-section is required. |
| `file.storage_path` | Directory for the files, named `audit-<service.name>-…`. Must be writable by user `65532`. |
| `file.format` | `json`, `csv` or `txt`. |
| `file.rotation_strategy` | `time`, `size` or `size-and-time`. Required. |
| `file.rotation_interval`, `file.rotation_max_bytes` | Defaults `24h` and `104857600` (100 MiB). |
| `http.url`, `http.method` | Webhook destination; method `post` or `put`. Records are sent as JSON. |
| `http.auth.type` | `no-auth`, `api-key` or `mTLS`. |
| `http.auth.api_key` (`apikey`), `api_key_header` (`apikeyheader`) | For `api-key`; the header defaults to `X-API-Key`. |
| `http.auth.mtls_certificate_file_path` (`mtlscertificatepath`), `mtls_private_key_path` (`mtlsprivatekeypath`) | For `mTLS`; both required. |
| `async.buffer_size` (`buffersize`) | Queue length, default `512`. |
| `include_prompt` | Default `false`: whether the `INTENT` records carry the prompt and the reason of a failed task. |

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

## Startup errors

A configuration problem stops the process with one of these messages in the log.

| Message | Cause |
|---------|-------|
| `invalid identity_provider configuration: missing <key>`, `… client_credential_renew_before must not be negative` | One of the four IdP keys is absent, or the renewal margin is negative. |
| `missing authentication.audiences in protected_agent configuration`, `invalid authorization_header.same_user_check: …` | With `token_service`, the entry audiences are absent, or `same_user_check` is not a boolean. |
| `intent_agent.base_url is required when ibac.enabled is on in front of an A2A agent`, `intent_agent.base_url must be an absolute http or https URL`, `intent_agent.timeout must be positive` | Incomplete `intent_agent` section with `ibac.enabled` on. |
| `invalid token_service configuration: missing <key>`, `client_auth of type "client_secret_basic" requires client_id and client_secret`, `client_auth has invalid type "…" (want "client_secret_basic")` | Incomplete Token Service section. |
| `cannot get protected_agent base_url`, `invalid protected_agent protocol`, `missing client_id in protected_agent configuration`, `missing client_secret in protected_agent configuration` | Incomplete protected agent section. |
| `cannot get service base_url, the public URL of the gateway`, `service base_url must be an absolute URL`, `cannot get identity_provider openid_configuration_url` | In `a2a` mode, the settings the served agent card needs are absent. |
| `protected_agent base_url must be the full URL of the MCP endpoint of the server, with its path, unencoded, and without a fragment`, `cannot get service base_url, the public URL of the MCP endpoint at the gateway`, `service base_url must be the full public URL of the MCP endpoint at the gateway, …`, `cannot get identity_provider issuer`, `identity_provider issuer must be an absolute URL without a query or fragment` | In `mcp` mode, one of the three endpoint settings is absent or malformed, e.g. a `protected_agent.base_url` without a path or a percent-encoded `gid%3A`. |
| `missing required authzen.base_url`, `missing required authzen.action` | Incomplete AuthZEN section. |
| `missing required contx_iq.base_url`, `missing required contx_iq.app_agent_credentials_token in configuration` | Incomplete ContX IQ section. |
| `contx_iq.allowed_workflow_id is no longer supported: restrict the workflows in the admission policy and pass the values with authzen.input_params and authzen.policy_tags` | A configuration from before the admission policy still restricts the gateway to one workflow. |
| `authzen.input_params must be a map: …`, `authzen.input_params: the key "…" is reserved, the platform fills it`, `… must have 2 to 20 lowercase letters, digits or underscores and start with a lowercase letter`, `… the value of "…" must have 1 to 256 bytes`, `authzen.policy_tags: the tag "…" must have 1 to 20 letters or digits`, `… the tag "…" is listed twice` | An `input_params` or `policy_tags` value the platform would refuse, including invalid JSON in `JARVIS_AUTHZEN_INPUT_PARAMS`. |
| `<section>.cache_ttl must not be negative, got …`, `<section>.cache_update_after (…) must not exceed <section>.cache_ttl (…)`, `<section>.cache_update_after_error (…) must not exceed <section>.cache_update_after (…)` | Cache durations out of order, for `authzen`, `contx_iq` or `a2a`. |
| `invalid port value … - not in range` | `service.port` or `service.healthcheck_port` is not a valid TCP port. |
| `audit: unknown delivery type "…", must be one of: file, webhook`, `audit: http url is required`, `audit: http method must be POST or PUT, got "…"`, `audit: unsupported auth type "…"`, `audit: api-key auth requires api_key`, `audit: mTLS requires mtls_certificate_file_path and mtls_private_key_path`, `audit: file storage path is required`, `audit: file rotation is required and must be one of "time", "size", "size-and-time"` | Incomplete audit section. The two auth messages name the keys in snake_case, but the values are read from `apikey`, `mtlscertificatepath` and `mtlsprivatekeypath`. |

## Per-instance values

Each IAG instance must override these (and only these need to differ in a multi-instance deployment):

- `service.name` / `JARVIS_SERVICE_NAME`, `service.port` / `JARVIS_SERVICE_PORT`, `service.base_url` / `JARVIS_SERVICE_BASE_URL`
- `service.healthcheck_port` / `JARVIS_SERVICE_HEALTHCHECK_PORT` (only when instances share a network namespace)
- `protected_agent.base_url` / `JARVIS_PROTECTED_AGENT_BASE_URL`, `protected_agent.protocol` / `JARVIS_PROTECTED_AGENT_PROTOCOL`
- `protected_agent.authentication.client_id` / `JARVIS_PROTECTED_AGENT_AUTHENTICATION_CLIENT_ID`, `…_CLIENT_SECRET`
- `protected_agent.authentication.audiences` / `JARVIS_PROTECTED_AGENT_AUTHENTICATION_AUDIENCES` (with the Token Service: which user tokens may start a workflow here)
- `authzen.input_params` / `JARVIS_AUTHZEN_INPUT_PARAMS` and `authzen.policy_tags` / `JARVIS_AUTHZEN_POLICY_TAGS`, when a gateway is pinned to some workflows

Example mapping from iag-mcp-demo:

| IAG instance         | Port    | Protected agent URL          | Client-id env var              |
|----------------------|---------|------------------------------|--------------------------------|
| `orchestrator-iag`   | `8881`  | `http://orchestrator:6001`   | `ORCHESTRATOR_IDP_CLIENT_ID`   |
| `retriever-iag`      | `8882`  | `http://retriever:6002`      | `RETRIEVER_IDP_CLIENT_ID`      |
| `weather-iag`        | `8884`  | `http://weather:6004`        | `WEATHER_IDP_CLIENT_ID`        |

## Env-var form (Docker Compose pattern)

One base service with the shared variables, extended once per gateway with the per-instance values above; a small mounted file carries the `audit` section, since audit cannot be enabled from variables.

```yaml
services:
  iag-base:
    image: indykite/agent-gateway:<tag> # pin a release; latest lags weeks behind
    command: ["--config=/app/config.yaml"] # the file holds the audit section
    environment:
      JARVIS_SERVICE_LOG_LEVEL: info
      JARVIS_SERVICE_ENVIRONMENT: demo
      JARVIS_IDENTITY_PROVIDER_BASE_URL: ${IDP_BASE_URL}
      JARVIS_IDENTITY_PROVIDER_INTROSPECT_ENDPOINT: "oauth-introspect"
      JARVIS_IDENTITY_PROVIDER_CLIENT_CREDENTIAL_ENDPOINT: "oauth-token"
      JARVIS_IDENTITY_PROVIDER_EXCHANGE_ENDPOINT: "oauth-token"
      JARVIS_IDENTITY_PROVIDER_OPENID_CONFIGURATION_URL: ${IDP_OPENID_CONFIGURATION_URL} # a2a
      JARVIS_CONTX_IQ_BASE_URL: ${INDYKITE_BASE_URL}/contx-iq/v1
      JARVIS_CONTX_IQ_APP_AGENT_CREDENTIALS_TOKEN: ${APP_AGENT_CREDENTIALS_TOKEN}
      JARVIS_AUTHZEN_BASE_URL: ${INDYKITE_BASE_URL}/access/v1
      JARVIS_AUTHZEN_ACTION: CAN_TRIGGER
      # Optional: mint the delegation token at a self-hosted Token Service instead of the IdP.
      # JARVIS_TOKEN_SERVICE_BASE_URL: ${TOKEN_SERVICE_BASE_URL}
      # JARVIS_TOKEN_SERVICE_EXCHANGE_ENDPOINT: /oauth2/token
      # JARVIS_TOKEN_SERVICE_INTROSPECT_ENDPOINT: /oauth2/introspect
      # JARVIS_TOKEN_SERVICE_AUDIENCE: agent-gateway
      # JARVIS_TOKEN_SERVICE_CLIENT_AUTH_TYPE: client_secret_basic
      # JARVIS_TOKEN_SERVICE_CLIENT_AUTH_CLIENT_ID: agent-gateway
      # JARVIS_TOKEN_SERVICE_CLIENT_AUTH_CLIENT_SECRET: ${TOKEN_SERVICE_CLIENT_SECRET}
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

Per gateway, add `JARVIS_SERVICE_NAME`, `JARVIS_SERVICE_PORT`, `JARVIS_SERVICE_BASE_URL`, `JARVIS_PROTECTED_AGENT_BASE_URL`, the agent's client id and secret, its audiences, and optionally `JARVIS_AUTHZEN_INPUT_PARAMS` / `JARVIS_AUTHZEN_POLICY_TAGS`.

## Protecting an MCP server (`protocol: mcp`)

Set `protected_agent.protocol: mcp` (or `JARVIS_PROTECTED_AGENT_PROTOCOL: mcp`) to switch the gateway from its default A2A proxy into MCP **Streamable HTTP** proxy mode. The decision sequence is identical (caller → exchange → whoami → admission → forward); only the forwarded protocol differs. A gateway in front of an MCP server needs three settings and does not start without them:

| Setting                      | Value |
|------------------------------|-------|
| `service.base_url`           | Public URL of the MCP endpoint at the gateway, e.g. `https://agents.example.com/mcp/v1/gid:AAAA…`. To keep the URL your clients already call, set it to that URL. |
| `protected_agent.base_url`   | Full URL of the MCP endpoint of the server, e.g. `http://mcp-server:8080/mcp/v1/gid:AAAA…` (for the IndyKite MCP server, `https://<region>.mcp.indykite.com/mcp/v1/<project gid>`), not the server's address alone. |
| `identity_provider.issuer`   | Issuer identifier of the IdP, e.g. `https://idp.example.com/realms/main`. |

Write both paths unencoded (`gid:`, not `gid%3A`). In MCP mode:

- The gateway serves MCP on the path of `service.base_url` only; a client that used to call other paths of the server through the gateway now gets `404`. The two OAuth metadata paths are public.
- The `Mcp-Session-Id` header and the response body pass through unchanged, streamed for SSE; the server's status is returned as is.
- IAG mints its own delegation token for the downstream MCP server (from `protected_agent.authentication.client_id` / `client_secret`) and forwards the request with it - in `Authorization` when the IdP mints it, in `X-IK-Token` next to the caller's access token when the Token Service does.
- Only the MCP protocol revisions `2025-06-18`, `2025-11-25`, and `2026-07-28` are forwarded, and the gateway reads the tool or resource each request names; there is no configuration knob for either. Details in the *MCP protocol revisions* and *MCP request classification* sections of [`architecture.md`](architecture.md#mcp-protocol-revisions).

### iag-mcp-demo (the `mcp-iag` instance)

The `iag-mcp-demo` reference app adds one MCP-mode instance, `mcp-iag`, in front of the IndyKite MCP server; the `retriever` and `weather` agents are MCP clients routed through it instead of calling the MCP server directly. The MCP agents authenticate with their own token (`IK_APP_AGENT_KEY`), not the chatbot user token used by the A2A flows, so that token must match a Token Introspect configuration of the project (its `ikg_node_type` is the subject type an admission policy must name) and the one-agent workflow `[mcp-agent]` must exist; `JARVIS_AUTHZEN_ACTION` can be overridden on the instance.

## Moving from the workflow query to the admission policy

A deployment set up when the gateway still ran a ContX IQ Knowledge Query and an AuthZEN resource search needs, in this order:

1. **Before the upgrade** (harmless to the old gateway): create the admission policy, and a Token Introspect configuration for the issuer and audience of the delegation tokens of every gateway, also without a Token Service. Delegation tokens with one shared audience need one configuration per issuer.
2. **With the upgrade**: remove any `contx_iq.allowed_workflow_id`, which stops the new gateway, and express the restriction with `authzen.input_params` and `authzen.policy_tags`. In `mcp` mode, set the three endpoint settings above. In `a2a` mode, set `service.base_url` and `identity_provider.openid_configuration_url`.
3. **After the upgrade**: remove `contx_iq.query_id` (ignored by the new gateway, required by the old one) and `authzen.subject_types` (not read), and delete the old `Workflow` trigger policy, the ContX IQ policy and the Knowledge Query it named - the new gateway no longer uses them, but the old gateway refuses every request without them.

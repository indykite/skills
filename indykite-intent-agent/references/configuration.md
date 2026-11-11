# Intent Agent Configuration and Deployment

The Intent Agent is deployed and operated in your environment from the `indykite/intent-agent` image; only the IndyKite platform and Google Gemini are remote. Source, README, and Helm chart: [github.com/indykite/intent-agent](https://github.com/indykite/intent-agent).

## What the project needs

- **An AppAgent credential** with the `ReadDataSchema` and `ReadAuthZConfigs` API permissions ([Credentials guide](https://developer.indykite.com/guides/guide-credentials)), sent as `X-IK-ClientKey` to `GET /data-schema/v1/` and `GET /access/v1/policies`. It must be a well-formed JWT: the agent refuses to start otherwise.
- **Data in the graph**, so the data schema lists your node types (the schema is updated at most once a minute after an ingest).
- **ACTIVE KBAC policies** for every subject type that will ask ([`indykite-authzen-kbac-policies`](../../indykite-authzen-kbac-policies/SKILL.md)). The agent can only express a subject-action-resource combination a policy grants; a new policy reaches it after up to `POLICY_REFRESH_TTL_MINUTES`.
- **An RFC 7662 introspection endpoint** that knows the callers' tokens, with a client the agent authenticates with (HTTP Basic): your identity provider, or the [Token Service](https://developer.indykite.com/guides/guide-token-service) (`/oauth2/introspect` with its `idp.client_auth`).
- **A Google Gemini API key** for the extraction.

## Environment variables

All settings are environment variables (or a `.env` file), read once at startup. The service refuses to start when a required one is missing or blank.

### Required

| Variable                                        | Meaning |
|-------------------------------------------------|---------|
| `INDYKITE_BASE_URL`                             | The regional IndyKite API base URL (`https://eu.api.indykite.com` or `https://us.api.indykite.com`). |
| `IK_APP_AGENT_KEY`                              | The AppAgent credential (`X-IK-ClientKey`). |
| `GEMINI_API_KEY`                                | Google Gemini API key used for the extraction. |
| `INTROSPECT_URL`, `INTROSPECT_CLIENT_ID`, `INTROSPECT_CLIENT_SECRET` | The RFC 7662 introspection endpoint and the agent's client there. |
| `AUDIT_DELIVERY`                                | `file` or `webhook`. No default: auditing cannot be switched off. |

### Commonly tuned

| Variable                                        | Default                     | Meaning |
|-------------------------------------------------|-----------------------------|---------|
| `INTENT_PORT`, `HEALTH_PORT`                    | `6003`, `8001`              | The A2A and health listeners; they must differ. |
| `ADVERTISED_URL`                                | `http://intent:<INTENT_PORT>` | The JSON-RPC URL on the agent card. Only published, never checked: set it to the scheme, host, and port callers really use (the ingress or gateway in front), e.g. `https://intent-agent.example.com`. A mismatch makes the agent unreachable for clients that follow the card; the agent logs a warning at startup when it is unset. |
| `EXPECTED_TOKEN_AUDIENCE`                       | `intent_agent`              | The `aud` a caller's token must carry. Published on the agent card, so a client can request the right token; the gateway's `intent_agent.audience` must match it. |
| `INTENT_AGENT_NAME`                             | `intent_agent`              | The agent's name on the card and in audit file names. |
| `GEMINI_MODEL`                                  | `gemini-3.5-flash-lite`     | Model used for the extraction. |
| `LLM_TIMEOUT_SECONDS`, `REQUEST_TIMEOUT_SECONDS` | `3.0`, `10.0`              | Per LLM call, and for the whole extraction (schema and policy fetch, every LLM call and retry; not introspection). `LLM_TIMEOUT_SECONDS` must not exceed `REQUEST_TIMEOUT_SECONDS`. |
| `VALIDATION_MAX_RETRIES`                        | `1`                         | Extra LLM attempts after an off-schema answer (`0` disables). |
| `TOOL_CALL_MAX_ITERATIONS`                      | `5`                         | Tool-call rounds before giving up. |
| `SCHEMA_FETCH_TIMEOUT_SECONDS`, `POLICY_FETCH_TIMEOUT_SECONDS`, `POLICY_FETCH_RETRY_ATTEMPTS` | `3.0`, `2.0`, `2` | Per fetch (neither may exceed `REQUEST_TIMEOUT_SECONDS`); policy fetch attempts. |
| `SCHEMA_REFRESH_TTL_MINUTES`, `POLICY_REFRESH_TTL_MINUTES` | `5.0`             | How long a cached schema / policy list is served. An expired schema is served stale while it refreshes in the background; a failed policy refresh serves the last known-good list (audit `policy_fetch_failed: true`). |
| `CACHE_BACKEND`, `REDIS_URL`                    | `memory`, -                 | `redis` shares the schema and policy cache between instances; `REDIS_URL` is then required. |
| `INTROSPECT_TIMEOUT_SECONDS`                    | `5.0`                       | Per introspection call. |
| `HEALTH_CHECK_TIMEOUT_SECONDS`                  | `3.0`                       | Bound on each startup probe that seeds `/health` (must be positive). |
| `LOG_LEVEL`                                     | `INFO`                      | `DEBUG`, `INFO`, `WARNING`, `ERROR`, `CRITICAL`. At `DEBUG` the log shows the model's raw answer. |

### Audit delivery

Every request produces one record; a failed delivery (unreachable webhook, disk error) is logged and never fails the request. The chosen delivery has required settings of its own, also checked at startup.

| Variable                                        | Meaning |
|-------------------------------------------------|---------|
| `AUDIT_ASYNC`, `AUDIT_ASYNC_BUFFER_SIZE`        | `true` delivers through a bounded in-memory queue (default length `512`) drained by a background worker and flushed on shutdown; a full queue drops records with the warning `dropping payload, async queue is full`. Default `false` (inline delivery). |
| `AUDIT_FILE_STORAGE_PATH`, `AUDIT_FILE_FORMAT`, `AUDIT_FILE_ROTATION_STRATEGY` | Required with `file`: the directory (created if missing, must be writable by user `65532`), `csv` / `json` (one object per line) / `txt`, and `time` / `size` / `size-and-time`. Files are named `audit-<INTENT_AGENT_NAME>-<unixNano>.<format>`. |
| `AUDIT_FILE_ROTATION_INTERVAL_SECONDS`, `AUDIT_FILE_ROTATION_MAX_BYTES` | Defaults `86400` (24 h) and `104857600` (100 MiB). |
| `AUDIT_HTTP_URL`, `AUDIT_HTTP_METHOD`, `AUDIT_HTTP_AUTH_TYPE` | Required with `webhook`: one request per record with the record as JSON body, `POST` or `PUT` (any letter case), and `mTLS` / `api-key` / `no-auth`. |
| `AUDIT_HTTP_MTLS_CERTIFICATE_FILE_PATH`, `AUDIT_HTTP_MTLS_PRIVATE_KEY_PATH` | Both required with `mTLS` (TLS 1.3 minimum). |
| `AUDIT_HTTP_API_KEY`, `AUDIT_HTTP_API_KEY_HEADER` | Required with `api-key`; the header defaults to `X-API-Key`. |
| `AUDIT_HTTP_TIMEOUT_SECONDS`                    | Per delivery, default `5.0`. |

## The audit record

One record per request, snake_case keys, in this order (also the csv column order): `timestamp` (RFC 3339 UTC, microseconds), `request_id` (the caller's `X-Request-ID` when non-blank and at most 40 characters, else a generated UUID), `subject_id`, `subject_type` (from the message metadata - also for a subject search, where the evaluations carry another subject), `requesting_agent_id` (reserved, empty), `context_id`, `prompt`, `evaluations` (empty when none were derived), `schema_version` and `policy_version` (content hashes of the schema and of the subject type's policies, not version numbers; empty when unavailable), `llm_provider`, `llm_model`, `latency_ms` (authentication included), `validation_retries`, `policy_fetch_failed` (`null` no fetch attempted, `false` succeeded, `true` the last known-good policies were used), `outcome`, and `message` (the text the caller received, exactly).

| `outcome`           | When |
|---------------------|------|
| `success`           | Evaluations were returned. |
| `unmatched`         | The prompt yielded no intent or a free-text reply. |
| `validation_failed` | The model's answer never passed validation within `VALIDATION_MAX_RETRIES`. |
| `error`             | An authentication rejection, a missing or empty schema, a subject type mismatch, a timeout, or any other failure. |

Field semantics, the csv and txt layouts, and the correlation with the gateway's `INTENT` records are in the [Audit Event Formats guide](https://developer.indykite.com/guides/guide-audit-formats). The records are not tamper-proof: ship them somewhere durable (a webhook, or a mounted directory).

## Running the image

```bash
mkdir -p audit && sudo chown 65532 audit                 # the container runs as user 65532
docker run -d --name intent-agent -p 6003:6003 -p 8001:8001 --env-file .env \
  -v "$(pwd)/audit:/var/audit" \
  -e AUDIT_FILE_STORAGE_PATH=/var/audit \
  indykite/intent-agent:<version>
curl http://localhost:8001/health                        # liveness + last known dependency state
curl http://localhost:6003/.well-known/agent-card.json   # public agent card
```

- **Pin a version**: no `latest` tag is published; the image and the Helm chart are published to Docker Hub on each release.
- The container runs as user `65532` with a read-only `/app`, so file audit needs a directory that user can write; mount it from the host so the records outlive the container (a path inside the container only suits a throwaway test).
- Several instances behind a load balancer share one vocabulary cache with `CACHE_BACKEND=redis` and a `REDIS_URL`; with `memory` each instance fetches on its own.
- **Helm**: a chart is published with each release. Its `app.*` values mirror the environment variables one to one (`app.advertisedUrl`, `app.expectedTokenAudience`, `app.auditDelivery`, …), with the secrets (`GEMINI_API_KEY`, `INTROSPECT_CLIENT_SECRET`, `IK_APP_AGENT_KEY`, `REDIS_URL`, `AUDIT_HTTP_API_KEY`) taken from Kubernetes Secrets by reference. With `file` delivery the chart mounts an `emptyDir`, so records live only as long as the pod does - use `webhook` for anything durable. `app.advertisedUrl` must match the Ingress host and TLS, or the Istio VirtualService host, callers use; the chart can also run an in-cluster Redis for self-contained deployments. The chart validates the timeout ordering at install time.
- The agent card is public and announces the bearer requirement and the expected audience; the JSON-RPC route is the only authenticated one.

## Behind the Agent Gateway

An [Agent Gateway](../../indykite-agent-gateway/SKILL.md) protecting an A2A agent asks the Intent Agent about every message with text before it forwards it, when `ibac.enabled` is on. The gateway plays the caller: it resolves the user with ContX IQ whoami, gets its own client-credentials token for `intent_agent.audience` (default `intent_agent`), keeps it until shortly before it expires, and sends the text parts of a `message/send` or `message/stream` message, joined one per line, with `subject_type` and `subject_id`. The call happens after the gateway's own admission check and before forwarding. A completed task's intent is forwarded with the message: with a Token Service the gateway writes its evaluations into `act.intent` of the delegation token the agent receives, so the next hop sees it, and an intent with more evaluations than the Token Service accepts (`10` by default) or more than 64 is answered in place of the agent with the error `The request asks for too much at once: its intent has <n> evaluations, too many for one request.`, the reason `intent_too_large` and the obligation `Send the request in smaller parts.` Without a Token Service the intent is not written into the token, and an intent over 64 evaluations is `502`.

On the Intent Agent side this needs: `EXPECTED_TOKEN_AUDIENCE` equal to the gateway's `intent_agent.audience`, an introspection endpoint that knows the gateway's token (the IdP that issued it), and `ADVERTISED_URL` set to the address the gateway reaches (the gateway reads the agent card from `intent_agent.base_url`). The gateway's keys, its `200`-with-`intent_error` answer on a failed task, its `502` / `504` refusals, `intent_agent.timeout` (default 45 s, which must leave room for `REQUEST_TIMEOUT_SECONDS` plus the token grant), `audit.include_prompt`, and its `INTENT` audit records (`INTENT_FOUND` / `INTENT_FAILED` / `ERROR`, `durationMs`) are documented in the gateway skill's [configuration reference](../../indykite-agent-gateway/references/configuration.md#ibac-and-intent-agent-ibac-intent_agent-optional). The Intent Agent writes its own record for the same call.

## The demo

The [`intent-agent-demo`](https://github.com/indykite/developer-hub/tree/master/a2a/intent-agent-demo) in the developer-hub repository runs the Intent Agent, the Token Service, and a web console locally with Docker Compose, or on minikube with its Helm chart. Its graph and 24 KBAC policies come from the `intent` dataset of the instant-stack app (the CanBank users and customers of the examples). The console exchanges the person's token at the Token Service for a delegation token with audience `intent_agent`, and the Intent Agent introspects that token at the Token Service. Views: a playground (prompt, steps, each evaluation as a ticket with its AuthZEN decision, raw JSON-RPC and audit record), guardrails (sample prompts the agent refuses, and three token failures), the vocabulary per subject type, live audit records, and the architecture.

---
name: indykite-agent-gateway
description: Configure IndyKite Agent Gateway (IAG) in front of agent-to-agent (A2A) workflows or MCP servers, optionally with the self-hosted IndyKite Token Service (ITS) that mints the delegation token carried in `X-IK-Token` so multi-hop chains grow hop by hop. Use when wiring up A2A or MCP policy enforcement, modeling workflows in the IKG, configuring `JARVIS_*` / `config.yaml` (including `token_service`), running the Token Service, reading IAG audit records, or debugging IAG 401/403 responses.
license: Apache-2.0
compatibility: Requires Docker and Docker Compose to run the iag-mcp-demo reference app. Runtime network access to the configured IndyKite Hub, OAuth IdP, AuthZEN, ContX IQ endpoints, and the optional Token Service is required.
---

# IndyKite Agent Gateway

The Indykite Agent Gateway (IAG) is a standalone service that protects exactly one downstream - an **A2A agent** or an **MCP server**. Run one IAG per protected downstream. From the caller's perspective IAG appears as the Target; from the protected downstream's perspective IAG appears as the Source. IAG is **not a generic reverse proxy**: by default (`protocol: a2a`) it speaks the **A2A protocol** and tracks A2A sessions so JSON-RPC streams flow correctly; with `protocol: mcp` it proxies **MCP Streamable HTTP** traffic (forwarding `Mcp-Session-Id` and streaming SSE responses through). Either way the same authorization runs in front.

For each request IAG validates three things:

1. The **caller** (token introspection at the IdP).
2. The **workflow** (subject `CAN_TRIGGER` check via AuthZEN/KBAC).
3. The **delegation chain** (the request's `act` chain matches a chain modeled in the IKG).

The delegation token that carries the `act` chain is minted either by the **IdP** (RFC 8693 token exchange) or, when the optional `token_service` section is configured, by the self-hosted **IndyKite Token Service (ITS)**. With ITS the caller's own access token travels untouched in `Authorization` and the delegation token beside it in `X-IK-Token`, and a request that arrives with an `X-IK-Token` is a later hop whose chain is nested into the next token - which is what makes workflows longer than one hop work.

## When to use

Activate this skill when the user:

- is building an agent-to-agent (A2A) workflow and wants policy enforcement in front of each agent;
- is putting an enforcement point in front of an **MCP server** (`protocol: mcp`) so MCP traffic gets the same introspection, AuthZEN check, and audit as A2A;
- needs traceable user-to-agent delegation through OAuth token exchange and the `act` chain, including **multi-hop chains** that require the **IndyKite Token Service** and the `X-IK-Token` header;
- is configuring the **Token Service** itself (issuer `base_url`, signing keys, audiences, `token_introspection` configurations);
- is modeling a `Workflow` and `Agent` nodes with `INVOKES` relationships in the IndyKite Graph (IKG);
- is configuring `JARVIS_*` environment variables or a `config.yaml` for one or more IAG instances (including `token_service`, `healthcheck_port`, cache tuning, audit delivery);
- is reading IAG or Token Service audit records (`AUTHORIZED` / `NOT_AUTHORIZED`, `TOKEN_EXCHANGED` / `EXCHANGE_REFUSED`, `INTROSPECTED*`) and trying to explain a `401` or `403`;
- is reproducing or extending the [`iag-mcp-demo`](https://github.com/indykite/developer-hub/tree/master/a2a/iag-mcp-demo) (A2A + MCP), or [`iag-token-exchange`](https://github.com/indykite/developer-hub/tree/master/a2a/iag-token-exchange) (Token Service) reference applications.

Do **not** activate this skill when the user:

- wants a generic HTTP reverse proxy or service mesh - IAG only speaks A2A or MCP, not arbitrary HTTP;
- is asking about IndyKite features unrelated to agent gating (Token Introspect configurations of the platform, plain AuthZEN policies, ContX IQ queries outside of agent gating);
- is debugging the protected agent itself rather than the gateway in front of it.

## Prerequisites

Before any of the steps below will succeed, the user needs:

- An **IndyKite project** with AuthZEN / KBAC and ContX IQ enabled, plus a `Workflow` node and `Agent` nodes already modeled (or a plan to model them - see Step 1).
- An **OAuth2-compliant IdP** with introspect, client-credentials, and token-exchange endpoints. Set `IDP_BASE_URL` to the IdP base for the target environment. The IdP stays required even with the Token Service: it introspects the caller's access token and authenticates the protected agent.
- One **client_id / client_secret pair per protected downstream** (A2A agent or MCP server), registered with the IdP.
- A **ContX IQ query** that returns `(workflow, agent_list)` pairs for each protected downstream - its `query_id` goes into IAG configuration.
- For an **MCP downstream** (`protocol: mcp`): the MCP server's origin and endpoint path, and the gateway image `indykite/agent-gateway` **≥ 2.0.1** (older images ignore the protocol and behave as an A2A proxy). MCP clients typically authenticate with an App Agent token, which must be introspectable and pass the AuthZEN check.
- For **workflows longer than one hop** (agent → agent → agent), or whenever the protected agent must see the caller's original access token: a running **IndyKite Token Service** (`indykite/token-service`) with an `https` issuer `base_url`, at least one signing key, the audiences of every protected agent, and a `client_auth` client for the gateways - see [`references/token-service.md`](references/token-service.md). Without it the gateway exchanges tokens at the IdP on every hop and the chain never grows past one hop.
- Docker (and Docker Compose) to run the iag-mcp-demo reference app.

If any of these are missing, stop and tell the user - IAG cannot run without them.

## Steps

### 1. Model the workflow in the IKG

Create one `Workflow` node identified by `external_id`, one `Agent` node per protected agent, and `INVOKES` relationships between agents. Every `INVOKES` relationship **must** carry a `workflow_name` property whose value matches the `Workflow.external_id`. The ContX IQ query in step 3 silently excludes any chain without it.

Example shape (the canonical `wf1` workflow from the demo):

```text
(Workflow {external_id: "wf1"})
(Agent {external_id: "orchestrator"})
  -[INVOKES {workflow_name: "wf1"}]-> (Agent {external_id: "retriever"})
(Agent {external_id: "orchestrator"})
  -[INVOKES {workflow_name: "wf1"}]-> (Agent {external_id: "weather"})
```

Capture this data through the **Capture API** (`POST /capture/v1/nodes`, `POST /capture/v1/relationships`), the IndyKite Hub UI, or an existing Terraform / identity pipeline - whichever the project already uses.

### 2. Wire the subject to the workflow

For every subject that is allowed to trigger the workflow, create the edge `(:User)-[:CAN_TRIGGER]->(:Workflow)` (or the equivalent AuthZEN relation). Without this edge IAG returns `403` at the AuthZEN check even if the chain is correct.

### 3. Build the ContX IQ query

The query must return `(workflow, agent_list)` pairs given a protected agent identifier, where `agent_list` is the ordered chain of agents the request must traverse. Save its `query_id` - IAG references it via `JARVIS_CONTX_IQ_QUERY_ID` (or `contx_iq.query_id`).

If the KBAC policy behind `CAN_TRIGGER` reads the delegation token, it must reference the token the gateway actually forwards: `$token` when the IdP mints it (it replaces `Authorization`), `$ik_token` when the Token Service mints it (it travels in `X-IK-Token`). A reference to a token that was not sent resolves to nothing, and the decision is a denial.

### 4. Configure each IAG instance

Pick one of the two configuration forms:

- **YAML config file** - pass with `--config=/app/config.yaml`. Best for production where configuration management is strict. See `assets/config-template.yaml` in this skill.
- **Environment variables** - keys use the `JARVIS_` prefix with underscores (e.g. `JARVIS_SERVICE_NAME`). Best when multiple IAG instances share a base image (as in the iag-mcp-demo) and override only per-agent fields.

The full set of sections is `service`, `identity_provider`, `token_service` (optional), `protected_agent`, `authzen`, `contx_iq`, and `audit`. See `references/configuration.md` for every field and its default.

Pick the downstream protocol with `protected_agent.protocol` (env `JARVIS_PROTECTED_AGENT_PROTOCOL`): `a2a` (default) for an A2A agent, `mcp` for an MCP server. Any other value fails startup with *invalid protected_agent protocol*. In `mcp` mode `protected_agent.base_url` is the MCP server **origin only** - IAG appends the incoming request path. The authorization sequence is unchanged; only the forwarded protocol differs. See the *Protecting an MCP server* section of `references/configuration.md`.

Pick where the delegation token comes from with the optional `token_service` section (`base_url`, `exchange_endpoint`, `introspect_endpoint`, `client_auth.type: client_secret_basic`, `client_auth.client_id`, `client_auth.client_secret`; env `JARVIS_TOKEN_SERVICE_*`). Left out, the IdP exchanges the tokens. Filled in, the Token Service mints the delegation token, the request is forwarded with both `Authorization` and `X-IK-Token`, and an incoming `X-IK-Token` is validated at the Token Service and becomes the subject of the next exchange. When set, also list the audiences the gateway requests in `protected_agent.authentication.audiences` - every one of them must be in the Token Service's `idp.audiences`, or the exchange is refused with `invalid_target`.

Per-instance values that **must** differ between IAG instances:

- `service.name` / `JARVIS_SERVICE_NAME`
- `service.port` / `JARVIS_SERVICE_PORT`
- `service.healthcheck_port` / `JARVIS_SERVICE_HEALTHCHECK_PORT` (only when several instances share one network namespace; default `9080`)
- `protected_agent.base_url` / `JARVIS_PROTECTED_AGENT_BASE_URL`
- `protected_agent.protocol` / `JARVIS_PROTECTED_AGENT_PROTOCOL` (if any instance protects an MCP server)
- `protected_agent.authentication.client_id` and `client_secret`
- `protected_agent.authentication.audiences` (with the Token Service, the audience of that instance's protected agent)

The `token_service` section itself is the same for every instance.

### 5. Deploy the IAG instances (and the Token Service, if used)

For Docker Compose, follow the iag-mcp-demo pattern: one shared `iag-base-docker.yaml` plus one service per protected agent that overrides only the per-instance fields above. For Kubernetes, deploy each IAG as a standalone Pod for independent scaling, or as a sidecar to its protected agent for tighter coupling.

Each gateway serves `/healthz`, `/readyz`, and `/startupz` on `service.healthcheck_port` (default `9080`), and the container image's `HEALTHCHECK` probes `http://localhost:9080/healthz`. Older images did not serve that endpoint and reported unhealthy for their whole life - pull a current image if orchestration keyed on container health never fires.

The Token Service is one deployment shared by all gateways: run `indykite/token-service` (pin a concrete tag such as `1.0.0`, never `latest`) with `--config=<file>` or, in production, `--config-dir=<dir>` so the secret (signing keys, `client_auth`) can be mounted as a separate file merged over the non-sensitive definitions. `service.base_url` (the `iss` of every token it signs) is mandatory, has no default, and must be `https`. Details in [`references/token-service.md`](references/token-service.md).

The IndyKite platform must also **trust** the tokens ITS signs, or every request that reaches AuthZEN, ContX IQ, or the MCP server with an `X-IK-Token` is refused with `401 Invalid token in X-IK-Token header`. Create one Token Introspect configuration per audience the delegation token can carry (`POST /configs/v1/token-introspects`, Service Account token): `jwt_matcher.issuer` = the ITS `base_url`, `jwt_matcher.audience` = the protected agent's audience, `offline_validation.public_jwks` = the **public** half of the signing key. Exact payload in the *Making the platform trust ITS tokens* section of [`references/token-service.md`](references/token-service.md).

Verify that each IAG can reach the IdP, AuthZEN, ContX IQ, the Token Service (if configured), and the protected agent - common deployment failures are network-level, not IAG-level.

### 6. Verify the runtime path

Send a request through the gateway and confirm the [nine-step path](references/architecture.md) executes end-to-end. The expected HTTP responses are:

- `200` - request was authorized and forwarded.
- `400` - bad request.
- `401` - caller token missing or inactive (`Missing bearer token`, `Invalid token, missing subject`), or an incoming `X-IK-Token` that cannot be used (`Invalid delegated token, subject mismatch` / `missing subject`).
- `403` - caller authenticated but not allowed (subject, chain, or both) - `Authorization check failed`.
- `500` - internal error.
- `502` - upstream / gateway-side processing error, including an IdP or Token Service that cannot be reached or answers unreadably. A provider outage is reported as a fault, never counted as a denial.

Watch service logs (JSON to stdout) and audit records together - service logs explain *what IAG did*, audit records explain *what IAG decided*. A refused IdP or Token Service call is logged with the endpoint, the status, and a sanitized preview of the response body, so a wrong client secret and a broken endpoint no longer look the same.

### 7. Read the audit trail

Audit records are emitted as a separate stream from service logs. Configure delivery as either:

- **Webhook** - `audit.delivery: webhook`, `audit.http.url`, `audit.http.method` (`post` or `put`), auth `type` one of `no-auth`, `api-key`, `mTLS`.
- **File** - `audit.delivery: file`, `audit.file.storage_path`, `audit.file.format` (`csv`, `json`, `txt`), `audit.file.rotation_strategy` (`size`, `time`, `size-and-time`).

Either form can be buffered with `audit.async.buffer_size` (default `512`); buffered records are drained on shutdown, and a full queue drops records with a warning in the service log.

Each gateway record contains `decision` (`AUTHORIZED`, `NOT_AUTHORIZED`, or `ERROR` when the request could not be decided), `reason`, `subject`, `actor`, `actorsChain`, `action`, `service`, `timestamp`, `traceID`. The `traceID` correlates with the protected agent's logs and the upstream client. The Token Service writes records of the same shape for every exchange and introspection, with the decisions `TOKEN_EXCHANGED` / `EXCHANGE_REFUSED`, `INTROSPECTED` / `INTROSPECTED_INACTIVE` / `INTROSPECTION_REFUSED`, and `ERROR`, plus `tokenID` (the token's `jti`).

### 8. Exercise denial paths intentionally

To gain confidence that IAG is enforcing as expected, deliberately force `NOT_AUTHORIZED` outcomes:

- **Skip an agent in the chain** (e.g. call `retriever-iag` directly without the orchestrator in `act`).
- **Remove `workflow_name`** from one `INVOKES` relationship - ContX IQ stops returning that chain.
- **Delete the `CAN_TRIGGER` edge** between the subject and the workflow - AuthZEN says no.
- **Use a subject whose type is not in `JARVIS_AUTHZEN_SUBJECT_TYPES`** - no policy matches.
- **With the Token Service: replay an `X-IK-Token` with a different user's access token** - `401 Invalid delegated token, subject mismatch`.

Each should return `403 Forbidden` (or `401` for the token pairing) and produce a `NOT_AUTHORIZED` audit record with a useful `reason`.

## Outcome

When this skill has been applied successfully:

- A `Workflow` node, the relevant `Agent` nodes, and `INVOKES` edges (with `workflow_name`) exist in the IKG.
- A ContX IQ query returns the right `(workflow, agent_list)` pairs for each protected agent.
- One IAG instance runs in front of each protected agent with the right per-instance config, reporting healthy on `/healthz`.
- If the workflow has more than one hop, the Token Service runs, every gateway points at it, the project holds a Token Introspect configuration for each audience ITS issues for, and the forwarded request carries `Authorization` plus `X-IK-Token` with a chain that grows on every hop.
- A canonical successful prompt flows through the gateway chain and produces `AUTHORIZED` audit records on every IAG it touches (and `TOKEN_EXCHANGED` records at the Token Service).
- A canonical denial path produces `403 Forbidden` plus a `NOT_AUTHORIZED` audit record with a human-readable `reason`.

## Files in this skill

- [`references/architecture.md`](references/architecture.md) - the nine-step IAG request path, delegation-token delivery (`$token` vs `$ik_token`), multi-hop chains, and the IKG data shape.
- [`references/configuration.md`](references/configuration.md) - every IAG configuration section, field, and default, including `token_service`, health port, cache rules, and audit delivery.
- [`references/token-service.md`](references/token-service.md) - the IndyKite Token Service: endpoints, configuration (`service.base_url`, `idp`, `token_introspection`), config directory merging, audit decisions, deployment notes.
- [`references/troubleshooting.md`](references/troubleshooting.md) - common failure modes mapped to fixes.
- [`assets/config-template.yaml`](assets/config-template.yaml) - a starter gateway `config.yaml` to copy and adapt.
- [`assets/token-service-config-template.yaml`](assets/token-service-config-template.yaml) - a starter Token Service `config.yaml`.

## Agent-specific notes

This skill uses generic markdown instructions and works across all agents listed in the [README](../README.md). It does not require Claude Code hooks, Cursor `@`-mentions, Copilot workspace context, or any agent-specific feature. Network access (`curl`, the agent's web tools, or MCP) is needed only if the agent will call IndyKite APIs directly during a task; for setup-only work no special tools are required.

## References

- [IndyKite Token Service guide](https://developer.indykite.com/guides/guide-token-service) - endpoints, exchange and introspection contracts, configuration, platform trust via Token Introspect, audit records.
- [Protect an MCP server with Agent Gateway (tutorial)](https://developer.indykite.com/tutorials/tutorial-agent-gateway-mcp) - the rest of the gateway configuration, demonstrated in MCP proxy mode.
- [AuthZEN guide](https://developer.indykite.com/guides/guide-authzen) and [ContX IQ guide](https://developer.indykite.com/guides/guide-contx-iq) - how policies read `$token` and `$ik_token`.
- [`iag-mcp-demo` reference app](https://github.com/indykite/developer-hub/tree/master/a2a/iag-mcp-demo) - three A2A gateways (orchestrator, retriever, weather) plus an `mcp-iag` instance (`protocol: mcp`) protecting the IndyKite MCP server.
- [`iag-token-exchange` reference app](https://github.com/indykite/developer-hub/tree/master/a2a/iag-token-exchange) - runs the Token Service setup end to end (`token_service` on every gateway, `X-IK-Token` growing hop by hop).
- [`canbank` dataset](https://github.com/indykite/developer-hub/tree/master/canbank)
- [RFC 8693 OAuth 2.0 Token Exchange](https://www.rfc-editor.org/rfc/rfc8693) and [RFC 7662 Token Introspection](https://www.rfc-editor.org/rfc/rfc7662) - the two protocols the Token Service implements.
- A2A protocol - see the protected agent's vendor docs for the JSON-RPC shape IAG forwards. For MCP, IAG proxies MCP Streamable HTTP (`initialize`, `tools/list`, `tools/call`, …).

---
name: indykite-agent-gateway
description: Deploy and configure IndyKite Agent Gateway (IAG) in front of agent-to-agent (A2A) workflows. Use when wiring up A2A policy enforcement, modeling workflows in the IKG, or debugging IAG 401/403 responses.
---

# IndyKite Agent Gateway

The Indykite Agent Gateway (IAG) is a standalone service that protects exactly one AI agent. Deploy one IAG per protected agent. From the caller's perspective IAG appears as the Target; from the protected agent's perspective IAG appears as the Source. IAG is **not a generic reverse proxy** — it assumes the agents speak the **A2A protocol** and tracks A2A sessions so JSON-RPC streams flow correctly.

For each request IAG validates three things:

1. The **caller** (token introspection at the IdP).
2. The **workflow** (subject `CAN_TRIGGER` check via AuthZEN/KBAC).
3. The **delegation chain** (the request's `act` chain matches a chain modeled in the IKG).

## When to use

Activate this skill when the user:

- is deploying an agent-to-agent (A2A) workflow and wants policy enforcement in front of each agent;
- needs traceable user-to-agent delegation through OAuth token exchange and the `act` chain;
- is modeling a `Workflow` and `Agent` nodes with `INVOKES` relationships in the IndyKite Graph (IKG);
- is configuring `JARVIS_*` environment variables or a `config.yaml` for one or more IAG instances;
- is reading IAG audit records (`AUTHORIZED` / `NOT_AUTHORIZED`) and trying to explain a `403`;
- is reproducing or extending the [`iag-demo`](https://github.com/indykite/developer-hub/tree/master/a2a/iag-demo) reference application.

Do **not** activate this skill when the user:

- wants a generic HTTP reverse proxy or service mesh — IAG is A2A-specific;
- is asking about IndyKite features unrelated to A2A (token introspection alone, plain AuthZEN policies, ContX IQ queries outside of agent gating);
- is debugging the protected agent itself rather than the gateway in front of it.

## Prerequisites

Before any of the steps below will succeed, the user needs:

- An **IndyKite project** with AuthZEN / KBAC and ContX IQ enabled, plus a `Workflow` node and `Agent` nodes already modeled (or a plan to model them — see Step 1).
- An **OAuth2-compliant IdP** with introspect, client-credentials, and token-exchange endpoints. Set `IDP_BASE_URL` to the IdP base for the target environment.
- One **client_id / client_secret pair per protected agent**, registered with the IdP.
- A **ContX IQ query** that returns `(workflow, agent_list)` pairs for each protected agent — its `query_id` goes into IAG configuration.
- Docker (and Docker Compose) for the reference deployment, or a Kubernetes cluster for production.

If any of these are missing, stop and tell the user — IAG cannot run without them.

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

Capture this data through the **Capture API** (`POST /capture/v1/nodes`, `POST /capture/v1/relationships`), the IndyKite Hub UI, or an existing Terraform / identity pipeline — whichever the project already uses.

### 2. Wire the subject to the workflow

For every subject that is allowed to trigger the workflow, create the edge `(:User)-[:CAN_TRIGGER]->(:Workflow)` (or the equivalent AuthZEN relation). Without this edge IAG returns `403` at the AuthZEN check even if the chain is correct.

### 3. Build the ContX IQ query

The query must return `(workflow, agent_list)` pairs given a protected agent identifier, where `agent_list` is the ordered chain of agents the request must traverse. Save its `query_id` — IAG references it via `JARVIS_CONTX_IQ_QUERY_ID` (or `contx_iq.query_id`).

### 4. Configure each IAG instance

Pick one of the two configuration forms:

- **YAML config file** — pass with `--config=/app/config.yaml`. Best for production where configuration management is strict. See `assets/config-template.yaml` in this skill.
- **Environment variables** — keys use the `JARVIS_` prefix with underscores (e.g. `JARVIS_SERVICE_NAME`). Best for Docker Compose deployments where multiple IAG instances share a base image and override only per-agent fields.

The full set of sections is `service`, `identity_provider`, `protected_agent`, `authzen`, `contx_iq`, and `audit`. See `references/configuration.md` for every field and its default.

Per-instance values that **must** differ between IAG instances:

- `service.name` / `JARVIS_SERVICE_NAME`
- `service.port` / `JARVIS_SERVICE_PORT`
- `protected_agent.base_url` / `JARVIS_PROTECTED_AGENT_BASE_URL`
- `protected_agent.authentication.client_id` and `client_secret`

### 5. Deploy the IAG instances

For Docker Compose, follow the iag-demo pattern: one shared `iag-base-docker.yaml` plus one service per protected agent that overrides only the per-instance fields above. For Kubernetes, deploy each IAG as a standalone Pod for independent scaling, or as a sidecar to its protected agent for tighter coupling.

Verify that each IAG can reach the IdP, AuthZEN, ContX IQ, and the protected agent — common deployment failures are network-level, not IAG-level.

### 6. Verify the runtime path

Send a request through the gateway and confirm the [nine-step path](references/architecture.md) executes end-to-end. The expected HTTP responses are:

- `200` — request was authorized and forwarded.
- `400` — bad request.
- `401` — caller token missing or inactive.
- `403` — caller authenticated but not allowed (subject, chain, or both).
- `500` — internal error.
- `502` — upstream / gateway-side processing error.

Watch service logs (JSON to stdout) and audit records together — service logs explain *what IAG did*, audit records explain *what IAG decided*.

### 7. Read the audit trail

Audit records are emitted as a separate stream from service logs. Configure delivery as either:

- **Webhook** — `audit.delivery: webhook`, `audit.http.url`, optional auth (`mTLS`, `api-key`, `basic`, `no-auth`).
- **File** — `audit.delivery: file`, `audit.storage_path`, `audit.format` (`csv`, `json`, `txt`), `audit.rotation_strategy` (`size`, `time`, `size_and_time`).

Each record contains `decision`, `reason`, `subject`, `actor`, `action`, `service`, `timestamp`, `traceID`. The `traceID` correlates with the protected agent's logs and the upstream client.

### 8. Exercise denial paths intentionally

To gain confidence that IAG is enforcing as expected, deliberately force `NOT_AUTHORIZED` outcomes:

- **Skip an agent in the chain** (e.g. call `retriever-iag` directly without the orchestrator in `act`).
- **Remove `workflow_name`** from one `INVOKES` relationship — ContX IQ stops returning that chain.
- **Delete the `CAN_TRIGGER` edge** between the subject and the workflow — AuthZEN says no.
- **Use a subject whose type is not in `JARVIS_AUTHZEN_SUBJECT_TYPES`** — no policy matches.

Each should return `403 Forbidden` and produce a `NOT_AUTHORIZED` audit record with a useful `reason`.

## Outcome

When this skill has been applied successfully:

- A `Workflow` node, the relevant `Agent` nodes, and `INVOKES` edges (with `workflow_name`) exist in the IKG.
- A ContX IQ query returns the right `(workflow, agent_list)` pairs for each protected agent.
- One IAG instance runs in front of each protected agent with the right per-instance config.
- A canonical successful prompt flows through the gateway chain and produces `AUTHORIZED` audit records on every IAG it touches.
- A canonical denial path produces `403 Forbidden` plus a `NOT_AUTHORIZED` audit record with a human-readable `reason`.

## Files in this skill

- [`references/architecture.md`](references/architecture.md) — the nine-step IAG request path and the IKG data shape.
- [`references/configuration.md`](references/configuration.md) — every IAG configuration section, field, and default.
- [`references/troubleshooting.md`](references/troubleshooting.md) — common failure modes mapped to fixes.
- [`assets/config-template.yaml`](assets/config-template.yaml) — a starter `config.yaml` to copy and adapt.

## Agent-specific notes

This skill uses generic markdown instructions and works across all agents listed in the [README](../README.md). It does not require Claude Code hooks, Cursor `@`-mentions, Copilot workspace context, or any agent-specific feature. Network access (`curl`, the agent's web tools, or MCP) is needed only if the agent will call IndyKite APIs directly during a task; for setup-only work no special tools are required.

## References

- [IndyKite Agent Gateway documentation](https://docs.indykite.com/docs/agent-gateway)
- [`iag-demo` reference app](https://github.com/indykite/developer-hub/tree/master/a2a/iag-demo)
- [`canbank` dataset](https://github.com/indykite/developer-hub/tree/master/canbank)
- A2A protocol — see the protected agent's vendor docs for the JSON-RPC shape IAG forwards.

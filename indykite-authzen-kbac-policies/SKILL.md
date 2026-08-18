---
name: indykite-authzen-kbac-policies
description: Author and manage an IndyKite KBAC (Knowledge-Based Access Control) authorization policy - a single subject type, an actions list, a single resource type, and a Cypher condition over the IKG - through the Config API (`/configs/v1/authorization-policies` - create / read / list `?type=kbac` / update / delete, ETag-guarded). Covers `2.0-kbac` and `3.0-kbac` (raw Cypher, optional location routing for composite / data-residency IKGs). Use to write, publish, inspect, update, or delete a KBAC policy - e.g. "write a policy letting a Person PROVISION a Server within budget", "author a location-routed policy for our composite IKG". This authors the rule; it does NOT make decisions - for "can X do Y on Z?" use indykite-authzen-evaluation (single) or indykite-authzen-evaluations (batch), and to enumerate allowed actions/resources/subjects use indykite-authzen-search-action / -search-resource / -search-subject. This is KBAC, not ContX IQ - for CIQ read/write data policies use the indykite-ciq-* skills.
license: Apache-2.0
compatibility: Requires curl, bash 4+, and jq. Network access to the regional IndyKite REST API (eu.api.indykite.com or us.api.indykite.com) is required at runtime.
---

# IndyKite KBAC - authorization policies

KBAC (Knowledge-Based Access Control) is IndyKite's graph-driven authorization model. A KBAC **policy** declares *who* (`subject`) may perform *which* operations (`actions`) on *what* (`resource`), gated by a **condition** in Cypher (the Neo4j / openCypher graph query language) evaluated against the IKG: IndyKite's knowledge graph, a property-graph database. The policy itself renders no decision - it is the *rule* that the AuthZEN endpoints consult when a decision or search is requested.

This skill is the home of the KBAC **policy lifecycle**: writing the policy JSON and managing it through the Config API.

- A **policy** with `meta.policy_version` `"2.0-kbac"` (the default, platform-rewritten Cypher) or `"3.0-kbac"` (raw Cypher, usable on any IKG, with optional location routing for composite IKGs - see [Location-aware policies](#location-aware-policies-for-data-residency-30-kbac)), a single `subject.type`, an `actions` list, a single `resource.type`, and a `condition.cypher` that binds the reserved variables `subject` and `resource`.
- The **Config API** operations on `/configs/v1/authorization-policies`: create (`POST`), read (`GET /{id}` or by name), list (`GET ?project_id=…&type=kbac`), update (`PUT /{id}` with an `If-Match` ETag), and delete (`DELETE /{id}`).
- Publishing: a policy must be **ACTIVE** to participate in decisions; an `INACTIVE` or `DRAFT` policy is stored but ignored (`DRAFT` may even be invalid).

Once a policy is ACTIVE, the runtime AuthZEN skills evaluate it:

| Need                                            | Endpoint                     | Skill                                                                  |
|-------------------------------------------------|------------------------------|-----------------------------------------------------------------------|
| One yes/no decision                             | `/access/v1/evaluation`      | [`indykite-authzen-evaluation`](../indykite-authzen-evaluation/SKILL.md) |
| Many decisions at once                          | `/access/v1/evaluations`     | [`indykite-authzen-evaluations`](../indykite-authzen-evaluations/SKILL.md) |
| Actions a subject may perform on a resource     | `/access/v1/search/action`   | [`indykite-authzen-search-action`](../indykite-authzen-search-action/SKILL.md) |
| Resources a subject may act on, given an action | `/access/v1/search/resource` | [`indykite-authzen-search-resource`](../indykite-authzen-search-resource/SKILL.md) |
| Subjects allowed an action on a resource        | `/access/v1/search/subject`  | [`indykite-authzen-search-subject`](../indykite-authzen-search-subject/SKILL.md) |

## When to use

Activate this skill when the user wants to:

- **author** a KBAC authorization policy (`policy_version` `2.0-kbac` or `3.0-kbac`, `subject`, `actions`, `resource`, `condition.cypher`);
- **author a location-aware policy** for a composite / data-residency IKG (`3.0-kbac` with `USE graph.byName()` routing);
- **create / publish** a policy through the Config API, or flip it between `DRAFT` and `ACTIVE`;
- **read, list, update, or delete** existing KBAC policies (including listing with `?type=kbac` to separate them from CIQ policies);
- needs the policy that backs an [`indykite-authzen-evaluation`](../indykite-authzen-evaluation/SKILL.md) decision or the [`indykite-mcp-server`](../indykite-mcp-server/SKILL.md) `authzen_evaluate` tool.

Do **not** activate this skill when the user wants to:

- **make a decision** (one triple or many) - use [`indykite-authzen-evaluation`](../indykite-authzen-evaluation/SKILL.md) / [`indykite-authzen-evaluations`](../indykite-authzen-evaluations/SKILL.md);
- **enumerate** allowed actions, resources, or subjects - use the search skills [`-search-action`](../indykite-authzen-search-action/SKILL.md) / [`-search-resource`](../indykite-authzen-search-resource/SKILL.md) / [`-search-subject`](../indykite-authzen-search-subject/SKILL.md);
- author a **ContX IQ** read/write policy (the same `/configs/v1/authorization-policies` endpoint also serves CIQ, distinguished by `type=ciq`) - use the [`indykite-ciq-*`](../README.md) skills;
- **create / update / delete graph data** - a KBAC policy is a rule over the graph, not a write to it.

## Prerequisites

- An IndyKite **project**, and the project's GID in `PROJECT_GID` - it becomes the policy's `project_id`.
- A **Service Account token** with Config API write access, in `SERVICE_ACCOUNT_TOKEN` - used for every `/configs/v1/authorization-policies` call.
- A **subject type** for the policy - the node type making the request (`Person`, `Service`, `Namespace`, etc.). A policy is restricted to a single subject type; if two subject types need the same action, write two policies.
- For a `2.0-kbac` policy, the subject nodes must be **identity nodes** - ingested with `is_identity: true` (see [`indykite-capture-upsert-nodes`](../indykite-capture-upsert-nodes/SKILL.md)). A subject ingested as a plain entity never matches a `2.0-kbac` condition, so every decision quietly evaluates to `false`. `3.0-kbac` matches the subject by type and external ID only and does not require `is_identity`.
- The **IKG model** the condition will match (node types, properties, relationships). The policy can be authored before the data exists, but a decision over an empty graph is just `false`. For a populated IKG, the exact type and property spellings can be read from the Data Schema API ([`indykite-data-schema`](../indykite-data-schema/SKILL.md)).

If any of these are missing, say so before writing JSON.

## Steps

### 1. Frame the rule as (subject, actions, resource, condition)

Every KBAC policy answers one shape of question. Pin down all four parts before writing JSON:

| Part        | What it is                                                        | Example             |
|-------------|------------------------------------------------------------------|---------------------|
| `subject`   | The single node type making the request.                          | `Person`            |
| `actions`   | Action names the policy grants (1-5 per policy), conventionally uppercase verbs. | `["PROVISION"]`       |
| `resource`  | The single node type being acted on.                              | `Server`               |
| `condition` | A Cypher pattern + `WHERE` that must hold for a decision to be `true`. | price within budget |

Working example used throughout this skill:

> A `Person` (subject) may `PROVISION` a `Server` (resource) when the server's price is within a budget supplied at evaluation time.

### 2. Write the Cypher condition

The condition is a single `cypher` string. Two hard rules:

- It **must** bind a variable literally named `subject` (matching `subject.type`) and a variable literally named `resource` (matching `resource.type`). At decision time the AuthZEN request's `subject.id` / `resource.id` are matched against each node's `external_id`.
- Anything that varies per request is a **partial parameter** written `$name` in the `WHERE` clause; the decision call supplies it under `context.input_params` (without the `$`). Here the budget is `$max_price`.

```cypher
MATCH (subject:Person), (resource:Server)
WHERE resource.property.price <= $max_price
```

For relationship-based rules, match the relationship instead of (or in addition to) a property check:

```cypher
MATCH (subject:Person)-[:CAN_AFFORD]->(resource:Server)
```

For the full condition grammar (attribute references, multi-hop patterns, partial parameters, and the reserved `$subject_id` parameter that `2.0-kbac` binds to the user token's identity) see [`references/policy-reference.md`](references/policy-reference.md).

### 3. Assemble the policy and its create envelope

A KBAC policy has exactly five top-level keys: `meta` (with `meta.policy_version` set to `"2.0-kbac"` or `"3.0-kbac"`), `subject` (with `subject.type`), `actions`, `resource` (with `resource.type`), and `condition` (required `condition.cypher`; optional `condition.filter`, a graph-free pre-check over token claims and `input_params` - see [`references/policy-reference.md`](references/policy-reference.md#conditionfilter-optional)).

The Config API does not take the policy object directly - it takes a **create envelope** in which the policy is a **stringified** JSON value:

```json
{
  "name": "kbac-person-provision-server",
  "display_name": "Person: PROVISION a Server within budget",
  "description": "Allow a Person to PROVISION a Server when its price is within a budget supplied at evaluation time.",
  "project_id": "<project-gid>",
  "policy": "{ \"meta\": { \"policy_version\": \"2.0-kbac\" }, … }",
  "status": "ACTIVE"
}
```

For readability the asset [`assets/policy-provision-server.json`](assets/policy-provision-server.json) keeps `policy` as an object and `project_id` as a placeholder; the create step sets `project_id` and stringifies `policy` just before sending.

### 4. Create the policy

```text
POST <API_URL>/configs/v1/authorization-policies
```

Authenticate with the Service Account token: `Authorization: Bearer <SERVICE_ACCOUNT_TOKEN>`.

```bash
# set project_id and stringify only the `policy` field, then POST
jq --arg pid "$PROJECT_GID" '.project_id = $pid | .policy |= tojson' assets/policy-provision-server.json \
  | curl -X POST "$API_URL/configs/v1/authorization-policies" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $SERVICE_ACCOUNT_TOKEN" \
      -d @-
```

Or use the helper [`scripts/create-policy.sh`](scripts/create-policy.sh), which sets `project_id`, stringifies the `policy` field, pins the IndyKite host, and redacts the token under `--print`.

A `201 Created` returns the policy's `id` (a `gid:…`), audit fields (`create_time`, `created_by`, …), and an **ETag** header. Keep the `id` and ETag - update and delete need them. The policy participates in decisions only when its `status` is **ACTIVE**.

### 5. Read, list, update, and delete

The same `/configs/v1/authorization-policies` path manages the policy lifecycle (all with the Service Account token):

- **Read by id**: `GET /configs/v1/authorization-policies/{id}` - returns the full record, including the stringified `policy`, `status`, `tags`, audit fields, and the current ETag.
- **Read by name**: `GET /configs/v1/authorization-policies/{name}?location={PROJECT_GID}`.
- **List KBAC policies**: `GET /configs/v1/authorization-policies?project_id={PROJECT_GID}&type=kbac` - `type=kbac` returns only KBAC policies (use `type=ciq` for ContX IQ). List responses carry an empty `policy` string per item; read by id to get the body.
- **Update**: `PUT /configs/v1/authorization-policies/{id}` with header `If-Match: <etag>` and a body of the fields to change (`display_name`, `description`, `policy`, `status`, `tags`). Use this to publish (`status: "ACTIVE"`), deactivate (`status: "INACTIVE"`), or hold as `DRAFT`, or to revise the condition. A new ETag comes back.
- **Delete**: `DELETE /configs/v1/authorization-policies/{id}` with header `If-Match: <etag>`.

Full request/response shapes, response fields, and the ETag concurrency rules are in [`references/policy-reference.md`](references/policy-reference.md).

## Location-aware policies for data residency (`3.0-kbac`)

On a **composite IKG** - one logical graph spanning multiple constituent databases so that individual nodes can be stored in a specific location (see the [Data Residency guide](https://developer.indykite.com/guides/guide-data-residency)) - a `2.0-kbac` condition always evaluates against the **default database**, where located nodes exist only as lightweight proxies (external ID, type, and location - no property data). To evaluate a condition **inside a location constituent**, author the policy as `3.0-kbac`:

- The condition is **raw Cypher**: it runs as authored; the platform only pins `subject` / `resource` by type and external ID and appends the projection.
- Route with `USE graph.byName(...)` - **static** (`USE graph.byName('ikcomposite.db2')` always evaluates in that constituent) or **dynamic** (`USE graph.byName($region)`), where `$region` becomes a **location parameter**: at decision time the caller passes a *logical location* (a key of the project's `alias_mapping`, e.g. `"east"`) under `context.input_params`, and IndyKite translates it to the physical constituent just before execution. Callers never see or supply physical database names.
- `CALL { }` subqueries with inner `RETURN`s are allowed (each subquery can carry its own `USE` clause), so one condition can combine matches from several constituents. Both are rejected on `2.0-kbac`.
- The subject does **not** need to be an identity node: it is matched by type and external ID. Instead, when the decision request carries a user (OAuth bearer) token, the token's subject must be the same identity as the request's `subject`, or the call is denied with `bearer token subject differs from requested subject`.
- Conditions referencing **external (resolver-backed) properties** are rejected at creation (`external properties cannot be used in data-residency policies`); they are supported only in `2.0-kbac` conditions.

```json
{
  "meta": { "policy_version": "3.0-kbac" },
  "subject": { "type": "Person" },
  "actions": ["CAN_DRIVE"],
  "resource": { "type": "Car" },
  "condition": {
    "cypher": "USE graph.byName($region) MATCH (subject:Person)-[:OWNS]->(resource:Car)"
  }
}
```

The lifecycle is unchanged - same endpoint, create envelope, statuses, and ETag rules as steps 3-5; only the policy JSON differs. Note that `3.0-kbac` itself does not require a composite database - only `USE` routing (static or dynamic) does; a `3.0-kbac` policy without a `USE` clause evaluates on any IKG as plain raw Cypher. Residency support is **opt-in per policy**: existing `2.0-kbac` policies keep working, and a valid `2.0-kbac` condition can be carried over by switching `meta.policy_version` (as long as it references neither `$subject_id` nor external properties, both of which `3.0-kbac` rejects). The full 2.0 vs 3.0 comparison, authoring rules, and decision-time failure modes are in [`references/policy-reference.md`](references/policy-reference.md#30-kbac-raw-cypher-and-location-routing); a runnable create envelope is in [`assets/policy-location-routed.json`](assets/policy-location-routed.json).

## Outcome

When this skill has been applied successfully:

- A KBAC policy exists in the project with `policy_version` `"2.0-kbac"` (or `"3.0-kbac"` for location-aware conditions), a single `subject.type`, an `actions` list, a single `resource.type`, and a `condition.cypher` binding `subject` and `resource`.
- The policy is **ACTIVE** (or deliberately `INACTIVE` / `DRAFT`), and its `id` and current ETag are known so it can be read, updated, or deleted.
- Listing with `?type=kbac` shows the policy, and an [`indykite-authzen-evaluation`](../indykite-authzen-evaluation/SKILL.md) decision over a matching `(subject, action, resource)` triple reflects it.

## Files in this skill

- [`references/policy-reference.md`](references/policy-reference.md) - KBAC policy schema (`meta`, `subject`, `actions`, `resource`, `condition.cypher`, the optional `condition.filter`, partial parameters, multi-action and relationship variants), the 2.0 vs 3.0 version comparison with `3.0-kbac` routing and authoring rules, and the Config API lifecycle (create / read / list `?type=kbac` / update / delete, ETag concurrency, response fields).
- [`assets/policy-provision-server.json`](assets/policy-provision-server.json) - runnable KBAC policy create envelope for the `Person PROVISION Server` example.
- [`assets/policy-location-routed.json`](assets/policy-location-routed.json) - runnable `3.0-kbac` create envelope with dynamic `USE graph.byName($region)` location routing.
- [`scripts/create-policy.sh`](scripts/create-policy.sh) - Bash helper that sets `project_id`, stringifies `policy`, and POSTs the create envelope to `/configs/v1/authorization-policies` (host-pinned; `--print` to preview).

## Agent-specific notes

This skill uses generic markdown instructions and works across all agents listed in the [README](../README.md). The agent needs to be able to issue HTTP requests (`curl`, an HTTP client, or the IndyKite Terraform provider - see References). No Claude Code hooks, Cursor `@`-mentions, or Copilot workspace context are required.

## References

- [AuthZEN guide (developer hub)](https://developer.indykite.com/guides/guide-authzen)
- [Data Residency guide (developer hub)](https://developer.indykite.com/guides/guide-data-residency) - regions, composite databases, and `3.0-kbac` location routing
- [Dynamic authorization with Knowledge Graphs (developer hub)](https://developer.indykite.com/guides/guide-dynamic-authz)
- [Config API documentation - authorization policies](https://openapi.indykite.com/api-documentation-config#tag/authorization-policies)
- [Cypher query language manual (Neo4j; openCypher)](https://neo4j.com/docs/cypher-manual/current/) - the graph query language used in KBAC policy conditions over the IndyKite Knowledge Graph.
- [Music dataset tutorial (worked KBAC policy + AuthZEN example)](https://developer.indykite.com/tutorials/tutorial-music-dataset)
- [KBAC recipes (developer hub resources)](https://developer.indykite.com/resources)
- [KBAC 3.0: raw-Cypher policies with `CALL { }` subqueries and `USE` routing (authz-7)](https://developer.indykite.com/resources/authz-7)
- [KBAC 3.0: location-routed policies for data residency (authz-8)](https://developer.indykite.com/resources/authz-8)
- [IndyKite Terraform provider - `indykite_authorization_policy`](https://registry.terraform.io/providers/indykite/indykite/latest/docs)
- [Credentials guide](https://developer.indykite.com/guides/guide-credentials)

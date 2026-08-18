---
name: indykite-ciq-read
description: Author a read-only IndyKite ContX IQ (CIQ) policy plus its Knowledge Query, then run it via `POST /contx-iq/v1/execute`. Use when exposing IKG nodes, relationships, or aggregate values as a parameterized read query - no upserts, no deletes.
license: Apache-2.0
compatibility: Requires curl, bash 4+, and jq. Network access to the regional IndyKite REST API (eu.api.indykite.com or us.api.indykite.com) is required at runtime.
---

# IndyKite ContX IQ - read-only policy + Knowledge Query

ContX IQ (CIQ) is IndyKite's context-aware data layer over the IKG — IndyKite's knowledge graph, a property-graph database queried with Cypher (the Neo4j / openCypher graph query language). A CIQ **policy** declares *what graph elements may be touched* and *under what conditions*; a CIQ **Knowledge Query** declares *what to do with them*; an **execution** call runs the Knowledge Query at runtime with concrete parameter values.

This skill covers the **read-only** path:

- A policy whose `condition.cypher` matches nodes and relationships and whose `allowed_reads` whitelists the variables the Knowledge Query may return.
- A Knowledge Query that lists those variables in `nodes`, `relationships`, and/or `aggregate_values`.
- An `execute` call that supplies values for the policy's partial filters (`$variable`) and returns the rows.

`allowed_upserts` and `allowed_deletes` are intentionally **out of scope** here - leave them out entirely for read-only use.

## When to use

Activate this skill when the user:

- wants to **read** data from the IKG and shape the result through a CIQ policy + Knowledge Query;
- is building the `(workflow, agent_list)` query the [`indykite-agent-gateway`](../indykite-agent-gateway/SKILL.md) skill consumes from ContX IQ;
- is preparing a Knowledge Query that the [`indykite-mcp-server`](../indykite-mcp-server/SKILL.md) skill will run via `ciq_execute`;
- is debugging a read CIQ that returns nothing or `403`s for a subject that should have access.

Do **not** activate this skill when the user:

- needs to **create, update, or delete** nodes or relationships through CIQ - that uses `allowed_upserts` / `allowed_deletes` and `upsert_*` / `delete_*` Knowledge Query fields, which this skill leaves out for clarity;
- is calling **AuthZEN** for a yes/no authorization decision (use `authzen_evaluate` and the MCP skill);
- is calling the **External Data Resolver** to fetch data from an external API at query time (different feature).

## Prerequisites

- An IndyKite **project**, an **AppAgent**, and AppAgent **credentials** (the token that goes into `X-IK-ClientKey` at execution time).
- A **Service Account token** with Config API access, and the project's GID in `PROJECT_GID` (both used to *create* the policy and Knowledge Query).
- The **IKG already populated** with the nodes and relationships the policy will match. CIQ only filters and projects; it does not seed data.
- A **subject type** to authenticate against - `Person`, `User`, `_Application`, etc. CIQ policies are restricted to a single subject type, so if you need two subjects, plan for two policies.

If any of these are missing, stop and tell the user - fixing them first is much cheaper than debugging an opaque CIQ rejection.

## Steps

### 1. Pick the subject and the Cypher pattern

**Subject type** - pick one. The schema is identical across both choices; only `subject.type`, the filter, and the execute-time auth differ:

| Subject           | Use when                                                       | Auth at execute time                                | Filter convention                              |
|-------------------|----------------------------------------------------------------|------------------------------------------------------|------------------------------------------------|
| `_Application`    | System-side / ETL / catalog work; no user in the loop.          | `X-IK-ClientKey` only.                               | `subject.external_id = $_appId` (reserved).    |
| `Person` / `User` | The authenticated user is performing the operation themselves.  | `X-IK-ClientKey` + `Authorization: Bearer <token>`.  | `subject.external_id = $token.sub`.            |

A policy is restricted to a single subject type - if both should be allowed, write two policies. The subject's variable in `cypher` is conventionally named `subject`. The runnable example below uses `Person`; an `_Application` variant - for example, a service reading the catalog - differs only in `subject.type`, the filter, and the execute headers.

**Cypher pattern** - the `MATCH` / `OPTIONAL MATCH` clauses naming every node and relationship the query will touch. Each one must have a **variable name** so the policy and Knowledge Query can reference it. If the exact node types, relationship types, or property spellings in the project's IKG are unknown, read them from the Data Schema API first ([`indykite-data-schema`](../indykite-data-schema/SKILL.md)) - a typoed name silently matches nothing.

Working example used throughout this skill:

> A `Person` (subject) `OWNS` `Car`s. Given a person's `external_id`, return the cars they own.

```cypher
MATCH (subject:Person)-[r:OWNS]->(car:Car)
```

Variables: `subject`, `r`, `car`.

### 2. Author the read-only CIQ policy

Build the policy JSON. For a read-only policy you need three things and only three things:

- `meta.policy_version` - currently `1.0-ciq`.
- `subject.type` - the chosen subject type.
- `condition.cypher` and (optionally) `condition.filter` - the pattern and any filters. Use `$varname` to mark **partial filters** that will be supplied at execution time.
- `allowed_reads` - list every variable the Knowledge Query will be allowed to return. Use `<var>.*` to allow all properties of a node/relationship, or `<var>.property.<name>` for a single property.

Skip `allowed_upserts` and `allowed_deletes` entirely - omitting them is the supported way to forbid writes.

A complete read-only policy for the running example: see [`assets/policy-read-cars.json`](assets/policy-read-cars.json).

Create it through the Config API:

```bash
# set the current project_id, and stringify only the `policy` field, before POSTing
jq --arg pid "$PROJECT_GID" '.project_id = $pid | .policy |= tojson' assets/policy-read-cars.json \
  | curl -X POST "$API_URL/configs/v1/authorization-policies" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $SERVICE_ACCOUNT_TOKEN" \
      -d @-
```

A `201 Created` returns the policy's `id` (GID). Export it as `POLICY_ID` - the Knowledge Query create injects it into `policy_id`.

For the full schema (every operator, every attribute pattern, what `token_filter` is for) see [`references/policy-reference.md`](references/policy-reference.md).

### 3. Create the Knowledge Query

A read-only Knowledge Query references the policy and lists what to return. The four read-relevant fields are:

- `nodes` - node variables (or `<var>.property.<name>`) to include in the response.
- `relationships` - relationship variables to include.
- `aggregate_values` - variables produced by aggregate functions in `cypher` (e.g. `COLLECT(...) AS xs` → `"xs"`).
- `batch_read` - set to `true` only when you expect a result set big enough to risk the default timeout; raises the timeout to 5 minutes.

A complete Knowledge Query for the running example: see [`assets/knowledge-query-read-cars.json`](assets/knowledge-query-read-cars.json).

Create it through the Config API (with `POLICY_ID` set to the policy's GID from the previous step):

```bash
# set the current project_id and policy_id, and stringify only the `query` field, before POSTing
jq --arg pid "$PROJECT_GID" --arg polid "$POLICY_ID" '.project_id = $pid | .policy_id = $polid | .query |= tojson' assets/knowledge-query-read-cars.json \
  | curl -X POST "$API_URL/configs/v1/knowledge-queries" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $SERVICE_ACCOUNT_TOKEN" \
      -d @-
```

A `201 Created` returns the Knowledge Query's `id` (GID). This is what `execute` (and the MCP `ciq_execute` tool) will reference.

Schema details for every Knowledge Query field, including `upsert_*` and `delete_*` (omitted for the read case): [`references/knowledge-query-reference.md`](references/knowledge-query-reference.md).

### 4. Execute the query

The execute endpoint runs the Knowledge Query at runtime with concrete parameter values:

```text
POST <API_URL>/contx-iq/v1/execute
```

Authentication:

- Always: `X-IK-ClientKey: <AppAgent-credentials-token>`.
- If `subject.type` is **not** `_Application`: also `Authorization: Bearer <user-access-token>`. The token's `sub` is the subject identifier.
- If `subject.type` **is** `_Application`: the reserved `$_appId` parameter is auto-filled from the application's `external_id`; do not pass it in `input_params`.

Request:

```json
{
  "id": "<knowledge_query_gid_or_name>",
  "input_params": {
    "person_external_id": "alice"
  }
}
```

A runnable shell helper: [`scripts/execute.sh`](scripts/execute.sh).

The full execute reference (auth combinations, response shape, error semantics) lives in [`references/execution-reference.md`](references/execution-reference.md).

### 5. Read the response and verify

The response shape is:

```json
{
  "data": [
    { "nodes": { "<var>.<attr>": "<value>", ... } },
    { "relationships": { ... } }
  ]
}
```

One row per match, with `nodes` keyed `<var>.<attr>` and `relationships` keyed similarly. If the policy or Knowledge Query whitelists a variable but the IKG has nothing matching, the data array is simply empty.

If the response is **not** what you expected, walk through this check list before changing the policy:

1. **Variable in the response?** It must appear in both the policy's `allowed_reads.nodes` / `relationships` / `aggregate_values` *and* the Knowledge Query's `nodes` / `relationships` / `aggregate_values`. The intersection is what gets returned.
2. **Filter actually firing?** A typo in `attribute` (e.g. `subject.external_id` vs. `person.external_id`) silently matches nothing. Re-read the [attribute naming conventions](references/policy-reference.md#attribute-naming-conventions).
3. **Subject set up correctly?** For non-`_Application` subjects, the Bearer token's `sub` is the subject identifier; without a token the subject is not bound and many policies match nothing.
4. **Data actually in the IKG?** Run a probe query against the same shape but with `IS NOT NULL` filters to confirm the data exists.

## Outcome

When this skill has been applied successfully:

- A read-only CIQ policy exists in the project; it has a single `subject.type`, a `cypher` pattern with named variables, optional partial filters, and an `allowed_reads` whitelist - but no `allowed_upserts` or `allowed_deletes`.
- A Knowledge Query references that policy and lists exactly the variables it should return in `nodes` / `relationships` / `aggregate_values`.
- `POST /contx-iq/v1/execute` (or the MCP `ciq_execute` tool) returns the expected rows for valid `input_params` and an empty `data` array for valid-but-non-matching ones.
- The same Knowledge Query can be invoked from the [`indykite-mcp-server`](../indykite-mcp-server/SKILL.md) skill via `ciq_execute` without further changes.

## Files in this skill

- [`references/policy-reference.md`](references/policy-reference.md) - read-only policy schema, operators, attribute naming, partial filters, `token_filter` and step-up advice.
- [`references/knowledge-query-reference.md`](references/knowledge-query-reference.md) - Knowledge Query schema, including the read-only fields used here and a one-line description of every other field for context.
- [`references/execution-reference.md`](references/execution-reference.md) - `POST /contx-iq/v1/execute` request and response shape, auth combinations, common error codes.
- [`assets/policy-read-cars.json`](assets/policy-read-cars.json) - runnable read-only policy for the `Person -[:OWNS]-> Car` example.
- [`assets/knowledge-query-read-cars.json`](assets/knowledge-query-read-cars.json) - matching Knowledge Query.
- [`scripts/execute.sh`](scripts/execute.sh) - Bash helper that posts to `/contx-iq/v1/execute` with the right headers.

## Agent-specific notes

This skill uses generic markdown instructions and works across all agents listed in the [README](../README.md). The agent needs to be able to issue HTTP requests (`curl`, an HTTP client, or the IndyKite Terraform provider - see References). No Claude Code hooks, Cursor `@`-mentions, or Copilot workspace context are required.

## References

- [ContX IQ guide (developer hub)](https://developer.indykite.com/guides/guide-contx-iq)
- [Config API documentation](https://openapi.indykite.com/api-documentation-config)
- [Cypher query language manual (Neo4j; openCypher)](https://neo4j.com/docs/cypher-manual/current/) - the graph query language used in CIQ policy and Knowledge Query conditions over the IndyKite Knowledge Graph.
- [IndyKite Terraform provider - `indykite_authorization_policy` and `indykite_knowledge_query`](https://registry.terraform.io/providers/indykite/indykite/latest/docs)
- [Credentials guide](https://developer.indykite.com/guides/guide-credentials)
- [External Data Resolver guide (out of scope here, but useful for follow-on work)](https://developer.indykite.com/guides/guide-external-data-resolver)

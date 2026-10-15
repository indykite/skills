---
name: indykite-data-schema
description: Read the observed data schema of the IndyKite Knowledge Graph (IKG) via the Data Schema REST API (`GET /data-schema/v1/`) - a JGFv2 document listing every node type with its properties, value-type tallies, and labels, plus every (source, relation, target) relationship combination, with occurrence counts but never the data itself. Use before authoring Cypher for CIQ Knowledge Queries or KBAC policies (exact type and property spellings), to verify a Capture ingest landed, to detect schema drift, or to give an agent the graph's vocabulary - "what does our IKG look like?". Not for reading graph data (indykite-ciq-read), writing it (indykite-capture-* / indykite-ciq-*), or authoring policies (indykite-authzen-kbac-policies).
license: Apache-2.0
compatibility: Requires curl, bash 4+, and jq. Network access to the regional IndyKite REST API (eu.api.indykite.com or us.api.indykite.com) is required at runtime.
---

# IndyKite Data Schema - read the IKG's observed schema

The IndyKite Knowledge Graph (IKG) has no up-front schema definition step: the schema *emerges* from the data ingested through the Capture API or ContX IQ upserts. The platform tracks that emergent schema - which node types exist, which properties they carry with which value types, and how the types are connected - and exposes it through the **Data Schema API** as a JSON Graph Format (JGF) v2 document.

It is a schema-level view only: type names, property names, observed value types, and occurrence counts. It never returns the data itself, so it is safe to hand to tools and agents that should know the graph's *vocabulary* without seeing its contents.

## When to use

Activate this skill when the user wants to:

- discover the **exact spelling** of node types, relationship types, and property names before authoring Cypher - a CIQ policy or Knowledge Query ([`indykite-ciq-read`](../indykite-ciq-read/SKILL.md) and siblings) or a KBAC policy ([`indykite-authzen-kbac-policies`](../indykite-authzen-kbac-policies/SKILL.md)) references them literally, and a policy written against `givenName` matches nothing when the data was ingested as `given_name`;
- **verify an ingest** - after a Capture batch, one GET confirms the expected types and properties landed and the counts sanity-check the volume (a `"Perosn"` typo shows up immediately as a surprise node type);
- **detect schema drift or data-quality issues** - a property reporting `STRING NOT NULL: 4980, INTEGER NOT NULL: 20` means an upstream source started sending the wrong type;
- get a **meta-model overview** of the project's graph ("what does our IKG look like?") for onboarding, visualization, or impact analysis before a cleanup.

Do **not** activate this skill when the user:

- wants the **data itself** - that is a ContX IQ read ([`indykite-ciq-read`](../indykite-ciq-read/SKILL.md));
- wants to **write** nodes, relationships, or properties (the [`indykite-capture-*`](../README.md) and [`indykite-ciq-*`](../README.md) skills);
- expects to **define or enforce** a schema - the response is descriptive, observed from ingested data; it is not a constraint definition you author.

## Prerequisites

- An IndyKite **project** with an **AppAgent** holding the **`ReadDataSchema` API permission** and AppAgent **credentials** (the token that goes into `X-IK-ClientKey`) - see the [Credentials guide](https://developer.indykite.com/guides/guide-credentials). Without the permission the call fails with `401` and the message `insufficient API access level for appAgent`; add it to the agent's `api_permissions` (see the [Environment guide](https://developer.indykite.com/guides/guide-environment)).
- **Data already ingested.** A project with an empty IKG returns `404 Not Found` with `errors: ["data schema not found for the specified project"]` - that is the normal "nothing ingested yet" answer, not a failure of this skill.
- **A minute of patience after a write.** The schema is maintained from the graph's change stream and persisted at most once a minute, and only when something changed, so a Capture call is reflected within about a minute rather than instantly. Right after a large batch, read again a minute later before concluding that a type is missing or a count is short.

This endpoint is the only way to read the schema. The platform keeps it as nodes of its own in the graph, and a ContX IQ policy condition that tries to match them is refused when the policy is saved (see the [`indykite-ciq-read`](../indykite-ciq-read/SKILL.md) policy reference for the blocked labels).

## Steps

### 1. Call the endpoint

```text
GET <API_URL>/data-schema/v1/
```

where `API_URL` is `https://eu.api.indykite.com` or `https://us.api.indykite.com`, matching the project's region, and the trailing slash is part of the path. Authentication is the AppAgent credential in the `X-IK-ClientKey` header, as is, without any prefix. There are no parameters - the project is derived from the credential.

A runnable shell helper builds the authenticated request: [`scripts/read-schema.sh`](scripts/read-schema.sh) — run with `--print` to preview the `curl` (host-pinned; token redacted).

### 2. Read the response

The response is one `graph` object:

- `graph.directed` - always `true`.
- `graph.metadata` - `created_at` and `updated_at` timestamps of the schema.
- `graph.nodes` - a **map keyed by node type**. Each entry's `metadata` holds `node_count`, a `properties` map (keyed by property name), `system_labels` (a list of `{ name, count }`; every node type carries `Resource`, and identity nodes also carry `DigitalTwin`), and `user_defined_labels` (a list of the labels given at ingest, each `{ name, count }`, or `null` when there are none - check for `null` before iterating).
- `graph.edges` - one entry per **(source type, relation, target type)** combination: the `source` and `target` node types, the `relation` (relationship type), `directed`, and `metadata` with the edge `count` and its `properties` map.

Each `properties` entry describes one property: how many times it occurs (`count`) and the observed value types with per-type tallies (`types`), using the names the graph store reports - the common scalar ones are `STRING NOT NULL`, `INTEGER NOT NULL`, `FLOAT NOT NULL`, `BOOLEAN NOT NULL`, and `ZONED DATETIME NOT NULL`, and an array-valued property reports a list type, so a name outside those five is not by itself drift; node properties additionally carry a `metadata` map with the same statistics for their provenance fields (relationship properties have none). Trimmed example - one node type and one edge from a vehicle-rental graph:

```json
{
  "graph": {
    "nodes": {
      "Car": {
        "metadata": {
          "node_count": 1,
          "properties": {
            "manufacturer": { "count": 1, "types": [ { "type": "STRING NOT NULL", "count": 1 } ] },
            "seats":        { "count": 1, "types": [ { "type": "INTEGER NOT NULL", "count": 1 } ] }
          },
          "system_labels": [ { "name": "Resource", "count": 1 } ],
          "user_defined_labels": null
        }
      }
    },
    "edges": [
      {
        "source": "Person", "target": "Car", "relation": "CAN_DRIVE", "directed": true,
        "metadata": { "count": 1, "properties": { "valid_until": { "count": 1, "types": [ { "type": "STRING NOT NULL", "count": 1 } ] } } }
      }
    ]
  }
}
```

The full field reference, a complete example response, and `jq` recipes for common questions ("which node types exist?", "which properties does `Person` have?") are in [`references/data-schema-reference.md`](references/data-schema-reference.md).

### 3. Use what it tells you

- **Copy spellings, don't retype them.** Take node types, relationship types, and property names verbatim from the response into Cypher patterns, KBAC conditions, Capture payloads, and AuthZEN `subject.type` / `resource.type` fields.
- **Check the edge direction.** `graph.edges` records the stored `source` → `target` direction; a Cypher pattern drawn in the opposite direction matches nothing.
- **Treat mixed type tallies as a red flag.** More than one entry in a property's `types` list usually means an upstream source changed what it sends.
- **Diff over time.** `graph.metadata.updated_at` tells you when the schema was last persisted; it moves about once a minute while data flows (counts change even when the shape does not) and stays put while the graph is idle. Polling and diffing the response is a cheap monitor for upstream changes.
- **Count before you delete.** The per-property and per-edge counts show how much data a cleanup would touch before you call the Capture delete endpoints.

## Outcome

When this skill has been applied successfully:

- `GET /data-schema/v1/` returns the project's observed schema as a JGFv2 `graph` document - node types with property and label statistics, and one `edges` entry per (source, relation, target) combination - or a `404` that correctly identifies an empty project.
- Downstream Cypher (CIQ policies and Knowledge Queries, KBAC conditions) and Capture payloads use type and property spellings taken from the response instead of guesses.

## Files in this skill

- [`references/data-schema-reference.md`](references/data-schema-reference.md) - endpoint, auth, full JGFv2 response field reference, complete example response, error codes, and `jq` recipes.
- [`scripts/read-schema.sh`](scripts/read-schema.sh) - Bash helper that GETs `/data-schema/v1/` with the right header (host-pinned; `--print` to preview).

## Agent-specific notes

This skill uses generic markdown instructions and works across all agents listed in the [README](../README.md). The agent needs to be able to issue HTTP requests (`curl` or an HTTP client). No Claude Code hooks, Cursor `@`-mentions, or Copilot workspace context are required.

## References

- [IKG Data Schema guide (developer hub)](https://developer.indykite.com/guides/guide-data-schema)
- [Data Schema API documentation](https://openapi.indykite.com/api-documentation/dataschema)
- [Credentials guide](https://developer.indykite.com/guides/guide-credentials)
- [JSON Graph Format (JGF)](https://jsongraphformat.info/) - the response format.

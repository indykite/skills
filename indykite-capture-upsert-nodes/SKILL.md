---
name: indykite-capture-upsert-nodes
description: Build the request-body JSON for the IndyKite Capture API batch node upsert (`POST /capture/v1/nodes`) - a `nodes` array (1-250 per request) of entities, each with `external_id`, `type`, optional `is_identity` / `labels` / `location`, and typed `properties` (values, external-data references, and per-property metadata such as source, assurance level, and verified time). Use when the user wants to ingest or update entities in the IndyKite Knowledge Graph (IKG) - "add these people and cars to the graph", "upsert this customer with verified email metadata", "prepare a nodes payload for the Capture API". Produces a ready-to-send JSON file; sending it is optional. Not for connecting nodes (indykite-capture-upsert-relationships), removing them (indykite-capture-delete-nodes), or CIQ policy-mediated writes (indykite-ciq-create-node).
license: Apache-2.0
compatibility: Requires curl, bash 4+, and jq for the bundled helper script; authoring the JSON payload itself needs no tools. Network access to the regional IndyKite REST API (eu.api.indykite.com or us.api.indykite.com) is required at runtime.
---

# IndyKite Capture - upsert nodes

The Capture API is the direct ingestion surface of the IndyKite Knowledge Graph (IKG): it writes entities (**nodes**) and connections (**relationships**) without any policy in between. This skill builds the request body for the **batch node upsert** endpoint - the JSON file is the deliverable, ready to be POSTed by any application, CI job, or shell helper:

```text
POST <API_URL>/capture/v1/nodes
```

Upsert semantics: a node is identified by its (`type`, `external_id`) pair - posting the same pair again **updates** the node instead of creating a duplicate.

The [MCP server](../indykite-mcp-server/SKILL.md) does not currently expose Capture endpoints (its tools cover AuthZEN decisions and CIQ queries); the JSON bodies this skill produces are for direct REST use and remain valid if Capture tools are added later.

## When to use

Activate this skill when the user wants to:

- **ingest entities** into the IKG - people, organizations, devices, resources - as graph nodes;
- **update** an existing node's properties (same `type` + `external_id`);
- attach **property metadata** (source, assurance level, verified time) or an **external-data reference** (`external_value`) to a property;
- prepare graph data that [`indykite-authzen-*`](../indykite-authzen-kbac-policies/SKILL.md) policies or [`indykite-ciq-*`](../indykite-ciq-read/SKILL.md) queries will later match.

Do **not** activate this skill to:

- **connect** nodes - use [`indykite-capture-upsert-relationships`](../indykite-capture-upsert-relationships/SKILL.md);
- **remove** nodes, properties, or metadata - use the [`indykite-capture-delete-*`](../indykite-capture-delete-nodes/SKILL.md) skills;
- write through a **CIQ policy + Knowledge Query** (parameterized, authorization-gated writes) - use [`indykite-ciq-create-node`](../indykite-ciq-create-node/SKILL.md); the Capture API writes directly, with no policy involved;
- **read** graph data - use [`indykite-ciq-read`](../indykite-ciq-read/SKILL.md).

## Prerequisites

- An IndyKite **project** with an **AppAgent** whose credentials are configured for the calling application ([Credentials guide](https://developer.indykite.com/guides/guide-credentials)).
- The **graph model**: node types, their identifying `external_id` scheme, and the property names downstream queries and policies will reference.

## Steps

### 1. Model the nodes

For each entity decide:

| Field         | Required | Meaning                                                                                    |
|---------------|----------|--------------------------------------------------------------------------------------------|
| `external_id` | yes      | Your identifier for the node (1-256 chars). Upserts key on (`type`, `external_id`).        |
| `type`        | yes      | Node type / label, e.g. `Person`, `Car` (2-64 chars).                                      |
| `is_identity` | no       | `true` marks an identity node (a person or other actor, e.g. an AuthZEN subject); omit or `false` for plain entities. |
| `labels`      | no       | Extra labels beyond `type`.                                                                 |
| `location`    | no       | Composite-IKG routing only: a logical location (an `alias_mapping` key, 2-32 chars). Omit on a regular IKG. |
| `properties`  | no       | Array of typed values - see step 2.                                                        |

### 2. Write the properties

Each property is `{ "type": ..., "value": ... }`; `value` is a string, integer, float, boolean, or an array of those. Two optional extensions:

- **`metadata`** - provenance for the single property: `source` (string), `assurance_level` (1, 2, or 3), `verified_time` (RFC 3339 timestamp), `custom_metadata` (object). Used e.g. by [trust scoring](https://developer.indykite.com/guides/guide-trust-score).
- **`external_value`** - instead of `value`, a data reference resolved at query time by an [External Data Resolver](https://developer.indykite.com/guides/guide-external-data-resolver), so the actual data never lives in the IKG.

### 3. Assemble the request body

The body is one JSON object: `{ "nodes": [ … ] }` with 1-250 nodes per request (batch larger sets into multiple files). A ready example - two `Person` identities and a `Car`, one property carrying metadata: [`assets/nodes-vehicle-rental.json`](assets/nodes-vehicle-rental.json).

```json
{
  "nodes": [
    {
      "external_id": "millicent",
      "type": "Person",
      "is_identity": true,
      "properties": [
        { "type": "email", "value": "millicent@email.com" },
        {
          "type": "name",
          "value": "Millicent Contextsworth",
          "metadata": { "assurance_level": 1, "source": "Some Source", "verified_time": "2026-04-10T06:28:16Z" }
        }
      ]
    },
    { "external_id": "kitt", "type": "Car", "properties": [ { "type": "manufacturer", "value": "pontiac" } ] }
  ]
}
```

This file is the deliverable - any HTTP-capable application can send it.

### 4. Send it (optional)

The endpoint authenticates the **calling application** (its AppAgent credentials). Which credential goes in which request header is covered by the [Credentials guide](https://developer.indykite.com/guides/guide-credentials).

A runnable shell helper builds the authenticated request: [`scripts/capture.sh`](scripts/capture.sh) — run with `--print` to preview the `curl` (host-pinned; token redacted).

### 5. Read the results

A `200` returns one result per node, in order:

```json
{ "results": [ { "id": "gid:…" }, { "id": "gid:…" } ] }
```

`400` (with `errors[]`) means a malformed body - commonly a missing `external_id` or `type`. Field shapes, batch limits, and error semantics: [`references/capture-reference.md`](references/capture-reference.md). To verify the ingest at schema level (types, property names, counts), read the schema back with [`indykite-data-schema`](../indykite-data-schema/SKILL.md).

## Outcome

- A valid `{ "nodes": [ … ] }` JSON file exists, each node carrying `external_id`, `type`, and its properties.
- If sent, the nodes exist in the IKG (created or updated by `external_id`), visible to CIQ queries, KBAC decisions, and the Hub Explorer.

## Files in this skill

- [`references/capture-reference.md`](references/capture-reference.md) - full field reference (node, property, metadata, external_value, location), batch limits, and error semantics.
- [`assets/nodes-vehicle-rental.json`](assets/nodes-vehicle-rental.json) - ready request body: two `Person` identities and a `Car` with property metadata.
- [`scripts/capture.sh`](scripts/capture.sh) - Bash helper that POSTs a body file to `/capture/v1/nodes` (host-pinned; `--print` to preview).

## Agent-specific notes

This skill uses generic markdown instructions and works across all agents listed in the [README](../README.md). The agent needs to be able to write a JSON file; sending it additionally requires HTTP access (`curl` or any HTTP client).

## References

- [Capture API reference (OpenAPI)](https://openapi.indykite.com/)
- [Ingest data into the IKG (developer hub resource)](https://developer.indykite.com/resources/capture-1)
- [Data Residency guide](https://developer.indykite.com/guides/guide-data-residency) - `location` routing on composite IKGs
- [External Data Resolver guide](https://developer.indykite.com/guides/guide-external-data-resolver) - `external_value` data references
- [Trust Score guide](https://developer.indykite.com/guides/guide-trust-score) - how property metadata feeds scoring
- [Credentials guide](https://developer.indykite.com/guides/guide-credentials)

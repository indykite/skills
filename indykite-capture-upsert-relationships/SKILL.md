---
name: indykite-capture-upsert-relationships
description: Build the request-body JSON for the IndyKite Capture API batch relationship upsert (`POST /capture/v1/relationships`) - a `relationships` array (1-250 per request), each entry connecting a `source` node to a `target` node (by `external_id` + `type`) with a relationship `type` and optional typed `properties`; on composite IKGs setting `use_global_db` to `true` routes cross-location relationships to the global constituent. Use when the user wants to connect existing entities in the IndyKite Knowledge Graph (IKG) - "link millicent OWNS kitt", "wire these contracts to their vehicles", "prepare a relationships payload for the Capture API". Produces a ready-to-send JSON file; sending it is optional. Not for creating the nodes themselves (indykite-capture-upsert-nodes), removing relationships (indykite-capture-delete-relationships), or CIQ policy-mediated writes (indykite-ciq-create-relationship).
license: Apache-2.0
compatibility: Requires curl, bash 4+, and jq for the bundled helper script; authoring the JSON payload itself needs no tools. Network access to the regional IndyKite REST API (eu.api.indykite.com or us.api.indykite.com) is required at runtime.
---

# IndyKite Capture - upsert relationships

The Capture API is the direct ingestion surface of the IndyKite Knowledge Graph (IKG). This skill builds the request body for the **batch relationship upsert** endpoint - connecting nodes that already exist (or are being ingested alongside, see [`indykite-capture-upsert-nodes`](../indykite-capture-upsert-nodes/SKILL.md)):

```text
POST <API_URL>/capture/v1/relationships
```

Each entry names a `source` node, a `target` node (each by `external_id` + `type`), and the relationship `type` - e.g. `Person(millicent) -[OWNS]-> Car(kitt)`. The JSON file is the deliverable, ready to be POSTed by any application.

The [MCP server](../indykite-mcp-server/SKILL.md) does not currently expose Capture endpoints; the JSON bodies this skill produces are for direct REST use and remain valid if Capture tools are added later.

## When to use

Activate this skill when the user wants to:

- **connect** two entities in the IKG with a typed relationship (`OWNS`, `ACCEPTED`, `COVERS`, `HAS`, …);
- attach **properties** to a relationship (e.g. a `status` or a timestamp);
- build the relationship structure that [`indykite-authzen-*`](../indykite-authzen-kbac-policies/SKILL.md) policy conditions or [`indykite-ciq-*`](../indykite-ciq-read/SKILL.md) queries traverse.

Do **not** activate this skill to:

- **create the nodes** being connected - use [`indykite-capture-upsert-nodes`](../indykite-capture-upsert-nodes/SKILL.md);
- **remove** relationships or their properties - use [`indykite-capture-delete-relationships`](../indykite-capture-delete-relationships/SKILL.md) / [`indykite-capture-delete-relationship-properties`](../indykite-capture-delete-relationship-properties/SKILL.md);
- write through a **CIQ policy + Knowledge Query** - use [`indykite-ciq-create-relationship`](../indykite-ciq-create-relationship/SKILL.md); the Capture API writes directly, with no policy involved.

## Prerequisites

- An IndyKite **project** with an **AppAgent** whose credentials are configured for the calling application ([Credentials guide](https://developer.indykite.com/guides/guide-credentials)).
- The **endpoint nodes**: each `source`/`target` is referenced by (`type`, `external_id`) - ingest them first (or in the same session) with [`indykite-capture-upsert-nodes`](../indykite-capture-upsert-nodes/SKILL.md).

## Steps

### 1. Model the relationships

For each connection decide:

| Field        | Required | Meaning                                                            |
|--------------|----------|---------------------------------------------------------------------|
| `source`     | yes      | `{ "external_id": …, "type": … }` of the outgoing node.            |
| `target`     | yes      | `{ "external_id": …, "type": … }` of the incoming node.            |
| `type`       | yes      | Relationship type, conventionally an uppercase verb (max 128 chars). |
| `properties` | no       | Array of `{ "type": …, "value": … }` (string / integer / float / boolean or arrays of those); `external_value` data references are also accepted. |

### 2. Assemble the request body

One JSON object: `{ "relationships": [ … ] }`, 1-250 entries per request. On a **composite IKG**, add top-level `"use_global_db": true` - relationships can connect nodes living in different locations, so they are stored in the global constituent alongside the proxy nodes ([Data Residency guide](https://developer.indykite.com/guides/guide-data-residency)). Omit it on a regular IKG.

A ready example: [`assets/relationships-vehicle-rental.json`](assets/relationships-vehicle-rental.json).

```json
{
  "relationships": [
    {
      "source": { "external_id": "millicent", "type": "Person" },
      "target": { "external_id": "kitt", "type": "Car" },
      "type": "OWNS",
      "properties": [ { "type": "status", "value": "active" } ]
    }
  ]
}
```

### 3. Send it (optional)

The endpoint authenticates the **calling application** (its AppAgent credentials). Which credential goes in which request header is covered by the [Credentials guide](https://developer.indykite.com/guides/guide-credentials).

A runnable shell helper builds the authenticated request: [`scripts/capture.sh`](scripts/capture.sh) — run with `--print` to preview the `curl` (host-pinned; token redacted).

### 4. Read the results

A `200` returns one result per relationship, in order: `{ "results": [ { "id": "gid:…" } ] }`. Field shapes and error semantics: [`references/capture-reference.md`](references/capture-reference.md).

## Outcome

- A valid `{ "relationships": [ … ] }` JSON file exists, each entry naming `source`, `target`, and `type`.
- If sent, the relationships exist in the IKG between the referenced nodes, traversable by CIQ queries and KBAC policy conditions.

## Files in this skill

- [`references/capture-reference.md`](references/capture-reference.md) - full field reference (relationship, node reference, properties, `use_global_db`), batch limits, and error semantics.
- [`assets/relationships-vehicle-rental.json`](assets/relationships-vehicle-rental.json) - ready request body: `OWNS` (with a property) and `CAN_DRIVE` relationships.
- [`scripts/capture.sh`](scripts/capture.sh) - Bash helper that POSTs a body file to `/capture/v1/relationships` (host-pinned; `--print` to preview).

## Agent-specific notes

This skill uses generic markdown instructions and works across all agents listed in the [README](../README.md). The agent needs to be able to write a JSON file; sending it additionally requires HTTP access (`curl` or any HTTP client).

## References

- [Capture API reference (OpenAPI)](https://openapi.indykite.com/)
- [Ingest data into the IKG (developer hub resource)](https://developer.indykite.com/resources/capture-1)
- [Data Residency guide](https://developer.indykite.com/guides/guide-data-residency) - `use_global_db` on composite IKGs
- [Credentials guide](https://developer.indykite.com/guides/guide-credentials)

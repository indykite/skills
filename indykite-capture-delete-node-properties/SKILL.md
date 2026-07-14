---
name: indykite-capture-delete-node-properties
description: Build the request-body JSON for the IndyKite Capture API batch node-property delete (`POST /capture/v1/nodes/properties/delete`) - a `nodes` array (1-250 per request) where each entry names a node (`external_id` + `type`) and the `property_types` (1-250 names) to strip from it; the node itself survives. On composite IKGs an optional per-node `location` routes the delete. Use when the user wants to remove specific properties from entities in the IndyKite Knowledge Graph (IKG) - "drop the email property from millicent", "strip these deprecated fields from all listed devices", "prepare a property-delete payload for the Capture API". Produces a ready-to-send JSON file; sending it is optional. Not for deleting whole nodes (indykite-capture-delete-nodes), property metadata only (indykite-capture-delete-node-property-metadata), relationship properties (indykite-capture-delete-relationship-properties), or CIQ policy-mediated deletes (indykite-ciq-delete).
license: Apache-2.0
compatibility: Requires curl, bash 4+, and jq for the bundled helper script; authoring the JSON payload itself needs no tools. Network access to the regional IndyKite REST API (eu.api.indykite.com or us.api.indykite.com) is required at runtime.
---

# IndyKite Capture - delete node properties

This skill builds the request body for the Capture API's **batch node-property delete** endpoint - removing named properties from nodes in the IndyKite Knowledge Graph (IKG) while keeping the nodes themselves:

```text
POST <API_URL>/capture/v1/nodes/properties/delete
```

Each entry names one node by (`type`, `external_id`) and lists the `property_types` to strip. The JSON file is the deliverable, ready to be POSTed by any application.

The [MCP server](../indykite-mcp-server/SKILL.md) does not currently expose Capture endpoints; the JSON bodies this skill produces are for direct REST use and remain valid if Capture tools are added later.

## When to use

Activate this skill when the user wants to:

- **remove specific properties** from a node - PII minimization, dropping deprecated fields, correcting a wrong ingest - while keeping the node;
- strip the same property set from **many nodes** in one call.

Do **not** activate this skill to:

- delete the **whole node** - use [`indykite-capture-delete-nodes`](../indykite-capture-delete-nodes/SKILL.md);
- remove only a property's **metadata** (value survives) - use [`indykite-capture-delete-node-property-metadata`](../indykite-capture-delete-node-property-metadata/SKILL.md);
- remove **relationship** properties - use [`indykite-capture-delete-relationship-properties`](../indykite-capture-delete-relationship-properties/SKILL.md);
- overwrite a property with a new value - just re-upsert it with [`indykite-capture-upsert-nodes`](../indykite-capture-upsert-nodes/SKILL.md);
- delete through a **CIQ policy + Knowledge Query** - use [`indykite-ciq-delete`](../indykite-ciq-delete/SKILL.md).

## Prerequisites

- An IndyKite **project** with an **AppAgent** whose credentials are configured for the calling application ([Credentials guide](https://developer.indykite.com/guides/guide-credentials)).
- The (`type`, `external_id`) of each node and the exact **property names** to remove.

## Steps

### 1. List the nodes and the properties to strip

| Field            | Required | Constraints  | Meaning                                                  |
|------------------|----------|--------------|-----------------------------------------------------------|
| `external_id`    | yes      | 1-256 chars  | The node's caller-owned identifier.                      |
| `type`           | yes      | 2-64 chars   | The node's type.                                         |
| `property_types` | yes      | 1-250 names  | The property names to delete from this node.             |
| `location`       | no       | 2-32 chars   | Composite IKG only: the node's logical location. Omit on a regular IKG. |

### 2. Assemble the request body

One JSON object: `{ "nodes": [ … ] }`, 1-250 entries per request. A ready example: [`assets/delete-node-properties.json`](assets/delete-node-properties.json).

```json
{
  "nodes": [
    {
      "external_id": "millicent",
      "type": "Person",
      "property_types": ["email", "given_name"]
    }
  ]
}
```

This file is the deliverable - any HTTP-capable application can send it.

### 3. Send it (optional)

The endpoint authenticates the **calling application** (its AppAgent credentials). Which credential goes in which request header is covered by the [Credentials guide](https://developer.indykite.com/guides/guide-credentials).

A runnable shell helper builds the authenticated request: [`scripts/capture.sh`](scripts/capture.sh) — run with `--print` to preview the `curl` (host-pinned; token redacted). Deletion is destructive: preview with `--print`, and confirm the property list, before sending.

### 4. Read the results

A `200` returns one result per node, in order: `{ "results": [ { "id": "gid:…" } ] }`. Field shapes and error semantics: [`references/capture-reference.md`](references/capture-reference.md).

## Outcome

- A valid `{ "nodes": [ … ] }` body exists, each entry naming a node and its `property_types` to remove.
- If sent, the listed properties are gone from those nodes; the nodes, their other properties, and their relationships are untouched.

## Files in this skill

- [`references/capture-reference.md`](references/capture-reference.md) - field reference, batch limits, and error semantics.
- [`assets/delete-node-properties.json`](assets/delete-node-properties.json) - ready request body stripping two properties from a `Person`.
- [`scripts/capture.sh`](scripts/capture.sh) - Bash helper that POSTs a body file to `/capture/v1/nodes/properties/delete` (host-pinned; `--print` to preview).

## Agent-specific notes

This skill uses generic markdown instructions and works across all agents listed in the [README](../README.md). The agent needs to be able to write a JSON file; sending it additionally requires HTTP access (`curl` or any HTTP client).

## References

- [Capture API reference (OpenAPI)](https://openapi.indykite.com/)
- [Data Residency guide](https://developer.indykite.com/guides/guide-data-residency) - location-aware deletes on composite IKGs
- [Credentials guide](https://developer.indykite.com/guides/guide-credentials)

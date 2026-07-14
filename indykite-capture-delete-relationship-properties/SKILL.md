---
name: indykite-capture-delete-relationship-properties
description: Build the request-body JSON for the IndyKite Capture API batch relationship-property delete (`POST /capture/v1/relationships/properties/delete`) - a `relationships` array (1-250 per request), each entry identifying a relationship by `source` node, `target` node (each `external_id` + `type`), and relationship `type`, plus the `property_types` (1-250 names) to strip from it; the relationship itself survives. On composite IKGs setting the top-level `use_global_db` field to `true` targets the global constituent. Use when the user wants to remove properties from edges in the IndyKite Knowledge Graph (IKG) - "drop the status property from millicent's OWNS edge", "prepare a relationship-property-delete payload for the Capture API". Produces a ready-to-send JSON file; sending it is optional. Not for deleting the relationship (indykite-capture-delete-relationships), node properties (indykite-capture-delete-node-properties), or CIQ policy-mediated deletes (indykite-ciq-delete).
license: Apache-2.0
compatibility: Requires curl, bash 4+, and jq for the bundled helper script; authoring the JSON payload itself needs no tools. Network access to the regional IndyKite REST API (eu.api.indykite.com or us.api.indykite.com) is required at runtime.
---

# IndyKite Capture - delete relationship properties

This skill builds the request body for the Capture API's **batch relationship-property delete** endpoint - removing named properties from relationships in the IndyKite Knowledge Graph (IKG) while keeping the relationships themselves:

```text
POST <API_URL>/capture/v1/relationships/properties/delete
```

Each entry identifies one relationship (`source`, `target`, `type`) and lists the `property_types` to strip from it. The JSON file is the deliverable, ready to be POSTed by any application.

The [MCP server](../indykite-mcp-server/SKILL.md) does not currently expose Capture endpoints; the JSON bodies this skill produces are for direct REST use and remain valid if Capture tools are added later.

## When to use

Activate this skill when the user wants to:

- **remove properties from an edge** - e.g. drop a stale `status` or timestamp from an `OWNS` relationship - while keeping the connection;
- strip the same property set from **many relationships** in one call.

Do **not** activate this skill to:

- delete the **relationship itself** - use [`indykite-capture-delete-relationships`](../indykite-capture-delete-relationships/SKILL.md);
- remove **node** properties - use [`indykite-capture-delete-node-properties`](../indykite-capture-delete-node-properties/SKILL.md);
- overwrite a property with a new value - re-upsert the relationship with [`indykite-capture-upsert-relationships`](../indykite-capture-upsert-relationships/SKILL.md);
- delete through a **CIQ policy + Knowledge Query** - use [`indykite-ciq-delete`](../indykite-ciq-delete/SKILL.md).

## Prerequisites

- An IndyKite **project** with an **AppAgent** whose credentials are configured for the calling application ([Credentials guide](https://developer.indykite.com/guides/guide-credentials)).
- For each target: the relationship's `source` and `target` (`type`, `external_id`) pairs, its `type`, and the exact **property names** to remove.

## Steps

### 1. List the relationships and the properties to strip

| Field            | Required | Meaning                                                     |
|------------------|----------|--------------------------------------------------------------|
| `source`         | yes      | `{ "external_id": …, "type": … }` of the outgoing node.     |
| `target`         | yes      | `{ "external_id": …, "type": … }` of the incoming node.     |
| `type`           | yes      | The relationship type (max 128 chars).                       |
| `property_types` | yes      | 1-250 property names to delete from this relationship.       |

### 2. Assemble the request body

One JSON object: `{ "relationships": [ … ] }`, 1-250 entries per request. On a **composite IKG**, add top-level `"use_global_db": true` to target relationships stored in the global constituent ([Data Residency guide](https://developer.indykite.com/guides/guide-data-residency)); omit it on a regular IKG. A ready example: [`assets/delete-relationship-properties.json`](assets/delete-relationship-properties.json).

```json
{
  "relationships": [
    {
      "source": { "external_id": "millicent", "type": "Person" },
      "target": { "external_id": "kitt", "type": "Car" },
      "type": "OWNS",
      "property_types": ["status"]
    }
  ]
}
```

This file is the deliverable - any HTTP-capable application can send it.

### 3. Send it (optional)

The endpoint authenticates the **calling application** (its AppAgent credentials). Which credential goes in which request header is covered by the [Credentials guide](https://developer.indykite.com/guides/guide-credentials).

A runnable shell helper builds the authenticated request: [`scripts/capture.sh`](scripts/capture.sh) — run with `--print` to preview the `curl` (host-pinned; token redacted). Deletion is destructive: preview with `--print`, and confirm the property list, before sending.

### 4. Read the results

A `200` returns one result per entry, in order: `{ "results": [ { "id": "gid:…" } ] }`. Field shapes and error semantics: [`references/capture-reference.md`](references/capture-reference.md).

## Outcome

- A valid `{ "relationships": [ … ] }` body exists, each entry identifying a relationship and its `property_types` to remove.
- If sent, the listed properties are gone from those relationships; the relationships and their endpoint nodes are untouched.

## Files in this skill

- [`references/capture-reference.md`](references/capture-reference.md) - field reference, `use_global_db` behavior, batch limits, and error semantics.
- [`assets/delete-relationship-properties.json`](assets/delete-relationship-properties.json) - ready request body stripping `status` from an `OWNS` edge.
- [`scripts/capture.sh`](scripts/capture.sh) - Bash helper that POSTs a body file to `/capture/v1/relationships/properties/delete` (host-pinned; `--print` to preview).

## Agent-specific notes

This skill uses generic markdown instructions and works across all agents listed in the [README](../README.md). The agent needs to be able to write a JSON file; sending it additionally requires HTTP access (`curl` or any HTTP client).

## References

- [Capture API reference (OpenAPI)](https://openapi.indykite.com/)
- [Data Residency guide](https://developer.indykite.com/guides/guide-data-residency) - `use_global_db` on composite IKGs
- [Credentials guide](https://developer.indykite.com/guides/guide-credentials)

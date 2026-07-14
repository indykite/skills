---
name: indykite-capture-delete-node-property-metadata
description: Build the request-body JSON for the IndyKite Capture API batch property-metadata delete (`POST /capture/v1/nodes/properties/metadata/delete`) - a `nodes` array (1-250 per request) where each entry names a node (`external_id` + `type`), one `property_type`, and the `metadata_fields` (1-250, e.g. source, assurance_level, verified_time, custom_metadata) to remove from that property; the property and its value survive. Use when the user wants to strip provenance metadata in the IndyKite Knowledge Graph (IKG) - "remove the assurance level from millicent's name property", "clear the verified_time metadata on these records", "prepare a metadata-delete payload for the Capture API". Produces a ready-to-send JSON file; sending it is optional. Not for deleting the property itself (indykite-capture-delete-node-properties), whole nodes (indykite-capture-delete-nodes), or attaching metadata (indykite-capture-upsert-nodes re-upserts it).
license: Apache-2.0
compatibility: Requires curl, bash 4+, and jq for the bundled helper script; authoring the JSON payload itself needs no tools. Network access to the regional IndyKite REST API (eu.api.indykite.com or us.api.indykite.com) is required at runtime.
---

# IndyKite Capture - delete node property metadata

This skill builds the request body for the Capture API's **batch property-metadata delete** endpoint - removing metadata fields (provenance such as `source`, `assurance_level`, `verified_time`, `custom_metadata`) from a node property in the IndyKite Knowledge Graph (IKG), while keeping the property and its value:

```text
POST <API_URL>/capture/v1/nodes/properties/metadata/delete
```

Each entry names one node by (`type`, `external_id`), one `property_type` on it, and the `metadata_fields` to strip. The JSON file is the deliverable, ready to be POSTed by any application.

The [MCP server](../indykite-mcp-server/SKILL.md) does not currently expose Capture endpoints; the JSON bodies this skill produces are for direct REST use and remain valid if Capture tools are added later.

## When to use

Activate this skill when the user wants to:

- **strip provenance metadata** from a property - e.g. drop a stale `verified_time` or an obsolete `source` - without touching the property value;
- clean metadata that feeds [trust scoring](https://developer.indykite.com/guides/guide-trust-score) so a factor no longer contributes.

Do **not** activate this skill to:

- delete the **property itself** (value and all) - use [`indykite-capture-delete-node-properties`](../indykite-capture-delete-node-properties/SKILL.md);
- delete the **whole node** - use [`indykite-capture-delete-nodes`](../indykite-capture-delete-nodes/SKILL.md);
- **set or update** metadata - re-upsert the property with a `metadata` object via [`indykite-capture-upsert-nodes`](../indykite-capture-upsert-nodes/SKILL.md).

## Prerequisites

- An IndyKite **project** with an **AppAgent** whose credentials are configured for the calling application ([Credentials guide](https://developer.indykite.com/guides/guide-credentials)).
- For each target: the node's (`type`, `external_id`), the **property name**, and the **metadata field names** to remove.

## Steps

### 1. List the targets

| Field             | Required | Constraints | Meaning                                                       |
|-------------------|----------|-------------|----------------------------------------------------------------|
| `external_id`     | yes      | 1-256 chars | The node's caller-owned identifier.                           |
| `type`            | yes      | 2-64 chars  | The node's type.                                              |
| `property_type`   | yes      | string      | The single property whose metadata is being removed.         |
| `metadata_fields` | yes      | 1-250 names | Metadata fields to remove - the fields a property's `metadata` object can carry are `source`, `assurance_level`, `verified_time`, and `custom_metadata`. |
| `location`        | no       | 2-32 chars  | Composite IKG only: the node's logical location. Omit on a regular IKG. |

One entry addresses **one property**; to clean several properties on the same node, add one entry per property.

### 2. Assemble the request body

One JSON object: `{ "nodes": [ … ] }`, 1-250 entries per request. A ready example: [`assets/delete-property-metadata.json`](assets/delete-property-metadata.json).

```json
{
  "nodes": [
    {
      "external_id": "millicent",
      "type": "Person",
      "property_type": "name",
      "metadata_fields": ["assurance_level", "source"]
    }
  ]
}
```

This file is the deliverable - any HTTP-capable application can send it.

### 3. Send it (optional)

The endpoint authenticates the **calling application** (its AppAgent credentials). Which credential goes in which request header is covered by the [Credentials guide](https://developer.indykite.com/guides/guide-credentials).

A runnable shell helper builds the authenticated request: [`scripts/capture.sh`](scripts/capture.sh) — run with `--print` to preview the `curl` (host-pinned; token redacted).

### 4. Read the results

A `200` returns one result per entry, in order: `{ "results": [ { "id": "gid:…" } ] }`. Field shapes and error semantics: [`references/capture-reference.md`](references/capture-reference.md).

## Outcome

- A valid `{ "nodes": [ … ] }` body exists, each entry naming a node, one `property_type`, and the `metadata_fields` to remove.
- If sent, those metadata fields are gone from the property; the property value, the node, and everything else are untouched.

## Files in this skill

- [`references/capture-reference.md`](references/capture-reference.md) - field reference, the metadata field names, batch limits, and error semantics.
- [`assets/delete-property-metadata.json`](assets/delete-property-metadata.json) - ready request body stripping `assurance_level` and `source` from a property.
- [`scripts/capture.sh`](scripts/capture.sh) - Bash helper that POSTs a body file to `/capture/v1/nodes/properties/metadata/delete` (host-pinned; `--print` to preview).

## Agent-specific notes

This skill uses generic markdown instructions and works across all agents listed in the [README](../README.md). The agent needs to be able to write a JSON file; sending it additionally requires HTTP access (`curl` or any HTTP client).

## References

- [Capture API reference (OpenAPI)](https://openapi.indykite.com/)
- [Trust Score guide](https://developer.indykite.com/guides/guide-trust-score) - how property metadata feeds scoring
- [Credentials guide](https://developer.indykite.com/guides/guide-credentials)

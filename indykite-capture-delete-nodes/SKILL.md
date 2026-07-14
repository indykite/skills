---
name: indykite-capture-delete-nodes
description: Build the request-body JSON for the IndyKite Capture API batch node delete (`POST /capture/v1/nodes/delete`) - a `nodes` array (1-250 per request) of `{external_id, type}` references, each removing one whole node from the IndyKite Knowledge Graph (IKG); on composite IKGs an optional per-node `location` routes the delete to the right constituent. Use when the user wants to remove entities - "delete these test people from the graph", "remove the car kitt", "prepare a node-delete payload for the Capture API". Produces a ready-to-send JSON file; sending it is optional. Not for removing individual properties (indykite-capture-delete-node-properties), property metadata (indykite-capture-delete-node-property-metadata), relationships (indykite-capture-delete-relationships), or CIQ policy-mediated deletes (indykite-ciq-delete).
license: Apache-2.0
compatibility: Requires curl, bash 4+, and jq for the bundled helper script; authoring the JSON payload itself needs no tools. Network access to the regional IndyKite REST API (eu.api.indykite.com or us.api.indykite.com) is required at runtime.
---

# IndyKite Capture - delete nodes

This skill builds the request body for the Capture API's **batch node delete** endpoint - removing whole nodes from the IndyKite Knowledge Graph (IKG):

```text
POST <API_URL>/capture/v1/nodes/delete
```

Each entry references one node by (`type`, `external_id`) - the same pair that identified it at upsert. The JSON file is the deliverable, ready to be POSTed by any application.

The [MCP server](../indykite-mcp-server/SKILL.md) does not currently expose Capture endpoints; the JSON bodies this skill produces are for direct REST use and remain valid if Capture tools are added later.

## When to use

Activate this skill when the user wants to:

- **remove entities** from the IKG - cleanup of test data, offboarding a record, retiring a device;
- undo a batch ingested with [`indykite-capture-upsert-nodes`](../indykite-capture-upsert-nodes/SKILL.md).

Do **not** activate this skill to:

- remove **individual properties** (node survives) - use [`indykite-capture-delete-node-properties`](../indykite-capture-delete-node-properties/SKILL.md);
- remove **property metadata** (property survives) - use [`indykite-capture-delete-node-property-metadata`](../indykite-capture-delete-node-property-metadata/SKILL.md);
- remove **relationships** - use [`indykite-capture-delete-relationships`](../indykite-capture-delete-relationships/SKILL.md);
- delete through a **CIQ policy + Knowledge Query** (parameterized, authorization-gated deletes) - use [`indykite-ciq-delete`](../indykite-ciq-delete/SKILL.md).

## Prerequisites

- An IndyKite **project** with an **AppAgent** whose credentials are configured for the calling application ([Credentials guide](https://developer.indykite.com/guides/guide-credentials)).
- The (`type`, `external_id`) pairs of the nodes to remove.

## Steps

### 1. List the nodes to delete

| Field         | Required | Constraints | Meaning                                            |
|---------------|----------|-------------|-----------------------------------------------------|
| `external_id` | yes      | 1-256 chars | The node's caller-owned identifier.                |
| `type`        | yes      | 2-64 chars  | The node's type.                                   |
| `location`    | no       | 2-32 chars  | Composite IKG only: the node's logical location (an `alias_mapping` key). Deleting a located node removes both its data node and its global proxy. Omit on a regular IKG. |

### 2. Assemble the request body

One JSON object: `{ "nodes": [ … ] }`, 1-250 entries per request. A ready example: [`assets/delete-nodes.json`](assets/delete-nodes.json).

```json
{
  "nodes": [
    { "external_id": "kitt", "type": "Car" },
    { "external_id": "ryan", "type": "Person" }
  ]
}
```

This file is the deliverable - any HTTP-capable application can send it.

### 3. Send it (optional)

The endpoint authenticates the **calling application** (its AppAgent credentials). Which credential goes in which request header is covered by the [Credentials guide](https://developer.indykite.com/guides/guide-credentials).

A runnable shell helper builds the authenticated request: [`scripts/capture.sh`](scripts/capture.sh) — run with `--print` to preview the `curl` (host-pinned; token redacted). Deletion is destructive: preview with `--print`, and confirm the target list, before sending.

### 4. Read the results

A `200` returns one result per node, in order: `{ "results": [ { "id": "gid:…" } ] }`. Field shapes and error semantics: [`references/capture-reference.md`](references/capture-reference.md).

## Outcome

- A valid `{ "nodes": [ … ] }` delete body exists, each entry a (`type`, `external_id`) reference.
- If sent, the nodes are gone from the IKG and no longer appear in CIQ query results or KBAC decisions.

## Files in this skill

- [`references/capture-reference.md`](references/capture-reference.md) - field reference, composite-IKG `location` behavior, batch limits, and error semantics.
- [`assets/delete-nodes.json`](assets/delete-nodes.json) - ready request body removing a `Car` and a `Person`.
- [`scripts/capture.sh`](scripts/capture.sh) - Bash helper that POSTs a body file to `/capture/v1/nodes/delete` (host-pinned; `--print` to preview).

## Agent-specific notes

This skill uses generic markdown instructions and works across all agents listed in the [README](../README.md). The agent needs to be able to write a JSON file; sending it additionally requires HTTP access (`curl` or any HTTP client).

## References

- [Capture API reference (OpenAPI)](https://openapi.indykite.com/)
- [Data Residency guide](https://developer.indykite.com/guides/guide-data-residency) - location-aware deletes on composite IKGs
- [Credentials guide](https://developer.indykite.com/guides/guide-credentials)

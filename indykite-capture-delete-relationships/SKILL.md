---
name: indykite-capture-delete-relationships
description: Build the request-body JSON for the IndyKite Capture API batch relationship delete (`POST /capture/v1/relationships/delete`) - a `relationships` array (1-250 per request), each entry identifying a relationship by `source` node, `target` node (each `external_id` + `type`), and relationship `type`; on composite IKGs setting the top-level `use_global_db` field to `true` targets relationships stored in the global constituent. Use when the user wants to disconnect entities in the IndyKite Knowledge Graph (IKG) - "remove the CAN_DRIVE link between ryan and kitt", "unlink these contracts from their vehicles", "prepare a relationship-delete payload for the Capture API". Produces a ready-to-send JSON file; sending it is optional. The endpoint nodes survive. Not for deleting nodes (indykite-capture-delete-nodes), removing only relationship properties (indykite-capture-delete-relationship-properties), creating relationships (indykite-capture-upsert-relationships), or CIQ policy-mediated deletes (indykite-ciq-delete).
license: Apache-2.0
compatibility: Requires curl, bash 4+, and jq for the bundled helper script; authoring the JSON payload itself needs no tools. Network access to the regional IndyKite REST API (eu.api.indykite.com or us.api.indykite.com) is required at runtime.
---

# IndyKite Capture - delete relationships

This skill builds the request body for the Capture API's **batch relationship delete** endpoint - removing typed connections between nodes in the IndyKite Knowledge Graph (IKG) while leaving the nodes in place:

```text
POST <API_URL>/capture/v1/relationships/delete
```

Each entry identifies one relationship the same way it was created: `source` node, `target` node, and relationship `type`. The JSON file is the deliverable, ready to be POSTed by any application.

The [MCP server](../indykite-mcp-server/SKILL.md) does not currently expose Capture endpoints; the JSON bodies this skill produces are for direct REST use and remain valid if Capture tools are added later.

## When to use

Activate this skill when the user wants to:

- **disconnect** two entities - revoke an `OWNS` / `CAN_DRIVE` / `ACCEPTED` edge - while keeping both nodes;
- undo a batch created with [`indykite-capture-upsert-relationships`](../indykite-capture-upsert-relationships/SKILL.md).

Do **not** activate this skill to:

- delete the **nodes** themselves - use [`indykite-capture-delete-nodes`](../indykite-capture-delete-nodes/SKILL.md);
- remove only a relationship's **properties** (edge survives) - use [`indykite-capture-delete-relationship-properties`](../indykite-capture-delete-relationship-properties/SKILL.md);
- **create** relationships - use [`indykite-capture-upsert-relationships`](../indykite-capture-upsert-relationships/SKILL.md);
- delete through a **CIQ policy + Knowledge Query** - use [`indykite-ciq-delete`](../indykite-ciq-delete/SKILL.md).

## Prerequisites

- An IndyKite **project** with an **AppAgent** whose credentials are configured for the calling application ([Credentials guide](https://developer.indykite.com/guides/guide-credentials)).
- For each relationship: the `source` and `target` (`type`, `external_id`) pairs and the relationship `type`.

## Steps

### 1. List the relationships to delete

| Field    | Required | Meaning                                                     |
|----------|----------|--------------------------------------------------------------|
| `source` | yes      | `{ "external_id": …, "type": … }` of the outgoing node.     |
| `target` | yes      | `{ "external_id": …, "type": … }` of the incoming node.     |
| `type`   | yes      | The relationship type to remove between them (max 128 chars). |

### 2. Assemble the request body

One JSON object: `{ "relationships": [ … ] }`, 1-250 entries per request. On a **composite IKG**, add top-level `"use_global_db": true` to delete relationships stored in the global constituent ([Data Residency guide](https://developer.indykite.com/guides/guide-data-residency)); omit it on a regular IKG. A ready example: [`assets/delete-relationships.json`](assets/delete-relationships.json).

```json
{
  "relationships": [
    {
      "source": { "external_id": "ryan", "type": "Person" },
      "target": { "external_id": "kitt", "type": "Car" },
      "type": "CAN_DRIVE"
    }
  ]
}
```

This file is the deliverable - any HTTP-capable application can send it.

### 3. Send it (optional)

The endpoint authenticates the **calling application** (its AppAgent credentials). Which credential goes in which request header is covered by the [Credentials guide](https://developer.indykite.com/guides/guide-credentials).

A runnable shell helper builds the authenticated request: [`scripts/capture.sh`](scripts/capture.sh) — run with `--print` to preview the `curl` (host-pinned; token redacted). Deletion is destructive: preview with `--print`, and confirm the edge list, before sending.

### 4. Read the results

A `200` returns one result per relationship, in order: `{ "results": [ { "id": "gid:…" } ] }`. Field shapes and error semantics: [`references/capture-reference.md`](references/capture-reference.md).

## Outcome

- A valid `{ "relationships": [ … ] }` delete body exists, each entry naming `source`, `target`, and `type`.
- If sent, those relationships are gone from the IKG - policy conditions and queries that traversed them no longer match - while both endpoint nodes remain.

## Files in this skill

- [`references/capture-reference.md`](references/capture-reference.md) - field reference, `use_global_db` behavior, batch limits, and error semantics.
- [`assets/delete-relationships.json`](assets/delete-relationships.json) - ready request body removing a `CAN_DRIVE` edge.
- [`scripts/capture.sh`](scripts/capture.sh) - Bash helper that POSTs a body file to `/capture/v1/relationships/delete` (host-pinned; `--print` to preview).

## Agent-specific notes

This skill uses generic markdown instructions and works across all agents listed in the [README](../README.md). The agent needs to be able to write a JSON file; sending it additionally requires HTTP access (`curl` or any HTTP client).

## References

- [Capture API reference (OpenAPI)](https://openapi.indykite.com/)
- [Data Residency guide](https://developer.indykite.com/guides/guide-data-residency) - `use_global_db` on composite IKGs
- [Credentials guide](https://developer.indykite.com/guides/guide-credentials)

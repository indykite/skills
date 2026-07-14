# Capture API - node upsert reference

Request/response shapes for the batch node upsert endpoint, per the [public OpenAPI specification](https://openapi.indykite.com/).

## Endpoint

```text
POST <API_URL>/capture/v1/nodes
```

`<API_URL>` is the regional IndyKite API base (`https://eu.api.indykite.com` or `https://us.api.indykite.com`). The request authenticates the calling application via its AppAgent credentials ([Credentials guide](https://developer.indykite.com/guides/guide-credentials)); the skill's helper script sets the headers from environment variables.

## Request body

```json
{ "nodes": [ <node>, … ] }
```

`nodes` is required, 1-250 items per request. Batch larger ingests into multiple requests.

### Node

| Field         | Required | Type    | Constraints | Meaning |
|---------------|----------|---------|-------------|---------|
| `external_id` | yes      | string  | 1-256 chars | Caller-owned identifier. The upsert keys on (`type`, `external_id`) - reposting updates the node. |
| `type`        | yes      | string  | 2-64 chars  | Node type (graph label), e.g. `Person`, `Car`. |
| `is_identity` | no       | boolean | -           | `true` marks an identity node (person or other actor). |
| `labels`      | no       | string[] | -          | Additional labels beyond `type`. |
| `location`    | no       | string  | 2-32 chars  | Composite IKG only: logical location to store the node in - must be a key of the project's `alias_mapping`. See [Data Residency guide](https://developer.indykite.com/guides/guide-data-residency). |
| `properties`  | no       | array   | -           | Typed property values - below. |

### Property

| Field            | Required | Meaning |
|------------------|----------|---------|
| `type`           | yes      | Property name (max 128 chars), e.g. `email`. |
| `value`          | no*      | String, integer, float, boolean, or an array of any of those. |
| `external_value` | no*      | Data reference resolved at query time by an [External Data Resolver](https://developer.indykite.com/guides/guide-external-data-resolver) instead of a stored value. |
| `metadata`       | no       | Per-property provenance - below. |

\* a property carries `value` or `external_value`.

### Property metadata

| Field             | Type    | Meaning |
|-------------------|---------|---------|
| `source`          | string  | Where the value came from, e.g. `"BRREG"`. |
| `assurance_level` | integer | `1`, `2`, or `3`. |
| `verified_time`   | string  | RFC 3339 timestamp, e.g. `"2026-04-10T06:28:16Z"`. |
| `custom_metadata` | object  | Free-form key/value provenance. |

```json
{
  "type": "name",
  "value": "Millicent Contextsworth",
  "metadata": {
    "assurance_level": 1,
    "source": "Some Source",
    "verified_time": "2026-04-10T06:28:16Z"
  }
}
```

## Location routing (composite IKG)

On a composite-database project, a node with `location` is stored in that constituent database, and a property-less **proxy node** (external ID, type, location) is automatically upserted into the global constituent so the node stays addressable graph-wide. A node **without** `location` goes to the default database - the regular, always-safe behavior. A `location` that is not an `alias_mapping` key, or any `location` on a project without a composite database, fails the request. Details: [Data Residency guide](https://developer.indykite.com/guides/guide-data-residency).

## Response

`200 OK` - one result per node, in request order:

```json
{ "results": [ { "id": "gid:…" } ] }
```

## Error semantics

| HTTP code | When | Likely fix |
|-----------|------|------------|
| `400 Bad Request` | Malformed body; `errors[]` lists details (e.g. missing `external_id` / `type`, batch size out of 1-250, field length out of range). | Fix the listed fields. |
| `401 Unauthorized` | Invalid AppAgent credentials. | Refresh the AppAgent credentials. |
| `422 Unprocessable Entity` | Well-formed but unprocessable - e.g. unknown `location`, or `location` without a composite database. | Match `location` to an `alias_mapping` key, or drop it. |
| `500` | Server-side issue. | Retry with backoff; escalate if persistent. |

## Sibling endpoints

- `/capture/v1/relationships` - connect nodes ([`indykite-capture-upsert-relationships`](../../indykite-capture-upsert-relationships/SKILL.md))
- `/capture/v1/nodes/delete` - remove nodes ([`indykite-capture-delete-nodes`](../../indykite-capture-delete-nodes/SKILL.md))
- `/capture/v1/nodes/properties/delete` - remove properties ([`indykite-capture-delete-node-properties`](../../indykite-capture-delete-node-properties/SKILL.md))
- `/capture/v1/nodes/properties/metadata/delete` - remove property metadata ([`indykite-capture-delete-node-property-metadata`](../../indykite-capture-delete-node-property-metadata/SKILL.md))

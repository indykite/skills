# Capture API - property metadata delete reference

Request/response shapes for the batch property-metadata delete endpoint, per the [public OpenAPI specification](https://openapi.indykite.com/).

## Endpoint

```text
POST <API_URL>/capture/v1/nodes/properties/metadata/delete
```

`<API_URL>` is the regional IndyKite API base (`https://eu.api.indykite.com` or `https://us.api.indykite.com`). The request authenticates the calling application via its AppAgent credentials ([Credentials guide](https://developer.indykite.com/guides/guide-credentials)); the skill's helper script sets the headers from environment variables.

## Request body

```json
{ "nodes": [ <entry>, … ] }
```

`nodes` is required, 1-250 items per request.

### Entry

| Field             | Required | Constraints | Meaning |
|-------------------|----------|-------------|---------|
| `external_id`     | yes      | 1-256 chars | The node's caller-owned identifier. |
| `type`            | yes      | 2-64 chars  | The node's type. |
| `property_type`   | yes      | string      | The single property whose metadata is removed. One entry per property. |
| `metadata_fields` | yes      | 1-250 items | Names of the metadata fields to remove. |
| `location`        | no       | 2-32 chars  | Composite IKG only: the node's logical location (an `alias_mapping` key). |

### Metadata fields

A property's `metadata` object (set at upsert) carries these fields:

| Field             | Type    | Meaning |
|-------------------|---------|---------|
| `source`          | string  | Where the value came from. |
| `assurance_level` | integer | `1`, `2`, or `3`. |
| `verified_time`   | string  | RFC 3339 timestamp. |
| `custom_metadata` | object  | Free-form key/value provenance. |

The property value itself is untouched; to remove the property, use [`indykite-capture-delete-node-properties`](../../indykite-capture-delete-node-properties/SKILL.md).

## Response

`200 OK` - one result per entry, in request order:

```json
{ "results": [ { "id": "gid:…" } ] }
```

## Error semantics

| HTTP code | When | Likely fix |
|-----------|------|------------|
| `400 Bad Request` | Malformed body; `errors[]` lists details (missing required field, empty `metadata_fields`, batch size out of 1-250). | Fix the listed fields. |
| `401 Unauthorized` | Invalid AppAgent credentials. | Refresh the AppAgent credentials. |
| `422 Unprocessable Entity` | Well-formed but unprocessable - e.g. unknown `location`, or `location` without a composite database. | Match `location` to an `alias_mapping` key, or drop it. |
| `500` | Server-side issue. | Retry with backoff; escalate if persistent. |

## Sibling endpoints

- `/capture/v1/nodes` - set or update metadata by re-upserting the property ([`indykite-capture-upsert-nodes`](../../indykite-capture-upsert-nodes/SKILL.md))
- `/capture/v1/nodes/properties/delete` - remove the property itself ([`indykite-capture-delete-node-properties`](../../indykite-capture-delete-node-properties/SKILL.md))
- `/capture/v1/nodes/delete` - remove whole nodes ([`indykite-capture-delete-nodes`](../../indykite-capture-delete-nodes/SKILL.md))

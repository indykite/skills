# Capture API - node property delete reference

Request/response shapes for the batch node-property delete endpoint, per the [public OpenAPI specification](https://openapi.indykite.com/).

## Endpoint

```text
POST <API_URL>/capture/v1/nodes/properties/delete
```

`<API_URL>` is the regional IndyKite API base (`https://eu.api.indykite.com` or `https://us.api.indykite.com`). The request authenticates the calling application via its AppAgent credentials ([Credentials guide](https://developer.indykite.com/guides/guide-credentials)); the skill's helper script sets the headers from environment variables.

## Request body

```json
{ "nodes": [ <entry>, … ] }
```

`nodes` is required, 1-250 items per request.

### Entry

| Field            | Required | Constraints | Meaning |
|------------------|----------|-------------|---------|
| `external_id`    | yes      | 1-256 chars | The node's caller-owned identifier. |
| `type`           | yes      | 2-64 chars  | The node's type. |
| `property_types` | yes      | 1-250 items | Names of the properties to delete from this node. |
| `location`       | no       | 2-32 chars  | Composite IKG only: the node's logical location (an `alias_mapping` key). See [Data Residency guide](https://developer.indykite.com/guides/guide-data-residency). |

The node itself, its remaining properties, and its relationships are not affected.

## Response

`200 OK` - one result per entry, in request order:

```json
{ "results": [ { "id": "gid:…" } ] }
```

## Error semantics

| HTTP code | When | Likely fix |
|-----------|------|------------|
| `400 Bad Request` | Malformed body; `errors[]` lists details (missing required field, empty `property_types`, batch size out of 1-250). | Fix the listed fields. |
| `401 Unauthorized` | Invalid AppAgent credentials. | Refresh the AppAgent credentials. |
| `422 Unprocessable Entity` | Well-formed but unprocessable - e.g. unknown `location`, or `location` without a composite database. | Match `location` to an `alias_mapping` key, or drop it. |
| `500` | Server-side issue. | Retry with backoff; escalate if persistent. |

## Sibling endpoints

- `/capture/v1/nodes` - re-upsert a property with a new value ([`indykite-capture-upsert-nodes`](../../indykite-capture-upsert-nodes/SKILL.md))
- `/capture/v1/nodes/delete` - remove whole nodes ([`indykite-capture-delete-nodes`](../../indykite-capture-delete-nodes/SKILL.md))
- `/capture/v1/nodes/properties/metadata/delete` - remove only a property's metadata ([`indykite-capture-delete-node-property-metadata`](../../indykite-capture-delete-node-property-metadata/SKILL.md))
- `/capture/v1/relationships/properties/delete` - remove relationship properties ([`indykite-capture-delete-relationship-properties`](../../indykite-capture-delete-relationship-properties/SKILL.md))

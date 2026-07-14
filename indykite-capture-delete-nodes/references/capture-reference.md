# Capture API - node delete reference

Request/response shapes for the batch node delete endpoint, per the [public OpenAPI specification](https://openapi.indykite.com/).

## Endpoint

```text
POST <API_URL>/capture/v1/nodes/delete
```

`<API_URL>` is the regional IndyKite API base (`https://eu.api.indykite.com` or `https://us.api.indykite.com`). The request authenticates the calling application via its AppAgent credentials ([Credentials guide](https://developer.indykite.com/guides/guide-credentials)); the skill's helper script sets the headers from environment variables.

## Request body

```json
{ "nodes": [ <delete-node>, … ] }
```

`nodes` is required, 1-250 items per request.

### Delete-node entry

| Field         | Required | Constraints | Meaning |
|---------------|----------|-------------|---------|
| `external_id` | yes      | 1-256 chars | The node's caller-owned identifier. |
| `type`        | yes      | 2-64 chars  | The node's type. |
| `location`    | no       | 2-32 chars  | Composite IKG only: the node's logical location (an `alias_mapping` key). |

## Location behavior (composite IKG)

Deleting a located node removes **both** its full data node in the location constituent and its proxy node in the global database. A node without `location` is deleted from the default database. A `location` that is not an `alias_mapping` key, or any `location` on a project without a composite database, fails the request. Details: [Data Residency guide](https://developer.indykite.com/guides/guide-data-residency).

## Response

`200 OK` - one result per node, in request order:

```json
{ "results": [ { "id": "gid:…" } ] }
```

## Error semantics

| HTTP code | When | Likely fix |
|-----------|------|------------|
| `400 Bad Request` | Malformed body; `errors[]` lists details (missing `external_id` / `type`, batch size out of 1-250). | Fix the listed fields. |
| `401 Unauthorized` | Invalid AppAgent credentials. | Refresh the AppAgent credentials. |
| `422 Unprocessable Entity` | Well-formed but unprocessable - e.g. unknown `location`, or `location` without a composite database. | Match `location` to an `alias_mapping` key, or drop it. |
| `500` | Server-side issue. | Retry with backoff; escalate if persistent. |

## Sibling endpoints

- `/capture/v1/nodes` - (re-)ingest nodes ([`indykite-capture-upsert-nodes`](../../indykite-capture-upsert-nodes/SKILL.md))
- `/capture/v1/nodes/properties/delete` - remove properties, keep the node ([`indykite-capture-delete-node-properties`](../../indykite-capture-delete-node-properties/SKILL.md))
- `/capture/v1/nodes/properties/metadata/delete` - remove property metadata ([`indykite-capture-delete-node-property-metadata`](../../indykite-capture-delete-node-property-metadata/SKILL.md))
- `/capture/v1/relationships/delete` - remove relationships ([`indykite-capture-delete-relationships`](../../indykite-capture-delete-relationships/SKILL.md))

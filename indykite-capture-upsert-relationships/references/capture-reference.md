# Capture API - relationship upsert reference

Request/response shapes for the batch relationship upsert endpoint, per the [public OpenAPI specification](https://openapi.indykite.com/).

## Endpoint

```text
POST <API_URL>/capture/v1/relationships
```

`<API_URL>` is the regional IndyKite API base (`https://eu.api.indykite.com` or `https://us.api.indykite.com`). The request authenticates the calling application via its AppAgent credentials ([Credentials guide](https://developer.indykite.com/guides/guide-credentials)); the skill's helper script sets the headers from environment variables.

## Request body

```json
{ "relationships": [ <relationship>, … ], "use_global_db": false }
```

`relationships` is required, 1-250 items per request. `use_global_db` is optional (composite IKGs only - below).

### Relationship

| Field        | Required | Meaning |
|--------------|----------|---------|
| `source`     | yes      | Node reference - below. |
| `target`     | yes      | Node reference - below. |
| `type`       | yes      | Relationship type (max 128 chars), conventionally an uppercase verb (`OWNS`, `ACCEPTED`, `COVERS`, `HAS`). |
| `properties` | no       | Array of properties: `type` (max 128 chars) plus `value` (string / integer / float / boolean, or an array of those) or `external_value` (a data reference). |

### Node reference (`source` / `target`)

| Field         | Required | Constraints | Meaning |
|---------------|----------|-------------|---------|
| `external_id` | yes      | 1-256 chars | The node's caller-owned identifier. |
| `type`        | yes      | 2-64 chars  | The node's type. |
| `location`    | no       | 2-32 chars  | Composite IKG only: the node's logical location. |

## `use_global_db` (composite IKG)

On a composite-database project, set top-level `"use_global_db": true`: relationships can connect nodes living in different location constituents, so they are stored in the **global** constituent between the proxy nodes. On a regular IKG omit the field. Details: [Data Residency guide](https://developer.indykite.com/guides/guide-data-residency).

## Response

`200 OK` - one result per relationship, in request order:

```json
{ "results": [ { "id": "gid:…" } ] }
```

## Error semantics

| HTTP code | When | Likely fix |
|-----------|------|------------|
| `400 Bad Request` | Malformed body; `errors[]` lists details (missing `source` / `target` / `type`, batch size out of 1-250). | Fix the listed fields. |
| `401 Unauthorized` | Invalid AppAgent credentials. | Refresh the AppAgent credentials. |
| `422 Unprocessable Entity` | Well-formed but unprocessable (e.g. composite routing misuse). | Check `use_global_db` / `location` against the project's setup. |
| `500` | Server-side issue. | Retry with backoff; escalate if persistent. |

## Sibling endpoints

- `/capture/v1/nodes` - ingest the endpoint nodes ([`indykite-capture-upsert-nodes`](../../indykite-capture-upsert-nodes/SKILL.md))
- `/capture/v1/relationships/delete` - remove relationships ([`indykite-capture-delete-relationships`](../../indykite-capture-delete-relationships/SKILL.md))
- `/capture/v1/relationships/properties/delete` - remove relationship properties ([`indykite-capture-delete-relationship-properties`](../../indykite-capture-delete-relationship-properties/SKILL.md))

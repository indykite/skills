# Capture API - relationship property delete reference

Request/response shapes for the batch relationship-property delete endpoint, per the [public OpenAPI specification](https://openapi.indykite.com/).

## Endpoint

```text
POST <API_URL>/capture/v1/relationships/properties/delete
```

`<API_URL>` is the regional IndyKite API base (`https://eu.api.indykite.com` or `https://us.api.indykite.com`). The request authenticates the calling application via its AppAgent credentials ([Credentials guide](https://developer.indykite.com/guides/guide-credentials)); the skill's helper script sets the headers from environment variables.

## Request body

```json
{ "relationships": [ <entry>, … ], "use_global_db": false }
```

`relationships` is required, 1-250 items per request. `use_global_db` is optional (composite IKGs only): set `true` to route the property deletes to the **global** constituent of a composite deployment ([Data Residency guide](https://developer.indykite.com/guides/guide-data-residency)).

### Entry

| Field            | Required | Meaning |
|------------------|----------|---------|
| `source`         | yes      | `{ "external_id": (1-256 chars), "type": (2-64 chars), "location"?: (2-32 chars) }` - the outgoing node. |
| `target`         | yes      | Same shape - the incoming node. |
| `type`           | yes      | The relationship type (max 128 chars). |
| `property_types` | yes      | 1-250 names of the properties to delete from this relationship. |
| `properties`     | no       | Accepted by the schema; deletion is driven by `property_types`. |

The relationship itself and its endpoint nodes are not affected.

## Response

`200 OK` - one result per entry, in request order:

```json
{ "results": [ { "id": "gid:…" } ] }
```

## Error semantics

| HTTP code | When | Likely fix |
|-----------|------|------------|
| `400 Bad Request` | Malformed body; `errors[]` lists details (missing `source` / `target` / `type`, empty `property_types`, batch size out of 1-250). | Fix the listed fields. |
| `401 Unauthorized` | Invalid AppAgent credentials. | Refresh the AppAgent credentials. |
| `422 Unprocessable Entity` | Well-formed but unprocessable (e.g. composite routing misuse). | Check `use_global_db` / `location` against the project's setup. |
| `500` | Server-side issue. | Retry with backoff; escalate if persistent. |

## Sibling endpoints

- `/capture/v1/relationships` - re-upsert a property with a new value ([`indykite-capture-upsert-relationships`](../../indykite-capture-upsert-relationships/SKILL.md))
- `/capture/v1/relationships/delete` - remove the relationship itself ([`indykite-capture-delete-relationships`](../../indykite-capture-delete-relationships/SKILL.md))
- `/capture/v1/nodes/properties/delete` - remove node properties ([`indykite-capture-delete-node-properties`](../../indykite-capture-delete-node-properties/SKILL.md))

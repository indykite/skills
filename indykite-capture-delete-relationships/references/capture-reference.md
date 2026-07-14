# Capture API - relationship delete reference

Request/response shapes for the batch relationship delete endpoint, per the [public OpenAPI specification](https://openapi.indykite.com/).

## Endpoint

```text
POST <API_URL>/capture/v1/relationships/delete
```

`<API_URL>` is the regional IndyKite API base (`https://eu.api.indykite.com` or `https://us.api.indykite.com`). The request authenticates the calling application via its AppAgent credentials ([Credentials guide](https://developer.indykite.com/guides/guide-credentials)); the skill's helper script sets the headers from environment variables.

## Request body

```json
{ "relationships": [ <relationship>, … ], "use_global_db": false }
```

`relationships` is required, 1-250 items per request. `use_global_db` is optional (composite IKGs only): set `true` to delete relationships stored in the **global** constituent of a composite deployment - the place cross-location relationships live ([Data Residency guide](https://developer.indykite.com/guides/guide-data-residency)).

### Relationship entry

| Field        | Required | Meaning |
|--------------|----------|---------|
| `source`     | yes      | `{ "external_id": (1-256 chars), "type": (2-64 chars), "location"?: (2-32 chars) }` - the outgoing node. |
| `target`     | yes      | Same shape - the incoming node. |
| `type`       | yes      | The relationship type to remove (max 128 chars). |
| `properties` | no       | Accepted by the schema; identification is by (`source`, `target`, `type`). |

The endpoint nodes are not affected - only the relationship is removed.

## Response

`200 OK` - one result per entry, in request order:

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

- `/capture/v1/relationships` - (re-)create relationships ([`indykite-capture-upsert-relationships`](../../indykite-capture-upsert-relationships/SKILL.md))
- `/capture/v1/relationships/properties/delete` - remove properties, keep the edge ([`indykite-capture-delete-relationship-properties`](../../indykite-capture-delete-relationship-properties/SKILL.md))
- `/capture/v1/nodes/delete` - remove the nodes themselves ([`indykite-capture-delete-nodes`](../../indykite-capture-delete-nodes/SKILL.md))

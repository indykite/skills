# Capture API - relationship upsert reference

Request/response shapes for the batch relationship upsert endpoint, per the [public OpenAPI specification](https://openapi.indykite.com/).

## Endpoint

```text
POST <API_URL>/capture/v1/relationships
```

`<API_URL>` is the regional IndyKite API base (`https://eu.api.indykite.com` or `https://us.api.indykite.com`). The request authenticates the calling application via its AppAgent credentials ([Credentials guide](https://developer.indykite.com/guides/guide-credentials)); the skill's helper script sets the headers from environment variables.

## Request body

```json
{ "relationships": [ <relationship>, … ] }
```

`relationships` is required, 1-250 items per request. On a composite IKG (data residency) there is no routing field: the `location` of the source and target nodes chooses the database - see *Composite IKG* below. `use_global_db`, the former data-residency setting, is refused when `true`, with `400` `use_global_db is removed: set the location of the source and target nodes instead` (`false` is accepted). On a regular IKG nothing changes.

### Relationship

| Field        | Required | Meaning |
|--------------|----------|---------|
| `source`     | yes      | Node reference - below. |
| `target`     | yes      | Node reference - below. |
| `type`       | yes      | Relationship type (max 128 chars), conventionally an uppercase verb (`OWNS`, `ACCEPTED`, `COVERS`, `HAS`). |
| `properties` | no       | Array of properties: `type` (max 128 chars) plus `value` (string / integer / float / boolean, or an array of those) or `external_value` (a string naming an External Data Resolver configuration). Relationship properties take no `metadata`; provenance is a node-property feature. |

### Node reference (`source` / `target`)

| Field         | Required | Constraints | Meaning |
|---------------|----------|-------------|---------|
| `external_id` | yes      | 1-256 chars | The node's caller-owned identifier. |
| `type`        | yes      | 2-64 chars  | The node's type. |
| `location`    | no       | 2-32 chars  | Composite IKG only: the node's logical location. |

## Composite IKG (data residency)

On a project with a composite database, give each `source` and `target` node the `location` it was upserted with. The platform writes each relationship to exactly one database:

| Source and target | The relationship is in | Response key |
|-------------------|------------------------|--------------|
| The same location on both (e.g. `west` and `west`) | that location's database | `west` |
| Different locations (e.g. `east` and `west`, `east` and `global`, `east` and none) | the global database | `global` |
| No location on either | the default database | `__default` |

Every location is checked against the project's `alias_mapping`, also when the relationship goes to the global database (`422` `invalid locations: "…"`), and `__default` is reserved (`422` `location __default is reserved and cannot be used`). A relationship written to the global database creates any source or target node missing there with its external ID and type only - no location, no properties - so upsert a located node that takes part in cross-location relationships with `"create_proxy": true` first ([`indykite-capture-upsert-nodes`](../../indykite-capture-upsert-nodes/SKILL.md)). On a regular IKG, or in a request without any location, relationships go to the project's one database as before. Details: [Data Residency guide](https://developer.indykite.com/guides/guide-data-residency).

## Response

`200 OK` - one result per relationship, in request order:

```json
{ "results": [ { "id": "gid:…" } ] }
```

On a composite IKG, a request in which at least one node carries a `location` is answered instead with one key per location and the GIDs written there: `{"east": ["gid:…"], "global": ["gid:…"]}`.

## Error semantics

| HTTP code | When | Likely fix |
|-----------|------|------------|
| `400 Bad Request` | Malformed body; `errors[]` lists details (missing `source` / `target` / `type`, batch size out of 1-250). | Fix the listed fields. |
| `401 Unauthorized` | Invalid AppAgent credentials. | Refresh the AppAgent credentials. |
| `400 Bad Request` + `use_global_db is removed: set the location of the source and target nodes instead` | The request set `"use_global_db": true`. | Remove the field; on a composite IKG give the source and target nodes their `location`. |
| `422 Unprocessable Entity` | Composite IKG: a `location` that is not an `alias_mapping` key (`invalid locations: "…"`), the reserved `__default`, or a `location` on a project without a composite database. | Match each `location` to an `alias_mapping` key, or drop it on a regular IKG. |
| `404 Not Found` + `{"message": "knowledge graph not found for this project"}` | The project has no knowledge graph to write to: it was deleted, or it has not finished provisioning yet. The request itself is fine. | Check the project in the Hub or via `GET /configs/v1/projects/{id}`. If it is still provisioning, wait for it to complete and resend. If the graph was deleted, waiting will not help: provision a project again (and point the AppAgent credential at it) before re-ingesting. |
| `503 Service Unavailable` + `{"message": "Unable to verify the AppAgent credential token, retry the request"}` | The credential could not be checked right now (transient); it was not judged. | Retry the same request with the same credential, with backoff. |
| `503 Service Unavailable` (other) | The graph backend could not answer right now. Nothing is wrong with the request. | Retry with backoff. Batches are idempotent, so resending the same payload is safe. |
| `500` + `{"message": "Unable to verify the AppAgent credential token"}` | Non-transient failure of the credential check; the credential was not judged. | Report the request's trace to IndyKite support; the credential itself was not judged. |
| `500` (other) | Server-side issue. | Retry with backoff; escalate if persistent. |

## Sibling endpoints

- `/capture/v1/nodes` - ingest the endpoint nodes ([`indykite-capture-upsert-nodes`](../../indykite-capture-upsert-nodes/SKILL.md))
- `/capture/v1/relationships/delete` - remove relationships ([`indykite-capture-delete-relationships`](../../indykite-capture-delete-relationships/SKILL.md))
- `/capture/v1/relationships/properties/delete` - remove relationship properties ([`indykite-capture-delete-relationship-properties`](../../indykite-capture-delete-relationship-properties/SKILL.md))

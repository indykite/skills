# Data Schema API reference

## Endpoint and auth

```text
GET https://eu.api.indykite.com/data-schema/v1/
GET https://us.api.indykite.com/data-schema/v1/
```

- **Auth**: the AppAgent credential in the `X-IK-ClientKey` header, passed as is, without any prefix. No user bearer token is involved.
- **Parameters**: none - the project is derived from the credential. The trailing slash is part of the path.
- **Response**: `200 OK` with an `application/json` body in JSON Graph Format (JGF) v2.

## Response fields

Top level is a single `graph` object.

| Field            | Type    | Meaning                                                              |
|------------------|---------|----------------------------------------------------------------------|
| `graph.directed` | boolean | Always `true` - the IKG is a directed graph.                          |
| `graph.metadata` | object  | `created_at` and `updated_at` timestamps (RFC 3339) of the schema. `updated_at` advances with each persist, at most once a minute and only when the shape or the counts changed. |
| `graph.nodes`    | map     | Keyed by **node type** (e.g. `"Person"`). Values below.               |
| `graph.edges`    | array   | One entry per **(source type, relation, target type)** combination.   |

### `graph.nodes.<Type>.metadata`

| Field                 | Type  | Meaning                                                                  |
|-----------------------|-------|--------------------------------------------------------------------------|
| `node_count`          | int   | How many nodes of this type exist.                                        |
| `properties`          | map   | Keyed by **property name**; each value is a property entry (below).       |
| `system_labels`       | array | Platform-assigned labels, each `{ name, count }`: `Resource` on every node type, plus `DigitalTwin` on identity nodes. |
| `user_defined_labels` | array \| null | Labels from the `labels` field at ingest, each `{ name, count }`; `null` (not `[]`) when the type carries none. |

### `graph.edges[]`

| Field      | Type    | Meaning                                                        |
|------------|---------|-----------------------------------------------------------------|
| `source`   | string  | Source **node type** (not an instance).                         |
| `target`   | string  | Target **node type**.                                           |
| `relation` | string  | Relationship type, e.g. `OWNS`, `CAN_DRIVE`.                    |
| `directed` | boolean | Always `true`; the stored direction is `source` → `target`.     |
| `metadata` | object  | `count` (how many such edges exist) and a `properties` map.     |

### Property entries

Each value in a `properties` map (node or edge) describes one property:

| Field      | Type  | Meaning                                                                      |
|------------|-------|-------------------------------------------------------------------------------|
| `count`    | int   | How many times the property occurs across instances.                          |
| `types`    | array | Observed value types with per-type tallies: `{ "type": "STRING NOT NULL", "count": 4980 }`. The names are the graph store's; the common scalar ones are `STRING NOT NULL`, `INTEGER NOT NULL`, `FLOAT NOT NULL`, `BOOLEAN NOT NULL`, and `ZONED DATETIME NOT NULL`, and an array-valued property (Capture accepts arrays of those scalars) reports a list type, so other names can appear. |
| `metadata` | map   | **Node properties only** - relationship properties carry no provenance. Keyed by provenance field (`source`, `assurance_level`, `verified_time`, custom keys); each value has the same `count` + `types` statistics. |

More than one entry in `types` means instances of the property were ingested with different value types - usually a data-quality problem upstream, not an intended union type.

## Complete example response

After ingesting a minimal vehicle-rental graph (`Person(millicent) -[CAN_DRIVE]-> Car(kitt)`), the schema reads back along these lines (illustrative):

```json
{
  "graph": {
    "directed": true,
    "metadata": {
      "created_at": "2026-08-01T10:00:00Z",
      "updated_at": "2026-08-15T08:30:00Z"
    },
    "nodes": {
      "Person": {
        "metadata": {
          "node_count": 1,
          "properties": {
            "email": { "count": 1, "types": [ { "type": "STRING NOT NULL", "count": 1 } ] },
            "name": {
              "count": 1,
              "types": [ { "type": "STRING NOT NULL", "count": 1 } ],
              "metadata": {
                "source":        { "count": 1, "types": [ { "type": "STRING NOT NULL", "count": 1 } ] },
                "assurance_level": { "count": 1, "types": [ { "type": "INTEGER NOT NULL", "count": 1 } ] }
              }
            }
          },
          "system_labels": [ { "name": "DigitalTwin", "count": 1 }, { "name": "Resource", "count": 1 } ],
          "user_defined_labels": null
        }
      },
      "Car": {
        "metadata": {
          "node_count": 1,
          "properties": {
            "manufacturer": { "count": 1, "types": [ { "type": "STRING NOT NULL", "count": 1 } ] },
            "seats":        { "count": 1, "types": [ { "type": "INTEGER NOT NULL", "count": 1 } ] }
          },
          "system_labels": [ { "name": "Resource", "count": 1 } ],
          "user_defined_labels": null
        }
      }
    },
    "edges": [
      {
        "source": "Person",
        "target": "Car",
        "relation": "CAN_DRIVE",
        "directed": true,
        "metadata": {
          "count": 1,
          "properties": {
            "valid_until": { "count": 1, "types": [ { "type": "STRING NOT NULL", "count": 1 } ] }
          }
        }
      }
    ]
  }
}
```

## `jq` recipes

With the response in `schema.json`:

```bash
# Which node types exist, and how many of each?
jq -r '.graph.nodes | to_entries[] | "\(.key)\t\(.value.metadata.node_count)"' schema.json

# Which properties does Person carry, with their value types?
jq -r '.graph.nodes.Person.metadata.properties
       | to_entries[] | "\(.key)\t\([.value.types[].type] | join(","))"' schema.json

# Which relationships exist, as source -[RELATION]-> target?
jq -r '.graph.edges[] | "\(.source) -[\(.relation)]-> \(.target)  (\(.metadata.count))"' schema.json

# Any property observed with more than one value type? (drift check)
jq -r '.graph.nodes | to_entries[]
       | .key as $t | .value.metadata.properties | to_entries[]
       | select((.value.types | length) > 1)
       | "\($t).\(.key): \([.value.types[] | "\(.type):\(.count)"] | join(", "))"' schema.json
```

## Errors

| HTTP code                   | When                                                                                              |
|-----------------------------|---------------------------------------------------------------------------------------------------|
| `400 Bad Request`           | Malformed request; the body carries a `message`.                                                   |
| `404 Not Found`             | No data schema for the project - typically nothing has been ingested yet. Body: `{"message": "Not Found", "errors": ["data schema not found for the specified project"]}`. Not a failure: it correctly describes an empty project. |
| `503 Service Unavailable`   | `{"message": "Unable to verify the AppAgent credential token, retry the request"}`: the credential could not be checked right now (transient) and was not judged. Retry the same request with the same credential, with backoff; do not mint new credentials. |
| `500 Internal Server Error` | With `{"message": "Unable to verify the AppAgent credential token"}`: non-transient failure of the credential check, the credential was not judged - do not rotate it, report the request's trace to IndyKite support. Otherwise a server-side issue; retry with backoff. |

## Troubleshooting

- **`404` but you just ingested data**: the schema is persisted at most once a minute, so wait a minute and read again; then confirm the ingest hit the same project as the AppAgent credential you are reading with, and the same region (`eu` vs `us`).
- **A count is short, or a new type is missing, right after a large batch**: same cause - the persist runs at most once a minute and only when something changed. `graph.metadata.updated_at` tells you whether a persist has happened since the batch.
- **A type you expect is missing**: the schema only reflects what was actually ingested - check the Capture response for per-item errors, and check for a misspelled variant of the type in `graph.nodes` (e.g. `Perosn`).
- **A relationship you expect is missing**: `graph.edges` is keyed by the (source type, relation, target type) combination - if the edge was ingested with source and target swapped, it appears under the reversed combination.

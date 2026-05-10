# CIQ Execution Reference (combined-create flows)

The execution endpoint runs the combined-create Knowledge Query atomically — all writes succeed or none do.

## Endpoint

```text
POST <API_URL>/contx-iq/v1/execute
```

## Authentication

| Subject type             | `X-IK-ClientKey`                       | `Authorization: Bearer …`                                    |
|--------------------------|----------------------------------------|--------------------------------------------------------------|
| `_Application`           | AppAgent credentials token (required)  | **Omit.**                                                     |
| `Person` / `User` / etc. | AppAgent credentials token (required)  | User OAuth access token (required). `$token.sub` substituted. |

## Request

```json
{
  "id": "<knowledge_query_gid_or_name>",
  "input_params": {
    "vehicleID":           "car2",
    "personID":            "ryan",
    "contract_external_id": "ct853",
    "contractNumber":       "rbjh853"
  }
}
```

`input_params` covers:

- existing-endpoint pinning (`vehicleID`, `personID`),
- the new node's `external_id`,
- any property values declared as `$param`.

`$_appId` is reserved — do not include.

## Response (successful combined-create)

```json
{
  "data": [
    {
      "nodes": {
        "contract.external_id":     "ct853",
        "contract.property.number": "rbjh853"
      },
      "relationships": {
        "r3": {
          "Id": …,
          "ElementId": "…",
          "StartId": …, "StartElementId": "…",
          "EndId":   …, "EndElementId":   "…"
        },
        "r4": { "Id": …, "ElementId": "…", "StartId": …, "EndId": … }
      }
    }
  ]
}
```

The `nodes` block echoes the new node's projection per the KQ's `nodes` array. The `relationships` block carries one entry per new relationship, keyed by `upsert_relationships[].name`.

## Atomicity

The combined-create is **transactional**. If any single entry fails — wrong label in `node_types`, unmatched relationship triple, missing `$param`, protected property — the whole call fails with `403` or `422` and **none of the writes happen**.

This is the main reason to use this skill instead of issuing two separate executes (`create-node` then `create-relationship`): atomicity. With two separate calls, you can end up with a created node that didn't get wired up because the second call failed.

## Idempotence on rerun

Re-running the same combined-create with the same `external_id`s is **not** an error. The platform treats it as upsert:

- The new node is re-upserted: same `external_id`, properties overwritten.
- The new relationships are re-upserted: matching `(source, target, type)` triples are matched to existing edges instead of creating duplicates.

The response shape is the same. To detect "this is a retry" reliably, project the new node's `update_time` — it bumps on every write but stays stable on reruns where nothing changed.

## Error semantics

| HTTP code             | When                                                                                            | Likely fix                                                                                                      |
|-----------------------|-------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------|
| `400 Bad Request`     | Malformed JSON, missing `id`.                                                                    | Fix the request body.                                                                                            |
| `401 Unauthorized`    | Missing or invalid `X-IK-ClientKey`, or for non-`_Application` subjects, missing/invalid Bearer.  | Refresh the AppAgent token; for Person subjects, ensure the user token is present and valid.                    |
| `403 Forbidden`       | KQ writes something not whitelisted (label or triple), *or* references a protected property.    | Check `node_types`, `relationship_types`, and the protected-property list.                                       |
| `422 invalid_argument: missing or wrong input params` | A `$param` is absent from `input_params`.                                  | Add the missing key.                                                                                             |
| `200` with empty `data` | Cypher matched no rows — usually a missing existing endpoint.                                   | Confirm `vehicleID`, `personID`, etc. exist in the IKG.                                                          |
| `404 Not Found`       | Knowledge Query `id` does not exist.                                                              | Verify the `id` and project context.                                                                              |

## Calling through MCP instead of REST

The MCP server's `ciq_execute` tool wraps the same call — see [`indykite-mcp-server`](../../indykite-mcp-server/SKILL.md). The atomicity, parameters, and response semantics are identical.

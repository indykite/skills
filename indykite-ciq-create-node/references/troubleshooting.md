# IndyKite CIQ Create-Node Troubleshooting

A symptom-first map. Walk it top-down — earlier rows are cheaper to verify.

## Symptom: `403 Forbidden` on a create that "should work"

| Likely cause                                                              | How to verify                                                                                  | Fix                                                                                          |
|---------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| `upsert_nodes[].type` not in policy's `allowed_upserts.nodes.node_types`  | Compare the KQ's node label to the policy's whitelist.                                          | Add the label to `node_types` (and republish the policy), or change the KQ's `type`.         |
| Policy filter rejects the subject                                          | For `_Application`: confirm the AppAgent's `external_id` matches what the filter compares to.<br>For Person: confirm the Bearer's `sub` matches the seeded `Person.external_id`. | Use the right AppAgent / user token. Don't try to override `$_appId` in `input_params`.       |
| Policy uses `existing_nodes` only (no `node_types`)                        | Look for `allowed_upserts.nodes.existing_nodes` and absence of `node_types`.                    | Add `node_types: ["<Label>"]`. The two keys serve different operations; only one is set.      |
| Policy is in `INACTIVE` status                                             | `GET /configs/v1/authorization-policies/<gid>` and check `status`.                              | Patch to `ACTIVE` (`PATCH /configs/v1/authorization-policies/<gid>` with `{"status":"ACTIVE"}`). |

## Symptom: `422 invalid_argument: missing or wrong input params`

| Likely cause                                                              | How to verify                                                                                  | Fix                                                                                          |
|---------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| A `$param` in the policy filter is not in `input_params`                   | `grep -E '"\$[a-z_]+"' <policy.json>` and compare to the request body.                          | Add the missing key (no `$` prefix) with the right value.                                     |
| A `$param` in `upsert_nodes[].external_id` is not in `input_params`        | Inspect the KQ's `upsert_nodes` block.                                                          | Add the missing key.                                                                         |
| A `$param` in `upsert_nodes[].properties[].value` is not in `input_params` | Inspect the properties array.                                                                   | Add the missing key.                                                                         |
| You passed `_appId` (or `$_appId`) explicitly                              | Inspect `input_params`.                                                                         | Remove it. `$_appId` is reserved and auto-filled.                                             |
| `input_params` was sent under the wrong key (e.g. `params` or `inputParams`) | Inspect the request body.                                                                       | Use exactly `"input_params"`.                                                                |

## Symptom: Create returns `200` but the new node isn't visible

| Likely cause                                                              | How to verify                                                                                  | Fix                                                                                          |
|---------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| `nodes` array in the KQ is empty                                           | Inspect the KQ.                                                                                 | Add the new node's `name` to `nodes` so the response echoes it.                              |
| The create succeeded but the read query you used afterwards isn't authorized to see it | Run a fresh read with the same subject context.                            | Make sure the read-side policy includes the new node's label in `allowed_reads.nodes`.       |
| You retried with the same `external_id` and the result is an upsert       | Compare the response's properties to what you sent. If properties match, this *is* the existing node. | Use a different `external_id`, or accept that re-runs are upserts (this is the documented behaviour). |

## Symptom: `403` says "property '\<name\>' is protected"

| Likely cause                                                              | Fix                                                                                          |
|---------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| `properties[]` includes one of `_service` / `create_time` / `external_id` / `id` / `type` / `update_time` | Remove that property entry. Set `external_id` and `type` via the dedicated fields on `upsert_nodes[]`, not via `properties`. The others are platform-managed; you can't set them. |

## Symptom: Property value is wrong type

| Likely cause                                                              | How to verify                                                                                  | Fix                                                                                          |
|---------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| You sent a string for a numeric property (e.g. `"-7.5"` instead of `-7.5`) | Inspect the JSON in `input_params`.                                                              | Send a JSON number, not a string. JSON's type is significant.                                |
| The IKG already has a different type recorded for that property            | Look at an existing node of the same type.                                                       | Decide which type wins; if you're correct, delete the old node first or rename the property. |

## Symptom: `401 Unauthorized` on a Person-subject create

| Likely cause                                                              | Fix                                                                                          |
|---------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| Bearer token missing                                                       | Add `Authorization: Bearer <user-token>`.                                                    |
| Bearer token expired                                                       | Refresh and retry.                                                                            |
| Token's `sub` not seeded as a Person `external_id`                          | Either seed the Person, or use a different test user. (See the music-dataset Chapter 5 test-user table for the canonical Cornelius / Marmaduke split.) |

## Symptom: execution is fast on a small graph, slow as data grows

| Likely cause                                                       | How to verify                                                                                        | Fix                                                                                          |
|--------------------------------------------------------------------|------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| Policy `condition.cypher` is anchored on a high-fan-in node (a brand / tenant / category most records point to) instead of the subject | Execution time grows roughly linearly with dataset size, and the pattern's only selective filters sit at the endpoints of a multi-hop chain. | Take the fan-in node out of the connected chain (separate `MATCH` pinned by `external_id` + a `WHERE (x)-[:REL]->(fanin)` pattern predicate), or pin the subject with `WHERE … WITH subject LIMIT 1` — see "Performance: pin the subject before high-fan-in hops" in `policy-reference.md`. |

## Useful one-liners

```bash
# Show every $param a policy file references
jq -r '.policy' policy.json | jq -r '..|strings|select(test("^\\$"))'

# Show every $param a KQ file references
jq -r '.query' knowledge-query.json | jq -r '..|strings|select(test("^\\$"))'

# Confirm the Knowledge Query is ACTIVE
curl -sH "Authorization: Bearer $SERVICE_ACCOUNT_TOKEN" \
  "$API_URL/configs/v1/knowledge-queries/$query_gid" | jq .status

# Read back the just-created node (assumes a paired read-policy + read-KQ exists)
QUERY_ID="<read-kq-gid>" ./scripts/execute.sh /tmp/input_params.json | jq .
```

# IndyKite CIQ Add-Property Troubleshooting

A symptom-first map. Walk it top-down — earlier rows are cheaper to verify.

## Symptom: `403 Forbidden` on a property write that "should work"

| Likely cause                                                                                          | How to verify                                                                                       | Fix                                                                                          |
|-------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| KQ's `upsert_nodes[].name` not in policy's `allowed_upserts.nodes.existing_nodes`                     | Compare the KQ entry's `name` to the policy's `existing_nodes` array.                                | Add the variable to `existing_nodes` and republish the policy, or change the KQ's `name`.     |
| KQ's `upsert_nodes[].name` is a fresh value (not in the policy's `cypher`)                            | Inspect the policy's `cypher` for variable bindings.                                                 | Use a name that's bound by the cypher, e.g. `subject`, `car`, `ln`.                          |
| KQ includes a protected property name (`_service`, `create_time`, `external_id`, `id`, `type`, `update_time`) | Inspect the `properties` array.                                                                | Remove the protected property entry. These are platform-managed; you cannot set them.        |
| KQ includes `external_id` on the `upsert_nodes[]` entry                                                | Inspect the entry — it should not have `external_id` for a property write.                           | Remove `external_id`. Including it flips the operation to "create" semantics.                |
| Policy filter rejects the subject                                                                      | For Person: confirm the Bearer's `sub` matches a seeded `Person.external_id`. For `_Application`: confirm the AppAgent's `external_id` matches the filter. | Use the right token. Don't try to override `$_appId`.                                        |
| Policy is in `INACTIVE` status                                                                         | `GET /configs/v1/authorization-policies/<gid>` and check `status`.                                  | Patch to `ACTIVE`.                                                                            |

## Symptom: `200` with empty `data` array (no node matched)

| Likely cause                                                       | How to verify                                                                                        | Fix                                                                                          |
|--------------------------------------------------------------------|------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| Target node doesn't exist with the supplied `external_id`           | Spot-check with a read query, or the IKG directly: `MATCH (n {external_id: "<id>"}) RETURN n LIMIT 1`. | Seed the missing node, or correct the `external_id` value in `input_params`.                  |
| Bearer's `sub` claim doesn't match a seeded Person `external_id`     | Decode the Bearer token (`cut -d. -f2 \| base64 -d \| jq`) and compare to seeded Persons.            | Use a different test user, or seed a Person with the right `external_id`.                    |
| Policy's cypher path is broken (e.g. missing `OWNS` relationship)    | Run a read query against the same path.                                                              | Either pre-create the missing relationship, or simplify the cypher.                          |
| Filter clause references a property the matched node doesn't have    | Inspect the failing node's properties.                                                               | Either add the property, or change the filter.                                                |

## Symptom: `422 invalid_argument: missing or wrong input params`

| Likely cause                                                              | How to verify                                                                                  | Fix                                                                                          |
|---------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| A `$param` in the policy filter is not in `input_params`                   | `grep -E '"\$[a-z_]+"' <policy.json>` and compare to the request body.                          | Add the missing key (no `$` prefix) with the right value.                                     |
| A `$param` in `upsert_nodes[].properties[].value` is not in `input_params` | Inspect the properties array.                                                                   | Add the missing key.                                                                         |
| A `$param` in property metadata is not in `input_params`                   | Inspect the `metadata` arrays.                                                                  | Add the missing key.                                                                         |
| A `$param` in the KQ's own `filter` is not in `input_params`               | Inspect the KQ's `filter`.                                                                      | Add the missing key.                                                                         |
| You passed `_appId` (or `$_appId`) explicitly                              | Inspect `input_params`.                                                                         | Remove it. `$_appId` is reserved.                                                            |

## Symptom: Property write returns `200` but the value isn't visible in subsequent reads

| Likely cause                                                              | How to verify                                                                                       | Fix                                                                                          |
|---------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| Read-side policy doesn't list the property in `allowed_reads.nodes`        | Inspect the read policy.                                                                            | Add `<var>.property.<name>` (or `<var>.*` for everything) to `allowed_reads.nodes`.          |
| Read-side KQ projects different properties                                  | Inspect the read KQ's `nodes` array.                                                                | Add the property path to the read KQ.                                                        |
| The full-node `Props` block shows `update_time` was NOT bumped              | Compare `update_time` before and after the write.                                                   | The write didn't actually happen — go back to the `403` / empty-data symptoms above.          |
| Caching/stale data in a downstream consumer                                  | Re-run the read after a few seconds.                                                                | Wait or invalidate any client-side cache.                                                    |

## Symptom: Wrong-type rejection on a property value

| Likely cause                                                              | How to verify                                                                                  | Fix                                                                                          |
|---------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| You sent a string for a numeric property (e.g. `"7.5"` instead of `7.5`)  | Inspect the JSON in `input_params`.                                                              | Send a JSON number, not a string. JSON's type is significant.                                |
| You sent `null` to "clear" a property                                       | Inspect the `value` field.                                                                       | Property writes overwrite; they don't delete. To delete, use a different policy with `allowed_deletes` on `<var>.property.<name>`. |

## Symptom: Metadata is wrong / missing in the response

| Likely cause                                                              | How to verify                                                                                  | Fix                                                                                          |
|---------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| The KQ's `nodes` array doesn't project the metadata path                   | Inspect the `nodes` array.                                                                       | Add `<var>.property.<name>.metadata.<meta>` for each metadata key you want returned.         |
| Metadata `type` was supplied as `$param` (only `value` may be `$param`)    | Inspect each metadata entry.                                                                     | Hardcode the metadata `type`.                                                                 |
| `$token.iss` doesn't appear in the metadata you wrote                       | Decode the Bearer token; check it has a `iss` claim.                                             | Ensure the token issuer is set correctly at the IdP.                                          |

## Symptom: `401 Unauthorized` on a Person-subject write

| Likely cause                                                              | Fix                                                                                          |
|---------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| Bearer token missing                                                       | Add `Authorization: Bearer <user-token>`.                                                    |
| Bearer token expired                                                       | Refresh and retry.                                                                            |
| Token's `sub` not seeded as a Person `external_id`                         | Either seed the Person, or use a different test user.                                        |

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

# Read back the property after the write (assumes a paired read-policy + read-KQ)
QUERY_ID="<read-kq-gid>" ./scripts/execute.sh /tmp/input_params.json | jq

# Check that update_time changed (indicating the write actually happened)
QUERY_ID="<full-node-projection-kq-gid>" ./scripts/execute.sh /tmp/input_params.json \
  | jq '.data[0].nodes.subject.Props.update_time'
```

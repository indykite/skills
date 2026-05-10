# IndyKite CIQ Add-Relationship-Property Troubleshooting

A symptom-first map. Walk it top-down — earlier rows are cheaper to verify.

## Symptom: `403 Forbidden` on a property write that "should work"

| Likely cause                                                                                          | Fix                                                                                          |
|-------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| KQ's `upsert_relationships[].name` not in policy's `existing_relationships`                           | Add the variable to `existing_relationships` and republish, or change the KQ's `name`.       |
| KQ entry is a fresh value (not a cypher variable)                                                      | Use a name that's bound in the policy's `cypher` (e.g. `r`).                                 |
| KQ includes a protected property name (`_service`, `create_time`, `id`, `type`, `update_time`)        | Remove the protected property entry.                                                         |
| KQ entry includes `source` / `target` / `type`                                                         | Remove them. They're only valid on a create; including them flips the operation.             |
| Policy filter rejects the subject                                                                      | For Person: confirm Bearer's `sub` matches a seeded `Person.external_id`. For `_Application`: confirm the AppAgent matches. |

## Symptom: `200` with empty `data` (no relationship matched)

| Likely cause                                                       | Fix                                                                                          |
|--------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| The relationship doesn't exist between the supplied endpoints       | Spot-check with a read query first; create the missing edge with [`indykite-ciq-create-relationship`](../../indykite-ciq-create-relationship/SKILL.md) if needed. |
| Endpoints don't exist with the supplied `external_id`s              | Seed the missing nodes, or correct the values in `input_params`.                              |
| Filter clause references a property the matched edge doesn't have    | Inspect the existing edge's properties.                                                       |

## Symptom: `422 invalid_argument: missing or wrong input params`

| Likely cause                                                              | Fix                                                                                          |
|---------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| A `$param` in the policy filter is not in `input_params`                   | Add the missing key (no `$` prefix).                                                          |
| A `$param` in `properties[].value` or metadata is not in `input_params`    | Add the missing key.                                                                         |
| You passed `_appId` (or `$_appId`) explicitly                              | Remove it. `$_appId` is reserved.                                                            |

## Symptom: Property write returns `200` but value isn't visible in subsequent reads

| Likely cause                                                              | Fix                                                                                          |
|---------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| Read-side policy doesn't list the property in `allowed_reads.relationships` | Add `<var>.<name>` (or `<var>.*`) to `allowed_reads.relationships`.                          |
| Read-side KQ projects different properties                                  | Add the property path to the read KQ's `relationships` array.                                 |
| `update_time` on the relationship was NOT bumped                            | The write didn't actually happen — go back to the `403` / empty-data symptoms above.          |

## Symptom: Wrong-type rejection on a property value

| Likely cause                                                              | Fix                                                                                          |
|---------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| You sent a string for a numeric / boolean property                         | Send the right JSON type. JSON's type is significant.                                         |
| You sent `null` to "clear" a property                                       | Property writes overwrite; they don't delete. To delete a property, use [`indykite-ciq-delete`](../../indykite-ciq-delete/SKILL.md). |

## Symptom: `401 Unauthorized` on a Person-subject write

| Likely cause                                                              | Fix                                                                                          |
|---------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| Bearer token missing                                                       | Add `Authorization: Bearer <user-token>`.                                                    |
| Bearer token expired                                                       | Refresh and retry.                                                                            |
| Token's `sub` not seeded as a Person `external_id`                         | Either seed the Person, or use a different test user.                                        |

## Useful one-liners

```bash
# Show every $param a policy file references
jq -r '.policy' policy.json | jq -r '..|strings|select(test("^\\$"))'

# Show every $param a KQ file references
jq -r '.query' knowledge-query.json | jq -r '..|strings|select(test("^\\$"))'

# Confirm the relationship exists before retrying a failing write
QUERY_ID="<read-kq-with-played-at>" ./scripts/execute.sh /tmp/input_params.json | jq

# Check that the relationship's update_time changed
QUERY_ID="<read-kq-with-relationship-Props>" ./scripts/execute.sh /tmp/input_params.json \
  | jq '.data[0].relationships.r.Props.update_time'
```

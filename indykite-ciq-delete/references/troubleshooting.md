# IndyKite CIQ Delete Troubleshooting

A symptom-first map. Walk it top-down.

## Symptom: `403 Forbidden` on a delete that "should work"

| Likely cause                                                                                          | Fix                                                                                          |
|-------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| KQ's entry not in policy's `allowed_deletes` (literally or via a wildcard)                             | Add the entry to `allowed_deletes.nodes` or `.relationships` and republish.                  |
| Entry uses the wrong path syntax — node properties are `<var>.property.<name>`; relationship properties are `<var>.<name>` (no `.property.`) | Use the right syntax for the element type.                            |
| Target is a protected property (`_service`, `create_time`, `external_id`, `id`, `type`, `update_time`) | Remove the target. These cannot be deleted.                                                  |
| Policy is in `INACTIVE` status                                                                         | Patch to `ACTIVE`.                                                                            |
| Policy filter rejects the subject                                                                      | For Person: confirm Bearer's `sub` matches a seeded `Person.external_id`.                    |

## Symptom: `200` with empty `data` (delete didn't happen?)

This is ambiguous: the cypher matched no rows. Two scenarios:

| Scenario                                                                  | Diagnosis                                                                                  |
|---------------------------------------------------------------------------|--------------------------------------------------------------------------------------------|
| You're re-running a successful delete                                      | This is the **idempotent success** case. The target is already gone. Run a read to confirm. |
| You expected the target to exist                                            | The cypher anchor isn't matching. Check `external_id`s, the bearer's `sub`, and any path-walking constraints. |

## Symptom: The element is still there after `200`

| Likely cause                                                              | Fix                                                                                          |
|---------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| Read-side cache is stale                                                   | Wait or invalidate; re-run the read after a few seconds.                                      |
| You deleted a *different* element (wrong `external_id` in `input_params`) | Inspect the response (if it included projections) or rerun with verified IDs.                |
| You deleted only one property but expected the whole node gone             | Inspect the KQ's `delete_nodes` — `"car.property.color"` deletes only the property; `"car"` deletes the node. |
| You deleted only one relationship property but expected the whole edge     | `"r.status"` deletes only the property; `"r"` deletes the relationship.                       |

## Symptom: `422 invalid_argument: missing or wrong input params`

| Likely cause                                                              | Fix                                                                                          |
|---------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| A `$param` in the policy filter is not in `input_params`                   | Add the missing key (no `$` prefix).                                                          |
| You passed `_appId` (or `$_appId`) explicitly                              | Remove it. `$_appId` is reserved.                                                            |

## Symptom: Cascading deletion concerns

Deleting a node also deletes all relationships incident to it. If that's not what you want:

- Delete only specific properties (`<var>.property.<name>`) instead of the whole node.
- Or delete the relationships *first* (with a paired delete-relationship policy/KQ) then leave the node alone.

There is no "delete-without-cascade" option.

## Symptom: `401 Unauthorized` on a Person-subject delete

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

# Confirm the target exists before retrying a failing delete
QUERY_ID="<read-kq-gid>" ./scripts/execute.sh /tmp/input_params.json | jq

# Confirm the delete by checking the property is now missing
QUERY_ID="<read-kq-gid>" ./scripts/execute.sh /tmp/input_params.json \
  | jq '.data[0].nodes."subject.property.music_mood" // "<deleted>"'

# Check that update_time bumped (writes and deletes both bump it)
QUERY_ID="<full-node-projection-kq-gid>" ./scripts/execute.sh /tmp/input_params.json \
  | jq '.data[0].nodes.subject.Props.update_time'
```

# IndyKite CIQ Create-Node-With-Link Troubleshooting

A symptom-first map. Walk it top-down.

## Symptom: `403 Forbidden` on a combined-create that "should work"

| Likely cause                                                                                          | Fix                                                                                          |
|-------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| KQ's `upsert_nodes[].type` not in `allowed_upserts.nodes.node_types`                                   | Add the label to `node_types` and republish.                                                  |
| KQ's `upsert_relationships[]` triple not in `allowed_upserts.relationships.relationship_types`         | Add the triple. Direction matters — `(A)-[T]->(B)` differs from `(B)-[T]->(A)`.               |
| Protected property name in either `upsert_nodes` or `upsert_relationships` properties                   | Remove `_service`, `create_time`, `external_id`, `id`, `type`, `update_time` from properties. |
| Source/target in `upsert_relationships` references a **node label** instead of a variable name          | Use the variable: `"source": "vehicle"` not `"source": "Vehicle"`.                            |
| Source/target references a name that's neither in cypher nor in `upsert_nodes`                          | Fix the typo. The string must match one of those two sets exactly.                            |

## Symptom: `200` with empty `data` (nothing got created)

| Likely cause                                                                                          | Fix                                                                                          |
|-------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| One or more existing endpoints don't exist with the supplied `external_id`s                            | Spot-check each endpoint with a read query. Seed missing ones, or correct the values.        |
| Connected cypher path is broken (e.g. `(:_Application)-[:HAS_AGREEMENT_WITH]->(:Company)` doesn't exist) | Either pre-create the missing relationship, or change the policy to disjoint `MATCH` clauses. |

## Symptom: `422 invalid_argument: missing or wrong input params`

| Likely cause                                                              | Fix                                                                                          |
|---------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| A `$param` in the policy filter is not in `input_params`                   | Add the missing key.                                                                         |
| The new node's `$external_id` is missing                                    | Add it (without the `$`).                                                                    |
| A property `$param` is missing                                              | Add it.                                                                                       |
| You passed `_appId` (or `$_appId`) explicitly                              | Remove it.                                                                                    |

## Symptom: Wiring is wrong after a successful create

The most common silent failure mode in combined-creates. The platform creates the node and the relationships, but the relationships go to the wrong endpoints.

| Likely cause                                                                                          | Fix                                                                                          |
|-------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| Cross-reference typo: `upsert_relationships[].source` references a name that doesn't quite match `upsert_nodes[].name` | Fix the typo. The strings must match exactly.                          |
| Direction confusion: triple is `(Contract)-[:COVERS]->(Vehicle)` but you wrote `"source": "vehicle"` and `"target": "contract"` | Match direction to the `relationship_types` triple.                  |
| Two `upsert_relationships` entries with the same `name`                                               | Use distinct `name` values. Same applies to `upsert_nodes`.                                  |

To detect this: project the relationships in the response (`"relationships": ["r3", "r4"]`) and check `StartElementId` / `EndElementId` against what you expected.

## Symptom: Re-run created duplicate relationships

This shouldn't happen — the platform upserts on `(source, target, type)`. If you genuinely see duplicates:

| Likely cause                                                                                          | Fix                                                                                          |
|-------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| Different `external_id`s on what you thought was the same new node                                    | Audit the `input_params` from each run.                                                       |
| The IKG model declares parallel relationships of the same type as distinct (rare)                       | Check the model.                                                                              |

## Symptom: Atomicity violated (some writes happened, some didn't)

The platform's combined-create is transactional. If you observe partial success, that's a platform bug worth reporting upstream — but first check:

- Are you actually running one execute, or two? Two separate `POST /contx-iq/v1/execute` calls (one create-node, one create-relationship) are not atomic. Use this skill's combined Knowledge Query.
- Did you accidentally retry just one half?

## Symptom: `401 Unauthorized` on a Person-subject combined-create

| Likely cause                                                              | Fix                                                                                          |
|---------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| Bearer token missing or expired                                            | Add or refresh.                                                                              |
| Token's `sub` not seeded as a Person                                       | Seed, or use a different test user.                                                          |

## Useful one-liners

```bash
# List every variable name in a combined-create KQ (helps spot typos)
jq -r '.query' kq.json | jq -r '
  (.upsert_nodes // []) | .[].name,
  (.upsert_relationships // []) | .[] | (.name, .source, .target)
'

# Show every $param a policy or KQ references
jq -r '.policy' policy.json | jq -r '..|strings|select(test("^\\$"))'
jq -r '.query'  kq.json     | jq -r '..|strings|select(test("^\\$"))'

# Confirm the new node was created and properly wired
QUERY_ID="<read-kq-with-contract-and-relationships>" ./scripts/execute.sh /tmp/input_params.json | jq
```

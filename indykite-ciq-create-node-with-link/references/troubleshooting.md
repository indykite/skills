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

## Symptom: `422 invalid_argument: invalid <type> metadata value in input params`

A `$param` used as the value of an `assurance_level`, `verified_time` or `source` metadata entry received a value of the wrong shape: `assurance_level` must be `1`, `2` or `3`, `verified_time` an RFC 3339 timestamp string, `source` a string. Nothing was written. Fix the value in `input_params`. The same rule on a hardcoded value refuses the Knowledge Query when it is saved, with `invalid <type> for node <name>`.

## Symptom: `401 Unauthorized` on a Person-subject combined-create

| Likely cause                                                              | Fix                                                                                          |
|---------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| Bearer token missing or expired                                            | Add or refresh.                                                                              |
| Token's `sub` not seeded as a Person                                       | Seed, or use a different test user.                                                          |

## Symptom: execution is fast on a small graph, slow as data grows

| Likely cause                                                       | How to verify                                                                                        | Fix                                                                                          |
|--------------------------------------------------------------------|------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| Policy `condition.cypher` is anchored on a high-fan-in node (a brand / tenant / category most records point to) instead of the subject | Execution time grows roughly linearly with dataset size, and the pattern's only selective filters sit at the endpoints of a multi-hop chain. | Take the fan-in node out of the connected chain (separate `MATCH` pinned by `external_id` + a `WHERE (x)-[:REL]->(fanin)` pattern predicate), or pin the subject with `WHERE … WITH subject LIMIT 1` — see "Performance: pin the subject before high-fan-in hops" in `policy-reference.md`. |

## Symptom: a `2.0-ciq` (CIQ v2) policy or query misbehaves

See the version differences in [`policy-reference.md`](policy-reference.md#metapolicy_version).

| Likely cause | How to verify | Fix |
|--------------|---------------|-----|
| A filter that worked on `1.0-ciq` matches nothing on `2.0-ciq` | An `attribute` without the `@` prefix (`subject.external_id`) is a literal string in v2. | Write `"attribute": "@subject.external_id"` - in the policy's `condition.filter` and in every Knowledge Query `filter`. |
| `token filter attribute references cypher value: @…` | A `token_filter` attribute names a graph value. | `token_filter` reads token claims only; move the graph comparison to `condition.filter`. |
| `untyped relationship <name> cannot be used in <section>` | An untyped `-[r]->` is listed in `allowed_upserts.relationships.existing_relationships` or `allowed_deletes.relationships`. | Give the relationship a type in the Cypher. |
| `422` `missing or wrong input params, '…'` naming a parameter only `condition.cypher` uses | v2 checks every parameter before the query runs (`1.0-ciq` answered `500` from the graph database instead). | Send every listed name in `input_params`. |
| `upsert value @<ref> must reference a variable of the policy cypher` (and the other `upsert value @…` / `invalid upsert value @…` / `must not start with __ref_` messages) | An `@` reference in an upsert value breaks a rule - see [`knowledge-query-reference.md`](knowledge-query-reference.md#v2-only-copying-graph-values-with--references). | Point it at an in-scope policy variable with an attribute / property / metadata / trust-score path or an aggregate alias; write token claims as `$token.<claim>`. |
| An upsert with an `@` reference returns `200` but one property was not written | The referenced value was null for that row (e.g. the matched node lacks the property), so nothing was written for it. | Read the source value first; make the condition match only rows that hold it. |

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

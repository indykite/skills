# IndyKite CIQ Create-Relationship Troubleshooting

A symptom-first map. Walk it top-down — earlier rows are cheaper to verify.

## Symptom: `403 Forbidden` on a create that "should work"

| Likely cause                                                                                          | How to verify                                                                                     | Fix                                                                                              |
|-------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------|
| `(source-label, type, target-label)` triple is not in `allowed_upserts.relationships.relationship_types` | Compare the KQ's relationship triple to the policy's whitelist. Check direction: `(A)-[T]->(B)` and `(B)-[T]->(A)` are different triples. | Add the triple to the policy (and republish), or change the KQ.                                  |
| `source` or `target` in the KQ is a node **label** instead of a cypher **variable name**              | Cross-check the policy's cypher: `(track:Track)` declares variable `track` (label `Track`). The KQ should use `"source": "track"`. | Use the variable name (lowercase by convention), not the label.                                  |
| Policy uses `existing_relationships` only (no `relationship_types`)                                   | Look for `allowed_upserts.relationships.existing_relationships` and absence of `relationship_types`. | Add `relationship_types: [{type, source_node_label, target_node_label}]`. The two keys serve different operations. |
| Policy filter rejects the subject                                                                      | For `_Application`: confirm the AppAgent matches the filter.<br>For Person: confirm the Bearer's `sub` matches a seeded `Person.external_id`. | Use the right token. Don't try to override `$_appId` in `input_params`.                          |
| Policy is in `INACTIVE` status                                                                         | `GET /configs/v1/authorization-policies/<gid>` and check `status`.                                | Patch to `ACTIVE`.                                                                                |

## Symptom: `200` with empty `data` array (no edge created)

| Likely cause                                                       | How to verify                                                                                                       | Fix                                                                                          |
|--------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| One or both endpoint nodes don't exist with the supplied `external_id`s | Spot-check with a read query (or query the IKG directly): `MATCH (n {external_id: "<id>"}) RETURN n LIMIT 1`.       | Seed the missing node(s), or correct the `external_id` value in `input_params`.              |
| The cypher's connectivity requirement isn't satisfied               | Re-read the policy's `cypher`. If it requires the endpoints to share an existing path, that path must already exist.  | Either pre-create the connecting path, or simplify the cypher to disjoint `MATCH` clauses.   |
| Filter clause references a property the endpoint doesn't have       | Inspect the failing endpoint's properties.                                                                          | Either add the property, or change the filter to use a property that exists.                 |

## Symptom: `422 invalid_argument: missing or wrong input params`

| Likely cause                                                              | How to verify                                                                                  | Fix                                                                                          |
|---------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| A `$param` in the policy filter is not in `input_params`                   | `grep -E '"\$[a-z_]+"' <policy.json>` and compare to the request body.                          | Add the missing key (no `$` prefix) with the right value.                                     |
| A `$param` in `upsert_relationships[].properties[].value` is not in `input_params` | Inspect the properties array.                                                            | Add the missing key.                                                                         |
| You passed `_appId` (or `$_appId`) explicitly                              | Inspect `input_params`.                                                                         | Remove it. `$_appId` is reserved and auto-filled.                                             |
| `input_params` was sent under the wrong key                                 | Inspect the request body.                                                                       | Use exactly `"input_params"`.                                                                |

## Symptom: Create returns `200` with the new edge, but a follow-up read can't see it

| Likely cause                                                              | How to verify                                                                                  | Fix                                                                                          |
|---------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| The read-side policy doesn't whitelist the new relationship in `allowed_reads.relationships` | Inspect the read policy.                                                       | Add the relationship variable to `allowed_reads.relationships` and republish.                |
| The read-side cypher doesn't match the new edge (e.g. wrong direction or label) | Trace the read cypher against the new edge's `(source, type, target)`.                | Adjust the read cypher.                                                                      |
| Caching/stale data in the consumer                                         | Re-run the read after a few seconds.                                                            | Wait or invalidate any client-side cache.                                                    |

## Symptom: "duplicate" relationship complaint or unexpected upsert

| Likely cause                                                              | Fix                                                                                          |
|---------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| Re-running with the same `(source, target, type)` upserts (matches the existing edge) | This is documented behaviour, not an error. Don't expect parallel-edge semantics unless your IKG model declares them. |
| Properties on the existing edge got overwritten                            | This is also documented — `upsert_relationships[].properties` overwrite on match. Use a guard property and `IS NULL` filter if you want create-only-if-missing. |

## Symptom: Property value is wrong type on the new relationship

| Likely cause                                                              | Fix                                                                                          |
|---------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| You sent a string for a numeric property (e.g. `"7.5"` instead of `7.5`)   | Send a JSON number, not a string.                                                            |
| The IKG already has a different type recorded for that relationship property | Decide which type wins; if you're correct, you may need to delete the old edge first.        |

## Symptom: `401 Unauthorized` on a Person-subject create

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

# Confirm both endpoints exist before retrying a failing create
# (assumes a generic read KQ keyed on external_id; adapt to your read policy)
QUERY_ID="<read-kq-gid>" \
  bash -c 'echo "{\"endpoint_id\":\"track-99\"}" | ./scripts/execute.sh -' | jq

# Watch for the new edge in subsequent reads
QUERY_ID="<read-kq-with-played-at>" ./scripts/execute.sh /tmp/input_params.json | jq
```

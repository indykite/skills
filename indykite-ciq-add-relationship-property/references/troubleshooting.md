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
| A `$param` in `properties[].value` is not in `input_params`                | Add the missing key.                                                                         |
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

# KBAC Troubleshooting

Most KBAC surprises are a `200` response carrying an unexpected `decision`. Work top-down - cheap checks first.

## Decision is `false` when you expected `true`

1. **Policy ACTIVE?** A draft or inactive policy never participates. Confirm the policy status is `ACTIVE`.
2. **Triple matches the policy?**
   - `subject.type` in the request equals the policy's `subject.type`.
   - `action.name` is one of the policy's `actions` (case-sensitive - `PROVISION` ≠ `provision`).
   - `resource.type` equals the policy's `resource.type`.
3. **Reserved variable names.** The condition must bind variables literally named `subject` and `resource`. If the Cypher uses other names (`p`, `server`), the request's subject/resource never bind and the condition matches nothing.
4. **IDs are `external_id`s.** `subject.id` / `resource.id` are matched against node `external_id`, not internal GIDs or display names. A wrong id silently yields `false`.
5. **Partial parameters supplied and typed.** Every `$name` in the condition must appear in `context.input_params` (without the `$`). A numeric comparison (`<= $max_price`) needs a number, not a string - `"120000"` may not compare as expected.
6. **Graph data exists.** The subject node, resource node, and any matched relationship must exist in the IKG. Confirm with a graph probe before blaming the policy.

## Decision is `true` when you expected `false`

1. **Another policy grants it.** Decisions are a logical OR across all ACTIVE policies. A broader policy (e.g. one with no `WHERE`, or a different relationship) may grant the triple. Search for every policy whose `subject.type` / `actions` / `resource.type` cover the request.
2. **Condition weaker than intended.** A missing `WHERE`, an `OR` where you meant `AND`, or a relationship match with no property guard will pass more than you expect. Re-read `condition.cypher`.
3. **Stale policy.** A previously created test policy may still be ACTIVE. List policies and deactivate or delete the ones you no longer want.

## `422 Unprocessable Entity` (missing input params)

- A single `/evaluation` returns `422` when `input_params` is missing a parameter the condition needs; the body carries `errors: ["missing or wrong input params, '<name>'"]`. The condition's `$name` set and the `input_params` keys must line up exactly. (A *batch* `/evaluations` call surfaces the same problem per entry instead, as `decision: false` with `context.reason`.)

## `400 Bad Request`

- Malformed JSON or a missing required field. Fix the request body shape.

## `401 Unauthorized`

- Invalid AppAgent credentials, or an invalid user token when one is supplied. Refresh the AppAgent credentials; if a user token is required, confirm it is valid.

## Isolating which policy decided

- Use **action search** (`/access/v1/search/action`) with the same subject + resource to list every action currently granted - if your action appears there unexpectedly, a policy grants it.
- Temporarily deactivate candidate policies one at a time and re-evaluate to find the one responsible.
- Reduce the condition to its simplest matching form (just the `MATCH`, no `WHERE`), confirm `true`, then add each clause back until the decision flips - that clause is the cause.

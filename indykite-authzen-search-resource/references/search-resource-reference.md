# AuthZEN Resource Search Reference

Resource search answers: *which resources may this subject perform a given action on?* Given one subject, one action, and a resource **type**, it returns the matching resource instances under the project's currently ACTIVE policies and the current graph state.

## Endpoint

```text
POST <API_URL>/access/v1/search/resource
```

`<API_URL>` is the regional IndyKite API base (`https://eu.api.indykite.com` or `https://us.api.indykite.com`). All AuthZEN endpoints live under `/access/v1`.

## Authentication

The call authenticates the **calling application** via its AppAgent credentials - always required. A **user access token** is **optional** and applies only in some cases (e.g. a policy condition references a token claim); when supplied it can *narrow* the results, and an invalid/wrong user token yields fewer or empty results rather than an error. The mapping of each credential to its request header is documented in the [Credentials guide](https://developer.indykite.com/guides/guide-credentials); the skill's helper script sets the headers from environment variables.

The subject is identified by `subject.id` (matched to a node `external_id`), not by the caller's credentials.

## Request

The subject is fully pinned; the resource carries **only a `type`** — you are searching across resources of that type. The action is required (it scopes the search).

```json
{
  "subject":  { "type": "Person", "id": "linus" },
  "resource": { "type": "Server" },
  "action":   { "name": "PROVISION" },
  "context":  { "input_params": { "max_price": 4000 } }
}
```

| Field                  | Required | Notes                                                                                  |
|------------------------|----------|----------------------------------------------------------------------------------------|
| `subject.type`         | yes      | Node type making the request.                                                           |
| `subject.id`           | yes      | The subject node's `external_id`.                                                       |
| `resource.type`        | yes      | Node type to search over. **Do not** set `resource.id` — that is what the search returns. |
| `action.name`          | yes      | The single action to test (case-sensitive).                                            |
| `context.input_params` | maybe    | Supply every `$name` partial parameter the policy references (key without the `$`). Required only if the policy uses one. |

## Response

```json
{ "results": [ { "type": "Server", "id": "edge-box-2" } ] }
```

Each `results[]` entry is a resource (`type` + `id`, the `external_id`) the subject may perform the action on. An empty `results` array means no resource of that type is permitted — a normal `200`, not an error.

## Error semantics

| HTTP code          | When                                                                               | Likely fix                                                                  |
|--------------------|------------------------------------------------------------------------------------|-----------------------------------------------------------------------------|
| `200` + `results:[]`| Well-formed, but no resource of that type is granted (or a user token narrowed it to nothing). | Confirm a matching ACTIVE policy and resource nodes exist. Not an error.    |
| `422 Unprocessable`| The policy needs a partial parameter that `input_params` did not supply.           | Add the missing key, e.g. `"errors": ["missing or wrong input params, 'max_price'"]`. |
| `400 Bad Request`  | Malformed JSON or missing required field (e.g. no `action`).                       | Fix the request body.                                                       |
| `401 Unauthorized` | Invalid AppAgent credentials.                                                       | Refresh the AppAgent credentials.                                           |
| `404 Not Found`    | Wrong base path or project context.                                                | Confirm `<API_URL>/access/v1/search/resource` and the credentials' project. |
| `5xx`              | Server-side issue.                                                                  | Retry with backoff; escalate if persistent.                                |

## Troubleshooting empty / unexpected results

1. **`resource.id` accidentally set?** Resource search takes `resource.type` only. An `id` here over-constrains the search.
2. **Action matches a policy?** `action.name` must be one of an ACTIVE policy's `actions` (case-sensitive).
3. **`subject.id` is an `external_id`?** A wrong id silently matches no node.
4. **Partial parameters supplied and typed?** Tightening `max_price` shrinks the result set; a string where a number is expected can drop everything.
5. **Resource nodes exist?** The candidate resource nodes (and any matched relationship) must be in the IKG.
6. **User token narrowing?** If you sent a user access token, a wrong/expired one can drop claim-gated resources; retry without it to see the baseline.

## Sibling endpoints

- `/access/v1/search/action` — actions a subject may perform on a resource ([`indykite-authzen-search-action`](../../indykite-authzen-search-action/SKILL.md)).
- `/access/v1/search/subject` — subjects allowed an action on a resource ([`indykite-authzen-search-subject`](../../indykite-authzen-search-subject/SKILL.md)).
- `/access/v1/evaluation` and `/access/v1/evaluations` — single and batch yes/no decisions ([`indykite-authzen-evaluation`](../../indykite-authzen-evaluation/SKILL.md), [`indykite-authzen-evaluations`](../../indykite-authzen-evaluations/SKILL.md)).

Policy authoring (the `2.0-kbac` policy these results are evaluated against) lives in [`indykite-authzen-kbac-policies`](../../indykite-authzen-kbac-policies/SKILL.md).

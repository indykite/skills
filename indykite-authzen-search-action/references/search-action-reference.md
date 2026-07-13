# AuthZEN Action Search Reference

Action search answers: *which actions may this subject perform on this resource?* It returns the list of granted action names under the project's currently ACTIVE policies and the current graph state — not a single yes/no decision.

## Endpoint

```text
POST <API_URL>/access/v1/search/action
```

`<API_URL>` is the regional IndyKite API base (`https://eu.api.indykite.com` or `https://us.api.indykite.com`). All AuthZEN endpoints live under `/access/v1`.

## Authentication

The call authenticates the **calling application** via its AppAgent credentials - always required. A **user access token** is **optional** and applies only in some cases (e.g. a policy condition references a token claim); when supplied it can *narrow* the results, and an invalid/wrong user token yields fewer or empty results rather than an error. The mapping of each credential to its request header is documented in the [Credentials guide](https://developer.indykite.com/guides/guide-credentials); the skill's helper script sets the headers from environment variables.

The subject is identified by `subject.id` (matched to a node `external_id`), not by the caller's credentials.

## Request

Both the subject and the resource are fully pinned — you ask about one specific pair.

```json
{
  "subject":  { "type": "Person", "id": "linus" },
  "resource": { "type": "Server",    "id": "gpu-node-7" },
  "context":  { "input_params": { "max_price": 120000 } }
}
```

| Field                  | Required | Notes                                                                                  |
|------------------------|----------|----------------------------------------------------------------------------------------|
| `subject.type`         | yes      | Node type making the request.                                                           |
| `subject.id`           | yes      | The subject node's `external_id`.                                                       |
| `resource.type`        | yes      | Node type being acted on.                                                               |
| `resource.id`          | yes      | The resource node's `external_id`.                                                      |
| `context.input_params` | maybe    | Supply every `$name` partial parameter that any candidate policy references (key without the `$`). Required only if a relevant policy uses one. |

There is no `action` field — discovering the actions is the point.

## Response

```json
{ "results": [ { "name": "DEPLOY" }, { "name": "REBOOT" }, { "name": "SNAPSHOT" } ] }
```

Each `results[]` entry is an action the subject may currently perform on that resource. An empty `results` array means no action is granted — this is a normal `200`, not an error.

## Error semantics

| HTTP code          | When                                                                               | Likely fix                                                                  |
|--------------------|------------------------------------------------------------------------------------|-----------------------------------------------------------------------------|
| `200` + `results:[]`| Well-formed, but no policy grants any action for the pair (or a user token narrowed it to nothing). | Confirm a matching ACTIVE policy exists and the graph data is present. Not an error. |
| `422 Unprocessable`| A candidate policy needs a partial parameter that `input_params` did not supply.   | Add the missing key, e.g. `"errors": ["missing or wrong input params, 'max_price'"]`. |
| `400 Bad Request`  | Malformed JSON or missing required field.                                          | Fix the request body.                                                       |
| `401 Unauthorized` | Invalid AppAgent credentials.                                                       | Refresh the AppAgent credentials.                                           |
| `404 Not Found`    | Wrong base path or project context.                                                | Confirm `<API_URL>/access/v1/search/action` and the credentials' project.  |
| `5xx`              | Server-side issue.                                                                  | Retry with backoff; escalate if persistent.                                |

## Troubleshooting empty / unexpected results

1. **Policy ACTIVE and matching?** Only ACTIVE policies whose `subject.type` and `resource.type` match the request contribute actions.
2. **IDs are `external_id`s?** A wrong `subject.id` / `resource.id` silently matches no node → empty results.
3. **Partial parameters supplied and typed?** A numeric guard (`<= $max_price`) needs a number, not a string.
4. **Graph data present?** The subject node, resource node, and any matched relationship must exist in the IKG.
5. **User token narrowing?** If you sent a user access token, a wrong/expired one can drop claim-gated actions; retry without it to see the AppAgent-only baseline.

## Sibling endpoints

- `/access/v1/search/resource` — resources a subject may act on, given an action ([`indykite-authzen-search-resource`](../../indykite-authzen-search-resource/SKILL.md)).
- `/access/v1/search/subject` — subjects allowed an action on a resource ([`indykite-authzen-search-subject`](../../indykite-authzen-search-subject/SKILL.md)).
- `/access/v1/evaluation` and `/access/v1/evaluations` — single and batch yes/no decisions ([`indykite-authzen-evaluation`](../../indykite-authzen-evaluation/SKILL.md), [`indykite-authzen-evaluations`](../../indykite-authzen-evaluations/SKILL.md)).

Policy authoring (the `2.0-kbac` policy whose `actions` these results come from) lives in [`indykite-authzen-kbac-policies`](../../indykite-authzen-kbac-policies/SKILL.md).

# AuthZEN Subject Search Reference

Subject search answers: *which subjects may perform a given action on this resource?* Given a subject **type**, one resource, and one action, it returns the matching subject instances under the project's currently ACTIVE policies and the current graph state.

## Endpoint

```text
POST <API_URL>/access/v1/search/subject
```

`<API_URL>` is the regional IndyKite API base (`https://eu.api.indykite.com` or `https://us.api.indykite.com`). All AuthZEN endpoints live under `/access/v1`.

## Authentication

- **Always**: `X-IK-ClientKey: <AppAgent-credentials-token>` — authenticates the calling application.
- **Optional**: `Authorization: Bearer <user-access-token>` — applies only in some cases. For subject search the user token typically has **no effect** on the result set (you are enumerating subjects, not acting as one), but it is accepted.

## Request

The resource is fully pinned; the subject carries **only a `type`** — you are searching across subjects of that type. The action is required (it scopes the search).

```json
{
  "subject":  { "type": "Person" },
  "resource": { "type": "Server", "id": "gpu-node-7" },
  "action":   { "name": "PROVISION" },
  "context":  { "input_params": { "max_price": 80000 } }
}
```

| Field                  | Required | Notes                                                                                  |
|------------------------|----------|----------------------------------------------------------------------------------------|
| `subject.type`         | yes      | Node type to search over. **Do not** set `subject.id` — that is what the search returns. |
| `resource.type`        | yes      | Node type being acted on.                                                               |
| `resource.id`          | yes      | The resource node's `external_id`.                                                      |
| `action.name`          | yes      | The single action to test (case-sensitive).                                            |
| `context.input_params` | maybe    | Supply every `$name` partial parameter the policy references (key without the `$`). Required only if the policy uses one. |

## Response

```json
{ "results": [ { "type": "Person", "id": "grace" }, { "type": "Person", "id": "dennis" } ] }
```

Each `results[]` entry is a subject (`type` + `id`, the `external_id`) allowed the action on that resource. An empty `results` array means no subject of that type is permitted — a normal `200`, not an error.

## Error semantics

| HTTP code          | When                                                                               | Likely fix                                                                  |
|--------------------|------------------------------------------------------------------------------------|-----------------------------------------------------------------------------|
| `200` + `results:[]`| Well-formed, but no subject of that type is granted the action on the resource.    | Confirm a matching ACTIVE policy and subject nodes exist. Not an error.     |
| `422 Unprocessable`| The policy needs a partial parameter that `input_params` did not supply.           | Add the missing key, e.g. `"errors": ["missing or wrong input params, 'max_price'"]`. |
| `400 Bad Request`  | Malformed JSON or missing required field (e.g. no `action` or no `resource.id`).   | Fix the request body.                                                       |
| `401 Unauthorized` | Invalid `X-IK-ClientKey`.                                                           | Refresh the AppAgent credentials token.                                     |
| `404 Not Found`    | Wrong base path or project context.                                                | Confirm `<API_URL>/access/v1/search/subject` and the credentials' project.  |
| `5xx`              | Server-side issue.                                                                  | Retry with backoff; escalate if persistent.                                |

## Troubleshooting empty / unexpected results

1. **`subject.id` accidentally set?** Subject search takes `subject.type` only. An `id` here over-constrains the search.
2. **`resource.id` is an `external_id`?** A wrong resource id silently matches no node → empty results.
3. **Action matches a policy?** `action.name` must be one of an ACTIVE policy's `actions` (case-sensitive).
4. **Partial parameters supplied and typed?** Loosening `max_price` widens the set; a string where a number is expected can drop everything.
5. **Subject nodes exist?** The candidate subject nodes (and any matched relationship) must be in the IKG.

## Sibling endpoints

- `/access/v1/search/action` — actions a subject may perform on a resource ([`indykite-authzen-search-action`](../../indykite-authzen-search-action/SKILL.md)).
- `/access/v1/search/resource` — resources a subject may act on, given an action ([`indykite-authzen-search-resource`](../../indykite-authzen-search-resource/SKILL.md)).

Policy authoring (the `2.0-kbac` policy these results are evaluated against) lives in [`indykite-authzen-kbac`](../../indykite-authzen-kbac/SKILL.md).

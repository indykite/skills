# AuthZEN Subject Search Reference

Subject search answers: *which subjects may perform a given action on this resource?* Given a subject **type**, one resource, and one action, it returns the matching subject instances under the project's currently ACTIVE policies and the current graph state.

## Endpoint

```text
POST <API_URL>/access/v1/search/subject
```

`<API_URL>` is the regional IndyKite API base (`https://eu.api.indykite.com` or `https://us.api.indykite.com`). All AuthZEN endpoints live under `/access/v1`.

## Authentication

The call authenticates the **calling application** via its AppAgent credentials - always required. A **user access token** is accepted but applies only in some cases; for subject search it typically has **no effect** on the result set (you are enumerating subjects, not acting as one). The mapping of each credential to its request header is documented in the [Credentials guide](https://developer.indykite.com/guides/guide-credentials); the skill's helper script sets the headers from environment variables.

Requests routed through the Agent Gateway may also carry an `X-IK-Token` delegation token; see the [evaluation reference](../../indykite-authzen-evaluation/references/evaluation-reference.md#authentication). Subject search takes no user token into the policy, so the reserved `$token` and `$ik_token` claim parameters are bound **empty** here: a policy whose `condition.cypher` or `condition.filter` reads a claim (e.g. `$ik_token.act.sub`) matches no subject on this endpoint. Use evaluation, evaluations, or the resource / action searches for claim-dependent policies.

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
| `context.input_params` | maybe    | Supply every `$name` partial parameter the policy references (key without the `$`). Required only if the policy uses one. For a location-routed `3.0-kbac` policy (`USE graph.byName($region)` on a composite IKG) this is also where the **logical location** goes - `{ "region": "east" }`, a key of the project's `alias_mapping`, never a database name. |

The policy may be `2.0-kbac` or `3.0-kbac`; the search reads both. With a location-routed `3.0-kbac` policy the location physically routes the query, so only subjects whose full node is stored in the named constituent can be returned - pick the location the subjects live in, and expect an empty result from any other. A location that is missing, empty, unknown (not a key of `alias_mapping`), or `USE` routing on a project without a composite database is a `422` (below). Subject search names no `subject.id`, so the `3.0-kbac` bearer-token subject check that evaluation, batch evaluation, and the action and resource searches run (`403 bearer token subject differs from requested subject`) does not apply here. A `3.0-kbac` policy also matches subjects that were not ingested with `is_identity: true`, which a `2.0-kbac` policy never returns. Authoring rules are in [`indykite-authzen-kbac-policies`](../../indykite-authzen-kbac-policies/references/policy-reference.md#30-kbac-raw-cypher-and-location-routing).

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
| `422` + `location parameter "$<name>" must be a non-empty string` / `unknown location "<value>" for parameter "$<name>"` / `location parameter "$<name>" requires a composite database, …` / `policy requires a composite database, but the app space has none configured` | A `3.0-kbac` policy routes by location and the request's location is missing, malformed, unknown, or the project has no composite database. | Pass a key of the project's `alias_mapping` as a string under `context.input_params`. |
| `400 Bad Request`  | Malformed JSON or missing required field (e.g. no `action` or no `resource.id`).   | Fix the request body.                                                       |
| `401 Unauthorized` | Invalid AppAgent credentials.                                                       | Refresh the AppAgent credentials.                                           |
| `404 Not Found`    | Wrong base path or project context.                                                | Confirm `<API_URL>/access/v1/search/subject` and the credentials' project.  |
| `503` + `Unable to verify the AppAgent credential token, retry the request` | The credential could not be checked right now (transient); it was not judged. | Retry the same request with the same credential, with backoff. |
| `500` + `Unable to verify the AppAgent credential token` | Non-transient failure of the credential check; the credential was not judged. | Report the request's trace to IndyKite support; the credential itself was not judged. |
| other `5xx`        | Server-side issue.                                                                  | Retry with backoff; escalate if persistent.                                |

## Troubleshooting empty / unexpected results

1. **`subject.id` accidentally set?** Subject search takes `subject.type` only. An `id` here over-constrains the search.
2. **`resource.id` is an `external_id`?** A wrong resource id silently matches no node → empty results.
3. **Action matches a policy?** `action.name` must be one of an ACTIVE policy's `actions` (case-sensitive).
4. **Partial parameters supplied and typed?** Loosening `max_price` widens the set; a string where a number is expected can drop everything.
5. **Subject nodes exist?** The candidate subject nodes (and any matched relationship) must be in the IKG.

## Sibling endpoints

- `/access/v1/search/action` — actions a subject may perform on a resource ([`indykite-authzen-search-action`](../../indykite-authzen-search-action/SKILL.md)).
- `/access/v1/search/resource` — resources a subject may act on, given an action ([`indykite-authzen-search-resource`](../../indykite-authzen-search-resource/SKILL.md)).

Policy authoring (the `2.0-kbac` policy these results are evaluated against) lives in [`indykite-authzen-kbac-policies`](../../indykite-authzen-kbac-policies/SKILL.md).

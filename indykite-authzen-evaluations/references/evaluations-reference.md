# AuthZEN Batch Evaluations Reference

Batch evaluation runs **many KBAC decisions in one round trip**. Use it when one subject is checked against many resources, one action across many subjects, or any mix — each entry yields its own boolean `decision`, in order.

## Endpoint

```text
POST <API_URL>/access/v1/evaluations       # batch decisions (one per entry)
```

`<API_URL>` is the regional IndyKite API base (`https://eu.api.indykite.com` or `https://us.api.indykite.com`). All AuthZEN endpoints live under `/access/v1`.

## Authentication

- **Always**: `X-IK-ClientKey: <AppAgent-credentials-token>` — authenticates the calling application.
- **Optional**: `Authorization: Bearer <user-access-token>` — applies only in some cases (e.g. a policy condition references a token claim or scope). When supplied it can flip claim-gated entries from `true` to `false` (or back).
- Requests routed through the Agent Gateway may also carry an `X-IK-Token` delegation token; see the [evaluation reference](../../indykite-authzen-evaluation/references/evaluation-reference.md#authentication).

## Batch evaluations

Top-level `subject` / `action` / `resource` / `context` act as **defaults**; each entry in `evaluations[]` overrides only the parts it specifies.

Request — one action and resource fixed at the top, the subject varied per entry (with one entry overriding the resource):

```json
{
  "action":   { "name": "PROVISION" },
  "resource": { "type": "Server", "id": "gpu-node-7" },
  "evaluations": [
    { "subject": { "type": "Person", "id": "linus" } },
    { "subject": { "type": "Person", "id": "grace" } },
    { "subject": { "type": "Person", "id": "grace" }, "resource": { "type": "Server", "id": "edge-box-2" } },
    { "subject": { "type": "Person", "id": "dennis" } }
  ],
  "context": { "input_params": { "max_price": 80000 } }
}
```

Response — one decision per entry, in request order:

```json
{
  "evaluations": [
    { "decision": false },
    { "decision": true },
    { "decision": false },
    { "decision": true }
  ]
}
```

`context.policy_tags` (top level or per entry) restricts evaluation to policies carrying the given tags.

### Field rules

- `subject.id` / `resource.id` are node `external_id`s.
- `action.name` must match a policy's `actions` exactly (case-sensitive).
- `context.input_params` supplies every `$name` partial parameter the conditions reference (keys without the `$`); values are typed (numbers stay numbers).

## Location-routed policies (`3.0-kbac`)

Batch evaluation reads `2.0-kbac` and `3.0-kbac` policies alike. When a `3.0-kbac` policy routes on a composite IKG with `USE graph.byName($region)`, the **logical location** (a key of the project's `alias_mapping`, e.g. `"east"`) is passed under `context.input_params` exactly like any other partial parameter - in the top-level default `context`, or per entry, since each entry's location is resolved on its own. That lets one batch test the same triple in several locations:

```json
{
  "subject": { "type": "Person", "id": "person-alice" },
  "action":  { "name": "CAN_DRIVE" },
  "evaluations": [
    { "resource": { "type": "Car", "id": "car-kitt" }, "context": { "input_params": { "region": "east" } } },
    { "resource": { "type": "Car", "id": "car-kitt" }, "context": { "input_params": { "region": "west" } } }
  ]
}
```

An entry routed to a constituent that does not hold the subject or resource node comes back `decision: false` - a normal denial. A location that is missing, empty, not a string, or not a key of `alias_mapping`, or `USE` routing on a project without a composite database, surfaces the way a missing partial parameter does (next section): the call stays `200` and the entry carries `decision: false` with a `context.reason` that quotes the same message the single endpoint returns as a `422` (`unknown location "mars" for parameter "$region"`, `location parameter "$region" must be a non-empty string`, `… requires a composite database, but the app space has none configured`). A user token on the request whose identity differs from an entry's `subject` fails that entry the same way, with the message `bearer token subject differs from requested subject` (a `403` on the single endpoint). Only the `missing or wrong input params` reason is known to carry the `invalid_argument:` prefix shown below; match on the message, not the prefix. Policy authoring for `3.0-kbac` is in [`indykite-authzen-kbac-policies`](../../indykite-authzen-kbac-policies/references/policy-reference.md#30-kbac-raw-cypher-and-location-routing); the single-decision view of the same rules in the [evaluation reference](../../indykite-authzen-evaluation/references/evaluation-reference.md#location-routed-policies-30-kbac).

## Missing input_params behaves differently from single evaluation

A single `/evaluation` call that omits a required partial parameter returns **`422`** with `errors: ["missing or wrong input params, 'max_price'"]`.

In a **batch** call the response is still **`200`**: each entry whose matched policy needed the missing parameter comes back as `decision: false` with a `context.reason`:

```json
{
  "evaluations": [
    { "decision": false, "context": { "reason": "invalid_argument: missing or wrong input params, 'max_price'" } },
    { "decision": false, "context": { "reason": "invalid_argument: missing or wrong input params, 'max_price'" } },
    { "decision": false }
  ]
}
```

Entries that did not need the parameter (e.g. an entry whose resource type matches no parameterised policy) just get a plain `decision: false` with no `context`. So a batch never fails wholesale on a missing parameter — inspect each entry's `context.reason` to tell a real deny from a missing-input deny.

## Error semantics

| HTTP code          | When                                                                                  | Likely fix                                                                          |
|--------------------|---------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------|
| `200`              | Always for a well-formed batch — per-entry `decision` (and `context.reason`) carry the outcome. | Inspect each entry; a `false` is not a request error.                          |
| `400 Bad Request`  | Malformed JSON, or `evaluations[]` missing / not an array.                             | Fix the envelope: top-level defaults plus an `evaluations` array.                   |
| `401 Unauthorized` | Invalid `X-IK-ClientKey`, or an invalid user OAuth token when one is supplied.         | Refresh the AppAgent credentials token; if a user token is required, ensure it is valid. |
| `404 Not Found`    | Wrong base path or project context.                                                    | Confirm `<API_URL>/access/v1/evaluations` and the credentials' project.             |
| `503` + `{"message": "Unable to verify the AppAgent credential token, retry the request"}` | The credential could not be checked right now (transient); it was not judged. | Retry the same request with the same credential, with backoff. |
| `500` + `{"message": "Unable to verify the AppAgent credential token"}` | The credential check failed for a non-transient reason; the credential was not judged. | Report the request's trace to IndyKite support; the credential itself was not judged. |
| other `5xx`        | Server-side issue.                                                                     | Retry with backoff; escalate if persistent.                                         |

## Relationship to the other AuthZEN skills

- A single decision is [`indykite-authzen-evaluation`](../../indykite-authzen-evaluation/SKILL.md)'s `/access/v1/evaluation`. Batch is the same decision semantics, fanned out.
- To enumerate every instance for one probe (the actions, resources, or subjects), use the search skills ([`indykite-authzen-search-action`](../../indykite-authzen-search-action/SKILL.md), [`indykite-authzen-search-resource`](../../indykite-authzen-search-resource/SKILL.md), [`indykite-authzen-search-subject`](../../indykite-authzen-search-subject/SKILL.md)).

Policy authoring (the `2.0-kbac` policies every entry is evaluated against) lives in [`indykite-authzen-kbac-policies`](../../indykite-authzen-kbac-policies/SKILL.md).

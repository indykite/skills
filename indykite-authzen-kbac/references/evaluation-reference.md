# KBAC Evaluation Reference (AuthZEN)

KBAC decisions are made through IndyKite's AuthZEN-compliant REST endpoints. A decision asks: *may this subject perform this action on this resource?* and returns a boolean.

## Base path

```text
<API_URL>/access/v1
```

`<API_URL>` is the regional IndyKite API base URL (e.g. `https://us.api.indykite.com` or `https://eu.api.indykite.com`). The AuthZEN endpoints live under `/access/v1`.

## Authentication

Evaluation requires the **AppAgent credentials token**, sent as the `X-IK-ClientKey` header on every call. This authenticates the application making the decision request, and is always required.

A **user OAuth access token** (`Authorization: Bearer <token>`) is **optional** and applies only in some cases. Otherwise `X-IK-ClientKey` alone is enough.

The subject being evaluated is identified by the request's `subject.id` (matched to the node `external_id`), not by the caller's credentials.

(Policy *creation* is a separate operation with its own auth - a Service Account token; see [`policy-reference.md`](policy-reference.md).)

## Single evaluation

```text
POST <API_URL>/access/v1/evaluation
```

Request:

```json
{
  "subject":  { "type": "Person", "id": "alice" },
  "resource": { "type": "Car",    "id": "kitt"  },
  "action":   { "name": "CAN_BUY" },
  "context":  { "input_params": { "max_price": 150000 } }
}
```

Field rules:

- `subject.type` / `resource.type` - must match a policy's `subject.type` / `resource.type`.
- `subject.id` / `resource.id` - the nodes' `external_id`s.
- `action.name` - must be one of a matching policy's `actions` (case-sensitive).
- `context.input_params` - supplies every `$name` partial parameter the condition references; keys are written **without** the leading `$`. Values are typed (numbers stay numbers, strings stay strings).

Response:

```json
{ "decision": true }
```

`true` = at least one ACTIVE policy granted the triple and its condition held. `false` = nothing granted it.

## Batch evaluations

```text
POST <API_URL>/access/v1/evaluations
```

Top-level `subject` / `action` / `resource` / `context` act as **defaults**; each entry in `evaluations[]` overrides the parts it specifies. This is efficient when one subject is checked against many resources, or one action across many subjects.

Request:

```json
{
  "subject": { "type": "Person", "id": "knightrider" },
  "action":  { "name": "CAN_DRIVE" },
  "evaluations": [
    { "resource": { "type": "Car", "id": "kitt" } },
    { "resource": { "type": "Car", "id": "caddilacv16" } },
    { "resource": { "type": "Bus", "id": "harmonika" }, "action": { "name": "CAN_RIDE" } }
  ]
}
```

Response - one decision per request entry, in order:

```json
{
  "evaluations": [
    { "decision": true },
    { "decision": false },
    { "decision": true }
  ]
}
```

`context.policy_tags` (top level or per entry) restricts evaluation to policies carrying the given tags.

## Action search

```text
POST <API_URL>/access/v1/search/action
```

Returns the actions a subject is allowed to perform on a resource - useful for building a UI that shows only permitted operations.

Request:

```json
{
  "subject":  { "type": "Person", "id": "alice" },
  "resource": { "type": "Car",    "id": "kitt"  }
}
```

Response:

```json
{ "results": [ { "name": "CAN_BUY" } ] }
```

Each `results[]` entry is an action the subject may perform on that resource under current policies and graph state. Two sibling endpoints exist with analogous request bodies: `/access/v1/search/resource` (resources a subject may act on, given an action) and `/access/v1/search/subject` (subjects allowed an action on a resource).

## Error semantics

| HTTP code          | When                                                                                  | Likely fix                                                                          |
|--------------------|---------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------|
| `200` + `decision:false` | Request well-formed but no policy granted the triple, or the condition did not hold. | Walk the [troubleshooting checklist](troubleshooting.md). This is **not** an error. |
| `400 Bad Request`  | Malformed JSON, or `input_params` missing a parameter the condition requires.          | Fix the body; supply every `$name` the policy references.                            |
| `401 Unauthorized` | Invalid `X-IK-ClientKey`, or an invalid user OAuth token when one is supplied. | Refresh the AppAgent credentials token; if a user token is required, ensure it is valid. |
| `404 Not Found`    | Wrong base path or project context.                                                    | Confirm `<API_URL>/access/v1/...` and the credentials' project.                     |
| `5xx`              | Server-side issue.                                                                     | Retry with backoff; if persistent, file with the IndyKite team.                     |

A `false` decision is a normal `200` response - distinguish it from the `4xx`/`5xx` failures above before changing the policy.

## Calling through MCP instead of REST

The [`indykite-mcp-server`](../../indykite-mcp-server/SKILL.md) skill's `authzen_evaluate` tool wraps the same decision call as a JSON-RPC tool. The wire shape differs (JSON-RPC over HTTP, `Mcp-Session-Id` header) but the policy, subject/resource/action/context inputs, and the boolean decision semantics are identical.

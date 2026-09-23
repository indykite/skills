# KBAC Evaluation Reference (AuthZEN)

KBAC decisions are made through IndyKite's AuthZEN-compliant REST endpoints. A decision asks: *may this subject perform this action on this resource?* and returns a boolean.

## Base path

```text
<API_URL>/access/v1
```

`<API_URL>` is the regional IndyKite API base URL (e.g. `https://us.api.indykite.com` or `https://eu.api.indykite.com`). The AuthZEN endpoints live under `/access/v1`.

## Authentication

Every call authenticates the **application making the decision request** via its AppAgent credentials - always required. A **user access token** is **optional** and applies only in some cases; otherwise the application credentials alone are enough. The mapping of each credential to its request header is documented in the [Credentials guide](https://developer.indykite.com/guides/guide-credentials); the skill's helper script sets the headers from environment variables.

The subject being evaluated is identified by the request's `subject.id` (matched to the node `external_id`), not by the caller's credentials.

A request that already carries a user token may also carry an optional **delegation token** in the `X-IK-Token` header (as is, no prefix), minted by the self-hosted [IndyKite Token Service](https://developer.indykite.com/guides/guide-token-service) and forwarded by the Agent Gateway. It never replaces the user token: `Authorization: Bearer` still identifies the subject, and the delegation token adds the chain of agents acting on that subject's behalf. The platform validates it through the project's Token Introspect configurations exactly like the user token, requires its `sub` to equal the user token's `sub`, and exposes its claims to the policy as `$ik_token` (`$ik_token.act.sub` = the calling agent, `$ik_token.act.act.sub` = the one before it). The name `ik_token` is reserved in `context.input_params` and ignored there.

(Policy *creation* is a separate operation with its own auth - a Service Account token; see [`indykite-authzen-kbac-policies`](../../indykite-authzen-kbac-policies/SKILL.md) and its [`policy-reference.md`](../../indykite-authzen-kbac-policies/references/policy-reference.md).)

## Single evaluation

```text
POST <API_URL>/access/v1/evaluation
```

Request:

```json
{
  "subject":  { "type": "Person", "id": "ada" },
  "resource": { "type": "Server",    "id": "gpu-node-7"  },
  "action":   { "name": "PROVISION" },
  "context":  { "input_params": { "max_price": 120000 } }
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

## Beyond a single decision

This reference covers the single `/evaluation` endpoint. The same policy is evaluated by sibling endpoints, each with its own skill:

| Need                                                | Endpoint                       | Skill                                                                  |
|-----------------------------------------------------|--------------------------------|-----------------------------------------------------------------------|
| Many decisions in one call                          | `/access/v1/evaluations`       | [`indykite-authzen-evaluations`](../../indykite-authzen-evaluations/SKILL.md) |
| Actions a subject may perform on a resource         | `/access/v1/search/action`     | [`indykite-authzen-search-action`](../../indykite-authzen-search-action/SKILL.md)   |
| Resources a subject may act on, given an action     | `/access/v1/search/resource`   | [`indykite-authzen-search-resource`](../../indykite-authzen-search-resource/SKILL.md) |
| Subjects allowed an action on a resource            | `/access/v1/search/subject`    | [`indykite-authzen-search-subject`](../../indykite-authzen-search-subject/SKILL.md)  |

All of them authenticate the same way (AppAgent credentials, optional user token) and read the same `2.0-kbac` policies authored via [`indykite-authzen-kbac-policies`](../../indykite-authzen-kbac-policies/SKILL.md).

## Error semantics

| HTTP code          | When                                                                                  | Likely fix                                                                          |
|--------------------|---------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------|
| `200` + `decision:false` | Request well-formed but no policy granted the triple, or the condition did not hold. | Walk the [troubleshooting checklist](troubleshooting.md). This is **not** an error. |
| `422 Unprocessable Entity` | `input_params` missing a parameter the condition requires - body carries `errors: ["missing or wrong input params, '<name>'"]`. | Supply every `$name` the policy references. (In a *batch* call this instead surfaces per-entry as `decision:false` + `context.reason`.) |
| `400 Bad Request`  | Malformed JSON or a missing required field.                                            | Fix the request body.                                                                |
| `401 Unauthorized` | Invalid AppAgent credentials, or an invalid user token when one is supplied. | Refresh the AppAgent credentials; if a user token is required, ensure it is valid. |
| `401` + `{"message": "Invalid token in X-IK-Token header"}` | The delegation token is expired, not signed by a trusted issuer, or matches no Token Introspect configuration. | Create a Token Introspect configuration for the Token Service issuer + audience, or mint a fresh delegation token. |
| `401` + `{"message": "Token in X-IK-Token header carries a different sub than the subject token"}` (or `is missing the sub claim`) | The user token and the delegation token are not about the same user. | Forward both headers exactly as received from the previous hop. |
| `404 Not Found`    | Wrong base path or project context.                                                    | Confirm `<API_URL>/access/v1/...` and the credentials' project.                     |
| `503` + `{"message": "Unable to verify the AppAgent credential token, retry the request"}` | The credential could not be checked right now (transient). It was **not** judged. | Retry the same request with the same credential, with backoff. |
| `500` + `{"message": "Unable to verify the AppAgent credential token"}` | The credential check failed for a non-transient reason. The credential was not judged. | Report the request's trace to IndyKite support; the credential itself was not judged. |
| other `5xx`        | Server-side issue.                                                                     | Retry with backoff; if persistent, file with the IndyKite team.                     |

A `false` decision is a normal `200` response - distinguish it from the `4xx`/`5xx` failures above before changing the policy.

## Calling through MCP instead of REST

The [`indykite-mcp-server`](../../indykite-mcp-server/SKILL.md) skill's `authzen_evaluate` tool wraps the same decision call as a JSON-RPC tool. The wire shape differs (JSON-RPC over HTTP, `Mcp-Session-Id` header) but the policy, subject/resource/action/context inputs, and the boolean decision semantics are identical.

# AuthZEN Policy Listing Reference

`GET /access/v1/policies` returns the ACTIVE KBAC policies of the calling application agent's project, as stored, with their tags. It is a read-only runtime view; it makes no decision and manages no policy.

## Endpoint

```text
GET https://eu.api.indykite.com/access/v1/policies
GET https://us.api.indykite.com/access/v1/policies
```

`<API_URL>` is the regional IndyKite API base matching the project's region. All AuthZEN endpoints live under `/access/v1`; this one is the only `GET`.

## Authentication and permission

- **Auth**: the AppAgent credential in the `X-IK-ClientKey` header, passed as is, without any prefix. No user bearer token is involved, and none is needed. Which credential goes in which header is documented in the [Credentials guide](https://developer.indykite.com/guides/guide-credentials).
- **Permission**: the AppAgent must hold the **`ReadAuthZConfigs`** API permission. This permission gates this endpoint and nothing else. It is independent of `Authorization`: an agent with `Authorization` alone is refused here with `401`, and an agent with `ReadAuthZConfigs` alone can read the rules but cannot evaluate them.
- **Granting it**: add `"ReadAuthZConfigs"` to the agent's `api_permissions` when creating it (`POST /configs/v1/application-agents`) or by updating it (`PUT /configs/v1/application-agents/{id}` with the full list), both with a Service Account token; or in the Hub UI. Permissions are per agent and are never granted to existing agents automatically.
- **Accepted values**: `api_permissions` takes `Authorization`, `Capture`, `ContXIQ`, `EntityMatching`, `ReadAuthZConfigs`, `ReadDataSchema` - see the [Environment guide](https://developer.indykite.com/guides/guide-environment).

## Query parameter

| Parameter      | Required | Notes                                                                                                                                           |
|----------------|----------|-------------------------------------------------------------------------------------------------------------------------------------------------|
| `subject_type` | no       | Keep only the policies whose `subject.type` equals this node type - a valid node label (2-64 characters, e.g. `Person`, `_Application`), matched case-sensitively. Omitted: every policy is returned. A value no policy uses gives `{"results": []}`, not an error. |

## Response

`200 OK`, `application/json`:

```json
{
  "results": [
    {
      "policy": {
        "meta": { "policy_version": "2.0-kbac" },
        "subject": { "type": "Person" },
        "actions": ["CAN_DRIVE"],
        "resource": { "type": "Car" },
        "condition": { "cypher": "MATCH (subject:Person)-[:DRIVES]->(resource:Car)" }
      },
      "tags": []
    },
    {
      "policy": {
        "meta": { "policy_version": "2.0-kbac" },
        "subject": { "type": "Person" },
        "actions": ["CAN_RIDE"],
        "resource": { "type": "Bus" },
        "condition": { "cypher": "MATCH (subject)-[:HAS]->(ticket:Ticket)-[:FOR]->(resource)" }
      },
      "tags": []
    },
    {
      "policy": {
        "meta": { "policy_version": "2.0-kbac" },
        "subject": { "type": "_Application" },
        "actions": ["CAN_READ"],
        "resource": { "type": "Car" },
        "condition": { "cypher": "MATCH (subject) MATCH (resource:Car)" }
      },
      "tags": ["fleet"]
    }
  ]
}
```

| Field               | Type   | Meaning                                                                                                                                                   |
|---------------------|--------|-----------------------------------------------------------------------------------------------------------------------------------------------------------|
| `results`           | array  | One entry per policy. Empty when nothing matches.                                                                                                          |
| `results[].policy`  | object | The policy definition as stored: the `policy` string sent to `POST /configs/v1/authorization-policies`, parsed into a JSON object. `meta`, `subject`, `actions`, `resource`, `condition` (`cypher`, optional `filter`) appear exactly as authored, for `2.0-kbac` and `3.0-kbac` alike. |
| `results[].tags`    | array  | The policy's tags - the values matched by `context.policy_tags` on evaluation. Always an array, `[]` when the policy has none.                              |

### What is included

- KBAC policies (`2.0-kbac` and `3.0-kbac`) with status **ACTIVE** - the same set the decision and search endpoints evaluate. `INACTIVE` and `DRAFT` policies are not listed.
- Only the project of the calling agent. There is no project parameter.

### What is not included

- ContX IQ (`1.0-ciq`) policies.
- Policy `id`, `name`, `display_name`, `description`, `status`, audit timestamps, ETag. Use the Config API (`GET /configs/v1/authorization-policies?project_id=…&type=kbac`, Service Account token - [`indykite-authzen-kbac-policies`](../../indykite-authzen-kbac-policies/SKILL.md)) when you need to manage a policy rather than read its rule.

## Error semantics

| HTTP code            | Body                                                  | When                                                                       | Likely fix                                                                                                         |
|----------------------|-------------------------------------------------------|----------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------|
| `200` + `results:[]` | -                                                     | No ACTIVE KBAC policy matches (or none exists).                            | Not an error. Check policy status, the credential's project, and the exact `subject_type` spelling.                 |
| `401 Unauthorized`   | `{"message": "insufficient API access level for appAgent"}` | The agent lacks `ReadAuthZConfigs`. `Authorization` alone is not enough.    | Add `ReadAuthZConfigs` to the agent's `api_permissions`; retry with the same credential.                            |
| `401 Unauthorized`   | `{"message": …}`                                      | Invalid or expired AppAgent credential.                                     | Mint a new credential (`POST /configs/v1/application-agent-credentials`).                                          |
| `422 Unprocessable`  | `{"message": …, "errors": ["…"]}`                     | `subject_type` is not a valid node type (too short, too long, bad label).   | Use a plain node label such as `Person` or `_Application`; read `errors[]` for the offending field.                |
| `404 Not Found`      | -                                                     | Wrong base path.                                                            | Confirm `<API_URL>/access/v1/policies` and the region.                                                             |
| `5xx`                | `{"message": …}`                                      | Server-side issue.                                                          | Retry with backoff; escalate if persistent.                                                                        |

## Troubleshooting

1. **`401` but the agent "has Authorization"?** That permission covers `/evaluation`, `/evaluations`, and `/search/*` only. This endpoint needs `ReadAuthZConfigs`; add it explicitly - it is not implied.
2. **Empty listing but policies exist in the Hub?** Only `ACTIVE` KBAC policies are listed. Check `status`, that the credential belongs to the same project and region, and that `subject_type` matches `subject.type` exactly (case-sensitive).
3. **A policy is missing that a decision does use?** Then it is a ContX IQ policy or belongs to another project - both are out of scope for this listing.
4. **Policy looks different from what was posted?** It is returned as stored: whitespace and key order may differ from the original string, but every field is the authored one.

## `jq` recipes

With the response in `policies.json`:

```bash
# subject -> actions -> resource, one line per policy
jq -r '.results[] | "\(.policy.subject.type)\t\(.policy.actions | join(","))\t\(.policy.resource.type)\t[\(.tags | join(","))]"' policies.json

# every distinct action name in the project (feed evaluation / search requests)
jq -r '[.results[].policy.actions[]] | unique[]' policies.json

# every distinct tag (candidates for context.policy_tags)
jq -r '[.results[].tags[]] | unique[]' policies.json

# partial parameters ($name) each policy's condition expects under context.input_params
jq -r '.results[] | "\(.policy.actions | join(",")) on \(.policy.resource.type): \([.policy.condition.cypher | scan("\\$[A-Za-z_][A-Za-z0-9_]*")] | unique | join(" "))"' policies.json

# policies by version (2.0-kbac vs 3.0-kbac)
jq -r 'group_by(.policy.meta.policy_version)[] | "\(.[0].policy.meta.policy_version)\t\(length)"' <(jq '.results' policies.json)
```

## Sibling endpoints

- `/access/v1/evaluation` and `/access/v1/evaluations` - single and batch yes/no decisions ([`indykite-authzen-evaluation`](../../indykite-authzen-evaluation/SKILL.md), [`indykite-authzen-evaluations`](../../indykite-authzen-evaluations/SKILL.md)).
- `/access/v1/search/action`, `/search/resource`, `/search/subject` - enumerate what a specific subject may do ([`indykite-authzen-search-action`](../../indykite-authzen-search-action/SKILL.md), [`-search-resource`](../../indykite-authzen-search-resource/SKILL.md), [`-search-subject`](../../indykite-authzen-search-subject/SKILL.md)).
- `/configs/v1/authorization-policies` - the Config API lifecycle of the policies this endpoint lists ([`indykite-authzen-kbac-policies`](../../indykite-authzen-kbac-policies/SKILL.md)).
- `/contx-iq/v1/whoami` - resolve a user token to the `subject.type` / `subject.id` a policy will be evaluated for ([`indykite-ciq-whoami`](../../indykite-ciq-whoami/SKILL.md)).

---
name: indykite-authzen-search-resource
description: List the resources a subject is allowed to perform a given action on via the IndyKite AuthZEN REST API (`POST /access/v1/search/resource`) - given a subject and an action, returns the matching resource instances of a type. Use to enumerate permitted resources - "which servers can linus provision?", "list the documents this user can read" (access-filtered feeds). Returns `{type,id}` references, not a yes/no decision and not the resource data itself (for graph data use indykite-ciq-read). For a single-resource yes/no use indykite-authzen-evaluation; to enumerate the other axes use indykite-authzen-search-action (which actions) or indykite-authzen-search-subject (which subjects); to author the policy use indykite-authzen-kbac.
license: Apache-2.0
compatibility: Requires curl, bash 4+, and jq. Network access to the regional IndyKite REST API (eu.api.indykite.com or us.api.indykite.com) is required at runtime.
---

# IndyKite AuthZEN - resource search

Resource search asks the AuthZEN endpoint: *which resources may this subject perform a given action on?* Given one subject, one action, and a resource **type**, it returns the matching resource instances under the project's currently ACTIVE KBAC policies and current graph state.

It is one of three AuthZEN search endpoints, each pinning two of the three `(subject, action, resource)` parts and enumerating the third:

| Endpoint                  | Pinned        | Enumerates | Skill                                                                |
|---------------------------|---------------|------------|---------------------------------------------------------------------|
| `/search/action`          | subject + resource | actions    | [`indykite-authzen-search-action`](../indykite-authzen-search-action/SKILL.md) |
| `/search/resource`        | subject + action   | **resources** | this skill                                                         |
| `/search/subject`         | resource + action  | subjects   | [`indykite-authzen-search-subject`](../indykite-authzen-search-subject/SKILL.md) |

This skill covers building and sending the request and reading the results. It does **not** author policies - the `2.0-kbac` policies these results are evaluated against are authored with [`indykite-authzen-kbac`](../indykite-authzen-kbac/SKILL.md).

## When to use

Activate this skill when the user wants to:

- list **every resource of a type a subject may act on** under one action (e.g. "which servers can `linus` `PROVISION`?", "which documents can this user read?");
- build a list/feed filtered to the items a user is permitted to act on;
- debug why an expected resource is or is not in a subject's permitted set.

Do **not** activate this skill for a single yes/no **decision** ([`indykite-authzen-evaluation`](../indykite-authzen-evaluation/SKILL.md)), to enumerate **actions** or **subjects** instead (the sibling search skills), or to **author a policy** or **read/write graph data** (search only lists resources).

## Prerequisites

- One or more **ACTIVE KBAC policies** whose `subject.type` / `resource.type` and `actions` cover the question. If none exist, author them first with [`indykite-authzen-kbac`](../indykite-authzen-kbac/SKILL.md); search over an empty policy set returns `{"results": []}`.
- An **AppAgent** and its **credentials token** (the `X-IK-ClientKey` value).
- The **IKG populated** with the subject and candidate resource nodes (and any relationships the policy conditions match).
- Any **partial parameters** a candidate policy references, ready to pass under `context.input_params`.

If a prerequisite is missing, say so - an empty result set from a missing policy or absent node looks identical to a real "nothing permitted".

## Steps

### 1. Pin the subject and the action; leave the resource a type

Resource search fixes the **subject** and the **action**, and searches across resources of a given **type**:

| Part       | Field                          | Example                  |
|------------|--------------------------------|--------------------------|
| subject    | `subject.type` + `subject.id`  | `Person` / `linus` |
| action     | `action.name`                  | `PROVISION`                |
| resource   | `resource.type` **only**       | `Server` (no `id`)          |

Do **not** set `resource.id` - the instances are what the search returns.

### 2. Build the request body

```json
{
  "subject":  { "type": "Person", "id": "linus" },
  "resource": { "type": "Server" },
  "action":   { "name": "PROVISION" },
  "context":  { "input_params": { "max_price": 4000 } }
}
```

Include `context.input_params` only if a candidate policy references a `$name` partial parameter; supply each key **without** the `$`, correctly typed. A ready body: [`assets/search-resource-request.json`](assets/search-resource-request.json).

### 3. Send the search

```text
POST <API_URL>/access/v1/search/resource
```

Authentication:

- **Always**: `X-IK-ClientKey: <AppAgent-credentials-token>`.
- **Optional**: `Authorization: Bearer <user-access-token>` - applies only in some cases; when supplied it can narrow the results.

A runnable shell helper: [`scripts/search-resource.sh`](scripts/search-resource.sh) — run with `--print` to preview the `curl` (host-pinned; tokens redacted).

### 4. Read the results

```json
{ "results": [ { "type": "Server", "id": "edge-box-2" } ] }
```

Each `results[]` entry is a resource (`type` + `id`, the `external_id`) the subject may perform the action on. An **empty** `results` array is a normal `200` meaning nothing of that type is permitted - not an error.

### 5. Verify

Empty or surprising results usually trace to: `resource.id` accidentally set (it takes `resource.type` only), the `action` not matching a policy, `subject.id` not being an `external_id`, a `$param` missing/mistyped (tightening `max_price` shrinks the set), or the resource nodes being absent. Full checklist: [`references/search-resource-reference.md`](references/search-resource-reference.md).

## Outcome

When this skill has been applied successfully:

- `POST /access/v1/search/resource` returns a `results` array of resource instances (`type` + `id`) a subject may perform the given action on, under current ACTIVE policies and graph state (an empty array means nothing of that type permitted — a normal `200`).
- The resources returned are consistent with single-decision (`/access/v1/evaluation`) results for the same triples.

## Files in this skill

- [`references/search-resource-reference.md`](references/search-resource-reference.md) - endpoint, auth, request/response shape, error codes, troubleshooting, sibling endpoints.
- [`assets/search-resource-request.json`](assets/search-resource-request.json) - runnable resource-search request body for the `linus` `PROVISION` `Server` example.
- [`scripts/search-resource.sh`](scripts/search-resource.sh) - Bash helper that posts a search request to `/access/v1/search/resource` (host-pinned; `--print` to preview).

## Agent-specific notes

This skill uses generic markdown instructions and works across all agents listed in the [README](../README.md). The agent needs to be able to issue HTTP requests (`curl`, an HTTP client, or the IndyKite Terraform provider). No Claude Code hooks, Cursor `@`-mentions, or Copilot workspace context are required.

## References

- [AuthZEN guide (developer hub)](https://developer.indykite.com/guides/guide-authzen)
- [Config API documentation - authorization policies](https://openapi.indykite.com/api-documentation-config#tag/authorization-policies)
- [Credentials guide](https://developer.indykite.com/guides/guide-credentials)

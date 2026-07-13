---
name: indykite-authzen-search-subject
description: List the subjects allowed to perform a given action on a resource via the IndyKite AuthZEN REST API (`POST /access/v1/search/subject`) - given a resource and an action, returns the matching subject instances of a type. Use to enumerate who has access - "who can provision gpu-node-7?", "list the people allowed to approve this document" (audit / reviewer views). Not for a specific-subject yes/no ("can grace provision gpu-node-7?" -> indykite-authzen-evaluation); to enumerate the other axes use indykite-authzen-search-action (which actions) or indykite-authzen-search-resource (which resources); to author the policy use indykite-authzen-kbac-policies.
license: Apache-2.0
compatibility: Requires curl, bash 4+, and jq. Network access to the regional IndyKite REST API (eu.api.indykite.com or us.api.indykite.com) is required at runtime.
---

# IndyKite AuthZEN - subject search

Subject search asks the AuthZEN endpoint: *which subjects may perform a given action on this resource?* Given a subject **type**, one resource, and one action, it returns the matching subject instances under the project's currently ACTIVE KBAC policies and current graph state.

It is one of three AuthZEN search endpoints, each pinning two of the three `(subject, action, resource)` parts and enumerating the third:

| Endpoint                  | Pinned        | Enumerates | Skill                                                                |
|---------------------------|---------------|------------|---------------------------------------------------------------------|
| `/search/action`          | subject + resource | actions    | [`indykite-authzen-search-action`](../indykite-authzen-search-action/SKILL.md) |
| `/search/resource`        | subject + action   | resources  | [`indykite-authzen-search-resource`](../indykite-authzen-search-resource/SKILL.md) |
| `/search/subject`         | resource + action  | **subjects** | this skill                                                         |

This skill covers building and sending the request and reading the results. It does **not** author policies - the `2.0-kbac` policies these results are evaluated against are authored with [`indykite-authzen-kbac-policies`](../indykite-authzen-kbac-policies/SKILL.md).

## When to use

Activate this skill when the user wants to:

- list **every subject of a type that may perform an action on a specific resource** (e.g. "who can `DEPLOY` `gpu-node-7`?", "who can approve this document?");
- build an audit or reviewer view of who currently has access to an item;
- debug why an expected subject is or is not in a resource's permitted set.

Do **not** activate this skill for a single yes/no **decision** ([`indykite-authzen-evaluation`](../indykite-authzen-evaluation/SKILL.md)), to enumerate **actions** or **resources** instead (the sibling search skills), or to **author a policy** or **read/write graph data** (search only lists subjects).

## Prerequisites

- One or more **ACTIVE KBAC policies** whose `subject.type` / `resource.type` and `actions` cover the question. If none exist, author them first with [`indykite-authzen-kbac-policies`](../indykite-authzen-kbac-policies/SKILL.md); search over an empty policy set returns `{"results": []}`.
- An **AppAgent** with credentials configured for the calling application ([Credentials guide](https://developer.indykite.com/guides/guide-credentials)).
- The **IKG populated** with the candidate subject nodes and the resource node (and any relationships the policy conditions match).
- Any **partial parameters** a candidate policy references, ready to pass under `context.input_params`.

If a prerequisite is missing, say so - an empty result set from a missing policy or absent node looks identical to a real "nothing permitted".

## Steps

### 1. Pin the resource and the action; leave the subject a type

Subject search fixes the **resource** and the **action**, and searches across subjects of a given **type**:

| Part       | Field                          | Example          |
|------------|--------------------------------|------------------|
| subject    | `subject.type` **only**        | `Person` (no `id`) |
| action     | `action.name`                  | `PROVISION`        |
| resource   | `resource.type` + `resource.id`| `Server` / `gpu-node-7`   |

Do **not** set `subject.id` - the subjects are what the search returns.

### 2. Build the request body

```json
{
  "subject":  { "type": "Person" },
  "resource": { "type": "Server", "id": "gpu-node-7" },
  "action":   { "name": "PROVISION" },
  "context":  { "input_params": { "max_price": 80000 } }
}
```

Include `context.input_params` only if a candidate policy references a `$name` partial parameter; supply each key **without** the `$`, correctly typed. A ready body: [`assets/search-subject-request.json`](assets/search-subject-request.json).

### 3. Send the search

```text
POST <API_URL>/access/v1/search/subject
```

The endpoint authenticates the **calling application** (its AppAgent credentials - always required). A **user access token** is accepted too, but for subject search it typically has **no effect** on the result set (you are enumerating subjects, not acting as one). Which credential goes in which request header is covered by the [Credentials guide](https://developer.indykite.com/guides/guide-credentials).

A runnable shell helper builds the authenticated request: [`scripts/search-subject.sh`](scripts/search-subject.sh) — run with `--print` to preview the `curl` (host-pinned; tokens redacted).

### 4. Read the results

```json
{ "results": [ { "type": "Person", "id": "grace" }, { "type": "Person", "id": "dennis" } ] }
```

Each `results[]` entry is a subject (`type` + `id`, the `external_id`) allowed the action on that resource. An **empty** `results` array is a normal `200` meaning no subject of that type is permitted - not an error.

### 5. Verify

Empty or surprising results usually trace to: `subject.id` accidentally set (it takes `subject.type` only), `resource.id` not being an `external_id`, the `action` not matching a policy, a `$param` missing/mistyped (loosening `max_price` widens the set), or the subject nodes being absent. Full checklist: [`references/search-subject-reference.md`](references/search-subject-reference.md).

## Outcome

When this skill has been applied successfully:

- `POST /access/v1/search/subject` returns a `results` array of subject instances (`type` + `id`) allowed a given action on a specific resource, under current ACTIVE policies and graph state (an empty array means no subject of that type permitted — a normal `200`).
- The subjects returned are consistent with single-decision (`/access/v1/evaluation`) results for the same triples.

## Files in this skill

- [`references/search-subject-reference.md`](references/search-subject-reference.md) - endpoint, auth, request/response shape, error codes, troubleshooting, sibling endpoints.
- [`assets/search-subject-request.json`](assets/search-subject-request.json) - runnable subject-search request body for the "who can `PROVISION` `gpu-node-7`" example.
- [`scripts/search-subject.sh`](scripts/search-subject.sh) - Bash helper that posts a search request to `/access/v1/search/subject` (host-pinned; `--print` to preview).

## Agent-specific notes

This skill uses generic markdown instructions and works across all agents listed in the [README](../README.md). The agent needs to be able to issue HTTP requests (`curl`, an HTTP client, or the IndyKite Terraform provider). No Claude Code hooks, Cursor `@`-mentions, or Copilot workspace context are required.

## References

- [AuthZEN guide (developer hub)](https://developer.indykite.com/guides/guide-authzen)
- [Config API documentation - authorization policies](https://openapi.indykite.com/api-documentation-config#tag/authorization-policies)
- [Credentials guide](https://developer.indykite.com/guides/guide-credentials)

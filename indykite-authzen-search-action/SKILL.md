---
name: indykite-authzen-search-action
description: List the actions a subject is allowed to perform on a resource via the IndyKite AuthZEN REST API (`POST /access/v1/search/action`) - returns the granted action names for one pinned (subject, resource) pair. Use to enumerate permitted operations - "what can linus do with gpu-node-7?", "which actions does this user have on this item?" (e.g. to render only allowed UI controls). Not for a specific-action yes/no ("can linus DEPLOY gpu-node-7?" -> indykite-authzen-evaluation); to enumerate the other axes use indykite-authzen-search-resource (which resources) or indykite-authzen-search-subject (which subjects); to author the policy use indykite-authzen-kbac-policies.
license: Apache-2.0
compatibility: Requires curl, bash 4+, and jq. Network access to the regional IndyKite REST API (eu.api.indykite.com or us.api.indykite.com) is required at runtime.
---

# IndyKite AuthZEN - action search

Action search asks the AuthZEN endpoint: *which actions may this subject perform on this resource?* It returns the list of granted action names under the project's currently ACTIVE KBAC policies and current graph state - not a single boolean.

It is one of three AuthZEN search endpoints, each pinning two of the three `(subject, action, resource)` parts and enumerating the third:

| Endpoint                  | Pinned        | Enumerates | Skill                                                                  |
|---------------------------|---------------|------------|-----------------------------------------------------------------------|
| `/search/action`          | subject + resource | **actions** | this skill                                                            |
| `/search/resource`        | subject + action   | resources  | [`indykite-authzen-search-resource`](../indykite-authzen-search-resource/SKILL.md) |
| `/search/subject`         | resource + action  | subjects   | [`indykite-authzen-search-subject`](../indykite-authzen-search-subject/SKILL.md)   |

This skill covers building and sending the request and reading the results. It does **not** author policies - the `2.0-kbac` policies whose `actions` these results come from are authored with [`indykite-authzen-kbac-policies`](../indykite-authzen-kbac-policies/SKILL.md).

## When to use

Activate this skill when the user wants to:

- list **every action a subject may perform on a specific resource** (e.g. "what can `linus` do with `gpu-node-7`?");
- drive a UI that shows only the operations a user is currently permitted on an item;
- debug why an expected action is or is not granted for a `(subject, resource)` pair.

Do **not** activate this skill for a single yes/no **decision** ([`indykite-authzen-evaluation`](../indykite-authzen-evaluation/SKILL.md)), to enumerate **resources** or **subjects** instead (the sibling search skills), to run **many decisions** at once ([`indykite-authzen-evaluations`](../indykite-authzen-evaluations/SKILL.md)), or to **author a policy** or **read/write graph data** (search only lists actions).

## Prerequisites

- One or more **ACTIVE KBAC policies** whose `subject.type` / `resource.type` match the pair you are asking about. If none exist, author them first with [`indykite-authzen-kbac-policies`](../indykite-authzen-kbac-policies/SKILL.md); search over an empty policy set returns `{"results": []}`.
- An **AppAgent** with credentials configured for the calling application ([Credentials guide](https://developer.indykite.com/guides/guide-credentials)).
- The **IKG populated** with the subject and resource nodes (and any relationships the policy conditions match). Search evaluates the graph; it does not seed it.
- Any **partial parameters** a candidate policy references, ready to pass under `context.input_params`.

If a prerequisite is missing, say so - an empty result set from a missing policy or absent node looks identical to a real "nothing permitted".

## Steps

### 1. Pin the subject and the resource

Action search fixes **both** the subject and the resource and asks what is allowed between them. Identify each by its node `external_id`:

| Part       | Field            | Example                  |
|------------|------------------|--------------------------|
| subject    | `subject.type` + `subject.id` | `Person` / `linus` |
| resource   | `resource.type` + `resource.id` | `Server` / `gpu-node-7`          |

There is no `action` field - discovering the actions is the point.

### 2. Build the request body

```json
{
  "subject":  { "type": "Person", "id": "linus" },
  "resource": { "type": "Server",    "id": "gpu-node-7" },
  "context":  { "input_params": { "max_price": 120000 } }
}
```

Include `context.input_params` only if a candidate policy's condition references a `$name` partial parameter; supply each key **without** the leading `$`, with the correct type (numbers stay numbers). A ready body: [`assets/search-action-request.json`](assets/search-action-request.json).

### 3. Send the search

```text
POST <API_URL>/access/v1/search/action
```

The endpoint authenticates the **calling application** (its AppAgent credentials - always required) and **optionally the user** (an access token - applies only in some cases; when supplied it can narrow the results). Which credential goes in which request header is covered by the [Credentials guide](https://developer.indykite.com/guides/guide-credentials).

A runnable shell helper builds the authenticated request: [`scripts/search-action.sh`](scripts/search-action.sh) — run with `--print` to preview the `curl` (host-pinned; tokens redacted).

### 4. Read the results

```json
{ "results": [ { "name": "DEPLOY" }, { "name": "REBOOT" }, { "name": "SNAPSHOT" } ] }
```

Each `results[]` entry is an action the subject may currently perform on that resource. An **empty** `results` array is a normal `200` meaning nothing is granted - not an error.

### 5. Verify

Empty or surprising results usually trace to: the policy isn't **ACTIVE**/matching, `subject.id`/`resource.id` aren't the nodes' `external_id`s, a required `$param` is missing or mistyped, the graph data is absent, or a supplied user token narrowed claim-gated actions. Full checklist: [`references/search-action-reference.md`](references/search-action-reference.md).

## Outcome

When this skill has been applied successfully:

- `POST /access/v1/search/action` returns a `results` array of the actions a subject may perform on a specific resource under current ACTIVE policies and graph state (an empty array means nothing permitted — a normal `200`).
- The actions returned line up with the `actions` of the KBAC policies authored via [`indykite-authzen-kbac-policies`](../indykite-authzen-kbac-policies/SKILL.md).

## Files in this skill

- [`references/search-action-reference.md`](references/search-action-reference.md) - endpoint, auth, request/response shape, error codes, troubleshooting, sibling endpoints.
- [`assets/search-action-request.json`](assets/search-action-request.json) - runnable action-search request body for the `linus` / `gpu-node-7` example.
- [`scripts/search-action.sh`](scripts/search-action.sh) - Bash helper that posts a search request to `/access/v1/search/action` (host-pinned; `--print` to preview).

## Agent-specific notes

This skill uses generic markdown instructions and works across all agents listed in the [README](../README.md). The agent needs to be able to issue HTTP requests (`curl`, an HTTP client, or the IndyKite Terraform provider). No Claude Code hooks, Cursor `@`-mentions, or Copilot workspace context are required.

## References

- [AuthZEN guide (developer hub)](https://developer.indykite.com/guides/guide-authzen)
- [Config API documentation - authorization policies](https://openapi.indykite.com/api-documentation-config#tag/authorization-policies)
- [Credentials guide](https://developer.indykite.com/guides/guide-credentials)

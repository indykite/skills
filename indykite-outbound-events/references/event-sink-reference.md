# Event sink reference

The event sink is the Config API object behind IndyKite Outbound Events. This file holds the body schema, the event types, the lifecycle calls, the `last_error` messages and the refusals. The step-by-step flow is in [`../SKILL.md`](../SKILL.md).

- Base URL: `https://eu.api.indykite.com/configs/v1` or `https://us.api.indykite.com/configs/v1`.
- Authentication: `Authorization: Bearer <SERVICE_ACCOUNT_TOKEN>` on every call.
- A project has at most one event sink.

## Body

| Field                | Required on create | Meaning |
|----------------------|--------------------|---------|
| `project_id`         | yes                | GID of the project the sink belongs to. Cannot change. |
| `name`               | yes                | 2-63 chars of lowercase letters, digits and hyphens, starting with a letter and ending with a letter or digit. Unique in the project. Cannot change. |
| `display_name`       | no                 | Human-readable name, 2-254 chars. |
| `description`        | no                 | Free text, 2-65000 chars. |
| `include_cdc_events` | no                 | `true` sends CDC events to the sink; `false` or left out sends none. Applies to every provider. |
| `providers`          | yes                | Object of at least one provider, keyed by a name you choose (same form as `name`). |
| `routes`             | yes                | Ordered list of at least one route. |

An update (`PUT`) takes `providers` and `routes` (both required), `include_cdc_events`, and optionally `display_name` / `description` (left out or `null` keeps the stored value, `""` clears it).

## Providers

Each provider holds exactly one of the four blocks; two blocks in one provider, or none, is refused with `422`.

### `kafka`

| Field             | Required | Meaning |
|-------------------|----------|---------|
| `brokers`         | yes      | List of at least one `host:port` (each at least 8 chars). With several, the client tries the next when one is down - list at least two. |
| `topic`           | yes      | Topic name, 1-249 chars. |
| `username`        | no       | SASL user name, e.g. a Confluent Cloud API key. |
| `password`        | no       | Write-only. |
| `disable_tls`     | no       | `true` connects without TLS. Default `false`; development only. |
| `tls_skip_verify` | no       | `true` keeps encryption but accepts the server certificate without validating it. Default `false`; ignored when TLS is disabled. Development with self-signed certificates only. |
| `display_name`    | no       | Label for the provider. |

### `azure_event_grid`

| Field            | Required | Meaning |
|------------------|----------|---------|
| `topic_endpoint` | yes      | The topic's endpoint, an absolute `https` URL of up to 1024 chars. |
| `access_key`     | yes      | Write-only, up to 1024 chars. |
| `display_name`   | no       | Label for the provider. |

### `azure_service_bus`

| Field                 | Required | Meaning |
|-----------------------|----------|---------|
| `connection_string`   | yes      | Write-only, up to 1024 chars. |
| `queue_or_topic_name` | yes      | Queue or topic, up to 1024 chars. |
| `display_name`        | no       | Label for the provider. |

### `pubsub`

| Field              | Required | Meaning |
|--------------------|----------|---------|
| `project_id`       | yes      | The GCP project that owns the topic, 6-30 chars. Not the IndyKite project GID. |
| `topic_name`       | yes      | The Pub/Sub topic, 3-255 chars. |
| `credentials_json` | yes      | Write-only: the JSON of a GCP service account key allowed to publish to the topic (e.g. `roles/pubsub.publisher`), as one string of up to 10240 chars. |
| `display_name`     | no       | Label for the provider. |

Every block also carries the read-only `last_error` when the provider has failed - see [`last_error`](#last_error).

The four write-only fields - `password`, `access_key`, `connection_string`, `credentials_json` - come back as empty strings in every read. An update therefore has to send them again.

## Routes

| Field                                            | Required | Meaning |
|--------------------------------------------------|----------|---------|
| `provider_id`                                    | yes      | A key of `providers`. |
| `event_type_key_values_filter.event_type`        | yes      | One event type, or a wildcard ending in `.*`. |
| `event_type_key_values_filter.context_key_value` | no       | List of `{ "key", "value" }` pairs; all must match. |
| `stop_processing`                                | no       | `true`: the routes after this one do not get an event this route matches. Default `false`. |
| `display_name`                                   | no       | Label for the route. |

Rules:

- Routes are evaluated in order; an event goes to every route it matches until one with `stop_processing: true` matches.
- Put specific routes before wildcard routes.
- Prefer `stop_processing: true` on each route. When the send to one route fails, the event is sent again later to all the routes it matches, also to those that already received it, so a provider that accepted the event gets it a second time. An event that goes to one route only is not duplicated that way.
- A route whose provider is switched off after a failure still stops the routes after it when it has `stop_processing`.

### Filters

`context_key_value` narrows a route on the content of the event:

- `captureLabel` - the type or a label of the captured node. Two `captureLabel` pairs match a node that has both: `Person` and `Human` match a node with `"type": "Person"` and the label `Human`.
- A property name as key - matches on the property's value; `*` as value matches any node that has the property.
- `label0`, `label1`, … - for CDC node events only: the node's labels in alphabetical order, one key per label.

```json
{
  "provider_id": "kafka-provider",
  "display_name": "Person Email Events",
  "stop_processing": true,
  "event_type_key_values_filter": {
    "event_type": "indykite.audit.capture.upsert.node",
    "context_key_value": [
      { "key": "captureLabel", "value": "Person" },
      { "key": "email", "value": "*" }
    ]
  }
}
```

## Event types

### Capture

| Operation                              | Event type                                             | Filters |
|----------------------------------------|--------------------------------------------------------|---------|
| Upsert nodes                           | `indykite.audit.capture.upsert.node`                   | `captureLabel`, property key/value |
| Upsert relationships                   | `indykite.audit.capture.upsert.relationship`           | `captureLabel`, property key/value |
| Delete nodes                           | `indykite.audit.capture.delete.node`                   | `captureLabel`, property key/value |
| Delete relationships                   | `indykite.audit.capture.delete.relationship`           | `captureLabel` |
| Delete node properties                 | `indykite.audit.capture.delete.node.property`          | - |
| Delete relationship properties         | `indykite.audit.capture.delete.relationship.property`  | - |
| Delete node labels                     | `indykite.audit.capture.delete.node.tag`               | `captureLabel` |
| Delete node property metadata          | `indykite.audit.capture.delete.node.property.metadata` | - |
| All Capture events                     | `indykite.audit.capture.*`                             | - |

### Configuration

| Operation             | Event type |
|-----------------------|------------|
| Create configuration  | `indykite.audit.config.create` |
| Read configuration    | `indykite.audit.config.read` |
| Update configuration  | `indykite.audit.config.update` |
| Delete configuration  | `indykite.audit.config.delete` |
| List configurations (one event per list call; also `GET /access/v1/policies`) | `indykite.audit.config.list` |
| Assign permission     | `indykite.audit.config.permission.assign` |
| Revoke permission     | `indykite.audit.config.permission.revoke` |
| All configuration events | `indykite.audit.config.*` |

### Authorization, ContX IQ and tokens

| Operation                                               | Event type |
|---------------------------------------------------------|------------|
| Token introspection                                     | `indykite.audit.credentials.token.introspected` |
| AuthZEN evaluation (`POST /access/v1/evaluation`)       | `indykite.audit.authorization.evaluation` |
| AuthZEN evaluations (`POST /access/v1/evaluations`)     | `indykite.audit.authorization.evaluations` |
| AuthZEN subject search (`POST /access/v1/search/subject`)   | `indykite.audit.authorization.searchsubject` |
| AuthZEN resource search (`POST /access/v1/search/resource`) | `indykite.audit.authorization.searchresource` |
| AuthZEN action search (`POST /access/v1/search/action`)     | `indykite.audit.authorization.searchaction` |
| All authorization events                                | `indykite.audit.authorization.*` |
| ContX IQ execute                                        | `indykite.audit.ciq.execute` |

### CDC

Change Data Capture events carry the content of a change: the entity (node or relationship), the operation, its labels, and the property values before and after. They are sent only when the sink has `include_cdc_events: true`.

| Entity       | Event types |
|--------------|-------------|
| Node         | `indykite.audit.cdc.node.create`, `indykite.audit.cdc.node.update`, `indykite.audit.cdc.node.delete` |
| Relationship | `indykite.audit.cdc.relationship.create`, `indykite.audit.cdc.relationship.update`, `indykite.audit.cdc.relationship.delete` |
| All          | `indykite.audit.cdc.*` |

The payload fields of every event type are in the [Audit Event Formats guide](https://developer.indykite.com/guides/guide-audit-formats).

## Lifecycle

### Create

```text
POST /configs/v1/event-sinks
```

`201 Created` returns `id`, `create_time`, `created_by`, `update_time`, `updated_by`, and an ETag header. The destinations are checked for forbidden addresses before anything is stored ([below](#destinations-refused-when-saving)); the connection itself is checked afterwards and reported in `last_error`.

### Read

```text
GET /configs/v1/event-sinks/{id}
GET /configs/v1/event-sinks/{name}?project_id=<project-gid>
```

Returns `id`, `name`, `display_name`, `description`, `organization_id`, `project_id`, `include_cdc_events`, `providers`, `routes`, the audit fields, and the current ETag header. `?version=<n>` reads an earlier version. The write-only fields are empty strings; a failed provider carries `last_error`.

### List

```text
GET /configs/v1/event-sinks?project_id=<project-gid>
```

Returns `{ "data": [ … ] }`. Without `full_fetch=true` the item's `providers` and `routes` are empty. `search=<text>` narrows on name, display name or description.

### Update

```text
PUT /configs/v1/event-sinks/{id}
If-Match: <current-etag>
```

A full replacement of `providers` and `routes`: send every provider with its write-only fields, and every route. `include_cdc_events` left out means `false`. `If-Match` is optional; a stale value is refused with `412`. A new ETag comes back. Every update clears `last_error` on all providers and starts a new connection check. When IndyKite records or removes `last_error` by itself, the ETag does not change, so a held `If-Match` value stays valid.

### Delete

```text
DELETE /configs/v1/event-sinks/{id}
If-Match: <current-etag>
```

Returns `{ "id": "<deleted sink GID>" }`. Events produced from then on are not delivered anywhere.

To stop one route or one provider without deleting the sink, remove it in an update and put it back later.

## `last_error`

Creating or updating a sink does not test the connection in the same call. Each provider is checked afterwards, and a failure is recorded on its block:

```json
{
  "providers": {
    "kafka-provider": {
      "kafka": {
        "brokers": ["broker-1.example.com:9092"],
        "topic": "indykite-events",
        "username": "user1",
        "disable_tls": false,
        "tls_skip_verify": false,
        "last_error": "the endpoint could not be reached. Failure 1 of 10, next retry after <time>."
      }
    }
  }
}
```

The field is absent while the provider is healthy. When present it starts with one of four fixed messages, at most 1024 chars in all:

| `last_error` starts with                  | Meaning and fix | Tried again by IndyKite |
|-------------------------------------------|-----------------|-------------------------|
| `the endpoint could not be reached`       | DNS, dial, TLS or timeout failure. Check host and port, that the endpoint is reachable from the public internet, and for Kafka the TLS settings. | Yes - except when the host resolves to a private, loopback or link-local address. |
| `invalid access key or topic endpoint`    | The endpoint answered but refused the access values or the target: `access_key` / `topic_endpoint` (Event Grid), `connection_string` / `queue_or_topic_name` (Service Bus), `username` / `password` / `topic` (Kafka), `credentials_json` / `topic_name` (Pub/Sub). | No. Correct the settings and update the sink. |
| `the endpoint reported a server error`    | The destination itself failed. Check its own status. | Yes. |
| `the connection to the endpoint failed`   | The connection could not be set up for another reason, such as a setting the provider's client refuses. Check the provider settings. | No. Correct the settings and update the sink. |

How the message ends says where the retries stand:

- `. Failure 3 of 10, next retry after <time>.` - IndyKite tries again by itself; `<time>` is a UTC timestamp (RFC 3339).
- `. Failure 10 of 10, retries stopped. Save the configuration to try again.` - no further attempt until the sink is updated.
- Neither ending - a refusal that is not tried again until the sink is updated.

A provider that was delivering gets `last_error` too, with the same messages, when its sends keep failing or the destination starts refusing them. Once a failure is recorded, every route pointing at that provider is switched off until a later attempt succeeds or the sink is updated, and events that match only such a route in that time are not delivered and not kept for later. The retry schedule is in the [Outbound Events guide](https://developer.indykite.com/guides/guide-outbound-events).

After correcting the settings with a `PUT`, read the sink again a little later: an absent `last_error` means the check passed.

## Destinations refused when saving

`POST` and `PUT` refuse a destination IndyKite would never deliver to, with `422`. Only a host written as a literal address is checked at this point; a host name is resolved later, when IndyKite connects.

| Message | Cause |
|---------|-------|
| `kafka broker: destination is not permitted` | An entry of `kafka.brokers` is a literal private, loopback or link-local address. |
| `azure event grid topic endpoint: destination is not permitted` | `azure_event_grid.topic_endpoint` points at such an address. |
| `azure event grid topic endpoint: not an absolute URL` | `topic_endpoint` has no scheme or no host. |
| `azure event grid topic endpoint: unsupported URL scheme: must be https` | `topic_endpoint` uses `http`. |
| `azure service bus endpoint: destination is not permitted` | The `Endpoint=` part of `azure_service_bus.connection_string` names such an address. |

A Kafka broker given as a host name that resolves to such an address is refused when IndyKite connects, and the provider reports `the endpoint could not be reached` in `last_error`.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `409` `event sink already exists in project` on create | The project already has its event sink. | Read it (list with `?project_id=`) and update it. |
| `422` on create or update, with an `errors` list | Validation failed before anything was stored: no provider, a provider with no block or with two, no route, a missing required field, a field out of its length range, a `name` of the wrong form. | Fix everything the `errors` list names; a `422` reports all the problems at once. |
| `400` on create or update | The body is not valid JSON, a field has the wrong JSON type, or `If-Match` is not an ETag. | Fix the body or the header. |
| `422` naming a destination | See [Destinations refused when saving](#destinations-refused-when-saving). | Use a public address; `https` for Event Grid. |
| `422` `project_id is required when querying by name` | A read by name without `?project_id=`. | Add the project GID. |
| `412` on update or delete | The `If-Match` value is stale. | Read the sink again and use its current ETag. |
| `401` | No Service Account token in `Authorization: Bearer`, or one that is not valid or expired. The Config API takes no other kind of token. | Send a current Service Account token. |
| `403` | The account's role does not allow the operation, or the sink belongs to another organization. | Use an account with Config API write access to the project. |
| An update built from a read is refused, or the provider fails afterwards | A read returns the write-only fields as empty strings, and the update sent those back. | Send the update again with the provider's real values. |
| Created with `201`, but no event arrives | The connection failed after the save, or no route matches. | Read the sink: fix what `last_error` names; otherwise check the route's `event_type` and filters against the operation. |
| CDC events never arrive | `include_cdc_events` is `false`, or was left out of the last update. | Send the update with `include_cdc_events: true` and a route for `indykite.audit.cdc.*`. |
| The same event arrives twice | Delivery is at least once; an event matching several routes is sent again to all of them when one send fails. | Set `stop_processing: true` on each route, and deduplicate on the CloudEvents `id`. |
| A list shows a sink with no providers or routes | The list was read without `full_fetch=true`. | Add `full_fetch=true`, or read the sink by `id`. |

## References

- [Outbound Events guide](https://developer.indykite.com/guides/guide-outbound-events)
- [Audit Event Formats guide](https://developer.indykite.com/guides/guide-audit-formats)
- [Config API guide](https://developer.indykite.com/guides/guide-config-api)
- [Config API documentation - Event Sinks](https://openapi.indykite.com/api-documentation-config#tag/event-sinks)

---
name: indykite-outbound-events
description: Configure IndyKite Outbound Events - the project's event sink, which sends a CloudEvents message to your own Kafka topic, Azure Event Grid, Azure Service Bus or Google Cloud Pub/Sub when data is captured, a configuration changes, an AuthZEN decision is made or a ContX IQ query runs - through the Config API (`/configs/v1/event-sinks` - create / read / list / update / delete, optional ETag). Covers providers, ordered routes with event-type and key/value filters, `stop_processing`, CDC events (`include_cdc_events`), and reading a provider's `last_error`. Use to author, inspect, change or remove an event sink - "send all Capture events to our Kafka topic", "route config changes to Service Bus", "why does the event sink show last_error?", "why 409 / 422 on /configs/v1/event-sinks?". Not for reading the audit trail (indykite-audit-logs), consuming the events in your own system, or writing graph data (indykite-capture-*).
license: Apache-2.0
compatibility: Requires curl and jq. Network access to the regional IndyKite REST API (eu.api.indykite.com or us.api.indykite.com) is required at runtime.
---

# IndyKite Outbound Events - the event sink

Outbound Events send a notification to a system you run each time something happens in an IndyKite project: a node or relationship is captured or deleted, a configuration is created or changed, an AuthZEN decision or search is made, a ContX IQ query is executed. Each notification is a [CloudEvents](https://cloudevents.io/) message.

What is sent, and where, is one Config API object per project: the **event sink**. It has two parts:

- **providers** - the destinations, each under a name you choose: a Kafka topic, an Azure Event Grid topic, an Azure Service Bus queue or topic, or a Google Cloud Pub/Sub topic;
- **routes** - an ordered list of rules, each naming an event type (optionally narrowed by key/value pairs) and the provider that gets the matching events.

This skill covers the event sink lifecycle on `/configs/v1/event-sinks`: writing the JSON body, creating the sink, reading it back (including the health of each provider in `last_error`), updating and deleting it.

## When to use

Activate this skill when the user wants to:

- **send IndyKite events to their own system** - Kafka (Confluent Cloud or self-hosted), Azure Event Grid, Azure Service Bus, Google Cloud Pub/Sub;
- **author or change routes** - which event types go to which provider, filters on a node label or property, route order, `stop_processing`;
- **switch CDC events on or off** (`include_cdc_events`), to receive the before and after state of a change;
- **read, list, update or delete** the project's event sink;
- find out **why events do not arrive** - a provider's `last_error`, a route that never matches;
- understand a `409` or `422` from `/configs/v1/event-sinks`.

Do **not** activate this skill when the user wants to:

- **read or export the audit trail** kept by IndyKite - use [`indykite-audit-logs`](../indykite-audit-logs/SKILL.md);
- **write the consumer** on their side (a Kafka client, a Pub/Sub subscriber) - that is their own code; the payload of each event type is in the [Audit Event Formats guide](https://developer.indykite.com/guides/guide-audit-formats);
- **write graph data** - use the [`indykite-capture-*`](../README.md) or [`indykite-ciq-*`](../README.md) skills; those calls produce the events, they do not configure the sink.

## Prerequisites

- An IndyKite **project**, and its GID in `PROJECT_GID` - it becomes the sink's `project_id`.
- A **Service Account token** with Config API write access, in `SERVICE_ACCOUNT_TOKEN` - used for every `/configs/v1/event-sinks` call.
- The **destination** already exists and can be reached from the public internet: the Kafka brokers and topic, the Event Grid topic endpoint, the Service Bus queue or topic, or the Pub/Sub topic. Its access values (`password`, `access_key`, `connection_string`, `credentials_json`) are not written into the body file: the user sets them in environment variables - for Pub/Sub, the path of the key file - and step 4 fills them in when the request is sent.
- The **event types** to send (step 2). A project has **at most one** event sink: to add a destination to a project that has one, update it (step 6).

If any of these are missing, say so before writing JSON.

## Steps

### 1. Declare the providers

`providers` is an object: each key is a provider name you choose, each value holds **exactly one** of four blocks.

| Block               | Required fields                                    | Optional fields |
|---------------------|----------------------------------------------------|-----------------|
| `kafka`             | `brokers` (list of `host:port`, at least one), `topic` | `username`, `password`, `disable_tls`, `tls_skip_verify`, `display_name` |
| `azure_event_grid`  | `topic_endpoint` (an `https` URL), `access_key`    | `display_name`  |
| `azure_service_bus` | `connection_string`, `queue_or_topic_name`         | `display_name`  |
| `pubsub`            | `project_id` (the GCP project), `topic_name`, `credentials_json` (the service account key, as one JSON string) | `display_name` |

List at least two Kafka brokers, so the connection survives one of them being down. Keep `disable_tls` and `tls_skip_verify` at `false` outside development. Field limits are in [`references/event-sink-reference.md`](references/event-sink-reference.md#providers).

### 2. Write the routes

`routes` is an ordered list with at least one entry. Each route has:

- `provider_id` - a key of `providers`;
- `event_type_key_values_filter.event_type` - one event type, or a wildcard such as `indykite.audit.capture.*`;
- optional `event_type_key_values_filter.context_key_value` - `{ "key", "value" }` pairs that narrow the match, e.g. `captureLabel` = `Person` for the node type, or a property name with value `*` for "has this property";
- optional `stop_processing` and `display_name`.

The event types, by family:

| Family        | Wildcard                         | Examples |
|---------------|----------------------------------|----------|
| Capture       | `indykite.audit.capture.*`       | `indykite.audit.capture.upsert.node`, `indykite.audit.capture.delete.relationship` |
| Configuration | `indykite.audit.config.*`        | `indykite.audit.config.create`, `indykite.audit.config.update` |
| Authorization | `indykite.audit.authorization.*` | `indykite.audit.authorization.evaluation`, `indykite.audit.authorization.searchresource` |
| ContX IQ      | -                                | `indykite.audit.ciq.execute` |
| Token         | -                                | `indykite.audit.credentials.token.introspected` |
| CDC           | `indykite.audit.cdc.*`           | `indykite.audit.cdc.node.update` - sent only with `include_cdc_events: true` |

The full list, and which filters each type accepts, is in [`references/event-sink-reference.md`](references/event-sink-reference.md#event-types).

Routes are evaluated in order. An event goes to each route it matches, until a matching route has `stop_processing: true`: the routes after it are then skipped. Two rules follow:

- Put specific routes before wildcard routes.
- Prefer `stop_processing: true` on each route, so that an event goes to one route only. When the send to one route fails, the event is sent again later to all the routes it matches, also to those that already received it; an event that goes to one route only is not duplicated that way. When the same event must reach several destinations, leave it `false` on the routes that must let later routes match, and deduplicate on the `id` of the CloudEvents envelope in the consumers.

### 3. Assemble the body

```json
{
  "project_id": "<project-gid>",
  "name": "outbound-events",
  "display_name": "Outbound Events",
  "include_cdc_events": false,
  "providers": {
    "kafka-provider": {
      "kafka": {
        "brokers": ["<broker-1-host>:9092", "<broker-2-host>:9092"],
        "topic": "<topic>",
        "username": "<kafka-username>",
        "password": "<kafka-password>"
      }
    }
  },
  "routes": [
    {
      "provider_id": "kafka-provider",
      "stop_processing": true,
      "event_type_key_values_filter": { "event_type": "indykite.audit.capture.*" }
    }
  ]
}
```

`name` is 2-63 chars of lowercase letters, digits and hyphens, unique in the project, and cannot be changed later. Ready bodies with placeholders: [`assets/event-sink-kafka-capture.json`](assets/event-sink-kafka-capture.json) (one provider) and [`assets/event-sink-multi-provider.json`](assets/event-sink-multi-provider.json) (all four provider types, four routes). Copy one to a working file and set the hosts, topics and names there. Leave the placeholders of the four write-only fields (`password`, `access_key`, `connection_string`, `credentials_json`) as they are: step 4 fills them in when the request is sent.

### 4. Create the sink

```text
POST <API_URL>/configs/v1/event-sinks
```

Authenticate with the Service Account token: `Authorization: Bearer <SERVICE_ACCOUNT_TOKEN>`.

`jq` sets `project_id` and the write-only field of each provider from the environment as the request is sent, so the body file keeps its placeholders:

```bash
# project_id and the Kafka password come from the environment at send time
jq --arg pid "$PROJECT_GID" --arg pw "$KAFKA_PASSWORD" \
    '.project_id = $pid | .providers["kafka-provider"].kafka.password = $pw' event-sink.json \
  | curl -i -X POST "$API_URL/configs/v1/event-sinks" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $SERVICE_ACCOUNT_TOKEN" \
      -d @-
```

Each provider takes one `jq` argument and one assignment of this kind; the line for each of the four provider types is in [`references/event-sink-reference.md`](references/event-sink-reference.md#write-only-fields-at-send-time).

A `201 Created` returns the sink's `id` (a `gid:…`), `create_time`, `created_by`, `update_time`, `updated_by`, and an **ETag** header (`-i` prints the response headers). Keep the `id` and the ETag for step 6. Two refusals are specific to event sinks:

- `409` with `event sink already exists in project` - the project has its sink; update that one.
- `422` with an `errors` list - validation failed before anything was stored; fix everything it lists. A destination can be refused this way, e.g. `kafka broker: destination is not permitted` - a provider points at a private, loopback or link-local address, or an Event Grid endpoint is not `https`. The list is in [`references/event-sink-reference.md`](references/event-sink-reference.md#destinations-refused-when-saving).

### 5. Check that the providers connect

`201` means the body is valid, not that the destination answers: the connection is checked afterwards. Read the sink back a little later:

```text
GET <API_URL>/configs/v1/event-sinks/{id}
```

- A provider block **without** `last_error` is healthy.
- A provider block **with** `last_error` has failed. The text says what failed and whether IndyKite tries again by itself (`Failure 3 of 10, next retry after <time>.`) or has stopped (`Failure 10 of 10, retries stopped. Save the configuration to try again.`, or a message with neither ending). The four messages and their fixes are in [`references/event-sink-reference.md`](references/event-sink-reference.md#last_error).

Then run an operation that a route matches - for example a Capture upsert - and look for the message at the destination.

In a read, `access_key`, `connection_string`, `password` and `credentials_json` always come back as empty strings: they are write-only.

### 6. Read, list, update and delete

All with the Service Account token:

- **Read**: `GET /configs/v1/event-sinks/{id}`, or by name with `GET /configs/v1/event-sinks/{name}?project_id={PROJECT_GID}`.
- **List**: `GET /configs/v1/event-sinks?project_id={PROJECT_GID}`. Without `full_fetch=true` the item's `providers` and `routes` are empty.
- **Update**: `PUT /configs/v1/event-sinks/{id}` is a full replacement of `providers` and `routes`, both required. Send every provider again **with its write-only fields**, filled in at send time as in step 4, since a read never returns them, and every route. `include_cdc_events` left out means `false`. `name` and `project_id` cannot change. `If-Match: <etag>` is optional and recommended: a stale value is refused with `412`. Every update clears `last_error` on all providers and starts a new connection check.
- **Delete**: `DELETE /configs/v1/event-sinks/{id}`, with the same optional `If-Match`. It returns the deleted `id`; events produced from then on are not delivered anywhere.

There is no switch to pause one route or one provider. Remove a route in an update, or a provider together with the routes that name it, and put them back later. An update must keep at least one provider and one route: to stop the only destination, delete the sink and create it again later - it gets a new `id`.

## Delivery in brief

- Delivery is **at least once**. A consumer that cannot tolerate repeats should deduplicate on the `id` of the CloudEvents envelope.
- While a provider is failing and nothing is recorded yet, its events are sent again until it recovers. Once `last_error` records a failed round, every route pointing at that provider is switched off until a later round succeeds or the sink is updated; events that match only such a route in that time are not delivered and not kept for later.
- A single event the destination refuses (too large, refused by a filter of the destination) is not sent again, and nothing is recorded in `last_error`.

So watch `last_error` on a sink you depend on. The retry schedule is in the [Outbound Events guide](https://developer.indykite.com/guides/guide-outbound-events).

## Outcome

When this skill has been applied successfully:

- The project has one event sink whose providers point at the user's destinations and whose routes name the event types to send, each with `stop_processing` set deliberately.
- The sink's `id` and current ETag are known, so it can be read, updated or deleted.
- A read shows no `last_error` on any provider, and a matching operation produced a message at the destination - or the `last_error` text has been reported with its fix.

## Files in this skill

- [`references/event-sink-reference.md`](references/event-sink-reference.md) - the body schema (providers, routes, filters), every event type with its filters, CDC events, the Config API lifecycle, `last_error` messages, save-time refusals, and a troubleshooting table.
- [`assets/event-sink-kafka-capture.json`](assets/event-sink-kafka-capture.json) - create body with one Kafka provider and one route for all Capture events.
- [`assets/event-sink-multi-provider.json`](assets/event-sink-multi-provider.json) - create body with all four provider types and four ordered routes.

## Agent-specific notes

This skill uses generic markdown instructions and works across all agents listed in the [README](../README.md). The agent needs to be able to issue HTTP requests (`curl`, an HTTP client, or the IndyKite Terraform provider - see References). No Claude Code hooks, Cursor `@`-mentions, or Copilot workspace context are required.

## References

- [Outbound Events guide (developer hub)](https://developer.indykite.com/guides/guide-outbound-events) - providers, routing, event types, CDC events, provider health and retries.
- [Audit Event Formats guide (developer hub)](https://developer.indykite.com/guides/guide-audit-formats) - the CloudEvents envelope and the payload of every event type.
- [Config API guide (developer hub)](https://developer.indykite.com/guides/guide-config-api) - the rules shared by every Config API resource.
- [Config API documentation - Event Sinks](https://openapi.indykite.com/api-documentation-config#tag/event-sinks)
- [IndyKite Terraform provider - `indykite_event_sink`](https://registry.terraform.io/providers/indykite/indykite/latest/docs) - manages the same object declaratively.

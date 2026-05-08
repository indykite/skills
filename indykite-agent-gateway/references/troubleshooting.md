# IAG Troubleshooting

A symptom-first map from observable failure to most likely cause. Walk it top-to-bottom — earlier rows are cheaper to verify than later ones.

## Symptom: every request returns `401`

| Likely cause                                          | How to verify                                                                    | Fix                                                                |
|-------------------------------------------------------|----------------------------------------------------------------------------------|--------------------------------------------------------------------|
| Caller is not sending a token                         | Check the inbound HTTP `Authorization` header.                                    | Add `Bearer <token>` at the caller.                                |
| Token is expired or not yet active                    | Decode `exp` / `nbf`. Compare with IAG host clock.                                | Refresh the token; sync clocks if skewed.                          |
| IdP introspect endpoint wrong                          | `JARVIS_IDENTITY_PROVIDER_INTROSPECT_ENDPOINT` value vs. IdP docs.                 | Correct the endpoint and restart IAG.                              |
| IdP unreachable from IAG                              | `docker compose logs orchestrator-iag` shows DNS / TCP errors.                    | Fix network path; ensure `extra_hosts` if using Docker Compose.    |

## Symptom: every request returns `403` regardless of caller

| Likely cause                                          | How to verify                                                                     | Fix                                                                 |
|-------------------------------------------------------|-----------------------------------------------------------------------------------|---------------------------------------------------------------------|
| Subject type not allowed                              | Audit `reason` mentions subject type / no policy match.                            | Add the type to `JARVIS_AUTHZEN_SUBJECT_TYPES`.                     |
| `CAN_TRIGGER` edge missing                            | Inspect the IKG: `(:User {external_id:"…"})-[:CAN_TRIGGER]->(:Workflow)`.          | Capture the missing edge.                                           |
| ContX IQ returns nothing                              | Audit `reason` says "no workflow matches" or chain list empty.                     | Confirm `workflow_name` on every `INVOKES` matches `Workflow.external_id`. |
| Wrong `query_id`                                      | Hub UI vs. `JARVIS_CONTX_IQ_QUERY_ID`.                                              | Set the correct `query_id`.                                         |

## Symptom: `403` only when chains include a specific agent

| Likely cause                                          | How to verify                                                                     | Fix                                                                 |
|-------------------------------------------------------|-----------------------------------------------------------------------------------|---------------------------------------------------------------------|
| `Agent.external_id` does not match the IdP client / `act` chain entry | Compare the three values side-by-side.                            | Make all three identical.                                           |
| `INVOKES` relationship missing                        | Query the IKG for the relationship.                                                | Capture the missing relationship.                                   |
| Chain skips a required intermediate agent             | Audit `reason` shows the requested chain.                                          | Route through the orchestrator (or whichever agent the workflow demands). |

## Symptom: `502 Bad Gateway`

| Likely cause                                          | How to verify                                                                     | Fix                                                                 |
|-------------------------------------------------------|-----------------------------------------------------------------------------------|---------------------------------------------------------------------|
| Protected agent unreachable                           | Service log shows connect / dial errors to `protected_agent.base_url`.            | Fix the network path or the URL.                                    |
| Protected agent returns malformed A2A response        | Log shows JSON-RPC parse error.                                                    | Fix the agent's response shape; this is an agent-side bug, not IAG. |
| Audit webhook target down (only if it is the upstream failure surfaced) | Webhook logs / target service.                              | Restart the webhook target or change `audit.http.url`.              |

## Symptom: `500` on otherwise valid requests

| Likely cause                                          | How to verify                                                                     | Fix                                                                 |
|-------------------------------------------------------|-----------------------------------------------------------------------------------|---------------------------------------------------------------------|
| Misconfigured cache TTL                               | Service log shows panic / cache errors.                                            | Reset to defaults (`5m` / `5m` / `10s`); raise log level to `debug`. |
| Audit file path not writable                          | Service log shows `permission denied`.                                             | Fix `audit.storage_path` permissions or volume mount.               |

## Symptom: audit records never reach the configured destination

| Likely cause                                          | How to verify                                                                     | Fix                                                                 |
|-------------------------------------------------------|-----------------------------------------------------------------------------------|---------------------------------------------------------------------|
| Webhook URL wrong                                     | Service log shows HTTP error from audit subsystem.                                 | Correct `audit.http.url`.                                           |
| API-key auth header mismatch                          | Webhook target rejects with `401` / `403`.                                         | Set `audit.http.auth.api_key_header` (default `X-API-Key`).         |
| File rotation deleting before reader consumes         | `ls -la` on `storage_path` shows churning files.                                   | Loosen rotation (`rotation_interval`, `rotation_max_bytes`).        |

## Useful one-liners

```bash
# Stream the JSON service log for one IAG instance
docker compose logs -f orchestrator-iag

# Show only audit-shaped lines (rough filter; audit is a separate stream when configured)
docker compose logs orchestrator-iag | grep -E '"decision":'

# Tail a CSV audit file
tail -f /var/log/iag/audit.csv

# Count denials in the last 100 audit lines
tail -n 100 /var/log/iag/audit.csv | grep -c NOT_AUTHORIZED
```

## When to escalate

- The error reproduces only intermittently → capture `traceID` from the audit record and the protected agent's logs, then file a ticket with both.
- IAG itself crashes (no `200`/`4xx`/`5xx`, the container exits) → grab `docker compose logs <iag>` from boot to crash and share with the IAG maintainers.
- Decision is correct but `reason` is unhelpful → that is a documentation/observability issue, not a misconfiguration; report upstream.

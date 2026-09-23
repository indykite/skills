# IndyKite Token Service (ITS) Reference

The IndyKite Token Service issues and validates the delegation tokens of the Agent Control suite, letting a delegation chain grow safely as a request hops between agents. It implements RFC 8693 (OAuth 2.0 Token Exchange) and RFC 7662 (OAuth 2.0 Token Introspection), and publishes OIDC discovery so relying parties can verify what it signs.

Like the gateway, it is **not part of the IndyKite platform**: it is deployed and operated in the customer's environment from the `indykite/token-service` image. One instance serves every gateway of a workflow.

## When you need it

| Situation                                                                 | IdP alone | With Token Service |
|---------------------------------------------------------------------------|-----------|--------------------|
| One-hop workflow (user → gateway → agent)                                 | works     | works              |
| Multi-hop workflow (user → gateway → agent → gateway → agent …)           | refused - each hop re-exchanges the user's access token, the chain never grows | works - each hop nests the incoming chain |
| Protected agent must see the caller's original access token               | no - replaced by the delegation token | yes - `Authorization` untouched, delegation in `X-IK-Token` |
| Policy reads the delegation chain                                         | `$token`  | `$ik_token`        |

The IdP stays required in both cases: it introspects the caller's access token and authenticates the protected agent (client credentials). The Token Service only exchanges tokens and validates the ones it issued itself.

## Endpoints

| Path                                       | Method     | Purpose                                                                                     |
|--------------------------------------------|------------|---------------------------------------------------------------------------------------------|
| `/oauth2/token`                            | `POST`     | RFC 8693 token exchange: `subject_token` + `actor_token` (both required) → delegation token. Caller authenticates with `idp.client_auth` (HTTP Basic). |
| `/oauth2/introspect`                       | `POST`     | RFC 7662 introspection of a token **this service signed**. Any other token is reported `active: false`. Same client authentication. |
| `/.well-known/openid-configuration`        | `GET`      | Discovery document (issuer, endpoints, supported auth methods).                              |
| `/.well-known/oauth-authorization-server`  | `GET`      | RFC 8414 discovery, same content.                                                            |
| `/.well-known/jwks.json`                   | `GET`      | Public halves of `idp.signing_keys`, so relying parties can verify issued tokens.            |
| `/userinfo`                                | `GET`/`POST` | Claims of an ITS-issued token presented as `Authorization: Bearer`, minus the token mechanics (`iss`, `aud`, `exp`, `iat`, `nbf`, `jti`). A token of any other issuer is refused with `401 invalid_token`. |
| `/oauth2/auth`, `/oauth2/revoke`           | -          | Advertised in discovery for completeness but answer `501` with `{"error": "not_implemented"}`: tokens are obtained only by exchange, and nothing revokes them before they expire. |
| `/healthz`, `/readyz`, `/startupz`         | `GET`      | On `service.healthcheck_port` (default `9080`).                                              |

The gateway's `token_service.exchange_endpoint` and `introspect_endpoint` are `/oauth2/token` and `/oauth2/introspect`. All paths are relative to `service.base_url`, which is also the `iss` of every token. The discovery document is cacheable for 5 minutes.

## Exchange request

The gateway performs this call on every request; it is listed here so a policy author can read the resulting token. `POST /oauth2/token` takes form parameters, and the caller authenticates as the `idp.client_auth` client (HTTP Basic).

| Parameter                                | Rule                                                                                                      |
|------------------------------------------|-----------------------------------------------------------------------------------------------------------|
| `grant_type`                             | Must be `urn:ietf:params:oauth:grant-type:token-exchange`.                                                |
| `subject_token`, `subject_token_type`    | Required. Type must be `urn:ietf:params:oauth:token-type:access_token`. The user's token on the first hop, the previous hop's delegation token afterwards. |
| `actor_token`, `actor_token_type`        | Required - ITS only issues delegated tokens. Same type rule.                                              |
| `requested_token_type`                   | Optional: `urn:ietf:params:oauth:token-type:access_token` or `urn:ietf:params:oauth:token-type:jwt`.      |
| `audience`, `resource`                   | Optional, repeatable; every value must be in `idp.audiences` / `idp.resources`, else `invalid_target`.     |
| `scope`                                  | Accepted and ignored: the claims of an issued token are fixed.                                            |

The `200` response (`Cache-Control: no-store`) carries `access_token`, `issued_token_type`, `token_type: Bearer`, and `expires_in`. The token's claims are exactly `iss`, `sub`, `aud`, `iat`, `exp`, `jti`, and `act` (`sub` + `type` of the actor, nesting the subject token's own `act`, so the oldest agent ends up innermost).

### Exchange errors

RFC 6749 shape: a JSON body with `error` and `error_description`.

| Status / `error`             | Meaning                                                                                                          |
|------------------------------|------------------------------------------------------------------------------------------------------------------|
| `401 invalid_client`         | Client credentials missing or wrong; comes with a `WWW-Authenticate: Basic` challenge.                            |
| `400 unsupported_grant_type` | `grant_type` is not the token-exchange grant.                                                                    |
| `400 invalid_request`        | A required parameter is missing (`subject_token is required`, `actor_token is required, this service only issues delegated tokens`), a token type is not the access-token URN, or `requested_token_type` is unsupported. |
| `400 invalid_grant`          | `the subject_token is not valid` / `the actor_token is not valid` (no configuration matches, expired, badly signed, inactive), `the <name> has no subject`, or `the subject_token has a malformed act claim`. |
| `400 invalid_target`         | `this service does not issue tokens for the audience "<value>"` (or `resource`): the value is not configured.    |
| `500 server_error`           | `the tokens could not be validated` (a provider could not be reached) or `the token could not be issued` (signing failed). Audited as `ERROR`, not as a refusal. |

Introspection: `POST /oauth2/introspect` with `token=<jwt>` (same client authentication) answers the token's claims plus `active: true`, or `{"active": false}` with status `200` for anything unusable. `token_type_hint` is accepted and ignored; no `token` gives `400 invalid_request` (`token is required`); an unauthenticated call gives `401 invalid_client`.

## How an exchange is decided

1. Both tokens are introspected: a token whose `iss` equals `service.base_url` is verified against `idp.signing_keys`; any other token is matched to a `token_introspection.configurations` entry (below) and validated there.
2. The `aud` of the issued token is decided in order: the request's `audience` parameters; else the `aud` of the subject token (the exchange inherits what the delegation was for rather than widening it); else every value in `idp.audiences` (the case of an opaque subject token). A `resource` parameter is added to `aud` as well. Every value must be listed in `idp.audiences` / `idp.resources`, otherwise the exchange is refused with `invalid_target`.
3. The token is signed with the first key in `idp.signing_keys`, carries `sub` (the subject), `act` (`sub` of the actor plus `actor_type`, nesting the previous `act` on later hops), `jti`, and expires after `idp.token_ttl`.

The service keeps no record of issued tokens: introspection re-validates the presented token against its own keys, and it speaks for nothing it did not sign.

## Configuration

Pass `--config=/app/config.yaml` for a single file or, in production, `--config-dir=/etc/token-service`: every file in that directory with a supported extension (`yaml`, `yml`, `json`, `toml`) is merged in alphabetical order, later files overriding earlier ones, so non-sensitive definitions and a secret-store-written file can complete each other without knowing the other's layout. The two flags are mutually exclusive; subdirectories are not read, and the service refuses to start if the directory holds no loadable file. Every key can also come from the environment with the `JARVIS_` prefix.

### `service`

| Field              | Required | Notes                                                                                                                        |
|--------------------|----------|------------------------------------------------------------------------------------------------------------------------------|
| `name`             | yes      | Service name; appears as `service` in audit records.                                                                          |
| `port`             | yes      | Listening port (`8080` by default in the image).                                                                              |
| `base_url`         | **yes**  | Public base URL of this service - the `iss` claim of every token it signs and the base of every discovery URL. No default: startup fails with `service.base_url is required`. Must be stable and `https`; a deployed instance should get a host of its own rather than a path. |
| `environment`, `log_level`, `healthcheck_port` | no | As for the gateway.                                                                                             |

### `idp` - this service as an issuer

| Field                        | Required | Notes                                                                                                                |
|------------------------------|----------|----------------------------------------------------------------------------------------------------------------------|
| `audiences`                  | yes (≥1) | Allow-list of what a token may be issued for; the `aud` values it may carry. List the audience of every protected agent and MCP server the gateways request. Not used to recognise a token as ours. |
| `resources`                  | no       | Allow-list for the RFC 8693 `resource` parameter; without it no request may name a resource.                         |
| `token_ttl`                  | yes      | Lifetime of an exchanged token, positive. Keep it as short as the workflow allows - nothing can revoke a delegation token before it expires. |
| `actor_type`                 | no       | Written into `act` beside the actor `sub`; defaults to `Agent`. The IndyKite backend uses it to resolve the actor in the graph. |
| `client_auth.type`           | yes      | `client_secret_basic` (the only implemented method); published in the discovery document.                             |
| `client_auth.client_id` / `client_secret` | yes | What callers (the gateways' `token_service.client_auth`) present as HTTP Basic on the token and introspection endpoints. |
| `signing_keys`               | yes (≥1) | JSON JWK strings **including the private part**. Each must set `alg` (RS256/384/512, PS256/384/512, ES256/384/512, EdDSA; symmetric algorithms are rejected); `kid` derives from the thumbprint when unset and must be unique. The **first** key signs new tokens; the rest stay published on `jwks_uri` so earlier tokens still verify. To rotate, add the new key at the top and keep the old one until the last token signed with it has expired. |

### `token_introspection.configurations` - validating tokens of other issuers

A map keyed by configuration **name** (required, unique, lower-cased by the loader; used in startup errors and audit records). Being a map is what lets a second file name one configuration and add only the part it carries - which is where `client_auth` secrets belong.

Each entry has:

- `matcher` - `type: jwt` with `issuer` and `audience` (matched against the token's `iss` / `aud` claims), or `type: opaque` (matches non-JWT tokens and is the fallback for JWT-shaped tokens no `jwt` entry matches; at most one per token type).
- `token_types` - any subset of `[subject_token, actor_token]`.
- `validation` - exactly **one** of:
  - `offline` - verify signature and `exp` / `nbf` locally, with inline `keys` (public JWKs) or a `jwks_uri` (else discovered from the issuer's `.well-known/openid-configuration`); `cache_ttl` for fetched keys (default `1h`).
  - `online_oidc` - call the `userinfo_endpoint` (required for opaque tokens; discovered for JWTs); a `jwks_uri` when a signed `application/jwt` userinfo response must be verified without an issuer to discover from; `cache_ttl` for the result (`0` disables).
  - `online_oauth2` - RFC 7662 `introspection_endpoint` (required) with `client_auth` (`client_secret_basic`, `client_id`, `client_secret` - required, kept in a separate merged file); `cache_ttl` for the result.

Matching reads issuer and audience before validation, so they select a configuration rather than enforce a restriction; only offline validation turns them into a guarantee, because there the signature covers those claims. Startup fails when two `jwt` configurations share an issuer + audience pair for the same token type, or when more than one `opaque` configuration exists for a token type. A token issued by this service needs no configuration and no configuration may claim its issuer.

### `audit`

Same shape and options as the gateway's `audit` section (`delivery: webhook | file`, `http.*`, `file.*`, `async.buffer_size`). Every request of both endpoints is audited, whether it succeeded or not. Without the section auditing is disabled - rarely what you want for an issuer of delegated tokens.

Decisions, read together with the record's `action`:

| Action             | Decision                | Meaning                                                                                     |
|--------------------|-------------------------|---------------------------------------------------------------------------------------------|
| `TOKEN_EXCHANGE`   | `TOKEN_EXCHANGED`       | A token was issued; `tokenID` names its `jti`. Issuing is not a grant of access.            |
| `TOKEN_EXCHANGE`   | `EXCHANGE_REFUSED`      | The request was refused (bad request, unauthenticated caller, a token that cannot be exchanged). |
| `TOKEN_INTROSPECT` | `INTROSPECTED`          | The token was described, i.e. it is active. Also written for each token of an exchange, tied to it by `traceID`. |
| `TOKEN_INTROSPECT` | `INTROSPECTED_INACTIVE` | The token cannot be used; `reason` says why (expired, other issuer, forged signature).       |
| `TOKEN_INTROSPECT` | `INTROSPECTION_REFUSED` | Refused before any token was looked at (unauthenticated caller, no token named).             |
| either             | `ERROR`                 | Could not be decided at all (provider unreachable, signing failed). Never counted as a refusal. |

The CSV sink carries a `tokenID` column; files rotated before it was added keep the old header.

## Making the platform trust ITS tokens

The IndyKite platform validates an `X-IK-Token` through the project's [Token Introspect configurations](https://developer.indykite.com/guides/guide-token-introspect), exactly as it validates the user's Bearer token. Without a matching configuration every AuthZEN, ContX IQ, and MCP request that carries an `X-IK-Token` is refused (`401 Invalid token in X-IK-Token header` on REST, `400 invalid_request` on the MCP server). Create **one configuration per audience** ITS can issue for, once per project, with a Service Account token:

```bash
curl -X POST "$API_URL/configs/v1/token-introspects" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $SERVICE_ACCOUNT_TOKEN" \
  -d '{
        "name": "its-indykiteagent-2",
        "project_id": "gid-of-project",
        "jwt_matcher": {
          "issuer": "https://its.example.com",
          "audience": "indykiteagent-2"
        },
        "offline_validation": {
          "public_jwks": [
            "{\"kty\":\"RSA\",\"alg\":\"RS256\",\"kid\":\"its-2026-q3\",\"use\":\"sig\",\"n\":\"...\",\"e\":\"AQAB\"}"
          ]
        },
        "ikg_node_type": "Person",
        "perform_upsert": false
      }'
```

- `jwt_matcher.issuer` is the ITS `service.base_url`, and it must be `https`: the platform treats an `http` issuer as opaque and skips offline validation.
- `offline_validation.public_jwks` holds the **public** JWK only (`kty`, `n`, `e`, `alg`, `kid`, `use`) as a JSON string, up to 10 keys - which is how a rotation is prepared ahead of time. Left empty, the platform fetches the keys from the issuer's discovery document instead, which requires ITS to be reachable from the platform.
- One configuration per `audience` value the delegation token can carry on that path. Allow a few minutes for a new configuration to propagate.

Once trusted, the delegation token is accepted on every AuthZEN and ContX IQ endpoint and by the MCP server, always beside the user's Bearer token and with the same `sub`. Policies read it as `$ik_token`; for example a KBAC filter `{"operator": "=", "attribute": "$ik_token.act.act.sub", "value": "orchestrator"}` allows the action only when the chain started at the orchestrator. See the [AuthZEN guide](https://developer.indykite.com/guides/guide-authzen) and [ContX IQ guide](https://developer.indykite.com/guides/guide-contx-iq).

## Deployment notes

```bash
docker run --rm -d --name token-service -p 8102:8102 \
  -v "$(pwd)/token-service.yaml:/app/.configs/token-service.yaml:ro" \
  indykite/token-service:1.0.0 --config=/app/.configs/token-service.yaml
```

- Pin a concrete tag from Docker Hub rather than `latest`. The image is built for `linux/amd64`; on Apple Silicon add `--platform linux/amd64`.
- Use `--config=<file>` for a single file, or `--config-dir=<dir>` when the sensitive part (`idp.signing_keys`, `idp.client_auth`, introspection `client_auth`) is delivered as a separate file, e.g. from a secret store or a Kubernetes Secret mounted next to the non-sensitive definitions.
- `service.base_url` must be the public `https` URL the gateways, the platform, and any relying party reach the service at; it is the issuer of every token, so it must not change once tokens are in flight. Put the service behind TLS on its own hostname.
- The published port must match `service.port`: the command above and the starter template both use `8102`; if you keep the image default of `8080`, publish `-p 8080:8080` instead. Expose only the ports you need: the request port for the gateways, the health port for orchestration. Ingress, TLS termination, and monitoring are your deployment's concern.

After the rollout, probe readiness on the discovery endpoint rather than only on `/healthz`: a `200` here proves the configuration loaded and traffic is served.

```bash
curl --fail "https://token-service.example.com/.well-known/openid-configuration"
```

A starter `config.yaml` is in [`../assets/token-service-config-template.yaml`](../assets/token-service-config-template.yaml).

## References

- [IndyKite Token Service guide](https://developer.indykite.com/guides/guide-token-service)
- [Token Introspect guide](https://developer.indykite.com/guides/guide-token-introspect)
- [RFC 8693 OAuth 2.0 Token Exchange](https://www.rfc-editor.org/rfc/rfc8693)
- [RFC 7662 OAuth 2.0 Token Introspection](https://www.rfc-editor.org/rfc/rfc7662)
- [RFC 8414 OAuth 2.0 Authorization Server Metadata](https://www.rfc-editor.org/rfc/rfc8414)

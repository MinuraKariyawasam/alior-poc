# What to do next (written 2026-11-02, after phases 1 to 3 and PoD 6.11)

Per-item detail (what it asks, where we stand, how we do it in this setup, proof): `docs/pod-guide.md`.

Out of scope here: PoD 9 (Open Banking), 13 and 14 (AI Gateway), which use the existing demo environments.
Policy Hub catalogue checked on 2026-11-02 (71 policies); "CHECK" means no catalogue policy covers it, so the item is
proven differently, marked `slide`, or reported as a gap (ground rule 2). One PoD item per commit, one `tests/pod-X.sh`
per item, evidence under `evidence/<id>/`, STATUS.md updated as each lands.

## Block 1: routing and the platform story (about 4 days)

| Order | PoD | What to build | How it is proven | Catalogue / notes |
|---|---|---|---|---|
| 1 | 1.2 | API `/legacy/accounts` on pod-b-gw with the VM mock (10.20.16.4:8083) as backend, one policy on it | 200 from region B through Front Door, `x-mock-version: legacy` | none needed |
| 2 | 1.1 | In-cluster mock (`apps`) called by a client pod through the gateway's ClusterIP service, policy applied | east-west call 200, same call without policy header 401 | reuse jwt-auth or basic-auth |
| 3 | 4.1, 4.5, 4.6, 4.7, 4.8 | Routes to v1/v2 mocks by hostname (DNS), context stripping, `/transfers` vs `/transfers/instant`, two routes to one backend | one script, one check per item | gateway routing, no policy |
| 4 | 4.3 | Backend timeout 30 s: endpoint timeout in the Publisher or gateway router config; mock delay header `x-mock-delay-ms: 35000` | 504 after 30 s, 200 at 25 s | CHECK the exact timeout key in the gateway docs |
| 5 | 1.6 | `HTTPS_PROXY` / `NO_PROXY` on the runtime via chart `extraEnv`, a tiny proxy pod that logs | proxy log shows the VM call, the in-cluster call bypasses it | chart key `gateway.gatewayRuntime.deployment.extraEnv` |
| 6 | 2.2, 2.3 | Second environment label per system; GUI path recorded, pipeline path = `tests/gate.sh` extended to a new API version | screen recording + script output | control plane only |
| 7 | 2.4, 2.5 | APIM roles scoped per API/gateway, AKS RBAC per namespace; audit = `git log` + APIM audit log + AKS audit log | screenshots + log excerpts | control plane + AKS diagnostic settings (cheap) |
| 8 | 8.1 | Legacy NGINX origin on Front Door, routes moved one path at a time | k6 against the same client URL, zero errors during the move | Front Door only |

## Block 2: OWASP and OpenAPI readiness with catalogue policies (about 5 days)

| PoD | Policy / mechanism | Status |
|---|---|---|
| 11.1.1 | `basic-auth`, `jwt-auth` (done for the Resident KM), `mtls-auth`; Entra ID once the app registration exists | catalogue |
| 11.1.2, 11.2.4 | `basic-ratelimit` / `advanced-ratelimit` per API, operation, key, user and token; spike arrest = burst setting | catalogue; alerts via Prometheus rule, SIEM via stdout logs (6.6) |
| 11.2.1 | `content-length-guardrail` | catalogue |
| 11.2.2 | `json-schema-guardrail` (depth, fields, array size, length through the schema) | catalogue, partial: CHECK depth limit |
| 11.2.3 | XML threat protection | CHECK: nothing in the catalogue; slide or custom |
| 11.4.1 | SSRF: `url-guardrail` / `regex-guardrail` on the target, or the PoD 3 custom policy | plan says custom; try catalogue first |
| 11.5.1 | TLS version and ciphers: Front Door TLS policy + gateway `router.downstream_tls` | gateway config + Azure |
| 11.5.2 | 405 for methods not in the API definition; `respond` policy for an explicit list | gateway behaviour, test it |
| 11.5.3, 11.5.4, 11.5.6 | `cors`, `set-headers`, `remove-headers` | catalogue |
| 11.5.5 | 415 on content type: `regex-guardrail` on the header or `respond` | CHECK |
| 11.5.7, 6.7 | error sanitization and custom error policy on a group of APIs: `respond` with a fixed body on fault | CHECK how fault flow is attached on the Platform Gateway |
| 11.6.1 to 11.6.3 | inventory, versioning, deprecation, usage: Publisher lifecycle + Dev Portal + Prometheus per-API counters | control plane; usage per consumer needs analytics: CHECK |
| 6.3 | `remove-headers` global (operator values) and per API; compression | headers catalogue; compression CHECK (router config) |
| 6.4 | policy parameters (API), gateway config (Git), environments (control plane) | show the three levels on one policy |
| 6.5 | `pii-masking-regex` on logs/responses; router access log vs controller log as the two streams | catalogue + 6.6 |
| 6.1, 6.2, 6.12 | client certificates per application, CRL/OCSP, JWS verification | CHECK: 6.1/6.2 via `mtls-auth` with stored certs, CRL/OCSP likely slide; 6.12 custom |
| 6.10 | SQL injection: Front Door WAF (already 403) + `regex-guardrail`; k6 with and without | WAF proven, perf run pending |
| 6.9 | upgrade procedure: `docs/upgrade.md` (operator chart bump, APIM Helm bump, order, rollback) | docs |
| 4.9, 5.2, 5.3 | session affinity, fault injection, circuit breaking | CHECK: not in the catalogue; ask Gihan, else `slide` |
| 5.1, 5.4 | weighted v1/v2 backends, shift 90/10 → 0/100, mirroring | weights: CHECK the Publisher endpoint config for the Platform Gateway; mirroring not in the catalogue |

## Block 3: custom security layer, PoD 3 (about 5 days, highest risk)

Go policy built with Gateway Builder: read request and response bodies (3.1), MD5 logged (3.2), `X-Status` on success and
on backend errors (3.3), startup load from an external service with 15-minute refresh and last-good value (3.4),
readiness OUT_OF_SERVICE until loaded (3.5), k6 with and without (3.6). Also covers 6.8 (global vs selective) and the
SSRF fallback for 11.4.1. Needs a custom gateway image in ACR and the operator pointed at it; agree the load profile for
3.6 with the bank first.

## Block 4: resilience, DR and the drills (about 3 days)

| PoD / drill | What |
|---|---|
| 10.2 | HPA on the region A runtime, scale 4 → 8 under k6, zero errors |
| 10.1 | `docs/dr.md`: control plane DB backup/restore (pod-a-db), rebuild from Git; live demo: wipe wso2-gw in region B, Argo CD rebuilds it |
| D1 to D6 | kill region A pods, control plane down + runtime restart, scale, pipeline import, NSG cut of region B, lose region A. Record each with Grafana on screen |
| 15.2, 15.4 | slides backed by the recordings. The controller-restart API loss was a 1.2.x issue, fixed by the 2026.10.0 upgrade (2026-11-02); `make drill D=controller-restart` is the check |

## Block 5: slides and evidence (about 3 days)

PoD 12 (data flows, JIT access, bank-owned keys, tenant separation), 15.1 and 15.3 (service mesh), 1.4 and 1.5
write-ups with the evidence collected above, `evidence/` complete for every live item, bank sheet columns filled, dry run.

## Small items to close in passing

- Ask WSO2 (via Gihan) whether gateway 1.2.x has an outbound proxy setting for the controller, policy engine and router: HTTPS_PROXY/NO_PROXY env is ignored (PoD 1.6 finding, 2026-11-02).
- Switch the UI WAF `podwafui` to Prevention after a login pass.
- Change the gateway controller admin password from the chart default.
- Decide live syslog demo or slide for 6.6.

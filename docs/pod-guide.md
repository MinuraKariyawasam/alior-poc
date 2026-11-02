# PoD item guide (table): what it asks, where we stand, how we do it here, proof

PoD 9, 13, 14 (Open Banking, AI Gateway) live on the existing demo environments and are not listed. Status as of 2026-11-02.

**Vocabulary.** *Catalogue* = a Policy Hub policy attached in the Publisher (API → Policies) and deployed as a new revision (REST shape in `docs/pod-6.11-jwt.md`). *Gateway config* = `platform/gateway/region-*/gateway-values.yaml` through Argo CD (bump `config-rev`; since the 2026.10.0 upgrade a controller restart keeps the deployed APIs). *CHECK* = nothing in the catalogue or unverified; ask Gihan before spending time, else `slide`.

**Fixed pieces**

| Piece | Where |
|---|---|
| Front Door API | `https://pod-api-guf3bbbjh5htgxfu.a02.azurefd.net/<context>/<version>/...`, WAF `podwaf` Prevention |
| Gateways | `pod-a-gw` (polandcentral, 74.153.35.38), `pod-b-gw` (westeurope, 132.220.139.111); vhosts `pod-<r>-gw.alior-poc.local` |
| Control plane | APIM 4.7.0 in `wso2-cp`; Publisher, Dev Portal, Admin at `pod-cp-eccmfmahgkevcqcy.a02.azurefd.net` |
| Mocks | pod-b-vm 10.20.16.4: v1 :8081, v2 :8082, legacy :8083 (`mocks/mock.py`; headers `x-mock-delay-ms`, `x-mock-status`); one in-cluster mock per cluster in `apps` |
| Observability | Prometheus + Grafana per cluster (`/grafana` on the UI endpoints); JSON logs on stdout |
| Existing APIs / app | `accounts` (open), `accounts-secure` (jwt-auth 1.3); Dev Portal app `pod-health` |
| Proof pattern | `tests/pod-X.sh`, `make test POD=X`, output in `evidence/X/` |

## Items

| PoD | Ask | Status | How we do it here | Proof |
|---|---|---|---|---|
| **1 Architecture** | | | | |
| 1.1 | App A calls app B through the gateway inside one cluster | **Done** | API `internal` → in-cluster mock (`platform/apps/`, Argo app `apps`) with `jwt-auth`; curl pod in `apps` calls the runtime ClusterIP with the vhost Host header | `make test POD=1.1` PASSED 2026-11-02 in both clusters; `evidence/1.1/` |
| 1.2 | Dedicated gateway cluster, untrusted zone, backend on a VM | **Done** | API `legacy` (`/legacy` → `http://10.20.16.4:8083`) with `jwt-auth`, deployed to both gateways (Front Door may pick either region); region B is the dedicated cluster, the VM is the standalone backend | `make test POD=1.2` PASSED 2026-11-02: 401/200 via Front Door with `x-mock-version: legacy`, region B direct 200, gateway IPs and VM closed to the Internet; `evidence/1.2/` |
| 1.3 | WAF / anti-DDoS in front of exposed services | **Done** | Front Door Premium WAF `podwaf` (OWASP DRS 2.1 + Bot Manager), Prevention; `infra/azure/frontdoor.sh` | `tests/gate.sh`, `make health`: injection → 403; add WAF log screenshot to `evidence/1.3/` |
| 1.4 | Gateway on-prem (K8s/VMs) and in cloud | **Done** | Two AKS clusters in two regions run the same `APIGateway` CR; region B is the on-prem stand-in (K8s). Decided 2026-11-02: no VM deployment | `evidence/1.4/two-clusters.txt` (pods in both clusters) and `cr-diff-a-vs-b.txt` (only the control plane host differs) |
| 1.5 | Multiple gateway instances, HA, no SPOF | **Done** | `replicaCount: 2` for the runtime in both overlays; two regions behind Front Door; control plane single by scope | `make test POD=1.5` PASSED 2026-11-02: region A runtimes killed under traffic, 0/40 failures; `evidence/1.5/` |
| 1.6 | Selective HTTP proxy (NO_PROXY / PAC) | **Gap, to check with WSO2** | Proxy env on controller and runtime (`extraEnv`, both overlays), logging proxy `proxy.apps.svc:3128` (`platform/apps/proxy.py`). Result: no gateway component honours the env (control plane link, JWKS fetch, Envoy backend calls all direct) | `make test POD=1.6` records the finding and fails; `evidence/1.6/`. Question for WSO2: outbound proxy setting in the controller / policy engine / router |
| **2 Control / data plane ops** | | | | |
| 2.1 | General API Management configuration | **Done** | APIM 4.7.0, Postgres on `pod-a-db`, both gateways registered | Admin portal screenshots → `evidence/2.1/` |
| 2.2 | Gateways per environment / system | In progress | Environments `pod-a-gw`, `pod-b-gw` exist; add a third / labels in Admin → Gateways; one API to A only, one to both | `tests/pod-2.2.sh`: environments + per-API deployments |
| 2.3 | New gateway + API versioning, GUI and pipeline | In progress | GUI: record publishing `accounts` 2.0.0; pipeline: extend `tests/gate.sh` to a version bump; new gateway: `platform/gateway/region-c/` CR via Argo CD + `register.sh` | recording + script output |
| 2.4 | Permissions per gateway / domain | Not started | APIM roles + scope mapping (`team-a` can publish to A only); K8s RBAC Role limited to `wso2-gw` (`platform/rbac/`) | denied-action screenshots; `kubectl auth can-i` |
| 2.5 | Audit who changed what and when | Not started | `git log`; APIM `audit.log`; AKS `kube-audit-admin` diagnostic to Log Analytics | one route added → the three log lines |
| **3 Custom security layer** | | | | |
| 3.1 | Read full request and response bodies | Not started | One Go policy in `policies/custom-security/`, built with Gateway Builder into a custom image in ACR; operator CR points at it. Attach path verified 2026-11-02: Publisher accepts non-Hub policy names, the controller validates against the definitions in the image | `tests/pod-3.sh` |
| 3.2 | MD5 of both bodies, logged | Not started | same policy, MD5 in the router/policy log | MD5 printed from the log |
| 3.3 | `X-Status` on success and on backend errors | Not started | same policy, response hook incl. upstream failure path | header on 200 and on `x-mock-status: 500` |
| 3.4 | Load external data at startup, refresh every 15 min, keep last good | Not started | background goroutine + cached value; mock VM as the external service | stop the service → value persists |
| 3.5 | OUT_OF_SERVICE until first load | Not started | policy engine readiness; fallback sidecar + pod readiness probe | readiness flips, shown with `kubectl get pods` |
| 3.6 | Latency overhead of the layer | Not started | k6 (`tests/k6/`) with policy on and off; agree profile with the bank; note the 25 ms peering hop for region A | k6 summaries |
| **4 Routing** | | | | |
| 4.1 | Client → microservice through the gateway | Done in practice | `accounts` → VM v1 | in `tests/pod-4.sh` |
| 4.2 | Microservice → microservice inside the cluster | Not started | same build as 1.1 | `tests/pod-1.1.sh` |
| 4.3 | Backend not responding, 30 s timeout | Not started | endpoint timeout in the Publisher or router upstream timeout in gateway config (CHECK which applies); `x-mock-delay-ms: 35000` / `25000` | 504 after 30 s, 200 at 25 s |
| 4.4 | Multi-cluster communication | Slide | L0/L1 diagrams | slide |
| 4.5 | DNS support | Not started | backend by hostname (Private DNS record for pod-b-vm) instead of IP | router log shows resolution |
| 4.6 | Strip prefix | Not started | context `/accounts/1.0.0` stripped by default | mock echoes the backend `path` |
| 4.7 | Route priority `/transfers` vs `/transfers/instant` | Not started | two resources to v1 and v2; longest match wins | `x-mock-version` per path |
| 4.8 | Multiple routes to one microservice | Not started | two contexts, same backend | both 200 to v1 |
| 4.9 | Sticky sessions | CHECK | not in the catalogue; ask about router hash/cookie LB | else `slide` |
| **5 Traffic** | | | | |
| 5.1 | X% of traffic to a version | CHECK | how the Platform Gateway expresses weighted endpoints (Publisher endpoint config?) | k6 + `x-mock-version` split |
| 5.2 | Fault injection abort / delay | CHECK | not in the catalogue; mocks fake it but that is the backend | likely `slide` |
| 5.3 | Circuit breaking | CHECK | not in the catalogue; router outlier detection? | likely `slide` |
| 5.4 | Traffic shifting / mirroring | CHECK | shifting = 5.1 weights in steps via the Publisher; mirroring not in the catalogue | shifting k6; mirroring `slide` |
| **6 OpenAPI readiness** | | | | |
| 6.1 | Public cert per Dev Portal application | CHECK | `mtls-auth` with stored certs; verify what the Dev Portal offers for the Platform Gateway | |
| 6.2 | CRL / OCSP validation | CHECK | probably `slide` | |
| 6.3 | Shared header removal, compression | Not started | `remove-headers` per API and global (CHECK global chain); compression CHECK router config | headers absent in response |
| 6.4 | Parameters at API, gateway, environment level | Not started | policy parameter (API), overlay value (gateway), environment-specific endpoint (control plane); guided demo | screenshots |
| 6.5 | Log anonymisation, technical vs customer logs | Not started | `pii-masking-regex`; two log streams (router vs controller); access-log fields via `router.access_logs.json_fields` | masked log line |
| 6.6 | Forward logs to syslog / Elasticsearch | In progress | JSON on stdout proven; decide Fluent Bit → syslog receiver pod for the demo, or slide | `evidence/6.6` |
| 6.7 | Custom error policy on a group of APIs | Not started | `respond` with fixed JSON on the fault flow, attached to several APIs (CHECK fault-flow attach) | `x-mock-status: 500` → standard body |
| 6.8 | Custom modules global and selective | Not started | PoD 3 policy on one API, then globally (CHECK global attach) | |
| 6.9 | Upgrade procedure | Not started | `docs/upgrade.md`: operator chart bump, APIM chart bump, order, rollback by Git revert, WSO2 Updates | docs |
| 6.10 | SQL injection protection and its cost | In progress | Front Door WAF already 403; `regex-guardrail` on the gateway; k6 with/without | WAF proven; k6 pending |
| 6.11 | Bundled OAuth2 server on selected APIs | **Done** | key manager block in gateway config + `jwt-auth` 1.3 on `accounts-secure` | `make test POD=6.11`, `evidence/6.11` |
| 6.12 | JWS verification with stored certificates | CHECK | not in the catalogue; custom or `slide` | |
| **7 Logs and metrics** | | | | |
| 7.1 | Metrics and logs per layer | **Done** (gateway) | kube-prometheus-stack + ServiceMonitors + WSO2 dashboards; control plane metrics optional (APIM Prometheus endpoint + ServiceMonitor) | `make test POD=7.1`, `evidence/7.1` |
| 7.2 | Grafana, OpenTelemetry | **Done** (Grafana) | OTel traces via `[tracing]` to a collector not deployed; slide or add if asked | same |
| **8 Migration** | | | | |
| 8.1 | Move microservices to the new gateway transparently | Not started | NGINX pod in `apps` as legacy gateway, second Front Door origin group; move paths one at a time by route patterns | k6 on the same URL, zero errors |
| **10 HA / DR** | | | | |
| 10.1 | DR approach, backup and restore | Not started | `docs/dr.md`: `pg_dump` of pod-a-db to the storage account, restore, rebuild from Git; live: wipe `wso2-gw` in B, Argo CD rebuilds, re-register, redeploy | recording |
| 10.2 | HA, scale 4 → 8 | Not started | HPA on the region A runtime (`gateway.gatewayRuntime.autoscaling`); node pool sized for the drill; k6 | Grafana + k6, zero errors |
| **11 OWASP** | | | | |
| 11.1.1 | Per-endpoint auth: Basic, OAuth2/JWT (Entra ID), mTLS | In progress | `basic-auth`, `jwt-auth` (done for Resident KM; Entra ID = second `keymanagers` entry when the app registration exists), `mtls-auth`; attach per operation | `tests/pod-11.1.1.sh` |
| 11.1.2 | Brute force: rate limit by key/user/token, spike arrest, alerts, SIEM | Not started | `basic-ratelimit` / `advanced-ratelimit` keyed on key, user claim, token; alert = Prometheus rule; SIEM = stdout logs (6.6) | 429 after N calls; alert fired |
| 11.2.1 | Payload size limit | Not started | `content-length-guardrail` | 413 over the limit |
| 11.2.2 | JSON threat protection | Not started | `json-schema-guardrail` bounding depth, fields, arrays, lengths (CHECK pure depth limit) | 400 on a deep payload |
| 11.2.3 | XML threat protection | CHECK | nothing in the catalogue | `slide` or custom |
| 11.2.4 | Rate limits per API / endpoint / operation; parameter caps | Not started | ratelimit at API and operation level; `regex-guardrail` / `url-guardrail` on `limit`, `pageSize`; override via `request-rewrite` (CHECK) | 429 and 400 cases |
| 11.3.1 | Flow control, bot detection, CAPTCHA | GAP | gateway alone cannot; Front Door Bot Manager + rate rules; flow control `slide` | WAF bot log |
| 11.4.1 | SSRF detection | Not started | `url-guardrail` / `regex-guardrail` for 169.254.169.254, localhost, 127.0.0.1; fallback PoD 3 policy | 400 on the SSRF payload |
| 11.5.1 | TLS versions and ciphers | Not started | Front Door TLS policy (min 1.2) + `router.downstream_tls` in gateway config | `openssl s_client` TLS 1.0/1.1 refused |
| 11.5.2 | Method filtering, 405 | Not started | methods not in the API definition rejected by the router; `respond` if the code is 404 not 405 | PUT/DELETE/TRACE on `accounts` |
| 11.5.3 | CORS | Not started | `cors` policy, same config on several APIs | preflight response headers |
| 11.5.4 | Security headers | Not started | `set-headers` on the response flow (HSTS, nosniff, X-Frame-Options, CSP) | headers present |
| 11.5.5 | Content-Type restrictions, 415 | CHECK | `regex-guardrail` on Content-Type + `respond` 415, or note the gap | |
| 11.5.6 | Header transformation | Not started | `remove-headers` (Server, X-Powered-By) + `set-headers` | headers gone / added |
| 11.5.7 | Error response sanitisation | Not started | `respond` on the fault flow with a standard body (same as 6.7) | backend stack trace never reaches the client |
| 11.6.1 | API inventory (shadow, zombie) | CHECK | Publisher lists all APIs with state; discovery of unknown endpoints not a Platform Gateway feature | gateway API list vs Publisher |
| 11.6.2 | Versioning, deprecation, lifecycle | Not started | Publisher lifecycle on `accounts` 1.0.0 vs 2.0.0 (from 2.3) | lifecycle screenshots |
| 11.6.3 | Usage per consumer / version, unused APIs | CHECK | `policy_engine_requests_total` by route; per consumer needs analytics or access-log subject | Grafana panel |
| **12 Data processing (slides)** | | | | |
| 12.1 | Data flows and locations | Slide | L0/L1; Postgres in A, SQLite on gateways, logs on stdout | slide |
| 12.2 | JIT service/support access | Slide | Azure PIM, Key Vault | slide |
| 12.3 | Bank-owned keys, rotation | Slide | Key Vault; gateway AES key (`secrets.sh`), APIM encryption key | slide |
| 12.4 | Two tenants / domains separated | Slide | APIM organisations/tenants; separate gateways per domain (2.2) | slide |
| **15 Evolution (slides + recordings)** | | | | |
| 15.1 | Central layer across clusters, on-prem, clouds | Slide | L0 + operator story | slide |
| 15.2 | Control/data plane, loss of connectivity | In progress | drill D2 recording; include the controller-restart finding and workaround | recording |
| 15.3 | Service mesh split of responsibilities | Slide | slide | slide |
| 15.4 | HA, scaling, DR, degraded mode | Slide | drills D1, D3, D5, D6 recordings; 10.1, 10.2 evidence | recordings |

## Drills (feed 1.5, 10.x, 15.x)

| ID | Drill | Expected | Notes |
|---|---|---|---|
| D1 | kill region A gateway pods | Front Door shifts to B, a blip | probe interval sets the blip length |
| D2 | control plane down, then restart runtime and controller pods | traffic continues from local config | fixed in gateway 2026.10.0 (upgraded 2026-11-02); `make drill D=controller-restart` passes |
| D3 | scale runtimes 4 → 8 | zero errors | node capacity |
| D4 | pipeline imports a new API version | appears in both regions | `tests/gate.sh` |
| D5 | NSG blocks region B → control plane | B keeps serving | rule like `make lockdown` |
| D6 | lose region A | B serves; no publishing until A is back | stop the A node pools |

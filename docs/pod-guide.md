# PoD item guide: what each item asks, where we stand, how we do it here

One entry per item, same four lines each, so it is quick to scan and recall. PoD 9, 13 and 14 (Open Banking, AI Gateway)
are on the existing demo environments and are not listed. "Catalogue" means a Policy Hub policy attached in the Publisher
(API → Policies) and deployed as a new revision; the Publisher REST shape is in `docs/pod-6.11-jwt.md`. "Gateway config"
means `platform/gateway/region-*/gateway-values.yaml` through Argo CD (bump `config-rev`, then `make gate` because a
controller restart drops the deployed APIs until the control plane redeploys them). Status dates are 2026-11-02.

Our fixed pieces, for reference:

| Piece | Where |
|---|---|
| Front Door API endpoint | `https://pod-api-guf3bbbjh5htgxfu.a02.azurefd.net/<context>/<version>/...`, WAF `podwaf` Prevention |
| Gateways | `pod-a-gw` (polandcentral, 74.153.35.38) and `pod-b-gw` (westeurope, 132.220.139.111), vhosts `pod-<r>-gw.alior-poc.local` |
| Control plane | APIM 4.7.0 in `wso2-cp`, Publisher/Dev Portal/Admin at `pod-cp-eccmfmahgkevcqcy.a02.azurefd.net` |
| Mocks | pod-b-vm 10.20.16.4: v1 :8081, v2 :8082, legacy :8083 (`mocks/mock.py`, headers `x-mock-delay-ms`, `x-mock-status`); one in-cluster mock per cluster in `apps` |
| Observability | Prometheus + Grafana per cluster (`/grafana` on the UI endpoints), JSON logs on stdout |
| Existing APIs | `accounts` (open), `accounts-secure` (jwt-auth 1.3), Dev Portal app `pod-health` |
| Proof pattern | `tests/pod-X.sh`, `make test POD=X`, output under `evidence/X/` |

---

## PoD 1: architecture in practice

**1.1 Control API calls between apps inside one cluster**
- Ask: deploy on K8s, app A calls app B through the gateway inside the cluster.
- Status: Not started. The in-cluster mock pod and the gateway ClusterIP service exist.
- How: publish `accounts-internal` with the in-cluster mock service as backend (`http://mock.apps.svc:8080`); attach `basic-auth` or `jwt-auth`; run a `curl` pod in `apps` calling `pod-a-gw-gw-gateway-gateway-runtime.wso2-gw.svc:8080` with the vhost as Host header.
- Proof: `tests/pod-1.1.sh`: 401 without credentials, 200 with, from inside the cluster; `kubectl logs` of the router showing the call.

**1.2 Separate cluster, untrusted zone, backend on a VM**
- Ask: a dedicated gateway cluster handling calls from an untrusted zone to APIs on another cluster or on VMs.
- Status: Not started. Region B gateway, VNet peering and the VM mocks are all in place; `accounts` already reaches the VM through both gateways.
- How: publish `legacy` (context `/legacy`, backend `http://10.20.16.4:8083`) to `pod-b-gw` only, attach one policy (for example `basic-ratelimit`); call through Front Door, which only has the two gateways as origins.
- Proof: `tests/pod-1.2.sh`: 200 with `x-mock-version: legacy` through Front Door; direct VM port unreachable from the Internet (NSG).

**1.3 WAF / lower-layer protection**
- Ask: protect exposed services with IPS/anti-DDoS or a WAF.
- Status: Done. Front Door Premium WAF `podwaf` (OWASP DRS 2.1 + Bot Manager) in Prevention; `?q=1 union select 1` → 403 (`tests/gate.sh`, `make health`).
- How: `infra/azure/frontdoor.sh`. Front Door also absorbs L3/L4 DDoS by design (Azure DDoS infrastructure protection).
- Proof: in place; add a screenshot of the WAF log entry to `evidence/1.3/`.

**1.4 Gateway on-prem and in cloud**
- Ask: deploy the gateway both on-prem (K8s or VMs) and in Azure/GCP.
- Status: In progress. Two AKS clusters by the same operator CR; region B stands in for on-prem.
- How: the same `APIGateway` CR and chart work on any K8s; for the VM story show WSO2's Docker Compose / binary distribution on a slide (the AI Gateway sample uses it). No build needed.
- Proof: write-up in `docs/` with the two CRs side by side plus the vendor's VM install reference.

**1.5 Multiple gateway instances, HA, no SPOF**
- Ask: cooperating gateway instances with HA.
- Status: In progress. Two regions active-active behind Front Door; one runtime replica per region by decision.
- How: raise `gateway.gatewayRuntime.deployment.replicas` to 2 in both overlays for the drills; Front Door health probes on `/_gateway-health/ready` take a region out. The control plane is the known single instance (decision, PoD 15.2).
- Proof: drill D1 recording (kill region A pods, traffic continues from B) plus `kubectl get pods` with 2 runtimes.

**1.6 Selective HTTP proxy for outbound**
- Ask: HTTPS_PROXY with NO_PROXY or PAC.
- Status: Not started.
- How: deploy a small proxy (tinyproxy) in `apps` with logging; set `HTTPS_PROXY`/`HTTP_PROXY`/`NO_PROXY` through `gateway.gatewayRuntime.deployment.extraEnv` in the overlay, NO_PROXY covering `.svc` and the VM subnet or not, depending on the scenario.
- Proof: `tests/pod-1.6.sh`: proxy log shows the external call, the in-cluster call is absent from it. CHECK: whether the Envoy router honours proxy env vars for upstream connections (it may need an explicit proxy config instead); verify in the gateway docs before building.

## PoD 2: control plane and data plane operations

**2.1 General API Management configuration**
- Status: Done. APIM 4.7.0 in `wso2-cp`, Postgres on `pod-a-db`, both gateways registered (`docs/phase2-platform.md`).
- Proof: Admin portal screenshots (environments, key managers) to `evidence/2.1/`.

**2.2 Gateways per environment / system**
- Status: In progress. Environments `pod-a-gw` and `pod-b-gw` exist.
- How: add gateway environment labels or a third environment in Admin → Gateways; deploy one API to A only, another to both. Show the Publisher's environment picker.
- Proof: `tests/pod-2.2.sh`: `admin/v4/environments` and the per-API deployments list.

**2.3 New gateway + API versioning, GUI and pipeline**
- Status: In progress. Pipeline path = `tests/gate.sh` (import OpenAPI, revision, deploy to both gateways).
- How: GUI: record publishing `accounts` 2.0.0 in the Publisher and deploying it. Pipeline: extend the gate to create version 2.0.0 from `tests/accounts-openapi.yaml` with a version bump. New gateway: show the operator CR for a third gateway (`platform/gateway/region-c/`) applied by Argo CD and registered by `register.sh`, without actually paying for a cluster: apply it in region B's cluster as a second gateway if time allows.
- Proof: recording + script output; `evidence/2.3/`.

**2.4 Permissions per gateway / domain**
- Status: Not started.
- How: APIM roles and scopes (Admin → Scope mapping) so a `team-a` user can only publish to environment A; Kubernetes RBAC: a Role limited to `wso2-gw` for the infra team, read-only elsewhere (`platform/rbac/`).
- Proof: screenshots of a denied action per user; `kubectl auth can-i` output.

**2.5 Audit of configuration changes**
- Status: Not started.
- How: three sources already there: `git log` for everything in Git, APIM's audit log (`repository/logs/audit.log`, who published what) and AKS audit logs (enable the `kube-audit-admin` diagnostic category to a Log Analytics workspace, cheap).
- Proof: one route added, then the three log lines that show who and when.

## PoD 3: custom security layer (Go policy with Gateway Builder)

**3.1 Read full request and response bodies**, **3.2 MD5 of both, logged**, **3.3 `X-Status` header on success and on backend errors**, **3.4 Load data from an external service at startup, refresh every 15 min, keep last good value**, **3.5 Health OUT_OF_SERVICE until the first load**, **3.6 Latency overhead**
- Status: Not started. Highest risk block.
- How: one Go policy under `policies/custom-security/`, built with WSO2's Gateway Builder into a custom gateway image pushed to ACR, the operator's `APIGateway` CR pointed at that image. 3.1 to 3.3 are request/response hooks in the policy; 3.4 is a background goroutine with a cached value; 3.5 wires the policy engine readiness (or, fallback, a sidecar that owns the data and a pod readiness probe). The mock VM serves as the "external service".
- Proof: `tests/pod-3.sh` prints the MD5 from the router log and the `X-Status` header on a 200 and on a `x-mock-status: 500`; 3.4/3.5 by stopping the external service and watching the value persist and the readiness flip; 3.6 by k6 with the policy on and off (`tests/k6/`), load profile agreed with the bank first. Region A calls cross the peering (about 25 ms), mention it in the write-up.

## PoD 4: routing and addressing

**4.1 Client to microservice through the gateway**: Done in practice (`accounts` → VM v1); formal proof in the routing script.
**4.2 Microservice to microservice inside the cluster**: same build as 1.1.
**4.3 Backend not responding, 30-second timeout**
- How: set the endpoint timeout on the API (Publisher endpoint config) or the router's upstream timeout in gateway config; drive with `x-mock-delay-ms: 35000` and `25000`. CHECK which of the two the Platform Gateway honours.
- Proof: 504 after 30 s, 200 at 25 s, timings printed.
**4.4 Multi-cluster communication**: Slide (bank: implementation not required). Reuse the L0/L1 diagrams.
**4.5 DNS support**: backend given as a hostname (`pod-b-vm.<private-dns>` or an Azure Private DNS zone record) instead of the IP; show resolution in the router log.
**4.6 Strip prefix**: the context `/accounts/1.0.0` is stripped before the backend by default; prove with the mock's echoed `path`.
**4.7 Route conflicts / priorities**: two APIs or two resources `/transfers` and `/transfers/instant` pointing at v1 and v2; longest match wins; prove with `x-mock-version`.
**4.8 Multiple routes to one microservice**: two contexts to the same backend.
- Proof for 4.1, 4.5 to 4.8: one script `tests/pod-4.sh`, one labelled check per item.
**4.9 Sticky sessions**: CHECK. Not in the catalogue; ask Gihan whether the router exposes hash/cookie load balancing. Otherwise `slide`.

## PoD 5: traffic management

**5.1 X% of traffic to a version**: CHECK how the Platform Gateway expresses weighted endpoints (Publisher endpoint config or gateway route config). Prove with k6 and the `x-mock-version` split.
**5.2 Fault injection abort/delay**: CHECK. Not in the catalogue. The mocks can fake it (`x-mock-status`, `x-mock-delay-ms`) but that is the backend, not the gateway. Likely `slide`.
**5.3 Circuit breaking / outlier detection**: CHECK. Not in the catalogue. Likely `slide`, unless the router's cluster config exposes outlier detection.
**5.4 Traffic shifting and mirroring**: shifting = change the weights of 5.1 in three steps (through the Publisher, top-down; note the plan said "via Git", which does not apply to APIs here). Mirroring not in the catalogue: CHECK, likely `slide`.

## PoD 6: OpenAPI readiness

**6.1 Public certificate per application stored online**: CHECK. Dev Portal application certificates exist for the classic gateway; for the Platform Gateway use `mtls-auth` with stored certificates. Verify what the Dev Portal offers before promising.
**6.2 CRL/OCSP validation**: CHECK. Probably `slide`.
**6.3 Shared header removal and compression**: `remove-headers` per API and globally (gateway config CHECK for a global policy chain); compression: CHECK the router config.
**6.4 Parameters at API, gateway and environment level**: show one policy parameterised per API, one gateway-level value in the overlay (for example the key manager list) and one environment-level value in the control plane (environment-specific endpoints). No new build, a guided demo.
**6.5 Log anonymisation, technical vs customer logs**: `pii-masking-regex` on responses; the two log streams (router access log vs controller log) as the separation; anonymise the access log fields through `router.access_logs.json_fields` in gateway config.
**6.6 Syslog / Elasticsearch**: In progress; JSON on stdout proven (`evidence/6.6`). Decide: Fluent Bit DaemonSet with syslog output to a receiver pod for the demo, or slide. `docs/phase3-observability.md`.
**6.7 Custom error policy on a group of APIs**: `respond` policy with a fixed JSON body on the fault flow, attached to several APIs. CHECK how fault-flow policies attach on the Platform Gateway.
**6.8 Custom modules globally and selectively**: the PoD 3 policy attached to one API, then to all through a global chain (CHECK the global attachment mechanism).
**6.9 Upgrade procedure**: `docs/upgrade.md`: operator chart bump in `platform/argocd/*/gateway-operator.yaml`, APIM chart bump in `control-plane.yaml`, order (control plane first, then gateways one region at a time), rollback = Git revert. Mention WSO2 Updates for the APIM image.
**6.10 SQL injection protection and its cost**: Front Door WAF already blocks (403); add `regex-guardrail` on the gateway as the in-gateway option; k6 with and without for the performance impact.
**6.11 Bundled OAuth2 server on selected APIs**: Done (`docs/pod-6.11-jwt.md`, `make test POD=6.11`).
**6.12 JWS signature verification against stored certificates**: CHECK. Not in the catalogue; custom policy or `slide`.

## PoD 7: logs and metrics

**7.1 Metrics and logs per layer**: Done for the gateway (controller, policy engine, runtime pods); control plane metrics not scraped. Optional: enable APIM's Prometheus endpoint and add a ServiceMonitor to complete the "each layer" wording.
**7.2 Grafana and OpenTelemetry**: Done for Grafana. OTel: the gateway can export traces to an OTel collector (`[tracing]` section, seen in WSO2's sample); not deployed, mention on the slide or add the collector if the bank asks.

## PoD 8: gradual migration

**8.1 Move microservices to the new gateway transparently**
- How: add an NGINX pod in `apps` as the "legacy gateway", put it behind Front Door as a second origin group with a route for `/legacy/*`; then move one path at a time to the WSO2 origin group by changing Front Door route patterns (`infra/azure/`). The client URL never changes.
- Proof: k6 running against the same URL during the moves, zero errors; `evidence/8.1/`.

## PoD 10: HA and DR

**10.1 DR approach, backup and restore**: `docs/dr.md` (pod-a-db `pg_dump` to the storage account, restore procedure, rebuild everything from Git); live demo: delete the `wso2-gw` namespace contents in region B, Argo CD rebuilds it, `register.sh` re-registers, redeploy from the Publisher.
**10.2 HA and scaling 4 → 8**: HPA on the region A runtime (`gateway.gatewayRuntime.autoscaling` in the chart), k6 load, watch pods go from 4 to 8 with zero errors in Grafana. Needs the work pool able to hold 8 runtimes: scale the node pool for the drill.

## PoD 11: OWASP API Top 10

**11.1.1 Per-endpoint auth: Basic, OAuth2/JWT (Entra ID), mTLS**: `basic-auth`, `jwt-auth` (done for the Resident KM; Entra ID = second `keymanagers` entry once the app registration exists), `mtls-auth`; attach at operation level to show different rules per endpoint.
**11.1.2 Brute force: rate limit by key/user/token, spike arrest, alerts, SIEM**: `basic-ratelimit` / `advanced-ratelimit` keyed on API key, user claim or token; alert = Prometheus rule on `policy_engine_request_errors_total` (enable `defaultRules`/Alertmanager only if needed) ; SIEM = the stdout JSON logs (6.6).
**11.2.1 Payload size limit**: `content-length-guardrail`.
**11.2.2 JSON threat protection**: `json-schema-guardrail` with a schema that bounds depth, properties, array items and string lengths. CHECK whether a pure depth limit is expressible.
**11.2.3 XML threat protection**: CHECK, nothing in the catalogue. `slide` or custom.
**11.2.4 Rate limits per API/endpoint/operation, parameter caps**: ratelimit policies at API and operation level; parameter caps with `regex-guardrail` / `url-guardrail` on `limit`/`pageSize` (CHECK the override capability; `request-rewrite` may do the override).
**11.3.1 Flow control, bot detection, CAPTCHA**: GAP for the gateway alone; Front Door WAF Bot Manager and rate rules cover bots. Flow control is `slide`.
**11.4.1 SSRF detection**: `url-guardrail` / `regex-guardrail` on the request target or body for `169.254.169.254`, `localhost`, `127.0.0.1`; fallback the PoD 3 policy.
**11.5.1 TLS versions and ciphers**: Front Door TLS policy (minimum TLS 1.2) and the gateway's `router.downstream_tls` settings in gateway config; prove with `openssl s_client` for TLS 1.0/1.1 refused.
**11.5.2 Method filtering, 405**: operations not in the API definition are rejected by the router; prove PUT/DELETE/TRACE on `accounts`. If the code is 404 rather than 405, add a `respond` policy or note it.
**11.5.3 CORS**: `cors` policy, same parameters on several APIs (inheritance = reuse of the same policy config).
**11.5.4 Security headers**: `set-headers` on the response flow (HSTS, X-Content-Type-Options, X-Frame-Options, CSP).
**11.5.5 Content-Type restrictions, 415**: CHECK: `regex-guardrail` on the Content-Type header plus `respond` 415, or note the gap.
**11.5.6 Header transformation**: `remove-headers` (Server, X-Powered-By) plus `set-headers`.
**11.5.7 Error response sanitisation**: `respond` on the fault flow with a standard body (same as 6.7); prove with `x-mock-status: 500` returning a backend stack trace that the client never sees.
**11.6.1 API inventory**: Publisher lists every API with state; shadow/zombie discovery is CHECK (no discovery feature on the Platform Gateway); show the gateway's own API list vs the Publisher.
**11.6.2 Versioning, deprecation, lifecycle**: Publisher lifecycle (Created → Published → Deprecated → Retired) on `accounts` 1.0.0 vs 2.0.0 (from 2.3).
**11.6.3 Usage visibility per consumer / version, unused APIs**: Prometheus `policy_engine_requests_total` by route; per consumer needs APIM analytics or the access log `reqId`/token subject (CHECK which label the policy engine exports).

## PoD 12: data processing model (slides)

12.1 data flows and locations (L0/L1 diagrams, Postgres in A, SQLite on the gateways, logs on stdout), 12.2 JIT access (Azure PIM, Key Vault), 12.3 bank-owned keys and rotation (Key Vault, the gateway AES key Secret from `secrets.sh`, APIM encryption key), 12.4 tenant separation (APIM organisations/tenants, separate gateways per domain as in 2.2).

## PoD 15: evolution and future capabilities (slides + drill recordings)

15.1 central layer across clusters, on-prem, clouds (L0 plus the operator story), 15.2 control/data plane and loss of connectivity (drill D2 recording; include the controller-restart finding and its workaround honestly), 15.3 service mesh split of responsibilities (slide), 15.4 HA, scaling, DR, degraded mode (drills D1, D3, D5, D6 recordings, 10.1 and 10.2 evidence).

## Drills (feed 1.5, 10.x, 15.x)

| ID | Drill | Expected | Notes |
|---|---|---|---|
| D1 | kill region A gateway pods | Front Door shifts to B, a blip | health probe interval decides the blip length |
| D2 | control plane down, then restart runtime pods | traffic continues from the controller's local config | restart runtimes only; a controller restart needs the control plane (finding 2026-11-02) |
| D3 | scale runtimes 4 → 8 | zero errors | needs node capacity |
| D4 | pipeline imports a new API version | appears in both regions | `tests/gate.sh` |
| D5 | NSG blocks region B → control plane | B keeps serving | `make lockdown` style rule |
| D6 | lose region A | B serves; no publishing until A is back | stop the A node pools |

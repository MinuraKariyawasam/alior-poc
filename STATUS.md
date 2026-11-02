# STATUS

States: Not started / In progress / Done / Blocked / Slide. Updated whenever a task changes state (ground rule 8).
Base platform (phases 1 and 2) is up: `make health`, `make gate`, docs/health-check-2026-11-02.md.

| PoD | Item | State | Proof / note |
|---|---|---|---|
| 1.1 | App A calls App B through the gateway inside the cluster | Not started |  |
| 1.2 | Region B gateway routes to the standalone VM | Not started |  |
| 1.3 | WAF rule on Front Door | Done | WAF 403 on injection through Front Door, tests/gate.sh (2026-10-30) |
| 1.6 | HTTPS_PROXY + NO_PROXY on the runtime | Not started |  |
| 2.1 | APIM 4.7 control plane in region A (Helm, `wso2-cp`) | Done | APIM 4.7.0 up in wso2-cp via Argo CD, both gateways registered (docs/phase2-platform.md, 2026-10-30) |
| 2.2 | Dev and prod environments, gateways per environment | Not started |  |
| 2.3 | GUI path and Git path for a new API version and a new gateway | Not started |  |
| 2.4 | RBAC: APIM roles per team + Kubernetes RBAC per namespace | Not started |  |
| 2.5 | Audit: Git history + APIM audit log + Kubernetes audit logs | Not started |  |
| 3.1–3.2 | Go policy reads full request and response bodies, computes MD5, logs it | Not started |  |
| 3.3 | Adds `X-Status` on success **and** on backend communication errors | Not started |  |
| 3.4 | Loads data from an external service at startup, refreshes every 15 min, keeps the last good value on failure. Fallback: a sidecar does the load and refresh, and the policy reads it locally | Not started |  |
| 3.5 | Health reports OUT_OF_SERVICE until the first load succeeds. Fallback: pod readiness probe tied to the sidecar | Not started |  |
| 3.6 | k6 benchmark with and without the policy. Agree the load profile with the bank first | Not started |  |
| 4.1–4.8 | Routes, prefix strip, priority, DNS, 30-second timeout | Not started |  |
| 4.4 | Slide only (bank says implementation not required) | Not started |  |
| 4.9 | Session affinity **(CHECK)** | Not started |  |
| 5.1 | Weighted backends 90/10 | Not started |  |
| 5.2 | Fault injection abort/delay **(CHECK)** | Not started |  |
| 5.3 | Circuit breaking / outlier detection **(CHECK)** | Not started |  |
| 5.4 | Shift 90/10 → 50/50 → 0/100 via Git; request mirroring | Not started |  |
| 6.1 | Per-application public certificate stored and retrieved | Not started |  |
| 6.2 | Client certificate validation via CRL/OCSP | Not started |  |
| 6.3 | Shared policy strips headers (including platform headers) and toggles compression | Not started |  |
| 6.4 | Parameters at API, gateway and environment level | Not started |  |
| 6.5 | Log masking; technical logs separated from customer logs | Not started |  |
| 6.6 | Syslog + Elasticsearch forwarding | In progress | router access log and controller log are JSON on stdout, samples in evidence/6.6 (2026-11-02). Open: Fluent Bit → syslog for the demo, or slide. |
| 6.7 | Custom error policy on a group of APIs | Not started |  |
| 6.8 | Custom policy applied globally and selectively | Not started |  |
| 6.9 | Upgrade procedure documentation | Not started |  |
| 6.10 | SQL injection protection, including the performance impact | Not started |  |
| 6.11 | Bundled OAuth2 server (Key Manager) protecting selected APIs | Done | `make test POD=6.11` PASSED 2026-11-02: accounts-secure 401 without/with a bad token, 200 with a Resident Key Manager token, on both gateways via Front Door; `accounts` stays open. Gateway trust block in gateway-values.yaml, Policy Hub jwt-auth 1.3 on the API. evidence/6.11 |
| 6.12 | JWS signature verification against a stored certificate | Not started |  |
| 7.1 | Dashboards per layer: control plane, gateway controller, runtime, policy engine (start from stock dashboards) | Done | `make test POD=7.1` PASSED 2026-11-02: WSO2's controller, policy engine and overview dashboards in Grafana (A and B) through Front Door, evidence/7.1. Control plane (APIM) metrics not scraped yet. |
| 7.2 | OTel collector in both clusters → Prometheus, Grafana, Loki | Done | reduced with Gihan (2026-11-02) to gateway metrics endpoint → Prometheus → Grafana per cluster; no OTel/Loki. Proof shared with 7.1. |
| 8.1 | Legacy NGINX behind Front Door; move routes one at a time | Not started |  |
| 10.1 | DR runbook `docs/dr.md`: control plane DB backup and restore, rebuild from Git. Live demo: wipe the region B gateway namespace, then rebuild with Argo CD | Not started |  |
| 10.2 | HPA on the region A runtime; scale from 4 to 8 under k6 load, zero errors | Not started |  |
| 11.1.1 | Per-endpoint auth: Basic, OAuth2/JWT with Entra ID (JWKS, issuer, audience, expiry), mTLS | Not started |  |
| 11.1.2 | Rate limit by key, user and token; spike arrest; alerts + SIEM forwarding | Not started |  |
| 11.2.1 | Payload size limit | Not started |  |
| 11.2.4 | Rate limits per API, endpoint and operation; cap `pageSize`/`limit` | Not started |  |
| 11.3.1 | Flow control on the gateway; bot detection and CAPTCHA via the WAF | Not started |  |
| 11.4.1 | Block 169.254.169.254, localhost, 127.0.0.1 | Not started |  |
| 15.1–15.4 | Slides backed by the drill recordings below | Not started |  |

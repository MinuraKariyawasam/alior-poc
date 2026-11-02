# Base platform health check, 2026-11-02

Scope: everything built in phases 1 and 2, checked live. Re-run with `make health` (read-only) and `make gate` (end-to-end API proof).

## Result

| Area | Check | Result |
|---|---|---|
| Azure | pod-a-aks, pod-b-aks | Running / Succeeded, Kubernetes 1.36.4, node pools system B2s + work D4s_v5 (+ wso2cp D4s_v5 in A), all 1 node |
| Azure | pod-a-db (PostgreSQL 16), pod-b-vm (mocks) | VM running, 10.10.17.4 and 10.20.16.4 |
| Azure | Front Door pod-afd | endpoints pod-api, pod-cp, pod-ops-b Enabled; route `all` HttpOnly to the gateway origin group |
| Azure | WAF | `podwaf` (APIs) Prevention, `podwafui` (UIs) Detection |
| Clusters | nodes | all Ready in both clusters |
| Clusters | Argo CD apps | all Synced/Healthy; `cert-manager` shows OutOfSync on CRD annotations only (cosmetic) |
| Clusters | pods | nothing outside Running/Completed in either cluster |
| Clusters | certificates | origin-tls, argocd-server-tls, gateway controller TLS all Ready |
| Gateways | operator 0.11.4, controller, runtime | running in both clusters, runtime LB IPs 74.153.35.38 (A) and 132.220.139.111 (B), `/_gateway-health/ready` 200 |
| Gateways | control plane link | both controllers registered (`isActive: true` in the Admin API), receive `api.deployed` WebSocket events and ack them; no ERROR lines |
| Control plane | APIM 4.7.0 | login page 200; environments Default (Regular) + pod-a-gw, pod-b-gw (APIPlatform); Resident Key Manager enabled; throttling tiers present |
| Control plane | APIs | `accounts 1.0.0` PUBLISHED on both gateways; `accounts-secure 1.0.0` PUBLISHED (test fixture, see below) |
| Control plane | Dev Portal | application `pod-health` created, keys generated, client-credentials token issued by the Resident Key Manager |
| Front Door | gate test | `make gate` PASSED: direct gateway IPs time out, API 200 x4 through Front Door, Publisher + both Argo UIs 200 |
| Front Door | WAF | `?q=1 union select 1` blocked with 403 by `podwaf` |
| Mocks | headers | `x-mock-version: v1` returned through the whole chain |

## Findings that need a decision

### 1. OAuth2 is not enforced on the Platform Gateway yet

`accounts-secure` was published with `securityScheme: oauth2` and a subscription tier, yet the gateway answers 200 with no token, an invalid token and a valid token alike, directly on the runtime and through Front Door.

This is by design in APIM 4.7 for the Platform Gateway, not a fault. The APIM docs for the Platform Gateway state that the model is subscription-less and that access "is governed entirely by the security policies" attached from Policy Hub; subscription validation does not apply. The API's `securityScheme` and tiers only affect the classic gateway.

What is needed to enforce tokens (next build item, suggested for PoD 6.11 / 11.1.2 / 2.x):

1. Gateway-side key manager config. The Policy Hub `jwt-auth` policy (v1.3) reads `systemParameters.keyManagers[]`, each with `name`, optional `issuer`, and `jwks.remote.uri` (plus `skipTlsVerify` or `certificatePath` for the self-signed control plane). Our tokens carry `iss: https://am.wso2.com:443/oauth2/token`; the JWKS is `https://apim-wso2am-all-in-one-am-service.wso2-cp.svc.cluster.local:9443/oauth2/jwks` from region A and `https://10.10.0.6:9443/oauth2/jwks` over the peering from region B (both verified reachable, 200). The exact gateway chart key that carries this block still has to be confirmed in the gateway docs before it goes into `platform/gateway/region-*/gateway-values.yaml`.
2. Attach `jwt-auth` to the API in the Publisher (Develop → Policies) and redeploy the revision. The Publisher loads the catalogue from the public Policy Hub API (`.../policy-hub-api/policy-hub-public/v1.0/policies`, 71 policies). The REST payload the Publisher sends for a hub policy was not captured; attaching through the UI once and reading the API back will give it, after which the gate can do it headlessly.

Policy Hub also offers `api-key-auth`, `basic-auth`, `subscription-validation`, `basic-ratelimit`, `advanced-ratelimit`, `set-headers`, `remove-headers`, `request-rewrite`, `interceptor-service`, `cors`, `backend-jwt`, `opa-policy`. Not in the hub: request mirroring, timeouts, retries, circuit breaking, fault injection, session affinity (plan items 4.9, 5.2, 5.3 stay CHECK).

### 2. APIM is at GA update level

The control plane image is 4.7.0 with no WSO2 Updates applied (`updates/` holds only `product.txt`). Automated gateway registration via `deployment.toml` needs update level 7; we register through the Admin REST API instead, so nothing is blocked today. Policy Hub fixes and Platform Gateway improvements ship as updates, so the image may need rebuilding with updates before phase 5.

### 3. Small items

- `podwafui` is still in Detection; switch to Prevention after one login pass through Publisher and Argo CD.
- The Publisher's 56 built-in operation policies are all `Synapse`/`APK` gateway policies and do not apply to the Platform Gateway.
- `tests/gate.sh` hung once because the `kubectl port-forward` on 19443 failed silently and the readiness loop waits forever; `tests/health.sh` caps its wait at 30 s. Worth the same cap in the gate.
- Test fixtures left in the control plane on purpose: API `accounts-secure 1.0.0` (OAuth2, tier Unlimited) and Dev Portal application `pod-health` with production keys. Reuse them for the JWT enforcement work; delete afterwards.

# Phase 2: platform inside the clusters

Written before building, 2026-10-30. Phase 1 (Azure resources) is done; this page says what goes
into the two clusters, who deploys it, and in what order.

## Two pipelines, not one

| What | Deployed by | How |
|---|---|---|
| The platform: Argo CD apps, APIM 4.7 control plane, gateway operator, gateways, observability, the in-cluster mock pod | **Argo CD** | Helm charts and values files committed to this repo. Argo CD renders and applies them, and reverts manual changes. Nobody runs `helm install` or `kubectl apply` by hand. |
| The APIs and their policies | **APIM 4.7 control plane** | Published in the APIM UI or merged as API definitions under `apis/`. The control plane pushes them to both gateways over WebSocket. Argo CD is not involved. |

Helm stays the packaging format WSO2 ships; Argo CD is the thing that runs it. The one install done by hand is
Argo CD itself, once per cluster, because it cannot install itself. That command is in this repo too.

## Where Argo CD runs

One Argo CD per cluster, namespace `argocd`, on the `work` node pool. Not a single hub in region A, because:

- drills D5 and D6 cut region B off from region A, and region B must stay deployable through them;
- the DR demo (PoD 10.1) rebuilds the region B gateway namespace from Git, which needs Argo CD in region B;
- an on-prem cluster would run its own deployment tooling, which is the story region B tells.

Both instances watch `https://github.com/MinuraKariyawasam/alior-poc`, branch `main`, different paths:

| Cluster | Argo CD app-of-apps path | Deploys |
|---|---|---|
| pod-a-aks | `platform/argocd/region-a/` | control plane (`wso2-cp`), gateway operator + gateway (`wso2-gw`), Prometheus/Grafana/Loki + OTel (`observability`), mock pod (`apps`) |
| pod-b-aks | `platform/argocd/region-b/` | gateway operator + gateway (`wso2-gw`), OTel collector (`observability`), mock pod (`apps`) |

Pinned versions (ground rule 4):

| Component | Chart | Version | App version | Source |
|---|---|---|---|---|
| Argo CD | `argo-cd` from https://argoproj.github.io/argo-helm | 10.11.6 | v3.5.6 | chart index, published 2026-10-26 |
| APIM 4.7 | `wso2/helm-apim`, branch 4.7.x, all-in-one | 4.7.0-5 | 4.7.0 | Chart.yaml on the branch, 2026-10-30 |
| Gateway operator | `oci://ghcr.io/wso2/api-platform/helm-charts/gateway-operator` | 0.11.4 | 0.11.1 | ghcr tags, 2026-10-30 |
| API Platform Gateway | pulled by the operator from `oci://ghcr.io/wso2/api-platform/helm-charts/gateway` | 1.2.5 (pinned by the operator chart) | | |
| cert-manager | `oci://quay.io/jetstack/charts/cert-manager` | v1.19.1 | v1.19.1 | operator quick start |

APIM and gateway versions are read from the official charts when the values files are written, never guessed (ground rule 1).

## Namespaces and placement

| Namespace | Cluster | Node pool | Contents |
|---|---|---|---|
| `argocd` | both | work | Argo CD |
| `wso2-cp` | A only | wso2cp (tainted, toleration on the APIM pod) | APIM 4.7 control plane, DB on `pod-a-db` |
| `wso2-gw` | both | work | gateway operator, gateway controller (SQLite PVC) + router |
| `observability` | both | work | A: Prometheus, Grafana, Loki, OTel collector. B: OTel collector shipping to A |
| `apps` | both | work | one small mock pod (`mocks/mock.py`) for PoD 1.1 only |

Backends for everything else are on `pod-b-vm` (10.20.16.4), see `mocks/README.md`.

## Secrets

Key Vault `pod-kv-alior` through the Secrets Store CSI driver (AKS add-on `azure-keyvault-secrets-provider`).
Secrets needed: `pod-a-db-apim` (exists), the gateway-to-control-plane token, the ACR pull token for mirrored
WSO2 images. Values files reference the Kubernetes Secret the CSI driver creates; no secret text in Git.

## Build order

Each step: write files, check locally (`helm template` renders, `kubectl --dry-run=server` where possible),
commit, push, then apply (ground rule 12).

1. `platform/argocd/`: pinned Argo CD values, bootstrap script per cluster (`helm install` by hand, then the app-of-apps `Application`). Apply to A, then B. **Done 2026-10-30** on both clusters; app-of-apps and `namespaces` Synced/Healthy. Note: the Free-tier API servers answer slowly at times (TLS handshake timeouts); retry rather than assume failure, and move to the Standard tier (73 USD/month per cluster) if it keeps interfering with demos.
2. Enable the Key Vault CSI add-on on both clusters; CSI `SecretProviderClass` manifests under `platform/secrets/`. **Done 2026-10-30**: add-on enabled, add-on identities have Key Vault Secrets User, `apim-secrets` provider class synced by Argo CD.
3. Mirror APIM and gateway images into `podacralior`; record digests. **Done 2026-10-30** for APIM: `podacralior.azurecr.io/wso2am:4.7.0-pg1` (public 4.7.0 + PostgreSQL JDBC 42.7.7, `platform/control-plane/image`). Gateway images are pulled from ghcr by the operator; mirror later if ghcr access becomes a concern.
4. `platform/control-plane/`: APIM 4.7 values for region A, DB pointed at `pod-a-db`, node selector `wso2cp` (taint removed: the chart has no tolerations). Argo CD syncs it as a multi-source app from the official chart. **Done 2026-10-30**: schema loaded, app synced, APIM up (fixes: `kubernetes.gatewayAPI.enabled: false`, truststore password). Portals via `kubectl port-forward svc/apim-wso2am-all-in-one-am-service -n wso2-cp 9443:9443`, hostname `am.wso2.com` in /etc/hosts.
5. `platform/gateway/region-a/` and `region-b/`: gateway operator 0.11.4 (Argo app `gateway-operator`, installed), cert-manager v1.19.1 (installed), AES key Secrets (`secrets.sh`, done), `APIGateway` CRs + value overlays (pushed), registration (`register.sh`, done), `gateway` Argo apps (done). **Both gateways Ready and connected 2026-10-30.** Overlay fixes needed on operator 0.11.4: absolute SQLite path, control plane host/token via the chart keys, `fsGroup: 10001`, `Recreate` strategy.
6. `platform/observability/`: collector in both, stack in A.
7. `infra/azure/frontdoor.sh`: Front Door Premium + WAF with both gateway public IPs as origins. Only now, because it bills from creation. **Done 2026-10-30**: profile `pod-afd`, endpoint `https://pod-api-guf3bbbjh5htgxfu.a02.azurefd.net`, origins 74.153.35.38 (A) and 132.220.139.111 (B) with the registered vhost as Host header, HTTPS-only route, WAF `podwaf` with OWASP DRS 2.1 + Bot Manager 1.1 in prevention mode. Billing started today.
8. Gate: an API published in the control plane answers through Front Door from both regions. Then phase 3. **2026-10-30**: `tests/gate.sh` publishes `accounts` (from `apis/accounts/openapi.yaml`) to both gateways; both answer 200 directly. **Gate passed 2026-10-30**: 200 from both gateways directly and through Front Door (`https://pod-api-guf3bbbjh5htgxfu.a02.azurefd.net/accounts/1.0.0/accounts`), WAF blocks an injection payload with 403 (PoD 1.3), HTTP redirects to HTTPS with 307. Front Door forwards to the gateways over HTTP 8080 inside Azure (decision, see CLAUDE.md); its config changes took 30 to 45 minutes to propagate. Phase 3 can start.

## What the bank sees in PoD 2.3

- UI path: publish an API in the APIM portal, call it through Front Door, both regions answer.
- Git path (drill D4): merge a pull request that adds an API version under `apis/`; CI validates it, the control
  plane picks it up, both gateways serve it. Argo CD shows the platform in sync; Git history is the audit trail (PoD 2.5).

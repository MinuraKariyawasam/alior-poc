# CLAUDE.md: WSO2 API Platform PoD (bank, Poland)

You are helping build a Proof of Delivery (PoD) environment for a bank evaluating
WSO2 against IBM API Connect. The full plan, task list and PoD item mapping live in
`IMPLEMENTATION_PLAN.md`. Read it before starting any task.

## What we are building (L0)

- **Two Azure AKS clusters in two regions.**
  - Region A is "cloud". It runs the WSO2 API Platform Gateway and the single WSO2 API Manager 4.7 control plane.
  - Region B is the "on-prem stand-in". It runs the WSO2 API Platform Gateway only, plus a small standalone Azure VM backend (PoD 1.2).
- **Azure Front Door + WAF** in front of both gateways (active-active).
- **One control plane.** It pushes APIs and policies to both gateways over WebSocket. There is no standby control plane.
- **GitOps:** Git → CI → Argo CD → gateway operator custom resources in both clusters.
- **Observability:** OpenTelemetry → Prometheus/Grafana, Loki/Elasticsearch, syslog/SIEM.
- AI Gateway (PoD 13, 14) and Open Banking (PoD 9) use **existing demo environments**. They are out of scope for this repo.

Lucid L0 diagram: https://lucid.app/lucidchart/18d92842-bd20-49f0-b111-1bcbea0e0d8e/edit

## Azure environment (fixed, don't change)

| Item | Value |
|---|---|
| Cloud | **Azure** (AKS). Not AWS/EKS. |
| Subscription | `presales-001` (shared WSO2 presales subscription) |
| Resource group | `rg-Alior-POC-minura`. **All resources go here. Never create resource groups.** |
| Access | Owner on the resource group; Contributor on the subscription |
| Regions | Region A: `polandcentral`, Region B: `westeurope` (both subject to the quota check; swap Region B if quota is short) |
| Access expiry | Access is revoked on the "Last Day of Use": `<FILL IN DATE>`. Run the teardown in `docs/cluster-spec.md` before it. |
| Tooling | **Azure CLI scripts** for Azure resources (no Terraform, decided 2026-10-30; build order and commands in `docs/cluster-spec.md`), **Helm** (applied by Argo CD) for everything in the clusters. Ansible is out of scope. |

What the access allows, and what it doesn't:

- Owner on the resource group lets you create resources and assign roles inside it, for example AcrPull for the AKS kubelet identity and Network Contributor on subnets.
- Contributor on the subscription lets AKS create its own `MC_*` node resource group.
- It does **not** cover Entra ID app registrations, which are needed for PoD 11.1.1. Those are requested from the WSO2 Digital team. Never try to create them from scripts.

Required tags on **every** Azure resource:

```
--tags project=alior-poc owner=minura@wso2.com expiry=<FILL IN DATE> env=pod
```

There is no Terraform state. The approved sizing, prices and `az` build commands live in `docs/cluster-spec.md`; the cost approval is https://claude.ai/artifact/WGZiDnfUkxs5gF1Qtgg1MJ.

## Confirmed decisions (2026-10-30)

- No Terraform. Azure resources are built by hand with the `az` commands in `docs/cluster-spec.md`.
- Node floor: B2s system nodes; region A two D4s_v5 (one tainted `wso2cp=true:NoSchedule` for APIM), region B one D4s_v5. The 4 CPU size is driven by APIM's 2 CPU Helm request.
- Gateway controllers keep the chart's in-cluster SQLite. Only APIM gets PostgreSQL: PostgreSQL 16 on `pod-a-db`, a B1ms VM in region A, because Azure Database for PostgreSQL Flexible Server refuses every SKU in polandcentral on this subscription (verified 2026-10-30). External Postgres for controllers was considered and declined.
- Front Door Premium stays, because PoD 1.3 needs its managed WAF rules.
- Cost: 1,123 USD/month running, 534 idle, two-month ceiling 2,250 USD. Idle means the worker pools are scaled to zero by hand on days with no build work or demo; nothing is deleted.
- GitOps (decided 2026-10-30, see `docs/phase2-platform.md`): one Argo CD per cluster in `argocd`, each watching this repo on `main`. Argo CD deploys the platform from Helm charts; the APIM control plane deploys the APIs. Argo CD itself is the only hand-run Helm install. Pinned: argo-cd chart 10.11.6 (app v3.5.6).
- Gateways (decided 2026-10-30): deployed by the WSO2 gateway operator (chart gateway-operator 0.11.4, which pins gateway chart 1.2.5), one `APIGateway` CR per cluster in `wso2-gw`, with cert-manager v1.19.1 as its listener-TLS prerequisite. The operator needs an AES-256 key Secret per gateway namespace (`platform/gateway/secrets.sh`, key kept in Key Vault) and a control plane token Secret (`platform/gateway/register.sh`).
- Front Door to gateways (decided 2026-10-30): plain HTTP on 8080 inside Azure, TLS and WAF terminate at Front Door, because Front Door rejects the gateways' self-signed certificates. Switch the route to HttpsOnly once the gateways carry CA-issued certificates.
- API deployment approach (confirmed with Gihan Anuruddha on 2026-10-30): top-down. The gateway operator deploys the gateway runtimes from `APIGateway` CRs (via Argo CD); the APIM control plane deploys APIs to the registered gateways, so APIs live in the control plane database. No bottom-up `RestAPI` CRs are applied to the clusters; `apis/` holds OpenAPI files that are imported into the Publisher.
- Exposure (done 2026-10-30): every UI and API goes through Front Door (`docs/phase2-platform.md`, "Exposure through Front Door"); the gateway and ingress IPs are locked to the `AzureFrontDoor.Backend` service tag by `make lockdown`. Direct cluster IPs are not reachable from the Internet, by design.
- Reviewed with Gihan Anuruddha on 2026-10-30 and confirmed as is. No HA for the control plane or the gateway controller: one APIM instance, one controller replica per region, AKS Free tier, Postgres without the HA option. Mock backends run on `pod-b-vm` (10.20.16.4) as three systemd services from `mocks/mock.py`: v1 :8081, v2 :8082, legacy :8083 (decided 2026-10-30 after Gihan's suggestion). Both gateways route there; one tiny in-cluster mock per cluster remains only for PoD 1.1. Region A calls cross the peering (about 25 ms), which the PoD 3.6 write-up should mention. Cheaper node options (2 CPU region B worker, APIM request override, burstable APIM node, Front Door Standard) were offered and not taken.

## Ground rules

1. **Never guess WSO2 product details.** CRD schemas, Helm values, policy names and config keys for the API Platform Gateway and APIM 4.7 must come from official docs (wso2.com/api-platform/docs, apim.docs.wso2.com) or the `wso2/api-platform` GitHub repo. If you can't verify something, stop and say so.
2. **Policy catalogue gaps are not ours to hack around.** If a PoD item needs a policy that isn't in the catalogue (items are flagged "CHECK" in the plan), report it and mark the item `slide` in `STATUS.md`. Don't build custom workarounds unless the plan explicitly says so (section 3 custom policy, 11.4 SSRF).
3. **No secrets in Git.** Use Azure Key Vault and the CSI driver or External Secrets. Commit `.example` files only.
4. **Pin every version:** Kubernetes version, Helm charts, container images, Go modules. No `latest`.
5. **Everything is declarative and rebuildable.** The definition of done for the platform is one run of the `az` build in `docs/cluster-spec.md` plus one Argo CD sync from an empty resource group.
6. **Every PoD item gets proof.** That means a script under `tests/` that demonstrates it, plus a screenshot or log saved to `evidence/<PoD-ID>/`.
7. **Small, reviewable changes.** One PoD item or one infra component per commit. Use conventional commit messages, for example `feat(pod-4.7): route priority for /transfers/instant`.
8. **Update `STATUS.md`** whenever a task changes state (Not started / In progress / Done / Blocked / Slide).
9. **Stay inside `rg-Alior-POC-minura`.** No new resource groups, no subscription-level resources other than what AKS creates itself.
10. **Check quota before creating compute.** Run `az vm list-usage --location <region>` for both regions and report the figures before any AKS or VM apply.
11. **Keep it cheap.** It's a shared presales subscription, so use the smallest SKUs that work and scale node pools to zero when idle. The cleanup target is `make destroy`.
12. **Build locally, commit, push, then apply.** Every script, manifest or mock is checked locally first, committed and pushed to https://github.com/MinuraKariyawasam/alior-poc, and only then run against Azure or the clusters. Nothing is applied from an uncommitted file.

## Repo layout

```
infra/azure/              # az CLI build scripts: network, AKS x2, Front Door + WAF, Postgres, VM, Key Vault, ACR
platform/argocd/          # Argo CD app-of-apps, one app per component
platform/control-plane/   # APIM 4.7 Helm values (region A only)
platform/gateway/         # API Platform Gateway operator + gateway CRs per region
  region-a/
  region-b/
platform/observability/   # OTel collector, Prometheus, Grafana dashboards, Loki
apis/                     # API definitions + routes (GitOps source for PoD 2.3)
policies/custom-security/ # Go custom policy for PoD 3 (Gateway Builder)
mocks/                    # mock microservices v1/v2, legacy NGINX, standalone VM API
tests/                    # one script per PoD item: tests/pod-4.7.sh etc.
  k6/                     # load profiles for drills and benchmarks
drills/                   # failure drill runbooks + scripts (D1-D6)
evidence/                 # screenshots/logs per PoD ID (git-lfs if large)
docs/                     # runbooks, DR, upgrade procedure (PoD 6.9, 10.1)
STATUS.md                 # live status per PoD ID
```

## Conventions

- **Azure naming:** `pod-<region>-<resource>`, for example `pod-a-aks`, `pod-b-aks`, `pod-afd`.
- **Kubernetes namespaces:** `wso2-cp` (control plane, region A only), `wso2-gw`, `apps`, `observability`, `argocd`.
- **Mock API paths:** `/transfers`, `/transfers/instant`, `/accounts`, `/legacy/accounts` (VM).
- **Mock behaviour headers:** `x-mock-delay-ms` and `x-mock-status` control latency and errors in the mocks. Responses carry `x-mock-version` and a JSON body with version, path, method, host, port and body MD5.
- **Tests** exit non-zero on failure and print the exact proof (status codes, headers, timings).

## Commands (fill in as the repo grows)

```
make infra                       # infra/azure/build.sh, rerunnable
make idle / make resume          # worker pools to 0 / back to 1
make argocd-sync                 # platform
make test POD=4.7                # run one PoD proof
make drill D=2                   # run a failure drill
make evidence                    # collect screenshots/logs into evidence/
make quota                       # vCPU quota check for both regions
make destroy                     # full teardown before access expiry
```

## First session

1. Read `IMPLEMENTATION_PLAN.md`.
2. Create the repo skeleton and `STATUS.md`, with every in-scope PoD ID set to Not started.
3. Run the quota check for both regions and report back.
4. Confirm the approved spec in `docs/cluster-spec.md` (done 2026-10-30).
5. Build networking, then the region A AKS cluster, with the `az` commands from that file.

## When unsure

Ask before you:

- change the architecture (cluster count, control plane placement, Front Door);
- add a component not in the plan;
- spend more than an hour on an item marked CHECK or GAP.

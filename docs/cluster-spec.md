# PoD cluster spec and pricing (manual build, no Terraform)

Prices: Azure retail pay-as-you-go, USD, pulled from the Azure Retail Prices API on 2026-10-29.
Monthly figures assume 730 h. Quota checked the same day: 0 of 350 vCPUs used in both regions.

Everything goes in `rg-Alior-POC-minura`, subscription `presales-001`. No new resource groups.

Sizing is derived from WSO2's published chart defaults (checked 2026-10-29):

- APIM 4.7 all-in-one Helm chart (`wso2/helm-apim`, branch 4.7.x): requests 2 CPU / 2 GiB, limits 3 CPU / 3 GiB.
- API Platform Gateway chart (`wso2/api-platform`, `kubernetes/helm/gateway-helm-chart`): one controller + one router replica, no resource requests set, controller state in SQLite on a PVC by default; `gateway.config.controller.storage.type: postgres` switches to an external PostgreSQL, which is required for more than one controller replica. Decision 2026-10-30: keep SQLite in-cluster for the PoD; Postgres was considered and declined.
- Gateway operator: requests 10m CPU / 64 MiB.

## 1. What to create

| Resource | Region | SKU / size | Count | Purpose |
|---|---|---|---|---|
| `pod-a-aks` | polandcentral | AKS Free tier, k8s 1.36 | 1 | Region A: gateway + APIM 4.7 control plane |
| `pod-a-aks` system pool | polandcentral | Standard_B2s (2 vCPU, 4 GB, burstable) | 1 | CoreDNS, metrics, CSI drivers |
| `pod-a-aks` wso2cp pool | polandcentral | Standard_D4s_v5 (4 vCPU, 16 GB) | 1 | APIM 4.7 control plane only (tainted) |
| `pod-a-aks` work pool | polandcentral | Standard_D4s_v5 | 1, autoscale to 3 | gateway, mocks, Argo CD, Prometheus/Grafana/Loki |
| `pod-b-aks` | westeurope | AKS Free tier, k8s 1.36 | 1 | Region B: gateway only (on-prem stand-in) |
| `pod-b-aks` system pool | westeurope | Standard_B2s | 1 | |
| `pod-b-aks` work pool | westeurope | Standard_D4s_v5 | 1, autoscale to 2 | gateway, mocks, Argo CD, OTel collector |
| `pod-a-db` | polandcentral | Standard_B1ms VM (1 vCPU, 2 GB), 30 GB disk, PostgreSQL 16 | 1 | APIM 4.7 control plane DB (`apim`), nightly pg_dump to /var/backups/pg. Azure Flexible Server refused every SKU in polandcentral on this subscription (2026-10-30) |
| `pod-b-vm` | westeurope | Standard_B1ms (1 vCPU, 2 GB), 30 GB disk, private IP 10.20.16.4 | 1 | all mock backends (`mocks/mock.py`, stdlib Python): mock-v1 :8081, mock-v2 :8082, mock-legacy :8083. Both gateways route here; region B in-region (PoD 1.2), region A over the peering. One tiny in-cluster mock per cluster stays for PoD 1.1 |
| `pod-afd` | global | Front Door Premium + WAF policy | 1 | active-active entry, managed WAF rules (PoD 1.3) |
| `podacr` | polandcentral | ACR Basic | 1 | mirrored WSO2 images |
| `pod-kv` | polandcentral | Key Vault Standard | 1 | secrets via CSI driver |
| `podstate` | polandcentral | Storage account LRS | 1 | evidence, k6 results |

vCPU use: region A 10, region B 6. Both far under the 350 quota.

Why this is the floor, not lower:

- APIM's 2 CPU request plus the gateway, Argo CD and the observability stack will not schedule on a single 4 vCPU node, so region A needs two workers. Keeping APIM on its own tainted node also keeps the control plane isolation story from the plan.
- Region B runs a gateway, mocks and collectors only. One 4 vCPU node holds that with room for the HPA drill (D3) to scale router pods.
- Gateway controllers use the chart's SQLite default on a 100 MiB PVC, so no Postgres for them. The APIM database runs on `pod-a-db`, a B1ms VM in region A, because Azure Database for PostgreSQL Flexible Server returned SkuNotAvailable for Burstable and GeneralPurpose SKUs in polandcentral on this subscription; a VM next to APIM keeps the DB in-region and costs the same as the managed B1ms would have. This means one controller replica per region; the router keeps serving from its last config if the controller is down (drill D2). Switch `gateway.config.controller.storage.type` to `postgres` (about $20/month for two B1ms) if the bank asks for a multi-replica controller.

What is given up versus the full spec: no dedicated gateway nodes (mocks and observability share the node, so the PoD 3.6 latency benchmark should be run with the observability stack scaled down), one worker in region B, and a 1 vCPU APIM database.

## 2. Monthly cost, running 24x7

| Item | Unit price | Qty | USD/month |
|---|---|---|---|
| Region A nodes: 1 x B2s | $0.048/h | 1 | 35 |
| Region A nodes: 2 x D4s_v5 | $0.230/h | 2 | 336 |
| Region B nodes: 1 x B2s | $0.048/h | 1 | 35 |
| Region B nodes: 1 x D4s_v5 | $0.230/h | 1 | 168 |
| Node OS disks: P10 128 GB Premium SSD | $21.68/mo | 5 | 108 |
| AKS control plane (Free tier) | $0 | 2 | 0 |
| Standard load balancer + public IP | approx $22/mo | 2 | 44 |
| `pod-a-db` B1ms VM + 30 GB disk (PostgreSQL for APIM) | $0.024/h | 1 | 20 |
| `pod-b-vm` B1ms + 30 GB disk | $0.024/h | 1 | 20 |
| Front Door Premium base | $330/mo | 1 | 330 |
| Front Door requests + egress (PoC volume) | approx | | 10 |
| ACR Basic, Key Vault, storage account | approx | | 7 |
| Inter-region egress (CP to GW websocket, k6) | approx | | 10 |
| **Total** | | | **approx 1,125** |

Per day: about $37.

## 3. Monthly cost, idle (work and wso2cp pools scaled to 0)

| Item | USD/month |
|---|---|
| 2 system nodes + their disks | 113 |
| Front Door Premium | 330 |
| `pod-a-db` VM (PostgreSQL) | 20 |
| Load balancers, VM, ACR, KV, storage | 71 |
| **Total** | **approx 535** |

Per day: about $18. Front Door is the big fixed cost. Delete `pod-afd` between demo days
if the PoC runs for months; recreating it takes 15 minutes.

## 4. Cheaper options, if needed

- Ephemeral OS disks on the Dsv5 nodes remove the $108/month disk line. Needs
  `--node-osdisk-type Ephemeral --node-osdisk-size 100` on D4s_v5 (bounded by the VM cache size).
  Skipped by default to avoid a sizing gotcha on manual builds.
- Front Door Standard is $35/month but has no managed WAF rulesets, so PoD 1.3 would not
  pass. Premium stays.
- AKS Standard tier ($73/month per cluster) only adds the uptime SLA. Not needed for a PoC.

## 5. Build commands

The build is scripted, rerunnable, and skips what already exists:

```bash
make infra     # infra/azure/build.sh: network, ACR, Key Vault, storage, AKS x2, node pools, pod-a-db (PostgreSQL), pod-b-vm
make idle      # worker pools to 0
make resume    # worker pools back to 1
make destroy   # delete everything in the resource group
```

Front Door is created separately once both gateways have public IPs (`infra/azure/frontdoor.sh`, to be added in phase 2).
Settings, including the `EXPIRY` tag, live in `infra/azure/env.sh`.

## 6. Review notes (Gihan Anuruddha, 2026-10-30)

Spec confirmed as is. Questions raised and the answers given:

| Question | Answer | Outcome |
|---|---|---|
| Put the sample backend on one or two VMs behind a load balancer, shared by both clusters? (Done 2026-10-30: all mocks run on `pod-b-vm`, three ports.) | Workable, and `pod-b-vm` can host it at no extra cost. It does not shrink the cluster nodes, which are sized for the gateway, Argo CD and observability, not the mocks. PoD 1.1 needs one in-cluster service for the east-west call, and drills D5/D6 need region B to keep serving without region A. | Mocks stay in each cluster; `pod-b-vm` covers the shared-backend case. |
| Do we need 4 CPU nodes? Is it Kubernetes? | No. APIM 4.7's Helm chart requests 2 CPU for the control plane pod, which does not fit on a 2 CPU node after system daemons. Only the APIM node needs 4 CPU for that reason. | Kept 4 CPU, 16 GB on all three workers for a stock configuration. |
| Can hardware go lower, since the gateway is small? | Yes: region B worker to D2s_v5 (saves 84 USD/month), APIM CPU request overridden to 1 so it fits a D2s_v5 (84), burstable B4as_v2 for the APIM node (42), Front Door Standard instead of Premium (295, loses managed WAF rules for PoD 1.3 and bot protection for 11.3.1). | Not taken. Running cost stays 1,123 USD/month. |
| HA for the control plane and gateway controller? | Not needed for the PoD. One APIM instance (DR by backup/restore, PoD 10.1); one controller replica per region on SQLite, router keeps serving if the controller is down (drill D2). | Confirmed. No change. |

## 7. Teardown before access expiry

```bash
az resource list -g rg-Alior-POC-minura --query "[].id" -o tsv | xargs -n1 az resource delete --ids
```

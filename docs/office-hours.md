# Office hours: the whole PoD runs 09:00 to 17:00 Mon-Fri, off at nights and weekends (decided 2026-11-04)

Reason: cost. The shared presales subscription pays for two AKS clusters and two VMs only while they run.

## What is stopped and what keeps billing

| Stopped at 17:00 | Keeps running (idle cost) |
|---|---|
| `pod-a-aks` and `pod-b-aks`: control plane and every node pool (`az aks stop`) | Front Door Premium + WAF (fixed fee), Key Vault, ACR, the public IPs, the managed disks (gateway SQLite PVCs, VM OS disks, Postgres data) |
| `pod-a-db` (PostgreSQL VM) and `pod-b-vm` (mock backends): deallocated | Log Analytics if any, the storage account |

Everything is state on disk, nothing is deleted. Start order matters: VMs first (APIM needs Postgres), then the clusters;
stop order is the reverse. AKS Free tier allows stop/start; the gateway and ingress public IPs are standard static IPs and
survive a stop, so Front Door's origins stay valid.

## How it runs

| Piece | Where |
|---|---|
| Schedule | Azure Automation account `pod-automation` (polandcentral, in the resource group), system-assigned identity with Contributor on the resource group. Schedules `pod-start` 09:00 and `pod-stop` 17:00, Monday to Friday, time zone `Asia/Colombo` (Minura's laptop time; change `TZ_NAME` in `infra/azure/schedule.sh` and rerun `make schedule` to move it, for example to `Europe/Warsaw` for demo weeks). |
| Runbook | `infra/azure/runbooks/pod-power.ps1`: PowerShell 5.1, no modules, takes a token from the sandbox identity endpoint and calls ARM REST (`managedClusters/{name}/stop|start`, `virtualMachines/{name}/deallocate|start`). Note the `${var}?api-version` braces: PowerShell treats `?` as part of a variable name. |
| Manual | `make stop`, `make start`, `make power-status` (`infra/azure/power.sh`, same order). `make idle` / `make resume` remain the lighter option (worker pools to zero, control plane up). |
| Rerun / change | `make schedule` is idempotent: it updates the account, republishes the runbook and rewrites both schedules. |

After a start, pods take a few minutes: Argo CD re-syncs, the gateway controllers reconnect to the control plane, Front
Door marks the origins healthy again. `make health` is the check. A demo outside office hours needs `make start` first
(about 10 minutes to green) and the next scheduled stop will still fire at 17:00; run `make stop` yourself afterwards if
the demo is on a weekend.

## Verified 2026-11-04

- Stop through Automation (same runbook the schedule calls): four 202s, both clusters Stopped and both VMs deallocated within about 4 minutes.
- Start through Automation, run 40 seconds after the stop for the test: VMs and region A started, region B answered 409 "in-progress stop operation" because its stop had not finished. The runbook now retries a busy resource every 60 s for up to 15 minutes and reports per-resource failures at the end; in the real schedule there are 16 hours between stop and start. Region B was started by hand (`make start`); once both clusters reported provisioning Succeeded, `make gate` passed (API and all three UIs 200 through Front Door). `make health` needs the cluster API servers and the laptop network to be calm; a run during the start showed transient failures only.
- First scheduled runs: start 2026-11-05 09:00, stop 2026-11-05 17:00 (Asia/Colombo). Check the first morning with `make power-status` and `make health`.

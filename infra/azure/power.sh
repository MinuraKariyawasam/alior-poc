#!/usr/bin/env bash
# power.sh stop  -> stop both AKS clusters (control plane + all node pools) and deallocate pod-a-db and pod-b-vm
# power.sh start -> start the VMs first (APIM needs Postgres), then both clusters
# Manual counterpart of the Automation runbooks in runbooks/ (same order). Front Door, Key Vault, ACR, disks and
# public IPs keep running; they are the idle cost. Rerunnable: already-stopped/started resources are skipped by Azure.
set -euo pipefail
cd "$(dirname "$0")" && source ./env.sh
case "${1:-}" in
  stop)
    for c in pod-a-aks pod-b-aks; do az aks stop -g "$RG" -n "$c" --no-wait -o none && echo "$c stopping"; done
    for v in pod-a-db pod-b-vm; do az vm deallocate -g "$RG" -n "$v" --no-wait -o none && echo "$v deallocating"; done
    ;;
  start)
    for v in pod-a-db pod-b-vm; do az vm start -g "$RG" -n "$v" --no-wait -o none && echo "$v starting"; done
    for c in pod-a-aks pod-b-aks; do az aks start -g "$RG" -n "$c" --no-wait -o none && echo "$c starting"; done
    ;;
  status)
    for c in pod-a-aks pod-b-aks; do printf '%-10s %s\n' "$c" "$(az aks show -g "$RG" -n "$c" --query powerState.code -o tsv --only-show-errors)"; done
    for v in pod-a-db pod-b-vm; do printf '%-10s %s\n' "$v" "$(az vm get-instance-view -g "$RG" -n "$v" --query "instanceView.statuses[?starts_with(code,'PowerState')].displayStatus" -o tsv)"; done
    ;;
  *) echo "usage: power.sh stop|start|status"; exit 1;;
esac

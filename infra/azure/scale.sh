#!/usr/bin/env bash
# scale.sh idle   -> worker pools to 0 (system nodes, Postgres, VM, Front Door keep running)
# scale.sh resume -> worker pools back to 1
set -euo pipefail
cd "$(dirname "$0")" && source ./env.sh
n=$([ "${1:-}" = idle ] && echo 0 || echo 1)
for c in pod-a-aks pod-b-aks; do
  for p in $(az aks nodepool list -g $RG --cluster-name $c --query "[?name!='system'].name" -o tsv); do
    az aks nodepool scale -g $RG --cluster-name $c -n $p --node-count $n -o none && echo "$c/$p -> $n"
  done
done

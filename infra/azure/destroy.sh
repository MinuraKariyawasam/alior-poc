#!/usr/bin/env bash
# Deletes everything in the resource group (not the group itself). Irreversible.
set -euo pipefail
cd "$(dirname "$0")" && source ./env.sh
read -r -p "Delete ALL resources in $RG? type the group name to confirm: " ans; [ "$ans" = "$RG" ] || exit 1
az aks delete -g $RG -n pod-a-aks --yes --no-wait 2>/dev/null || true
az aks delete -g $RG -n pod-b-aks --yes --no-wait 2>/dev/null || true
az resource list -g $RG --query "[?type!='Microsoft.ContainerService/managedClusters'].id" -o tsv | xargs -n1 -I{} az resource delete --ids {} 2>/dev/null || true
az resource list -g $RG -o table

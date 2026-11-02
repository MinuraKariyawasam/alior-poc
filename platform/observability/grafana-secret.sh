#!/usr/bin/env bash
# Grafana admin password: generated once into Key Vault, copied into Secret grafana-admin (observability) in both clusters.
# Run before the monitoring app syncs for the first time; rerunnable.
set -euo pipefail; cd "$(dirname "$0")/../.."; source infra/azure/env.sh
az keyvault secret show --vault-name "$KV" -n grafana-admin-password -o none 2>/dev/null \
  || az keyvault secret set --vault-name "$KV" -n grafana-admin-password --value "$(openssl rand -base64 24 | tr -d '/+=')" -o none
PW=$(az keyvault secret show --vault-name "$KV" -n grafana-admin-password --query value -o tsv)
for ctx in pod-a-aks pod-b-aks; do
  kubectl --context "$ctx" -n observability create secret generic grafana-admin \
    --from-literal=admin-user=admin --from-literal=admin-password="$PW" --dry-run=client -o yaml | kubectl --context "$ctx" apply -f -
done

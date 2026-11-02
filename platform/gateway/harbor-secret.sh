#!/usr/bin/env bash
# Pull credentials for the fixed gateway release served from WSO2's Harbor (registry.wso2.com, project wso2-api-platform/sts).
# Creates in wso2-gw of both clusters: Secret harbor-registry (username/password, read by the operator to pull the chart)
# and Secret harbor-pull (docker-registry type, used as imagePullSecrets by the gateway pods). CLI secret lives in Key Vault
# as harbor-cli-secret; rerunnable.
set -euo pipefail; cd "$(dirname "$0")/../.."; source infra/azure/env.sh
USER=minura@wso2.com
PW=$(az keyvault secret show --vault-name "$KV" -n harbor-cli-secret --query value -o tsv)
for ctx in pod-a-aks pod-b-aks; do
  kubectl --context "$ctx" -n wso2-gw create secret generic harbor-registry --from-literal=username="$USER" --from-literal=password="$PW" --dry-run=client -o yaml | kubectl --context "$ctx" apply -f -
  kubectl --context "$ctx" -n wso2-gw create secret docker-registry harbor-pull --docker-server=registry.wso2.com --docker-username="$USER" --docker-password="$PW" --dry-run=client -o yaml | kubectl --context "$ctx" apply -f -
done

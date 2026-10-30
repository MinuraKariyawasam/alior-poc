#!/usr/bin/env bash
# secrets.sh <a|b>  — creates the two Secrets the gateway operator needs in wso2-gw of pod-<r>-aks:
#   gateway-encryption-keys  AES-256 key file default-aesgcm256-v1.bin (mandatory, fail-closed; never rotate casually)
#   gateway-cp-token         control plane registration token (see register.sh)
# The key is generated once and kept in Key Vault (gw-aes-<r>) so a rebuilt cluster gets the same key.
set -euo pipefail
r=${1:?a or b}; ctx=pod-$r-aks; cd "$(dirname "$0")/../../infra/azure" && source ./env.sh
if ! az keyvault secret show --vault-name $KV -n gw-aes-$r -o none 2>/dev/null; then
  az keyvault secret set --vault-name $KV -n gw-aes-$r --value "$(head -c 32 /dev/urandom | base64)" -o none
  echo "generated gw-aes-$r in Key Vault"
fi
az keyvault secret show --vault-name $KV -n gw-aes-$r --query value -o tsv | base64 -d > /tmp/aes.bin
[ "$(wc -c < /tmp/aes.bin | tr -d " ")" = 32 ] || { echo "key is not 32 bytes"; exit 1; }
kubectl --context $ctx -n wso2-gw create secret generic gateway-encryption-keys --from-file=default-aesgcm256-v1.bin=/tmp/aes.bin \
  --dry-run=client -o yaml | kubectl --context $ctx apply -f -
rm -f /tmp/aes.bin
kubectl --context $ctx -n wso2-gw describe secret gateway-encryption-keys | grep -E "bin|Name:"

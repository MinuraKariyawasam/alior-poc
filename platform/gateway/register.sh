#!/usr/bin/env bash
# register.sh <a|b> [vhost-url]
# Registers "pod-<r>-gw" as a Platform Gateway in the APIM control plane (Admin API v4), stores the one-time
# registration token in Key Vault (gw-token-<r>) and creates Secret gateway-cp-token in wso2-gw of pod-<r>-aks,
# which the APIGateway CR references (controlPlane.tokenSecretRef). Idempotent: an existing gateway keeps its id;
# a missing token is regenerated through /gateways/{id}/regenerate-token.
# Talks to APIM through a port-forward to localhost:9443 (svc apim-wso2am-all-in-one-am-service in wso2-cp).
set -euo pipefail
r=${1:?a or b}; VHOST=${2:-https://pod-$r-gw.alior-poc.local:8443}; ctx=pod-$r-aks; GW=pod-$r-gw
cd "$(dirname "$0")/../../infra/azure" && source ./env.sh
ADMIN=https://localhost:9443/api/am/admin/v4
PW=$(az keyvault secret show --vault-name $KV -n apim-admin-password --query value -o tsv)
kubectl --context pod-a-aks -n wso2-cp port-forward svc/apim-wso2am-all-in-one-am-service 9443:9443 >/dev/null 2>&1 &
PF=$!; trap 'kill $PF 2>/dev/null' EXIT; sleep 3
api(){ curl -sk -u "admin:$PW" "$@"; }
GW_ID=$(api "$ADMIN/gateways" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(next((g["id"] for g in d.get("list",[]) if g.get("name")=="'"$GW"'"),""))')
TOKEN=""
if [ -z "$GW_ID" ]; then
  RESP=$(api -X POST -H "Content-Type: application/json" "$ADMIN/gateways" \
    -d '{"name":"'"$GW"'","displayName":"'"$GW"'","description":"Alior PoD region '"$r"' platform gateway","vhost":"'"$VHOST"'"}')
  GW_ID=$(echo "$RESP" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("id",""))')
  TOKEN=$(echo "$RESP" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("registrationToken",""))')
  [ -n "$TOKEN" ] || { echo "registration failed: $RESP"; exit 1; }
  echo "registered $GW ($GW_ID)"
elif ! az keyvault secret show --vault-name $KV -n gw-token-$r -o none 2>/dev/null; then
  TOKEN=$(api -X POST "$ADMIN/gateways/$GW_ID/regenerate-token" | python3 -c 'import sys,json; print(json.load(sys.stdin)["registrationToken"])')
  echo "regenerated token for $GW ($GW_ID)"
else
  echo "$GW exists ($GW_ID); token already in Key Vault"
fi
[ -n "$TOKEN" ] && az keyvault secret set --vault-name $KV -n gw-token-$r --value "$TOKEN" -o none
az keyvault secret show --vault-name $KV -n gw-token-$r --query value -o tsv | tr -d '\n' \
  | kubectl --context $ctx -n wso2-gw create secret generic gateway-cp-token --from-file=token=/dev/stdin --dry-run=client -o yaml \
  | kubectl --context $ctx apply -f -
kubectl --context $ctx -n wso2-gw get secret gateway-cp-token -o jsonpath='{.metadata.name} ok{"\n"}'

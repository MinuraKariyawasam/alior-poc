#!/usr/bin/env bash
# Phase 1/2 gate: an API published in the APIM control plane answers from BOTH gateways and through Front Door.
# Publisher REST API over a port-forward with admin basic auth (verified on APIM 4.7 in the HDI PoC).
# Exits non-zero on failure and prints status codes per path.
set -euo pipefail
cd "$(dirname "$0")/.." ; source infra/azure/env.sh
N=accounts; V=1.0.0; EP=http://10.20.16.4:8081          # mock-v1 on pod-b-vm
PUB=https://localhost:9443/api/am/publisher/v4
PW=$(az keyvault secret show --vault-name $KV -n apim-admin-password --query value -o tsv)
kubectl --context pod-a-aks -n wso2-cp port-forward svc/apim-wso2am-all-in-one-am-service 9443:9443 >/dev/null 2>&1 & PF=$!; trap 'kill $PF 2>/dev/null' EXIT; sleep 3
api(){ curl -sk -u "admin:$PW" "$@"; }
j(){ python3 -c "import sys,json; d=json.load(sys.stdin); $1"; }

ID=$(api "$PUB/apis?query=name:$N" | j 'l=[a["id"] for a in d.get("list",[]) if a["name"]=="'$N'"]; print(l[0] if l else "")')
if [ -z "$ID" ]; then
  ID=$(api -X POST "$PUB/apis/import-openapi" -F file=@apis/accounts/openapi.yaml \
    -F 'additionalProperties={"name":"'$N'","version":"'$V'","context":"/'$N'","gatewayType":"APIPlatform","policies":["DefaultSubscriptionless"],"endpointConfig":{"endpoint_type":"http","production_endpoints":{"url":"'$EP'"},"sandbox_endpoints":{"url":"'$EP'"}}}' \
    | j 'print(d.get("id") or sys.exit("import failed: "+json.dumps(d)))')
  echo "created API $N ($ID) -> $EP"
else echo "API $N exists ($ID)"; fi
REV=$(api -X POST -H "Content-Type: application/json" "$PUB/apis/$ID/revisions" -d '{"description":"gate"}' | j 'print(d.get("id") or sys.exit("revision failed: "+json.dumps(d)))')
api -X POST -H "Content-Type: application/json" "$PUB/apis/$ID/deploy-revision?revisionId=$REV" \
  -d '[{"name":"pod-a-gw","vhost":"pod-a-gw.alior-poc.local","displayOnDevportal":true},{"name":"pod-b-gw","vhost":"pod-b-gw.alior-poc.local","displayOnDevportal":true}]' \
  -o /dev/null -w "deploy revision to pod-a-gw + pod-b-gw -> %{http_code}\n"
api -X POST "$PUB/apis/change-lifecycle?apiId=$ID&action=Publish" -o /dev/null -w "publish -> %{http_code} (400 = already published)\n"
sleep 10

fail=0
call(){ # label url host
  local code; code=$(curl -sk -m 15 -o /dev/null -w '%{http_code}' -H "Host: $3" "$2/$N/$V/accounts" || echo 000)
  printf '%-34s %s\n' "$1" "$code"; [ "$code" = 200 ] || fail=1
}
IP_A=$(kubectl --context pod-a-aks -n wso2-gw get svc -l app.kubernetes.io/component=gateway-runtime -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')
IP_B=$(kubectl --context pod-b-aks -n wso2-gw get svc -l app.kubernetes.io/component=gateway-runtime -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')
FD=$(az afd endpoint show -g $RG --profile-name pod-afd --endpoint-name pod-api --query hostName -o tsv 2>/dev/null || true)
call "region A gateway ($IP_A)" "https://$IP_A:8443" pod-a-gw.alior-poc.local
call "region B gateway ($IP_B)" "https://$IP_B:8443" pod-b-gw.alior-poc.local
[ -n "$FD" ] && for i in 1 2 3 4; do call "front door $FD try $i" "https://$FD" "$FD"; done
[ $fail = 0 ] && echo "GATE PASSED" || { echo "GATE FAILED"; exit 1; }

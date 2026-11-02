# Shared control plane helpers for tests/pod-*.sh. Source after infra/azure/env.sh.
# cp_connect [port]      port-forward to the APIM control plane with retries; sets $PUB, $DEV, $CP and api()
# cp_token                prints a client_credentials access token for the Dev Portal app pod-health
# cp_publish NAME VER CTX ENDPOINT [HUB_POLICIES_JSON] [GATEWAYS]   import (if new), attach policies, new revision, deploy, publish
cp_connect(){
  local port=${1:-19448}; CP=https://localhost:$port; PUB=$CP/api/am/publisher/v4; DEV=$CP/api/am/devportal/v3
  CP_PW=$(az keyvault secret show --vault-name "$KV" -n apim-admin-password --query value -o tsv)
  pkill -f "port-forward svc/apim-wso2am-all-in-one-am-service $port" 2>/dev/null
  for try in 1 2 3; do
    kubectl --context pod-a-aks -n wso2-cp port-forward svc/apim-wso2am-all-in-one-am-service $port:9443 >/dev/null 2>&1 & CP_PF=$!
    for i in $(seq 1 40); do [ "$(curl -sk -m 3 -o /dev/null -w '%{http_code}' $CP/services/Version)" != 000 ] && return 0; sleep 1; done
    kill $CP_PF 2>/dev/null; wait $CP_PF 2>/dev/null
  done; echo "control plane port-forward failed on $port"; return 1
}
api(){ curl -sk -m 60 -u "admin:$CP_PW" "$@"; }
j(){ python3 -c "import sys,json; d=json.load(sys.stdin); $1"; }
cp_token(){
  local app ck cs
  app=$(api "$DEV/applications?query=pod-health" | j 'print([a["applicationId"] for a in d["list"] if a["name"]=="pod-health"][0])')
  ck=$(api "$DEV/applications/$app/oauth-keys" | j 'print([k["consumerKey"] for k in d["list"] if k["keyType"]=="PRODUCTION"][0])')
  cs=$(api "$CP/api/identity/oauth2/dcr/v1.1/register/$ck" | j 'print(d["client_secret"])')
  curl -sk -m 30 -u "$ck:$cs" -d 'grant_type=client_credentials' $CP/oauth2/token | j 'print(d["access_token"])'
}
cp_publish(){
  local N=$1 V=$2 CTX=$3 EP=$4 POL=${5:-[]} GWS=${6:-"pod-a-gw pod-b-gw"} ID tmp
  ID=$(api "$PUB/apis?query=name:$N" | j 'l=[a["id"] for a in d.get("list",[]) if a["name"]=="'$N'" and a["version"]=="'$V'"]; print(l[0] if l else "")')
  if [ -z "$ID" ]; then
    tmp=$(mktemp); sed "s/^  title: .*/  title: $N/; s/^  version: .*/  version: $V/" tests/accounts-openapi.yaml > "$tmp"
    ID=$(api -X POST "$PUB/apis/import-openapi" -F file=@"$tmp" \
      -F 'additionalProperties={"name":"'$N'","version":"'$V'","context":"'$CTX'","gatewayType":"APIPlatform","policies":["DefaultSubscriptionless"],"endpointConfig":{"endpoint_type":"http","production_endpoints":{"url":"'$EP'"},"sandbox_endpoints":{"url":"'$EP'"}}}' \
      | j 'print(d.get("id") or sys.exit("import failed: "+json.dumps(d)))'); rm -f "$tmp"
    echo "created API $N $V ($ID) -> $EP"
  else echo "API $N $V exists ($ID)"; fi
  # Policy Hub policies at API level: items need policyId "<name>::<version>" (what the Publisher UI sends) and apiPolicies must be the empty flows
  api "$PUB/apis/$ID" | python3 -c '
import sys,json; d=json.load(sys.stdin); pol=json.loads(sys.argv[1])
d["apiHubPolicies"]=[{"policyName":p["name"],"policyId":p["name"]+"::"+p["version"],"policyVersion":p["version"],"parameters":p.get("parameters",{})} for p in pol]
d["apiPolicies"]={"request":[],"response":[],"fault":[]}
for o in d.get("operations",[]): o.setdefault("operationHubPolicies",[])
print(json.dumps(d))' "$POL" > /tmp/claude-501/api-$ID.json
  api -X PUT -H "Content-Type: application/json" "$PUB/apis/$ID" --data-binary @/tmp/claude-501/api-$ID.json -o /dev/null -w "policies $(printf '%s' "$POL" | tr -d ' \n' | cut -c1-60) -> %{http_code}\n"
  for old in $(api "$PUB/apis/$ID/revisions?query=deployed:false" | j 'print(" ".join(r["id"] for r in d.get("list",[])[:-1]))'); do api -X DELETE "$PUB/apis/$ID/revisions/$old" -o /dev/null; done
  local REV; REV=$(api -X POST -H "Content-Type: application/json" "$PUB/apis/$ID/revisions" -d '{"description":"'"$(date -u +%FT%TZ)"'"}' | j 'print(d.get("id") or sys.exit("revision failed: "+json.dumps(d)))')
  local targets=""; for g in $GWS; do targets+='{"name":"'$g'","vhost":"'$g'.alior-poc.local","displayOnDevportal":true},'; done
  api -X POST -H "Content-Type: application/json" "$PUB/apis/$ID/deploy-revision?revisionId=$REV" -d "[${targets%,}]" -o /dev/null -w "deploy revision to $GWS -> %{http_code}\n"
  api -X POST "$PUB/apis/change-lifecycle?apiId=$ID&action=Publish" -o /dev/null -w "publish -> %{http_code} (400 = already published)\n"
  CP_API_ID=$ID
}

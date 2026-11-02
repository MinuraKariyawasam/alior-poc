#!/usr/bin/env bash
# Read-only health check of the base platform: Azure resources, both clusters, Argo CD, gateways, control plane, Front Door.
# Prints one line per check; exits non-zero if any check fails. Run `make gate` afterwards for the end-to-end API proof.
set -uo pipefail
cd "$(dirname "$0")/.." ; source infra/azure/env.sh
fail=0; ok(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fail=1; }
check(){ # label command...   (passes when the command exits 0; one retry, the AKS API servers occasionally time out a TLS handshake from a laptop)
  local l=$1; shift; if "$@" >/dev/null 2>&1 || { sleep 3; "$@" >/dev/null 2>&1; }; then ok "$l"; else bad "$l"; fi; }

echo "== Azure ($RG)"
for c in pod-a-aks pod-b-aks; do
  st=$(az aks show -g "$RG" -n $c --query "[powerState.code,provisioningState]" -o tsv 2>/dev/null | tr '\n' ' ')
  [ "$st" = "Running Succeeded " ] && ok "$c $st" || bad "$c $st"
done
for v in pod-a-db pod-b-vm; do
  st=$(az vm get-instance-view -g "$RG" -n $v --query "instanceView.statuses[?starts_with(code,'PowerState')].displayStatus" -o tsv 2>/dev/null)
  [ "$st" = "VM running" ] && ok "$v $st" || bad "$v ${st:-unknown}"
done
for e in pod-api pod-cp pod-ops-b; do
  st=$(az afd endpoint show -g "$RG" --profile-name pod-afd --endpoint-name $e --query "[enabledState,provisioningState]" -o tsv 2>/dev/null | tr '\n' ' ')
  [ "$st" = "Enabled Succeeded " ] && ok "front door $e" || bad "front door $e $st"
done
az network front-door waf-policy list -g "$RG" --query "[].[name,policySettings.mode]" -o tsv 2>/dev/null | while read -r n m; do printf '  info waf %s mode=%s\n' "$n" "$m"; done

for c in pod-a-aks pod-b-aks; do
  echo "== $c"
  nr=$(kubectl --context $c get nodes --no-headers 2>/dev/null | awk '$2!="Ready"' | wc -l | tr -d ' '); nt=$(kubectl --context $c get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
  [ "$nt" -gt 0 ] && [ "$nr" = 0 ] && ok "nodes ready ($nt)" || bad "nodes: $nr of $nt not ready"
  kubectl --context $c -n argocd get applications -o custom-columns=N:.metadata.name,S:.status.sync.status,H:.status.health.status --no-headers 2>/dev/null | while read -r n s h; do
    if [ "$h" = Healthy ] && { [ "$s" = Synced ] || [ "$n" = cert-manager ]; }; then ok "argo $n $s/$h"; else bad "argo $n $s/$h"; fi; done   # cert-manager shows OutOfSync on CRD annotations only
  np=$(kubectl --context $c get pods -A --no-headers 2>/dev/null | grep -vcE 'Running|Completed'); [ "$np" = 0 ] && ok "all pods running" || bad "$np pods not running"
  check "gateway CR present" kubectl --context $c --request-timeout=20s -n wso2-gw get apigateway
  ip=$(kubectl --context $c -n wso2-gw get svc -l app.kubernetes.io/component=gateway-runtime -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null)
  [ -n "$ip" ] && ok "gateway runtime LB ip $ip" || bad "gateway runtime has no LB ip"
  nc=$(kubectl --context $c get certificate -A --no-headers 2>/dev/null | awk '$3!="True"' | wc -l | tr -d ' '); [ "$nc" = 0 ] && ok "certificates ready" || bad "$nc certificates not ready"
done

echo "== control plane (region A)"
PW=$(az keyvault secret show --vault-name "$KV" -n apim-admin-password --query value -o tsv)
kubectl --context pod-a-aks -n wso2-cp port-forward svc/apim-wso2am-all-in-one-am-service 19445:9443 >/dev/null 2>&1 & PF=$!; trap 'kill $PF 2>/dev/null' EXIT
for i in $(seq 1 30); do curl -sk -m 3 -o /dev/null https://localhost:19445/ && break; sleep 1; done
api(){ curl -sk -m 20 -u "admin:$PW" "$@"; }
gws=$(api https://localhost:19445/api/am/admin/v4/gateways | python3 -c 'import sys,json; d=json.load(sys.stdin); print(" ".join(g["name"]+":"+("active" if g["isActive"] else "inactive") for g in d.get("list",[])))' 2>/dev/null)
case "$gws" in *pod-a-gw:active*pod-b-gw:active*|*pod-b-gw:active*pod-a-gw:active*) ok "gateways registered: $gws";; *) bad "gateways registered: ${gws:-none}";; esac
apis=$(api https://localhost:19445/api/am/publisher/v4/apis | python3 -c 'import sys,json; d=json.load(sys.stdin); print(", ".join(a["name"]+" "+a["version"]+" "+a["lifeCycleStatus"] for a in d.get("list",[])))' 2>/dev/null)
[ -n "$apis" ] && ok "APIs: $apis" || bad "publisher API list empty or unreachable"
for c in pod-a-aks pod-b-aks; do
  n=$(kubectl --context $c -n wso2-gw logs -l app.kubernetes.io/component=controller --since=24h 2>/dev/null | grep -c '"level":"ERROR"'); [ "$n" = 0 ] && ok "$c controller: no ERROR lines in 24h" || bad "$c controller: $n ERROR lines in 24h"
done

echo "== through Front Door"
for u in https://pod-cp-eccmfmahgkevcqcy.a02.azurefd.net/publisher/ https://pod-cp-eccmfmahgkevcqcy.a02.azurefd.net/argocd/ https://pod-ops-b-a3graqbqf9dvcxe8.a02.azurefd.net/argocd/ https://pod-api-guf3bbbjh5htgxfu.a02.azurefd.net/accounts/1.0.0/accounts; do
  code=$(curl -sk -m 20 -o /dev/null -w '%{http_code}' "$u"); [ "$code" = 200 ] && ok "$code ${u#https://}" || bad "$code ${u#https://}"
done
code=$(curl -sk -m 20 -o /dev/null -w '%{http_code}' "https://pod-api-guf3bbbjh5htgxfu.a02.azurefd.net/accounts/1.0.0/accounts?q=1%20union%20select%201")
[ "$code" = 403 ] && ok "WAF blocks injection ($code)" || bad "WAF did not block injection ($code)"

[ $fail = 0 ] && echo "HEALTH OK" || { echo "HEALTH FAILED"; exit 1; }

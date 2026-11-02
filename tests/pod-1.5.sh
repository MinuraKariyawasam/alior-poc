#!/usr/bin/env bash
# PoD 1.5 proof: multiple cooperating gateway instances, no single point of failure on the data path.
# Two runtime replicas per region behind each region's load balancer, two regions behind Front Door. Kills every runtime
# pod in region A while calling the API through Front Door and counts failures.
set -uo pipefail
cd "$(dirname "$0")/.." ; source infra/azure/env.sh
mkdir -p evidence/1.5; LOG=evidence/1.5/pod-1.5-$(date +%Y%m%d-%H%M).log; exec > >(tee "$LOG") 2>&1
fail=0; ok(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fail=1; }
U=https://pod-api-guf3bbbjh5htgxfu.a02.azurefd.net/accounts/1.0.0/accounts
for c in pod-a-aks pod-b-aks; do
  n=$(kubectl --context $c --request-timeout=60s -n wso2-gw get pods -l app.kubernetes.io/component=gateway-runtime -o jsonpath='{range .items[*]}{.status.containerStatuses[0].ready}{" "}{end}' | tr -s ' ' '\n' | grep -c true)
  [ "$n" -ge 2 ] && ok "$c: $n gateway runtimes ready" || bad "$c: $n gateway runtimes ready (want 2)"
done
echo "== 40 calls through Front Door while every region A runtime pod is deleted"
( sleep 3; kubectl --context pod-a-aks -n wso2-gw delete pods -l app.kubernetes.io/component=gateway-runtime --wait=false >/dev/null 2>&1 && echo "       region A runtime pods deleted" ) &
codes=""; for i in $(seq 1 40); do codes+="$(curl -sk -m 10 -o /dev/null -w '%{http_code}' $U) "; sleep 0.5; done; echo "       $codes"
bad_n=$(printf '%s' "$codes" | tr ' ' '\n' | grep -vc '^200$'); [ "$bad_n" -le 2 ] && ok "non-200 during the kill: $bad_n of 40 (a blip at most)" || bad "non-200 during the kill: $bad_n of 40"
wait; sleep 20
code=$(curl -sk -m 10 -o /dev/null -w '%{http_code}' $U); [ "$code" = 200 ] && ok "after recovery -> $code" || bad "after recovery -> $code"
n=$(kubectl --context pod-a-aks --request-timeout=60s -n wso2-gw get pods -l app.kubernetes.io/component=gateway-runtime --no-headers | grep -c Running); echo "  info region A runtimes running again: $n"
[ $fail = 0 ] && echo "POD 1.5 PASSED" || { echo "POD 1.5 FAILED"; exit 1; }

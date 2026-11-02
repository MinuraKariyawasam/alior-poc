#!/usr/bin/env bash
# Drill: restart the gateway controller in both regions and show the deployed APIs survive without a redeploy from the
# control plane (the 1.2.x behaviour was 503 cluster_not_found until redeploy; fixed in gateway 2026.10.0).
# Prints the Envoy cluster count before/after and the API status through Front Door.
set -uo pipefail
cd "$(dirname "$0")/.." ; source infra/azure/env.sh
mkdir -p evidence/15.2; LOG=evidence/15.2/controller-restart-$(date +%Y%m%d-%H%M).log; exec > >(tee "$LOG") 2>&1
fail=0; ok(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fail=1; }
U=https://pod-api-guf3bbbjh5htgxfu.a02.azurefd.net/accounts/1.0.0/accounts
clusters(){ local c=$1 r=${1:4:1} v; kubectl --context $c --request-timeout=60s -n wso2-gw port-forward svc/pod-$r-gw-gw-gateway-controller 19191:9091 >/dev/null 2>&1 & local PF=$!
  for i in $(seq 1 30); do curl -sf -m 2 -o /dev/null http://localhost:19191/metrics && break; sleep 1; done
  v=$(curl -s -m 10 http://localhost:19191/metrics | sed -n 's/^gateway_controller_snapshot_size{resource_type="cluster"} //p'); kill $PF 2>/dev/null; wait $PF 2>/dev/null; echo "${v:-?}"; }
echo "== before: controller image and Envoy cluster count"
for c in pod-a-aks pod-b-aks; do echo "  $c image=$(kubectl --context $c --request-timeout=60s -n wso2-gw get pods -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].spec.containers[0].image}') clusters=$(clusters $c)"; done
before=$(curl -sk -m 15 -o /dev/null -w '%{http_code}' $U); echo "  Front Door before: $before"
echo "== restart both controllers"
for c in pod-a-aks pod-b-aks; do r=${c:4:1}; kubectl --context $c --request-timeout=60s -n wso2-gw rollout restart deploy/pod-$r-gw-gw-gateway-controller >/dev/null && kubectl --context $c --request-timeout=60s -n wso2-gw rollout status deploy/pod-$r-gw-gw-gateway-controller --timeout=240s | tail -1; done
sleep 30
echo "== after"
for c in pod-a-aks pod-b-aks; do n=$(clusters $c); echo "  $c clusters=$n"; [ "$n" = "$(clusters $c)" ] && [ "${n:-0}" -ge 4 ] 2>/dev/null && ok "$c keeps the API upstream cluster ($n clusters)" || bad "$c cluster count $n (want the pre-restart count, 4+)"; done
codes=""; for i in $(seq 1 6); do codes+="$(curl -sk -m 15 -o /dev/null -w '%{http_code}' $U) "; sleep 2; done; echo "  Front Door after: $codes"
printf '%s' "$codes" | tr ' ' '\n' | grep -q -v '^200$' && bad "API through Front Door after the restart: $codes" || ok "API through Front Door after the restart, no redeploy: all 200"
[ $fail = 0 ] && echo "CONTROLLER RESTART DRILL PASSED" || { echo "CONTROLLER RESTART DRILL FAILED"; exit 1; }

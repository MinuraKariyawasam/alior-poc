#!/usr/bin/env bash
# PoD 1.1 proof: the gateway controls API calls between applications inside one Kubernetes cluster.
# App A = a curl pod in namespace apps. App B = the in-cluster mock (Service mock.apps.svc:8080, platform/apps/).
# The call goes to the gateway runtime's ClusterIP Service (never leaves the cluster) and the jwt-auth policy decides.
set -uo pipefail
cd "$(dirname "$0")/.." ; source infra/azure/env.sh; source tests/lib/cp.sh
mkdir -p evidence/1.1; LOG=evidence/1.1/pod-1.1-$(date +%Y%m%d-%H%M).log; exec > >(tee "$LOG") 2>&1
fail=0; ok(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fail=1; }
cp_connect || exit 1; trap 'kill $CP_PF 2>/dev/null' EXIT
echo "== publish internal 1.0.0 (/internal -> http://mock.apps.svc.cluster.local:8080) with jwt-auth, both gateways"
cp_publish internal 1.0.0 /internal http://mock.apps.svc.cluster.local:8080 '[{"name":"jwt-auth","version":"1.3","parameters":{"issuers":["apim-resident"]}}]'
TOK=$(cp_token); sleep 10
for c in pod-a-aks pod-b-aks; do
  r=${c:4:1}; GW="http://pod-$r-gw-gw-gateway-gateway-runtime.wso2-gw.svc.cluster.local:8080/internal/1.0.0/accounts"
  echo "== $c: app A (curl pod in apps) -> gateway ClusterIP -> app B (mock.apps.svc)"
  out=$(kubectl --context $c --request-timeout=120s -n apps run curl-pod-1-1 --rm -i --restart=Never --image=curlimages/curl:8.11.1 --quiet -- sh -c "
    printf 'no-token=%s\n' \$(curl -s -m 10 -o /dev/null -w '%{http_code}' -H 'Host: pod-$r-gw.alior-poc.local' $GW)
    printf 'with-token=%s\n' \$(curl -s -m 10 -o /dev/null -w '%{http_code}' -H 'Host: pod-$r-gw.alior-poc.local' -H 'Authorization: Bearer $TOK' $GW)
    printf 'body=%s\n' \"\$(curl -s -m 10 -H 'Host: pod-$r-gw.alior-poc.local' -H 'Authorization: Bearer $TOK' $GW)\"" 2>/dev/null)
  printf '%s\n' "$out" | sed 's/^/       /'; printf '%s\n' "$out" > evidence/1.1/$c-calls.txt
  nt=$(printf '%s' "$out" | sed -n 's/^no-token=//p'); wt=$(printf '%s' "$out" | sed -n 's/^with-token=//p'); host=$(printf '%s' "$out" | sed -n 's/^body=//p' | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d["host"], d["version"])' 2>/dev/null)
  [ "$nt" = 401 ] && ok "$c no token -> 401" || bad "$c no token -> ${nt:-none}"
  [ "$wt" = 200 ] && ok "$c with token -> 200, answered by in-cluster mock pod: $host" || bad "$c with token -> ${wt:-none}"
  echo "  info mock pod: $(kubectl --context $c -n apps get pods -l app=mock -o jsonpath='{.items[0].metadata.name} {.items[0].status.podIP}')"
done
[ $fail = 0 ] && echo "POD 1.1 PASSED" || { echo "POD 1.1 FAILED"; exit 1; }

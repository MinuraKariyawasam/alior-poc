#!/usr/bin/env bash
# PoD 1.2 proof: a dedicated gateway cluster (region B, westeurope) serves calls from the untrusted zone (Internet via
# Front Door) to a standalone backend on a VM (mock-legacy on pod-b-vm :8083), with a gateway policy (jwt-auth) applied.
# The API is also deployed to region A so Front Door can send any request to either region (both reach the VM).
set -uo pipefail
cd "$(dirname "$0")/.." ; source infra/azure/env.sh; source tests/lib/cp.sh
mkdir -p evidence/1.2; LOG=evidence/1.2/pod-1.2-$(date +%Y%m%d-%H%M).log; exec > >(tee "$LOG") 2>&1
fail=0; ok(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fail=1; }
FD=https://pod-api-guf3bbbjh5htgxfu.a02.azurefd.net
cp_connect || exit 1; trap 'kill $CP_PF 2>/dev/null' EXIT
echo "== publish legacy 1.0.0 (/legacy -> http://10.20.16.4:8083 on pod-b-vm) with jwt-auth"
cp_publish legacy 1.0.0 /legacy http://10.20.16.4:8083 '[{"name":"jwt-auth","version":"1.3","parameters":{"issuers":["apim-resident"]}}]'
TOK=$(cp_token); sleep 10
c(){ curl -sk -m 20 -o /dev/null -w '%{http_code}' "$@"; }
echo "== untrusted zone (Internet) -> Front Door -> gateway -> VM"
code=$(c "$FD/legacy/1.0.0/accounts"); [ "$code" = 401 ] && ok "no token -> $code" || bad "no token -> $code (want 401)"
curl -sk -m 20 -D evidence/1.2/headers.txt -o evidence/1.2/body.json -H "Authorization: Bearer $TOK" "$FD/legacy/1.0.0/accounts"
code=$(head -1 evidence/1.2/headers.txt | awk '{print $2}'); ver=$(grep -i '^x-mock-version' evidence/1.2/headers.txt | tr -d '\r' | awk '{print $2}')
[ "$code" = 200 ] && [ "$ver" = legacy ] && ok "with token -> $code from the VM backend (x-mock-version=$ver, body: $(python3 -c 'import json;d=json.load(open("evidence/1.2/body.json"));print(d["host"],d["port"],d["path"])'))" || bad "with token -> $code x-mock-version=$ver"
echo "== the dedicated cluster itself (region B) routes to the VM: direct call inside pod-b-aks"
for try in 1 2 3; do   # pod-b-aks API server sometimes times out a TLS handshake from a laptop
  kubectl --context pod-b-aks -n wso2-gw port-forward svc/pod-b-gw-gw-gateway-gateway-runtime 18082:8080 >/dev/null 2>&1 & PF=$!
  for i in $(seq 1 40); do [ "$(curl -s -m 2 -o /dev/null -w '%{http_code}' http://localhost:18082/_gateway-health/ready)" = 200 ] && break 2; sleep 1; done
  kill $PF 2>/dev/null; wait $PF 2>/dev/null
done
code=$(curl -s -m 15 -o /dev/null -w '%{http_code}' -H "Host: pod-b-gw.alior-poc.local" -H "Authorization: Bearer $TOK" http://localhost:18082/legacy/1.0.0/accounts); kill $PF 2>/dev/null; wait $PF 2>/dev/null
[ "$code" = 200 ] && ok "pod-b-gw direct -> $code" || bad "pod-b-gw direct -> $code"
echo "== nothing but Front Door reaches the gateways or the VM from the Internet"
for ip in 74.153.35.38 132.220.139.111; do code=$(curl -s -m 6 -o /dev/null -w '%{http_code}' http://$ip:8080/legacy/1.0.0/accounts || true); [ "$code" = 000 ] && ok "gateway $ip:8080 direct -> no answer (NSG allows AzureFrontDoor.Backend only)" || bad "gateway $ip:8080 direct -> $code"; done
pip=$(az vm show -g "$RG" -n pod-b-vm -d --query publicIps -o tsv 2>/dev/null); [ -z "$pip" ] && ok "pod-b-vm has no public IP (private 10.20.16.4 only)" || bad "pod-b-vm has a public IP: $pip"
[ $fail = 0 ] && echo "POD 1.2 PASSED" || { echo "POD 1.2 FAILED"; exit 1; }

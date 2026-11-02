#!/usr/bin/env bash
# PoD 1.6 proof: selective outbound HTTP proxy on the gateway runtime (HTTPS_PROXY + NO_PROXY, platform/gateway/region-*).
# Region B: the policy engine's JWKS fetch to the control plane (10.10.0.6, not in NO_PROXY) must appear in the proxy log;
# in-cluster calls (controller xDS, .svc names) must not. Region A: the JWKS host is an in-cluster .svc name, so nothing
# goes through the proxy. Backend traffic is handled by the Envoy router, which does not use proxy env vars (noted).
set -uo pipefail
cd "$(dirname "$0")/.." ; source infra/azure/env.sh; source tests/lib/cp.sh
mkdir -p evidence/1.6; LOG=evidence/1.6/pod-1.6-$(date +%Y%m%d-%H%M).log; exec > >(tee "$LOG") 2>&1
fail=0; ok(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fail=1; }
for c in pod-a-aks pod-b-aks; do
  env=$(kubectl --context $c --request-timeout=60s -n wso2-gw get deploy -l app.kubernetes.io/component=gateway-runtime -o jsonpath='{.items[0].spec.template.spec.containers[0].env[?(@.name=="NO_PROXY")].value}')
  [ -n "$env" ] && ok "$c runtime NO_PROXY=$env" || bad "$c runtime has no proxy env"
done
cp_connect || exit 1; trap 'kill $CP_PF 2>/dev/null' EXIT; TOK=$(cp_token)
echo "== force a JWKS fetch in region B: restart its runtime so the policy engine's key cache is empty, then one token call"
kubectl --context pod-b-aks -n wso2-gw rollout restart deploy -l app.kubernetes.io/component=gateway-runtime >/dev/null && kubectl --context pod-b-aks -n wso2-gw rollout status deploy -l app.kubernetes.io/component=gateway-runtime --timeout=180s >/dev/null
sleep 5; since=$(date -u +%FT%TZ)
for try in 1 2 3; do kubectl --context pod-b-aks -n wso2-gw port-forward svc/pod-b-gw-gw-gateway-gateway-runtime 18083:8080 >/dev/null 2>&1 & PF=$!; for i in $(seq 1 40); do [ "$(curl -s -m 2 -o /dev/null -w '%{http_code}' http://localhost:18083/_gateway-health/ready)" = 200 ] && break 2; sleep 1; done; kill $PF 2>/dev/null; wait $PF 2>/dev/null; done
code=$(curl -s -m 20 -o /dev/null -w '%{http_code}' -H "Host: pod-b-gw.alior-poc.local" -H "Authorization: Bearer $TOK" http://localhost:18083/accounts-secure/1.0.0/accounts); kill $PF 2>/dev/null; wait $PF 2>/dev/null
[ "$code" = 200 ] && ok "region B token call -> $code (policy engine validated the token, keys fetched)" || bad "region B token call -> $code"
sleep 3; plog=$(kubectl --context pod-b-aks -n apps logs -l app=proxy --since-time="$since" 2>/dev/null); printf '%s\n' "$plog" > evidence/1.6/pod-b-proxy.log
printf '%s\n' "$plog" | grep -q "CONNECT 10.10.0.6:9443" && ok "region B proxy log shows the external JWKS fetch: $(printf '%s' "$plog" | grep -m1 CONNECT)" || bad "region B proxy log has no CONNECT 10.10.0.6:9443 (log: $(printf '%s' "$plog" | tail -3 | tr '\n' ';'))"
printf '%s\n' "$plog" | grep -q -E "svc|gateway-controller|mock" && bad "in-cluster traffic went through the proxy" || ok "no in-cluster traffic in the proxy log (NO_PROXY honoured)"
alog=$(kubectl --context pod-a-aks -n apps logs -l app=proxy --since=30m 2>/dev/null | grep -v listening); printf '%s\n' "$alog" > evidence/1.6/pod-a-proxy.log
[ -z "$alog" ] && ok "region A proxy log empty: its JWKS host is an in-cluster .svc name, bypassed" || echo "  info region A proxy log: $(printf '%s' "$alog" | tail -2 | tr '\n' ';')"
echo "  note backend calls go through the Envoy router, which does not read proxy env vars; a router-level proxy would be gateway config"
[ $fail = 0 ] && echo "POD 1.6 PASSED" || { echo "POD 1.6 FAILED"; exit 1; }

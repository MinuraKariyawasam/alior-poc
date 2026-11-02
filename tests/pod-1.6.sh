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
  env=""; for try in 1 2 3; do env=$(kubectl --context $c --request-timeout=60s -n wso2-gw get deploy -l app.kubernetes.io/component=gateway-runtime -o jsonpath='{.items[0].spec.template.spec.containers[0].env[?(@.name=="NO_PROXY")].value}' 2>/dev/null); [ -n "$env" ] && break; sleep 5; done   # AKS API TLS timeouts
  [ -n "$env" ] && ok "$c runtime NO_PROXY=$env" || bad "$c runtime has no proxy env"
done
cp_connect || exit 1; trap 'kill $CP_PF 2>/dev/null' EXIT
echo "== region B: the controller's outbound link to the control plane (10.10.0.6:9443, not in NO_PROXY) must use the proxy"
cenv=$(kubectl --context pod-b-aks --request-timeout=60s -n wso2-gw get deploy -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].spec.template.spec.containers[0].env[?(@.name=="NO_PROXY")].value}' 2>/dev/null)
[ -n "$cenv" ] && ok "pod-b-aks controller NO_PROXY=$cenv" || bad "pod-b-aks controller has no proxy env"
plog=$(kubectl --context pod-b-aks --request-timeout=60s -n apps logs -l app=proxy --tail=200 2>/dev/null | grep -v listening); printf '%s\n' "$plog" > evidence/1.6/pod-b-proxy.log
printf '%s\n' "$plog" | grep -q "CONNECT 10.10.0.6:9443" && ok "region B proxy log: $(printf '%s' "$plog" | grep -c 'CONNECT 10.10.0.6:9443') x CONNECT 10.10.0.6:9443 (control plane reached through the proxy)" || bad "region B proxy log has no CONNECT 10.10.0.6:9443 (last lines: $(printf '%s' "$plog" | tail -3 | tr '\n' ';'))"
printf '%s\n' "$plog" | grep -q -E "\.svc|gateway-controller|mock|\.cluster\.local" && bad "in-cluster traffic went through the proxy" || ok "no in-cluster traffic in the proxy log (NO_PROXY honoured)"
act=$(api "$CP/api/am/admin/v4/gateways" | j 'print(" ".join(g["name"]+"="+str(g["isActive"]) for g in d.get("list",[])))'); case "$act" in *pod-b-gw=True*) ok "control plane sees pod-b-gw active ($act); the link is direct, not proxied";; *) bad "pod-b-gw not active: $act";; esac
alog=$(kubectl --context pod-a-aks --request-timeout=60s -n apps logs -l app=proxy --tail=200 2>/dev/null | grep -v listening); printf '%s\n' "$alog" > evidence/1.6/pod-a-proxy.log
[ -z "$alog" ] && ok "region A proxy log empty: its control plane is an in-cluster .svc name, bypassed by NO_PROXY" || echo "  info region A proxy log: $(printf '%s' "$alog" | tail -2 | tr '\n' ';')"
echo "  note result 2026-11-02: HTTPS_PROXY/NO_PROXY are set in the controller and runtime pods but no gateway component uses them: the controller opened its control plane WebSocket straight to 10.10.0.6:9443, the policy engine fetched JWKS directly, and the Envoy router never reads proxy env. Outbound proxy support is a question for WSO2 (gap in gateway 1.2.x as deployed)."
[ $fail = 0 ] && echo "POD 1.6 PASSED" || { echo "POD 1.6 FAILED"; exit 1; }

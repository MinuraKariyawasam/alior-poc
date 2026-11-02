#!/usr/bin/env bash
# Proof for PoD 7.1 / 7.2 (gateway metrics in Prometheus and the WSO2 Grafana dashboards, both regions) and PoD 6.6
# (gateway logs as JSON on stdout, ready for any shipper: syslog, Elastic). Exits non-zero on failure; output is saved
# under evidence/7.1/ and the sample log lines under evidence/6.6/.
set -uo pipefail
cd "$(dirname "$0")/.." ; source infra/azure/env.sh
mkdir -p evidence/7.1 evidence/6.6; LOG=evidence/7.1/pod-7.1-$(date +%Y%m%d-%H%M).log; exec > >(tee "$LOG") 2>&1
fail=0; ok(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fail=1; }
PW=$(az keyvault secret show --vault-name "$KV" -n grafana-admin-password --query value -o tsv)
val(){ python3 -c 'import sys,json; r=json.load(sys.stdin)["data"]["result"]; print(" ".join((x["metric"].get("job") or x["metric"].get("__name__") or "v")+"="+x["value"][1] for x in r))' 2>/dev/null; }

echo "== traffic through Front Door (so the policy engine counters move)"
for i in 1 2 3 4 5 6; do printf '%s ' "$(curl -sk -m 20 -o /dev/null -w '%{http_code}' https://pod-api-guf3bbbjh5htgxfu.a02.azurefd.net/accounts/1.0.0/accounts)"; done; echo; sleep 20   # one scrape interval

for c in pod-a-aks pod-b-aks; do
  echo "== $c: Prometheus"
  for try in 1 2; do   # pod-b-aks's API server sometimes times out a TLS handshake from a laptop; one retry of the port-forward
    kubectl --context $c -n observability port-forward svc/monitoring-kube-prometheus-prometheus 19095:9090 >/dev/null 2>&1 & PF=$!
    for i in $(seq 1 40); do curl -sf -m 3 -o /dev/null http://localhost:19095/-/ready && break 2; sleep 1; done
    kill $PF 2>/dev/null; wait $PF 2>/dev/null
  done
  q(){ curl -s -m 10 --data-urlencode "query=$1" http://localhost:19095/api/v1/query | val; }
  up=$(q 'up{job=~"gateway-controller|policy-engine"}')
  case "$up" in *gateway-controller=1*policy-engine=1*|*policy-engine=1*gateway-controller=1*) ok "scrape targets up: $up";; *) bad "scrape targets up: ${up:-none}";; esac
  # metric names as exported by gateway-controller/policy-engine 1.2.0 (the dashboards from main also reference a few newer ones)
  for m in gateway_controller_xds_clients_connected 'gateway_controller_snapshot_size{resource_type="cluster"}' policy_engine_policy_chains_loaded policy_engine_xds_connection_state; do
    v=$(q "$m"); [ -n "$v" ] && ok "$m: $v" || bad "$m: no series"; done
  r=$(q 'sum(increase(policy_engine_requests_total[10m]))'); case "$r" in ""|*=0) bad "policy_engine_requests_total did not move in 10m: ${r:-none}";; *) ok "policy_engine_requests_total 10m increase: $r";; esac
  kill $PF 2>/dev/null; wait $PF 2>/dev/null

  echo "== $c: gateway logs on stdout (PoD 6.6)"
  line=$(kubectl --context $c -n wso2-gw logs -l app.kubernetes.io/component=gateway-runtime -c gateway-runtime --since=24h --tail=2000 2>/dev/null | grep -m1 '"respCd"')
  js=${line#\[rtr\] }
  if printf '%s' "$js" | python3 -c 'import sys,json; d=json.load(sys.stdin); print("  ok   router access log is JSON: t=%s %s %s -> %s dur=%sms" % (d["t"],d["meth"],d["path"],d["respCd"],d["dur"]))' 2>/dev/null; then
    printf '%s\n' "$js" > evidence/6.6/$c-router-access-log.json
  else bad "no JSON access log line from the router"; fi
  cl=$(kubectl --context $c -n wso2-gw logs -l app.kubernetes.io/component=controller --tail=50 2>/dev/null | grep '^{' | tail -1)
  printf '%s' "$cl" | python3 -c 'import sys,json; d=json.load(sys.stdin); print("  ok   controller log is JSON: level=%s msg=%s" % (d["level"],d["msg"]))' 2>/dev/null \
    && printf '%s\n' "$cl" > evidence/6.6/$c-controller-log.json || bad "controller log line is not JSON"
done

echo "== Grafana through Front Door"
for pair in a:pod-cp-eccmfmahgkevcqcy.a02.azurefd.net b:pod-ops-b-a3graqbqf9dvcxe8.a02.azurefd.net; do
  H=${pair#*:}
  code=$(curl -sk -m 20 -o /dev/null -w '%{http_code}' "https://$H/grafana/api/health"); [ "$code" = 200 ] && ok "$H/grafana health $code" || bad "$H/grafana health $code"
  uids=$(curl -sk -m 20 -u "admin:$PW" "https://$H/grafana/api/search?type=dash-db" | python3 -c 'import sys,json; print(" ".join(sorted(d["uid"] for d in json.load(sys.stdin))))' 2>/dev/null)
  case "$uids" in *gateway-controller*infrastructure-overview*policy-engine*) ok "dashboards: $uids";; *) bad "dashboards: ${uids:-none}";; esac
done
[ $fail = 0 ] && echo "POD 7.1 PASSED" || { echo "POD 7.1 FAILED"; exit 1; }

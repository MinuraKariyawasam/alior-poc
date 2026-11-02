# Phase 3: observability (PoD 7.1, 7.2, 6.6)

Direction agreed with Gihan Anuruddha on 2026-11-02: metrics first (Prometheus + Grafana), logs last and cheap (gateway
logs to stdout, the bank forwards them to syslog or Elastic with the shipper of its choice). No ELK build, no Loki, no
OTel collector for now; the plan's D6 is reduced to that.

## Metrics (PoD 7.1, 7.2)

| Piece | Where | Notes |
|---|---|---|
| Gateway metrics endpoints | `platform/gateway/region-*/gateway-values.yaml` | `gateway.config.controller.metrics.enabled` (:9091 `/metrics`) and `gateway.config.policy_engine.metrics.enabled` (:9003 `/metrics`), both off by default in gateway chart 1.2.5. The chart already names the Service ports `metrics` and `pe-metrics`. Envoy's `/stats/prometheus` (:9901) is not scraped: the chart binds the Envoy admin interface to loopback only (`routerAdminEnabled`). |
| Prometheus + Grafana | Argo app `monitoring`, `platform/argocd/region-*/monitoring.yaml` | kube-prometheus-stack 92.17.0 (operator v0.94.2) per cluster, namespace `observability`, `work` pool. Alertmanager, node-exporter, kube-state-metrics, default rules and the control-plane scrapes are off; retention 3 days, no persistent volume. ~200m CPU, ~700Mi per cluster. |
| Scrape targets | Argo app `observability`, `platform/observability/servicemonitors.yaml` | Two ServiceMonitors selecting the gateway Services in `wso2-gw`; job labels `gateway-controller` and `policy-engine`, the names WSO2's own `prometheus.yml` uses. |
| Dashboards | `platform/observability/dashboards/` | WSO2's three dashboards (Gateway Controller, Policy Engine, Infrastructure Overview) copied unchanged from `wso2/api-platform`, loaded by the Grafana sidecar from ConfigMaps (kustomize `configMapGenerator`). |
| Grafana | `https://pod-cp-eccmfmahgkevcqcy.a02.azurefd.net/grafana` (A), `https://pod-ops-b-a3graqbqf9dvcxe8.a02.azurefd.net/grafana` (B) | Through the existing Front Door UI endpoints and ingress-nginx, path `/grafana`. User `admin`, password in Key Vault `grafana-admin-password`, copied into Secret `grafana-admin` by `make grafana-secret` (same pattern as the gateway secrets). |

Proof: `make test POD=7.1` checks both Prometheus instances (targets up, gateway series present), both Grafana UIs through
Front Door (health, the three dashboards) and the JSON logs below. Output goes to `evidence/7.1/`.

## Logs (PoD 6.6)

Both gateway processes already write JSON to stdout: the router's access log (`[rtr] {...}` with method, path, status,
durations, upstream, request id) and the controller's structured log. Kubernetes captures stdout, so any shipper the bank
runs (Fluent Bit, Filebeat, the Azure Monitor agent) can forward it to syslog or Elasticsearch without touching the gateway.
WSO2 publishes a Fluent Bit configuration for exactly this (`gateway/observability/fluent-bit/` in `wso2/api-platform`).
Not deployed here on purpose; `tests/pod-7.1.sh` saves a sample line per cluster under `evidence/6.6/`.

To be decided later: whether to run a Fluent Bit DaemonSet with a syslog output for the demo, or show the stdout lines
and the bank's own shipper story on a slide.

## Order of operations

1. Commit and push (ground rule 12); Argo CD picks up `monitoring` and `observability` in both clusters. `observability`
   retries until the CRDs from `monitoring` exist.
2. `make grafana-secret` before Grafana starts (the pod waits on the Secret otherwise).
3. The gateway overlays changed, so the operator re-renders both gateways (`config-rev` bumped to 4). The controller pod restarts.
4. `make test POD=7.1`.

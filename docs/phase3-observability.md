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

## Logs (PoD 6.6): how it works

Three steps; only the first is built.

1. **The gateway writes JSON to stdout.** Two processes, two streams. The router (Envoy) writes one line per API call
   (`[rtr] {...}`: time, method, path, status, durations, upstream host, request id), switched on in the gateway values
   with `router.access_logs` format `json`. The controller writes its own events as JSON (control plane connected, API
   deployed, errors). Neither process writes a file or sends logs anywhere; they print.
2. **Kubernetes catches stdout.** The node keeps each container's output under `/var/log/containers/`. That is what
   `kubectl logs` reads and what `tests/pod-7.1.sh` saves under `evidence/6.6/`.
3. **A shipper forwards it.** Not built. A small agent on every node reads those files and sends each line on. The bank
   picks the destination, because the gateway does not care and the same stdout feeds any of them:
   - syslog, the universal format every SIEM accepts (what PoD 6.6 names);
   - Elasticsearch, for search and Kibana;
   - Azure Monitor, one AKS flag.

   Gihan's point on 2026-11-02: stdout is the lowest common denominator, so "Elastic or syslog" costs nothing on the
   gateway side.

Demo option, if a `kubectl logs` screenshot is not enough: Fluent Bit as a DaemonSet with a syslog output pointing at a
tiny syslog receiver pod, so a gateway call shows up as a syslog line. Start from WSO2's Fluent Bit config for the gateway
(`gateway/observability/fluent-bit/` in `wso2/api-platform`), which parses the JSON lines and tags them by component.
About half a day. Open until the live-demo-or-slide decision is made.

## Result (2026-11-02)

`make test POD=7.1` PASSED: both Prometheus instances scrape `gateway-controller` and `policy-engine`, `policy_engine_requests_total`
moves with traffic through Front Door, both Grafana UIs serve the three WSO2 dashboards, JSON log samples saved. The
dashboards come from `main` and reference a few metrics this gateway build (controller 1.2.0) does not export yet
(`gateway_controller_apis_total`, `gateway_controller_http_requests_total`); those panels stay empty until the image moves on.

### Finding (resolved 2026-11-02): a gateway controller restart dropped the deployed API until the control plane redeployed it

**Resolved** by upgrading to gateway chart/images 2026.10.0 from WSO2's Harbor (known issue in 1.2.x, per Gihan). `make drill D=controller-restart` now passes: both controllers restarted, Envoy cluster count unchanged (8), API 200 through Front Door with no redeploy (evidence/15.2). Details of the upgrade in `docs/phase2-platform.md`. The text below is kept as history.

Bumping `config-rev` restarts the controller (Recreate) and the runtime. Afterwards the policy engine still had its 12
routes, but the Envoy snapshot had 3 clusters instead of 4 (`gateway_controller_snapshot_size{resource_type="cluster"}`),
so `/accounts/1.0.0/accounts` answered **503 `cluster_not_found` (flag NC)** on both gateways, directly and through Front
Door, for about 7 minutes, even though the control plane listed the revision as deployed and both gateways as active. The
controller's SQLite WAL on the PVC holds data ("Loaded configurations count 2"), so this is not a lost disk. Redeploying
the revision from the control plane (`make gate`) restored the cluster and the API answered 200 again.

Reproduced on 2026-11-02 09:40Z with a plain `kubectl rollout restart` of both controller Deployments (runtimes untouched):
cluster count 3 in both regions, Front Door 503 within two minutes; `make gate` (deploy-revision) brought the API back in
under a minute.

This matters for drill D2 / PoD 15.2 ("traffic keeps flowing from the controller's local config"): true for a runtime
restart, not shown for a controller restart. To raise with Gihan / the gateway team before phase 6; until then, redeploy
from the Publisher after any controller restart.

## Order of operations

1. Commit and push (ground rule 12); Argo CD picks up `monitoring` and `observability` in both clusters. `observability`
   retries until the CRDs from `monitoring` exist.
2. `make grafana-secret` before Grafana starts (the pod waits on the Secret otherwise).
3. The gateway overlays changed, so the operator re-renders both gateways (`config-rev` bumped to 4). The controller pod restarts.
4. `make test POD=7.1`.

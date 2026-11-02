Grafana dashboards copied unchanged from https://github.com/wso2/api-platform, `gateway/observability/grafana/dashboards/`
(main, 2026-11-02). They expect a datasource named `Prometheus` and the jobs `gateway-controller` and `policy-engine`,
which kube-prometheus-stack and `../servicemonitors.yaml` provide. Refresh by copying the files again.

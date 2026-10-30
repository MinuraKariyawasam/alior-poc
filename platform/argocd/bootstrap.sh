#!/usr/bin/env bash
# bootstrap.sh <a|b>  — the ONE hand-run Helm install per cluster (ground rule 12 applies: commit+push first).
# Installs Argo CD (pinned) into pod-<r>-aks, then applies the app-of-apps for that region.
set -euo pipefail
r=${1:?a or b}; ctx=pod-$r-aks; cd "$(dirname "$0")"
CHART_VERSION=10.11.6
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update argo >/dev/null
helm upgrade --install argocd argo/argo-cd --version $CHART_VERSION \
  --kube-context $ctx -n argocd --create-namespace -f values.yaml -f values-$r.yaml --wait --timeout 15m
kubectl --context $ctx apply -f region-$r/app-of-apps.yaml
kubectl --context $ctx -n argocd get pods
echo "admin password: kubectl --context $ctx -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo "ui: kubectl --context $ctx port-forward svc/argocd-server -n argocd 8080:80  ->  http://localhost:8080"

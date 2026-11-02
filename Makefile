.PHONY: quota infra idle resume destroy argocd argocd-status frontdoor frontdoor-ui lockdown gate health tags test grafana-secret redeploy-all harbor-secret drill
quota:   ; @for r in polandcentral westeurope; do echo "== $$r"; az vm list-usage -l $$r -o table | grep -E "Total Regional vCPUs|Standard DSv5|Standard BS"; done
infra:   ; bash infra/azure/build.sh
idle:    ; bash infra/azure/scale.sh idle
resume:  ; bash infra/azure/scale.sh resume
destroy: ; bash infra/azure/destroy.sh
argocd:  ; bash platform/argocd/bootstrap.sh a && bash platform/argocd/bootstrap.sh b
argocd-status: ; @for c in pod-a-aks pod-b-aks; do echo "== $$c"; kubectl --context $$c -n argocd get applications; done
frontdoor: ; bash infra/azure/frontdoor.sh
gate:      ; bash tests/gate.sh
frontdoor-ui: ; bash infra/azure/frontdoor-ui.sh all
lockdown:  ; bash infra/azure/lockdown.sh
tags:      ; bash infra/azure/tags.sh
health:    ; bash tests/health.sh
test:      ; bash tests/pod-$(POD).sh          # make test POD=7.1
grafana-secret: ; bash platform/observability/grafana-secret.sh
redeploy-all: ; bash tests/redeploy-all.sh      # after a gateway re-render: new revision of every API to its gateways
harbor-secret: ; bash platform/gateway/harbor-secret.sh
drill:     ; bash drills/$(D).sh                 # make drill D=controller-restart

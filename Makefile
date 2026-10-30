.PHONY: quota infra idle resume destroy argocd argocd-status frontdoor gate
quota:   ; @for r in polandcentral westeurope; do echo "== $$r"; az vm list-usage -l $$r -o table | grep -E "Total Regional vCPUs|Standard DSv5|Standard BS"; done
infra:   ; bash infra/azure/build.sh
idle:    ; bash infra/azure/scale.sh idle
resume:  ; bash infra/azure/scale.sh resume
destroy: ; bash infra/azure/destroy.sh
argocd:  ; bash platform/argocd/bootstrap.sh a && bash platform/argocd/bootstrap.sh b
argocd-status: ; @for c in pod-a-aks pod-b-aks; do echo "== $$c"; kubectl --context $$c -n argocd get applications; done
frontdoor: ; bash infra/azure/frontdoor.sh
gate:      ; bash tests/gate.sh

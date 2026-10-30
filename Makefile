.PHONY: quota infra idle resume destroy
quota:   ; @for r in polandcentral westeurope; do echo "== $$r"; az vm list-usage -l $$r -o table | grep -E "Total Regional vCPUs|Standard DSv5|Standard BS"; done
infra:   ; bash infra/azure/build.sh
idle:    ; bash infra/azure/scale.sh idle
resume:  ; bash infra/azure/scale.sh resume
destroy: ; bash infra/azure/destroy.sh

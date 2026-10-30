#!/usr/bin/env bash
# Front Door endpoints for the UIs: pod-cp (API Manager portals + region A Argo CD) and pod-ops-b (region B Argo CD).
# Origins are the ingress controllers' cloudapp names with Let's Encrypt certificates (HTTPS 443, name check on).
# Step 1 (endpoints only) runs before the in-cluster config, because API Manager's hostname must be the endpoint host.
# Rerunnable.
set -euo pipefail
cd "$(dirname "$0")" && source ./env.sh
exists(){ az "$@" >/dev/null 2>&1; }
STEP=${1:-endpoints}
for ep in pod-cp pod-ops-b; do
  exists afd endpoint show -g $RG --profile-name pod-afd --endpoint-name $ep || az afd endpoint create -g $RG --profile-name pod-afd --endpoint-name $ep --enabled-state Enabled -o none
  echo "$ep: https://$(az afd endpoint show -g $RG --profile-name pod-afd --endpoint-name $ep --query hostName -o tsv)"
done
[ "$STEP" = endpoints ] && exit 0

# Step 2: origin groups, origins, routes, WAF (run after the ingress certificates are issued)
ORIGIN_A=pod-a-alior.polandcentral.cloudapp.azure.com; ORIGIN_B=pod-b-alior.westeurope.cloudapp.azure.com
HOST_CP=$(az afd endpoint show -g $RG --profile-name pod-afd --endpoint-name pod-cp --query hostName -o tsv)
HOST_OPSB=$(az afd endpoint show -g $RG --profile-name pod-afd --endpoint-name pod-ops-b --query hostName -o tsv)
og(){ # name origin-fqdn host-header   (probe: GET /argocd/ answers 200 on both endpoints' hosts)
  exists afd origin-group show -g $RG --profile-name pod-afd --origin-group-name $1 || az afd origin-group create -g $RG --profile-name pod-afd --origin-group-name $1 \
    --probe-request-type GET --probe-protocol Https --probe-interval-in-seconds 60 --probe-path /argocd/ \
    --sample-size 4 --successful-samples-required 3 --additional-latency-in-milliseconds 50 -o none
  exists afd origin show -g $RG --profile-name pod-afd --origin-group-name $1 --origin-name main || az afd origin create -g $RG --profile-name pod-afd --origin-group-name $1 --origin-name main \
    --host-name $2 --origin-host-header $3 --http-port 80 --https-port 443 --priority 1 --weight 1000 --enabled-state Enabled --enforce-certificate-name-check true -o none
}
og ingress-a $ORIGIN_A $HOST_CP
og ingress-b $ORIGIN_B $HOST_OPSB
route(){ # endpoint route origin-group pattern
  exists afd route show -g $RG --profile-name pod-afd --endpoint-name $1 --route-name $2 || az afd route create -g $RG --profile-name pod-afd --endpoint-name $1 --route-name $2 \
    --origin-group $3 --supported-protocols Http Https --forwarding-protocol HttpsOnly --https-redirect Enabled --link-to-default-domain Enabled --patterns-to-match "$4" -o none
}
route pod-cp all ingress-a "/*"
route pod-ops-b all ingress-b "/*"
# WAF for the UIs starts in Detection: managed rules often false-positive on portal API calls; switch to Prevention after a demo pass
exists network front-door waf-policy show -g $RG -n podwafui || az network front-door waf-policy create -g $RG -n podwafui --sku Premium_AzureFrontDoor --mode Detection --tags $TAGS -o none
az network front-door waf-policy managed-rules add -g $RG --policy-name podwafui --type Microsoft_DefaultRuleSet --version 2.1 --action Log -o none 2>/dev/null || true
WAF_ID=$(az network front-door waf-policy show -g $RG -n podwafui --query id -o tsv)
EPS=$(az afd endpoint show -g $RG --profile-name pod-afd --endpoint-name pod-cp --query id -o tsv),$(az afd endpoint show -g $RG --profile-name pod-afd --endpoint-name pod-ops-b --query id -o tsv)
exists afd security-policy show -g $RG --profile-name pod-afd --security-policy-name waf-ui || az afd security-policy create -g $RG --profile-name pod-afd --security-policy-name waf-ui --domains ${EPS//,/ } --waf-policy $WAF_ID -o none
echo "control plane: https://$HOST_CP/publisher   argo A: https://$HOST_CP/argocd   argo B: https://$HOST_OPSB/argocd"

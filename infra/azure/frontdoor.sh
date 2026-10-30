#!/usr/bin/env bash
# Front Door Premium + WAF in front of both gateway runtimes (active-active). Run once the gateway LoadBalancer
# services have public IPs; rerunnable. Bills about 330 USD/month from creation (CLAUDE.md: delete between demo weeks).
set -euo pipefail
cd "$(dirname "$0")" && source ./env.sh
exists(){ az "$@" >/dev/null 2>&1; }
ip(){ kubectl --context pod-$1-aks -n wso2-gw get svc -l app.kubernetes.io/component=gateway-runtime -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null; }
IP_A=$(ip a); IP_B=$(ip b)
[ -n "$IP_A" ] && [ -n "$IP_B" ] || { echo "gateway public IPs not ready yet (a='$IP_A' b='$IP_B')"; exit 1; }
echo "origins: region A $IP_A, region B $IP_B"

exists afd profile show -g $RG --profile-name pod-afd || az afd profile create -g $RG --profile-name pod-afd --sku Premium_AzureFrontDoor --tags $TAGS -o none
exists afd endpoint show -g $RG --profile-name pod-afd --endpoint-name pod-api || az afd endpoint create -g $RG --profile-name pod-afd --endpoint-name pod-api --enabled-state Enabled -o none
# health probe: the runtime's readiness path, HTTPS on 8443, both regions in one group with equal weight (active-active)
exists afd origin-group show -g $RG --profile-name pod-afd --origin-group-name gateways || az afd origin-group create -g $RG --profile-name pod-afd --origin-group-name gateways \
  --probe-request-type GET --probe-protocol Https --probe-interval-in-seconds 30 --probe-path /_gateway-health/ready \
  --sample-size 4 --successful-samples-required 3 --additional-latency-in-milliseconds 50 -o none
for r in a b; do v=IP_$(echo $r | tr a-z A-Z); IP=${!v}
  if exists afd origin show -g $RG --profile-name pod-afd --origin-group-name gateways --origin-name region-$r; then
    az afd origin update -g $RG --profile-name pod-afd --origin-group-name gateways --origin-name region-$r --host-name $IP --origin-host-header $IP -o none
  else
    az afd origin create -g $RG --profile-name pod-afd --origin-group-name gateways --origin-name region-$r \
      --host-name $IP --origin-host-header $IP --http-port 8080 --https-port 8443 --priority 1 --weight 500 \
      --enabled-state Enabled --enable-certificate-name-check false -o none
  fi
done
exists afd route show -g $RG --profile-name pod-afd --endpoint-name pod-api --route-name all || az afd route create -g $RG --profile-name pod-afd --endpoint-name pod-api --route-name all \
  --origin-group gateways --supported-protocols Http Https --forwarding-protocol HttpsOnly --https-redirect Enabled \
  --link-to-default-domain Enabled --patterns-to-match "/*" -o none

# WAF: managed OWASP rule set in prevention mode (PoD 1.3) + bot manager (PoD 11.3.1)
exists network front-door waf-policy show -g $RG -n podwaf || az network front-door waf-policy create -g $RG -n podwaf --sku Premium_AzureFrontDoor --mode Prevention --tags $TAGS -o none
exists network front-door waf-policy managed-rules list -g $RG --policy-name podwaf --query "[?ruleSetType=='Microsoft_DefaultRuleSet']" -o tsv || true
az network front-door waf-policy managed-rules add -g $RG --policy-name podwaf --type Microsoft_DefaultRuleSet --version 2.1 --action Block -o none 2>/dev/null || true
az network front-door waf-policy managed-rules add -g $RG --policy-name podwaf --type Microsoft_BotManagerRuleSet --version 1.1 -o none 2>/dev/null || true
WAF_ID=$(az network front-door waf-policy show -g $RG -n podwaf --query id -o tsv)
EP_ID=$(az afd endpoint show -g $RG --profile-name pod-afd --endpoint-name pod-api --query id -o tsv)
exists afd security-policy show -g $RG --profile-name pod-afd --security-policy-name waf || az afd security-policy create -g $RG --profile-name pod-afd --security-policy-name waf --domains $EP_ID --waf-policy $WAF_ID -o none

HOST=$(az afd endpoint show -g $RG --profile-name pod-afd --endpoint-name pod-api --query hostName -o tsv)
echo "front door: https://$HOST  (propagation takes a few minutes)"

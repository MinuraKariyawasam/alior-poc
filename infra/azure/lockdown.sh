#!/usr/bin/env bash
# Restricts the public entry points to Azure Front Door. Adds NSG rules (priority 300, above AKS's own 500 rules) on
# each cluster's node NSG: gateway ports 8080/8443 and ingress 443 allowed only from the AzureFrontDoor.Backend
# service tag; ingress port 80 stays open to the Internet for Let's Encrypt HTTP-01; everything else on those IPs denied.
# Rerunnable. Undo: delete the rules named afd-* (AKS rules remain).
set -euo pipefail
cd "$(dirname "$0")" && source ./env.sh
for r in a b; do
  c=pod-$r-aks
  MC=$(az aks show -g $RG -n $c --query nodeResourceGroup -o tsv)
  NSG=$(az network nsg list -g $MC --query "[0].name" -o tsv)
  GW_IP=$(kubectl --context $c -n wso2-gw get svc -l app.kubernetes.io/component=gateway-runtime -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')
  ING_IP=$(az network public-ip show -g $RG -n pod-$r-ingress-ip --query ipAddress -o tsv)
  rule(){ # name prio access src dstip ports
    az network nsg rule show -g $MC --nsg-name $NSG -n $1 -o none 2>/dev/null && \
      az network nsg rule update -g $MC --nsg-name $NSG -n $1 --priority $2 --access $3 --source-address-prefixes "$4" --destination-address-prefixes $5 --destination-port-ranges $6 --protocol Tcp --direction Inbound -o none || \
      az network nsg rule create -g $MC --nsg-name $NSG -n $1 --priority $2 --access $3 --source-address-prefixes "$4" --destination-address-prefixes $5 --destination-port-ranges $6 --protocol Tcp --direction Inbound -o none
  }
  rule afd-gateway-allow 300 Allow AzureFrontDoor.Backend $GW_IP "8080 8443"
  rule afd-gateway-deny  310 Deny  Internet              $GW_IP "8080 8443 9003"
  rule afd-ingress-allow 320 Allow AzureFrontDoor.Backend $ING_IP 443
  rule acme-ingress-allow 330 Allow Internet             $ING_IP 80
  rule afd-ingress-deny  340 Deny  Internet              $ING_IP 443
  echo "$c: gateway $GW_IP and ingress $ING_IP locked to Front Door (80 open for ACME)"
done

#!/usr/bin/env bash
# Builds the Alior PoD Azure environment per docs/cluster-spec.md. Rerunnable: each step skips what exists.
# Front Door is NOT created here; run frontdoor.sh once both gateways have public IPs.
set -euo pipefail
cd "$(dirname "$0")" && source ./env.sh
az account set -s "$SUB"
log(){ printf '\n[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
exists(){ az "$@" >/dev/null 2>&1; }

log "network"
exists network vnet show -g $RG -n pod-a-vnet || az network vnet create -g $RG -n pod-a-vnet -l $LOC_A --address-prefixes 10.10.0.0/16 --subnet-name aks --subnet-prefixes 10.10.0.0/20 --tags $TAGS -o none
exists network vnet show -g $RG -n pod-b-vnet || az network vnet create -g $RG -n pod-b-vnet -l $LOC_B --address-prefixes 10.20.0.0/16 --subnet-name aks --subnet-prefixes 10.20.0.0/20 --tags $TAGS -o none
exists network vnet subnet show -g $RG --vnet-name pod-b-vnet -n vm || az network vnet subnet create -g $RG --vnet-name pod-b-vnet -n vm --address-prefixes 10.20.16.0/24 -o none
exists network vnet peering show -g $RG --vnet-name pod-a-vnet -n a-to-b || az network vnet peering create -g $RG -n a-to-b --vnet-name pod-a-vnet --remote-vnet pod-b-vnet --allow-vnet-access -o none
exists network vnet peering show -g $RG --vnet-name pod-b-vnet -n b-to-a || az network vnet peering create -g $RG -n b-to-a --vnet-name pod-b-vnet --remote-vnet pod-a-vnet --allow-vnet-access -o none

log "registry, key vault, storage"
exists acr show -g $RG -n $ACR || az acr create -g $RG -n $ACR -l $LOC_A --sku Basic --tags $TAGS -o none
exists keyvault show -g $RG -n $KV || az keyvault create -g $RG -n $KV -l $LOC_A --enable-rbac-authorization true --tags $TAGS -o none
exists storage account show -g $RG -n $SA || az storage account create -g $RG -n $SA -l $LOC_A --sku Standard_LRS --allow-blob-public-access false --tags $TAGS -o none

log "aks clusters (control planes, in parallel)"
SUBNET_A=$(az network vnet subnet show -g $RG --vnet-name pod-a-vnet -n aks --query id -o tsv)
SUBNET_B=$(az network vnet subnet show -g $RG --vnet-name pod-b-vnet -n aks --query id -o tsv)
mk_aks(){ # name loc subnet
  exists aks show -g $RG -n $1 || az aks create -g $RG -n $1 -l $2 --tier free --kubernetes-version $K8S \
    --network-plugin azure --network-plugin-mode overlay --vnet-subnet-id $3 \
    --nodepool-name system --node-count 1 --node-vm-size Standard_B2s \
    --enable-managed-identity --generate-ssh-keys --tags $TAGS --no-wait -o none
}
mk_aks pod-a-aks $LOC_A $SUBNET_A
mk_aks pod-b-aks $LOC_B $SUBNET_B
az aks wait -g $RG -n pod-a-aks --created --interval 30 --timeout 1800
az aks wait -g $RG -n pod-b-aks --created --interval 30 --timeout 1800

log "node pools"
mk_pool(){ # cluster name max extra...
  local c=$1 n=$2 max=$3; shift 3
  exists aks nodepool show -g $RG --cluster-name $c -n $n || az aks nodepool add -g $RG --cluster-name $c -n $n \
    --node-count 1 --node-vm-size Standard_D4s_v5 --enable-cluster-autoscaler --min-count 0 --max-count $max \
    --labels pool=$n --tags $TAGS "$@" -o none
}
mk_pool pod-a-aks wso2cp 1 --node-taints wso2cp=true:NoSchedule
mk_pool pod-a-aks work 3
mk_pool pod-b-aks work 2

log "key vault csi add-on (secrets from pod-kv-alior into pods, no secrets in git)"
for c in pod-a-aks pod-b-aks; do
  az aks addon show -g $RG -n $c -a azure-keyvault-secrets-provider -o none 2>/dev/null || \
    az aks enable-addons -g $RG -n $c -a azure-keyvault-secrets-provider --enable-secret-rotation -o none
done

log "attach acr"
az aks update -g $RG -n pod-a-aks --attach-acr $ACR -o none
az aks update -g $RG -n pod-b-aks --attach-acr $ACR -o none

log "postgres for apim: on a small VM in region A (Azure Flexible Server is refused in polandcentral on this subscription)"
exists network vnet subnet show -g $RG --vnet-name pod-a-vnet -n vm || az network vnet subnet create -g $RG --vnet-name pod-a-vnet -n vm --address-prefixes 10.10.17.0/24 -o none
exists vm show -g $RG -n pod-a-db || az vm create -g $RG -n pod-a-db -l $LOC_A --image Ubuntu2404 --size Standard_B1ms \
  --vnet-name pod-a-vnet --subnet vm --public-ip-address "" --os-disk-size-gb 30 --storage-sku StandardSSD_LRS \
  --admin-username azureuser --generate-ssh-keys --tags $TAGS -o none
if ! az keyvault secret show --vault-name $KV -n pod-a-db-apim -o none 2>/dev/null; then
  PGPASS=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)
  KVID=$(az keyvault show -g $RG -n $KV --query id -o tsv)
  ME=$(az ad signed-in-user show --query id -o tsv)
  az role assignment create --role "Key Vault Secrets Officer" --assignee-object-id $ME --assignee-principal-type User --scope $KVID -o none 2>/dev/null || true
  for i in $(seq 1 12); do az keyvault secret set --vault-name $KV -n pod-a-db-apim --value "$PGPASS" -o none 2>/dev/null && break || sleep 15; done
else
  PGPASS=$(az keyvault secret show --vault-name $KV -n pod-a-db-apim --query value -o tsv)
fi
# run-command uses /bin/sh; ship the script base64-encoded and run it with bash
az vm run-command invoke -g $RG -n pod-a-db --command-id RunShellScript \
  --scripts "echo $(base64 < pg-on-vm.sh | tr -d '\n') | base64 -d > /tmp/pg.sh && PGPASS='$PGPASS' bash /tmp/pg.sh && rm -f /tmp/pg.sh" \
  --query "value[0].message" -o tsv | tail -5
unset PGPASS

log "apim admin password in key vault (consumed by the chart via existingSecret)"
az keyvault secret show --vault-name $KV -n apim-admin-password -o none 2>/dev/null || \
  az keyvault secret set --vault-name $KV -n apim-admin-password --value "$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-20)" -o none

log "legacy backend vm (region B, private only)"
exists vm show -g $RG -n pod-b-vm || az vm create -g $RG -n pod-b-vm -l $LOC_B --image Ubuntu2404 --size Standard_B1ms \
  --vnet-name pod-b-vnet --subnet vm --public-ip-address "" --os-disk-size-gb 30 --storage-sku StandardSSD_LRS \
  --admin-username azureuser --generate-ssh-keys --tags $TAGS -o none

log "done"
az resource list -g $RG --query "[].{name:name,type:type,location:location}" -o table

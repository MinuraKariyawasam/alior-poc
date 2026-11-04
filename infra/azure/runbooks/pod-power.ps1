# Azure Automation runbook (PowerShell 5.1, no modules): stop or start the whole Alior PoD compute.
# Uses the account's system-assigned managed identity through the sandbox identity endpoint and plain ARM REST.
# Same order as infra/azure/power.sh: stop = AKS then VMs; start = VMs (Postgres first) then AKS.
param([Parameter(Mandatory=$true)][ValidateSet("stop","start")][string]$Action)
$ErrorActionPreference = "Stop"
$sub = "SUBSCRIPTION_ID"; $rg = "RESOURCE_GROUP"
$aks = @("pod-a-aks","pod-b-aks"); $vms = @("pod-a-db","pod-b-vm")
$tok = (Invoke-RestMethod -Method Get -Uri "$($env:IDENTITY_ENDPOINT)?resource=https://management.azure.com/&api-version=2019-08-01" -Headers @{ "X-IDENTITY-HEADER" = $env:IDENTITY_HEADER }).access_token
$h = @{ Authorization = "Bearer $tok" }
function Post($path) {
  $r = Invoke-WebRequest -Method Post -Uri "https://management.azure.com$path" -Headers $h -ContentType "application/json" -UseBasicParsing
  Write-Output ("{0} -> {1}" -f $path, $r.StatusCode)
}
$aksOp = @{ stop = "stop"; start = "start" }[$Action]
$vmOp  = @{ stop = "deallocate"; start = "start" }[$Action]
if ($Action -eq "stop") {
  foreach ($c in $aks) { Post "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.ContainerService/managedClusters/$c/$aksOp?api-version=AKS_API" }
  foreach ($v in $vms) { Post "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Compute/virtualMachines/$v/$vmOp?api-version=VM_API" }
} else {
  foreach ($v in $vms) { Post "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Compute/virtualMachines/$v/$vmOp?api-version=VM_API" }
  Start-Sleep -Seconds 60   # let Postgres come up before APIM's pods are scheduled
  foreach ($c in $aks) { Post "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.ContainerService/managedClusters/$c/$aksOp?api-version=AKS_API" }
}
Write-Output "pod-power $Action requested at $(Get-Date -Format u)"

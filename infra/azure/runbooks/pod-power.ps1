# Azure Automation runbook (PowerShell 5.1, no modules): stop or start the whole Alior PoD compute.
# Uses the account's system-assigned managed identity through the sandbox identity endpoint and plain ARM REST.
# Same order as infra/azure/power.sh: stop = AKS then VMs; start = VMs (Postgres first) then AKS.
param([Parameter(Mandatory=$true)][ValidateSet("stop","start")][string]$Action)
$ErrorActionPreference = "Stop"
$sub = "SUBSCRIPTION_ID"; $rg = "RESOURCE_GROUP"
$aks = @("pod-a-aks","pod-b-aks"); $vms = @("pod-a-db","pod-b-vm")
$tok = (Invoke-RestMethod -Method Get -Uri "$($env:IDENTITY_ENDPOINT)?resource=https://management.azure.com/&api-version=2019-08-01" -Headers @{ "X-IDENTITY-HEADER" = $env:IDENTITY_HEADER }).access_token
$h = @{ Authorization = "Bearer $tok" }
$failed = @()
function Post($path) {
  # Retry while Azure reports another operation in progress on the resource (409), up to 15 minutes; never stop the run.
  for ($i = 1; $i -le 15; $i++) {
    try {
      $r = Invoke-WebRequest -Method Post -Uri "https://management.azure.com$path" -Headers $h -ContentType "application/json" -UseBasicParsing
      Write-Output ("{0} -> {1}" -f $path, $r.StatusCode); return
    } catch {
      $msg = $_.Exception.Message
      if ($msg -match "409|Conflict|InProgress") { Write-Output ("{0} -> busy, retry {1}/15 in 60s" -f $path, $i); Start-Sleep -Seconds 60 }
      elseif ($msg -match "only allowed on a stopped cluster|already|PowerState") { Write-Output ("{0} -> already in the requested state" -f $path); return }
      else { Write-Output ("{0} -> ERROR {1}" -f $path, $msg); $script:failed += $path; return }
    }
  }
  Write-Output ("{0} -> gave up after 15 retries" -f $path); $script:failed += $path
}
$aksOp = @{ stop = "stop"; start = "start" }[$Action]
$vmOp  = @{ stop = "deallocate"; start = "start" }[$Action]
if ($Action -eq "stop") {
  foreach ($c in $aks) { Post "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.ContainerService/managedClusters/$c/${aksOp}?api-version=AKS_API" }
  foreach ($v in $vms) { Post "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Compute/virtualMachines/$v/${vmOp}?api-version=VM_API" }
} else {
  foreach ($v in $vms) { Post "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Compute/virtualMachines/$v/${vmOp}?api-version=VM_API" }
  Start-Sleep -Seconds 60   # let Postgres come up before APIM's pods are scheduled
  foreach ($c in $aks) { Post "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.ContainerService/managedClusters/$c/${aksOp}?api-version=AKS_API" }
}
Write-Output "pod-power $Action requested at $(Get-Date -Format u)"
if ($failed.Count -gt 0) { throw ("failed: " + ($failed -join ", ")) }

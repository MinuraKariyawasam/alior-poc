# Azure Automation runbook (PowerShell 5.1, no modules): stop or start the whole Alior PoD compute.
# Uses the account's system-assigned managed identity through the sandbox identity endpoint and plain ARM REST.
# Same order as infra/azure/power.sh: stop = AKS then VMs; start = VMs (Postgres first) then AKS.
# AKS calls use the same API version as the az CLI (aks-preview): on 2026-11-05 the GA 2026-09-01 version answered
# "start is only allowed on a stopped cluster" for clusters the CLI had stopped, while the CLI's version worked.
param([Parameter(Mandatory=$true)][ValidateSet("stop","start")][string]$Action)
$ErrorActionPreference = "Stop"
$sub = "SUBSCRIPTION_ID"; $rg = "RESOURCE_GROUP"
$aks = @("pod-a-aks","pod-b-aks"); $vms = @("pod-a-db","pod-b-vm")
$tok = (Invoke-RestMethod -Method Get -Uri "$($env:IDENTITY_ENDPOINT)?resource=https://management.azure.com/&api-version=2019-08-01" -Headers @{ "X-IDENTITY-HEADER" = $env:IDENTITY_HEADER }).access_token
$h = @{ Authorization = "Bearer $tok" }
$failed = @()
function Body($e) { try { $sr = New-Object IO.StreamReader($e.Exception.Response.GetResponseStream()); $sr.ReadToEnd() } catch { "" } }
function AksPower($name) {   # current powerState.code of a cluster, same API version as the start/stop calls
  try { (Invoke-RestMethod -Method Get -Uri "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.ContainerService/managedClusters/$name`?api-version=AKS_API" -Headers $h).properties.powerState.code } catch { "unknown" }
}
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
      else { Write-Output ("{0} -> ERROR {1} {2}" -f $path, $msg, (Body $_)); $script:failed += $path; return }
    }
  }
  Write-Output ("{0} -> gave up after 15 retries" -f $path); $script:failed += $path
}
$aksOp = @{ stop = "stop"; start = "start" }[$Action]
$vmOp  = @{ stop = "deallocate"; start = "start" }[$Action]
$want = @{ stop = "Stopped"; start = "Running" }[$Action]
function AksAction($c) {
  $p = AksPower $c
  if ($p -eq $want) { Write-Output ("{0}: already {1}" -f $c, $p); return }
  Post "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.ContainerService/managedClusters/$c/${aksOp}?api-version=AKS_API"
}
if ($Action -eq "stop") {
  foreach ($c in $aks) { AksAction $c }
  foreach ($v in $vms) { Post "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Compute/virtualMachines/$v/${vmOp}?api-version=VM_API" }
} else {
  foreach ($v in $vms) { Post "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Compute/virtualMachines/$v/${vmOp}?api-version=VM_API" }
  Start-Sleep -Seconds 60   # let Postgres come up before APIM's pods are scheduled
  foreach ($c in $aks) { AksAction $c }
}
Write-Output "pod-power $Action requested at $(Get-Date -Format u)"
if ($failed.Count -gt 0) { throw ("failed: " + ($failed -join ", ")) }

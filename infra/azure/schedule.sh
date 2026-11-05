#!/usr/bin/env bash
# Office-hours schedule for the whole PoD (decided 2026-11-04): start 09:00, stop 17:00, Monday to Friday, off at weekends.
# Azure Automation account pod-automation in the resource group, system-assigned identity with Contributor on the RG,
# one runbook (runbooks/pod-power.ps1, plain ARM REST, no modules) linked to two weekly schedules. Rerunnable.
# Time zone: TZ below (IANA). az CLI's automation extension is experimental and cannot link schedules, so this uses az rest.
set -euo pipefail
cd "$(dirname "$0")" && source ./env.sh
TZ_NAME=${TZ_NAME:-Asia/Colombo}; START_AT=${START_AT:-09:00}; STOP_AT=${STOP_AT:-17:00}
AA=pod-automation; LOC=$LOC_A; API=2024-10-23; AKS_API=${AKS_API:-2026-04-02-preview}; VM_API=${VM_API:-2026-04-01}
SUBID=$(az account show --query id -o tsv)
BASE="https://management.azure.com/subscriptions/$SUBID/resourceGroups/$RG/providers/Microsoft.Automation/automationAccounts/$AA"
tagsjson=$(python3 -c 'import sys,json; print(json.dumps(dict(kv.split("=",1) for kv in sys.argv[1].split())))' "$TAGS")

echo "== automation account $AA ($LOC)"
az rest --method put --uri "$BASE?api-version=$API" --body "{\"location\":\"$LOC\",\"tags\":$tagsjson,\"identity\":{\"type\":\"SystemAssigned\"},\"properties\":{\"sku\":{\"name\":\"Basic\"}}}" -o none
PRINCIPAL=$(az rest --method get --uri "$BASE?api-version=$API" --query identity.principalId -o tsv)
az role assignment create --assignee-object-id "$PRINCIPAL" --assignee-principal-type ServicePrincipal --role Contributor --scope "/subscriptions/$SUBID/resourceGroups/$RG" -o none 2>/dev/null && echo "Contributor on $RG granted to the account identity" || echo "role assignment already present"

echo "== runbook pod-power"
sed -e "s/SUBSCRIPTION_ID/$SUBID/; s/RESOURCE_GROUP/$RG/; s/AKS_API/$AKS_API/g; s/VM_API/$VM_API/g" runbooks/pod-power.ps1 > /tmp/claude-501/pod-power.ps1
az rest --method put --uri "$BASE/runbooks/pod-power?api-version=$API" --body "{\"location\":\"$LOC\",\"properties\":{\"runbookType\":\"PowerShell\",\"logProgress\":false,\"logVerbose\":false,\"description\":\"stop/start the whole PoD; source infra/azure/runbooks/pod-power.ps1\"}}" -o none
az rest --method put --uri "$BASE/runbooks/pod-power/draft/content?api-version=$API" --headers "Content-Type=text/powershell" --body @/tmp/claude-501/pod-power.ps1 -o none
az rest --method post --uri "$BASE/runbooks/pod-power/publish?api-version=$API" -o none && echo "published"

next_weekday(){ python3 -c '
import datetime,sys; h,m=map(int,sys.argv[1].split(":")); off=sys.argv[2]
d=datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=int(off[:3]),minutes=int(off[0]+off[4:6]))))
t=d.replace(hour=h,minute=m,second=0,microsecond=0)
if t<=d+datetime.timedelta(minutes=6): t+=datetime.timedelta(days=1)
while t.weekday()>4: t+=datetime.timedelta(days=1)
print(t.isoformat())' "$1" "$2"; }
OFF=$(TZ=$TZ_NAME date +%z | sed 's/\(...\)\(..\)/\1:\2/')   # e.g. +05:30
for s in "pod-start:$START_AT:start" "pod-stop:$STOP_AT:stop"; do
  name=${s%%:*}; rest=${s#*:}; at=${rest%:*}; action=${rest##*:}
  echo "== schedule $name at $at $TZ_NAME, Mon-Fri -> runbook pod-power -Action $action"
  az rest --method put --uri "$BASE/schedules/$name?api-version=$API" --body "{\"name\":\"$name\",\"properties\":{\"description\":\"PoD $action, weekdays $at $TZ_NAME\",\"startTime\":\"$(next_weekday "$at" "$OFF")\",\"frequency\":\"Week\",\"interval\":1,\"timeZone\":\"$TZ_NAME\",\"advancedSchedule\":{\"weekDays\":[\"Monday\",\"Tuesday\",\"Wednesday\",\"Thursday\",\"Friday\"]}}}" -o none
  JSID=$(python3 -c 'import uuid,sys; print(uuid.uuid5(uuid.NAMESPACE_URL, "alior-poc/"+sys.argv[1]))' "$name")
  if ! az rest --method get --uri "$BASE/jobSchedules/$JSID?api-version=$API" -o none 2>/dev/null; then
    az rest --method put --uri "$BASE/jobSchedules/$JSID?api-version=$API" --body "{\"properties\":{\"schedule\":{\"name\":\"$name\"},\"runbook\":{\"name\":\"pod-power\"},\"parameters\":{\"Action\":\"$action\"}}}" -o none && echo "linked"
  else echo "already linked"; fi
done
echo "== schedules"; az rest --method get --uri "$BASE/schedules?api-version=$API" --query "value[].{name:name,next:properties.nextRun,tz:properties.timeZone,enabled:properties.isEnabled}" -o table

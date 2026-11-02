#!/usr/bin/env bash
# After a gateway re-render (config-rev bump) the restarted controllers lose the deployed APIs until the control plane
# redeploys them (finding 2026-11-02). This creates a new revision of every Platform Gateway API and deploys it to the
# gateways it was deployed to. Rerunnable.
set -uo pipefail
cd "$(dirname "$0")/.." ; source infra/azure/env.sh; source tests/lib/cp.sh
cp_connect 19449 || exit 1; trap 'kill $CP_PF 2>/dev/null' EXIT
for ID in $(api "$PUB/apis?limit=100" | j 'print(" ".join(a["id"] for a in d.get("list",[]) if a.get("gatewayType")=="APIPlatform"))'); do
  name=$(api "$PUB/apis/$ID" | j 'print(d["name"]+" "+d["version"])')
  gws=$(api "$PUB/apis/$ID/deployments" | j 'print(" ".join(sorted(set(x["name"] for x in d))))')
  [ -z "$gws" ] && { echo "$name: not deployed anywhere, skipped"; continue; }
  for old in $(api "$PUB/apis/$ID/revisions?query=deployed:false" | j 'print(" ".join(r["id"] for r in d.get("list",[])[:-1]))'); do api -X DELETE "$PUB/apis/$ID/revisions/$old" -o /dev/null; done
  REV=$(api -X POST -H "Content-Type: application/json" "$PUB/apis/$ID/revisions" -d '{"description":"redeploy-all '"$(date -u +%FT%TZ)"'"}' | j 'print(d.get("id") or sys.exit("revision failed: "+json.dumps(d)))')
  targets=""; for g in $gws; do targets+='{"name":"'$g'","vhost":"'$g'.alior-poc.local","displayOnDevportal":true},'; done
  api -X POST -H "Content-Type: application/json" "$PUB/apis/$ID/deploy-revision?revisionId=$REV" -d "[${targets%,}]" -o /dev/null -w "$name -> $gws: %{http_code}\n"
done

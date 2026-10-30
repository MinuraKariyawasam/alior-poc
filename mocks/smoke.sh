#!/usr/bin/env bash
# Replays every mock call and prints request, status, time and body.
#   ./smoke.sh                 -> localhost (start mock.py --port 8081/8082/8083 first)
#   ./smoke.sh 10.20.16.4      -> pod-b-vm from inside the VNet
# Exits non-zero if any expected status is not met.
set -u
H=${1:-localhost}; D=$(cd "$(dirname "$0")" && pwd); fail=0
call(){ # expected method port path [curl args...]
  local want=$1 m=$2 port=$3 path=$4; shift 4
  echo; echo "### $m http://$H:$port$path $*"
  local out; out=$(curl -s -m 10 -X "$m" "$@" -w '\n%{http_code} %{time_total}s' "http://$H:$port$path")
  local body=${out%$'\n'*} meta=${out##*$'\n'}
  echo "-> ${meta}"; echo "$body"
  [ "${meta%% *}" = "$want" ] || { echo "!! expected $want"; fail=1; }
}
call 200 GET  8081 /accounts
call 200 GET  8082 /accounts
call 200 GET  8083 /legacy/accounts
call 200 POST 8081 /transfers         -H 'content-type: application/json' --data @"$D/payloads/transfer.json"
call 200 POST 8081 /transfers/instant -H 'content-type: application/json' --data @"$D/payloads/transfer-instant.json"
call 200 GET  8081 /accounts          -H 'x-mock-delay-ms: 300'
call 503 GET  8082 /transfers         -H 'x-mock-status: 503'
call 429 POST 8081 /transfers         -H 'x-mock-status: 429' --data @"$D/payloads/transfer.json"
call 404 GET  8081 /nope
call 200 GET  8083 /healthz
echo; [ $fail = 0 ] && echo "ALL OK" || { echo "FAILURES"; exit 1; }

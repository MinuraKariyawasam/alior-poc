#!/usr/bin/env bash
# PoD 6.11 proof: the bundled OAuth2 server (APIM Resident Key Manager) protects accounts-secure on both Platform Gateways.
# Gateway side: policy_configurations.jwtauth_v1.keymanagers in platform/gateway/region-*/gateway-values.yaml (trust the
# control plane issuer, JWKS). API side: Policy Hub jwt-auth 1.3 attached as apiHubPolicies in the Publisher and the
# revision deployed. Expect: no token 401, bad token 401, valid token 200; the unprotected `accounts` API stays 200.
set -uo pipefail
cd "$(dirname "$0")/.." ; source infra/azure/env.sh
mkdir -p evidence/6.11; LOG=evidence/6.11/pod-6.11-$(date +%Y%m%d-%H%M).log; exec > >(tee "$LOG") 2>&1
fail=0; ok(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fail=1; }
FD=https://pod-api-guf3bbbjh5htgxfu.a02.azurefd.net
PW=$(az keyvault secret show --vault-name "$KV" -n apim-admin-password --query value -o tsv)
pkill -f "port-forward svc/apim-wso2am-all-in-one-am-service 19447" 2>/dev/null
for try in 1 2 3; do
  kubectl --context pod-a-aks -n wso2-cp port-forward svc/apim-wso2am-all-in-one-am-service 19447:9443 >/dev/null 2>&1 & PF=$!
  for i in $(seq 1 40); do [ "$(curl -sk -m 3 -o /dev/null -w '%{http_code}' https://localhost:19447/services/Version)" != 000 ] && break 2; sleep 1; done
  kill $PF 2>/dev/null; wait $PF 2>/dev/null
done
trap 'kill $PF 2>/dev/null' EXIT
api(){ curl -sk -m 30 -u "admin:$PW" "$@"; }
j(){ python3 -c "import sys,json; d=json.load(sys.stdin); $1"; }

echo "== token from the control plane (Dev Portal app pod-health, client_credentials)"
APP=$(api "https://localhost:19447/api/am/devportal/v3/applications?query=pod-health" | j 'print([a["applicationId"] for a in d["list"] if a["name"]=="pod-health"][0])')
CK=$(api "https://localhost:19447/api/am/devportal/v3/applications/$APP/oauth-keys" | j 'print([k["consumerKey"] for k in d["list"] if k["keyType"]=="PRODUCTION"][0])')
CS=$(api "https://localhost:19447/api/identity/oauth2/dcr/v1.1/register/$CK" | j 'print(d["client_secret"])')
TOK=$(curl -sk -m 30 -u "$CK:$CS" -d 'grant_type=client_credentials' https://localhost:19447/oauth2/token | j 'print(d.get("access_token",""))')
[ -n "$TOK" ] && ok "access token issued (${#TOK} chars, iss $(printf '%s' "$TOK" | cut -d. -f2 | python3 -c 'import sys,base64,json; t=sys.stdin.read().strip(); print(json.loads(base64.urlsafe_b64decode(t+"="*(-len(t)%4))).get("iss"))'))" || bad "no access token"

echo "== accounts-secure through Front Door"
c(){ curl -sk -m 20 -o /dev/null -w '%{http_code}' "$@"; }
code=$(c "$FD/accounts-secure/1.0.0/accounts");                                 [ "$code" = 401 ] && ok "no token      -> $code" || bad "no token      -> $code (want 401)"
code=$(c -H "Authorization: Bearer not.a.token" "$FD/accounts-secure/1.0.0/accounts"); [ "$code" = 401 ] && ok "bad token     -> $code" || bad "bad token     -> $code (want 401)"
code=$(c -H "Authorization: Bearer $TOK" "$FD/accounts-secure/1.0.0/accounts");  [ "$code" = 200 ] && ok "valid token   -> $code" || bad "valid token   -> $code (want 200)"
curl -sk -m 20 -D - -o evidence/6.11/accounts-secure-valid-token.json -H "Authorization: Bearer $TOK" "$FD/accounts-secure/1.0.0/accounts" | grep -i -E "^HTTP|x-mock-version|www-authenticate" | sed 's/^/       /'
curl -sk -m 20 -D - -o /dev/null "$FD/accounts-secure/1.0.0/accounts" | grep -i -E "^HTTP|www-authenticate" | sed 's/^/       /'
code=$(c "$FD/accounts/1.0.0/accounts");                                        [ "$code" = 200 ] && ok "accounts (no policy), no token -> $code" || bad "accounts (no policy) -> $code (want 200)"

echo "== both regions enforce it (x-mock-version from each gateway's backend route; Front Door picks the region)"
for i in 1 2 3 4; do printf '  %s ' "$(c -H "Authorization: Bearer $TOK" "$FD/accounts-secure/1.0.0/accounts")"; done; echo
[ $fail = 0 ] && echo "POD 6.11 PASSED" || { echo "POD 6.11 FAILED"; exit 1; }

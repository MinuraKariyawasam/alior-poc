#!/usr/bin/env bash
# Loads the APIM 4.7.0 PostgreSQL schema into apim and apim_shared on pod-a-db, as role apim.
# Re-running RESETS the databases (the scripts drop tables first).
set -euo pipefail
cd "$(dirname "$0")" && source ./env.sh
D=../platform/control-plane/dbscripts
B64=$(tar czf - -C "$D" shared_db.sql apim_db.sql | base64 | tr -d '\n')
az vm run-command invoke -g $RG -n pod-a-db --command-id RunShellScript --scripts "
set -e; T=\$(mktemp -d); echo $B64 | base64 -d | tar xzf - -C \$T; chown -R postgres \$T
sudo -u postgres psql -v ON_ERROR_STOP=1 -q -d apim_shared -c 'SET ROLE apim;' -f \$T/shared_db.sql
sudo -u postgres psql -v ON_ERROR_STOP=1 -q -d apim        -c 'SET ROLE apim;' -f \$T/apim_db.sql
for db in apim_shared apim; do printf '%s tables: ' \$db; sudo -u postgres psql -tAc \"select count(*) from pg_tables where schemaname='public'\" -d \$db; done
rm -rf \$T" --query "value[0].message" -o tsv | sed -n '/stdout/,/stderr/p'

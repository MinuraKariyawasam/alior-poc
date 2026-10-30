#!/usr/bin/env bash
# Runs ON pod-a-db via `az vm run-command invoke`. Installs PostgreSQL 16, opens it to both VNets,
# creates role+db "apim", and sets a nightly pg_dump. Expects $PGPASS in the environment.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq && apt-get install -y -qq postgresql-16 postgresql-client-16 >/dev/null
PGCONF=/etc/postgresql/16/main
sed -i "s/^#\?listen_addresses.*/listen_addresses = '*'/" $PGCONF/postgresql.conf
grep -q "10.10.0.0/16" $PGCONF/pg_hba.conf || cat >> $PGCONF/pg_hba.conf <<'HBA'
host    all    all    10.10.0.0/16    scram-sha-256
host    all    all    10.20.0.0/16    scram-sha-256
HBA
systemctl restart postgresql
sudo -u postgres psql -v ON_ERROR_STOP=1 -c "DO \$\$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='apim') THEN CREATE ROLE apim LOGIN PASSWORD '$PGPASS'; ELSE ALTER ROLE apim PASSWORD '$PGPASS'; END IF; END \$\$;"
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='apim'" | grep -q 1 || sudo -u postgres createdb -O apim apim
install -d -o postgres -g postgres /var/backups/pg
echo "15 2 * * * postgres pg_dump -Fc apim > /var/backups/pg/apim-\$(date +\%F).dump && find /var/backups/pg -mtime +7 -delete" > /etc/cron.d/pg-backup
systemctl enable --now postgresql
sudo -u postgres psql -tc "select version()"

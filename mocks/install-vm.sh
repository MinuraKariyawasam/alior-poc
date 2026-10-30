#!/usr/bin/env bash
# Runs ON pod-b-vm via az vm run-command. Installs /opt/mock/mock.py and three systemd services:
#   mock-v1 :8081 (version v1)   mock-v2 :8082 (version v2)   mock-legacy :8083 (version legacy, /legacy/accounts)
# Expects MOCK_B64 (base64 of mock.py) in the environment.
set -euo pipefail
install -d /opt/mock
echo "$MOCK_B64" | base64 -d > /opt/mock/mock.py && chmod 755 /opt/mock/mock.py
for svc in "v1 8081" "v2 8082" "legacy 8083"; do set -- $svc
cat > /etc/systemd/system/mock-$1.service <<UNIT
[Unit]
Description=PoD mock backend $1 on :$2
After=network.target
[Service]
ExecStart=/usr/bin/python3 /opt/mock/mock.py --port $2 --version $1
Restart=always
User=nobody
[Install]
WantedBy=multi-user.target
UNIT
done
systemctl daemon-reload
systemctl enable --now mock-v1 mock-v2 mock-legacy
sleep 1
for port in 8081 8082 8083; do curl -s -m 3 -H 'x-mock-delay-ms: 50' localhost:$port/accounts; echo; done
curl -s -m 3 -o /dev/null -w 'status override -> %{http_code}\n' -H 'x-mock-status: 503' localhost:8081/transfers/instant

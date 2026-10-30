# Mock backends

One stdlib Python script, `mock.py`, run three times on `pod-b-vm` (westeurope, private IP `10.20.16.4`):

| Service | Port | `version` in the response | Role |
|---|---|---|---|
| mock-v1 | 8081 | `v1` | current backend for `/transfers`, `/transfers/instant`, `/accounts` |
| mock-v2 | 8082 | `v2` | new version, target of weighted routing and mirroring (PoD 5.x) |
| mock-legacy | 8083 | `legacy` | the standalone backend behind `/legacy/accounts` (PoD 1.2) |

Every service answers every path on any method, so the gateway decides what is exposed. Unknown paths return 404.

Behaviour headers:

| Header | Effect |
|---|---|
| `x-mock-delay-ms: 300` | sleep 300 ms before answering |
| `x-mock-status: 503` | answer with that HTTP status |

Response headers: `content-type: application/json`, `x-mock-version: <v1|v2|legacy>`.

Response body:

```json
{"service": "mock", "version": "v1", "path": "/transfers", "method": "POST",
 "host": "pod-b-vm", "port": 8081, "body_bytes": 168,
 "body_md5": "…", "ts": "2026-10-30T08:54:08Z"}
```

`body_md5` is the MD5 of the request body, which is what the PoD 3 custom policy must compute too, so the two can be compared.

## Files

- `mock.py` the server
- `install-vm.sh` installs it on the VM as three systemd units (run through `az vm run-command`)
- `payloads/transfer.json`, `payloads/transfer-instant.json` sample request bodies
- `smoke.sh` replays every call below and fails if a status is wrong

## Run locally

```bash
python3 mock.py --port 8081 --version v1 &
python3 mock.py --port 8082 --version v2 &
python3 mock.py --port 8083 --version legacy &
./smoke.sh
```

## Deploy to the VM

```bash
B64=$(base64 < mock.py | tr -d '\n')
az vm run-command invoke -g rg-Alior-POC-minura -n pod-b-vm --command-id RunShellScript \
  --scripts "echo $(base64 < install-vm.sh | tr -d '\n') | base64 -d > /tmp/inst.sh && MOCK_B64='$B64' bash /tmp/inst.sh"
```

## The calls

Replace `H` with `localhost` for a local run or `10.20.16.4` from anything inside the VNets.

Current account list, v1:

```bash
curl -i http://$H:8081/accounts
```

Same path on v2 (the only difference is `version` and `port` in the body):

```bash
curl -i http://$H:8082/accounts
```

Legacy backend, PoD 1.2:

```bash
curl -i http://$H:8083/legacy/accounts
```

Create a transfer:

```bash
curl -i -X POST http://$H:8081/transfers \
  -H 'content-type: application/json' \
  --data @payloads/transfer.json
```

Instant transfer:

```bash
curl -i -X POST http://$H:8081/transfers/instant \
  -H 'content-type: application/json' \
  --data @payloads/transfer-instant.json
```

Slow backend, 300 ms, for timeout and circuit-breaker tests:

```bash
curl -i http://$H:8081/accounts -H 'x-mock-delay-ms: 300'
```

Failing backend, for outlier ejection and error policies:

```bash
curl -i http://$H:8082/transfers -H 'x-mock-status: 503'
```

Rate-limited backend response:

```bash
curl -i -X POST http://$H:8081/transfers -H 'x-mock-status: 429' --data @payloads/transfer.json
```

Unknown path:

```bash
curl -i http://$H:8081/nope
```

Health:

```bash
curl -i http://$H:8083/healthz
```

## Recorded responses

Filled in by running `smoke.sh` on the VM; see below.

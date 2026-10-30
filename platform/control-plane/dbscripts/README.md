# APIM 4.7.0 PostgreSQL schema

Taken verbatim from the `wso2/wso2am:4.7.0` image (`dbscripts/postgresql.sql` and `dbscripts/apimgt/postgresql.sql`) on 2026-10-30.

| File | Loads into | Owner |
|---|---|---|
| `shared_db.sql` | `apim_shared` (registry and user store) | `apim` |
| `apim_db.sql` | `apim` (API management) | `apim` |

Load with `infra/azure/apim-schema.sh` (runs on `pod-a-db` through `az vm run-command`). The scripts start with
`DROP TABLE IF EXISTS`, so re-running resets both databases.

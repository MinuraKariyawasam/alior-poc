# PoD 6.11: control plane tokens enforced on the Platform Gateways (done 2026-11-02)

The Platform Gateway is subscription-less: an API's `securityScheme` and tiers do nothing there. Access is enforced only by
Policy Hub policies attached in the Publisher. Two halves, two owners:

| Half | Owner | Where | Once or per API |
|---|---|---|---|
| Trust tokens issued by our control plane | infra engineer | `platform/gateway/region-*/gateway-values.yaml`, `gateway.config.policy_configurations.jwtauth_v1.keymanagers` (name `apim-resident`, issuer `https://am.wso2.com:443/oauth2/token`, JWKS `/oauth2/jwks` from the control plane service in A and over the peering in B, `skipTlsVerify` for the self-signed certificate). The chart renders it as `[[policy_configurations.jwtauth_v1.keymanagers]]` in config.toml. Rolled by Git → Argo CD → operator (`config-rev` bump). | once |
| Require a token on this API | API developer | Publisher → API → Policies → JWT Auth (Policy Hub `jwt-auth` 1.3), then a new revision deployed to both gateways. The REST equivalent is `PUT /apis/{id}` with `apiHubPolicies: [{"policyName":"jwt-auth","policyId":"jwt-auth::1.3","policyVersion":"1.3","parameters":{"issuers":["apim-resident"]}}]` plus `apiPolicies: {request:[],response:[],fault:[]}`; without `policyId` the Publisher answers 500 (NPE in `createPlaceholderPolicyDataForExternalPolicy`). The Publisher stores its own UUID as `policyId` afterwards. | per API |

Neither half is bottom-up: the API still comes from the control plane, the trust block is gateway setup like the control
plane address and token already in the same file.

Proof: `make test POD=6.11` (evidence/6.11). Result 2026-11-02: no token 401, bad token 401, valid Resident Key Manager
token 200 with `x-mock-version: v1`, the unprotected `accounts` API still 200, four consecutive calls through Front Door 200.

Notes:
- Whether APIM 4.7 can push the Resident Key Manager to Platform Gateways by itself was not verified (apim.docs.wso2.com
  blocks scripted access). With the trust block in place it works; revisit if WSO2 confirms automatic key manager sync.
- Re-rendering the gateways restarted the controllers, which again dropped the deployed APIs until `make gate` redeployed
  them (see docs/phase3-observability.md, finding).
- PoD 11.1.1 (Entra ID) is the same mechanism with a second entry in `keymanagers` (Entra issuer + JWKS) once the app
  registration from the WSO2 Digital team exists.

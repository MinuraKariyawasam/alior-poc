# STATUS

Source list: `docs/pod-checklist.tsv` (the bank's PoD sheet). Per-item guide (ask, status, how we do it here, proof): `docs/pod-guide.md`. Order of work: `docs/plan-next.md`. States: Not started / In progress / Done / Blocked / Slide. Updated whenever a task changes state (ground rule 8).
Base platform (phases 1 to 3) is up: `make health`, `make gate`, `make test POD=7.1`, `make test POD=6.11`. PoD 9, 13 and 14 use existing demo environments (out of scope for this repo).

| PoD | Item | Mode | State | Proof / note |
|---|---|---|---|---|
| **1** | **Architecture in Practice** | Evidence-Based Presentation | | Evidence + live |
| 1.1 | Deploying the solution on a Kubernetes (K8s) cluster and controlling API calls between applications running within that cluster. | | Not started |  |
| 1.2 | Deploying the solution on a separate, dedicated Kubernetes (K8s) cluster (or virtual machines) and controlling API calls originating from untrusted zones and targeting API endpoints hosted on another K8s cluster or on standalone systems (e.g. VMs or appliances). | | Not started |  |
| 1.3 | When exposing services to untrusted zones (e.g. the Internet), the ability to protect lower-layer protocols, e.g. TCP/IP using an external IPS/anti-DDoS solution, or HTTP using an external or built-in WAF. | | Done | WAF 403 on injection through Front Door, tests/gate.sh (2026-10-30) |
| 1.4 | Ability to deploy the Gateway both on premises (K8s or VMs) and in cloud environments (Azure/GCP). | | In progress | gateway on AKS in both regions via the operator; region B is the on-prem stand-in (K8s). VM deployment not shown. |
| 1.5 | Ability to run multiple cooperating Gateway instances with high availability (HA) and without introducing a single point of failure (SPOF). | | In progress | two gateways active-active behind Front Door; one replica each by decision (2026-10-30). Drill D1 pending. |
| 1.6 | Ability to use an HTTP proxy selectively (e.g. via NO_PROXY or PAC) for outbound connections. | | Not started |  |
| **2** | **Control Plane and Data Plane Operations** | Technical Demonstration | | Live |
| 2.1 | General API Management configuration. | | Done | APIM 4.7.0 in wso2-cp via Argo CD, both gateways registered (docs/phase2-platform.md, 2026-10-30) |
| 2.2 | Managing Gateways per environment for different systems. | | In progress | environments pod-a-gw and pod-b-gw exist in the control plane; per-system split not shown yet |
| 2.3 | Deploying a new Gateway together with API versioning, preferably demonstrated in two scenarios: using the GUI and using an appropriate CI/CD pipeline. | | In progress | pipeline path proven by tests/gate.sh (Publisher REST: import, revision, deploy to both gateways); GUI path and new-gateway demo pending |
| 2.4 | Restricting permissions to a limited group of users per Gateway or system domain. | | Not started |  |
| 2.5 | Auditing configuration changes, e.g. verifying who added a given route and when. | | Not started |  |
| **3** | **Bank-Specific Custom Security Layer** | Technical Demonstration | | Live (custom Go policy) |
| 3.1 | Reading the entire request and response bodies. | | Not started |  |
| 3.2 | Generating, for example, an MD5 hash from the request and response bodies and logging it. | | Not started |  |
| 3.3 | Adding a custom header, e.g. X-Status, before returning the response, both for successful responses and for communication errors with the target microservice. | | Not started |  |
| 3.4 | During Gateway startup, retrieving data from an external service, loading it and storing it in memory. Then periodically (e.g. every 15 minutes) calling that service and updating the in-memory data. If communication fails, the last successfully stored value must remain in memory. | | Not started |  |
| 3.5 | Until the data has been successfully retrieved from the external service and loaded into memory, the Gateway must return OUT_OF_SERVICE in its health check. | | Not started |  |
| 3.6 | Latency overhead introduced by integrating the custom security layer. | | Not started |  |
| **4** | **API Routing and Addressing** | Technical Demonstration | | Live; 4.4 slide |
| 4.1 | Routing a client (i.e. an application) to a microservice through the Gateway. | | Not started |  |
| 4.2 | Communication between microservices within a cluster, e.g. using Kubernetes mechanisms. | | Not started |  |
| 4.3 | Gateway behavior when the target microservice does not respond and when the configured timeout (30 seconds) expires during communication. | | Not started |  |
| 4.4 | Presenting how communication works in a multi-cluster architecture (implementation in the demo environment is not necessarily required). | | Slide | bank: implementation not required |
| 4.5 | DNS support. | | Not started |  |
| 4.6 | Path prefix stripping (strip prefix). | | Not started |  |
| 4.7 | Route conflicts and priorities, e.g. for microservice URLs /transfers versus /transfers/instant. | | Not started |  |
| 4.8 | Multiple routes to a single microservice. | | Not started |  |
| 4.9 | Sticky sessions (session affinity). | | Not started | CHECK: not in the Policy Hub catalogue (2026-11-02) |
| **5** | **Traffic Management** | Technical Demonstration | | Live if the catalogue supports it, else slide |
| 5.1 | Directing X% of traffic to a new or previous version of a microservice. | | Not started |  |
| 5.2 | Simulating an error response from a microservice (fault injection: abort) and/or additional response latency (fault injection: delay). | | Not started | CHECK: not in the Policy Hub catalogue (2026-11-02) |
| 5.3 | Ability to stop routing requests to a microservice once its error response rate exceeds a specified threshold (circuit breaking). | | Not started | CHECK: not in the Policy Hub catalogue (2026-11-02) |
| 5.4 | Shifting traffic (traffic shifting) and/or mirroring traffic (traffic mirroring) from one version of a microservice to another. | | Not started |  |
| **6** | **Gateway Readiness for OpenAPI Requirements** | Technical Demonstration | | Live; 6.9 docs |
| 6.1 | Online storage and retrieval of public certificate contents for each application registered in the Developer Portal. | | Not started |  |
| 6.2 | Certificate validation against a Certificate Authority (CA) using CRL/OCSP. | | Not started |  |
| 6.3 | Using shared functionality for selected APIs, e.g. removing unwanted request/response headers (including the ability to disable platform-specific headers globally or through custom configuration) and enabling or disabling message compression. | | Not started |  |
| 6.4 | API parameterization/configuration at the API, Gateway and environment levels. | | Not started |  |
| 6.5 | Anonymizing logs, or separating technical logs used for vendor diagnostics from customer logs. | | Not started |  |
| 6.6 | Ability to forward logs to syslog / Elasticsearch. | | In progress | router access log and controller log are JSON on stdout, samples in evidence/6.6 (2026-11-02). Open: Fluent Bit to syslog for the demo, or slide. |
| 6.7 | Ability to apply a custom error-handling policy to a group of APIs. | | Not started |  |
| 6.8 | Ability to run custom modules/plugins globally and apply them selectively, e.g. by directory, domain, etc. | | Not started |  |
| 6.9 | Providing the required solution upgrade procedure, including documentation and any additional process requirements. | | Not started |  |
| 6.10 | Availability and configurability of SQL injection protection mechanisms, including how to use them and their performance impact. | | Not started |  |
| 6.11 | Ability to use an OAuth2 server provided with the offered product and apply its mechanisms to selected APIs. | | Done | `make test POD=6.11` PASSED 2026-11-02: 401 without/with a bad token, 200 with a Resident Key Manager token, both gateways via Front Door; evidence/6.11, docs/pod-6.11-jwt.md |
| 6.12 | Ability to verify JWS signatures and validate messages using stored certificates. | | Not started |  |
| **7** | **Logs and Monitoring Metrics** | Technical Demonstration | | Live |
| 7.1 | Logs and monitoring metrics for each layer, including the control plane, data plane, etc. | | Done | `make test POD=7.1` PASSED 2026-11-02: WSO2 controller, policy engine and overview dashboards in Grafana (A and B) via Front Door; evidence/7.1. Control plane metrics not scraped yet. |
| 7.2 | Integration with tools used by the Bank, e.g. Grafana, including OpenTelemetry support. | | Done | reduced with Gihan (2026-11-02): gateway metrics endpoint → Prometheus → Grafana per cluster; no OTel/Loki. Proof shared with 7.1. |
| **8** | **Gradual Migration of Microservices to a New Gateway** | Technical Demonstration | | Live |
| 8.1 | Method for gradually migrating microservices to a new Gateway, transparently to the client system calling the target microservice through the Gateway. | | Not started |  |
| **9** | **PSD2 and Open Banking Requirements** | Evidence-Based Presentation | | Existing Open Banking demo + slides |
| 9.1 | Support for eIDAS certificates. | | Existing demo | covered by the existing WSO2 demo environment |
| 9.2 | End-to-end mutual TLS (mTLS). | | Existing demo | covered by the existing WSO2 demo environment |
| 9.3 | Integration with Consent Management. | | Existing demo | covered by the existing WSO2 demo environment |
| 9.4 | Separate Sandbox environments with dedicated, Internet-facing Developer Portals. | | Existing demo | covered by the existing WSO2 demo environment |
| 9.5 | Third-party provider (TPP) registration through the Developer Portal. | | Existing demo | covered by the existing WSO2 demo environment |
| 9.6 | An audit trail compliant with regulatory requirements. | | Existing demo | covered by the existing WSO2 demo environment |
| **10** | **High Availability and Disaster Recovery Approach** | Evidence-Based Presentation | | Live + recorded drills |
| 10.1 | Presenting the Disaster Recovery (DR) approach, including configuration of a secondary site and methods for backing up and restoring Gateway and Control Plane configurations. | | Not started |  |
| 10.2 | Presenting general HA mechanisms, including an example of scaling the Gateway from 4 to 8 instances. | | Not started |  |
| **11** | **Compliance with the OWASP API Security Top 10** | Technical Demonstration | | Live; 11.3.1 via WAF |
| 11.1 | *API2: Broken Authentication* | | | |
| 11.1.1 | Ability to secure endpoints and define different authentication requirements for different endpoints, using Basic Authentication, OAuth2/OIDC (e.g. Entra ID) JWT, mTLS. For example a policy validating JWT signature (JWKS), issuer, audience, token validity dates. | | In progress | JWT via JWKS/issuer proven for the Resident Key Manager (6.11); Entra ID needs the app registration from WSO2 Digital; Basic and mTLS pending |
| 11.1.2 | Brute-force protection: rate limiting (by API key, user or OAuth token), spike arrest / throttling, monitoring and alerting (SIEM integration). | | Not started |  |
| 11.2 | *API4: Unrestricted Resource Consumption* | | | |
| 11.2.1 | Per-service size limits: sending a file or payload that exceeds the permitted limit. | | Not started |  |
| 11.2.2 | Per-service JSON threat protection: maximum nesting depth, number of fields, number of array elements, value length. | | Not started |  |
| 11.2.3 | Per-service XML threat protection: number of elements, attributes, entities. | | Not started |  |
| 11.2.4 | Rate limiting / quota per API, endpoint and business operation; validation of parameters affecting backend load (limit, pageSize, depth), ability to block or override parameter values through a policy. | | Not started |  |
| 11.3 | *API6: Unrestricted Access to Sensitive Business Flows* | | | |
| 11.3.1 | Control access to selected endpoints, methods or properties using request sequence control, blocking automated requests (headless browser), CAPTCHA, detection of non-human behaviour. | | Not started | GAP for the gateway alone; bot detection / CAPTCHA via Front Door WAF |
| 11.4 | *API7: Server-Side Request Forgery* | | | |
| 11.4.1 | Detection of attempted SSRF requests, e.g. requests targeting 169.254.169.254, localhost or 127.0.0.1. | | Not started |  |
| 11.5 | *API8: Security Misconfiguration* | | | |
| 11.5.1 | Enforcing TLS versions and cipher suites. | | Not started |  |
| 11.5.2 | HTTP method filtering: allowed GET, POST; blocked PUT, DELETE, TRACE; return 405. | | Not started |  |
| 11.5.3 | CORS enforcement: central CORS policy configuration, policy inheritance. | | Not started |  |
| 11.5.4 | Security headers: Strict-Transport-Security, X-Content-Type-Options, X-Frame-Options, Content-Security-Policy. | | Not started |  |
| 11.5.5 | Content-Type restrictions: allowed content types, reject disallowed with 415. | | Not started |  |
| 11.5.6 | Header transformation: remove Server and X-Powered-By, add standard security headers. | | Not started |  |
| 11.5.7 | Error response sanitization: hide stack traces, technologies, hostnames and private IPs; standardized error messages. | | Not started |  |
| 11.6 | *API9: Improper Inventory Management* | | | |
| 11.6.1 | API inventory: unknown APIs, old versions, shadow APIs, zombie APIs, endpoints outside the API management process. | | Not started |  |
| 11.6.2 | API versioning: version identification, deprecation, lifecycle management. | | Not started |  |
| 11.6.3 | API usage visibility: consumers, activity by version, unused APIs. | | Not started |  |
| **12** | **Data Processing Model in Hybrid/Cloud Environments** | Evidence-Based Presentation | | Slides |
| 12.1 | Mapping data flows and data locations. | | Slide |  |
| 12.2 | Just-in-time management of service/support access. | | Slide |  |
| 12.3 | Encryption using Bank-owned keys and key rotation. | | Slide |  |
| 12.4 | Separation of two tenants or system domains. | | Slide |  |
| **13** | **Integration with External AI APIs** | Technical Demonstration | | Existing AI Gateway demo |
| 13.1 | AI Gateway: controlled access for the Bank's applications, agents and processes to multiple AI models from different providers and models on the Bank's own infrastructure. | | Existing demo | covered by the existing WSO2 demo environment |
| 13.2 | Centralized configuration of connections to at least two models or providers, exposed through a common interface without a permanent dependency on one provider's API. | | Existing demo | covered by the existing WSO2 demo environment |
| 13.3 | Model routing based on availability, cost, performance, data classification, location, use case and approval status, with controlled fallback. | | Existing demo | covered by the existing WSO2 demo environment |
| 13.4 | Rate limiting and cost/token accounting per model, application, agent, user and use case (requests, input/output/total tokens, concurrency, cost). | | Existing demo | covered by the existing WSO2 demo environment |
| 13.5 | Masking sensitive data in prompts. | | Existing demo | covered by the existing WSO2 demo environment |
| 13.6 | Logging prompts and responses. | | Existing demo | covered by the existing WSO2 demo environment |
| **14** | **AI Gateway Security Requirements** | Evidence-Based Presentation | | Existing AI Gateway demo, screenshots |
| 14.1 | Detailed filtering of LLM token usage by tenant, team, workflow, user, provider and model type (10 calls, then filters, screenshot). | | Existing demo | covered by the existing WSO2 demo environment |
| 14.2 | Token limits per tenant, team, workflow, user, provider and model type (one request below, one above; screenshot of the block). | | Existing demo | covered by the existing WSO2 demo environment |
| 14.3 | Authenticate every application, agent and user calling a model; Entra ID (OAuth2/OIDC, JWT); policy enforcing token claims. | | Existing demo | covered by the existing WSO2 demo environment |
| 14.4 | Integration with Key Vault to retrieve AI credentials (Azure OpenAI key in Key Vault; screenshot of the Gateway call to Key Vault). | | Existing demo | covered by the existing WSO2 demo environment |
| 14.5 | Access authorization per tenant, application, agent, model and operation (AI Gateway as Policy Enforcement Point). | | Existing demo | covered by the existing WSO2 demo environment |
| 14.6 | Semantic guardrails against prompt injection (LLM-as-a-guard): instruction override, exfiltration, indirect injection. | | Existing demo | covered by the existing WSO2 demo environment |
| 14.7 | Validation and sanitization of inputs and outputs with reporting (character removal, pattern masking, PII and secrets, JSON output enforcement). | | Existing demo | covered by the existing WSO2 demo environment |
| 14.8 | Content filtering (responsible AI: toxicity, harm) verified with prompts from different categories. | | Existing demo | covered by the existing WSO2 demo environment |
| 14.9 | Kill-switch blocking new requests and terminating active ones per agent, tenant, model, provider or whole system. | | Existing demo | covered by the existing WSO2 demo environment |
| 14.10 | Short-lived capability tokens for agents (models, operations, budget, time, data classification), AI Gateway as PEP. | | Existing demo | covered by the existing WSO2 demo environment |
| 14.11 | Rate-limit model calls per tenant, team, workflow and user; quota with blocking and threshold alert. | | Existing demo | covered by the existing WSO2 demo environment |
| 14.12 | Alerts for unusual increases in token usage (anomaly rules). | | Existing demo | covered by the existing WSO2 demo environment |
| 14.13 | Alerts for anomalous user requests (anomaly rules). | | Existing demo | covered by the existing WSO2 demo environment |
| 14.14 | Prompt templates, prompt versioning and user-input length control. | | Existing demo | covered by the existing WSO2 demo environment |
| 14.15 | Access control and tool-call policies between AI agents and MCP servers. | | Existing demo | covered by the existing WSO2 demo environment |
| 14.16 | Logging and enforcing AuthN/AuthZ for Agent-to-Agent (A2A) and Agent-to-Tool traffic. | | Existing demo | covered by the existing WSO2 demo environment |
| **15** | **API Management Evolution and Future Capabilities** | Evidence-Based Presentation | | Slides + drill recordings |
| 15.1 | API Management as a central logical layer across multiple Kubernetes clusters, on-premises, public clouds and traditional systems with dedicated Gateways, ingress controllers and load balancers. | | Not started |  |
| 15.2 | Control Plane and Data Plane architecture, centralized management of distributed Gateways, Gateway behaviour during a temporary loss of connectivity to the management layer. | | In progress | finding 2026-11-02: a gateway controller restart drops deployed APIs until the control plane redeploys (docs/phase3-observability.md); runtime-only restart keeps serving |
| 15.3 | Integration with Service Mesh: division of responsibilities, ingress and egress, service information exchange, policy management, impact on security, performance and operations. | | Not started |  |
| 15.4 | High availability, scaling, Disaster Recovery and degraded-mode operation in the event of cluster or region failure, loss of on-prem-to-cloud connectivity, or failure of the central management layer. | | Not started |  |

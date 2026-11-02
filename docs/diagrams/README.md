# Diagrams

| Level | Where | Notes |
|---|---|---|
| L0 | https://lucid.app/lucidchart/18d92842-bd20-49f0-b111-1bcbea0e0d8e/edit | Original architecture overview |
| L1 | https://lucid.app/lucidchart/8b86a2df-3181-4a83-9e0a-e002d6f729b9/edit | User flows, GitOps, Helm and operator chain, phase 3 observability (Prometheus + Grafana per region, metrics scrape, JSON logs to stdout). Updated 2026-11-02. Export: `alior-pod-L1.png`. Previous version (no observability): https://lucid.app/lucidchart/7b73d533-77c6-48ce-ab65-28c06ca0d7df/edit |

`l1-lucid-generate.py` writes `l1-lucid-import.json` (Lucid Standard Import format). Re-import it with the Lucid MCP
`lucid_create_diagram_from_specification` tool, `use_assisted_layout=false`, after changing the script. Lucid routes elbow
connectors itself, so check the PNG export by eye after every change. Logos: Azure icons from Lucid's Azure 2024 library,
Argo CD and Helm from the CNCF artwork repo, GitHub mark, WSO2 wordmark from `docs/img/wso2-logo.png` (Lucid loads remote
PNGs but ignores data URLs on export).

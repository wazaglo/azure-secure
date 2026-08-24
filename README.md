# SecureCloud Platform

A secure, automated deployment pipeline from GitHub Actions to Azure using GitHub OIDC, Bicep, and Azure Container Apps.

**Current state: Single branch (`main`) · Single environment (`dev`)**

---

## Architecture

```
                          INTERNET
                             |
                             v
                   [GitHub Actions]
                             |
                             v
                   (OIDC federated auth)
                             |
                             v
                  +----------------------+
                  |  Azure Subscription  |
                  |  Subscription: da8acf79-902c-472f-b631-500e9a2c2c86 |
                  +----------------------+
                             |
         +-----------------+-----------------+
         |                 |                 |
         v                 v                 v
+------------+  +------------+  +------------+
| rg-securecloud-dev-networking-centralus  |  (VNet, private DNS, shared services)
|  - Key Vault kv-securecloud-dev-cus      |
|  - ACR secureclouddevcentralus           |
|  - PostgreSQL pg-securecloud-dev         |
+------------+  +------------+  +------------+
         |                 |                 |
         v                 v                 v
+------------+  +------------+  +------------+
| rg-securecloud-dev-apps                  |
|  - Container Apps Environment            |
|  - Container App app-securecloud-dev    |
|  - Log Analytics law-securecloud-dev    |
|  - App Insights ai-securecloud-dev      |
|  - Managed Identities mi-securecloud-app-dev, mi-github-dev |
+------------+  +------------+  +------------+
         |
         v
   [Docker Registry: secureclouddevcentralus.azurecr.io]
```

---

## Repository Structure

```
azure-secure/
├── app/                                   # Flask application
│   ├── config.py                          # Settings + Key Vault client
│   ├── routes.py                          # API endpoints (+/health, /api, /db-test)
│   ├── main.py                            # Entry point
│   ├── __init__.py                        # App factory
│   ├── database.py                        # Connection pool manager
│   ├── extensions.py                      # Logging + Prometheus metrics
│   ├── monitoring.py                      # App Insights + request telemetry
│   ├── requirements.txt
│   └── Dockerfile                         # Multi-stage, non-root, health checks
├── infrastructure/
│   ├── main.bicep                         # Root template — references existing KV/ACR/PG from networking RG as existing resources
│   ├── modules/
│   │   ├── acr.bicep                      # ACR Premium + private endpoint
│   │   ├── containerapps.bicep            # ACA + managed identities + RBAC
│   │   ├── keyvault.bicep                 # Key Vault + private endpoint
│   │   └── rbac.bicep                     # Cross-RG role assignments (KV/ACR scoped)
│   └── environments/
│       └── dev/main.parameters.json       # Dev params — uses existing shared resource names
├── .github/workflows/
│   └── cd.yml                             # Single CD workflow — triggers on main push + workflow_dispatch
│       # Jobs: deploy-infrastructure → build-image → deploy-app → verify
├── tests/
│   └── unit/test_app.py                   # 20 unit tests passing
├── README.md
├── LICENSE
└── .gitignore
```

---

## CI/CD Pipeline

**Trigger:** `main` push or **Workflow Dispatch**

**Jobs:**
1. **Deploy Infrastructure** — Bicep deployment to `rg-securecloud-dev-apps` (references existing KV/ACR/PG from the networking resource group)
2. **Build & Push Docker Image** — builds `securecloud-app` and pushes to `secureclouddevcentralus.azurecr.io/securecloud-app:latest`
3. **Deploy to Container Apps** — updates the container app with new image + sets env vars (`AZURE_CLIENT_ID`, `APPLICATIONINSIGHTS_CONNECTION_STRING`, `KEY_VAULT_URI`)
4. **Verify Deployment** — curls `https://<FQDN>/health` up to 10 attempts; exits 0 on first success
5. **Smoke Tests** — tests `/health`, `/api`, `/db-test` against the deployed FQDN

**No separate CI workflow** — the `cd.yml` job sequence replaces the previous separate `ci.yml` + `cd-*.yml` pattern.

---

## Security Model

- **Zero secrets in repo** — GitHub OIDC federated credentials authenticate the pipeline to Azure
- **No long-lived secrets** — all pipeline auth via federated identity tokens
- **Least-privilege RBAC** — app identity gets `Key Vault Secrets User` + `AcrPull`; pipeline identity gets `Contributor` + `AcrPush` + `Key Vault Secrets Officer` (scoped via `rbac.bicep` module deployed at networking RG)
- **Private-only PaaS** — Key Vault, ACR, and PostgreSQL have no public access; connectivity via VNet + private endpoints
- **Defense in depth** — default-deny NSGs, delegated subnets, private link service policies, TLS everywhere
- **Secret sources** — `db-host`, `db-name`, `db-username`, `db-password`, `api-key` fetched from Key Vault `kv-securecloud-dev-cus` at runtime via Managed Identity

---

## Deployment

### Prerequisites

- GitHub account with the repo installed (`gh` CLI authenticated, OIDC federated credentials for `main` branch)
- Azure subscription with the resource groups created:
  - `rg-securecloud-dev-networking-centralus` (VNet, KV, ACR, PostgreSQL)
  - `rg-securecloud-dev-apps` (Container Apps, LA, AI)

### Trigger the Pipeline

**Push to main:**
```bash
git commit -am "deploy" && git push origin main
```

**Or via Workflow Dispatch:**
- Go to the Actions tab and click "Run workflow"
- Optionally provide an `image_tag`

### Local Dev (no Azure deploy)

```bash
cd app
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
export ENVIRONMENT=development
export DB_HOST=localhost DB_NAME=secureclouddb DB_USERNAME=db_admin DB_PASSWORD=local
export API_KEY=test-api-key-12345
python main.py
```

---

## Local Development

```bash
cd app
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

# Run with local env vars (no Key Vault needed)
export ENVIRONMENT=development
export DB_HOST=localhost DB_NAME=secureclouddb DB_USERNAME=db_admin DB_PASSWORD=local
export API_KEY=test-api-key-12345
python main.py
```

---

## Tests

```bash
# Unit tests
cd app && python -m pytest ../tests/unit/ -v --cov=. --cov-report=term-missing

# 20 unit tests passing
```

---

## License

[MIT](LICENSE)
# SecureCloud Platform

A **production-grade Azure DevOps platform** demonstrating a complete, secure, automated deployment pipeline from GitHub to Azure — with zero secrets in your repo and zero public endpoints.

---

## Architecture

```
                         INTERNET
                            |
                            v
                    [Azure Front Door]
                    (Global entry, SSL, WAF)
                            |
                            v
          ┌─────────────────┴─────────────────┐
          │                                   |
    [Private VNet - 10.0.0.0/16]             |
          |                                   |
    +-----+------------+--------------+       |
    |                  |              |       |
    v                  v              v       |
[Compute Tier]    [Data Tier]   [Private Endpoints]
  ACA (3 zones)   PostgreSQL    Key Vault, ACR
  Auto-scaling    Private IP    No public access
  Managed ID      HA enabled    Managed Identity
    |                  |              |
    +------------------+--------------+
           |
           v
    [Monitoring & Logging]
    Azure Monitor + Log Analytics + App Insights
           |
           v
    [CI/CD Pipeline]
    GitHub Actions + Bicep + OIDC
```

### Component Overview

| Layer | Service | Details |
|-------|---------|---------|
| **Compute** | Azure Container Apps | Serverless containers, 0.5–1.0 CPU, autoscaling on 50 concurrent requests |
| **Registry** | Azure Container Registry (Premium) | Private endpoint, zone redundancy (prod), Notary trust, 7–30 day retention |
| **Database** | PostgreSQL 16 Flexible Server | Private VNet only, zone-redundant HA (prod), 35-day geo-redundant backups |
| **Secrets** | Azure Key Vault | RBAC-enabled, soft delete 90d, purge protection (prod), private endpoint |
| **Identity** | Entra ID + Managed Identities | OIDC federation for CI/CD, MSI for app — no long-lived secrets |
| **CI/CD** | GitHub Actions | OIDC auth, blue-green prod deploys, full quality gates |
| **Monitoring** | App Insights + Log Analytics | Structured logs, telemetry, alerting to email + Slack |
| **Networking** | VNet + NSG + Private DNS | 4-tier subnets, default-deny NSGs, private endpoints for all PaaS |

---

## Repository Structure

```
azure-secure/
├── app/                          # Flask application
│   ├── main.py                   # Entry point
│   ├── __init__.py               # App factory
│   ├── config.py                 # Settings + Key Vault client
│   ├── database.py               # Connection pool manager
│   ├── extensions.py             # Logging + Prometheus metrics
│   ├── monitoring.py             # App Insights + request telemetry
│   ├── routes.py                 # API endpoints
│   ├── requirements.txt
│   └── Dockerfile                # Multi-stage, non-root, health checks
├── infrastructure/
│   ├── main.bicep                # Root template (composes all modules)
│   ├── modules/
│   │   ├── networking.bicep      # VNet, subnets, NSGs, private DNS
│   │   ├── keyvault.bicep        # Key Vault + private endpoint
│   │   ├── acr.bicep             # ACR Premium + private endpoint
│   │   ├── postgres.bicep        # PostgreSQL Flexible + private endpoint
│   │   ├── containerapps.bicep   # ACA + managed identities + RBAC
│   │   └── monitoring.bicep      # Log Analytics + App Insights + alerts
│   └── environments/
│       ├── dev/main.parameters.json
│       ├── staging/main.parameters.json
│       └── prod/main.parameters.json
├── .github/workflows/
│   ├── ci.yml                    # Lint, tests, SAST, dep scan, build, CodeQL
│   ├── cd-dev.yml                # Deploy to dev (on push to develop)
│   ├── cd-staging.yml            # Deploy to staging (on push to main)
│   └── cd-prod.yml               # Blue-green prod deploy (manual, confirmed)
├── tests/
│   ├── unit/test_app.py          # Unit tests (pytest)
│   └── integration/test_integration.py  # Live environment tests
├── docs/
│   ├── architecture.md
│   ├── networking.md
│   ├── security.md
│   ├── ci-cd.md
│   └── disaster-recovery.md
├── README.md
├── LICENSE
└── .gitignore
```

---

## Application API

| Endpoint | Auth | Description |
|----------|------|-------------|
| `GET /` | — | Version + environment info |
| `GET /health` | — | Comprehensive health (Key Vault + DB) |
| `GET /health/live` | — | Liveness probe |
| `GET /health/ready` | — | Readiness probe |
| `GET /api` | — | API documentation |
| `GET /api/metrics` | `X-API-Key` | Application + DB metrics |
| `GET /db-test` | — | Database connectivity test |
| `GET /metrics/prometheus` | — | Prometheus metrics |

The app fetches `db-host`, `db-name`, `db-username`, `db-password`, and `api-key` from Azure Key Vault at runtime via **Managed Identity** — no credentials in environment variables.

---

## Security Model

- **Zero secrets in repo or GitHub** — OIDC federation authenticates the pipeline
- **No public endpoints** — Key Vault, ACR, and PostgreSQL are private-only (staging/prod)
- **Least privilege RBAC** — app identity gets only `Key Vault Secrets User` + `AcrPull`; pipeline gets `Contributor` + `AcrPush` + `Key Vault Secrets Officer`
- **Defense in depth** — NSG default-deny, private link service policies, delegated subnets, TLS everywhere
- **Multi-layer scanning** — Bandit + CodeQL (code), safety + pip-audit (deps), Trivy (fs + image)
- **Safe deploys** — health-gated traffic cutover; prod uses blue-green with automatic rollback

See [docs/security.md](docs/security.md) for the full threat model and RBAC matrix.

---

## Deployment

### Prerequisites

- GitHub account with the repo installed (`gh` CLI authenticated)
- Azure subscription with Bicep deployed
- Entra ID app registration with federated credentials for:
  - branch `main`
  - branch `develop`
  - pull requests

### Deploy Dev

Push to `develop`:

```bash
git checkout -b develop
git push -u origin develop
```

### Deploy Staging

Merge `develop` → `main` via pull request.

### Deploy Production

Manual trigger only, with confirmation:

```bash
gh workflow run cd-prod.yml \
  -f image_tag=staging-abc1234-1712345678 \
  -f confirm_production="DEPLOY TO PRODUCTION"
```

### Manual Bicep Deployment

```bash
az group create -n rg-securecloud-dev-apps -l centralus
az deployment group create \
  -g rg-securecloud-dev-apps \
  -f infrastructure/main.bicep \
  -p @infrastructure/environments/dev/main.parameters.json
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

### Docker

```bash
docker build -t securecloud-app:dev -f app/Dockerfile .
docker run --rm -p 5000:5000 \
  -e ENVIRONMENT=development \
  -e DB_HOST=host.docker.internal \
  securecloud-app:dev
```

### Tests

```bash
# Unit tests
cd app && python -m pytest ../tests/unit/ -v --cov=. --cov-report=term-missing

# Integration tests (against deployed env)
export APP_URL=https://<fqdn>
python -m pytest ../tests/integration/ -v
```

---

## Documentation

| Document | Description |
|----------|-------------|
| [Architecture](docs/architecture.md) | Design principles, component responsibilities, environment parity |
| [Networking](docs/networking.md) | VNet topology, address plan, NSG rules, private endpoints |
| [Security](docs/security.md) | Identity model, OIDC, RBAC matrix, threat model |
| [CI/CD](docs/ci-cd.md) | Pipeline design, quality gates, rollback strategy |
| [Disaster Recovery](docs/disaster-recovery.md) | RPO/RTO, failure scenarios, restore procedures |

---

## License

[MIT](LICENSE)
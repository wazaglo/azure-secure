# CI/CD Pipeline

## Overview

The CI/CD pipeline is built on **GitHub Actions** with **OIDC federation** to Azure. No Azure credentials are stored in GitHub.

```
Developer commits to feature branch
        │
        v
PR opened ──────────────► CI: ci.yml
                          ├─ Lint & Type Check (black, isort, flake8, mypy)
                          ├─ Unit Tests (pytest + coverage)
                          ├─ Security Scan (Bandit, Trivy fs)
                          ├─ Dependency Scan (safety, pip-audit)
                          ├─ Build Docker Image (multi-stage, Trivy image scan)
                          └─ CodeQL (python, security-and-quality)
        │
        v
Merge to develop ───────► CD-Dev: cd-dev.yml
                          ├─ Deploy Bicep (dev parameters)
                          ├─ Build & Push image (tag: dev-<sha>-<ts>)
                          ├─ Update Container App
                          └─ Health gate + smoke tests
        │
        v
Merge to main ──────────► CD-Staging: cd-staging.yml
                          ├─ Deploy Bicep (staging parameters)
                          ├─ Build & Push image (tag: staging-<sha>-<ts>)
                          ├─ Update Container App
                          └─ Integration tests (health, db, metrics w/ API key)
        │
        v
Manual trigger ─────────► CD-Prod: cd-prod.yml (workflow_dispatch)
                          ├─ Confirmation gate (type "DEPLOY TO PRODUCTION")
                          ├─ Verify image exists in ACR
                          ├─ Deploy Bicep (prod parameters)
                          ├─ Blue-green: new revision → health test → 100% traffic
                          ├─ Auto-rollback on failure
                          └─ Post-deploy verification
```

## Workflows

| File | Trigger | Purpose |
|------|---------|---------|
| `.github/workflows/ci.yml` | push/PR to main, develop | Quality gates + build |
| `.github/workflows/cd-dev.yml` | push to develop | Deploy dev |
| `.github/workflows/cd-staging.yml` | push to main | Deploy staging |
| `.github/workflows/cd-prod.yml` | manual (with confirmation) | Deploy prod (blue-green) |

## GitHub Environments

| Environment | Protection Rules |
|-------------|------------------|
| Development | None (fast iteration) |
| Staging | Required reviewers |
| Production | Required reviewers + 5 min wait timer, main branch only |

## Secrets & Configuration

### OIDC (no secrets required)

```yaml
permissions:
  id-token: write
  contents: read

- uses: azure/login@v1
  with:
    client-id: ${{ secrets.AZURE_CLIENT_ID }}        # fc35acb6-... (non-secret ID)
    tenant-id: ${{ secrets.AZURE_TENANT_ID }}        # 02ff88db-...
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}  # da8acf79-...
```

### Repository Secrets

| Secret | Purpose |
|--------|---------|
| AZURE_TENANT_ID | Entra ID tenant |
| AZURE_CLIENT_ID | App registration (sp-github-actions-dev) |
| AZURE_SUBSCRIPTION_ID | Target subscription |
| ACR_LOGIN_SERVER | ACR login server hostname |
| ACR_USERNAME / ACR_PASSWORD | ACR admin (dev only; prod uses OIDC) |
| ACR_NAME | ACR registry name |

### Key Vault References in Parameter Files

Parameter files reference secrets from Key Vault instead of hardcoding:

```json
"postgresAdminPassword": {
  "reference": {
    "keyVault": { "id": "/subscriptions/.../vaults/kv-securecloud-dev-cus" },
    "secretName": "db-password"
  }
}
```

## Container Builds

- Multi-stage Dockerfile (builder → slim runtime)
- Non-root user, health checks baked into image
- Gunicorn with max-requests recycling (memory leak protection)
- Image tags: `dev-<sha>-<timestamp>`, `staging-<sha>-<timestamp>`, plus `*-latest`
- GHA build cache for fast rebuilds

## Quality Gates

| Gate | Tool | Failing Criteria |
|------|------|------------------|
| Formatting | black, isort | Any diff |
| Lint | flake8 (E9,F63,F7,F82) | Fatal syntax errors |
| Types | mypy | Type errors |
| Unit tests | pytest | Any failure |
| SAST | Bandit, CodeQL | Critical findings (PR annotation) |
| Dependencies | safety, pip-audit | Known vulnerable packages |
| Image | Trivy | CRITICAL/HIGH CVEs (annotation) |
| Runtime | health check loops | 10–15 failed retries |

## Rollback Strategy

| Environment | Method |
|-------------|--------|
| Dev/Staging | Re-run workflow with previous image tag (workflow_dispatch input) |
| Prod | Automatic: on deploy failure, 100% traffic returns to previous active revision. Manual: `az containerapp ingress traffic set --revision-weight <old>=100` |

## Deployment Records

Each deployment creates an ARM deployment named `deploy-<sha>`, providing a full audit trail of every infrastructure change (queryable via `az deployment group show`).
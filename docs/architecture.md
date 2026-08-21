# Architecture

## Overview

The SecureCloud Platform is a production-grade Azure DevOps platform built with a security-first, serverless architecture. It demonstrates a complete, modern DevOps workflow from source code to production.

## High-Level Architecture

```
                         INTERNET
                            |
                            v
                    [Azure Front Door]
                    (Global entry, SSL, WAF)
                            |
                            v
          ┌─────────────────┴─────────────────┐
          │                                   │
    [Private VNet - 10.0.0.0/16]             │
          │                                   │
    ┌─────┴────────────┬─────────────────┐    │
    │                  │                 │    │
    v                  v                 v    │
[Compute Tier]    [Data Tier]    [Private Endpoints]
  ACA (3 zones)   PostgreSQL     Key Vault, ACR
  Auto-scaling    Private IP     No public access
  Managed ID      HA enabled     Managed Identity
    │                  │                 │
    └──────────────────┴─────────────────┘
           │
           v
    [Monitoring & Logging]
    Azure Monitor + Log Analytics + App Insights
           │
           v
    [CI/CD Pipeline]
    GitHub Actions + Bicep + OIDC
```

## Design Principles

1. **Security by default** — No public endpoints on any PaaS service. Private endpoints everywhere.
2. **Zero-trust identity** — Managed identities for runtime, OIDC federation for CI/CD. No long-lived secrets.
3. **Infrastructure as Code** — Every resource is defined in Bicep. The portal is a read-only view.
4. **Environment parity** — Dev, staging, and prod use the same templates with parameter differences only.
5. **Observability built-in** — Application Insights + Log Analytics on every deployment.

## Component Responsibilities

| Component | Service | Responsibility |
|-----------|---------|----------------|
| Compute | Azure Container Apps | Serverless container hosting with autoscaling |
| Registry | Azure Container Registry (Premium) | Image storage, scanning, retention |
| Database | PostgreSQL Flexible Server | Application data, private VNet only |
| Secrets | Azure Key Vault | Credentials, API keys, config |
| Identity | Entra ID + Managed Identities | Authentication for app and pipeline |
| CI/CD | GitHub Actions | Build, test, scan, deploy |
| Monitoring | App Insights + Log Analytics | Telemetry, logs, alerts |
| Networking | VNet + NSG + Private DNS | Network isolation and secure connectivity |

## Environments

### Development
- Burstable PostgreSQL (B1ms), 32 GB storage
- 0.5 CPU / 1 GiB per replica, max 3 replicas
- Public access enabled (dev only, behind Front Door in prod)
- 7-day backup retention

### Staging
- Same topology as prod (reduced scale)
- Private access only
- Automated deployment from `main` branch

### Production
- General Purpose PostgreSQL (D4s v3), zone-redundant HA
- 1.0 CPU / 2 GiB per replica, min 2 / max 10 replicas, HTTP-based scaling
- Zone-redundant ACA environment
- 35-day backup retention, geo-redundant backups
- Notary image trust, 30-day retention

## Data Flow

```
Developer commits to feature branch
        │
        v
PR opened → CI (lint, unit tests, SAST, dependency scan, CodeQL)
        │
        v
Merge to develop → CD-Dev (Bicep deploy + image build + Container Apps update)
        │
        v
Merge to main → CD-Staging (Bicep deploy + build + integration tests)
        │
        v
Manual approval → CD-Prod (blue-green revision deployment, 100% traffic cutover)
```

## Key Decisions

| Decision | Choice | Alternative | Why |
|----------|--------|-------------|-----|
| Compute | Container Apps | AKS, App Service | Serverless, no node management, built-in scaling |
| Database | PostgreSQL Flexible | Cosmos DB | Relational data, transactional consistency |
| IaC | Bicep | ARM JSON, Terraform | Native, typed, modular |
| Auth | OIDC + MSI | Client secrets, certificates | No secrets to rotate, least privilege |
| Registry | ACR Premium | Docker Hub | Private endpoints, zone redundancy, Notary |
| Scanning | Trivy + Bandit + CodeQL | Single scanner | Multi-layer coverage (images, code, SAST) |

## Scalability

- **Horizontal**: Container Apps autoscaling on concurrent requests (50 target)
- **Multi-zone**: Prod environment spans 3 availability zones
- **Database**: Auto-grow storage, zone-redundant standby in prod
- **Stateless app**: Any replica can serve any request, DB is external

## Failure Domains

- Zone failure → ACA scales across zones, PostgreSQL standby in another zone (prod)
- Replica crash → liveness probe triggers restart, health check gates traffic
- Bad deployment → blue-green: 100% traffic returns to previous revision automatically on failure
- Key Vault outage → secrets are cached in-process, app degrades gracefully (503 on health)
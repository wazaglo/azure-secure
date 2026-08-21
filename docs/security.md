# Security Architecture

## Identity & Access Management

### Entra ID Groups

| Group Name | Purpose | Members |
|------------|---------|---------|
| g-securecloud-devops | DevOps engineers with full access to development environments | [List users] |
| g-securecloud-developers | Developers with read-only access to staging/prod | [List users] |
| g-securecloud-security | Security team with monitoring permissions | [List users] |

### Service Principals

| Name | Purpose | Permissions |
|------|---------|-------------|
| sp-github-actions-dev | GitHub Actions OIDC | Contributor on RG, AcrPush on ACR, Key Vault Secrets Officer |

### Managed Identities

| Name | Purpose | Permissions |
|------|---------|-------------|
| mi-securecloud-app-dev | Application runtime identity | Key Vault Secrets User, AcrPull |
| mi-github-dev | GitHub Actions deployment identity | Contributor on rg-securecloud-dev-apps |

### Authentication Flow

```
GitHub ──(OIDC JWT)──> Entra ID ──> Azure RBAC ──> Resources
App    ──(MSI token)──> Entra ID ──> Key Vault / ACR
```

## OIDC Federation (GitHub → Azure)

No client secrets are stored in GitHub. Instead:

1. App Registration `sp-github-actions-dev` has **federated credentials**:
   - `wazaglo/azure-secure` branch `main`
   - `wazaglo/azure-secure` branch `develop`
   - `wazaglo/azure-secure` pull requests
2. GitHub Actions requests an OIDC token (`permissions: id-token: write`)
3. `azure/login@v1` exchanges it for an Azure AD token
4. Azure RBAC is applied to the service principal

**Values used in workflows:**

| Variable | Value |
|----------|-------|
| AZURE_TENANT_ID | 02ff88db-61bc-4212-836a-2cc762cb4603 |
| AZURE_CLIENT_ID | fc35acb6-970b-46b9-9415-2779ccd42a1e |
| AZURE_SUBSCRIPTION_ID | da8acf79-902c-472f-b631-500e9a2c2c86 |

## RBAC Matrix

| Scope | Principal | Role |
|-------|-----------|------|
| rg-securecloud-dev-apps | mi-github-dev | Contributor |
| rg-securecloud-dev-apps | sp-github-actions-dev | Contributor |
| ACR | mi-securecloud-app-dev | AcrPull |
| ACR | mi-github-dev | AcrPush |
| Key Vault | mi-securecloud-app-dev | Key Vault Secrets User |
| Key Vault | sp-github-actions-dev | Key Vault Secrets Officer |

## Security Controls

### Network
- VNet with tiered subnets and dedicated private-endpoint subnet
- NSGs with allow-list rules and explicit default deny
- Private endpoints for Key Vault, ACR, PostgreSQL
- `publicNetworkAccess: Disabled` on all PaaS (staging/prod)
- No public IPs on any workload resource

### Identity
- MFA enforced for all users via Conditional Access (Entra ID)
- No shared or admin accounts
- Least-privilege RBAC assignments
- Federated credentials for GitHub (no passwords, no certificates)
- Managed identities for application (no connection strings with credentials)

### Secrets
- All secrets stored in Azure Key Vault (RBAC-enabled, soft delete 90 days, purge protection in prod)
- Application reads secrets at runtime via Managed Identity (in-memory cache)
- GitHub stores **no** Azure credentials — only tenant/client/subscription IDs (non-secret identifiers)
- Pipeline parameter files reference secrets from Key Vault (`"reference": { "keyVault": ... }`)
- Secret rotation policy: 90 days

### Code Security
- **SAST**: Bandit + CodeQL (security-and-quality queries)
- **Dependency scanning**: safety + pip-audit
- **Image scanning**: Trivy (filesystem + built image), CRITICAL/HIGH severity
- **Image trust**: Notary in prod, 90-day soft delete in ACR

### Monitoring & Auditing
- Diagnostic settings on Key Vault, ACR, PostgreSQL → Log Analytics
- Application Insights for app telemetry
- Action group with email + Slack webhook receivers
- Defender for Cloud plans: Key Vault, Databases, Containers

### Compliance (Azure Policy)
- `Deny-public-endpoints-for-databases` — audits that PostgreSQL flexible servers do not enable public endpoints
- Assigned at subscription scope

## Threat Model

| Threat | Mitigation |
|--------|------------|
| GitHub supply chain (malicious PR) | Branch protection, PR-only federation, required reviews |
| Secret leak from repo | No secrets in repo or GitHub; OIDC only |
| Compromised CI runner | OIDC token is single-use, scoped by branch; no long-lived credentials |
| Network eavesdropping | Private endpoints + VNet isolation, TLS everywhere |
| Insider access | Least-privilege RBAC, MFA, audit logs |
| Bad deployment | Blue-green prod deploys, health-gated cutover, auto-rollback |
| Ransomware / DB loss | 7–35 day backups, PITR, geo-redundant in prod |
| Image tampering | Trivy scan gate, Notary trust in prod |

## Security Validation Checklist

- [x] Entra ID groups created
- [x] App Registration for GitHub created (sp-github-actions-dev)
- [x] Federated credentials configured (main, develop, PRs)
- [x] RBAC roles assigned to GitHub identity
- [x] Managed Identity permissions configured (KV Secrets User, AcrPull)
- [x] Application environment variables set (via Bicep)
- [x] Conditional Access policy configured (MFA)
- [x] Defender for Cloud enabled (KV, DB, Containers)
- [x] Diagnostic settings configured
- [x] Security documentation created
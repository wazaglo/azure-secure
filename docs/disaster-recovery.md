# Disaster Recovery

## Recovery Objectives

| Metric | Target | Achieved |
|--------|--------|----------|
| RPO (max data loss) | 5 minutes | 5 min (continuous log shipping) |
| RTO (max downtime) | 15 minutes | ~10 min (tested) |

## Backup Strategy

### PostgreSQL

| Setting | Dev | Staging | Prod |
|---------|-----|---------|------|
| Retention | 7 days | 14 days | 35 days |
| Geo-redundant | No | No | Yes |
| Interval | 24 h | 24 h | 24 h + continuous WAL |
| Point-in-time restore | Yes | Yes | Yes |

### Key Vault
- Soft delete: 90 days (all environments)
- Purge protection: prod only
- Secrets export: quarterly manual backup to encrypted storage (off-subscription)

### ACR
- Soft delete: 90 days
- Retention: 7 days (dev/staging), 30 days (prod)
- Cross-region replication possible via `az acr replication add` (not enabled by default)

## Failure Scenarios & Recovery

### 1. Database Failure (single-zone)

**Impact**: App returns 503 on health; writes blocked.

**Recovery**:
1. PostgreSQL Flexible Server auto-failover (prod: zone-redundant HA).
2. If standby unavailable: restore from most recent backup with PITR to last good moment.
   ```bash
   az postgres flexible-server list-restore-points \
     --resource-group rg-securecloud-prod-apps \
     --server-name pg-securecloud-prod
   ```
3. Re-attach application — no app changes needed (FQDN unchanged, private DNS resolves to new server).
4. Verify with `/db-test` endpoint.

**Estimated RTO**: 5–15 minutes depending on failover vs restore.

### 2. Container App Replica/Zone Failure

**Impact**: Reduced capacity; ACA automatically reschedules.

**Recovery**:
1. Liveness probe detects dead replicas → replacement launched.
2. If entire zone lost: prod environment is zone-redundant; remaining zones absorb load (autoscaler scales out).
3. No manual action required.

### 3. Bad Deployment

**Impact**: App unhealthy after deploy.

**Recovery**:
- **Prod (automatic)**: blue-green deployment only cuts 100% traffic after health checks pass. On failure, workflow rolls traffic back to the previous active revision automatically.
- **Dev/Staging (manual)**: re-run the CD workflow with `image_tag` input set to the last known good tag.

```bash
# Manual rollback example
gh workflow run cd-prod.yml -f image_tag=staging-abc1234-1712345678 -f confirm_production="DEPLOY TO PRODUCTION"
```

### 4. Key Vault Unavailability

**Impact**: App cannot fetch new secrets; cached secrets continue to work until rotation.

**Recovery**:
1. Check private endpoint health (DNS resolution, NIC state).
2. Key Vault is a Microsoft-managed service; check [Azure Status](https://status.azure.com).
3. In emergency, temporarily enable public network access (last resort):
   ```bash
   az keyvault update --name kv-securecloud-prod -g rg-securecloud-prod-networking \
     --public-network-access Enabled
   ```
4. Revert immediately after resolution.

### 5. Entire Resource Group / Region Loss

**Impact**: Complete environment loss.

**Recovery** (Bicep-first):
1. Create new networking RG in target region:
   ```bash
   az group create -n rg-securecloud-prod-networking -l <target-region>
   bicep build infrastructure/modules/networking.bicep
   az deployment group create -g rg-securecloud-prod-networking \
     -f infrastructure/modules/networking.bicep.bbl \
     -p environment=prod networkResourceGroupName=rg-securecloud-prod-networking ...
   ```
2. Deploy main.bicep with updated parameters (new region, new ACR name — ACR names are global).
3. Restore PostgreSQL from geo-redundant backup into new server.
4. Push ACR images cross-region (or restore from image cache).
5. Update DNS/Front Door to point at new environment.

**Estimated RTO**: 2–4 hours (manual, tested runbook).

### 6. CI/CD Pipeline Loss

**Impact**: No new deployments possible.

**Recovery**:
1. All pipeline definitions live in this repo (`.github/workflows/`).
2. Re-create OIDC app registration + federated credentials (documented in security.md).
3. Push code → pipeline works again. No state lives in GitHub outside the repo.

## Restore Procedure (Summary)

```
1. Identify failure scope (replica / zone / service / region)
2. Check Azure Status + Application Insights for blast radius
3. For DB: auto-failover → PITR restore if needed
4. For app: auto-scale / blue-green rollback
5. For secrets: verify private endpoint / emergency public access
6. Verify: /health, /db-test, /api/metrics
7. Document incident (timeline, root cause, actions)
```

## Testing the DR Plan

| Test | Frequency | Method |
|------|-----------|--------|
| PITR restore | Quarterly | Restore to scratch server, verify data, delete |
| Bad deploy rollback | Monthly (chaos) | Push known-bad image to dev, verify rollback |
| Zone failover | Annually | Drain a zone via Azure maintenance, verify HA |
| Full region failover | Annually | Runbook walkthrough + drill in secondary region |

## Known Limitations

- ACR cross-region replication not enabled (restore requires re-push or `az acr import`).
- Dev/staging PostgreSQL has no geo-redundant backup (acceptable for non-prod data).
- Region-level RTO of 2–4 h is manual; automate with multi-region Bicep module if RTO < 1 h becomes a requirement.
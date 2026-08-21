# Networking Design

## VNet Topology

The SecureCloud platform uses a single VNet per environment with dedicated subnets per tier (hub-and-spoke within the VNet).

## Address Plan

| Subnet | CIDR | Purpose | NSG |
|--------|------|---------|-----|
| `snet-ingress-{env}` | 10.0.1.0/24 | Front Door / ingress workloads | nsg-ingress-{env} |
| `snet-compute-{env}` | 10.0.2.0/23 | Container Apps infrastructure | nsg-compute-{env} |
| `snet-data-{env}` | 10.0.4.0/24 | PostgreSQL (delegated) | nsg-data-{env} |
| `snet-private-endpoints-{env}` | 10.0.5.0/24 | Private endpoints for all PaaS | default (implicit) |

Base address space: **10.0.0.0/16** per environment.

## Subnet Details

### snet-ingress
- HTTP/443 ingress (from VNet only, or internet in dev)
- Reserved for Azure Front Door / API Management

### snet-compute
- Delegated to `Microsoft.App/environments` (required for ACA VNet integration)
- Service endpoints: Microsoft.Storage, Microsoft.Sql
- Allows all VNet traffic + Azure LB health probes

### snet-data
- Delegated to `Microsoft.DBforPostgreSQL/flexibleServers`
- Service endpoints: Microsoft.Sql, Microsoft.Storage
- Allows only VNet traffic — database is unreachable from the internet by construction

### snet-private-endpoints
- Hosts all private endpoints (Key Vault, ACR, PostgreSQL)
- `privateLinkServiceNetworkPolicies: Enabled` (default deny for resources not explicitly allowed)
- `privateEndpointNetworkPolicies: Disabled` (endpoints can be reached from VNet)

## NSG Rules

All NSGs follow the same pattern:

| Priority | Direction | Source | Access | Description |
|----------|-----------|--------|--------|-------------|
| 100 | Inbound | VirtualNetwork | Allow | All VNet traffic |
| 200 | Inbound | AzureLoadBalancer | Allow | LB health probes |
| 210* | Inbound | * | Allow | HTTPS (ingress NSG, dev: internet; else: VNet) |
| 4000 | Inbound | * | Deny | Default deny |

\* Ingress NSG only.

## Private Endpoints

| Service | Group ID | Private DNS Zone |
|---------|----------|------------------|
| Key Vault | `vault` | privatelink.vaultcore.azure.net |
| ACR | `registry` | privatelink.azurecr.io |
| PostgreSQL | `postgresql` | privatelink.postgres.database.azure.com |

Each private endpoint sits in `snet-private-endpoints` and gets a DNS zone group pointing at the corresponding private DNS zone. This makes `kv-securecloud-dev-cus.vault.azure.net` etc. resolve to the private IP inside the VNet.

## Private DNS Zones

| Zone | Scope |
|------|-------|
| privatelink.postgres.database.azure.com | All subnets (via VNet link) |
| privatelink.vaultcore.azure.net | All subnets |
| privatelink.azurecr.io | All subnets |
| privatelink.azurewebsites.net | All subnets |
| privatelink.monitor.azure.com | All subnets |
| privatelink.oms.opinsights.azure.com | All subnets |

Registration is **disabled** on all links (private endpoints create their own A records).

## Traffic Flow Example

```
Container App replica
    │
    │  "SELECT ... from kv-securecloud-dev-cus.vault.azure.net"
    v
Private DNS (privatelink.vaultcore.azure.net)
    │  resolves to 10.0.5.x (private endpoint IP)
    v
Private endpoint NIC (snet-private-endpoints)
    │
    v
Key Vault (private link service)
```

No traffic ever leaves the VNet for PaaS access.

## Security Properties

1. **Internet isolation**: Database, Key Vault, and ACR have `publicNetworkAccess: Disabled` (staging/prod). Even if NSGs are misconfigured, the services reject public traffic.
2. **Default deny**: All NSGs end in an explicit DenyAllInbound at priority 4000.
3. **Private link service policies**: Enabled on private-endpoints subnet so only explicitly permitted services are reachable.
4. **Delegated subnets**: Prevents accidental creation of conflicting resources in compute/data subnets.

## Dev vs Prod Differences

| Property | Dev | Staging/Prod |
|----------|-----|--------------|
| Ingress NSG source (HTTP/HTTPS) | * (internet) | VirtualNetwork |
| Service publicNetworkAccess | Enabled | Disabled |
| VNet peering | — | Hub VNet (future) |
/*
================================================================================
SecureCloud Platform - PostgreSQL Flexible Server Module
================================================================================
DEPLOYED TO THE APPS RESOURCE GROUP.
Creates PostgreSQL Flexible Server + private endpoint. References the network
RG's data subnet (delegated) and private DNS zone by computed resource ID.
================================================================================
*/

@description('Environment name')
param environment string

@description('Azure region')
param location string

@description('Resource tags')
param tags object

@description('PostgreSQL server name')
param serverName string

@description('Admin username')
param adminLogin string

@description('Admin password (use Key Vault in production)')
@secure()
param adminPassword string

@description('Network resource group name (holds the VNet)')
param networkResourceGroupName string

@description('VNet name (in the network resource group)')
param vnetName string

@description('Enable public access for development')
param enablePublicAccess bool

// Cross-RG references (computed IDs)
var vnetId = resourceId(networkResourceGroupName, 'Microsoft.Network/virtualNetworks', vnetName)
var dataSubnetId = '${vnetId}/subnets/snet-data-${environment}'
var privateEndpointsSubnetId = '${vnetId}/subnets/snet-private-endpoints-${environment}'
var privateDnsPostgresZoneId = resourceId(networkResourceGroupName, 'Microsoft.Network/privateDnsZones', 'privatelink.postgres.database.azure.com')

// PostgreSQL Flexible Server
resource postgres 'Microsoft.DBforPostgreSQL/flexibleServers@2023-12-01' = {
  name: serverName
  location: location
  tags: tags
  sku: {
    name: environment == 'prod' ? 'Standard_D4ds_v5' : 'Standard_B1ms'
    tier: environment == 'prod' ? 'GeneralPurpose' : 'Burstable'
  }
  properties: {
    administratorLogin: adminLogin
    administratorLoginPassword: adminPassword
    version: '16'
    storage: {
      storageSizeGB: environment == 'prod' ? 128 : 32
      autoGrow: 'Enabled'
    }
    network: {
      delegatedSubnetResourceId: dataSubnetId
      privateDnsZoneArmResourceId: privateDnsPostgresZoneId
      publicNetworkAccess: enablePublicAccess ? 'Enabled' : 'Disabled'
    }
    highAvailability: {
      mode: environment == 'prod' ? 'ZoneRedundant' : 'Disabled'
    }
    backup: {
      backupRetentionDays: environment == 'prod' ? 35 : 7
      geoRedundantBackup: environment == 'prod' ? 'Enabled' : 'Disabled'
      backupIntervalHours: 24
    }
    maintenanceWindow: {
      customWindow: 'Disabled'
    }
  }
}

// Private Endpoint for PostgreSQL
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: 'pe-${serverName}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointsSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'pls-${serverName}'
        properties: {
          privateLinkServiceId: postgres.id
          groupIds: [
            'postgresql'
          ]
          requestMessage: 'Auto-approved for SecureCloud PostgreSQL'
        }
      }
    ]
  }
}

// Private DNS Zone Group for PostgreSQL
resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-postgres-database-azure-com'
        properties: {
          privateDnsZoneId: privateDnsPostgresZoneId
        }
      }
    ]
  }
}

// Outputs
output fullyQualifiedDomainName string = postgres.properties.fqdn
output serverId string = postgres.id
output administratorLogin string = postgres.properties.administratorLogin
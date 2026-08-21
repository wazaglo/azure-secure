/*
================================================================================
SecureCloud Platform - PostgreSQL Flexible Server Module
================================================================================
Creates PostgreSQL with private endpoint, HA, and backup configuration
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

@description('Network resource group name')
param networkResourceGroupName string

@description('VNet name')
param vnetName string

@description('Enable public access for development')
param enablePublicAccess bool

// Reference existing VNet
resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' existing = {
  scope: resourceGroup(networkResourceGroupName)
  name: vnetName
}

// Data subnet
resource dataSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' existing = {
  scope: resourceGroup(networkResourceGroupName)
  parent: vnet
  name: 'snet-data-${environment}'
}

// Private endpoints subnet
resource privateEndpointsSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' existing = {
  scope: resourceGroup(networkResourceGroupName)
  parent: vnet
  name: 'snet-private-endpoints-${environment}'
}

// PostgreSQL Flexible Server
resource postgres 'Microsoft.DBforPostgreSQL/flexibleServers@2023-12-01' = {
  name: serverName
  location: location
  tags: tags
  sku: {
    name: environment == 'prod' ? 'Standard_D4s_v3' : 'Standard_B1ms'
    tier: environment == 'prod' ? 'GeneralPurpose' : 'Burstable'
  }
  properties: {
    administratorLogin: adminLogin
    administratorLoginPassword: adminPassword
    version: '16'
    storage: {
      storageSizeGB: environment == 'prod' ? 128 : 32
      autoGrow: 'Enabled'
      iops: environment == 'prod' ? 3000 : 0
    }
    network: {
      delegatedSubnetResourceId: dataSubnet.id
      privateDnsZoneArmResourceId: resourceId(networkResourceGroupName, 'Microsoft.Network/privateDnsZones', 'privatelink.postgres.database.azure.com')
      publicNetworkAccess: enablePublicAccess ? 'Enabled' : 'Disabled'
    }
    highAvailability: {
      mode: environment == 'prod' ? 'ZoneRedundant' : 'Disabled'
      standbyAvailabilityZone: environment == 'prod' ? '2' : ''
    }
    backup: {
      backupRetentionDays: environment == 'prod' ? 35 : 7
      geoRedundantBackup: environment == 'prod' ? 'Enabled' : 'Disabled'
      backupIntervalHours: 24
    }
    maintenanceWindow: {
      customWindow: 'Disabled'
      dayOfWeek: 0
      startHour: 2
      startMinute: 0
    }
    createMode: 'Default'
  }
}

// Private Endpoint for PostgreSQL
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: 'pe-${serverName}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointsSubnet.id
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
          privateDnsZoneId: resourceId(networkResourceGroupName, 'Microsoft.Network/privateDnsZones', 'privatelink.postgres.database.azure.com')
        }
      }
    ]
  }
}

// Database firewall rule (for Azure services)
resource firewallRule 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2023-12-01' = {
  parent: postgres
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// Outputs
output fullyQualifiedDomainName string = postgres.properties.fullyQualifiedDomainName
output serverId string = postgres.id
output administratorLogin string = postgres.properties.administratorLogin
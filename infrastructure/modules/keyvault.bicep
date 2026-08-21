/*
================================================================================
SecureCloud Platform - Key Vault Module
================================================================================
DEPLOYED TO THE APPS RESOURCE GROUP.
Creates Key Vault + private endpoint. References the network RG's
private-endpoints subnet by computed resource ID (cross-RG reference).
================================================================================
*/

@description('Environment name')
param environment string

@description('Azure region')
param location string

@description('Resource tags')
param tags object

@description('Key Vault name')
param keyVaultName string

@description('Network resource group name (holds the VNet)')
param networkResourceGroupName string

@description('VNet name (in the network resource group)')
param vnetName string

@description('Enable public access for development')
param enablePublicAccess bool

// Cross-RG references (computed IDs)
var vnetId = resourceId(networkResourceGroupName, 'Microsoft.Network/virtualNetworks', vnetName)
var privateEndpointsSubnetId = '${vnetId}/subnets/snet-private-endpoints-${environment}'
var privateDnsVaultZoneId = resourceId(networkResourceGroupName, 'Microsoft.Network/privateDnsZones', 'privatelink.vaultcore.azure.net')

// Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: environment == 'prod' ? 'premium' : 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: environment == 'prod'
    publicNetworkAccess: enablePublicAccess ? 'Enabled' : 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: enablePublicAccess ? 'AzureServices' : 'None'
      ipRules: []
      virtualNetworkRules: []
    }
  }
}

// Private Endpoint for Key Vault
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: 'pe-${keyVaultName}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointsSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'pls-${keyVaultName}'
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: [
            'vault'
          ]
          requestMessage: 'Auto-approved for SecureCloud Key Vault'
        }
      }
    ]
  }
}

// Private DNS Zone Group for Key Vault
resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-vaultcore-azure-net'
        properties: {
          privateDnsZoneId: privateDnsVaultZoneId
        }
      }
    ]
  }
}

// Managed Identity for Key Vault operations
resource keyVaultIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'mi-kv-${environment}'
  location: location
  tags: tags
}

// Role assignment: Key Vault Officer for the identity
resource keyVaultIdentityRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, keyVaultIdentity.id, '00482a5a-887f-4fb3-b363-3b7fe8e74483')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '00482a5a-887f-4fb3-b363-3b7fe8e74483')
    principalId: keyVaultIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
output vaultUri string = keyVault.properties.vaultUri
output keyVaultId string = keyVault.id
output keyVaultNameOut string = keyVault.name
output identityId string = keyVaultIdentity.id
output identityClientId string = keyVaultIdentity.properties.clientId
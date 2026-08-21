/*
================================================================================
SecureCloud Platform - Key Vault Module
================================================================================
Creates Key Vault with RBAC, private endpoint, and secret rotation policies
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

// Private endpoints subnet
resource privateEndpointsSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' existing = {
  scope: resourceGroup(networkResourceGroupName)
  parent: vnet
  name: 'snet-private-endpoints-${environment}'
}

// Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: environment == 'prod' ? 'Premium' : 'Standard'
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
      id: privateEndpointsSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: 'pls-${keyVaultName}'
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: [
            'vault'
          ]
          requestMessage: 'Auto-approved for SecureCloud'
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
          privateDnsZoneId: resourceId(networkResourceGroupName, 'Microsoft.Network/privateDnsZones', 'privatelink.vaultcore.azure.net')
        }
      }
    ]
  }
}

// Managed Identity for Key Vault access
resource keyVaultIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'mi-kv-${environment}'
  location: location
  tags: tags
}

// Role assignment for Key Vault identity
resource keyVaultIdentityRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, keyVaultIdentity.id, '00482a5a-887f-4fb3-b363-3b7fe8e74483')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '00482a5a-887f-4fb3-b363-3b7fe8e74483') // Key Vault Administrator
    principalId: keyVaultIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
output vaultUri string = keyVault.properties.vaultUri
output keyVaultId string = keyVault.id
output identityId string = keyVaultIdentity.id
output identityClientId string = keyVaultIdentity.properties.clientId
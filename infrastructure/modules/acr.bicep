/*
================================================================================
SecureCloud Platform - Azure Container Registry Module
================================================================================
Creates ACR with Premium SKU, private endpoint, and image retention policies
================================================================================
*/

@description('Environment name')
param environment string

@description('Azure region')
param location string

@description('Resource tags')
param tags object

@description('ACR name (must be globally unique)')
param acrName string

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

// Azure Container Registry
resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' = {
  name: acrName
  location: location
  tags: tags
  sku: {
    name: 'Premium'
    tier: 'Premium'
  }
  properties: {
    adminUserEnabled: false
    anonymousPullEnabled: false
    publicNetworkAccess: enablePublicAccess ? 'Enabled' : 'Disabled'
    networkRuleBypassOptions: 'AzureServices'
    networkRuleSet: {
      defaultAction: 'Deny'
      ipRules: []
      virtualNetworkRules: []
    }
    policies: {
      quarantinePolicy: {
        status: environment == 'prod' ? 'enabled' : 'disabled'
      }
      retentionPolicy: {
        days: environment == 'prod' ? 30 : 7
        status: 'enabled'
      }
      softDeletePolicy: {
        retentionDays: 90
        status: 'enabled'
      }
      trustPolicy: {
        type: 'Notary'
        status: environment == 'prod' ? 'enabled' : 'disabled'
      }
      exportPolicy: {
        status: 'enabled'
      }
    }
    zoneRedundancy: environment == 'prod' ? 'Enabled' : 'Disabled'
    dataEndpointEnabled: true
    encryption: {
      status: 'Enabled'
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Private Endpoint for ACR
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: 'pe-${acrName}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointsSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: 'pls-${acrName}'
        properties: {
          privateLinkServiceId: acr.id
          groupIds: [
            'registry'
          ]
          requestMessage: 'Auto-approved for SecureCloud ACR'
        }
      }
    ]
  }
}

// Private DNS Zone Group for ACR
resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-azurecr-io'
        properties: {
          privateDnsZoneId: resourceId(networkResourceGroupName, 'Microsoft.Network/privateDnsZones', 'privatelink.azurecr.io')
        }
      }
    ]
  }
}

// Role assignment for AcrPull (for Container Apps)
resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, 'acr-pull-role')
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    principalId: subscription().tenantId // Will be updated with actual identity
    principalType: 'ServicePrincipal'
  }
}

// Outputs
output loginServer string = acr.properties.loginServer
output acrId string = acr.id
output identityId string = acr.identity.principalId
output identityClientId string = acr.identity.clientId
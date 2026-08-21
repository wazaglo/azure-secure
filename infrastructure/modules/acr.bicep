/*
================================================================================
SecureCloud Platform - Azure Container Registry Module
================================================================================
DEPLOYED TO THE APPS RESOURCE GROUP.
Creates ACR (Premium) + private endpoint. References the network RG's
private-endpoints subnet by computed resource ID (cross-RG reference).
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

@description('Network resource group name (holds the VNet)')
param networkResourceGroupName string

@description('VNet name (in the network resource group)')
param vnetName string

@description('Enable public access for development')
param enablePublicAccess bool

// Cross-RG references (computed IDs)
var vnetId = resourceId(networkResourceGroupName, 'Microsoft.Network/virtualNetworks', vnetName)
var privateEndpointsSubnetId = '${vnetId}/subnets/snet-private-endpoints-${environment}'
var privateDnsAcrZoneId = resourceId(networkResourceGroupName, 'Microsoft.Network/privateDnsZones', 'privatelink.azurecr.io')

// Azure Container Registry
resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' = {
  name: acrName
  location: location
  tags: tags
  sku: {
    name: 'Premium'
  }
  properties: {
    adminUserEnabled: true
    anonymousPullEnabled: false
    publicNetworkAccess: enablePublicAccess ? 'Enabled' : 'Disabled'
    networkRuleBypassOptions: 'AzureServices'
    networkRuleSet: {
      defaultAction: enablePublicAccess ? 'Allow' : 'Deny'
      ipRules: []
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
      id: privateEndpointsSubnetId
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
          privateDnsZoneId: privateDnsAcrZoneId
        }
      }
    ]
  }
}

// Outputs
output loginServer string = acr.properties.loginServer
output acrNameOut string = acr.name
output acrId string = acr.id
output identityPrincipalId string = acr.identity.principalId
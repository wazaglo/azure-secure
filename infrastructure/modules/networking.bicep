/*
================================================================================
SecureCloud Platform - Networking Module
================================================================================
DEPLOYED TO THE NETWORK RESOURCE GROUP.
Creates VNet, subnets, NSGs, Private DNS Zones and VNet links.
Other modules reference these resources by computed ID (different RG).
================================================================================
*/

@description('Environment name')
param environment string

@description('Azure region')
param location string

@description('Resource tags')
param tags object

@description('VNet name (in the deployment resource group)')
param vnetName string

@description('Enable public access for development')
param enablePublicAccess bool

// ---------------------------------------------------------------------------
// NSG security rules
// ---------------------------------------------------------------------------
var commonInbound = [
  {
    name: 'AllowVNetInbound'
    priority: 100
    direction: 'Inbound'
    access: 'Allow'
    protocol: '*'
    sourcePortRange: '*'
    destinationPortRange: '*'
    sourceAddressPrefix: 'VirtualNetwork'
    destinationAddressPrefix: '*'
    description: 'Allow all traffic from within the VNet'
  }
  {
    name: 'AllowAzureLoadBalancer'
    priority: 200
    direction: 'Inbound'
    access: 'Allow'
    protocol: '*'
    sourcePortRange: '*'
    destinationPortRange: '*'
    sourceAddressPrefix: 'AzureLoadBalancer'
    destinationAddressPrefix: '*'
    description: 'Allow Azure Load Balancer health probes'
  }
  {
    name: 'DenyAllInbound'
    priority: 4000
    direction: 'Inbound'
    access: 'Deny'
    protocol: '*'
    sourcePortRange: '*'
    destinationPortRange: '*'
    sourceAddressPrefix: '*'
    destinationAddressPrefix: '*'
    description: 'Default deny all other inbound traffic'
  }
]

var ingressOnly = [
  {
    name: 'AllowHttp'
    priority: 300
    direction: 'Inbound'
    access: 'Allow'
    protocol: 'Tcp'
    sourcePortRange: '*'
    destinationPortRange: '80'
    sourceAddressPrefix: enablePublicAccess ? 'Internet' : 'VirtualNetwork'
    destinationAddressPrefix: '*'
    description: 'Allow HTTP'
  }
  {
    name: 'AllowHttps'
    priority: 310
    direction: 'Inbound'
    access: 'Allow'
    protocol: 'Tcp'
    sourcePortRange: '*'
    destinationPortRange: '443'
    sourceAddressPrefix: enablePublicAccess ? 'Internet' : 'VirtualNetwork'
    destinationAddressPrefix: '*'
    description: 'Allow HTTPS'
  }
]

// Subnet prefixes
var ingressPrefix = '10.0.1.0/24'
var computePrefix = '10.0.2.0/23'
var dataPrefix = '10.0.4.0/24'
var privateEndpointsPrefix = '10.0.5.0/24'

// Private DNS zones
var privateDnsZoneNames = [
  'privatelink.postgres.database.azure.com'
  'privatelink.vaultcore.azure.net'
  'privatelink.azurecr.io'
  'privatelink.azurewebsites.net'
  'privatelink.monitor.azure.com'
  'privatelink.oms.opinsights.azure.com'
]

// ---------------------------------------------------------------------------
// Network Security Groups
// ---------------------------------------------------------------------------
resource nsgCompute 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'nsg-compute-${environment}'
  location: location
  tags: tags
  properties: {
    securityRules: [for rule in commonInbound: {
      name: rule.name
      properties: {
        priority: rule.priority
        direction: rule.direction
        access: rule.access
        protocol: rule.protocol
        sourcePortRange: rule.sourcePortRange
        destinationPortRange: rule.destinationPortRange
        sourceAddressPrefix: rule.sourceAddressPrefix
        destinationAddressPrefix: rule.destinationAddressPrefix
        description: rule.description
      }
    }]
  }
}

resource nsgData 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'nsg-data-${environment}'
  location: location
  tags: tags
  properties: {
    securityRules: [for rule in commonInbound: {
      name: rule.name
      properties: {
        priority: rule.priority
        direction: rule.direction
        access: rule.access
        protocol: rule.protocol
        sourcePortRange: rule.sourcePortRange
        destinationPortRange: rule.destinationPortRange
        sourceAddressPrefix: rule.sourceAddressPrefix
        destinationAddressPrefix: rule.destinationAddressPrefix
        description: rule.description
      }
    }]
  }
}

resource nsgIngress 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'nsg-ingress-${environment}'
  location: location
  tags: tags
  properties: {
    securityRules: [for rule in union(commonInbound, ingressOnly): {
      name: rule.name
      properties: {
        priority: rule.priority
        direction: rule.direction
        access: rule.access
        protocol: rule.protocol
        sourcePortRange: rule.sourcePortRange
        destinationPortRange: rule.destinationPortRange
        sourceAddressPrefix: rule.sourceAddressPrefix
        destinationAddressPrefix: rule.destinationAddressPrefix
        description: rule.description
      }
    }]
  }
}

// ---------------------------------------------------------------------------
// Virtual Network (subnets defined inline to allow NSG references)
// ---------------------------------------------------------------------------
resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'snet-ingress-${environment}'
        properties: {
          addressPrefix: ingressPrefix
          networkSecurityGroup: {
            id: nsgIngress.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: 'snet-compute-${environment}'
        properties: {
          addressPrefix: computePrefix
          networkSecurityGroup: {
            id: nsgCompute.id
          }
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
            }
            {
              service: 'Microsoft.Sql'
            }
          ]
          delegations: [
            {
              name: 'delegation-containerapps'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: 'snet-data-${environment}'
        properties: {
          addressPrefix: dataPrefix
          networkSecurityGroup: {
            id: nsgData.id
          }
          serviceEndpoints: [
            {
              service: 'Microsoft.Sql'
            }
            {
              service: 'Microsoft.Storage'
            }
          ]
          delegations: [
            {
              name: 'delegation-postgresql'
              properties: {
                serviceName: 'Microsoft.DBforPostgreSQL/flexibleServers'
              }
            }
          ]
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: 'snet-private-endpoints-${environment}'
        properties: {
          addressPrefix: privateEndpointsPrefix
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Private DNS Zones + VNet links
// ---------------------------------------------------------------------------
resource dnsZones 'Microsoft.Network/privateDnsZones@2020-06-01' = [for zoneName in privateDnsZoneNames: {
  name: zoneName
  location: 'global'
  tags: tags
  properties: {}
}]

resource vnetLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (zoneName, i) in privateDnsZoneNames: {
  parent: dnsZones[i]
  name: 'link-${vnetName}'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}]

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output vnetId string = vnet.id
output ingressSubnetId string = '${vnet.id}/subnets/snet-ingress-${environment}'
output computeSubnetId string = '${vnet.id}/subnets/snet-compute-${environment}'
output dataSubnetId string = '${vnet.id}/subnets/snet-data-${environment}'
output privateEndpointsSubnetId string = '${vnet.id}/subnets/snet-private-endpoints-${environment}'
output nsgComputeId string = nsgCompute.id
output nsgDataId string = nsgData.id
output nsgIngressId string = nsgIngress.id
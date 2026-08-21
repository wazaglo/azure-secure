/*
================================================================================
SecureCloud Platform - Networking Module
================================================================================
Creates or references VNet, subnets, NSGs, Private DNS Zones, and Private Endpoints
================================================================================
*/

@description('Environment name')
param environment string

@description('Azure region')
param location string

@description('Resource tags')
param tags object

@description('Network resource group name')
param networkResourceGroupName string

@description('VNet name')
param vnetName string

@description('Enable public access for development')
param enablePublicAccess bool

// VNet address space
var vnetAddressSpace = '10.0.0.0/16'

// Subnet configuration
var subnets = [
  {
    name: 'snet-ingress-${environment}'
    addressPrefix: '10.0.1.0/24'
    serviceEndpoints: []
    delegations: []
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
  {
    name: 'snet-compute-${environment}'
    addressPrefix: '10.0.2.0/23'
    serviceEndpoints: [
      'Microsoft.Storage'
      'Microsoft.Sql'
    ]
    delegations: [
      {
        name: 'delegation-containerapps'
        serviceName: 'Microsoft.App/environments'
      }
    ]
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
  {
    name: 'snet-data-${environment}'
    addressPrefix: '10.0.4.0/24'
    serviceEndpoints: [
      'Microsoft.Sql'
      'Microsoft.Storage'
    ]
    delegations: [
      {
        name: 'delegation-postgresql'
        serviceName: 'Microsoft.DBforPostgreSQL/flexibleServers'
      }
    ]
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
  {
    name: 'snet-private-endpoints-${environment}'
    addressPrefix: '10.0.5.0/24'
    serviceEndpoints: []
    delegations: []
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
]

// NSG Rules
var nsgRulesCompute = [
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
    description: 'Allow all traffic from VNet'
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
    description: 'Deny all other inbound traffic'
  }
]

var nsgRulesData = [
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
    description: 'Allow all traffic from VNet'
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
    description: 'Deny all other inbound traffic'
  }
]

var nsgRulesIngress = [
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
    description: 'Allow all traffic from VNet'
  }
  {
    name: 'AllowHttp'
    priority: 200
    direction: 'Inbound'
    access: 'Allow'
    protocol: 'Tcp'
    sourcePortRange: '*'
    destinationPortRange: '80'
    sourceAddressPrefix: enablePublicAccess ? '*' : 'VirtualNetwork'
    destinationAddressPrefix: '*'
    description: 'Allow HTTP traffic'
  }
  {
    name: 'AllowHttps'
    priority: 210
    direction: 'Inbound'
    access: 'Allow'
    protocol: 'Tcp'
    sourcePortRange: '*'
    destinationPortRange: '443'
    sourceAddressPrefix: enablePublicAccess ? '*' : 'VirtualNetwork'
    destinationAddressPrefix: '*'
    description: 'Allow HTTPS traffic'
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
    description: 'Deny all other inbound traffic'
  }
]

// Private DNS Zones
var privateDnsZones = [
  'privatelink.postgres.database.azure.com'
  'privatelink.vaultcore.azure.net'
  'privatelink.azurecr.io'
  'privatelink.azurewebsites.net'
  'privatelink.monitor.azure.com'
  'privatelink.oms.opinsights.azure.com'
]

// Resources

// VNet (reference existing or create new)
resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' existing = {
  scope: resourceGroup(networkResourceGroupName)
  name: vnetName
}

// Subnets
resource subnets 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = [for subnet in subnets: {
  parent: vnet
  name: subnet.name
  properties: {
    addressPrefix: subnet.addressPrefix
    serviceEndpoints: [for endpoint in subnet.serviceEndpoints: {
      service: endpoint
    }]
    delegations: [for delegation in subnet.delegations: {
      name: delegation.name
      properties: {
        serviceName: delegation.serviceName
      }
    }]
    privateEndpointNetworkPolicies: subnet.privateEndpointNetworkPolicies
    privateLinkServiceNetworkPolicies: subnet.privateLinkServiceNetworkPolicies
  }
}]

// Network Security Groups
resource nsgCompute 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'nsg-compute-${environment}'
  location: location
  tags: tags
  properties: {
    securityRules: [for rule in nsgRulesCompute: {
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
    securityRules: [for rule in nsgRulesData: {
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
    securityRules: [for rule in nsgRulesIngress: {
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

// Subnet NSG associations
resource subnetNsgAssociations 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = [for (subnet, i) in subnets: {
  parent: vnet
  name: subnet.name
  properties: {
    addressPrefix: subnet.addressPrefix
    networkSecurityGroup: (subnet.name.contains('compute') ? nsgCompute.id : subnet.name.contains('data') ? nsgData.id : subnet.name.contains('ingress') ? nsgIngress.id : null)
    serviceEndpoints: [for endpoint in subnet.serviceEndpoints: {
      service: endpoint
    }]
    delegations: [for delegation in subnet.delegations: {
      name: delegation.name
      properties: {
        serviceName: delegation.serviceName
      }
    }]
    privateEndpointNetworkPolicies: subnet.privateEndpointNetworkPolicies
    privateLinkServiceNetworkPolicies: subnet.privateLinkServiceNetworkPolicies
  }
}]

// Private DNS Zones
resource privateDnsZones 'Microsoft.Network/privateDnsZones@2020-06-01' = [for zoneName in privateDnsZones: {
  name: zoneName
  location: 'global'
  tags: tags
  properties: {}
}]

// VNet Links for Private DNS Zones
resource vnetLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (zoneName, i) in privateDnsZones: {
  parent: privateDnsZones[i]
  name: 'link-${networkResourceGroupName}'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}]

// Outputs
output vnetId string = vnet.id
output computeSubnetId string = subnets[1].id
output dataSubnetId string = subnets[2].id
output privateEndpointsSubnetId string = subnets[3].id
output nsgComputeId string = nsgCompute.id
output nsgDataId string = nsgData.id
output privateDnsZoneIds array = [for zone in privateDnsZones: zone.id]
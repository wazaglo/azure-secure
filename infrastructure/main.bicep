/*
================================================================================
SecureCloud Platform - Main Bicep Template (SINGLE ENVIRONMENT)
================================================================================
Deploys the app-tier infrastructure (Monitoring, Container Apps Environment,
Container App, Managed Identities, RBAC) into the APPS resource group.

The NETWORKING layer (VNet, subnets, private DNS) and the shared platform
services (Key Vault, ACR, PostgreSQL) already live in a separate resource
group (`rg-securecloud-dev-networking-centralus`) and are referenced here as
EXISTING resources (cross-RG) - they are NOT re-created, which avoids
globally-unique name conflicts.

Deploy:
  az deployment group create -g <apps-RG> -f infrastructure/main.bicep \
    -p @infrastructure/environments/dev/main.parameters.json
================================================================================
*/

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string

@description('Azure region for deployment')
param location string = resourceGroup().location

@description('Tags for all resources')
param tags object = {
  Environment: environment
  Project: 'securecloud'
  ManagedBy: 'bicep'
  Repository: 'github.com/wazaglo/azure-secure'
}

@description('Network resource group name (existing, holds the VNet + shared services)')
param networkResourceGroupName string

@description('VNet name (existing, in the network resource group)')
param vnetName string

@description('Key Vault name (existing, in the network resource group)')
param keyVaultName string

@description('ACR name (existing, in the network resource group)')
param acrName string

@description('PostgreSQL server name (existing, in the network resource group)')
param postgresServerName string

@description('Container Apps Environment name')
param containerAppsEnvName string

@description('Container App name')
param containerAppName string

@description('Log Analytics Workspace name')
param logAnalyticsWorkspaceName string

@description('Application Insights name')
param appInsightsName string

@description('Managed Identity name for the application')
param appIdentityName string

@description('Managed Identity name for GitHub Actions')
param githubIdentityName string

@description('Enable public access for development')
param enablePublicAccess bool = (environment == 'dev')

@description('Container image to deploy (empty = use ACR :latest)')
param containerImage string

@description('Container CPU cores (decimal, passed via JSON params)')
param containerCpu any

// Resource IDs for the existing shared services (network resource group)
var keyVaultId = resourceId(networkResourceGroupName, 'Microsoft.KeyVault/vaults', keyVaultName)
var acrId = resourceId(networkResourceGroupName, 'Microsoft.ContainerRegistry/registries', acrName)
var postgresId = resourceId(networkResourceGroupName, 'Microsoft.DBforPostgreSQL/flexibleServers', postgresServerName)

// ---------------------------------------------------------------------------
// Existing shared platform resources (networking resource group)
// ---------------------------------------------------------------------------
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
  scope: resourceGroup(networkResourceGroupName)
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' existing = {
  name: acrName
  scope: resourceGroup(networkResourceGroupName)
}

resource postgres 'Microsoft.DBforPostgreSQL/flexibleServers@2023-12-01' existing = {
  name: postgresServerName
  scope: resourceGroup(networkResourceGroupName)
}

// ---------------------------------------------------------------------------
// Monitoring
// ---------------------------------------------------------------------------
module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring-${environment}'
  params: {
    environment: environment
    location: location
    tags: tags
    workspaceName: logAnalyticsWorkspaceName
    appInsightsName: appInsightsName
  }
}

// ---------------------------------------------------------------------------
// Container Apps + Managed Identities
// ---------------------------------------------------------------------------
module containerapps 'modules/containerapps.bicep' = {
  name: 'containerapps-${environment}'
  params: {
    environment: environment
    location: location
    tags: tags
    containerAppsEnvName: containerAppsEnvName
    containerAppName: containerAppName
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
    workspaceCustomerId: monitoring.outputs.workspaceCustomerId
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    acrLoginServer: acr.properties.loginServer
    keyVaultUri: keyVault.properties.vaultUri
    appIdentityName: appIdentityName
    githubIdentityName: githubIdentityName
    containerImage: containerImage
    containerCpu: containerCpu
    enablePublicAccess: enablePublicAccess
  }
}

// ---------------------------------------------------------------------------
// RBAC scoped to the EXISTING Key Vault / ACR (network resource group).
// This must run in a module deployed at the network RG scope.
// ---------------------------------------------------------------------------
module rbac 'modules/rbac.bicep' = {
  name: 'rbac-${environment}'
  scope: resourceGroup(networkResourceGroupName)
  params: {
    keyVaultName: keyVaultName
    acrName: acrName
    appIdentityName: appIdentityName
    githubIdentityName: githubIdentityName
    appIdentityPrincipalId: containerapps.outputs.appIdentityPrincipalId
    githubIdentityPrincipalId: containerapps.outputs.githubIdentityPrincipalId
  }
}

// GitHub Actions identity: Contributor on the apps resource group
resource githubIdentityContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, githubIdentityName, 'contributor-rg')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
    principalId: containerapps.outputs.githubIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output acrLoginServer string = acr.properties.loginServer
output keyVaultUri string = keyVault.properties.vaultUri
output postgresFqdn string = postgres.properties.fullyQualifiedDomainName
output containerAppFqdn string = containerapps.outputs.containerAppFqdn
output appIdentityClientId string = containerapps.outputs.appIdentityClientId
output githubIdentityClientId string = containerapps.outputs.githubIdentityClientId
output appInsightsConnectionString string = monitoring.outputs.appInsightsConnectionString

/*
================================================================================
SecureCloud Platform - Main Bicep Template
================================================================================
Deploys complete infrastructure for the SecureCloud platform
Supports dev, staging, and prod environments
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

@description('Network resource group name (existing)')
param networkResourceGroupName string = 'rg-securecloud-${environment}-networking'

@description('VNet name (existing)')
param vnetName string = 'vnet-securecloud-${environment}'

@description('Key Vault name (existing or new)')
param keyVaultName string = 'kv-securecloud-${environment}'

@description('ACR name (existing or new)')
param acrName string = 'acrsecurecloud${uniqueString(resourceGroup().id)}'

@description('PostgreSQL server name')
param postgresServerName string = 'pg-securecloud-${environment}'

@description('PostgreSQL admin username')
param postgresAdminLogin string = 'dbadmin'

@description('PostgreSQL admin password (use Key Vault in production)')
@secure()
param postgresAdminPassword string

@description('Container Apps Environment name')
param containerAppsEnvName string = 'cae-securecloud-${environment}'

@description('Container App name')
param containerAppName string = 'app-securecloud-${environment}'

@description('Log Analytics Workspace name')
param logAnalyticsWorkspaceName string = 'law-securecloud-${environment}'

@description('Application Insights name')
param appInsightsName string = 'ai-securecloud-${environment}'

@description('Managed Identity name for app')
param appIdentityName string = 'mi-securecloud-app-${environment}'

@description('Managed Identity name for GitHub Actions')
param githubIdentityName string = 'mi-github-${environment}'

@description('Enable public access for development')
param enablePublicAccess bool = (environment == 'dev')

@description('Container image to deploy')
param containerImage string = ''

@description('Container registry server')
param containerRegistryServer string = ''

@description('Container registry identity')
param containerRegistryIdentity string = 'system'

// Module references
module networking 'modules/networking.bicep' = {
  name: 'networking-${environment}'
  params: {
    environment: environment
    location: location
    tags: tags
    networkResourceGroupName: networkResourceGroupName
    vnetName: vnetName
    enablePublicAccess: enablePublicAccess
  }
}

module keyvault 'modules/keyvault.bicep' = {
  name: 'keyvault-${environment}'
  params: {
    environment: environment
    location: location
    tags: tags
    keyVaultName: keyVaultName
    networkResourceGroupName: networkResourceGroupName
    vnetName: vnetName
    enablePublicAccess: enablePublicAccess
  }
}

module acr 'modules/acr.bicep' = {
  name: 'acr-${environment}'
  params: {
    environment: environment
    location: location
    tags: tags
    acrName: acrName
    networkResourceGroupName: networkResourceGroupName
    vnetName: vnetName
    enablePublicAccess: enablePublicAccess
  }
}

module postgres 'modules/postgres.bicep' = {
  name: 'postgres-${environment}'
  params: {
    environment: environment
    location: location
    tags: tags
    serverName: postgresServerName
    adminLogin: postgresAdminLogin
    adminPassword: postgresAdminPassword
    networkResourceGroupName: networkResourceGroupName
    vnetName: vnetName
    enablePublicAccess: enablePublicAccess
  }
}

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

module containerapps 'modules/containerapps.bicep' = {
  name: 'containerapps-${environment}'
  params: {
    environment: environment
    location: location
    tags: tags
    containerAppsEnvName: containerAppsEnvName
    containerAppName: containerAppName
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    acrLoginServer: acr.outputs.loginServer
    acrIdentity: acr.outputs.identityId
    keyVaultUri: keyvault.outputs.vaultUri
    keyVaultIdentity: keyvault.outputs.identityId
    postgresFqdn: postgres.outputs.fullyQualifiedDomainName
    appIdentityName: appIdentityName
    githubIdentityName: githubIdentityName
    containerImage: containerImage
    enablePublicAccess: enablePublicAccess
  }
}

// Outputs
output acrLoginServer string = acr.outputs.loginServer
output keyVaultUri string = keyvault.outputs.vaultUri
output postgresFqdn string = postgres.outputs.fullyQualifiedDomainName
output containerAppFqdn string = containerapps.outputs.containerAppFqdn
output appIdentityClientId string = containerapps.outputs.appIdentityClientId
output githubIdentityClientId string = containerapps.outputs.githubIdentityClientId
output appInsightsConnectionString string = monitoring.outputs.appInsightsConnectionString
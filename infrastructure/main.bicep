/*
================================================================================
SecureCloud Platform - Main Bicep Template
================================================================================
Deploys the app-tier infrastructure (Key Vault, ACR, PostgreSQL, Monitoring,
Container Apps) to the APPS resource group.

The NETWORKING layer (VNet, subnets, NSGs, private DNS) lives in a separate
resource group and is deployed with modules/networking.bicep. This template
references it by resource-group name + VNet name.

Deploy order:
  1. az deployment group create -g <network-RG> -f infrastructure/modules/networking.bicep ...
  2. az deployment group create -g <apps-RG>    -f infrastructure/main.bicep ...
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

@description('Network resource group name (existing, holds the VNet)')
param networkResourceGroupName string

@description('VNet name (existing, in the network resource group)')
param vnetName string

@description('Key Vault name')
param keyVaultName string

@description('ACR name (globally unique)')
param acrName string

@description('PostgreSQL server name')
param postgresServerName string

@description('PostgreSQL admin username')
param postgresAdminLogin string

@description('PostgreSQL admin password (use Key Vault reference in production)')
@secure()
param postgresAdminPassword string

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
// Key Vault
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// Azure Container Registry
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// PostgreSQL
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// Container Apps + Managed Identities + RBAC
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
    acrLoginServer: acr.outputs.loginServer
    acrName: acrName
    keyVaultUri: keyvault.outputs.vaultUri
    keyVaultName: keyVaultName
    postgresFqdn: postgres.outputs.fullyQualifiedDomainName
    appIdentityName: appIdentityName
    githubIdentityName: githubIdentityName
    containerImage: containerImage
    containerCpu: containerCpu
    enablePublicAccess: enablePublicAccess
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output acrLoginServer string = acr.outputs.loginServer
output keyVaultUri string = keyvault.outputs.vaultUri
output postgresFqdn string = postgres.outputs.fullyQualifiedDomainName
output containerAppFqdn string = containerapps.outputs.containerAppFqdn
output appIdentityClientId string = containerapps.outputs.appIdentityClientId
output githubIdentityClientId string = containerapps.outputs.githubIdentityClientId
output appInsightsConnectionString string = monitoring.outputs.appInsightsConnectionString
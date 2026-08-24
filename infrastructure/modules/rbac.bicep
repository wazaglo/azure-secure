/*
================================================================================
SecureCloud Platform - RBAC Module
================================================================================
Deployed at the NETWORK resource group scope (where the shared Key Vault and
ACR live). Assigns roles to the app + GitHub Actions managed identities
created by the containerapps module.

This module MUST be deployed with `scope: resourceGroup(networkResourceGroupName)`
from main.bicep, because role assignments on the KV/ACR can only be created
from within that resource group's scope.
================================================================================
*/

@description('Key Vault name (this resource group)')
param keyVaultName string

@description('ACR name (this resource group)')
param acrName string

@description('App managed identity name (used only to build a stable role assignment name)')
param appIdentityName string

@description('GitHub Actions managed identity name (used only to build a stable role assignment name)')
param githubIdentityName string

@description('App managed identity principal ID')
param appIdentityPrincipalId string

@description('GitHub Actions managed identity principal ID')
param githubIdentityPrincipalId string

// Existing shared resources in this (network) resource group
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' existing = {
  name: acrName
}

// Role definition IDs
var keyVaultSecretsUser = '4633458b-17de-408a-b874-0445c86b69e6'
var acrPull = '7f951dda-4ed3-4680-a7ca-43fe172d538d'
var acrPush = '8311e382-0749-4cb8-b61a-304f252e45ec'
var keyVaultOfficer = '00482a5a-887f-4fb3-b363-3b7fe8e74483'

// App identity: read Key Vault secrets + pull from ACR
resource appIdentityKeyVaultRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, appIdentityName, 'kv-secrets-user')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUser)
    principalId: appIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource appIdentityAcrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, appIdentityName, 'acr-pull')
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPull)
    principalId: appIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// GitHub Actions identity: push to ACR + KV officer
resource githubIdentityAcrPushRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, githubIdentityName, 'acr-push')
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPush)
    principalId: githubIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource githubIdentityKeyVaultOfficerRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, githubIdentityName, 'kv-officer')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultOfficer)
    principalId: githubIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

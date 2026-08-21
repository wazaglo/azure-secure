/*
================================================================================
SecureCloud Platform - Container Apps Module
================================================================================
DEPLOYED TO THE APPS RESOURCE GROUP.
Creates Container Apps Environment + Container App + Managed Identities + RBAC.
References KV/ACR (same RG) by name and the Log Analytics workspace by ID.
================================================================================
*/

@description('Environment name')
param environment string

@description('Azure region')
param location string

@description('Resource tags')
param tags object

@description('Container Apps Environment name')
param containerAppsEnvName string

@description('Container App name')
param containerAppName string

@description('Log Analytics Workspace resource ID')
param logAnalyticsWorkspaceId string

@description('Log Analytics Workspace customer ID')
param workspaceCustomerId string

@description('Application Insights Connection String')
@secure()
param appInsightsConnectionString string

@description('ACR Login Server hostname')
param acrLoginServer string

@description('ACR registry name (same resource group)')
param acrName string

@description('Key Vault URI')
@secure()
param keyVaultUri string

@description('Key Vault name (same resource group)')
param keyVaultName string

@description('PostgreSQL FQDN (for reference)')
param postgresFqdn string

@description('App Managed Identity name')
param appIdentityName string

@description('GitHub Actions Managed Identity name')
param githubIdentityName string

@description('Container image to deploy')
param containerImage string

@description('Enable public access for development')
param enablePublicAccess bool

@description('Container CPU cores (decimal, passed via JSON params)')
param containerCpu any

// Container sizing per environment
var isProd = environment == 'prod'
var containerMemory = isProd ? '2Gi' : '1Gi'
var minReplicas = isProd ? 2 : 1
var maxReplicas = isProd ? 10 : 3

// Same-RG references (KV and ACR created by sibling modules in this RG)
resource keyVaultRef 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource acrRef 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' existing = {
  name: acrName
}

// Container Apps Environment
resource containerAppsEnv 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: containerAppsEnvName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: workspaceCustomerId
        sharedKey: listKeys(logAnalyticsWorkspaceId, '2022-10-01').primarySharedKey
      }
    }
    zoneRedundant: environment == 'prod'
  }
}

// App Managed Identity
resource appIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: appIdentityName
  location: location
  tags: tags
}

// GitHub Actions Managed Identity
resource githubIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: githubIdentityName
  location: location
  tags: tags
}

// ---------------------------------------------------------------------------
// RBAC - App identity
// ---------------------------------------------------------------------------
resource appIdentityKeyVaultRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(appIdentity.id, 'keyvault-secrets-user')
  scope: keyVaultRef
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
    principalId: appIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource appIdentityAcrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(appIdentity.id, 'acr-pull')
  scope: acrRef
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
    principalId: appIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ---------------------------------------------------------------------------
// RBAC - GitHub identity
// ---------------------------------------------------------------------------
resource githubIdentityContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(githubIdentity.id, 'contributor-rg')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
    principalId: githubIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource githubIdentityAcrPushRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(githubIdentity.id, 'acr-push')
  scope: acrRef
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8311e382-0749-4cb8-b61a-304f252e45ec')
    principalId: githubIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource githubIdentityKeyVaultOfficerRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(githubIdentity.id, 'keyvault-officer')
  scope: keyVaultRef
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '00482a5a-887f-4fb3-b363-3b7fe8e74483')
    principalId: githubIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Container App
resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: containerAppName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${appIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppsEnv.id
    configuration: {
      ingress: {
        external: enablePublicAccess
        targetPort: 5000
        transport: 'http'
        allowInsecure: false
      }
      secrets: [
        {
          name: 'key-vault-uri'
          value: keyVaultUri
        }
        {
          name: 'app-insights-connection-string'
          value: appInsightsConnectionString
        }
      ]
      registries: [
        {
          server: acrLoginServer
          identity: appIdentity.id
        }
      ]
      activeRevisionsMode: environment == 'prod' ? 'multiple' : 'single'
    }
    template: {
      containers: [
        {
          name: 'securecloud-app'
          image: containerImage != '' ? containerImage : '${acrLoginServer}/securecloud-app:latest'
          resources: {
            cpu: containerCpu
            memory: containerMemory
          }
          env: [
            {
              name: 'KEY_VAULT_URI'
              secretRef: 'key-vault-uri'
            }
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              secretRef: 'app-insights-connection-string'
            }
            {
              name: 'ENVIRONMENT'
              value: environment
            }
            {
              name: 'AZURE_CLIENT_ID'
              value: appIdentity.properties.clientId
            }
            {
              name: 'PYTHONUNBUFFERED'
              value: '1'
            }
            {
              name: 'PYTHONDONTWRITEBYTECODE'
              value: '1'
            }
          ]
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/health/live'
                port: 5000
                scheme: 'HTTP'
              }
              initialDelaySeconds: 10
              periodSeconds: 30
              timeoutSeconds: 5
              failureThreshold: 3
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/health/ready'
                port: 5000
                scheme: 'HTTP'
              }
              initialDelaySeconds: 5
              periodSeconds: 10
              timeoutSeconds: 3
              failureThreshold: 3
            }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '50'
              }
            }
          }
        ]
      }
    }
  }
}

// Outputs
output containerAppFqdn string = containerApp.properties.configuration.ingress.fqdn
output appIdentityClientId string = appIdentity.properties.clientId
output appIdentityPrincipalId string = appIdentity.properties.principalId
output githubIdentityClientId string = githubIdentity.properties.clientId
output githubIdentityPrincipalId string = githubIdentity.properties.principalId
/*
================================================================================
SecureCloud Platform - Container Apps Module
================================================================================
Creates Container Apps Environment, Container App, and Managed Identities
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

@description('Log Analytics Workspace ID')
param logAnalyticsWorkspaceId string

@description('Application Insights Connection String')
param appInsightsConnectionString string

@description('ACR Login Server')
param acrLoginServer string

@description('ACR Identity ID')
param acrIdentity string

@description('Key Vault URI')
param keyVaultUri string

@description('Key Vault Identity ID')
param keyVaultIdentity string

@description('PostgreSQL FQDN')
param postgresFqdn string

@description('App Managed Identity name')
param appIdentityName string

@description('GitHub Actions Managed Identity name')
param githubIdentityName string

@description('Container image to deploy')
param containerImage string

@description('Enable public access for development')
param enablePublicAccess bool

// Log Analytics Workspace reference
resource workspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' existing = {
  id: logAnalyticsWorkspaceId
}

// Container Apps Environment
resource containerAppsEnv 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: containerAppsEnvName
  location: location
  tags: tags
  properties: {
    vnetConfiguration: {
      infrastructureSubnetId: '' // Will be set via subnet reference
      internal: true
    }
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: workspace.properties.customerId
        sharedKey: listKeys(workspace.id, workspace.apiVersion).primarySharedKey
      }
    }
    daprAIConnectionString: appInsightsConnectionString
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

// Role assignments for App Identity
resource appIdentityKeyVaultRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(appIdentity.id, 'keyvault-secrets-user')
  scope: resourceId('Microsoft.KeyVault/vaults', keyVaultUri.split('/')[8])
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: appIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource appIdentityAcrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(appIdentity.id, 'acr-pull')
  scope: resourceId('Microsoft.ContainerRegistry/registries', acrLoginServer.split('.')[0])
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    principalId: appIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role assignments for GitHub Identity
resource githubIdentityContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(githubIdentity.id, 'contributor-rg')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor
    principalId: githubIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource githubIdentityAcrPushRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(githubIdentity.id, 'acr-push')
  scope: resourceId('Microsoft.ContainerRegistry/registries', acrLoginServer.split('.')[0])
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8311e382-0749-4cb8-b61a-304f252e45ec') // AcrPush
    principalId: githubIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource githubIdentityKeyVaultOfficerRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(githubIdentity.id, 'keyvault-officer')
  scope: resourceId('Microsoft.KeyVault/vaults', keyVaultUri.split('/')[8])
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '00482a5a-887f-4fb3-b363-3b7fe8e74483') // Key Vault Secrets Officer
    principalId: githubIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Container App
resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: containerAppName
  location: location
  tags: tags
  properties: {
    managedEnvironmentId: containerAppsEnv.id
    configuration: {
      ingress: {
        external: enablePublicAccess
        targetPort: 5000
        transport: 'http'
        allowInsecure: false
        trafficWeight: 100
        stickySessions: {
          affinity: 'none'
        }
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
          identity: acrIdentity
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
            cpu: environment == 'prod' ? 1.0 : 0.5
            memory: environment == 'prod' ? '2Gi' : '1Gi'
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
        minReplicas: environment == 'prod' ? 2 : 1
        maxReplicas: environment == 'prod' ? 10 : 3
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
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${appIdentity.id}': {}
    }
  }
}

// Outputs
output containerAppFqdn string = containerApp.properties.configuration.ingress.fqdn
output appIdentityClientId string = appIdentity.properties.clientId
output appIdentityPrincipalId string = appIdentity.properties.principalId
output githubIdentityClientId string = githubIdentity.properties.clientId
output githubIdentityPrincipalId string = githubIdentity.properties.principalId
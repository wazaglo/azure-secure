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

@description('Key Vault URI')
@secure()
param keyVaultUri string

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

// Cross-RG references are passed in as resource IDs (KV/ACR live in the
// network resource group). RBAC role assignments are scoped to those IDs.

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
// RBAC role assignments are defined in main.bicep (they are scoped to the
// Key Vault / ACR that live in the network resource group).
// ---------------------------------------------------------------------------

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
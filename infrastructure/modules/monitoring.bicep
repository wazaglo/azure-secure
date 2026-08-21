/*
================================================================================
SecureCloud Platform - Monitoring Module
================================================================================
Creates Log Analytics Workspace, Application Insights, and Action Groups
================================================================================
*/

@description('Environment name')
param environment string

@description('Azure region')
param location string

@description('Resource tags')
param tags object

@description('Log Analytics Workspace name')
param workspaceName string

@description('Application Insights name')
param appInsightsName string

// Log Analytics Workspace
resource workspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: environment == 'prod' ? 90 : 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Flow_Type: 'Redfield'
    Request_Source: 'rest'
    WorkspaceResourceId: workspace.id
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Action Group for alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-securecloud-${environment}'
  location: 'Global'
  tags: tags
  properties: {
    groupShortName: 'SC${environment}'
    enabled: true
    emailReceivers: [
      {
        name: 'DevOps Team'
        emailAddress: 'devops@securecloud.example.com'
        useCommonAlertSchema: true
      }
    ]
    smsReceivers: []
    webhookReceivers: [
      {
        name: 'Slack Webhook'
        serviceUri: 'https://hooks.slack.com/services/xxx/xxx/xxx'
        useCommonAlertSchema: true
      }
    ]
  }
}

// Diagnostic settings for Key Vault (will be applied via separate deployment)
// Diagnostic settings for ACR (will be applied via separate deployment)

// Outputs
output workspaceId string = workspace.id
output workspaceName string = workspace.name
output appInsightsId string = appInsights.id
output appInsightsConnectionString string = appInsights.properties.ConnectionString
output actionGroupId string = actionGroup.id
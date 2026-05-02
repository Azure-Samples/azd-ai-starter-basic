targetScope = 'resourceGroup'

@description('Tags for all resources')
param tags object = {}

@description('Location for resources')
param location string

@description('Name of the AI Foundry project')
param aiFoundryProjectName string

@description('Optional name for the AI Account. If empty, auto-generated.')
param aiAccountName string = ''

@description('Model deployments to create')
param deployments array = []

@description('Connections to create from azure.yaml')
param connections array = []

@secure()
@description('Credentials map for connections: { "conn-name": { "key": "..." } }')
param connectionCredentials object = {}

@description('Developer principal ID for RBAC')
param principalId string

@description('Developer principal type')
param principalType string

@description('Use an existing Foundry project instead of creating one')
param useExistingAiProject bool = false

@description('Existing App Insights connection string (for existing projects)')
param existingAppInsightsConnectionString string = ''

@description('Existing App Insights resource ID (for existing projects)')
param existingAppInsightsResourceId string = ''

var resourceToken = uniqueString(subscription().id, resourceGroup().id, location)
var resolvedAccountName = !empty(aiAccountName) ? aiAccountName : 'ai-account-${resourceToken}'

// ═══════════════════════════════════════════════════════
// New project resources
// ═══════════════════════════════════════════════════════

resource aiAccount 'Microsoft.CognitiveServices/accounts@2025-06-01' = if (!useExistingAiProject) {
  name: resolvedAccountName
  location: location
  tags: tags
  sku: { name: 'S0' }
  kind: 'AIServices'
  identity: { type: 'SystemAssigned' }
  properties: {
    allowProjectManagement: true
    customSubDomainName: resolvedAccountName
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: true
  }

  @batchSize(1)
  resource modelDeployments 'deployments' = [for dep in deployments: {
    name: dep.name
    properties: { model: dep.model }
    sku: dep.sku
  }]

  resource project 'projects' = {
    name: aiFoundryProjectName
    location: location
    identity: { type: 'SystemAssigned' }
    properties: {
      description: '${aiFoundryProjectName} Project'
      displayName: '${aiFoundryProjectName}Project'
    }
    dependsOn: [modelDeployments]
  }

  resource capabilityHost 'capabilityHosts@2025-10-01-preview' = {
    name: 'agents'
    properties: {
      capabilityHostKind: 'Agents'
      enablePublicHostingEnvironment: true
    }
  }
}

// Monitoring (new project only)
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2021-12-01-preview' = if (!useExistingAiProject) {
  name: 'logs-${resourceToken}'
  location: location
  tags: tags
  properties: {
    retentionInDays: 30
    features: { searchVersion: 1 }
    sku: { name: 'PerGB2018' }
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = if (!useExistingAiProject) {
  name: 'appi-${resourceToken}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

resource appInsightsConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = if (!useExistingAiProject) {
  parent: aiAccount::project
  name: 'appi-${resourceToken}'
  properties: {
    category: 'AppInsights'
    target: appInsights.id
    authType: 'ApiKey'
    isSharedToAll: true
    #disable-next-line BCP318
    credentials: { key: appInsights.properties.ConnectionString }
    metadata: {
      ApiType: 'Azure'
      #disable-next-line BCP318
      ResourceId: appInsights.id
    }
  }
}

// Log Analytics Reader for project managed identity (enables trace evaluations)
resource logAnalyticsReaderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!useExistingAiProject) {
  scope: appInsights
  name: guid(appInsights.id, aiAccount::project.name, '73c42c96-874c-492b-b04d-ab87d138a893')
  properties: {
    #disable-next-line BCP318
    principalId: aiAccount::project.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '73c42c96-874c-492b-b04d-ab87d138a893')
  }
}

// ═══════════════════════════════════════════════════════
// Existing project reference
// ═══════════════════════════════════════════════════════

resource existingAiAccount 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = if (useExistingAiProject) {
  name: resolvedAccountName

  resource project 'projects' existing = {
    name: aiFoundryProjectName
  }
}

// ═══════════════════════════════════════════════════════
// RBAC — Azure AI User for the developer on the project
// ═══════════════════════════════════════════════════════

var aiUserRoleId = '53ca6127-db72-4b80-b1b0-d745d6d5456d'

resource newProjectRbac 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!useExistingAiProject) {
  scope: aiAccount::project
  name: guid(subscription().id, resourceGroup().id, principalId, aiUserRoleId)
  properties: {
    principalId: principalId
    principalType: principalType
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', aiUserRoleId)
  }
}

resource existingProjectRbac 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (useExistingAiProject) {
  scope: existingAiAccount::project
  name: guid(subscription().id, resourceGroup().id, principalId, aiUserRoleId)
  properties: {
    principalId: principalId
    principalType: principalType
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', aiUserRoleId)
  }
}

// ═══════════════════════════════════════════════════════
// Connections from azure.yaml (works for both new and existing)
// ═══════════════════════════════════════════════════════

module aiConnections './connection.bicep' = [for (conn, i) in connections: {
  name: 'connection-${conn.name}'
  params: {
    aiAccountName: resolvedAccountName
    aiProjectName: aiFoundryProjectName
    connectionConfig: conn
    credentials: connectionCredentials[?conn.name] ?? {}
  }
}]

// ═══════════════════════════════════════════════════════
// Outputs
// ═══════════════════════════════════════════════════════

output accountName string = resolvedAccountName
output projectName string = aiFoundryProjectName
#disable-next-line BCP318
output accountId string = useExistingAiProject ? existingAiAccount.id : aiAccount.id
#disable-next-line BCP318
output projectId string = useExistingAiProject ? existingAiAccount::project.id : aiAccount::project.id
#disable-next-line BCP318
output projectPrincipalId string = useExistingAiProject ? existingAiAccount::project.identity.principalId : aiAccount::project.identity.principalId
#disable-next-line BCP318
output projectEndpoint string = useExistingAiProject ? existingAiAccount::project.properties.endpoints['AI Foundry API'] : aiAccount::project.properties.endpoints['AI Foundry API']
#disable-next-line BCP318
output openAiEndpoint string = useExistingAiProject ? existingAiAccount.properties.endpoints['OpenAI Language Model Instance API'] : aiAccount.properties.endpoints['OpenAI Language Model Instance API']
#disable-next-line BCP318
output appInsightsConnectionString string = useExistingAiProject ? existingAppInsightsConnectionString : appInsights.properties.ConnectionString
#disable-next-line BCP318
output appInsightsResourceId string = useExistingAiProject ? existingAppInsightsResourceId : appInsights.id
output connectionIds array = [for (conn, i) in connections: {
  name: aiConnections[i].outputs.connectionName
  id: aiConnections[i].outputs.connectionId
}]

targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment that can be used as part of naming resource convention')
param environmentName string

@minLength(1)
@maxLength(90)
@description('Name of the resource group to use or create')
param resourceGroupName string = 'rg-${environmentName}'

@minLength(1)
@description('Primary location for all resources')
param location string

@description('Id of the user or app to assign application roles')
param principalId string

@description('Principal type of user or app')
param principalType string

@description('Optional. Name of the AI Account. If not provided, a new one will be created with an auto-generated name.')
param aiFoundryResourceName string = ''

@description('Name of the AI Foundry project')
param aiFoundryProjectName string = 'ai-project-${environmentName}'

@description('When true, reference an existing Foundry project instead of creating one')
param useExistingAiProject bool = false

// Extension-injected from azure.yaml service config
@description('Model deployments (JSON array from azure.yaml)')
param aiProjectDeploymentsJson string = '[]'

@description('Connections (JSON array from azure.yaml)')
param aiProjectConnectionsJson string = '[]'

@secure()
@description('Connection credentials (JSON map from azure.yaml)')
#disable-next-line secure-parameter-default
param aiProjectConnectionCredentialsJson string = '{}'

// Existing resource detection (set by extension when reusing resources)
@description('Existing ACR connection name on the Foundry project. If set, ACR creation is skipped.')
param existingAcrConnectionName string = ''

@description('Existing ACR login server endpoint. Used as output when ACR creation is skipped.')
param existingContainerRegistryEndpoint string = ''

@description('Existing App Insights connection string (for existing projects)')
param existingApplicationInsightsConnectionString string = ''

@description('Existing App Insights resource ID (for existing projects)')
param existingApplicationInsightsResourceId string = ''

var tags = { 'azd-env-name': environmentName }
var createAcr = empty(existingAcrConnectionName)

resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// ── AI Foundry Project (account + project + monitoring + RBAC) ──

module aiProject './modules/ai-project.bicep' = {
  scope: rg
  name: 'ai-project'
  params: {
    location: location
    tags: tags
    aiFoundryProjectName: aiFoundryProjectName
    aiAccountName: aiFoundryResourceName
    deployments: json(aiProjectDeploymentsJson)
    connections: json(aiProjectConnectionsJson)
    connectionCredentials: json(aiProjectConnectionCredentialsJson)
    principalId: principalId
    principalType: principalType
    useExistingAiProject: useExistingAiProject
    existingAppInsightsConnectionString: existingApplicationInsightsConnectionString
    existingAppInsightsResourceId: existingApplicationInsightsResourceId
  }
}

// ── Container Registry (for hosted agent image builds) ──

module acr './modules/acr.bicep' = if (createAcr) {
  scope: rg
  name: 'acr'
  params: {
    location: location
    tags: tags
    aiAccountName: aiProject.outputs.accountName
    aiProjectName: aiProject.outputs.projectName
    projectPrincipalId: aiProject.outputs.projectPrincipalId
    principalId: principalId
    principalType: principalType
  }
}

// ═══════════════════════════════════════════════════════
// Outputs
// ═══════════════════════════════════════════════════════

// Resources
output AZURE_RESOURCE_GROUP string = resourceGroupName
output AZURE_AI_ACCOUNT_ID string = aiProject.outputs.accountId
output AZURE_AI_PROJECT_ID string = aiProject.outputs.projectId
output AZURE_AI_FOUNDRY_PROJECT_ID string = aiProject.outputs.projectId
output AZURE_AI_ACCOUNT_NAME string = aiProject.outputs.accountName
output AZURE_AI_PROJECT_NAME string = aiProject.outputs.projectName

// Endpoints
output AZURE_AI_PROJECT_ENDPOINT string = aiProject.outputs.projectEndpoint
output AZURE_OPENAI_ENDPOINT string = aiProject.outputs.openAiEndpoint

// Monitoring
output APPLICATIONINSIGHTS_CONNECTION_STRING string = aiProject.outputs.appInsightsConnectionString
output APPLICATIONINSIGHTS_RESOURCE_ID string = aiProject.outputs.appInsightsResourceId

// Container Registry
#disable-next-line BCP318
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = createAcr ? acr.outputs.loginServer : existingContainerRegistryEndpoint
#disable-next-line BCP318
output AZURE_AI_PROJECT_ACR_CONNECTION_NAME string = createAcr ? acr.outputs.connectionName : existingAcrConnectionName

// Connections
output AI_PROJECT_CONNECTION_IDS_JSON string = string(aiProject.outputs.connectionIds)

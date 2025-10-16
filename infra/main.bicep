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

@metadata({azd: {
  type: 'location'
  usageName: [
    'OpenAI.GlobalStandard.gpt-4o-mini,10'
  ]}
})
param aiDeploymentsLocation string

@description('Id of the user or app to assign application roles')
param principalId string

@description('Principal type of user or app')
param principalType string

@description('Optional. Name of an existing AI Services account within the resource group. If not provided, a new one will be created.')
param aiFoundryResourceName string = ''

@description('Enable Bing Search grounding capability')
param enableBingGrounding bool = false

@description('Enable Custom Bing Search grounding capability')
param enableCustomBingGrounding bool = false

@description('List of model deployments')
param deployments array = []

@description('List of connections')
param connections array = []

@description('AI Foundry configuration for dependent resources')
param dependentResources array = []

// Determine which resources to create based on connections
var hasStorageConnection = length(filter(dependentResources, conn => conn.resource == 'AzureStorage')) > 0
var hasAcrConnection = length(filter(dependentResources, conn => conn.resource == 'AzureContainerRegistry')) > 0
var hasSearchConnection = length(filter(dependentResources, conn => conn.resource == 'AzureAISearch')) > 0
var hasBingConnection = length(filter(dependentResources, conn => conn.resource == 'BingSearch')) > 0
var hasBingCustomConnection = length(filter(dependentResources, conn => conn.resource == 'BingCustomSearch')) > 0

// Extract connection names from ai.yaml for each resource type
var storageConnectionName = hasStorageConnection ? filter(dependentResources, conn => conn.resource == 'AzureStorage')[0].connection_name : ''
var acrConnectionName = hasAcrConnection ? filter(dependentResources, conn => conn.resource == 'AzureContainerRegistry')[0].connection_name : ''
var searchConnectionName = hasSearchConnection ? filter(dependentResources, conn => conn.resource == 'AzureAISearch')[0].connection_name : ''
var bingConnectionName = hasBingConnection ? filter(dependentResources, conn => conn.resource == 'BingSearch')[0].connection_name : ''
var bingCustomConnectionName = hasBingCustomConnection ? filter(dependentResources, conn => conn.resource == 'BingCustomSearch')[0].connection_name : ''

// Tags that should be applied to all resources.
// 
// Note that 'azd-service-name' tags should be applied separately to service host resources.
// Example usage:
//   tags: union(tags, { 'azd-service-name': <service name in azure.yaml> })
var tags = {
  'azd-env-name': environmentName
}

// Check if resource group exists and create it if it doesn't
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = uniqueString(subscription().id, rg.id, location)

// AI Project module
module aiProject 'ai-project.bicep' = {
  scope: rg
  name: 'ai-project'
  params: {
    tags: tags
    location: aiDeploymentsLocation
    envName: environmentName
    principalId: principalId
    principalType: principalType
    existingAiAccountName: aiFoundryResourceName
    deployments: deployments
  }
}

// Create connections from ai.yaml configuration
module aiConnections 'foundry/connection.bicep' = [for (connection, index) in connections: {
  scope: rg
  name: 'connection-${connection.name}'
  params: {
    aiServicesAccountName: aiProject.outputs.aiServicesAccountName
    aiProjectName: aiProject.outputs.aiServicesProjectName
    connectionConfig: {
      name: connection.name
      category: connection.category
      target: connection.target
      authType: connection.authType
    }
    apiKey: '' // API keys should be provided via secure parameters or Key Vault
  }
}]

// Storage module - deploy if storage connection is defined in ai.yaml
module storage './resources/storage.bicep' = if (hasStorageConnection) {
  scope: rg
  name: 'storage'
  params: {
    location: location
    tags: tags
    storageAccountName: 'st${resourceToken}'
    connectionName: storageConnectionName
    principalId: principalId
    principalType: principalType
    aiServicesAccountName: aiProject.outputs.aiServicesAccountName
    aiProjectName: aiProject.outputs.aiServicesProjectName
  }
}

// Azure Container Registry module - deploy if ACR connection is defined in ai.yaml
module acr './resources/acr.bicep' = if (hasAcrConnection) {
  scope: rg
  name: 'acr'
  params: {
    location: location
    tags: tags
    resourceName: '${abbrs.containerRegistryRegistries}${resourceToken}'
    connectionName: acrConnectionName
    principalId: principalId
    principalType: principalType
    aiServicesAccountName: aiProject.outputs.aiServicesAccountName
    aiProjectName: aiProject.outputs.aiServicesProjectName
  }
}

// Bing Search grounding module - deploy if Bing connection is defined in ai.yaml or parameter is enabled
module bingGrounding './resources/bing_grounding.bicep' = if (hasBingConnection || enableBingGrounding) {
  scope: rg
  name: 'bing-grounding'
  params: {
    tags: tags
    resourceName: 'bing-${resourceToken}'
    connectionName: bingConnectionName
    aiAccountPrincipalId: aiProject.outputs.aiServicesPrincipalId
    aiAccountName: aiProject.name
    aiServicesAccountName: aiProject.outputs.aiServicesAccountName
    aiProjectName: aiProject.outputs.aiServicesProjectName
  }
}

// Bing Custom Search grounding module - deploy if custom Bing connection is defined in ai.yaml or parameter is enabled
module bingCustomGrounding './resources/bing_custom_grounding.bicep' = if (hasBingCustomConnection || enableCustomBingGrounding) {
  scope: rg
  name: 'bing-custom-grounding'
  params: {
    tags: tags
    resourceName: 'bingcustom-${resourceToken}'
    connectionName: bingCustomConnectionName
    aiAccountPrincipalId: aiProject.outputs.aiServicesPrincipalId
    aiAccountName: aiProject.name
    aiServicesAccountName: aiProject.outputs.aiServicesAccountName
    aiProjectName: aiProject.outputs.aiServicesProjectName
  }
}

// Azure AI Search module - deploy if search connection is defined in ai.yaml
module azureAiSearch './resources/azure_ai_search.bicep' = if (hasSearchConnection) {
  scope: rg
  name: 'azure-ai-search'
  params: {
    tags: tags
    azureSearchResourceName: 'search-${resourceToken}'
    connectionName: searchConnectionName
    aiAccountPrincipalId: aiProject.outputs.aiServicesPrincipalId
    storageAccountResourceId: hasStorageConnection ? storage!.outputs.storageAccountId : ''
    containerName: 'knowledge'
    aiServicesAccountName: aiProject.outputs.aiServicesAccountName
    aiProjectName: aiProject.outputs.aiServicesProjectName
    principalId: principalId
    principalType: principalType
    location: location
  }
}

// All connections are now created directly within their respective resource modules
// using the centralized foundry/connection.bicep module

output AZURE_RESOURCE_GROUP string = resourceGroupName
output AZURE_AI_PROJECT_ENDPOINT string = aiProject.outputs.ENDPOINT
output AZURE_AI_MODEL_DEPLOYMENT_NAME string = 'gpt-4o-mini'
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = hasAcrConnection ? acr!.outputs.containerRegistryLoginServer : ''
output AZURE_AI_PROJECT_ACR_CONNECTION_NAME string = hasAcrConnection ? acr!.outputs.containerRegistryConnectionName : ''
output AZURE_AI_FOUNDRY_RESOURCE_NAME string = aiProject.outputs.aiServicesAccountName
output AZURE_RESOURCE_AI_PROJECT_ID string = aiProject.outputs.projectId
output AZURE_BING_SEARCH_NAME string = (hasBingConnection || enableBingGrounding) ? bingGrounding!.outputs.bingSearchName : ''
output AZURE_BING_SEARCH_CONNECTION_NAME string = (hasBingConnection || enableBingGrounding) ? bingGrounding!.outputs.bingSearchConnectionName : ''
output AZURE_BING_CUSTOM_SEARCH_NAME string = (hasBingCustomConnection || enableCustomBingGrounding) ? bingCustomGrounding!.outputs.bingCustomSearchName : ''
output AZURE_BING_CUSTOM_SEARCH_CONNECTION_NAME string = (hasBingCustomConnection || enableCustomBingGrounding) ? bingCustomGrounding!.outputs.bingCustomSearchConnectionName : ''
output AZURE_SEARCH_SERVICE_NAME string = hasSearchConnection ? azureAiSearch!.outputs.searchServiceName : ''
output AZURE_SEARCH_CONNECTION_NAME string = hasSearchConnection ? azureAiSearch!.outputs.searchConnectionName : ''
output AZURE_STORAGE_ACCOUNT_NAME string = hasStorageConnection ? storage!.outputs.storageAccountName : ''
output AZURE_STORAGE_CONNECTION_NAME string = hasStorageConnection ? storage!.outputs.storageConnectionName : ''

// naming convention required in Agent Framework
output BING_CONNECTION_ID string = (hasBingConnection || enableBingGrounding) ? bingGrounding!.outputs.bingSearchConnectionId : ''

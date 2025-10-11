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

@description('Enable Azure AI Search')
param enableAzureAiSearch bool = false

@description('Enable Container Agents capability - creates ACR and related permissions')
param enableHostedAgents bool = false

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

// Resolve secondary provisioning flags from primary provisioning flags
// Create a storage account for the AI Services account if Azure AI Search is enabled
var enableStorageAccount = (enableAzureAiSearch)
// Create an ACR for container agents if hosted agents are enabled
var enableAcr = (enableHostedAgents)

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
    deployments: [
      {
        name: 'gpt-4o-mini'
        model: {
          name: 'gpt-4o-mini'
          format: 'OpenAI'
          version: '2024-07-18'
        }
        sku: {
          name: 'GlobalStandard'
          capacity: 100
        }
      }
    ]
  }
}

// Storage module - only deploy if storage is enabled
module storage './resources/storage.bicep' = if (enableStorageAccount) {
  scope: rg
  name: 'storage'
  params: {
    location: location
    tags: tags
    storageAccountName: 'st${resourceToken}'
    principalId: principalId
    principalType: principalType
    aiServicesAccountName: aiProject.outputs.aiServicesAccountName
    aiProjectName: aiProject.outputs.aiServicesProjectName
  }
}

// Azure Container Registry module - only deploy if hosted agents are enabled
module acr './resources/acr.bicep' = if (enableAcr) {
  scope: rg
  name: 'acr'
  params: {
    location: location
    tags: tags
    resourceName: '${abbrs.containerRegistryRegistries}${resourceToken}'
    principalId: principalId
    principalType: principalType
    aiServicesAccountName: aiProject.outputs.aiServicesAccountName
    aiProjectName: aiProject.outputs.aiServicesProjectName
  }
}

// Bing Search grounding module
module bingGrounding './resources/bing_grounding.bicep' = if (enableBingGrounding) {
  scope: rg
  name: 'bing-grounding'
  params: {
    tags: tags
    resourceName: 'bing-${resourceToken}'
    aiAccountPrincipalId: aiProject.outputs.aiServicesPrincipalId
    aiAccountName: aiProject.name
    aiServicesAccountName: aiProject.outputs.aiServicesAccountName
    aiProjectName: aiProject.outputs.aiServicesProjectName
  }
}

// Bing Custom Search grounding module
module bingCustomGrounding './resources/bing_custom_grounding.bicep' = if (enableCustomBingGrounding) {
  scope: rg
  name: 'bing-custom-grounding'
  params: {
    tags: tags
    resourceName: 'bingcustom-${resourceToken}'
    aiAccountPrincipalId: aiProject.outputs.aiServicesPrincipalId
    aiAccountName: aiProject.name
    aiServicesAccountName: aiProject.outputs.aiServicesAccountName
    aiProjectName: aiProject.outputs.aiServicesProjectName
  }
}

// Azure AI Search module
module azureAiSearch './resources/azure_ai_search.bicep' = if (enableAzureAiSearch) {
  scope: rg
  name: 'azure-ai-search'
  params: {
    tags: tags
    azureSearchResourceName: 'search-${resourceToken}'
    aiAccountPrincipalId: aiProject.outputs.aiServicesPrincipalId
    storageAccountResourceId: enableStorageAccount ? storage!.outputs.storageAccountId : ''
    containerName: 'knowledge'
    aiServicesAccountName: aiProject.outputs.aiServicesAccountName
    aiProjectName: aiProject.outputs.aiServicesProjectName
    principalId: principalId
    principalType: principalType
    location: location
  }
}

output AZURE_RESOURCE_GROUP string = resourceGroupName
output AZURE_AI_PROJECT_ENDPOINT string = aiProject.outputs.ENDPOINT
output AZURE_AI_MODEL_DEPLOYMENT_NAME string = 'gpt-4o-mini'
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = enableHostedAgents ? acr!.outputs.containerRegistryLoginServer : ''
output AZURE_AI_PROJECT_ACR_CONNECTION_NAME string = enableHostedAgents ? acr!.outputs.containerRegistryConnectionName : ''
output AZURE_AI_FOUNDRY_RESOURCE_NAME string = aiProject.outputs.aiServicesAccountName
output AZURE_RESOURCE_AI_PROJECT_ID string = aiProject.outputs.projectId
output AZURE_BING_SEARCH_NAME string = enableBingGrounding ? bingGrounding!.outputs.bingSearchName : ''
output AZURE_BING_SEARCH_CONNECTION_NAME string = enableBingGrounding ? bingGrounding!.outputs.bingSearchConnectionName : ''
output AZURE_BING_CUSTOM_SEARCH_NAME string = enableCustomBingGrounding ? bingCustomGrounding!.outputs.bingCustomSearchName : ''
output AZURE_BING_CUSTOM_SEARCH_CONNECTION_NAME string = enableCustomBingGrounding ? bingCustomGrounding!.outputs.bingCustomSearchConnectionName : ''
output AZURE_SEARCH_SERVICE_NAME string = enableAzureAiSearch ? azureAiSearch!.outputs.searchServiceName : ''
output AZURE_SEARCH_CONNECTION_NAME string = enableAzureAiSearch ? azureAiSearch!.outputs.searchConnectionName : ''
output AZURE_STORAGE_ACCOUNT_NAME string = enableStorageAccount ? storage!.outputs.storageAccountName : ''
output AZURE_STORAGE_CONNECTION_NAME string = enableStorageAccount ? storage!.outputs.storageConnectionName : ''

// naming convention required in Agent Framework
output BING_CONNECTION_ID string = enableBingGrounding ? bingGrounding!.outputs.bingSearchConnectionId : ''

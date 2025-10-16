targetScope = 'subscription'
// targetScope = 'resourceGroup'

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

@description('List of resources to create and connect to the AI project')
param resources array = []

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

// AI Project module
module aiProject 'core/ai/ai-project.bicep' = {
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
    connections: connections
    additionalDependentResources: resources
    enableBingGrounding: enableBingGrounding
    enableCustomBingGrounding: enableCustomBingGrounding
  }
}



output AZURE_RESOURCE_GROUP string = resourceGroupName
output AZURE_AI_PROJECT_ENDPOINT string = aiProject.outputs.ENDPOINT
output AZURE_AI_MODEL_DEPLOYMENT_NAME string = 'gpt-4o-mini'
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = aiProject.outputs.dependentResources.containerRegistry.loginServer
output AZURE_AI_PROJECT_ACR_CONNECTION_NAME string = aiProject.outputs.dependentResources.containerRegistry.connectionName
output AZURE_AI_FOUNDRY_RESOURCE_NAME string = aiProject.outputs.aiServicesAccountName
output AZURE_AI_FOUNDRY_PROJECT_ID string = aiProject.outputs.projectId
output BING_SEARCH_NAME string = aiProject.outputs.dependentResources.bingSearch.name
output BING_SEARCH_CONNECTION_NAME string = aiProject.outputs.dependentResources.bingSearch.connectionName
output BING_CUSTOM_SEARCH_NAME string = aiProject.outputs.dependentResources.bingCustomSearch.name
output BING_CUSTOM_SEARCH_CONNECTION_NAME string = aiProject.outputs.dependentResources.bingCustomSearch.connectionName
output AZURE_AI_SEARCH_SERVICE_NAME string = aiProject.outputs.dependentResources.search.serviceName
output AZURE_AI_SEARCH_CONNECTION_NAME string = aiProject.outputs.dependentResources.search.connectionName
output AZURE_STORAGE_ACCOUNT_NAME string = aiProject.outputs.dependentResources.storage.accountName
output AZURE_STORAGE_CONNECTION_NAME string = aiProject.outputs.dependentResources.storage.connectionName

// naming convention required in Agent Framework
output BING_CONNECTION_ID string = aiProject.outputs.dependentResources.bingSearch.connectionId

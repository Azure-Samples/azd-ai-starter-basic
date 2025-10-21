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

@description('List of model deployments')
param aiProjectDeploymentsJson string = '[]'

@description('List of connections')
param aiProjectConnectionsJson string = '[]'

@description('List of resources to create and connect to the AI project')
param aiProjectDependentResourcesJson string = '[]'

var aiProjectDeployments array = json(aiProjectDeploymentsJson)
var aiProjectConnections array = json(aiProjectConnectionsJson)
var aiProjectDependentResources array = json(aiProjectDependentResourcesJson)

@description('Enable COBO agent deployment')
param enableCoboAgent bool = true

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
    deployments: aiProjectDeployments
    connections: aiProjectConnections
    additionalDependentResources: aiProjectDependentResources
  }
}

var resourceToken = toLower(uniqueString(subscription().id, rg.id, location))
var prefix = 'ca-${environmentName}-${resourceToken}'

// Container Apps Environment for COBO agent
module containerAppsEnvironment 'core/host/container-apps-environment.bicep' = if (enableCoboAgent) {
  scope: rg
  name: 'container-apps-environment'
  params: {
    name: '${prefix}-env'
    location: location
    tags: tags
  }
}

// COBO Agent module
module coboAgent 'core/ai/cobo-agent.bicep' = if (enableCoboAgent) {
  scope: rg
  name: 'cobo-agent'
  params: {
    name: replace(take(prefix, 32), '--', '-')
    location: location
    tags: tags
    identityName: '${prefix}-id'
    containerAppsEnvironmentName: containerAppsEnvironment!.outputs.name
    containerRegistryName: aiProject.outputs.dependentResources.containerRegistry.name
    openaiEndpoint: aiProject.outputs.aiServicesEndpoint
    openaiApiVersion: '2025-03-01-preview'
    aiServicesAccountName: aiProject.outputs.aiServicesAccountName
    aiProjectName: environmentName
  }
}


output AZURE_RESOURCE_GROUP string = resourceGroupName
output AZURE_AI_PROJECT_ENDPOINT string = aiProject.outputs.ENDPOINT
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

// COBO Agent outputs
output AZURE_CONTAINER_ENVIRONMENT_NAME string = enableCoboAgent ? containerAppsEnvironment!.outputs.name : ''
output AZURE_CONTAINER_REGISTRY_NAME string = aiProject.outputs.dependentResources.containerRegistry.name
output COBO_ACA_IDENTITY_PRINCIPAL_ID string = enableCoboAgent ? coboAgent!.outputs.COBO_ACA_IDENTITY_PRINCIPAL_ID : ''
output SERVICE_API_NAME string = enableCoboAgent ? coboAgent!.outputs.SERVICE_API_NAME : ''
output SERVICE_API_URI string = enableCoboAgent ? coboAgent!.outputs.SERVICE_API_URI : ''
output SERVICE_API_IMAGE_NAME string = enableCoboAgent ? coboAgent!.outputs.SERVICE_API_IMAGE_NAME : ''
output SERVICE_API_RESOURCE_ID string = enableCoboAgent ? coboAgent!.outputs.SERVICE_API_RESOURCE_ID : ''
output AI_FOUNDRY_PROJECT_PRINCIPAL_ID string = enableCoboAgent ? coboAgent!.outputs.AI_FOUNDRY_PROJECT_PRINCIPAL_ID : ''
output AI_FOUNDRY_PROJECT_TENANT_ID string = enableCoboAgent ? coboAgent!.outputs.AI_FOUNDRY_PROJECT_TENANT_ID : ''
output AI_FOUNDRY_RESOURCE_ID string = '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroupName}/providers/Microsoft.CognitiveServices/accounts/${aiProject.outputs.aiServicesAccountName}'
output AI_FOUNDRY_PROJECT_RESOURCE_ID string = aiProject.outputs.projectId

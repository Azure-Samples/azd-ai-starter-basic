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

@description('Enable Container Agents capability - creates ACR and related permissions')
param enableHostedAgents bool = false

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

module resources 'resources.bicep' = {
  scope: rg
  name: 'resources'
  params: {
    location: location
    tags: tags
    principalId: principalId
    principalType: principalType
    aiServicesAccountName: aiProject.outputs.aiServicesAccountName
    aiProjectName: aiProject.outputs.aiServicesProjectName
    enableHostedAgents: enableHostedAgents
    enableCoboAgent: enableCoboAgent
    openaiEndpoint: aiProject.outputs.ENDPOINT
    openaiDeploymentName: 'gpt-4o-mini'
  }
}

// Bing Search grounding module
module bingGrounding './tools/bing_grounding.bicep' = if (enableBingGrounding) {
  scope: rg
  name: 'bing-grounding'
  params: {
    tags: tags
    resourceName: 'bing-${resources.outputs.resourcetoken}'
    aiAccountPrincipalId: aiProject.outputs.aiServicesPrincipalId
    aiAccountName: aiProject.name
    aiServicesAccountName: aiProject.outputs.aiServicesAccountName
    aiProjectName: aiProject.outputs.aiServicesProjectName
  }
}

output AZURE_AI_PROJECT_ENDPOINT string = aiProject.outputs.ENDPOINT
output AZURE_AI_MODEL_DEPLOYMENT_NAME string = 'gpt-4o-mini'
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = enableHostedAgents ? resources.outputs.containerRegistryLoginServer : ''
output AZURE_AI_PROJECT_ACR_CONNECTION_NAME string = enableHostedAgents ? resources.outputs.containerRegistryConnectionName : ''
output AZURE_AI_FOUNDRY_RESOURCE_NAME string = aiProject.outputs.aiServicesAccountName
output AZURE_RESOURCE_AI_PROJECT_ID string = aiProject.outputs.projectId
output AZURE_RESOURCE_GROUP string = resourceGroupName
output AZURE_BING_SEARCH_NAME string = enableBingGrounding ? bingGrounding!.outputs.bingSearchName : ''
output AZURE_BING_SEARCH_CONNECTION_NAME string = enableBingGrounding ? bingGrounding!.outputs.bingSearchConnectionName : ''

// naming convention required in Agent Framework
output BING_CONNECTION_ID string = enableBingGrounding ? bingGrounding!.outputs.bingSearchConnectionId : ''

// COBO Agent outputs
output AZURE_CONTAINER_ENVIRONMENT_NAME string = enableCoboAgent ? resources.outputs.containerAppsEnvironmentName : ''
output AZURE_CONTAINER_REGISTRY_NAME string = enableHostedAgents ? resources.outputs.containerRegistryName : ''
output COBO_AGENT_NAME string = enableCoboAgent ? resources.outputs.coboAgentName : ''
output COBO_AGENT_URI string = enableCoboAgent ? resources.outputs.coboAgentUri : ''
output COBO_AGENT_IDENTITY_PRINCIPAL_ID string = enableCoboAgent ? resources.outputs.coboAgentIdentityPrincipalId : ''
output AZURE_OPENAI_ENDPOINT string = aiProject.outputs.ENDPOINT
output AZURE_OPENAI_DEPLOYMENT_NAME string = 'gpt-4o-mini'

@description('The location used for all deployed resources')
param location string = resourceGroup().location

@description('Tags that will be applied to all resources')
param tags object = {}

@description('Id of the user or app to assign application roles')
param principalId string

@description('Principal type of user or app')
param principalType string

@description('AI Services account name to get managed identity')
param aiServicesAccountName string

@description('AI project name for creating the connection')
param aiProjectName string

@description('Enable Container Agents capability - creates ACR and related permissions')
param enableHostedAgents bool = false

@description('Enable COBO agent deployment')
param enableCoboAgent bool = true

@description('Azure OpenAI endpoint for COBO agent')
param openaiEndpoint string = ''

@description('Azure OpenAI deployment name')
param openaiDeploymentName string = 'gpt-4o-mini'

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = uniqueString(subscription().id, resourceGroup().id, location)

// Get reference to the AI Services account to access its managed identity
resource aiAccount 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: aiServicesAccountName

  resource project 'projects' existing = {
    name: aiProjectName
  }
}

module containerRegistry 'br/public:avm/res/container-registry/registry:0.1.1' = if (enableHostedAgents) {
  name: 'registry'
  params: {
    name: '${abbrs.containerRegistryRegistries}${resourceToken}'
    location: location
    tags: tags
    publicNetworkAccess: 'Enabled'
    roleAssignments:[
      {
        principalId: principalId
        principalType: principalType
        roleDefinitionIdOrName: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
      }
      {
        // the foundry project itself can pull from the ACR
        principalId: aiAccount.identity.principalId
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
      }
    ]
  }
}

resource acrConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = if (enableHostedAgents) {
  parent: aiAccount::project
  name: 'acr-connection'
  properties: {
    category: 'ContainerRegistry'
    target: containerRegistry!.outputs.loginServer
    authType: 'ManagedIdentity'
    credentials: {
      clientId: aiAccount.identity.principalId
      resourceId: containerRegistry!.outputs.resourceId
    }
    isSharedToAll: true
    metadata: {
      ResourceId: containerRegistry!.outputs.resourceId
    }
  }
}

// COBO Agent Identity - needs to be created before role assignment
resource coboAgentIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = if (enableCoboAgent) {
  name: '${abbrs.managedIdentityUserAssignedIdentities}cobo-agent-${resourceToken}'
  location: location
  tags: tags
}

// Grant Azure AI User role to COBO agent identity on AI Services account
// Role: 53ca6127-db72-4b80-b1b0-d745d6d5456d (Azure AI User)
resource coboAgentOpenAIRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableCoboAgent) {
  scope: aiAccount
  name: guid(aiAccount.id, coboAgentIdentity!.id, '53ca6127-db72-4b80-b1b0-d745d6d5456d')
  properties: {
    principalId: coboAgentIdentity!.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '53ca6127-db72-4b80-b1b0-d745d6d5456d')
  }
}

// Container Apps Environment for COBO agent
module containerAppsEnvironment 'core/host/container-apps-environment.bicep' = if (enableCoboAgent) {
  name: 'container-apps-environment'
  params: {
    name: '${abbrs.appManagedEnvironments}${resourceToken}'
    location: location
    tags: tags
  }
}

// COBO Agent
var prefix = resourceToken
module coboAgent 'cobo-agent.bicep' = if (enableCoboAgent) {
  name: 'cobo-agent'
  scope: resourceGroup()
  params: {
    name: replace('${take(prefix,19)}-ca', '--', '-')
    location: location
    tags: tags
    identityName: coboAgentIdentity!.name
    containerAppsEnvironmentName: containerAppsEnvironment!.outputs.name
    containerRegistryName: enableHostedAgents ? containerRegistry!.outputs.name : ''
    openaiEndpoint: openaiEndpoint
    openaiApiVersion: '2025-03-01-preview'
    openaiDeployment: openaiDeploymentName
    aiFoundryProjectPrincipalId: aiAccount::project.identity.principalId
    aiFoundryProjectTenantId: aiAccount::project.identity.tenantId
  }
  dependsOn: [
    coboAgentOpenAIRole // Ensure Azure AI User role is assigned before deploying container app
  ]
}

output containerRegistryName string = enableHostedAgents ? containerRegistry!.outputs.name : ''
output containerRegistryLoginServer string = enableHostedAgents ? containerRegistry!.outputs.loginServer : ''
output containerRegistryConnectionName string = enableHostedAgents ? acrConnection!.name : ''
output containerAppsEnvironmentName string = enableCoboAgent ? containerAppsEnvironment!.outputs.name : ''
output coboAgentName string = enableCoboAgent ? coboAgent!.outputs.COBO_AGENT_NAME : ''
output coboAgentUri string = enableCoboAgent ? coboAgent!.outputs.COBO_AGENT_URI : ''
output coboAgentIdentityPrincipalId string = enableCoboAgent ? coboAgentIdentity!.properties.principalId : ''
output resourcetoken string = resourceToken
output enableHostedAgents bool = enableHostedAgents

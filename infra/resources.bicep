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
param enableContainerAgents bool = false

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = uniqueString(subscription().id, resourceGroup().id, location)

// Get reference to the AI Services account to access its managed identity
resource aiAccount 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: aiServicesAccountName

  resource project 'projects' existing = {
    name: aiProjectName
  }
}

module containerRegistry 'br/public:avm/res/container-registry/registry:0.1.1' = if (enableContainerAgents) {
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

resource acrConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = if (enableContainerAgents) {
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

output containerRegistryName string = enableContainerAgents ? containerRegistry!.outputs.name : ''
output containerRegistryLoginServer string = enableContainerAgents ? containerRegistry!.outputs.loginServer : ''
output containerRegistryConnectionName string = enableContainerAgents ? acrConnection!.name : ''
output resourcetoken string = resourceToken
output enableContainerAgents bool = enableContainerAgents

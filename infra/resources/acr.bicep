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

@description('Resource name for the container registry')
param resourceName string

@description('Name for the AI Foundry ACR connection')
param connectionName string = 'acr-connection'

// Get reference to the AI Services account to access its managed identity
resource aiAccount 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: aiServicesAccountName
}

module containerRegistry 'br/public:avm/res/container-registry/registry:0.1.1' = {
  name: 'registry'
  params: {
    name: resourceName
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

@description('AI project name for creating the connection')
param aiProjectName string

// Create the ACR connection using the centralized connection module
module acrConnection '../foundry/connection.bicep' = {
  name: 'acr-connection-creation'
  params: {
    aiServicesAccountName: aiServicesAccountName
    aiProjectName: aiProjectName
    connectionConfig: {
      name: connectionName
      category: 'ContainerRegistry'
      target: containerRegistry.outputs.loginServer
      authType: 'ManagedIdentity'
      credentials: {
        clientId: aiAccount.identity.principalId
        resourceId: containerRegistry.outputs.resourceId
      }
      isSharedToAll: true
      metadata: {
        ResourceId: containerRegistry.outputs.resourceId
      }
    }
  }
}

output containerRegistryName string = containerRegistry.outputs.name
output containerRegistryLoginServer string = containerRegistry.outputs.loginServer
output containerRegistryResourceId string = containerRegistry.outputs.resourceId
output containerRegistryConnectionName string = acrConnection.outputs.connectionName

@description('Tags that will be applied to all resources')
param tags object = {}

@description('Bing grounding resource name')
param resourceName string

@description('AI Services account managed identity principal ID')
param aiAccountPrincipalId string

@description('AI Services account name for role assignment naming')
param aiAccountName string

@description('Name for the AI Foundry Bing search connection')
param connectionName string = 'bing-grounding-connection'

// Bing Search resource for grounding capability
resource bingSearch 'Microsoft.Bing/accounts@2020-06-10' = {
  name: resourceName
  location: 'global'
  tags: tags
  sku: {
    name: 'G1'
  }
  properties: {
    statisticsEnabled: false
  }
  kind: 'Bing.Grounding'
}

// Role assignment to allow AI project to use Bing Search
resource bingSearchRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: bingSearch
  name: guid(subscription().id, resourceGroup().id, 'bing-search-role', aiAccountName)
  properties: {
    principalId: aiAccountPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', 'a97b65f3-24c7-4388-baec-2e87135dc908') // Cognitive Services User
  }
}

@description('AI Services account name for the project parent')
param aiServicesAccountName string

@description('AI project name for creating the connection')
param aiProjectName string

// Create the Bing Search connection using the centralized connection module
module bingSearchConnection '../foundry/connection.bicep' = {
  name: 'bing-search-connection-creation'
  params: {
    aiServicesAccountName: aiServicesAccountName
    aiProjectName: aiProjectName
    connectionConfig: {
      name: connectionName
      category: 'GroundingWithBingSearch'
      target: bingSearch.properties.endpoint
      authType: 'ApiKey'
      isSharedToAll: true
      metadata: {
        Location: 'global'
        ResourceId: bingSearch.id
        ApiType: 'Azure'
        type: 'bing_grounding'
      }
    }
    apiKey: bingSearch.listKeys().key1
  }
  dependsOn: [
    bingSearchRoleAssignment
  ]
}

output bingSearchName string = bingSearch.name
output bingSearchConnectionName string = bingSearchConnection.outputs.connectionName
output bingSearchResourceId string = bingSearch.id
output bingSearchConnectionId string = bingSearchConnection.outputs.connectionId

@description('Tags that will be applied to all resources')
param tags object = {}

@description('Bing custom grounding resource name')
param resourceName string

@description('AI Services account managed identity principal ID')
param aiAccountPrincipalId string

@description('AI Services account name for role assignment naming')
param aiAccountName string

@description('Name for the AI Foundry Bing Custom Search connection')
param connectionName string = 'bing-custom-grounding-connection'

// Bing Search resource for grounding capability
resource bingCustomSearch 'Microsoft.Bing/accounts@2020-06-10' = {
  name: resourceName
  location: 'global'
  tags: tags
  sku: {
    name: 'G1'
  }
  properties: {
    statisticsEnabled: false
  }
  kind: 'Bing.CustomGrounding'
}

// Role assignment to allow AI project to use Bing Search
resource bingCustomSearchRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: bingCustomSearch
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

// Create the Bing Custom Search connection using the centralized connection module
module bingCustomSearchConnection '../foundry/connection.bicep' = {
  name: 'bing-custom-search-connection-creation'
  params: {
    aiServicesAccountName: aiServicesAccountName
    aiProjectName: aiProjectName
    connectionConfig: {
      name: connectionName
      category: 'GroundingWithCustomSearch'
      target: bingCustomSearch.properties.endpoint
      authType: 'ApiKey'
      isSharedToAll: true
      metadata: {
        Location: 'global'
        ResourceId: bingCustomSearch.id
        ApiType: 'Azure'
        type: 'bing_custom_search'
      }
    }
    apiKey: bingCustomSearch.listKeys().key1
  }
  dependsOn: [
    bingCustomSearchRoleAssignment
  ]
}

output bingCustomSearchName string = bingCustomSearch.name
output bingCustomSearchConnectionName string = bingCustomSearchConnection.outputs.connectionName
output bingCustomSearchResourceId string = bingCustomSearch.id
output bingCustomSearchConnectionId string = bingCustomSearchConnection.outputs.connectionId

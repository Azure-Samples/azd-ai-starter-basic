@description('Tags that will be applied to all resources')
param tags object = {}

@description('Bing custom grounding resource name')
param resourceName string

@description('AI Services account managed identity principal ID')
param aiAccountPrincipalId string

@description('AI Services account name for role assignment naming')
param aiAccountName string

@description('AI Services account name for the project parent')
param aiServicesAccountName string

@description('AI project name for creating the connection')
param aiProjectName string

@description('Name for the AI Foundry Bing custom search connection')
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

// Get reference to the AI Services account and project
resource aiAccount 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: aiServicesAccountName

  resource project 'projects' existing = {
    name: aiProjectName
  }
}


// Connection from AI project to Bing Custom Search
// see https://github.com/azure-ai-foundry/foundry-samples/blob/main/samples/microsoft/infrastructure-setup/01-connections/connection-bing-grounding.bicep
resource bingCustomSearchConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  parent: aiAccount::project
  name: connectionName
  properties: {
    category: 'GroundingWithCustomSearch'
    target: bingCustomSearch.properties.endpoint
    authType: 'ApiKey'
    isSharedToAll: true
    credentials: {
      key: bingCustomSearch.listKeys().key1
    }
    metadata: {
      Location: 'global'
      ResourceId: bingCustomSearch.id
      ApiType: 'Azure'
      type: 'bing_custom_search'
    }
  }
  dependsOn: [
    bingCustomSearchRoleAssignment
  ]
}

output bingCustomSearchName string = bingCustomSearch.name
output bingCustomSearchConnectionName string = bingCustomSearchConnection.name
output bingCustomSearchResourceId string = bingCustomSearch.id
output bingCustomSearchConnectionId string = bingCustomSearchConnection.id

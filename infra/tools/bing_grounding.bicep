@description('Tags that will be applied to all resources')
param tags object = {}

@description('Bing grouding resource name')
param resourceName string

@description('AI Services account managed identity principal ID')
param aiAccountPrincipalId string

@description('AI Services account name for role assignment naming')
param aiAccountName string

@description('AI Services account name for the project parent')
param aiServicesAccountName string

@description('AI project name for creating the connection')
param aiProjectName string

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

// Get reference to the AI Services account and project
resource aiAccount 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: aiServicesAccountName

  resource project 'projects' existing = {
    name: aiProjectName
  }
}


// Connection from AI project to Bing Search
// see https://github.com/azure-ai-foundry/foundry-samples/blob/main/samples/microsoft/infrastructure-setup/01-connections/connection-bing-grounding.bicep
resource bingSearchConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  parent: aiAccount::project
  name: 'bing-search-connection'
  properties: {
    category: 'ApiKey'
    target: 'https://api.bing.microsoft.com'
    authType: 'ApiKey'
    isSharedToAll: true
    credentials: {
      key: bingSearch.listKeys().key1
    }
    metadata: {
      ResourceId: bingSearch.id
      ApiType: 'Azure'
      Type: 'bing_grounding'
    }
  }
  dependsOn: [
    bingSearchRoleAssignment
  ]
}

output bingSearchName string = bingSearch.name
output bingSearchConnectionName string = bingSearchConnection.name
output bingSearchResourceId string = bingSearch.id

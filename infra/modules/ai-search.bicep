targetScope = 'resourceGroup'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Tags for all resources')
param tags object = {}

@description('AI Services account name')
param aiAccountName string

@description('AI project name')
param aiProjectName string

@description('Managed identity principal ID of the AI project')
param projectPrincipalId string

@description('Developer principal ID')
param principalId string

@description('Developer principal type')
param principalType string

@description('Connection name for the Foundry Project')
param connectionName string

@description('Storage account resource ID (for knowledge container and search indexer)')
param storageAccountId string

var resourceToken = uniqueString(subscription().id, resourceGroup().id, location)

resource searchService 'Microsoft.Search/searchServices@2024-06-01-preview' = {
  name: 'search-${resourceToken}'
  location: location
  tags: tags
  sku: { name: 'basic' }
  identity: { type: 'SystemAssigned' }
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: 'default'
    authOptions: {
      aadOrApiKey: { aadAuthFailureMode: 'http401WithBearerChallenge' }
    }
    publicNetworkAccess: 'enabled'
  }
}

// Knowledge container in the linked storage account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: last(split(storageAccountId, '/'))
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' existing = {
  parent: storageAccount
  name: 'default'
}

resource knowledgeContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'knowledge'
  properties: { publicAccess: 'None' }
}

// Search → Storage: Blob Data Reader
resource searchToStorageRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, searchService.id, '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1')
  properties: {
    principalId: searchService.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1')
  }
}

// Search → AI Services: Cognitive Services OpenAI User
resource searchToAiRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiAccountName, searchService.id, '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
  properties: {
    principalId: searchService.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
  }
}

// Project MI → Search: Search Service Contributor
resource projectToSearchContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: searchService
  name: guid(searchService.id, projectPrincipalId, '7ca78c08-252a-4471-8644-bb5ff32d4ba0')
  properties: {
    principalId: projectPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7ca78c08-252a-4471-8644-bb5ff32d4ba0')
  }
}

// Project MI → Search: Search Index Data Contributor
resource projectToSearchDataRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: searchService
  name: guid(searchService.id, projectPrincipalId, '8ebe5a00-799e-43f5-93ac-243d3dce84a7')
  properties: {
    principalId: projectPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8ebe5a00-799e-43f5-93ac-243d3dce84a7')
  }
}

// Developer → Search: Search Index Data Contributor
resource userToSearchRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: searchService
  name: guid(searchService.id, principalId, '8ebe5a00-799e-43f5-93ac-243d3dce84a7')
  properties: {
    principalId: principalId
    principalType: principalType
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8ebe5a00-799e-43f5-93ac-243d3dce84a7')
  }
}

// Connection to Foundry Project
module searchConnection './connection.bicep' = {
  name: 'search-connection'
  params: {
    aiAccountName: aiAccountName
    aiProjectName: aiProjectName
    connectionConfig: {
      name: connectionName
      category: 'CognitiveSearch'
      target: 'https://${searchService.name}.search.windows.net'
      authType: 'AAD'
      isSharedToAll: true
      metadata: {
        ApiVersion: '2024-07-01'
        ResourceId: searchService.id
        ApiType: 'Azure'
        type: 'azure_ai_search'
      }
    }
  }
  dependsOn: [projectToSearchDataRole]
}

output serviceName string = searchService.name
output connectionName string = searchConnection.outputs.connectionName

targetScope = 'resourceGroup'

@description('Location for the storage account')
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

var resourceToken = uniqueString(subscription().id, resourceGroup().id, location)

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: 'st${resourceToken}'
  location: location
  tags: tags
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  identity: { type: 'SystemAssigned' }
  properties: {
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    accessTier: 'Hot'
  }
}

// Project MI: Storage Blob Data Contributor
resource projectStorageRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, projectPrincipalId, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  properties: {
    principalId: projectPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  }
}

// Developer: Storage Blob Data Contributor
resource userStorageRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, principalId, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  properties: {
    principalId: principalId
    principalType: principalType
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  }
}

// Connection to Foundry Project
module storageConnection './connection.bicep' = {
  name: 'storage-connection'
  params: {
    aiAccountName: aiAccountName
    aiProjectName: aiProjectName
    connectionConfig: {
      name: connectionName
      category: 'AzureStorageAccount'
      target: storageAccount.properties.primaryEndpoints.blob
      authType: 'AAD'
      isSharedToAll: true
      metadata: {
        ApiType: 'Azure'
        ResourceId: storageAccount.id
        location: storageAccount.location
      }
    }
  }
}

output accountName string = storageAccount.name
output accountId string = storageAccount.id
output connectionName string = storageConnection.outputs.connectionName

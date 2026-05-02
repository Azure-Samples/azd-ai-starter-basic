targetScope = 'resourceGroup'

@description('Location for the container registry')
param location string = resourceGroup().location

@description('Tags for all resources')
param tags object = {}

@description('AI Services account name (for creating the project connection)')
param aiAccountName string

@description('AI project name (for creating the project connection)')
param aiProjectName string

@description('Managed identity principal ID of the AI project (for AcrPull role)')
param projectPrincipalId string

@description('Developer principal ID (for Container Registry Tasks Contributor role)')
param principalId string

@description('Developer principal type')
param principalType string

var resourceToken = uniqueString(subscription().id, resourceGroup().id, location)
var registryName = 'cr${resourceToken}'
var connectionName = 'acr-${resourceToken}'

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: registryName
  location: location
  tags: tags
  sku: { name: 'Basic' }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Enabled'
  }
}

// Developer: build & push images via ACR Tasks
resource developerRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: containerRegistry
  name: guid(containerRegistry.id, principalId, 'fb382eab-e894-4461-af04-94435c366c3f')
  properties: {
    principalId: principalId
    principalType: principalType
    // Container Registry Tasks Contributor
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'fb382eab-e894-4461-af04-94435c366c3f')
  }
}

// Project managed identity: pull images for hosted agents
resource projectPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: containerRegistry
  name: guid(containerRegistry.id, projectPrincipalId, '7f951dda-4ed3-4680-a7ca-43fe172d538d')
  properties: {
    principalId: projectPrincipalId
    principalType: 'ServicePrincipal'
    // AcrPull
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
  }
}

// Connection to Foundry Project
module acrConnection './connection.bicep' = {
  name: 'acr-connection'
  params: {
    aiAccountName: aiAccountName
    aiProjectName: aiProjectName
    connectionConfig: {
      name: connectionName
      category: 'ContainerRegistry'
      target: containerRegistry.properties.loginServer
      authType: 'ManagedIdentity'
      isSharedToAll: true
      metadata: { ResourceId: containerRegistry.id }
    }
    credentials: {
      clientId: projectPrincipalId
      resourceId: containerRegistry.id
    }
  }
}

output registryName string = containerRegistry.name
output loginServer string = containerRegistry.properties.loginServer
output connectionName string = acrConnection.outputs.connectionName

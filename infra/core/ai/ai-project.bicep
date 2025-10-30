targetScope = 'resourceGroup'

@description('Tags that will be applied to all resources')
param tags object = {}

@description('Main location for the resources')
param location string

var resourceToken = uniqueString(subscription().id, resourceGroup().id, location)

@description('The name of the environment')
param envName string

param deployments deploymentsType

@description('Id of the user or app to assign application roles')
param principalId string

@description('Principal type of user or app')
param principalType string

@description('Optional. Name of an existing AI Services account in the current resource group. If not provided, a new one will be created.')
param existingAiAccountName string = ''

@description('List of connections to provision')
param connections array = []

@description('Also provision dependent resources and connect to the project')
param additionalDependentResources  array = []

// Load abbreviations
var abbrs = loadJsonContent('../../abbreviations.json')

// Determine which resources to create based on connections
var hasStorageConnection = length(filter(additionalDependentResources, conn => conn.resource == 'AzureStorage')) > 0
var hasAcrConnection = length(filter(additionalDependentResources, conn => conn.resource == 'AzureContainerRegistry')) > 0
var hasSearchConnection = length(filter(additionalDependentResources, conn => conn.resource == 'AzureAISearch')) > 0
var hasBingConnection = length(filter(additionalDependentResources, conn => conn.resource == 'BingSearch')) > 0
var hasBingCustomConnection = length(filter(additionalDependentResources, conn => conn.resource == 'BingCustomSearch')) > 0

// Extract connection names from ai.yaml for each resource type
var storageConnectionName = hasStorageConnection ? filter(additionalDependentResources, conn => conn.resource == 'AzureStorage')[0].connection_name : ''
var acrConnectionName = hasAcrConnection ? filter(additionalDependentResources, conn => conn.resource == 'AzureContainerRegistry')[0].connection_name : ''
var searchConnectionName = hasSearchConnection ? filter(additionalDependentResources, conn => conn.resource == 'AzureAISearch')[0].connection_name : ''
var bingConnectionName = hasBingConnection ? filter(additionalDependentResources, conn => conn.resource == 'BingSearch')[0].connection_name : ''
var bingCustomConnectionName = hasBingCustomConnection ? filter(additionalDependentResources, conn => conn.resource == 'BingCustomSearch')[0].connection_name : ''

// Always create a new AI Account for now (simplified approach)
// TODO: Add support for existing accounts in a future version
resource aiAccount 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: !empty(existingAiAccountName) ? existingAiAccountName : 'ai-account-${resourceToken}'
  location: location
  tags: tags
  sku: {
    name: 'S0'
  }
  kind: 'AIServices'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    allowProjectManagement: true
    customSubDomainName: !empty(existingAiAccountName) ? existingAiAccountName : 'ai-account-${resourceToken}'
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
  
  @batchSize(1)
  resource seqDeployments 'deployments' = [
    for dep in (deployments??[]): {
      name: dep.name
      properties: {
        model: dep.model
      }
      sku: dep.sku
    }
  ]

  resource project 'projects' = {
    name: envName
    location: location
    identity: {
      type: 'SystemAssigned'
    }
    properties: {
      description: '${envName} Project'
      displayName: '${envName}Project'
    }
    dependsOn: [
      seqDeployments
    ]
  }
}

// Create connections from ai.yaml configuration
module aiConnections './connection.bicep' = [for (connection, index) in connections: {
  name: 'connection-${connection.name}'
  params: {
    aiServicesAccountName: aiAccount.name
    aiProjectName: aiAccount::project.name
    connectionConfig: {
      name: connection.name
      category: connection.category
      target: connection.target
      authType: connection.authType
    }
    apiKey: '' // API keys should be provided via secure parameters or Key Vault
  }
}]

resource localUserAiDeveloperRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: resourceGroup()
  name: guid(subscription().id, resourceGroup().id, principalId, '64702f94-c441-49e6-a78b-ef80e0188fee')
  properties: {
    principalId: principalId
    principalType: principalType
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '64702f94-c441-49e6-a78b-ef80e0188fee')
  }
}

resource localUserCognitiveServicesUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: resourceGroup()
  name: guid(subscription().id, resourceGroup().id, principalId, 'a97b65f3-24c7-4388-baec-2e87135dc908')
  properties: {
    principalId: principalId
    principalType: principalType
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', 'a97b65f3-24c7-4388-baec-2e87135dc908')
  }
}


// All connections are now created directly within their respective resource modules
// using the centralized ./connection.bicep module

// Storage module - deploy if storage connection is defined in ai.yaml
module storage './dependencies/storage.bicep' = if (hasStorageConnection) {
  name: 'storage'
  params: {
    location: location
    tags: tags
    storageAccountName: 'st${resourceToken}'
    connectionName: storageConnectionName
    principalId: principalId
    principalType: principalType
    aiServicesAccountName: aiAccount.name
    aiProjectName: aiAccount::project.name
  }
}

// Azure Container Registry module - deploy if ACR connection is defined in ai.yaml
module acr './dependencies/acr.bicep' = if (hasAcrConnection) {
  name: 'acr'
  params: {
    location: location
    tags: tags
    resourceName: '${abbrs.containerRegistryRegistries}${resourceToken}'
    connectionName: acrConnectionName
    principalId: principalId
    principalType: principalType
    aiServicesAccountName: aiAccount.name
    aiServicesProjectName: aiAccount::project.name
    aiProjectName: aiAccount::project.name
  }
}

// Bing Search grounding module - deploy if Bing connection is defined in ai.yaml or parameter is enabled
module bingGrounding './dependencies/bing_grounding.bicep' = if (hasBingConnection) {
  name: 'bing-grounding'
  params: {
    tags: tags
    resourceName: 'bing-${resourceToken}'
    connectionName: bingConnectionName
    aiAccountPrincipalId: aiAccount.identity.principalId
    aiAccountName: aiAccount.name
    aiServicesAccountName: aiAccount.name
    aiProjectName: aiAccount::project.name
  }
}

// Bing Custom Search grounding module - deploy if custom Bing connection is defined in ai.yaml or parameter is enabled
module bingCustomGrounding './dependencies/bing_custom_grounding.bicep' = if (hasBingCustomConnection) {
  name: 'bing-custom-grounding'
  params: {
    tags: tags
    resourceName: 'bingcustom-${resourceToken}'
    connectionName: bingCustomConnectionName
    aiAccountPrincipalId: aiAccount.identity.principalId
    aiAccountName: aiAccount.name
    aiServicesAccountName: aiAccount.name
    aiProjectName: aiAccount::project.name
  }
}

// Azure AI Search module - deploy if search connection is defined in ai.yaml
module azureAiSearch './dependencies/azure_ai_search.bicep' = if (hasSearchConnection) {
  name: 'azure-ai-search'
  params: {
    tags: tags
    azureSearchResourceName: 'search-${resourceToken}'
    connectionName: searchConnectionName
    aiAccountPrincipalId: aiAccount.identity.principalId
    storageAccountResourceId: hasStorageConnection ? storage!.outputs.storageAccountId : ''
    containerName: 'knowledge'
    aiServicesAccountName: aiAccount.name
    aiProjectName: aiAccount::project.name
    principalId: principalId
    principalType: principalType
    location: location
  }
}


// Outputs
output ENDPOINT string = aiAccount::project.properties.endpoints['AI Foundry API']
output aiServicesEndpoint string = aiAccount.properties.endpoint
output projectId string = aiAccount::project.id
output aiServicesAccountName string = aiAccount.name
output aiServicesProjectName string = aiAccount::project.name
output aiServicesPrincipalId string = aiAccount.identity.principalId

// Grouped dependent resources outputs
output dependentResources object = {
  containerRegistry: {
    name: hasAcrConnection ? acr!.outputs.containerRegistryName : ''
    loginServer: hasAcrConnection ? acr!.outputs.containerRegistryLoginServer : ''
    connectionName: hasAcrConnection ? acr!.outputs.containerRegistryConnectionName : ''
  }
  bingSearch: {
    name: (hasBingConnection) ? bingGrounding!.outputs.bingSearchName : ''
    connectionName: (hasBingConnection) ? bingGrounding!.outputs.bingSearchConnectionName : ''
    connectionId: (hasBingConnection) ? bingGrounding!.outputs.bingSearchConnectionId : ''
  }
  bingCustomSearch: {
    name: (hasBingCustomConnection) ? bingCustomGrounding!.outputs.bingCustomSearchName : ''
    connectionName: (hasBingCustomConnection) ? bingCustomGrounding!.outputs.bingCustomSearchConnectionName : ''
  }
  search: {
    serviceName: hasSearchConnection ? azureAiSearch!.outputs.searchServiceName : ''
    connectionName: hasSearchConnection ? azureAiSearch!.outputs.searchConnectionName : ''
  }
  storage: {
    accountName: hasStorageConnection ? storage!.outputs.storageAccountName : ''
    connectionName: hasStorageConnection ? storage!.outputs.storageConnectionName : ''
  }
}

type deploymentsType = {
  @description('Specify the name of cognitive service account deployment.')
  name: string

  @description('Required. Properties of Cognitive Services account deployment model.')
  model: {
    @description('Required. The name of Cognitive Services account deployment model.')
    name: string

    @description('Required. The format of Cognitive Services account deployment model.')
    format: string

    @description('Required. The version of Cognitive Services account deployment model.')
    version: string
  }

  @description('The resource model definition representing SKU.')
  sku: {
    @description('Required. The name of the resource model definition representing SKU.')
    name: string

    @description('The capacity of the resource model definition representing SKU.')
    capacity: int
  }
}[]?

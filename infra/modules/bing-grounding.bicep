targetScope = 'resourceGroup'

@description('Tags for all resources')
param tags object = {}

@description('AI Services account name')
param aiAccountName string

@description('AI project name')
param aiProjectName string

@description('Managed identity principal ID of the AI project')
param projectPrincipalId string

@description('Connection name for the Foundry Project')
param connectionName string

var resourceToken = uniqueString(subscription().id, resourceGroup().id)

resource bingSearch 'Microsoft.Bing/accounts@2020-06-10' = {
  name: 'bing-${resourceToken}'
  location: 'global'
  tags: tags
  sku: { name: 'G1' }
  kind: 'Bing.Grounding'
  properties: { statisticsEnabled: false }
}

// Project MI: Cognitive Services User
resource bingRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: bingSearch
  name: guid(bingSearch.id, projectPrincipalId, 'a97b65f3-24c7-4388-baec-2e87135dc908')
  properties: {
    principalId: projectPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', 'a97b65f3-24c7-4388-baec-2e87135dc908')
  }
}

// Connection to Foundry Project
module bingConnection './connection.bicep' = {
  name: 'bing-connection'
  params: {
    aiAccountName: aiAccountName
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
    credentials: { key: bingSearch.listKeys().key1 }
  }
  dependsOn: [bingRole]
}

output bingName string = bingSearch.name
output connectionName string = bingConnection.outputs.connectionName
output connectionId string = bingConnection.outputs.connectionId

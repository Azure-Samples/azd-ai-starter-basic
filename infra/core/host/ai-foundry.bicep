@description('Resource ID of the existing AI Foundry (Azure OpenAI) account')
param aiFoundryResourceId string

// Extract resource group and subscription from the resource ID
var subscriptionId = split(aiFoundryResourceId, '/')[2]
var resourceGroupName = split(aiFoundryResourceId, '/')[4]
var accountName = split(aiFoundryResourceId, '/')[8]

// Reference the existing AI Foundry resource
resource aiFoundry 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  scope: resourceGroup(subscriptionId, resourceGroupName)
  name: accountName
}

output endpoint string = aiFoundry.properties.endpoint
output resourceId string = aiFoundry.id

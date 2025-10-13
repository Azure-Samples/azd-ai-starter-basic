param name string
param location string = resourceGroup().location
param tags object = {}

param identityName string
param containerAppsEnvironmentName string
param containerRegistryName string
param serviceName string = 'cobo-agent'
param openaiEndpoint string
param openaiApiVersion string
param openaiDeployment string

@description('AI Foundry Project system-assigned identity principal ID (object ID)')
param aiFoundryProjectPrincipalId string

@description('AI Foundry Project system-assigned identity tenant ID')
param aiFoundryProjectTenantId string

@description('AI Foundry Project application ID (client ID) for authentication')
param aiFoundryProjectAppId string = ''

resource coboAgentIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
}

module app 'core/host/container-app-upsert.bicep' = {
  name: '${serviceName}-container-app-module'
  params: {
    name: name
    location: location
    tags: union(tags, { 'azd-service-name': serviceName })
    identityName: coboAgentIdentity.name
    containerAppsEnvironmentName: containerAppsEnvironmentName
    containerRegistryName: containerRegistryName
    targetPort: 8088
    authEnabled: !empty(aiFoundryProjectAppId)
    authAppId: aiFoundryProjectAppId
    authIssuerUrl: 'https://sts.windows.net/${aiFoundryProjectTenantId}/'
    #disable-next-line no-hardcoded-env-urls
    authAllowedAudiences: [ 'https://management.azure.com' ]
    authRequireClientApp: false
    secrets: []
    env: [
      {
        name: 'AZURE_OPENAI_ENDPOINT'
        value: openaiEndpoint
      }
      {
        name: 'AZURE_OPENAI_DEPLOYMENT_NAME'
        value: openaiDeployment
      }
      {
        name: 'AZURE_OPENAI_CHAT_DEPLOYMENT_NAME'
        value: openaiDeployment
      }
      {
        name: 'OPENAI_API_VERSION'
        value: openaiApiVersion
      }
      {
        name: 'AZURE_CLIENT_ID'
        value: coboAgentIdentity.properties.clientId
      }
    ]
  }
}

// Grant Container Apps Contributor role to AI Foundry Project's system-assigned identity on the Container App
// Role definition ID for "Container Apps Contributor" is: 358470bc-b998-42bd-ab17-a7e34c199c0f
module roleAssignment 'core/security/container-app-role.bicep' = {
  name: '${serviceName}-role-assignment'
  params: {
    containerAppName: app.outputs.name
    principalId: aiFoundryProjectPrincipalId
    roleDefinitionId: '358470bc-b998-42bd-ab17-a7e34c199c0f'
    principalType: 'ServicePrincipal'
  }
}

// NOTE: "Cognitive Services OpenAI User" role for Container App's managed identity on AI Foundry Account
// is assigned in resources.bicep (coboAgentOpenAIRole)
// Role: 5e0bd9bd-7b93-4f28-af87-19fc36ad61bd (Cognitive Services OpenAI User)
// This role provides access to Azure OpenAI services

output COBO_AGENT_IDENTITY_PRINCIPAL_ID string = coboAgentIdentity.properties.principalId
output COBO_AGENT_NAME string = app.outputs.name
output COBO_AGENT_URI string = app.outputs.uri
output COBO_AGENT_IMAGE_NAME string = app.outputs.imageName
output COBO_AGENT_RESOURCE_ID string = app.outputs.resourceId
output AI_FOUNDRY_PROJECT_PRINCIPAL_ID string = aiFoundryProjectPrincipalId
output AI_FOUNDRY_PROJECT_TENANT_ID string = aiFoundryProjectTenantId

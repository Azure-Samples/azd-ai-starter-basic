param name string
param location string = resourceGroup().location
param tags object = {}

param identityName string
param containerAppsEnvironmentName string
param containerRegistryName string
param serviceName string = 'cobo-agent'
param openaiEndpoint string
param openaiApiVersion string

@description('AI Foundry Account resource name for OpenAI access')
param aiServicesAccountName string

@description('AI Foundry Project name within the account')
param aiProjectName string

// Get reference to the existing AI project to access its identity
resource aiAccount 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: aiServicesAccountName

  resource project 'projects' existing = {
    name: aiProjectName
  }
}

// Using user-assigned managed identity instead of system-assigned to avoid
// the 60+ second delay required for ACR role assignment propagation.
// With user-assigned identity, we can create the identity and grant ACR access
// before creating the Container App, eliminating the delay during deployment.
resource apiIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
}

module app 'core/host/container-app-upsert.bicep' = {
  name: '${serviceName}-container-app-module'
  params: {
    name: name
    location: location
    tags: union(tags, { 'azd-service-name': serviceName })
    identityName: apiIdentity.name
    containerAppsEnvironmentName: containerAppsEnvironmentName
    containerRegistryName: containerRegistryName
    targetPort: 8088
    authEnabled: false  // Authentication will be configured by postdeploy script
    authAppId: ''
    authIssuerUrl: ''
    authAllowedAudiences: []
    authRequireClientApp: false
    secrets: []
    env: [
      {
        name: 'AZURE_OPENAI_ENDPOINT'
        value: openaiEndpoint
      }
      {
        name: 'OPENAI_API_VERSION'
        value: openaiApiVersion
      }
      {
        name: 'AZURE_CLIENT_ID'
        value: apiIdentity.properties.clientId
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
    principalId: aiAccount::project.identity.principalId
    roleDefinitionId: '358470bc-b998-42bd-ab17-a7e34c199c0f'
    principalType: 'ServicePrincipal'
  }
}

// Grant Azure AI User role to Container App's user-assigned managed identity on AI Foundry Account
// Role ID: 53ca6127-db72-4b80-b1b0-d745d6d5456d (Azure AI User)
resource aiUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiAccount.id, apiIdentity.id, '53ca6127-db72-4b80-b1b0-d745d6d5456d')
  scope: aiAccount
  properties: {
    principalId: apiIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '53ca6127-db72-4b80-b1b0-d745d6d5456d')
  }
}


output SERVICE_API_IDENTITY_PRINCIPAL_ID string = apiIdentity.properties.principalId
output SERVICE_API_NAME string = app.outputs.name
output SERVICE_API_URI string = app.outputs.uri
output SERVICE_API_IMAGE_NAME string = app.outputs.imageName
output SERVICE_API_RESOURCE_ID string = app.outputs.resourceId
output AI_FOUNDRY_PROJECT_PRINCIPAL_ID string = aiAccount::project.identity.principalId
output AI_FOUNDRY_PROJECT_TENANT_ID string = aiAccount::project.identity.tenantId

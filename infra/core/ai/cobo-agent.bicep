param location string = resourceGroup().location
param tags object = {}

param containerRegistryName string
param serviceName string = 'CalculatorAgentLG'
param openaiEndpoint string
param openaiApiVersion string

@description('AI Foundry Account resource name for OpenAI access')
param aiServicesAccountName string

@description('AI Foundry Project name within the account')
param aiProjectName string

@description('Principal ID for authentication')
param authAppId string

var resourceToken = uniqueString(subscription().id, resourceGroup().id, location)
var prefix = 'ca-${aiProjectName}-${resourceToken}'
var containerAppsEnvironmentName = '${prefix}-env'
var containerAppName = replace(take(prefix, 32), '--', '-')
var userAssignedIdentityName = '${prefix}-id'

// Container Apps Environment for COBO agent
module containerAppsEnvironment '../host/container-apps-environment.bicep' = {
  scope: resourceGroup()
  name: 'container-apps-environment'
  params: {
    name: containerAppsEnvironmentName
    location: location
    tags: tags
  }
}

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
  name: userAssignedIdentityName
  location: location
}

module app '../host/container-app.bicep' = {
  name: '${serviceName}-container-app-module'
  dependsOn: [containerAppsEnvironment]
  params: {
    name: containerAppName
    location: location
    tags: union(tags, { 'azd-service-name': serviceName })
    identityName: apiIdentity.name
    containerAppsEnvironmentName: containerAppsEnvironmentName
    containerRegistryName: containerRegistryName
    targetPort: 8088
    imageName: ''  // Empty during provision, azd deploy will update with actual image
    authEnabled: true
    authAppId: authAppId
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
module roleAssignment '../security/container-app-role.bicep' = {
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


output COBO_ACA_IDENTITY_PRINCIPAL_ID string = apiIdentity.properties.principalId
output SERVICE_API_RESOURCE_ID string = app.outputs.resourceId

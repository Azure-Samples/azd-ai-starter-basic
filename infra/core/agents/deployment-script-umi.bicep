// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.
//
// Creates a user-assigned managed identity used to run the digital-worker
// deployment script, and grants it the roles required to create a Managed Agent
// Identity Blueprint (MAIB) in the Foundry project via a data-plane call.

targetScope = 'resourceGroup'

@description('Name of the User Assigned Managed Identity to create')
param identityName string = 'foundry-deployment-script-umi'

resource umi 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: resourceGroup().location
}

resource contributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, umi.id, 'Contributor')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'b24988ac-6180-42a0-ab88-20f7382dd24c'
    )
    principalId: umi.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

var cognitiveServicesUserRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a97b65f3-24c7-4388-baec-2e87135dc908')

resource cogServicesUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, umi.id, cognitiveServicesUserRoleDefinitionId)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: cognitiveServicesUserRoleDefinitionId
    principalId: umi.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

output uamiClientId string = umi.properties.clientId
output uamiPrincipalId string = umi.properties.principalId
output uamiResourceId string = umi.id

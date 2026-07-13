// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.
//
// Creates a Managed Agent Identity Blueprint (MAIB) in the Foundry project. The
// blueprint backs an activity-protocol digital worker. Because blueprint creation
// is a data-plane operation, it runs via an AzurePowerShell deployment script
// executed as the supplied user-assigned managed identity.

targetScope = 'resourceGroup'

@description('User-assigned managed identity resource ID that the script will run as')
param uamiResourceId string

@description('Azure AI Project (Foundry) endpoint URL')
param azureAIProjectEndpoint string

@description('Managed agent identity blueprint name for the Azure AI Project')
param maibName string

resource psScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-agent-script'
  location: resourceGroup().location
  kind: 'AzurePowerShell'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uamiResourceId}': {}
    }
  }
  properties: {
    azPowerShellVersion: '11.5'
    timeout: 'PT15M'
    retentionInterval: 'P1D'
    arguments: '-AzureAIProjectEndpoint "${azureAIProjectEndpoint}" -MAIBName "${maibName}"'
    environmentVariables: [
      {
        name: 'RESOURCE_GROUP_NAME'
        value: resourceGroup().name
      }
    ]
    scriptContent: '''
  param(
    [Parameter(Mandatory = $true)]
    [string] $AzureAIProjectEndpoint,
    [Parameter(Mandatory = $true)]
    [string] $MAIBName
  )

  $ErrorActionPreference = "Stop"

  $maibUrl = "$($AzureAIProjectEndpoint)/managedagentidentityblueprints/$($MAIBName)?api-version=2025-11-15-preview"

  Write-Host "Connecting with managed identity..."
  Connect-AzAccount -Identity

  Write-Host "Getting access token for https://ai.azure.com ..."
  $tokenResponse = Get-AzAccessToken -ResourceUrl "https://ai.azure.com"
  $aiAzureToken  = $tokenResponse.Token | ConvertFrom-SecureString -AsPlainText
  Write-Host "Token length: $($aiAzureToken.Length)"

  $headers = @{
      "Content-Type"  = "application/json"
      "Accept"        = "application/json"
      "Authorization" = "Bearer $aiAzureToken"
  }

  Write-Host "Creating managed agent identity blueprint at: $maibUrl"

  $response = Invoke-RestMethod -Uri $maibUrl `
      -Method Put `
      -Headers $headers `
      -ErrorAction Stop

  Write-Host ""
  Write-Host "Response:"
  $response | ConvertTo-Json -Depth 100 | Write-Host

  $blueprintClientId = $response.agentIdentityBlueprint.clientId

  $DeploymentScriptOutputs = @{
      blueprintClientId = $blueprintClientId
  }
'''
  }
}

output blueprintClientId string = psScript.properties.outputs.blueprintClientId

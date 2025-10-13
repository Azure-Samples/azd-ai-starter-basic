param principalId string
param location string = resourceGroup().location

resource getAppId 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'get-sp-app-id-${uniqueString(principalId)}'
  location: location
  kind: 'AzureCLI'
  properties: {
    azCliVersion: '2.52.0'
    retentionInterval: 'PT1H'
    timeout: 'PT5M'
    cleanupPreference: 'OnSuccess'
    scriptContent: '''
      appId=$(az ad sp show --id ${principalId} --query appId -o tsv)
      echo "{\"appId\": \"$appId\"}" > $AZ_SCRIPTS_OUTPUT_PATH
    '''
    environmentVariables: [
      {
        name: 'principalId'
        value: principalId
      }
    ]
  }
}

output appId string = getAppId.properties.outputs.appId

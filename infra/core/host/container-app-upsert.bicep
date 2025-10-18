param name string
param location string = resourceGroup().location
param tags object = {}

param containerAppsEnvironmentName string
param containerName string = 'main'
param containerRegistryName string

@description('Minimum number of replicas to run')
@minValue(1)
param containerMinReplicas int = 1
@description('Maximum number of replicas to run')
@minValue(1)
param containerMaxReplicas int = 10

param secrets array = []
param env array = []
param external bool = true
param targetPort int = 80

@description('User assigned identity name')
param identityName string

@description('Enabled Ingress for container app')
param ingressEnabled bool = true

// Dapr Options
@description('Enable Dapr')
param daprEnabled bool = false
@description('Dapr app ID')
param daprAppId string = containerName
@allowed([ 'http', 'grpc' ])
@description('Protocol used by Dapr to connect to the app, e.g. http or grpc')
param daprAppProtocol string = 'http'

@description('CPU cores allocated to a single container instance, e.g. 0.5')
param containerCpuCoreCount string = '0.5'

@description('Memory allocated to a single container instance, e.g. 1Gi')
param containerMemory string = '1.0Gi'

@description('Enable authentication')
param authEnabled bool = false

@description('Authentication App ID (client ID)')
param authAppId string = ''

@description('Authentication Issuer URL')
param authIssuerUrl string = ''

@description('Allowed token audiences')
param authAllowedAudiences array = []

@description('Require client application (true) or allow requests only from this application itself (false)')
param authRequireClientApp bool = false

// Always use empty imageName to force fallback image during provisioning
// azd deploy will update with the actual built image

module app 'container-app.bicep' = {
  name: '${deployment().name}-update'
  params: {
    name: name
    location: location
    tags: tags
    identityName: identityName
    ingressEnabled: ingressEnabled
    containerName: containerName
    containerAppsEnvironmentName: containerAppsEnvironmentName
    containerRegistryName: containerRegistryName
    containerCpuCoreCount: containerCpuCoreCount
    containerMemory: containerMemory
    containerMinReplicas: containerMinReplicas
    containerMaxReplicas: containerMaxReplicas
    daprEnabled: daprEnabled
    daprAppId: daprAppId
    daprAppProtocol: daprAppProtocol
    secrets: secrets
    external: external
    env: env
    imageName: ''
    targetPort: targetPort
    authEnabled: authEnabled
    authAppId: authAppId
    authIssuerUrl: authIssuerUrl
    authAllowedAudiences: authAllowedAudiences
    authRequireClientApp: authRequireClientApp
  }
}

output defaultDomain string = app.outputs.defaultDomain
output imageName string = app.outputs.imageName
output name string = app.outputs.name
output uri string = app.outputs.uri
output resourceId string = app.outputs.resourceId

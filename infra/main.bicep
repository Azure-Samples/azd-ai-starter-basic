targetScope = 'subscription'
// targetScope = 'resourceGroup'

@minLength(1)
@maxLength(64)
@description('Name of the environment that can be used as part of naming resource convention')
param environmentName string

@minLength(1)
@maxLength(90)
@description('Name of the resource group to use or create')
param resourceGroupName string = 'rg-${environmentName}'

// Restricted locations to match list from
// https://learn.microsoft.com/en-us/azure/ai-foundry/openai/how-to/responses?tabs=python-key#region-availability
@minLength(1)
@description('Primary location for all resources')
@allowed([
  'australiaeast'
  'brazilsouth'
  'canadacentral'
  'canadaeast'
  'eastus'
  'eastus2'
  'francecentral'
  'germanywestcentral'
  'italynorth'
  'japaneast'
  'koreacentral'
  'northcentralus'
  'norwayeast'
  'polandcentral'
  'southafricanorth'
  'southcentralus'
  'southeastasia'
  'southindia'
  'spaincentral'
  'swedencentral'
  'switzerlandnorth'
  'uaenorth'
  'uksouth'
  'westus'
  'westus2'
  'westus3'
])
param location string

param aiDeploymentsLocation string = location

@description('Id of the user or app to assign application roles')
param principalId string

@description('Principal type of user or app')
param principalType string

@description('Optional. Name of an existing AI Services account within the resource group. If not provided, a new one will be created.')
param aiFoundryResourceName string = ''

@description('Optional. Name of the AI Foundry project. If not provided, a default name will be used.')
param aiFoundryProjectName string = 'ai-project-${environmentName}'

@description('List of model deployments')
param aiProjectDeploymentsJson string = '[]'

@description('List of connections')
param aiProjectConnectionsJson string = '[]'

@secure()
@description('JSON map of connection name to credentials object. Example: {"my-conn":{"key":"secret"}}')
param aiProjectConnectionCredentialsJson string = '{}'

@description('List of resources to create and connect to the AI project')
param aiProjectDependentResourcesJson string = '[]'

var aiProjectDeployments = json(aiProjectDeploymentsJson)
var aiProjectConnections = json(aiProjectConnectionsJson)
var aiProjectConnectionCreds = json(aiProjectConnectionCredentialsJson)
var aiProjectDependentResources = json(aiProjectDependentResourcesJson)

@description('Enable hosted agent deployment')
param enableHostedAgents bool

@description('Enable the capability host for supporting BYO storage of agent conversations. When false and hosted agents are enabled, the capability host is not created.')
param enableCapabilityHost bool

@description('Enable monitoring for the AI project')
param enableMonitoring bool

@description('When true, skip Foundry project/role/connection provisioning and reference the existing project read-only. Use when pointing at an existing Foundry project via --project-id.')
param useExistingAiProject bool = false

@description('Optional. Existing container registry resource ID. If provided, no new ACR will be created and a connection to this ACR will be established.')
param existingContainerRegistryResourceId string = ''

@description('Optional. Existing container registry endpoint (login server). Required if existingContainerRegistryResourceId is provided.')
param existingContainerRegistryEndpoint string = ''

@description('Optional. Name of an existing ACR connection on the Foundry project. If provided, no new ACR or connection will be created.')
param existingAcrConnectionName string = ''

@description('Optional. Skip ACR creation entirely (e.g. for code-deploy scenarios where no container registry is needed). Defaults to false for backward compatibility.')
param skipAcr bool = false

@description('Optional. Existing Application Insights connection string. If provided, a connection will be created but no new App Insights resource.')
param existingApplicationInsightsConnectionString string = ''

@description('Optional. Existing Application Insights resource ID. Used for connection metadata when providing an existing App Insights.')
param existingApplicationInsightsResourceId string = ''

@description('Optional. Name of an existing Application Insights connection on the Foundry project. If provided, no new App Insights or connection will be created.')
param existingAppInsightsConnectionName string = ''

// ---------- Existing account ----------

@description('When true, reference an existing AI Foundry account (created out of band) instead of creating a new one. A new project (and its deployments, capability host, and connections) is still created on that account. Implied true when existingAiAccountResourceId is non-empty. The account MUST live in the SAME resource group as this deployment.')
param useExistingAiAccount bool = false

@description('Optional. Full ARM resource ID of an existing AI Foundry (Microsoft.CognitiveServices/accounts, kind=AIServices) account to reuse. The account name is parsed from this ID. The account MUST live in the SAME resource group as this deployment.')
param existingAiAccountResourceId string = ''

// ---------- Network ----------

@description('Network mode for the AI Foundry account: none (public, default) | managed (Microsoft-managed network) | byo-vnet (customer-delegated agent subnet + private endpoint on the account).')
@allowed([
  'none'
  'managed'
  'byo-vnet'
])
param networkMode string = 'none'

@description('Optional. Full ARM resource ID of an existing VNet to reuse. The agent subnet must already be delegated to Microsoft.App/environments. Empty creates a new VNet in this resource group. Cross-RG / cross-subscription safe.')
param existingVnetResourceId string = ''

@description('Name of the new VNet (created when networkMode is byo-vnet and existingVnetResourceId is empty).')
param vnetName string = 'vnet-${environmentName}'

@description('VNet address prefix. Empty defaults to 192.168.0.0/16. Ignored for existing VNets.')
param vnetAddressPrefix string = ''

@description('Agent subnet name (delegated to Microsoft.App/environments).')
param agentSubnetName string = 'agent-subnet'

@description('Agent subnet prefix. Empty derives 192.168.0.0/24 from the default VNet prefix. Ignored for existing VNets.')
param agentSubnetPrefix string = ''

@description('Private endpoint subnet name.')
param peSubnetName string = 'pe-subnet'

@description('PE subnet prefix. Empty derives 192.168.1.0/24 from the default VNet prefix. Ignored for existing VNets.')
param peSubnetPrefix string = ''

@description('JSON array of IPv4 addresses or CIDR ranges allowed to reach the AI Foundry account data plane while public access is enabled (used only when networkMode is byo-vnet).')
param clientIpAllowList array = []

@description('When true, set publicNetworkAccess=Disabled on the AI Foundry account. Requires running azd from inside the VNet (or via a private VPN/peer). Only relevant when networkMode is byo-vnet.')
param disablePublicNetworkAccess bool = false

@description('Map of existing private DNS zone FQDN -> resource group name. Empty value means create a new zone in the current RG. Only consulted when networkMode is byo-vnet.')
param existingDnsZones object = {
  'privatelink.services.ai.azure.com': ''
  'privatelink.openai.azure.com': ''
  'privatelink.cognitiveservices.azure.com': ''
}

@description('Subscription ID where the existing private DNS zones live. Empty defaults to the current subscription. Accepts a bare GUID or /subscriptions/<guid> path.')
param dnsZonesSubscriptionId string = ''

// Tags that should be applied to all resources.
// 
// Note that 'azd-service-name' tags should be applied separately to service host resources.
// Example usage:
//   tags: union(tags, { 'azd-service-name': <service name in azure.yaml> })
var tags = {
  'azd-env-name': environmentName
}

// Check if resource group exists and create it if it doesn't
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// ---------- Network derivations ----------

var isByoVnet = networkMode == 'byo-vnet'

// VNet (only created/referenced when networkMode is byo-vnet). When isByoVnet
// is false, this module is skipped entirely and downstream consumers fall
// back to empty strings.
module vnet 'core/networking/vnet.bicep' = if (isByoVnet) {
  scope: rg
  name: 'vnet'
  params: {
    location: aiDeploymentsLocation
    tags: tags
    vnetName: vnetName
    existingVnetResourceId: existingVnetResourceId
    vnetAddressPrefix: vnetAddressPrefix
    agentSubnetName: agentSubnetName
    agentSubnetPrefix: agentSubnetPrefix
    peSubnetName: peSubnetName
    peSubnetPrefix: peSubnetPrefix
  }
}

#disable-next-line BCP318
var agentSubnetIdValue = isByoVnet ? vnet.outputs.agentSubnetId : ''

// Build dependent resources array conditionally
// Check if ACR already exists in the user-provided array to avoid duplicates
// Also skip if user provided an existing container registry endpoint or connection name
var hasAcr = contains(map(aiProjectDependentResources, r => r.resource), 'registry')
var shouldCreateAcr = !skipAcr && enableHostedAgents && !hasAcr && empty(existingContainerRegistryResourceId) && empty(existingAcrConnectionName)
var dependentResources = shouldCreateAcr ? union(aiProjectDependentResources, [
  {
    resource: 'registry'
    connectionName: 'acr-${uniqueString(subscription().id, resourceGroupName, location)}'
  }
]) : aiProjectDependentResources

// AI Project module -- only when creating new resources
module aiProject 'core/ai/ai-project.bicep' = if (!useExistingAiProject) {
  scope: rg
  name: 'ai-project'
  params: {
    tags: tags
    location: aiDeploymentsLocation
    aiFoundryProjectName: aiFoundryProjectName
    principalId: principalId
    principalType: principalType
    existingAiAccountName: aiFoundryResourceName
    useExistingAiAccount: useExistingAiAccount
    existingAiAccountResourceId: existingAiAccountResourceId
    deployments: aiProjectDeployments
    connections: aiProjectConnections
    connectionCredentials: aiProjectConnectionCreds
    additionalDependentResources: dependentResources
    enableMonitoring: enableMonitoring
    enableHostedAgents: enableHostedAgents
    enableCapabilityHost: enableCapabilityHost
    existingContainerRegistryResourceId: existingContainerRegistryResourceId
    existingContainerRegistryEndpoint: existingContainerRegistryEndpoint
    existingAcrConnectionName: existingAcrConnectionName
    existingApplicationInsightsConnectionString: existingApplicationInsightsConnectionString
    existingApplicationInsightsResourceId: existingApplicationInsightsResourceId
    existingAppInsightsConnectionName: existingAppInsightsConnectionName
    networkMode: networkMode
    agentSubnetId: agentSubnetIdValue
    clientIpAllowList: clientIpAllowList
    disablePublicNetworkAccess: disablePublicNetworkAccess
  }
}

// Private endpoint + DNS for the AI Foundry account (only when networkMode is
// byo-vnet). Created after the account exists so the PE can target it.
// Skipped for the read-only existing-project path (existing-ai-project.bicep)
// since that flow expects PE/DNS to already be in place.
module accountPeDns 'core/networking/private-endpoint-and-dns.bicep' = if (isByoVnet && !useExistingAiProject) {
  scope: rg
  name: 'account-pe-dns'
  params: {
    location: aiDeploymentsLocation
    #disable-next-line BCP318
    foundryAccountName: aiProject.outputs.aiServicesAccountName
    #disable-next-line BCP318
    foundryAccountId: aiProject.outputs.accountId
    #disable-next-line BCP318
    vnetName: isByoVnet ? vnet.outputs.vnetName : ''
    #disable-next-line BCP318
    vnetSubscriptionId: isByoVnet ? vnet.outputs.vnetSubscriptionId : subscription().subscriptionId
    #disable-next-line BCP318
    vnetResourceGroupName: isByoVnet ? vnet.outputs.vnetResourceGroupName : rg.name
    peSubnetName: peSubnetName
    suffix: uniqueString(subscription().id, resourceGroupName, location)
    existingDnsZones: existingDnsZones
    dnsZonesSubscriptionId: empty(dnsZonesSubscriptionId) ? subscription().subscriptionId : dnsZonesSubscriptionId
  }
}

// Existing project module -- read-only reference when reusing an existing Foundry project
module existingAiProject 'core/ai/existing-ai-project.bicep' = if (useExistingAiProject) {
  scope: rg
  name: 'existing-ai-project'
  params: {
    aiServicesAccountName: aiFoundryResourceName
    aiFoundryProjectName: aiFoundryProjectName
    deployments: aiProjectDeployments
    existingAcrConnectionName: existingAcrConnectionName
    existingContainerRegistryEndpoint: existingContainerRegistryEndpoint
    existingApplicationInsightsConnectionString: existingApplicationInsightsConnectionString
    existingApplicationInsightsResourceId: existingApplicationInsightsResourceId
    connections: aiProjectConnections
    connectionCredentials: aiProjectConnectionCreds
  }
}

// ACR for existing project -- create when hosted agents need a registry but the existing project has none
var shouldCreateAcrForExistingProject = useExistingAiProject && shouldCreateAcr
var acrConnectionName = 'acr-${uniqueString(subscription().id, resourceGroupName, location)}'

module acrForExistingProject 'core/host/acr.bicep' = if (shouldCreateAcrForExistingProject) {
  scope: rg
  name: 'acr-for-existing-project'
  params: {
    location: location
    tags: tags
    resourceName: 'cr${uniqueString(subscription().id, resourceGroupName, location)}'
    connectionName: acrConnectionName
    principalId: principalId
    principalType: principalType
    aiServicesAccountName: aiFoundryResourceName
    aiProjectName: aiFoundryProjectName
  }
}

// Resources
output AZURE_RESOURCE_GROUP string = resourceGroupName
output AZURE_AI_ACCOUNT_ID string = useExistingAiProject ? existingAiProject.outputs.accountId : aiProject.outputs.accountId
output AZURE_AI_PROJECT_ID string = useExistingAiProject ? existingAiProject.outputs.projectId : aiProject.outputs.projectId
output AZURE_AI_FOUNDRY_PROJECT_ID string = useExistingAiProject ? existingAiProject.outputs.projectId : aiProject.outputs.projectId
output AZURE_AI_ACCOUNT_NAME string = useExistingAiProject ? existingAiProject.outputs.aiServicesAccountName : aiProject.outputs.aiServicesAccountName
output AZURE_AI_PROJECT_NAME string = useExistingAiProject ? existingAiProject.outputs.projectName : aiProject.outputs.projectName

// Endpoints
output AZURE_AI_PROJECT_ENDPOINT string = useExistingAiProject ? existingAiProject.outputs.AZURE_AI_PROJECT_ENDPOINT : aiProject.outputs.AZURE_AI_PROJECT_ENDPOINT
output FOUNDRY_PROJECT_ENDPOINT string = useExistingAiProject ? existingAiProject.outputs.FOUNDRY_PROJECT_ENDPOINT : aiProject.outputs.FOUNDRY_PROJECT_ENDPOINT
output AZURE_OPENAI_ENDPOINT string = useExistingAiProject ? existingAiProject.outputs.AZURE_OPENAI_ENDPOINT : aiProject.outputs.AZURE_OPENAI_ENDPOINT
output APPLICATIONINSIGHTS_CONNECTION_STRING string = useExistingAiProject ? existingAiProject.outputs.APPLICATIONINSIGHTS_CONNECTION_STRING : aiProject.outputs.APPLICATIONINSIGHTS_CONNECTION_STRING
output APPLICATIONINSIGHTS_RESOURCE_ID string = useExistingAiProject ? existingAiProject.outputs.APPLICATIONINSIGHTS_RESOURCE_ID : aiProject.outputs.APPLICATIONINSIGHTS_RESOURCE_ID

// Dependent Resources and Connections

// ACR
output AZURE_AI_PROJECT_ACR_CONNECTION_NAME string = shouldCreateAcrForExistingProject ? acrForExistingProject.outputs.containerRegistryConnectionName : (useExistingAiProject ? existingAiProject.outputs.dependentResources.registry.connectionName : aiProject.outputs.dependentResources.registry.connectionName)
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = shouldCreateAcrForExistingProject ? acrForExistingProject.outputs.containerRegistryLoginServer : (useExistingAiProject ? existingAiProject.outputs.dependentResources.registry.loginServer : aiProject.outputs.dependentResources.registry.loginServer)

// Bing Search
output BING_GROUNDING_CONNECTION_NAME  string = useExistingAiProject ? existingAiProject.outputs.dependentResources.bing_grounding.connectionName : aiProject.outputs.dependentResources.bing_grounding.connectionName
output BING_GROUNDING_RESOURCE_NAME string = useExistingAiProject ? existingAiProject.outputs.dependentResources.bing_grounding.name : aiProject.outputs.dependentResources.bing_grounding.name
output BING_GROUNDING_CONNECTION_ID string = useExistingAiProject ? existingAiProject.outputs.dependentResources.bing_grounding.connectionId : aiProject.outputs.dependentResources.bing_grounding.connectionId

// Bing Custom Search
output BING_CUSTOM_GROUNDING_CONNECTION_NAME string = useExistingAiProject ? existingAiProject.outputs.dependentResources.bing_custom_grounding.connectionName : aiProject.outputs.dependentResources.bing_custom_grounding.connectionName
output BING_CUSTOM_GROUNDING_NAME string = useExistingAiProject ? existingAiProject.outputs.dependentResources.bing_custom_grounding.name : aiProject.outputs.dependentResources.bing_custom_grounding.name
output BING_CUSTOM_GROUNDING_CONNECTION_ID string = useExistingAiProject ? existingAiProject.outputs.dependentResources.bing_custom_grounding.connectionId : aiProject.outputs.dependentResources.bing_custom_grounding.connectionId

// Azure AI Search
output AZURE_AI_SEARCH_CONNECTION_NAME string = useExistingAiProject ? existingAiProject.outputs.dependentResources.search.connectionName : aiProject.outputs.dependentResources.search.connectionName
output AZURE_AI_SEARCH_SERVICE_NAME string = useExistingAiProject ? existingAiProject.outputs.dependentResources.search.serviceName : aiProject.outputs.dependentResources.search.serviceName

// Azure Storage
output AZURE_STORAGE_CONNECTION_NAME string = useExistingAiProject ? existingAiProject.outputs.dependentResources.storage.connectionName : aiProject.outputs.dependentResources.storage.connectionName
output AZURE_STORAGE_ACCOUNT_NAME string = useExistingAiProject ? existingAiProject.outputs.dependentResources.storage.accountName : aiProject.outputs.dependentResources.storage.accountName

// Connections
output AI_PROJECT_CONNECTION_IDS_JSON string = useExistingAiProject ? string(existingAiProject.outputs.connectionIds) : string(aiProject.outputs.connectionIds)

// Network
output FOUNDRY_NETWORK_MODE string = networkMode
#disable-next-line BCP318
output AZURE_VNET_ID string = isByoVnet ? vnet.outputs.vnetId : ''
#disable-next-line BCP318
output AZURE_VNET_NAME string = isByoVnet ? vnet.outputs.vnetName : ''
#disable-next-line BCP318
output AZURE_AGENT_SUBNET_ID string = isByoVnet ? vnet.outputs.agentSubnetId : ''
#disable-next-line BCP318
output AZURE_PE_SUBNET_ID string = isByoVnet ? vnet.outputs.peSubnetId : ''

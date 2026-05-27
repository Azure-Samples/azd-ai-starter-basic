targetScope = 'resourceGroup'

/*
  Private endpoint + 3 private DNS zones for an AI Foundry (Cognitive Services) account.

  - PE (groupIds: ['account']) on the PE subnet of the supplied VNet
  - 3 private DNS zones:
      * privatelink.services.ai.azure.com
      * privatelink.openai.azure.com
      * privatelink.cognitiveservices.azure.com
  - VNet links and a DNS zone group binding the zones to the PE.

  Supports reusing existing zones owned by a hub / platform team via the
  existingDnsZones map (zone name -> resource group). Empty string means
  "create a new zone in the current RG".
*/

@description('Name of the AI Foundry (Cognitive Services) account in the current resource group scope. The PE is created in this RG; the account itself can live elsewhere if you pass foundryAccountId.')
param foundryAccountName string

@description('Optional full ARM resource ID of the AI Foundry account. Use when the account lives in a different RG/subscription from the PE. When empty, the account is looked up by name in the current RG.')
param foundryAccountId string = ''

@description('Location for the private endpoint. Must match the region of the subnet/VNet the PE is attached to. Defaults to the current resource group location.')
param location string = resourceGroup().location

@description('Name of the VNet containing the PE subnet.')
param vnetName string

@description('Subscription ID where the VNet lives (defaults to the current subscription).')
param vnetSubscriptionId string = subscription().subscriptionId

@description('Resource group of the VNet (defaults to the current RG).')
param vnetResourceGroupName string = resourceGroup().name

@description('Name of the PE subnet within the VNet.')
param peSubnetName string

@description('Short unique suffix to disambiguate generated resource names.')
param suffix string

@description('Map of zone FQDN -> resource group of an existing zone to reuse. Empty string means create a new zone in the current RG. When an existing zone is reused, the caller is responsible for ensuring it is linked to the spoke VNet (typical hub-spoke pattern); this module only creates VNet links for zones it creates.')
param existingDnsZones object = {
  'privatelink.services.ai.azure.com': ''
  'privatelink.openai.azure.com': ''
  'privatelink.cognitiveservices.azure.com': ''
}

@description('Subscription ID where the existing private DNS zones live. Accepts either a bare GUID or a /subscriptions/<guid> path; normalized internally.')
param dnsZonesSubscriptionId string = subscription().subscriptionId

// Normalize dnsZonesSubscriptionId
var dnsZonesSubIsPath = startsWith(toLower(dnsZonesSubscriptionId), '/subscriptions/')
var resolvedDnsZonesSubscriptionId = dnsZonesSubIsPath ? split(dnsZonesSubscriptionId, '/')[2] : dnsZonesSubscriptionId

var aiServicesDnsZoneName = 'privatelink.services.ai.azure.com'
var openAiDnsZoneName = 'privatelink.openai.azure.com'
var cognitiveDnsZoneName = 'privatelink.cognitiveservices.azure.com'

var aiServicesDnsZoneRg = existingDnsZones[aiServicesDnsZoneName]
var openAiDnsZoneRg = existingDnsZones[openAiDnsZoneName]
var cognitiveDnsZoneRg = existingDnsZones[cognitiveDnsZoneName]

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: vnetName
  scope: resourceGroup(vnetSubscriptionId, vnetResourceGroupName)
}

resource peSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: vnet
  name: peSubnetName
}

resource foundryAccount 'Microsoft.CognitiveServices/accounts@2026-03-01' existing = {
  name: foundryAccountName
}

resource foundryAccountPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: '${foundryAccountName}-pe-${suffix}'
  location: location
  properties: {
    subnet: { id: peSubnet.id }
    privateLinkServiceConnections: [
      {
        name: '${foundryAccountName}-pls-${suffix}'
        properties: {
          privateLinkServiceId: empty(foundryAccountId) ? foundryAccount.id : foundryAccountId
          groupIds: ['account']
        }
      }
    ]
  }
}

// services.ai.azure.com
resource newAiServicesZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (empty(aiServicesDnsZoneRg)) {
  name: aiServicesDnsZoneName
  location: 'global'
}
resource existingAiServicesZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = if (!empty(aiServicesDnsZoneRg)) {
  name: aiServicesDnsZoneName
  scope: resourceGroup(resolvedDnsZonesSubscriptionId, aiServicesDnsZoneRg)
}
#disable-next-line BCP318
var aiServicesZoneId = empty(aiServicesDnsZoneRg) ? newAiServicesZone.id : existingAiServicesZone.id

resource newAiServicesLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = if (empty(aiServicesDnsZoneRg)) {
  parent: newAiServicesZone
  location: 'global'
  name: 'aiservices-${suffix}-link'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}

// openai.azure.com
resource newOpenAiZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (empty(openAiDnsZoneRg)) {
  name: openAiDnsZoneName
  location: 'global'
}
resource existingOpenAiZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = if (!empty(openAiDnsZoneRg)) {
  name: openAiDnsZoneName
  scope: resourceGroup(resolvedDnsZonesSubscriptionId, openAiDnsZoneRg)
}
#disable-next-line BCP318
var openAiZoneId = empty(openAiDnsZoneRg) ? newOpenAiZone.id : existingOpenAiZone.id

resource newOpenAiLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = if (empty(openAiDnsZoneRg)) {
  parent: newOpenAiZone
  location: 'global'
  name: 'openai-${suffix}-link'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}

// cognitiveservices.azure.com
resource newCognitiveZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (empty(cognitiveDnsZoneRg)) {
  name: cognitiveDnsZoneName
  location: 'global'
}
resource existingCognitiveZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = if (!empty(cognitiveDnsZoneRg)) {
  name: cognitiveDnsZoneName
  scope: resourceGroup(resolvedDnsZonesSubscriptionId, cognitiveDnsZoneRg)
}
#disable-next-line BCP318
var cognitiveZoneId = empty(cognitiveDnsZoneRg) ? newCognitiveZone.id : existingCognitiveZone.id

resource newCognitiveLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = if (empty(cognitiveDnsZoneRg)) {
  parent: newCognitiveZone
  location: 'global'
  name: 'cogserv-${suffix}-link'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}

resource foundryAccountDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: foundryAccountPrivateEndpoint
  name: '${foundryAccountName}-dns-group'
  properties: {
    privateDnsZoneConfigs: [
      { name: 'aiservices-config', properties: { privateDnsZoneId: aiServicesZoneId } }
      { name: 'openai-config', properties: { privateDnsZoneId: openAiZoneId } }
      { name: 'cogserv-config', properties: { privateDnsZoneId: cognitiveZoneId } }
    ]
  }
  dependsOn: [
    newAiServicesLink
    newOpenAiLink
    newCognitiveLink
  ]
}

output privateEndpointId string = foundryAccountPrivateEndpoint.id

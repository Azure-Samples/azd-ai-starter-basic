targetScope = 'resourceGroup'

/*
  VNet for Foundry BYO VNet (network injection) and BYO VNet Standard modes.

  Creates a new VNet + 2 subnets (agent + PE) when existingVnetResourceId is empty.
  Otherwise, references an existing VNet cross-RG / cross-subscription and exposes
  subnet IDs without mutating the existing subnets. This is the safer choice for
  hub-spoke topologies with platform-managed NSGs/route tables/policies.

  Preconditions when using an existing VNet:
    - The agent subnet MUST already be delegated to Microsoft.App/environments.
    - The PE subnet must support private endpoints (no policies preventing PEs).
    - The Foundry account region MUST match the VNet region (when main.bicep
      provisions both, set `aiDeploymentsLocation` to keep them aligned).
*/

@description('Location for the new VNet (ignored when an existing VNet is referenced).')
param location string

@description('Tags for the new VNet (ignored when an existing VNet is referenced).')
param tags object = {}

@description('Name of the VNet to create. Ignored when existingVnetResourceId is set (name is derived from the resource ID).')
param vnetName string

@description('Optional. Full ARM resource ID of an existing VNet to reuse. When set, the template will NOT create a new VNet and will reference the existing subnets without modification.')
param existingVnetResourceId string = ''

@description('Address space for the new VNet. Empty defaults to 192.168.0.0/16. Ignored for existing VNets.')
param vnetAddressPrefix string = ''

@description('Name of the agent subnet (delegated to Microsoft.App/environments). Must exist on the VNet when existingVnetResourceId is set.')
param agentSubnetName string = 'agent-subnet'

@description('Address prefix for the new agent subnet. Empty derives 192.168.0.0/24 from the default VNet prefix. Ignored for existing VNets.')
param agentSubnetPrefix string = ''

@description('Name of the private endpoint subnet. Must exist on the VNet when existingVnetResourceId is set.')
param peSubnetName string = 'pe-subnet'

@description('Address prefix for the new PE subnet. Empty derives 192.168.1.0/24 from the default VNet prefix. Ignored for existing VNets.')
param peSubnetPrefix string = ''

// ---------------------------------------------------------------------
// Derived values
// ---------------------------------------------------------------------

var hasExistingVnet = !empty(existingVnetResourceId)

var existingVnetParts = split(existingVnetResourceId, '/')
var existingVnetSubscriptionId = hasExistingVnet ? existingVnetParts[2] : subscription().subscriptionId
var existingVnetResourceGroupName = hasExistingVnet ? existingVnetParts[4] : resourceGroup().name
var resolvedVnetName = hasExistingVnet ? last(existingVnetParts) : vnetName

var defaultVnetAddressPrefix = '192.168.0.0/16'
var resolvedVnetAddressPrefix = empty(vnetAddressPrefix) ? defaultVnetAddressPrefix : vnetAddressPrefix
var resolvedAgentSubnetPrefix = empty(agentSubnetPrefix) ? cidrSubnet(resolvedVnetAddressPrefix, 24, 0) : agentSubnetPrefix
var resolvedPeSubnetPrefix = empty(peSubnetPrefix) ? cidrSubnet(resolvedVnetAddressPrefix, 24, 1) : peSubnetPrefix

// ---------------------------------------------------------------------
// New VNet
// ---------------------------------------------------------------------

resource newVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = if (!hasExistingVnet) {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [resolvedVnetAddressPrefix]
    }
    subnets: [
      {
        name: agentSubnetName
        properties: {
          addressPrefix: resolvedAgentSubnetPrefix
          delegations: [
            {
              name: 'Microsoft.app/environments'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
      {
        name: peSubnetName
        properties: {
          addressPrefix: resolvedPeSubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

// ---------------------------------------------------------------------
// Existing VNet (referenced for output; not modified)
// ---------------------------------------------------------------------

resource existingVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = if (hasExistingVnet) {
  name: resolvedVnetName
  scope: resourceGroup(existingVnetSubscriptionId, existingVnetResourceGroupName)
}

// ---------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------

output vnetName string = resolvedVnetName
#disable-next-line BCP318
output vnetId string = hasExistingVnet ? existingVnet.id : newVnet.id
output vnetSubscriptionId string = existingVnetSubscriptionId
output vnetResourceGroupName string = existingVnetResourceGroupName
output agentSubnetName string = agentSubnetName
output peSubnetName string = peSubnetName
#disable-next-line BCP318
output agentSubnetId string = hasExistingVnet
  ? resourceId(existingVnetSubscriptionId, existingVnetResourceGroupName, 'Microsoft.Network/virtualNetworks/subnets', resolvedVnetName, agentSubnetName)
  : '${newVnet.id}/subnets/${agentSubnetName}'
#disable-next-line BCP318
output peSubnetId string = hasExistingVnet
  ? resourceId(existingVnetSubscriptionId, existingVnetResourceGroupName, 'Microsoft.Network/virtualNetworks/subnets', resolvedVnetName, peSubnetName)
  : '${newVnet.id}/subnets/${peSubnetName}'

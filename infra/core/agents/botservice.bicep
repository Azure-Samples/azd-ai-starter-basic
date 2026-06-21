// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.
//
// Creates an Azure Bot Service (with a Microsoft Teams channel) for an
// activity-protocol digital worker. The bot's MSA App ID is the blueprint client
// ID, and the messaging endpoint points at the agent's activity protocol route so
// inbound Teams messages reach the deployed agent.

param botName string
param displayName string
param msaAppId string
param endpoint string
param botServiceSku string = 'F0'

resource botService 'Microsoft.BotService/botServices@2022-09-15' = {
  name: botName
  kind: 'azurebot'
  location: 'global'
  sku: {
    name: botServiceSku
  }
  properties: {
    displayName: displayName
    endpoint: endpoint
    msaAppId: msaAppId
    msaAppTenantId: tenant().tenantId
    msaAppType: 'SingleTenant'
  }
}

resource botServiceMsTeamsChannel 'Microsoft.BotService/botServices/channels@2021-03-01' = {
  parent: botService
  location: 'global'
  name: 'MsTeamsChannel'
  properties: {
    channelName: 'MsTeamsChannel'
  }
}

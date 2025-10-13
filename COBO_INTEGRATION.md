# COBO Agent Integration - Summary

## Changes Made

### 1. Source Code
- Copied COBO agent source code from `cobo-container-agent-azd-template/src/` to `src/cobo-agent/`
  - `langgraph_agent_calculator.py` - Main agent implementation
  - `requirements.txt` - Python dependencies
- Copied `Dockerfile` from COBO template to `src/cobo-agent/Dockerfile`

### 2. Infrastructure Files
- **Core Infrastructure (copied from COBO template)**:
  - `infra/core/host/container-app-upsert.bicep` - Container app deployment
  - `infra/core/host/container-apps-environment.bicep` - Container apps environment
  - `infra/core/host/container-apps.bicep` - Container apps module
  - `infra/core/security/container-app-role.bicep` - Role assignment for container apps
  - `infra/core/security/ai-user-role.bicep` - AI services role assignment

- **COBO Agent Module**:
  - `infra/cobo-agent.bicep` - Renamed from `api.bicep`, updated all references from "api" to "cobo-agent"
    - Creates managed identity for COBO agent
    - Deploys container app with authentication disabled by default
    - Sets up role assignments for AI Foundry Project to manage the container app
    - Configures environment variables for Azure OpenAI access

### 3. Main Infrastructure Updates

#### `infra/main.bicep`
- Added `enableCoboAgent` parameter (defaults to `true`)
- Pass `enableCoboAgent`, `openaiEndpoint`, and `openaiDeploymentName` to resources module
- Added outputs:
  - `AZURE_CONTAINER_ENVIRONMENT_NAME`
  - `AZURE_CONTAINER_REGISTRY_NAME`
  - `COBO_AGENT_NAME`
  - `COBO_AGENT_URI`
  - `COBO_AGENT_IDENTITY_PRINCIPAL_ID`
  - `AZURE_OPENAI_ENDPOINT`
  - `AZURE_OPENAI_DEPLOYMENT_NAME`

#### `infra/resources.bicep`
- Added parameters:
  - `enableCoboAgent` (defaults to `true`)
  - `openaiEndpoint`
  - `openaiDeploymentName`
- Added container apps environment module
- Added COBO agent module deployment
- Added outputs for COBO agent resources

#### `infra/main.parameters.json`
- Added `enableCoboAgent` parameter with default value `${ENABLE_CONTAINER_AGENT=true}`

### 4. Azure YAML Configuration
- `azure.yaml` already configured with:
  - Service: `cobo-agent` pointing to `./src/cobo-agent`
  - Language: Python
  - Host: Container App
  - Docker remote build enabled

## Key Features

### Identity and Permissions
1. **COBO Agent Managed Identity**: User-assigned managed identity for the container app
2. **AI Foundry Project Access**: AI Foundry Project's system-assigned identity gets "Container Apps Contributor" role on the container app
3. **Azure OpenAI Access**: Container app identity gets "Cognitive Services OpenAI User" role on AI Foundry Account (assigned in resources.bicep)
   - Role ID: `5e0bd9bd-7b93-4f28-af87-19fc36ad61bd`
   - Provides access to Azure OpenAI services
   - Same role as used in the original COBO template

### Environment Variables
The COBO agent receives these environment variables:
- `AZURE_OPENAI_ENDPOINT` - AI Foundry endpoint
- `AZURE_OPENAI_DEPLOYMENT_NAME` - Model deployment name (gpt-4o-mini)
- `AZURE_OPENAI_CHAT_DEPLOYMENT_NAME` - Same as deployment name
- `OPENAI_API_VERSION` - API version (2025-03-01-preview)
- `AZURE_CLIENT_ID` - Managed identity client ID for authentication

### ACR Integration
- Reuses the same ACR created by `enableHostedAgents`
- Container app configured to pull images using its managed identity
- Remote build enabled via `azd`

## Deployment

To deploy with COBO agent (default):
```bash
azd up
```

To deploy without COBO agent:
```bash
$env:ENABLE_CONTAINER_AGENT='false'
azd up
```

## Differences from Original COBO Template

1. **No External AI Foundry Project**: Uses the AI Foundry project created in this template's `ai-project.bicep`
2. **Integrated with Existing Infrastructure**: Shares ACR and follows azd infrastructure patterns
3. **Simplified Parameters**: No need to provide existing AI Foundry project resource ID or model deployment name
4. **Service Name**: Changed from "api" to "cobo-agent" throughout
5. **Default Enabled**: COBO agent deployment is enabled by default (`ENABLE_CONTAINER_AGENT=true`)

## Architecture

```
AI Foundry Project (ai-project.bicep)
    ├── Model Deployment: gpt-4o-mini
    └── System-Assigned Identity
            └── Has "Container Apps Contributor" role on COBO agent

Container Registry (resources.bicep)
    └── Shared with enableHostedAgents

Container Apps Environment (resources.bicep)
    └── COBO Agent Container App
            ├── User-Assigned Managed Identity
            │   └── Has "Cognitive Services OpenAI User" role on AI Foundry Account
            └── Authenticates to Azure OpenAI using managed identity
```

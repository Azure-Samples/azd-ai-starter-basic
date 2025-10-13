# COBO Agent Integration - Summary

## Overview

This integration adds COBO (Container-Based Operations) agent capabilities to the AI Foundry starter template. The COBO agent is deployed as an Azure Container App with Azure Active Directory authentication and full integration with AI Foundry projects.

## Changes Made

### 1. Source Code
- Copied COBO agent source code from `cobo-container-agent-azd-template/src/` to `src/cobo-agent/`
  - `langgraph_agent_calculator.py` - Main agent implementation
  - `requirements.txt` - Python dependencies
- Copied `Dockerfile` from COBO template to `src/cobo-agent/Dockerfile`

### 2. Infrastructure Files

#### Core Infrastructure (copied from COBO template)
- `infra/core/host/container-app-upsert.bicep` - Container app deployment with AAD authentication
- `infra/core/host/container-apps-environment.bicep` - Container apps environment
- `infra/core/host/container-apps.bicep` - Container apps module
- `infra/core/security/container-app-role.bicep` - Role assignment for container apps
- `infra/core/security/ai-user-role.bicep` - AI services role assignment

#### COBO Agent Module
- `infra/cobo-agent.bicep` - Main COBO agent infrastructure
  - Creates user-assigned managed identity for COBO agent
  - Deploys container app with conditional AAD authentication
  - Sets up role assignments for AI Foundry Project to manage the container app (Container Apps Contributor)
  - Configures environment variables for Azure OpenAI access
  - **Authentication**: Conditionally enables AAD authentication based on `aiFoundryProjectAppId` parameter

### 3. Main Infrastructure Updates

#### `infra/main.bicep`
- Added `enableCoboAgent` parameter (defaults to `true`)
- Added `aiFoundryProjectAppId` parameter (used for AAD authentication configuration)
- Pass `enableCoboAgent`, `aiFoundryProjectAppId`, `openaiEndpoint`, and `openaiDeploymentName` to resources module
- Auto-enables Azure Container Registry when COBO agent is enabled:
  ```bicep
  var enableHostedAgentsComputed = enableHostedAgents || enableCoboAgent
  ```
- Added outputs:
  - `AZURE_CONTAINER_ENVIRONMENT_NAME`
  - `AZURE_CONTAINER_REGISTRY_NAME`
  - `COBO_AGENT_NAME`
  - `COBO_AGENT_URI`
  - `COBO_AGENT_IDENTITY_PRINCIPAL_ID`
  - `AZURE_OPENAI_ENDPOINT`
  - `AZURE_OPENAI_DEPLOYMENT_NAME`
  - `AI_FOUNDRY_PROJECT_PRINCIPAL_ID` - For AAD authentication setup
  - `AI_FOUNDRY_PROJECT_TENANT_ID` - For AAD authentication setup

#### `infra/resources.bicep`
- Added parameters:
  - `enableCoboAgent` (defaults to `true`)
  - `aiFoundryProjectAppId` (for authentication)
  - `openaiEndpoint`
  - `openaiDeploymentName`
- Added container apps environment module
- Added COBO agent module deployment with authentication parameter
- Added outputs for COBO agent resources

#### `infra/main.parameters.json`
- Added `enableCoboAgent` parameter with default value `${ENABLE_CONTAINER_AGENT=true}`
- Added `aiFoundryProjectAppId` parameter (default empty, populated by postprovision hook)

### 4. Deployment Hooks

#### `scripts/postprovision.ps1` and `scripts/postprovision.sh`
- **Purpose**: Two-stage deployment pattern to configure AAD authentication
- **Process**:
  1. Checks if `AI_FOUNDRY_PROJECT_APP_ID` is already set (prevents infinite loop)
  2. Retrieves AI Foundry Project's system-assigned managed identity Principal ID
  3. Queries Azure AD to get the Application ID (Client ID) from the Service Principal
  4. Sets `AI_FOUNDRY_PROJECT_APP_ID` in azd environment
  5. Re-runs `azd provision --no-prompt` to update Container App with authentication

#### `scripts/postdeploy.ps1` and `scripts/postdeploy.sh`
- **Purpose**: Post-deployment configuration and validation
- **Process**:
  1. Assigns "Azure AI User" role to Container App identity on AI Foundry Account
  2. Deactivates hello-world placeholder revision
  3. Verifies AAD authentication configuration
  4. Registers COBO agent with AI Foundry using Agents API
  5. Tests agent with data plane call
  6. Verifies 401 response for unauthenticated requests

### 5. Azure YAML Configuration
- `azure.yaml` configured with:
  - Service: `cobo-agent` pointing to `./src/cobo-agent`
  - Language: Python
  - Host: Container App
  - Docker remote build enabled
  - **Hooks**:
    - `postprovision`: Configures AAD authentication (runs after first provision)
    - `postdeploy`: Assigns roles, registers agent, tests functionality

## Key Features

### Identity and Permissions
1. **COBO Agent Managed Identity**: User-assigned managed identity for the container app
2. **AI Foundry Project Access**: AI Foundry Project's system-assigned identity gets:
   - "Container Apps Contributor" role on the container app (configured in Bicep)
   - Used as AAD authentication client for the Container App
3. **Azure OpenAI Access**: Container app identity gets:
   - "Cognitive Services OpenAI User" role on AI Foundry Account (assigned in resources.bicep)
   - Role ID: `5e0bd9bd-7b93-4f28-af87-19fc36ad61bd`
   - Provides access to Azure OpenAI services
4. **AI Foundry Account Access**: Container app identity gets:
   - "Azure AI User" role on AI Foundry Account (assigned in postdeploy script)
   - Role ID: `53ca6127-db72-4b80-b1b0-d745d6d5456d`
   - Enables agent registration and data plane operations

### Azure Active Directory Authentication
- **Configuration**: AAD authentication with Return401 action for unauthenticated requests
- **Client ID**: Uses AI Foundry Project's Application ID (retrieved from managed identity)
- **Allowed Audiences**: `https://management.azure.com`
- **Two-Stage Deployment**: 
  - First provision: Creates infrastructure without authentication
  - Postprovision hook: Retrieves Application ID and re-provisions with authentication
  - This ensures authentication works on the first `azd up` command

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

### First-Time Deployment
To deploy with COBO agent (default):
```bash
azd up
```

**What happens during deployment:**
1. **First Provision**: Creates all infrastructure (AI Foundry, Container App, etc.)
2. **Postprovision Hook**: Retrieves AI Foundry Project's Application ID and re-provisions to enable authentication
3. **Deploy**: Builds and deploys the COBO agent container
4. **Postdeploy Hook**: Assigns roles, registers agent, and tests functionality

### Deploy Without COBO Agent
```powershell
# PowerShell
$env:ENABLE_CONTAINER_AGENT='false'
azd up
```

```bash
# Bash
export ENABLE_CONTAINER_AGENT='false'
azd up
```

### Re-running Deployment
On subsequent `azd up` runs:
- Postprovision hook detects existing `AI_FOUNDRY_PROJECT_APP_ID` and skips re-provisioning
- Only infrastructure changes and new deployments are applied
- No infinite loop issues

## Differences from Original COBO Template

1. **No External AI Foundry Project**: Uses the AI Foundry project created in this template's `ai-project.bicep`
2. **Integrated with Existing Infrastructure**: Shares ACR and follows azd infrastructure patterns
3. **Simplified Parameters**: No need to provide existing AI Foundry project resource ID or model deployment name
4. **Service Name**: Changed from "api" to "cobo-agent" throughout
5. **Default Enabled**: COBO agent deployment is enabled by default (`ENABLE_CONTAINER_AGENT=true`)
6. **Two-Stage Deployment**: Uses postprovision hook to configure AAD authentication (original uses preprovision)
7. **Single Command Deployment**: Works with first `azd up` - no manual intervention required
8. **Auto-ACR Creation**: Automatically creates ACR when COBO agent is enabled (even if hosted agents are disabled)

## Architecture

```
AI Foundry Project (ai-project.bicep)
    ├── Model Deployment: gpt-4o-mini
    └── System-Assigned Identity (Application ID retrieved in postprovision)
            ├── Has "Container Apps Contributor" role on COBO agent
            └── Used as AAD authentication client ID for Container App

Container Registry (resources.bicep)
    └── Auto-created when COBO agent is enabled

Container Apps Environment (resources.bicep)
    └── COBO Agent Container App
            ├── User-Assigned Managed Identity
            │   ├── Has "Cognitive Services OpenAI User" role on AI Foundry Account
            │   └── Has "Azure AI User" role on AI Foundry Account (assigned in postdeploy)
            ├── AAD Authentication (configured via postprovision hook)
            │   ├── Client ID: AI Foundry Project's Application ID
            │   ├── Allowed Audiences: https://management.azure.com
            │   └── Unauthenticated Action: Return401
            └── Authenticates to Azure OpenAI using managed identity
```

## Deployment Flow

```
azd up
    ↓
[1] First Provision (Bicep)
    - Creates AI Foundry Project with system-assigned identity
    - Creates Container App without authentication
    - Assigns "Container Apps Contributor" role to AI Foundry Project
    ↓
[2] Postprovision Hook
    - Retrieves AI Foundry Project's Principal ID
    - Queries Azure AD for Application ID (Client ID)
    - Sets AI_FOUNDRY_PROJECT_APP_ID in environment
    - Re-runs: azd provision --no-prompt
    ↓
[3] Second Provision (Bicep)
    - Updates Container App with AAD authentication
    - Client ID = AI Foundry Project's Application ID
    ↓
[4] Deploy
    - Builds container image in ACR
    - Deploys to Container App
    ↓
[5] Postdeploy Hook
    - Assigns "Azure AI User" role to Container App identity
    - Deactivates hello-world placeholder revision
    - Registers COBO agent with AI Foundry
    - Tests agent functionality
    - Verifies authentication (expects 401 for unauthenticated requests)
```

## Important Notes

### AAD Authentication Requirement
- The COBO agent requires AAD authentication to work with AI Foundry
- Authentication is configured using the AI Foundry Project's Application ID
- This Application ID can only be retrieved after the managed identity is created (not available in Bicep)
- Therefore, a two-stage deployment is necessary

### Preventing Infinite Loops
- The postprovision hook checks if `AI_FOUNDRY_PROJECT_APP_ID` is already set
- If set, it skips re-provisioning
- This ensures subsequent `azd up` runs don't trigger unnecessary re-provisions

### Role Assignment Timing
- "Container Apps Contributor" role: Assigned in Bicep (immediate)
- "Cognitive Services OpenAI User" role: Assigned in Bicep (immediate)
- "Azure AI User" role: Assigned in postdeploy script (with 30-second RBAC propagation wait)

### ACR Behavior on Linux
- Fixed a bug where ACR wasn't created on Linux when only COBO agent was enabled
- Solution: `var enableHostedAgentsComputed = enableHostedAgents || enableCoboAgent`
- ACR is now automatically created when COBO agent is enabled, regardless of platform

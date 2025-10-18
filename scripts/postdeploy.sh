#!/bin/bash
# postdeploy.sh
# Post-deployment script for AI Foundry integration:
# 1. Registers the agent with AI Foundry using the Agents API
# 2. Tests the agent with a data plane call
# 3. Verifies authentication is enforced (expects 401 for unauthenticated requests)

set -e  # Exit on error

# Helper function to get environment variable
get_env_var() {
    azd env get-values | grep "^$1=" | cut -d'=' -f2 | tr -d '"' | tr -d "'" | tr -d '\r\n'
}

# Helper function to parse JSON from string
parse_json_value() {
    local json_string=$1
    local json_path=$2
    
    if ! command -v python3 &> /dev/null; then
        echo "Error: python3 is required but not available. Please install python3." >&2
        exit 1
    fi
    
    echo "$json_string" | python3 -c "import sys, json; data=json.load(sys.stdin); print($json_path)"
}

# Get required values from azd environment
CONTAINER_APP_PRINCIPAL_ID=$(get_env_var "SERVICE_API_IDENTITY_PRINCIPAL_ID")
AI_FOUNDRY_RESOURCE_ID=$(get_env_var "AI_FOUNDRY_RESOURCE_ID")
AI_FOUNDRY_PROJECT_RESOURCE_ID=$(get_env_var "AI_FOUNDRY_PROJECT_RESOURCE_ID")
PROJECT_PRINCIPAL_ID=$(get_env_var "AI_FOUNDRY_PROJECT_PRINCIPAL_ID")
PROJECT_TENANT_ID=$(get_env_var "AI_FOUNDRY_PROJECT_TENANT_ID")
RESOURCE_ID=$(get_env_var "SERVICE_API_RESOURCE_ID")
AGENT_NAME=$(get_env_var "AGENT_NAME")

# Validate required variables
[ -z "$AI_FOUNDRY_RESOURCE_ID" ] && { echo "Error: AI_FOUNDRY_RESOURCE_ID not set" >&2; exit 1; }
[ -z "$AI_FOUNDRY_PROJECT_RESOURCE_ID" ] && { echo "Error: AI_FOUNDRY_PROJECT_RESOURCE_ID not set" >&2; exit 1; }
[ -z "$CONTAINER_APP_PRINCIPAL_ID" ] && { echo "Error: SERVICE_API_IDENTITY_PRINCIPAL_ID not set" >&2; exit 1; }
[ -z "$PROJECT_PRINCIPAL_ID" ] && { echo "Error: AI_FOUNDRY_PROJECT_PRINCIPAL_ID not set" >&2; exit 1; }
[ -z "$PROJECT_TENANT_ID" ] && { echo "Error: AI_FOUNDRY_PROJECT_TENANT_ID not set" >&2; exit 1; }
[ -z "$RESOURCE_ID" ] && { echo "Error: SERVICE_API_RESOURCE_ID not set" >&2; exit 1; }
[ -z "$AGENT_NAME" ] && { echo "Error: AGENT_NAME not set" >&2; exit 1; }

# Extract project information from resource IDs
IFS='/' read -ra PARTS <<< "$AI_FOUNDRY_PROJECT_RESOURCE_ID"
PROJECT_SUBSCRIPTION_ID="${PARTS[2]}"
PROJECT_RESOURCE_GROUP="${PARTS[4]}"
PROJECT_AI_FOUNDRY_NAME="${PARTS[8]}"
PROJECT_NAME="${PARTS[10]}"

# Set subscription
echo "Setting subscription: $PROJECT_SUBSCRIPTION_ID"
az account set --subscription "$PROJECT_SUBSCRIPTION_ID"

# Get AI Foundry region
AI_FOUNDRY_REGION=$(az cognitiveservices account show \
    --name "$PROJECT_AI_FOUNDRY_NAME" \
    --resource-group "$PROJECT_RESOURCE_GROUP" \
    --query location -o tsv | tr -d '\r\n')

echo "AI Foundry region: $AI_FOUNDRY_REGION"
echo "Project: $PROJECT_NAME"
echo "Agent: $AGENT_NAME"

# NOTE: Azure AI User role assignment is now handled in Bicep during deployment
# See infra/cobo-agent.bicep for the role assignment configuration

# Configure Container App Authentication
echo ""
echo "======================================"
echo "Configuring Container App Authentication"
echo "======================================"

echo "Retrieving Application ID (Client ID) for AI Foundry Project..."
echo "Principal ID (Object ID): $PROJECT_PRINCIPAL_ID"

# Query Azure AD to get the Application ID from the Service Principal
PROJECT_CLIENT_ID=$(az ad sp show --id "$PROJECT_PRINCIPAL_ID" --query appId -o tsv 2>/dev/null | tr -d '\r\n')

if [ -z "$PROJECT_CLIENT_ID" ]; then
    echo "Error: Failed to retrieve Application ID from Azure AD for Principal ID: $PROJECT_PRINCIPAL_ID" >&2
    exit 1
fi

echo "✓ Retrieved Application ID (Client ID): $PROJECT_CLIENT_ID"

echo ""
echo "Configuring authentication for Container App..."
echo "Container App Resource ID: $RESOURCE_ID"

# Build auth configuration JSON
AUTH_CONFIG=$(cat <<EOF
{
  "properties": {
    "platform": {
      "enabled": true
    },
    "globalValidation": {
      "unauthenticatedClientAction": "Return401"
    },
    "identityProviders": {
      "azureActiveDirectory": {
        "enabled": true,
        "registration": {
          "clientId": "$PROJECT_CLIENT_ID",
          "openIdIssuer": "https://sts.windows.net/$PROJECT_TENANT_ID/"
        },
        "validation": {
          "allowedAudiences": [
            "https://management.azure.com",
            "api://$PROJECT_CLIENT_ID",
            "https://ai.azure.com",
            "https://containeragents.ai.azure.com"
          ],
          "defaultAuthorizationPolicy": {
            "allowedApplications": ["$PROJECT_CLIENT_ID"]
          }
        }
      }
    }
  }
}
EOF
)

# Configure authentication using Azure REST API
AUTH_RESULT=$(az rest --method PUT \
    --uri "https://management.azure.com$RESOURCE_ID/authConfigs/current?api-version=2024-03-01" \
    --body "$AUTH_CONFIG" 2>&1)

if [ $? -ne 0 ]; then
    echo "Error: Failed to configure Container App authentication. Error: $AUTH_RESULT" >&2
    exit 1
fi

echo "✓ Container App authentication configured successfully"

# Verify authentication configuration
echo ""
echo "Verifying authentication configuration..."
AUTH_CONFIG_JSON=$(az rest --method GET \
    --uri "https://management.azure.com$RESOURCE_ID/authConfigs/current?api-version=2024-03-01" 2>/dev/null)

if [ -n "$AUTH_CONFIG_JSON" ]; then
    # Use python3 to parse JSON properly
    PLATFORM_ENABLED=$(echo "$AUTH_CONFIG_JSON" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('properties', {}).get('platform', {}).get('enabled', 'unknown'))" 2>/dev/null || echo "unknown")
    UNAUTH_ACTION=$(echo "$AUTH_CONFIG_JSON" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('properties', {}).get('globalValidation', {}).get('unauthenticatedClientAction', 'unknown'))" 2>/dev/null || echo "unknown")
    AAD_ENABLED=$(echo "$AUTH_CONFIG_JSON" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('properties', {}).get('identityProviders', {}).get('azureActiveDirectory', {}).get('enabled', 'unknown'))" 2>/dev/null || echo "unknown")
    CLIENT_ID=$(echo "$AUTH_CONFIG_JSON" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('properties', {}).get('identityProviders', {}).get('azureActiveDirectory', {}).get('registration', {}).get('clientId', 'unknown'))" 2>/dev/null || echo "unknown")
    ISSUER=$(echo "$AUTH_CONFIG_JSON" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('properties', {}).get('identityProviders', {}).get('azureActiveDirectory', {}).get('registration', {}).get('openIdIssuer', 'unknown'))" 2>/dev/null || echo "unknown")
    
    echo "✓ Authentication Platform Enabled: $PLATFORM_ENABLED"
    echo "✓ Unauthenticated Client Action: $UNAUTH_ACTION"
    echo "✓ Azure AD Enabled: $AAD_ENABLED"
    echo "✓ Client ID: $CLIENT_ID"
    echo "✓ Issuer: $ISSUER"
    echo "✓ Allowed Audiences: https://management.azure.com, api://$PROJECT_CLIENT_ID, https://ai.azure.com, https://containeragents.ai.azure.com"
fi

echo ""
echo "======================================"
echo "Container App Authentication Setup Complete"
echo "======================================"

# Restart the latest Container App revision to apply authentication changes
echo ""
echo "Restarting Container App to apply authentication changes..."

# Extract subscription, resource group and app name from resource ID
# Format: /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.App/containerApps/{name}
SUBSCRIPTION=$(echo "$RESOURCE_ID" | sed -n 's|.*/subscriptions/\([^/]*\)/.*|\1|p')
RESOURCE_GROUP=$(echo "$RESOURCE_ID" | sed -n 's|.*/resourceGroups/\([^/]*\)/.*|\1|p')
APP_NAME=$(echo "$RESOURCE_ID" | sed -n 's|.*/containerApps/\([^/]*\)$|\1|p')

if [ -z "$SUBSCRIPTION" ] || [ -z "$RESOURCE_GROUP" ] || [ -z "$APP_NAME" ]; then
    echo "Warning: Could not parse Container App resource ID for restart" >&2
else
    # Get the latest active revision name
    LATEST_REVISION=$(az containerapp revision list \
        --name "$APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --subscription "$SUBSCRIPTION" \
        --query "[?properties.active==\`true\`] | [0].name" \
        -o tsv 2>/dev/null | tr -d '\r\n')
    
    if [ -n "$LATEST_REVISION" ]; then
        echo "Latest active revision: $LATEST_REVISION"
        
        # Restart the revision
        az containerapp revision restart \
            --name "$APP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --subscription "$SUBSCRIPTION" \
            --revision "$LATEST_REVISION" >/dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            echo "✓ Container App revision restarted successfully"
        else
            echo "Warning: Failed to restart Container App revision, but continuing..." >&2
        fi
    else
        echo "Warning: Could not find active revision to restart" >&2
    fi
fi

# Wait for authentication settings to propagate and restart to complete
echo ""
echo "ℹ️  Waiting 60 seconds for authentication settings to propagate and restart to complete..."
sleep 60
echo "✓ Wait complete. Proceeding with agent registration."

    # Deactivate hello-world revision first
    echo ""
    echo "======================================"
    echo "Deactivating Hello-World Revision"
    echo "======================================"
    echo "ℹ️  Azure Container Apps requires an image during provision, but with remote Docker"
    echo "   build, the app image doesn't exist yet. A hello-world placeholder image is used"
    echo "   during 'azd provision', then replaced with your app image during 'azd deploy'."
    echo "   Now that your app is deployed, we'll deactivate the placeholder revision."
    echo ""
    
    # Extract subscription, resource group and app name from resource ID
    # Format: /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.App/containerApps/{name}
    SUBSCRIPTION=$(echo "$RESOURCE_ID" | sed -n 's|.*/subscriptions/\([^/]*\)/.*|\1|p')
    RESOURCE_GROUP=$(echo "$RESOURCE_ID" | sed -n 's|.*/resourceGroups/\([^/]*\)/.*|\1|p')
    APP_NAME=$(echo "$RESOURCE_ID" | sed -n 's|.*/containerApps/\([^/]*\)$|\1|p')
    
    if [ -z "$SUBSCRIPTION" ] || [ -z "$RESOURCE_GROUP" ] || [ -z "$APP_NAME" ]; then
        echo "Warning: Could not parse subscription, resource group or app name from resource ID" >&2
    else
        # Get all revisions with their images
        REVISIONS_JSON=$(az containerapp revision list \
            --name "$APP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --subscription "$SUBSCRIPTION" \
            --query "[].{name:name, image:properties.template.containers[0].image, active:properties.active}" \
            -o json | tr -d '\r\n')
        
        if [ -z "$REVISIONS_JSON" ]; then
            echo "Warning: Could not retrieve revisions" >&2
        else
            # Find hello-world revision by checking BOTH:
            # 1. Image contains 'containerapps-helloworld'
            # 2. Revision name does NOT contain '--azd-' (azd-generated revisions have this pattern)
            HELLO_WORLD_REVISION=$(parse_json_value "$REVISIONS_JSON" "[r['name'] for r in data if 'containerapps-helloworld' in r.get('image', '') and '--azd-' not in r['name']]")
            HELLO_WORLD_REVISION=$(echo "$HELLO_WORLD_REVISION" | tr -d "[]'\"" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            
            if [ -z "$HELLO_WORLD_REVISION" ]; then
                echo "No hello-world revision found (already removed or using custom image)"
            else
                echo "Found hello-world revision: $HELLO_WORLD_REVISION"
                
                # Verify the image to be extra safe
                IMAGE_CHECK=$(parse_json_value "$REVISIONS_JSON" "[r['image'] for r in data if r['name'] == '$HELLO_WORLD_REVISION'][0]")
                echo "Image: $IMAGE_CHECK"
                
                # Double-check before deactivating
                if [[ "$IMAGE_CHECK" != *"containerapps-helloworld"* ]]; then
                    echo "Warning: Revision does not have hello-world image, skipping for safety" >&2
                elif [[ "$HELLO_WORLD_REVISION" == *"--azd-"* ]]; then
                    echo "Warning: Revision name contains '--azd-' pattern, skipping for safety" >&2
                else
                    # Check if it's already inactive
                    IS_ACTIVE=$(parse_json_value "$REVISIONS_JSON" "[r['active'] for r in data if r['name'] == '$HELLO_WORLD_REVISION'][0]")
                    
                    if [ "$IS_ACTIVE" = "False" ] || [ "$IS_ACTIVE" = "false" ]; then
                        echo "Revision is already inactive"
                    else
                        echo "Deactivating revision..."
                        az containerapp revision deactivate \
                            --name "$APP_NAME" \
                            --resource-group "$RESOURCE_GROUP" \
                            --subscription "$SUBSCRIPTION" \
                            --revision "$HELLO_WORLD_REVISION" 2>&1
                        
                        if [ $? -eq 0 ]; then
                            echo "✓ Hello-world revision deactivated successfully"
                        else
                            echo "Warning: Failed to deactivate hello-world revision" >&2
                        fi
                    fi
                fi
            fi
        fi
    fi
    
    # Get the Container App endpoint (FQDN) for testing
    echo "Retrieving Container App endpoint..."
    CONTAINER_APP_FQDN=$(az resource show --ids "$RESOURCE_ID" --query properties.configuration.ingress.fqdn -o tsv | tr -d '\r\n')
    
    if [ -n "$CONTAINER_APP_FQDN" ]; then
        ACA_ENDPOINT="https://$CONTAINER_APP_FQDN"
        echo "Container App endpoint: $ACA_ENDPOINT"
    else
        echo "Warning: Failed to retrieve Container App endpoint." >&2
        ACA_ENDPOINT=""
    fi
    
    # Get AI Foundry Project endpoint from resource properties
    echo "Retrieving AI Foundry Project API endpoint..."
    AI_FOUNDRY_PROJECT_ENDPOINT=$(az resource show --ids "$AI_FOUNDRY_PROJECT_RESOURCE_ID" --query "properties.endpoints.\"AI Foundry API\"" -o tsv | tr -d '\r\n')
    
    if [ -n "$AI_FOUNDRY_PROJECT_ENDPOINT" ]; then
        echo "AI Foundry Project API endpoint: $AI_FOUNDRY_PROJECT_ENDPOINT"
    else
        echo "Warning: Failed to retrieve AI Foundry Project API endpoint." >&2
    fi
    
    # Acquire AAD token for audience https://ai.azure.com
    TOKEN=$(az account get-access-token --resource "https://ai.azure.com" --query accessToken -o tsv)
    
    if [ -n "$TOKEN" ]; then
    
    # Get latest revision and build ingress suffix
    LATEST_REVISION=$(az containerapp show --ids "$RESOURCE_ID" \
        --query properties.latestRevisionName -o tsv | tr -d '\r\n')
    INGRESS_SUFFIX="--${LATEST_REVISION##*--}"
    [ "$INGRESS_SUFFIX" = "--$LATEST_REVISION" ] && INGRESS_SUFFIX="--$LATEST_REVISION"
    
    # Construct agent registration URI (always use regional ARM endpoint)
    WORKSPACE_NAME="$PROJECT_AI_FOUNDRY_NAME@$PROJECT_NAME@AML"
    API_PATH="/agents/v2.0/subscriptions/$PROJECT_SUBSCRIPTION_ID/resourceGroups/$PROJECT_RESOURCE_GROUP/providers/Microsoft.MachineLearningServices/workspaces/$WORKSPACE_NAME/agents/$AGENT_NAME/versions?api-version=2025-05-15-preview"
    
    # Always use regional ARM API endpoint based on AI Foundry location
    URI="https://$AI_FOUNDRY_REGION.api.azureml.ms$API_PATH"
    echo "Using regional ARM API endpoint for region: $AI_FOUNDRY_REGION"

    
    # Build JSON payload
    PAYLOAD=$(cat <<EOF
{
  "description": "Test agent version description",
  "definition": {
    "kind": "container_app",
    "container_protocol_versions": [{"protocol": "responses", "version": "v1"}],
    "container_app_resource_id": "$RESOURCE_ID",
    "ingress_subdomain_suffix": "$INGRESS_SUFFIX"
  }
}
EOF
)
    
    # Register agent with retry logic
    echo ""
    echo "======================================"
    echo "Registering Agent Version"
    echo "======================================"
    echo "POST URL: $URI"
    echo "Request Body:"
    echo "$PAYLOAD"
    
    MAX_RETRIES=10
    RETRY_DELAY=60
    AGENT_VERSION=""
    
    for ATTEMPT in $(seq 0 $((MAX_RETRIES - 1))); do
        [ $ATTEMPT -gt 0 ] && echo "Retry attempt $ATTEMPT of $((MAX_RETRIES - 1))..."
        
        HTTP_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$URI" \
            -H "accept: application/json" \
            -H "authorization: Bearer $TOKEN" \
            -H "content-type: application/json" \
            -d "$PAYLOAD" 2>&1)
        
        HTTP_BODY=$(echo "$HTTP_RESPONSE" | sed '$d')
        HTTP_STATUS=$(echo "$HTTP_RESPONSE" | tail -n1)
        
        echo "Response Status: $HTTP_STATUS"
        echo "Response Body:"
        echo "$HTTP_BODY"
        echo ""
        
        if [ "$HTTP_STATUS" = "200" ] || [ "$HTTP_STATUS" = "201" ]; then
            echo "✓ Agent registered successfully"
            
            # Extract version using python3
            AGENT_VERSION=$(parse_json_value "$HTTP_BODY" "data.get('version', '')" | tr -d '\r\n ')
            echo "Agent version: $AGENT_VERSION"
            break
        elif [ "$HTTP_STATUS" = "500" ] && [ $ATTEMPT -lt $((MAX_RETRIES - 1)) ]; then
            echo "Warning: Registration failed with 500 error (permission propagation delay)"
            echo "Waiting $RETRY_DELAY seconds before retry..."
            sleep $RETRY_DELAY
        else
            echo "Error: Registration failed" >&2
            [ "$HTTP_STATUS" != "500" ] && break
        fi
    done
    
    # Test authentication and agent
    if [ -n "$AGENT_VERSION" ]; then
        # Test 1: Unauthenticated access (should return 401)
        echo ""
        echo "======================================"
        echo "Testing Unauthenticated Access"
        echo "======================================"
        
        UNAUTH_URI="$ACA_ENDPOINT/responses"
        UNAUTH_PAYLOAD='{"input": "test"}'
        echo "POST URL: $UNAUTH_URI"
        echo "Request Body: $UNAUTH_PAYLOAD"
        
        UNAUTH_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$UNAUTH_URI" \
            -H "content-type: application/json" \
            -d "$UNAUTH_PAYLOAD" 2>&1)
        
        UNAUTH_BODY=$(echo "$UNAUTH_RESPONSE" | sed '$d')
        UNAUTH_STATUS=$(echo "$UNAUTH_RESPONSE" | tail -n1)
        
        echo "Response Status: $UNAUTH_STATUS"
        echo "Response Body: $UNAUTH_BODY"
        echo ""
        
        if [ "$UNAUTH_STATUS" = "401" ]; then
            echo "✓ Authentication enforced (got 401)"
        else
            echo "Warning: Expected 401, got $UNAUTH_STATUS" >&2
        fi
        
        # Test 2: Data plane call with authenticated request
        echo ""
        echo "======================================"
        echo "Testing Agent Data Plane"
        echo "======================================"
        
        DATA_PLANE_PAYLOAD=$(cat <<EOF
{
  "agent": {"type": "agent_reference", "name": "$AGENT_NAME", "version": "$AGENT_VERSION"},
  "input": "Tell me a joke.",
  "stream": false
}
EOF
)
        
        DATA_PLANE_URI="$AI_FOUNDRY_PROJECT_ENDPOINT/openai/responses?api-version=2025-05-15-preview"
        echo "POST URL: $DATA_PLANE_URI"
        echo "Request Body:"
        echo "$DATA_PLANE_PAYLOAD"
        
        DATA_PLANE_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$DATA_PLANE_URI" \
            -H "accept: application/json" \
            -H "authorization: Bearer $TOKEN" \
            -H "content-type: application/json" \
            -d "$DATA_PLANE_PAYLOAD" 2>&1)
        
        DATA_PLANE_BODY=$(echo "$DATA_PLANE_RESPONSE" | sed '$d')
        DATA_PLANE_STATUS=$(echo "$DATA_PLANE_RESPONSE" | tail -n1)
        
        echo "Response Status: $DATA_PLANE_STATUS"
        echo "Response Body:"
        echo "$DATA_PLANE_BODY"
        echo ""
        
        if [ "$DATA_PLANE_STATUS" = "200" ] || [ "$DATA_PLANE_STATUS" = "201" ]; then
            echo "✓ Agent responded successfully"
            echo "Agent Output:"
            parse_json_value "$DATA_PLANE_BODY" "data.get('output', '')"
        else
            echo "Warning: Data plane call failed" >&2
        fi
    fi
    
    # Print Azure Portal link
    echo ""
    echo "======================================"
    echo "Azure Portal"
    echo "======================================"
    echo "https://portal.azure.com/#@/resource$RESOURCE_ID"
fi

echo ""
echo "✓ Post-deployment completed successfully"

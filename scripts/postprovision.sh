#!/bin/bash
set -e

echo ""
echo "======================================"
echo "Configuring Container App Authentication"
echo "======================================"

# Helper function to get environment variable from azd
get_env_var() {
    azd env get-values | grep "^$1=" | cut -d'=' -f2 | tr -d '"'
}

# Check if AI Foundry Project App ID is already set
EXISTING_APP_ID=$(get_env_var "AI_FOUNDRY_PROJECT_APP_ID")
if [ -n "$EXISTING_APP_ID" ]; then
    echo "✓ AI Foundry Project Application ID already configured: $EXISTING_APP_ID"
    echo "Skipping postprovision re-run."
    exit 0
fi

# Get AI Foundry Project Principal ID and Tenant ID
PROJECT_PRINCIPAL_ID=$(get_env_var "AI_FOUNDRY_PROJECT_PRINCIPAL_ID")
PROJECT_TENANT_ID=$(get_env_var "AI_FOUNDRY_PROJECT_TENANT_ID")

[ -z "$PROJECT_PRINCIPAL_ID" ] && { echo "Error: AI_FOUNDRY_PROJECT_PRINCIPAL_ID not set" >&2; exit 1; }
[ -z "$PROJECT_TENANT_ID" ] && { echo "Error: AI_FOUNDRY_PROJECT_TENANT_ID not set" >&2; exit 1; }

echo "Retrieving Application ID for Principal ID: $PROJECT_PRINCIPAL_ID"

# Query Azure AD to get the Application ID (Client ID) from the Service Principal
SP_JSON=$(az ad sp show --id "$PROJECT_PRINCIPAL_ID" --query appId -o json 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$SP_JSON" ]; then
    echo "Error: Failed to retrieve Application ID from Azure AD" >&2
    exit 1
fi

PROJECT_CLIENT_ID=$(echo "$SP_JSON" | tr -d '"' | tr -d '\r\n')
echo "✓ Retrieved Application ID: $PROJECT_CLIENT_ID"

# Set the Application ID in the environment
azd env set AI_FOUNDRY_PROJECT_APP_ID "$PROJECT_CLIENT_ID"

echo ""
echo "Re-running provisioning with Application ID..."
echo ""

# Re-run azd provision to update the Container App with authentication
azd provision --no-prompt

if [ $? -ne 0 ]; then
    echo "Error: Failed to re-provision with Application ID" >&2
    exit 1
fi

echo ""
echo "✓ Container App authentication configured successfully"

#!/bin/bash

# Script to create an Azure AI Foundry capability host using the REST API
# This script checks if the capability host exists before attempting to create it

set -e

# Load environment variables from azd
if [ -z "$AZURE_SUBSCRIPTION_ID" ]; then
    echo "Error: AZURE_SUBSCRIPTION_ID not set. Please run 'azd env refresh' first."
    exit 1
fi

if [ -z "$AZURE_RESOURCE_GROUP" ]; then
    echo "Error: AZURE_RESOURCE_GROUP not set. Please run 'azd env refresh' first."
    exit 1
fi

if [ -z "$AZURE_AI_ACCOUNT_NAME" ]; then
    echo "Error: AZURE_AI_ACCOUNT_NAME not set. Please run 'azd env refresh' first."
    exit 1
fi

SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID}"
RESOURCE_GROUP="${AZURE_RESOURCE_GROUP}"
ACCOUNT_NAME="${AZURE_AI_ACCOUNT_NAME}"
CAPABILITY_HOST_NAME="agents"
API_VERSION="2025-10-01-preview"

# Get Azure access token
echo "Getting Azure access token..."
TOKEN_JSON=$(azd auth token --output json --scope https://management.azure.com/.default)
ACCESS_TOKEN=$(echo "$TOKEN_JSON" | jq -r '.token')

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
    echo "Error: Failed to get access token. Please run 'azd auth login' first."
    exit 1
fi

# Check if capability host already exists
echo "Checking if capability host '$CAPABILITY_HOST_NAME' already exists..."
CHECK_URL="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.CognitiveServices/accounts/${ACCOUNT_NAME}/capabilityHosts/${CAPABILITY_HOST_NAME}?api-version=${API_VERSION}"

echo "Debug - Check URL: $CHECK_URL"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X GET \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    "${CHECK_URL}")

if [ "$HTTP_CODE" = "200" ]; then
    echo "✓ Capability host '$CAPABILITY_HOST_NAME' already exists. Skipping creation."
    exit 0
fi

echo "Capability host does not exist. Creating..."

# Construct the REST API URL
URL="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.CognitiveServices/accounts/${ACCOUNT_NAME}/capabilityHosts/${CAPABILITY_HOST_NAME}?api-version=${API_VERSION}"

# Construct the request body
# For hosted agents without BYONET, enablePublicHostingEnvironment is required
REQUEST_BODY=$(cat <<EOF
{
  "properties": {
    "capabilityHostKind": "Agents",
    "enablePublicHostingEnvironment": true
  }
}
EOF
)

echo "Creating capability host '$CAPABILITY_HOST_NAME'..."
echo "URL: $URL"

# Make the REST API call
RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X PUT \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "${REQUEST_BODY}" \
    "${URL}")

# Extract HTTP status code (last line) and response body (everything else)
HTTP_STATUS=$(echo "$RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')

echo "HTTP Status: $HTTP_STATUS"

if [ "$HTTP_STATUS" = "200" ] || [ "$HTTP_STATUS" = "201" ]; then
    echo "✓ Successfully created capability host '$CAPABILITY_HOST_NAME'"
    echo "Response:"
    echo "$RESPONSE_BODY" | jq '.' 2>/dev/null || echo "$RESPONSE_BODY"
    
    # Check provisioning state
    PROVISIONING_STATE=$(echo "$RESPONSE_BODY" | jq -r '.properties.provisioningState' 2>/dev/null)
    if [ "$PROVISIONING_STATE" = "Creating" ] || [ "$PROVISIONING_STATE" = "Updating" ]; then
        echo ""
        echo "⚠ Capability host is being provisioned (state: $PROVISIONING_STATE)"
        echo "This may take a few minutes. Check the Azure portal for status."
    fi
else
    echo "✗ Failed to create capability host"
    echo "Response:"
    echo "$RESPONSE_BODY" | jq '.' 2>/dev/null || echo "$RESPONSE_BODY"
    exit 1
fi

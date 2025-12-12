#!/usr/bin/env pwsh

# Script to create an Azure AI Foundry capability host using the REST API
# This script checks if the capability host exists before attempting to create it

$ErrorActionPreference = "Stop"

# Load environment variables from azd
if (-not $env:AZURE_SUBSCRIPTION_ID) {
    Write-Error "AZURE_SUBSCRIPTION_ID not set. Please run 'azd env refresh' first."
    exit 1
}

if (-not $env:AZURE_RESOURCE_GROUP) {
    Write-Error "AZURE_RESOURCE_GROUP not set. Please run 'azd env refresh' first."
    exit 1
}

if (-not $env:AZURE_AI_ACCOUNT_NAME) {
    Write-Error "AZURE_AI_ACCOUNT_NAME not set. Please run 'azd env refresh' first."
    exit 1
}

$subscriptionId = $env:AZURE_SUBSCRIPTION_ID
$resourceGroup = $env:AZURE_RESOURCE_GROUP
$accountName = $env:AZURE_AI_ACCOUNT_NAME
$capabilityHostName = "agents"
$apiVersion = "2025-10-01-preview"

# Get Azure access token
Write-Host "Getting Azure access token..." -ForegroundColor Cyan
try {
    $tokenResponse = azd auth token --output json --scope https://management.azure.com/.default | ConvertFrom-Json
    $accessToken = $tokenResponse.token
    if (-not $accessToken) {
        throw "Failed to get access token"
    }
}
catch {
    Write-Error "Failed to get access token. Please run 'azd auth login' first."
    exit 1
}

# Check if capability host already exists
Write-Host "Checking if capability host '$capabilityHostName' already exists..." -ForegroundColor Cyan
$checkUrl = "https://management.azure.com/subscriptions/${subscriptionId}/resourceGroups/${resourceGroup}/providers/Microsoft.CognitiveServices/accounts/${accountName}/capabilityHosts/${capabilityHostName}?api-version=${apiVersion}"

Write-Host "Debug - Check URL: $checkUrl" -ForegroundColor Gray

$headers = @{
    "Authorization" = "Bearer $accessToken"
    "Content-Type"  = "application/json"
}

try {
    $existingHost = Invoke-RestMethod -Uri $checkUrl -Method Get -Headers $headers
    if ($existingHost) {
        Write-Host "✓ Capability host '$capabilityHostName' already exists. Skipping creation." -ForegroundColor Green
        exit 0
    }
}
catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    if ($statusCode -eq 404) {
        # 404 means it doesn't exist, continue with creation
        Write-Host "Capability host does not exist. Creating..." -ForegroundColor Cyan
    }
    else {
        Write-Error "Error checking for existing capability host (HTTP $statusCode): $($_.ErrorDetails.Message)"
        exit 1
    }
}

# Construct the REST API URL
$url = "https://management.azure.com/subscriptions/${subscriptionId}/resourceGroups/${resourceGroup}/providers/Microsoft.CognitiveServices/accounts/${accountName}/capabilityHosts/${capabilityHostName}?api-version=${apiVersion}"

# Construct the request body
# For hosted agents without BYONET, enablePublicHostingEnvironment is required
$requestBody = @{
    properties = @{
        capabilityHostKind = "Agents"
        enablePublicHostingEnvironment = $true
    }
} | ConvertTo-Json -Depth 10

Write-Host "Creating capability host '$capabilityHostName'..." -ForegroundColor Cyan
Write-Host "URL: $url" -ForegroundColor Gray

# Make the REST API call
try {
    $response = Invoke-RestMethod -Uri $url -Method Put -Headers $headers -Body $requestBody
    
    Write-Host "✓ Capability host creation request submitted" -ForegroundColor Green
    
    # Poll for provisioning completion
    $provisioningState = $response.properties.provisioningState
    $maxAttempts = 60  # 5 minutes max (5 second intervals)
    $attempt = 0
    
    while ($provisioningState -in @("Creating", "Updating") -and $attempt -lt $maxAttempts) {
        $attempt++
        Write-Host "Waiting for provisioning to complete (state: $provisioningState, attempt $attempt/$maxAttempts)..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
        
        try {
            $statusResponse = Invoke-RestMethod -Uri $url -Method Get -Headers $headers
            $provisioningState = $statusResponse.properties.provisioningState
        }
        catch {
            Write-Warning "Failed to check status: $_"
            break
        }
    }
    
    # Check final state
    if ($provisioningState -eq "Succeeded") {
        Write-Host "✓ Successfully created capability host '$capabilityHostName'" -ForegroundColor Green
        Write-Host "Provisioning state: $provisioningState" -ForegroundColor Green
    }
    elseif ($provisioningState -eq "Failed") {
        Write-Error "Capability host provisioning failed"
        exit 1
    }
    elseif ($provisioningState -eq "Canceled") {
        Write-Error "Capability host provisioning was canceled"
        exit 1
    }
    else {
        Write-Warning "Capability host is still provisioning (state: $provisioningState)"
        Write-Host "Check the Azure portal for status." -ForegroundColor Yellow
    }
}
catch {
    Write-Host "✗ Failed to create capability host" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    if ($_.ErrorDetails.Message) {
        Write-Host "Details: $($_.ErrorDetails.Message)" -ForegroundColor Red
    }
    exit 1
}

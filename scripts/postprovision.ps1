#!/usr/bin/env pwsh

Write-Host ""
Write-Host "======================================"
Write-Host "Configuring Container App Authentication"
Write-Host "======================================"

# Check if AI Foundry Project App ID is already set
$existingAppId = azd env get-values | Select-String '^AI_FOUNDRY_PROJECT_APP_ID='
if ($existingAppId) {
    $appIdValue = $existingAppId.ToString().Split('=')[1].Trim('"')
    if (-not [string]::IsNullOrWhiteSpace($appIdValue)) {
        Write-Host "✓ AI Foundry Project Application ID already configured: $appIdValue"
        Write-Host "Skipping postprovision re-run."
        exit 0
    }
}

# Get AI Foundry Project Principal ID and Tenant ID
$projectPrincipalId = azd env get-values | Select-String '^AI_FOUNDRY_PROJECT_PRINCIPAL_ID='
if (-not $projectPrincipalId) {
    Write-Host "Error: AI_FOUNDRY_PROJECT_PRINCIPAL_ID not set" -ForegroundColor Red
    exit 1
}
$projectPrincipalId = $projectPrincipalId.ToString().Split('=')[1].Trim('"')

$projectTenantId = azd env get-values | Select-String '^AI_FOUNDRY_PROJECT_TENANT_ID='
if (-not $projectTenantId) {
    Write-Host "Error: AI_FOUNDRY_PROJECT_TENANT_ID not set" -ForegroundColor Red
    exit 1
}
$projectTenantId = $projectTenantId.ToString().Split('=')[1].Trim('"')

Write-Host "Retrieving Application ID for Principal ID: $projectPrincipalId"

# Query Azure AD to get the Application ID (Client ID) from the Service Principal
$spJson = az ad sp show --id $projectPrincipalId --query appId -o json 2>$null
if ($LASTEXITCODE -ne 0 -or -not $spJson) {
    Write-Host "Error: Failed to retrieve Application ID from Azure AD" -ForegroundColor Red
    exit 1
}

$projectClientId = ($spJson | ConvertFrom-Json).Trim()
Write-Host "✓ Retrieved Application ID: $projectClientId"

# Set the Application ID in the environment
azd env set AI_FOUNDRY_PROJECT_APP_ID $projectClientId

Write-Host ""
Write-Host "Re-running provisioning with Application ID..."
Write-Host ""

# Re-run azd provision to update the Container App with authentication
azd provision --no-prompt

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to re-provision with Application ID" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "✓ Container App authentication configured successfully"

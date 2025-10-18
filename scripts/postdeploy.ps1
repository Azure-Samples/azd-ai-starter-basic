#!/usr/bin/env pwsh
# postdeploy.ps1
# Post-deployment script for AI Foundry integration:
# 1. Configures Container App authentication with AI Foundry Project Application ID
# 2. Registers the agent with AI Foundry using the Agents API
# 3. Tests the agent with a data plane call
# 4. Verifies authentication is enforced (expects 401 for unauthenticated requests)

Write-Host "======================================"
Write-Host "POSTDEPLOY SCRIPT STARTED"
Write-Host "======================================"

# Get required values from azd environment
$containerAppPrincipalId = (azd env get-values | Select-String -Pattern '^SERVICE_API_IDENTITY_PRINCIPAL_ID=' | ForEach-Object { $_.Line.Split('=')[1].Trim() }) -replace '^"|"$', ''
$aiFoundryResourceId = (azd env get-values | Select-String -Pattern '^AI_FOUNDRY_RESOURCE_ID=' | ForEach-Object { $_.Line.Split('=')[1].Trim() }) -replace '^"|"$', ''
$aiFoundryProjectResourceId = (azd env get-values | Select-String -Pattern '^AI_FOUNDRY_PROJECT_RESOURCE_ID=' | ForEach-Object { $_.Line.Split('=')[1].Trim() }) -replace '^"|"$', ''
$projectPrincipalId = (azd env get-values | Select-String -Pattern '^AI_FOUNDRY_PROJECT_PRINCIPAL_ID=' | ForEach-Object { $_.Line.Split('=')[1].Trim() }) -replace '^"|"$', ''
$projectTenantId = (azd env get-values | Select-String -Pattern '^AI_FOUNDRY_PROJECT_TENANT_ID=' | ForEach-Object { $_.Line.Split('=')[1].Trim() }) -replace '^"|"$', ''
$resourceId = (azd env get-values | Select-String -Pattern '^SERVICE_API_RESOURCE_ID=' | ForEach-Object { $_.Line.Split('=')[1].Trim() }) -replace '^"|"$', ''

if (-not $aiFoundryResourceId) {
    Write-Error "AI_FOUNDRY_RESOURCE_ID must be set in azd environment"
    exit 1
}

if (-not $aiFoundryProjectResourceId) {
    Write-Error "AI_FOUNDRY_PROJECT_RESOURCE_ID must be set in azd environment"
    exit 1
}

if (-not $containerAppPrincipalId) {
    Write-Error "Could not find container app principal ID in azd environment (SERVICE_API_IDENTITY_PRINCIPAL_ID)"
    exit 1
}

if (-not $projectPrincipalId) {
    Write-Error "AI_FOUNDRY_PROJECT_PRINCIPAL_ID must be set in azd environment"
    exit 1
}

if (-not $projectTenantId) {
    Write-Error "AI_FOUNDRY_PROJECT_TENANT_ID must be set in azd environment"
    exit 1
}

if (-not $resourceId) {
    Write-Error "SERVICE_API_RESOURCE_ID must be set in azd environment"
    exit 1
}

# Step 1: Configure Container App Authentication
Write-Host "`n======================================"
Write-Host "Configuring Container App Authentication"
Write-Host "======================================"

Write-Host "Retrieving Application ID (Client ID) for AI Foundry Project..."
Write-Host "Principal ID (Object ID): $projectPrincipalId"

# Query Azure AD to get the Application ID from the Service Principal
$spJson = az ad sp show --id $projectPrincipalId --query appId -o tsv 2>$null

if ($LASTEXITCODE -ne 0 -or -not $spJson) {
    Write-Error "Failed to retrieve Application ID from Azure AD for Principal ID: $projectPrincipalId"
    exit 1
}

$projectClientId = $spJson.Trim()
Write-Host "✓ Retrieved Application ID (Client ID): $projectClientId"

# Configure Container App authentication
Write-Host "`nConfiguring authentication for Container App..."
Write-Host "Container App Resource ID: $resourceId"

# Build auth configuration JSON
$authConfigObj = @{
    properties = @{
        platform = @{
            enabled = $true
        }
        globalValidation = @{
            unauthenticatedClientAction = "Return401"
        }
        identityProviders = @{
            azureActiveDirectory = @{
                enabled = $true
                registration = @{
                    clientId = $projectClientId
                    openIdIssuer = "https://sts.windows.net/$projectTenantId/"
                }
                validation = @{
                    allowedAudiences = @(
                        "https://management.azure.com"
                        "api://$projectClientId"
                        "https://ai.azure.com"
                        "https://containeragents.ai.azure.com"
                    )
                    defaultAuthorizationPolicy = @{
                        allowedApplications = @($projectClientId)
                    }
                }
            }
        }
    }
}

# Convert to JSON and save to temp file to avoid shell escaping issues
$tempFile = [System.IO.Path]::GetTempFileName()
$authConfigObj | ConvertTo-Json -Depth 10 | Out-File -FilePath $tempFile -Encoding UTF8

# Configure authentication using Azure REST API
$authResult = az rest --method PUT `
    --uri "https://management.azure.com$resourceId/authConfigs/current?api-version=2024-03-01" `
    --body "@$tempFile" 2>&1

# Clean up temp file
Remove-Item $tempFile -ErrorAction SilentlyContinue

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to configure Container App authentication. Error: $authResult"
    exit 1
}

Write-Host "✓ Container App authentication configured successfully"

# Verify authentication configuration
Write-Host "`nVerifying authentication configuration..."
try {
    $authConfigJson = az rest --method GET --uri "https://management.azure.com$resourceId/authConfigs/current?api-version=2024-03-01"
    if ($authConfigJson) {
        $authConfig = $authConfigJson | ConvertFrom-Json
        Write-Host "✓ Authentication Platform Enabled: $($authConfig.properties.platform.enabled)"
        Write-Host "✓ Unauthenticated Client Action: $($authConfig.properties.globalValidation.unauthenticatedClientAction)"
        
        if ($authConfig.properties.identityProviders.azureActiveDirectory) {
            $aadConfig = $authConfig.properties.identityProviders.azureActiveDirectory
            Write-Host "✓ Azure AD Enabled: $($aadConfig.enabled)"
            Write-Host "✓ Client ID: $($aadConfig.registration.clientId)"
            Write-Host "✓ Issuer: $($aadConfig.registration.openIdIssuer)"
            Write-Host "✓ Allowed Audiences: $($aadConfig.validation.allowedAudiences -join ', ')"
        }
    }
} catch {
    Write-Warning "Failed to verify authentication configuration: $($_.Exception.Message)"
}

Write-Host "`n======================================"
Write-Host "Container App Authentication Setup Complete"
Write-Host "======================================"

# Wait for authentication settings to propagate
Write-Host "`nℹ️  Waiting 60 seconds for authentication settings to propagate..."
Start-Sleep -Seconds 60
Write-Host "✓ Wait complete. Proceeding with agent registration."

# Extract account name and resource group from resource ID
# Format: /subscriptions/{subscription-id}/resourceGroups/{resource-group}/providers/Microsoft.CognitiveServices/accounts/{account-name}
$resourceIdParts = $aiFoundryResourceId.Split('/')
$aiFoundryResourceGroup = $resourceIdParts[4]
$aiFoundryName = $resourceIdParts[8]

# Extract project information from project resource ID
# Format: /subscriptions/{subscription-id}/resourceGroups/{resource-group}/providers/Microsoft.CognitiveServices/accounts/{account-name}/projects/{project-name}
$projectResourceIdParts = $aiFoundryProjectResourceId.Split('/')
$projectSubscriptionId = $projectResourceIdParts[2]
$projectResourceGroup = $projectResourceIdParts[4] 
$projectAiFoundryName = $projectResourceIdParts[8]
$projectName = $projectResourceIdParts[10]

# Set the Azure CLI to use the correct subscription for AI Foundry operations
Write-Host "Setting Azure CLI subscription to: $projectSubscriptionId"
az account set --subscription $projectSubscriptionId

# Get the region/location of the AI Foundry account
Write-Host "Retrieving AI Foundry account location..."
$aiFoundryAccount = az cognitiveservices account show --name $projectAiFoundryName --resource-group $projectResourceGroup --query location -o tsv
if ($aiFoundryAccount) { $aiFoundryRegion = $aiFoundryAccount.Trim() } else { $aiFoundryRegion = "" }
Write-Host "AI Foundry region: $aiFoundryRegion"

Write-Host "AI Foundry Resource ID: $aiFoundryResourceId"
Write-Host "AI Foundry Project Resource ID: $aiFoundryProjectResourceId"
Write-Host "AI Foundry: $aiFoundryName in resource group: $aiFoundryResourceGroup"
Write-Host "Project: $projectName in AI Foundry: $projectAiFoundryName"
Write-Host "Container App Principal ID: $containerAppPrincipalId"

# Get the container app resource ID for agent registration
$resourceId = (azd env get-values | Select-String -Pattern '^SERVICE_API_RESOURCE_ID=' | ForEach-Object { $_.Line.Split('=')[1].Trim() }) -replace '^"|"$', ''

if ($resourceId) {
    # Deactivate hello-world revision first
    Write-Host "`n======================================"
    Write-Host "Deactivating Hello-World Revision"
    Write-Host "======================================"
    Write-Host "ℹ️  Azure Container Apps requires an image during provision, but with remote Docker"
    Write-Host "   build, the app image doesn't exist yet. A hello-world placeholder image is used"
    Write-Host "   during 'azd provision', then replaced with your app image during 'azd deploy'."
    Write-Host "   Now that your app is deployed, we'll deactivate the placeholder revision.`n"
    
    # Extract subscription, resource group and app name from resource ID
    # Format: /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.App/containerApps/{name}
    if ($resourceId -match '/subscriptions/([^/]+)/resourceGroups/([^/]+)/.*/containerApps/([^/]+)$') {
        $subscription = $matches[1]
        $resourceGroup = $matches[2]
        $appName = $matches[3]
        
        try {
            # Get all revisions with their images
            $revisionsJson = az containerapp revision list --name $appName --resource-group $resourceGroup --subscription $subscription --query "[].{name:name, image:properties.template.containers[0].image, active:properties.active}" -o json
            
            if (-not $revisionsJson) {
                Write-Warning "Could not retrieve revisions"
            } else {
                $revisions = $revisionsJson | ConvertFrom-Json
                
                # Find hello-world revision by checking BOTH:
                # 1. Image contains 'containerapps-helloworld'
                # 2. Revision name does NOT contain '--azd-' (azd-generated revisions have this pattern)
                $helloWorldRevision = $revisions | Where-Object { 
                    $_.image -like "*containerapps-helloworld*" -and $_.name -notlike "*--azd-*"
                } | Select-Object -First 1
                
                if (-not $helloWorldRevision) {
                    Write-Host "No hello-world revision found (already removed or using custom image)"
                } else {
                    Write-Host "Found hello-world revision: $($helloWorldRevision.name)"
                    Write-Host "Image: $($helloWorldRevision.image)"
                    
                    # Double-check before deactivating
                    if ($helloWorldRevision.image -notlike "*containerapps-helloworld*") {
                        Write-Warning "Revision does not have hello-world image, skipping for safety"
                    } elseif ($helloWorldRevision.name -like "*--azd-*") {
                        Write-Warning "Revision name contains '--azd-' pattern, skipping for safety"
                    } else {
                        # Check if it's already inactive
                        if ($helloWorldRevision.active -eq $false) {
                            Write-Host "Revision is already inactive"
                        } else {
                            Write-Host "Deactivating revision..."
                            az containerapp revision deactivate --name $appName --resource-group $resourceGroup --subscription $subscription --revision $helloWorldRevision.name
                            
                            if ($LASTEXITCODE -eq 0) {
                                Write-Host "✓ Hello-world revision deactivated successfully"
                            } else {
                                Write-Warning "Failed to deactivate hello-world revision"
                            }
                        }
                    }
                }
            }
        } catch {
            Write-Warning "Error while deactivating hello-world revision: $($_.Exception.Message)"
        }
    } else {
        Write-Warning "Could not parse subscription, resource group or app name from resource ID"
    }
    
    # Get the Container App endpoint (FQDN) for testing
    Write-Host "Retrieving Container App endpoint..."
    $containerAppJson = az resource show --ids $resourceId --query properties.configuration.ingress.fqdn -o json
    if ($containerAppJson) {
        $containerAppFqdn = ($containerAppJson | ConvertFrom-Json)
        $acaEndpoint = "https://$containerAppFqdn"
        Write-Host "Container App endpoint: $acaEndpoint"
    } else {
        Write-Warning "Failed to retrieve Container App endpoint."
        $acaEndpoint = $null
    }
    
    # Get AI Foundry Project endpoint from resource properties
    Write-Host "Retrieving AI Foundry Project API endpoint..."
    $projectJson = az resource show --ids $aiFoundryProjectResourceId
    $project = $projectJson | ConvertFrom-Json
    $aiFoundryProjectEndpoint = $project.properties.endpoints.'AI Foundry API'
    
    if ($aiFoundryProjectEndpoint) {
        Write-Host "AI Foundry Project API endpoint: $aiFoundryProjectEndpoint"
    } else {
        Write-Warning "Failed to retrieve AI Foundry Project API endpoint."
    }
    
    # Acquire AAD token for audience https://ai.azure.com
    $token = & az account get-access-token --resource "https://ai.azure.com" --query accessToken -o tsv
    if ($token) { $token = $token.Trim() }

    if (-not $token) {
        try {
            $azToken = Get-AzAccessToken -ResourceUrl "https://ai.azure.com"
            $token = $azToken.Token
        } catch {
            Write-Warning "Failed to obtain AAD access token. Skipping localhost API call."
            $token = $null
        }
    }

    if ($token) {
        # Determine the revision name that was just deployed (latest revision)
        $latestRevisionName = ''
        try {
            $latestRevisionName = az containerapp show --ids $resourceId --query properties.latestRevisionName -o tsv
            if ($latestRevisionName) { $latestRevisionName = $latestRevisionName.Trim() }
        } catch {
            Write-Warning "Unable to determine latest revision name: $($_.Exception.Message)"
        }

        # Get agent name from azd environment variables
        $agentName = (azd env get-values | Select-String -Pattern '^AGENT_NAME=' | ForEach-Object { $_.Line.Split('=')[1].Trim() }) -replace '^"|"$', ''
        if (-not $agentName) { 
            Write-Error "AGENT_NAME must be set in azd environment"
            exit 1
        }
        Write-Host "Using agent name from environment: $agentName"

        # Construct API endpoint
        $workspaceName = "$projectAiFoundryName@$projectName@AML"
        $apiPath = "/agents/v2.0/subscriptions/$projectSubscriptionId/resourceGroups/$projectResourceGroup/providers/Microsoft.MachineLearningServices/workspaces/$workspaceName/agents/$agentName/versions?api-version=2025-05-15-preview"
        
        if (-not $aiFoundryRegion) {
            Write-Error "Could not determine AI Foundry region and AI_PROJECT_ENDPOINT is not set"
            exit 1
        }
        $uri = "https://$aiFoundryRegion.api.azureml.ms$apiPath"
        Write-Host "Using regional API endpoint for region: $aiFoundryRegion"

        # Build payload
        $ingressSuffix = ''
        if ($latestRevisionName) {
            # Extract the suffix starting from the last "--", including the dashes.
            $lastDoubleDash = $latestRevisionName.LastIndexOf('--')
            if ($lastDoubleDash -ge 0) {
                $ingressSuffix = $latestRevisionName.Substring($lastDoubleDash)
            } else {
                # Fallback: prefix with '--' when no double-dash separator exists
                $ingressSuffix = "--$latestRevisionName"
            }
        }
        $bodyObject = @{
            description = "Test agent version description"
            definition = @{
                kind = "container_app"
                container_protocol_versions = @(
                    @{
                        protocol = "responses"
                        version = "v1"
                    }
                )
                container_app_resource_id = $resourceId
                ingress_subdomain_suffix = $ingressSuffix
            }
        }
        $payload = $bodyObject | ConvertTo-Json -Depth 10

        # Compute Content-Length (UTF8 bytes)
        $contentBytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
        $contentLength = $contentBytes.Length

        # Prepare headers
        $headers = @{
            "accept-encoding" = "gzip, deflate, br"
            "accept" = "application/json"
            "authorization" = "Bearer $token"
            "content-type" = "application/json"
            "content-length" = $contentLength.ToString()
        }

        # Send request with retry logic for 500 errors
        $maxRetries = 10
        $retryCount = 0
        $retryDelaySeconds = 60
        $response = $null
        $agentVersion = $null
        
        while ($retryCount -lt $maxRetries) {
            try {
                if ($retryCount -gt 0) {
                    Write-Host "`n--- Retry attempt $retryCount of $($maxRetries - 1) ---"
                }
                
                # Print request information
                Write-Host "POST URL: $uri"
                Write-Host "Payload: $payload"
                # Headers are not printed to avoid leaking sensitive information
                
                $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $payload
                Write-Host "POST completed. Response:"
                Write-Host (ConvertTo-Json $response -Depth 5)
                
                # Extract the version from the response for the data plane call
                $agentVersion = $response.version
                Write-Host "`nAgent version created: $agentVersion"
                
                # Success - break out of retry loop
                break
                
            } catch {
                $statusCode = 0
                $errorMessage = $_.Exception.Message
                
                # Try to extract status code
                if ($_.Exception.Response) {
                    $statusCode = [int]$_.Exception.Response.StatusCode
                }
                
                if ($statusCode -eq 500) {
                    $retryCount++
                    
                    if ($retryCount -lt $maxRetries) {
                        Write-Host "`n======================================"
                        Write-Host "Agent Registration Failed with 500 Error"
                        Write-Host "======================================"
                        Write-Warning "POST failed: $errorMessage"
                        
                        if ($_.Exception.Response) {
                            try {
                                if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                                    Write-Host "Response body:"
                                    Write-Host $_.ErrorDetails.Message
                                }
                            } catch {}
                        }
                        
                        Write-Host "`nℹ️  Note: The agent service might need some time to recognize that the AI Foundry Project"
                        Write-Host "   identity has read permission to the Container App. This is expected on first deployment."
                        Write-Host "   We are working on avoiding this delay in future updates."
                        Write-Host "`n⏳ Waiting $retryDelaySeconds seconds before retry attempt $retryCount..."
                        Start-Sleep -Seconds $retryDelaySeconds
                    } else {
                        Write-Host "`n======================================"
                        Write-Host "Agent Registration Failed After All Retries"
                        Write-Host "======================================"
                        Write-Warning "POST failed after $($maxRetries) attempts: $errorMessage"
                        
                        if ($_.Exception.Response) {
                            try {
                                if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                                    Write-Host "Response body:"
                                    Write-Host $_.ErrorDetails.Message
                                } elseif ($_.Exception.Response.StatusCode) {
                                    Write-Host "Response Status: $($_.Exception.Response.StatusCode)"
                                }
                            } catch {}
                        }
                        
                        Write-Host "`nℹ️  The agent service may still need more time for permission propagation."
                        Write-Host "   You can try running the postdeploy script again later: .\scripts\postdeploy.ps1"
                        # Don't exit - continue with other tests if possible
                    }
                } else {
                    # Non-500 error - don't retry
                    Write-Warning "POST failed: $errorMessage"
                    if ($_.Exception.Response) {
                        try {
                            if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                                Write-Host "Response body:"
                                Write-Host $_.ErrorDetails.Message
                            } elseif ($_.Exception.Response.StatusCode) {
                                Write-Host "Response Status: $($_.Exception.Response.StatusCode)"
                            }
                        } catch {}
                    }
                    break
                }
            }
        }

        # Only proceed with tests if agent registration succeeded
        if ($agentVersion) {
            # Test unauthenticated access - should return 401
            if ($acaEndpoint) {
                Write-Host "`n======================================"
                Write-Host "Testing unauthenticated access (expecting 401)..."
                Write-Host "======================================"
                
                $unauthUri = "$acaEndpoint/responses"
                $unauthPayload = '{"input": "test"}'
                
                Write-Host "Unauthenticated Request URL: $unauthUri"
                Write-Host "Unauthenticated Request Payload: $unauthPayload"
                
                try {
                    $unauthResponseCode = 0
                    $unauthError = $null
                    $unauthResponseBody = $null
                    
                    try {
                        # Try using Invoke-WebRequest with error handling
                        $unauthResponse = Invoke-WebRequest -Uri $unauthUri `
                            -Method POST `
                            -ContentType "application/json" `
                            -Body $unauthPayload `
                            -UseBasicParsing `
                            -ErrorAction Stop
                        $unauthResponseCode = $unauthResponse.StatusCode
                        $unauthResponseBody = $unauthResponse.Content
                    } catch {
                        $unauthError = $_
                        # Extract status code from the exception
                        if ($_.Exception.Response) {
                            $unauthResponseCode = [int]$_.Exception.Response.StatusCode
                            # Try to read the response body
                            try {
                                $stream = $_.Exception.Response.GetResponseStream()
                                $reader = New-Object System.IO.StreamReader($stream)
                                $unauthResponseBody = $reader.ReadToEnd()
                                $reader.Close()
                                $stream.Close()
                            } catch {
                                if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                                    $unauthResponseBody = $_.ErrorDetails.Message
                                }
                            }
                        } elseif ($_.Exception.Message -match 'The remote server returned an error: \((\d+)\)') {
                            $unauthResponseCode = [int]$matches[1]
                        } elseif ($_.Exception.Message -match '(\d+)') {
                            # Try to extract any number that looks like a status code
                            $possibleCode = [int]$matches[1]
                            if ($possibleCode -ge 100 -and $possibleCode -lt 600) {
                                $unauthResponseCode = $possibleCode
                            }
                        }
                    }
                    
                    Write-Host "Response Status Code: $unauthResponseCode"
                    if ($unauthResponseBody) {
                        Write-Host "Response Body: $unauthResponseBody"
                    }
                    
                    if ($unauthResponseCode -eq 401) {
                        Write-Host "✓ Authentication verification successful: Unauthenticated request returned 401 Unauthorized"
                    } elseif ($unauthResponseCode -eq 0) {
                        Write-Warning "Could not determine response code for unauthenticated request"
                        if ($unauthError) {
                            Write-Host "Error details: $($unauthError.Exception.Message)"
                        }
                    } else {
                        Write-Warning "Unexpected response code for unauthenticated request: $unauthResponseCode (expected 401)"
                    }
                } catch {
                    Write-Warning "Error testing unauthenticated access: $($_.Exception.Message)"
                }
            } else {
                Write-Warning "Container App endpoint not available. Skipping unauthenticated access test."
            }
            
            # Make a data plane call to test the agent
            Write-Host "`n--- Testing Agent with Data Plane Call ---"
            
            # Use the AI Foundry Project API endpoint
            if ($aiFoundryProjectEndpoint) {
                $dataPlaneUri = "$aiFoundryProjectEndpoint/openai/responses?api-version=2025-05-15-preview"
            } else {
                Write-Warning "AI Foundry Project API endpoint not available. Skipping data plane call."
                $dataPlaneUri = $null
            }
            
            if ($dataPlaneUri) {
                $dataPlaneBody = @{
                    agent = @{
                        type = "agent_reference"
                        name = $agentName
                        version = $agentVersion
                    }
                    input = "Tell me a joke."
                    stream = $false
                }
                $dataPlanePayload = $dataPlaneBody | ConvertTo-Json -Depth 10
                $dataPlaneContentBytes = [System.Text.Encoding]::UTF8.GetBytes($dataPlanePayload)
                $dataPlaneContentLength = $dataPlaneContentBytes.Length
                
                $dataPlaneHeaders = @{
                    "accept-encoding" = "gzip, deflate, br"
                    "accept" = "application/json"
                    "authorization" = "Bearer $token"
                    "content-type" = "application/json"
                    "content-length" = $dataPlaneContentLength.ToString()
                }
                
                try {
                    Write-Host "Data Plane POST URL: $dataPlaneUri"
                    Write-Host "Data Plane Payload: $dataPlanePayload"
                    
                    $dataPlaneResponse = Invoke-RestMethod -Uri $dataPlaneUri -Method Post -Headers $dataPlaneHeaders -Body $dataPlanePayload
                    Write-Host "Data Plane POST completed. Response:"
                    Write-Host (ConvertTo-Json $dataPlaneResponse -Depth 5)
                } catch {
                    Write-Warning "Data Plane POST failed: $($_.Exception.Message)"
                    if ($_.Exception.Response) {
                        try {
                            if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                                Write-Host "Response body:"
                                Write-Host $_.ErrorDetails.Message
                            } elseif ($_.Exception.Response.StatusCode) {
                                Write-Host "Response Status: $($_.Exception.Response.StatusCode)"
                            }
                        } catch {}
                    }
                }
            }
            
        }
    }
    
    # Print Azure Portal link for the Container App
    Write-Host "`n======================================"
    Write-Host "Azure Portal Links"
    Write-Host "======================================"
    $portalUrl = "https://portal.azure.com/#@/resource$resourceId"
    Write-Host "Container App: $portalUrl"
    
} else {
    Write-Warning "Could not find container app ARM resource ID in azd environment (SERVICE_API_RESOURCE_ID). Skipping localhost API call."
}

Write-Host "`nPost-deployment configuration completed successfully."

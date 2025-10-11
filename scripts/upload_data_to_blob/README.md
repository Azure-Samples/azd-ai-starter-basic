# Azure Blob Storage Folder Upload Tool

A Go utility to upload entire folders to Azure Blob Storage with support for subfolders and flexible authentication.

## Features

- Upload entire folder structures to Azure Blob Storage
- Preserve folder hierarchy in blob storage
- Support for uploading to specific subfolders within containers
- Flexible authentication (Azure Identity, Connection String)
- Command line arguments with environment variable fallbacks
- Concurrent uploads for better performance
- Cross-platform support (Windows, Linux, macOS)

## Installation

1. Ensure you have Go installed (version 1.21 or later)
2. Navigate to the script directory:
   ```bash
   cd scripts/upload_data_to_blob
   ```
3. Install dependencies:
   ```bash
   go mod tidy
   ```
4. Build the executable:
   ```bash
   go build -o upload upload.go
   ```

## Usage

### Command Line Arguments

```bash
./upload [options]
```

**Options:**
- `-account`: Azure Storage Account name
- `-container`: Container name (required)
- `-subfolder`: Subfolder in container (optional)
- `-folder`: Local folder to upload (required)
- `-connection`: Azure Storage connection string (optional)
- `-help`: Show help message

### Environment Variables

Instead of command line arguments, you can use environment variables:

- `AZURE_STORAGE_ACCOUNT`: Storage account name
- `AZURE_STORAGE_CONTAINER`: Container name
- `AZURE_STORAGE_SUBFOLDER`: Subfolder in container
- `LOCAL_FOLDER`: Local folder to upload
- `AZURE_STORAGE_CONNECTION_STRING`: Connection string

### Examples

#### Basic Upload
```bash
./upload -account mystorageaccount -container mycontainer -folder ./data
```

#### Upload to Subfolder
```bash
./upload -account mystorageaccount -container mycontainer -subfolder documents -folder ./docs
```

#### Using Environment Variables
```bash
export AZURE_STORAGE_ACCOUNT=mystorageaccount
export AZURE_STORAGE_CONTAINER=mycontainer
export LOCAL_FOLDER=./data
./upload
```

#### Using Connection String
```bash
./upload -connection "DefaultEndpointsProtocol=https;AccountName=...;AccountKey=...;EndpointSuffix=core.windows.net" -container mycontainer -folder ./data
```

#### Windows Examples
```powershell
# PowerShell
$env:AZURE_STORAGE_ACCOUNT="mystorageaccount"
$env:AZURE_STORAGE_CONTAINER="mycontainer"
$env:LOCAL_FOLDER="./data"
./upload.exe

# Command Prompt
set AZURE_STORAGE_ACCOUNT=mystorageaccount
set AZURE_STORAGE_CONTAINER=mycontainer
set LOCAL_FOLDER=./data
upload.exe
```

## Authentication

The tool uses Azure's DefaultAzureCredential by default, which tries authentication methods in this order:

1. **Environment Variables**: `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_TENANT_ID`
2. **Managed Identity**: For Azure VMs, App Service, etc.
3. **Azure CLI**: If you're logged in via `az login`
4. **Azure PowerShell**: If you're logged in via `Connect-AzAccount`
5. **Interactive Browser**: Opens browser for authentication

Alternatively, you can use a **Connection String** with the `-connection` parameter or `AZURE_STORAGE_CONNECTION_STRING` environment variable.

### Setting up Azure CLI Authentication
```bash
az login
az account set --subscription "your-subscription-id"
```

### Setting up Service Principal (for CI/CD)
```bash
export AZURE_CLIENT_ID="your-client-id"
export AZURE_CLIENT_SECRET="your-client-secret"
export AZURE_TENANT_ID="your-tenant-id"
```

## Integration with AI Foundry

This tool is particularly useful for uploading data to Azure Blob Storage for AI Foundry projects:

```bash
# Upload training data
./upload -account $AZURE_STORAGE_ACCOUNT_NAME -container knowledge -subfolder training-data -folder ./training_data

# Upload documents for RAG
./upload -account $AZURE_STORAGE_ACCOUNT_NAME -container knowledge -subfolder documents -folder ./documents
```

## Error Handling

The tool provides detailed error messages for common issues:
- Missing required parameters
- Authentication failures
- File access problems
- Network connectivity issues
- Azure service errors

## Performance

- Uses concurrent uploads (16 workers by default)
- Uploads files in 1MB blocks for optimal performance
- Preserves folder structure in blob names
- Handles large files efficiently

## Troubleshooting

### Common Issues

1. **Authentication Error**: Ensure you're logged in to Azure CLI or have proper environment variables set
2. **Container Not Found**: The tool will attempt to create the container if it doesn't exist
3. **Permission Denied**: Ensure your account has Storage Blob Data Contributor role
4. **File Not Found**: Check that the local folder path is correct and accessible

### Debug Mode

For verbose output, you can modify the source code to enable debug logging or run with:
```bash
AZURE_SDK_GO_LOGGING=all ./upload [options]
```
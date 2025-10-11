package main

import (
	"context"
	"flag"
	"fmt"
	"io/fs"
	"log"
	"os"
	"path/filepath"
	"strings"

	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob"
)

type Config struct {
	StorageAccount string
	ContainerName  string
	SubFolder      string
	LocalFolder    string
	ConnectionString string
}

func main() {
	// Define command line flags
	var (
		storageAccount   = flag.String("account", "", "Azure Storage Account name")
		containerName    = flag.String("container", "", "Container name")
		subFolder        = flag.String("subfolder", "", "Subfolder in container (optional)")
		localFolder      = flag.String("folder", "", "Local folder to upload")
		connectionString = flag.String("connection", "", "Azure Storage connection string (optional)")
		help             = flag.Bool("help", false, "Show help")
	)
	flag.Parse()

	if *help {
		printUsage()
		return
	}

	// Load configuration from args or environment variables
	config := loadConfig(*storageAccount, *containerName, *subFolder, *localFolder, *connectionString)

	// Validate required parameters
	if err := validateConfig(config); err != nil {
		log.Fatalf("Configuration error: %v", err)
	}

	// Upload folder
	if err := uploadFolder(config); err != nil {
		log.Fatalf("Upload failed: %v", err)
	}

	fmt.Printf("Successfully uploaded folder '%s' to container '%s'\n", config.LocalFolder, config.ContainerName)
}

func loadConfig(account, container, subFolder, folder, connectionString string) Config {
	config := Config{
		StorageAccount:   getValueOrEnv(account, "AZURE_STORAGE_ACCOUNT"),
		ContainerName:    getValueOrEnv(container, "AZURE_STORAGE_CONTAINER"),
		SubFolder:        getValueOrEnv(subFolder, "AZURE_STORAGE_SUBFOLDER"),
		LocalFolder:      getValueOrEnv(folder, "LOCAL_FOLDER"),
		ConnectionString: getValueOrEnv(connectionString, "AZURE_STORAGE_CONNECTION_STRING"),
	}
	return config
}

func getValueOrEnv(value, envVar string) string {
	if value != "" {
		return value
	}
	return os.Getenv(envVar)
}

func validateConfig(config Config) error {
	if config.LocalFolder == "" {
		return fmt.Errorf("local folder is required (use -folder or LOCAL_FOLDER env var)")
	}
	if config.ContainerName == "" {
		return fmt.Errorf("container name is required (use -container or AZURE_STORAGE_CONTAINER env var)")
	}
	if config.StorageAccount == "" && config.ConnectionString == "" {
		return fmt.Errorf("either storage account name (use -account or AZURE_STORAGE_ACCOUNT env var) or connection string is required")
	}

	// Check if local folder exists
	if _, err := os.Stat(config.LocalFolder); os.IsNotExist(err) {
		return fmt.Errorf("local folder '%s' does not exist", config.LocalFolder)
	}

	return nil
}

func uploadFolder(config Config) error {
	ctx := context.Background()

	// Create blob client
	blobClient, err := createBlobClient(config)
	if err != nil {
		return fmt.Errorf("failed to create blob client: %w", err)
	}

	// Create container if it doesn't exist
	_, err = blobClient.CreateContainer(ctx, config.ContainerName, nil)
	if err != nil {
		// Container might already exist, which is fine
		fmt.Printf("Container creation result (might already exist): %v\n", err)
	}

	// Walk through the local folder and upload files
	return filepath.WalkDir(config.LocalFolder, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}

		// Skip directories
		if d.IsDir() {
			return nil
		}

		// Calculate relative path from the base folder
		relPath, err := filepath.Rel(config.LocalFolder, path)
		if err != nil {
			return fmt.Errorf("failed to get relative path for %s: %w", path, err)
		}

		// Convert Windows path separators to forward slashes for blob names
		blobName := strings.ReplaceAll(relPath, "\\", "/")

		// Add subfolder prefix if specified
		if config.SubFolder != "" {
			blobName = strings.TrimSuffix(config.SubFolder, "/") + "/" + blobName
		}

		// Upload file
		if err := uploadFile(ctx, blobClient, config.ContainerName, path, blobName); err != nil {
			return fmt.Errorf("failed to upload %s: %w", path, err)
		}

		fmt.Printf("Uploaded: %s -> %s\n", path, blobName)
		return nil
	})
}

func createBlobClient(config Config) (*azblob.Client, error) {
	if config.ConnectionString != "" {
		// Use connection string
		return azblob.NewClientFromConnectionString(config.ConnectionString, nil)
	} else {
		// Use Azure Identity (DefaultAzureCredential)
		credential, err := azidentity.NewDefaultAzureCredential(nil)
		if err != nil {
			return nil, fmt.Errorf("failed to create credential: %w", err)
		}

		serviceURL := fmt.Sprintf("https://%s.blob.core.windows.net/", config.StorageAccount)
		return azblob.NewClient(serviceURL, credential, nil)
	}
}

func uploadFile(ctx context.Context, client *azblob.Client, containerName, filePath, blobName string) error {
	// Open the file
	file, err := os.Open(filePath)
	if err != nil {
		return fmt.Errorf("failed to open file %s: %w", filePath, err)
	}
	defer file.Close()

	// Upload file directly using the client
	_, err = client.UploadFile(ctx, containerName, blobName, file, &azblob.UploadFileOptions{
		BlockSize:   int64(1024 * 1024), // 1MB blocks
		Concurrency: 16,
	})

	return err
}

func printUsage() {
	fmt.Println("Azure Blob Storage Folder Upload Tool")
	fmt.Println("=====================================")
	fmt.Println()
	fmt.Println("Usage:")
	fmt.Println("  upload [options]")
	fmt.Println()
	fmt.Println("Options:")
	fmt.Println("  -account     Azure Storage Account name")
	fmt.Println("  -container   Container name (required)")
	fmt.Println("  -subfolder   Subfolder in container (optional)")
	fmt.Println("  -folder      Local folder to upload (required)")
	fmt.Println("  -connection  Azure Storage connection string (optional)")
	fmt.Println("  -help        Show this help message")
	fmt.Println()
	fmt.Println("Environment Variables:")
	fmt.Println("  AZURE_STORAGE_ACCOUNT           Storage account name")
	fmt.Println("  AZURE_STORAGE_CONTAINER         Container name")
	fmt.Println("  AZURE_STORAGE_SUBFOLDER         Subfolder in container")
	fmt.Println("  LOCAL_FOLDER                    Local folder to upload")
	fmt.Println("  AZURE_STORAGE_CONNECTION_STRING Connection string")
	fmt.Println()
	fmt.Println("Examples:")
	fmt.Println("  # Upload using command line arguments")
	fmt.Println("  upload -account mystorageaccount -container mycontainer -folder ./data")
	fmt.Println()
	fmt.Println("  # Upload to a subfolder")
	fmt.Println("  upload -account mystorageaccount -container mycontainer -subfolder documents -folder ./docs")
	fmt.Println()
	fmt.Println("  # Upload using environment variables")
	fmt.Println("  set AZURE_STORAGE_ACCOUNT=mystorageaccount")
	fmt.Println("  set AZURE_STORAGE_CONTAINER=mycontainer")
	fmt.Println("  set LOCAL_FOLDER=./data")
	fmt.Println("  upload")
	fmt.Println()
	fmt.Println("  # Upload using connection string")
	fmt.Println("  upload -connection \"DefaultEndpointsProtocol=https;AccountName=...\" -container mycontainer -folder ./data")
	fmt.Println()
	fmt.Println("Authentication:")
	fmt.Println("  The tool uses Azure DefaultAzureCredential by default, which tries:")
	fmt.Println("  1. Environment variables (AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, AZURE_TENANT_ID)")
	fmt.Println("  2. Managed Identity")
	fmt.Println("  3. Azure CLI authentication")
	fmt.Println("  4. Azure PowerShell authentication")
	fmt.Println("  5. Interactive browser authentication")
	fmt.Println()
	fmt.Println("  Alternatively, you can use a connection string with -connection parameter.")
}
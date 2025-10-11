#!/bin/bash
# Build script for the Azure Blob Storage upload tool

echo "Building Azure Blob Storage upload tool..."

# Ensure we're in the right directory
cd "$(dirname "$0")"

# Install dependencies
echo "Installing dependencies..."
go mod tidy

# Build for current platform
echo "Building for current platform..."
go build -o upload upload.go

# Build for different platforms (optional)
echo "Building for multiple platforms..."

# Windows
GOOS=windows GOARCH=amd64 go build -o upload.exe upload.go
echo "Built upload.exe for Windows"

# Linux
GOOS=linux GOARCH=amd64 go build -o upload-linux upload.go
echo "Built upload-linux for Linux"

# macOS
GOOS=darwin GOARCH=amd64 go build -o upload-macos upload.go
echo "Built upload-macos for macOS"

echo "Build complete!"
echo ""
echo "Usage examples:"
echo "  ./upload -help"
echo "  ./upload -account mystorageaccount -container mycontainer -folder ./data"
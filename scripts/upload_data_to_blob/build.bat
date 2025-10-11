@echo off
REM Build script for the Azure Blob Storage upload tool

echo Building Azure Blob Storage upload tool...

REM Ensure we're in the right directory
cd /d "%~dp0"

REM Install dependencies
echo Installing dependencies...
go mod tidy

REM Build for current platform
echo Building for current platform...
go build -o upload.exe upload.go

REM Build for different platforms (optional)
echo Building for multiple platforms...

REM Linux
set GOOS=linux
set GOARCH=amd64
go build -o upload-linux upload.go
echo Built upload-linux for Linux

REM macOS
set GOOS=darwin
set GOARCH=amd64
go build -o upload-macos upload.go
echo Built upload-macos for macOS

REM Reset environment
set GOOS=
set GOARCH=

echo Build complete!
echo.
echo Usage examples:
echo   upload.exe -help
echo   upload.exe -account mystorageaccount -container mycontainer -folder ./data
#!/bin/bash

# Package Lambda function for deployment
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$SCRIPT_DIR/package"
ZIP_FILE="$SCRIPT_DIR/ec2-shutdown-lambda.zip"

echo "Creating Lambda deployment package..."

# Clean previous package
rm -rf "$PACKAGE_DIR"
rm -f "$ZIP_FILE"

# Create package directory
mkdir -p "$PACKAGE_DIR"

# Install dependencies
echo "Installing Python dependencies..."
pip install -r "$SCRIPT_DIR/requirements.txt" -t "$PACKAGE_DIR/"

# Copy source code
echo "Copying source code..."
cp "$SCRIPT_DIR/src/"*.py "$PACKAGE_DIR/"

# Create ZIP file
echo "Creating ZIP package..."
cd "$PACKAGE_DIR"
zip -r "$ZIP_FILE" .

echo "Package created: $ZIP_FILE"
echo "Package size: $(du -h "$ZIP_FILE" | cut -f1)"
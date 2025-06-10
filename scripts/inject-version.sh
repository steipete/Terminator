#!/bin/bash
# Script to inject version from package.json into Swift CLI

set -e

# Get version from package.json
VERSION=$(node -p "require('./package.json').version")

# Get current build time in ISO format
BUILD_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Path to Swift main file
SWIFT_MAIN="cli/Sources/TerminatorCLI/main.swift"

# Create a temporary file
TEMP_FILE="${SWIFT_MAIN}.tmp"

# Check if file has AUTO-GENERATED marker
if grep -q "^// AUTO-GENERATED VERSION - DO NOT EDIT" "${SWIFT_MAIN}"; then
    # File already has version injection
    # Update the version and build time in the existing file
    sed -E "s/let appVersion = \"[^\"]*\"/let appVersion = \"${VERSION}\"/g" "${SWIFT_MAIN}" | \
    sed -E "s/let buildTime = \"[^\"]*\"/let buildTime = \"${BUILD_TIME}\"/g" | \
    sed -E "s/version: \"[^\"]*\"/version: \"${VERSION}\"/g" > "${TEMP_FILE}"
else
    # File doesn't have version injection yet
    # Process the file line by line
    > "${TEMP_FILE}"  # Clear temp file
    
    # Flag to track if we've added the version yet
    VERSION_ADDED=false
    
    while IFS= read -r line; do
        echo "$line" >> "${TEMP_FILE}"
        
        # After the last import or Foundation import, add version
        if [[ ! "$VERSION_ADDED" == true ]] && [[ "$line" =~ ^import\ Foundation ]]; then
            echo "" >> "${TEMP_FILE}"
            echo "// AUTO-GENERATED VERSION - DO NOT EDIT" >> "${TEMP_FILE}"
            echo "let appVersion = \"${VERSION}\"" >> "${TEMP_FILE}"
            echo "let buildTime = \"${BUILD_TIME}\"" >> "${TEMP_FILE}"
            VERSION_ADDED=true
        fi
    done < "${SWIFT_MAIN}"
    
    # Update version references in the file
    sed -i.bak -E "s/version: \"[^\"]*\"/version: \"${VERSION}\"/g" "${TEMP_FILE}"
    rm "${TEMP_FILE}.bak"
fi

# Replace original file
mv "${TEMP_FILE}" "${SWIFT_MAIN}"

echo "✅ Injected version ${VERSION} into Swift CLI"
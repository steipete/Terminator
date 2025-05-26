#!/bin/bash
# Script to inject version from package.json into Swift CLI

set -e

# Get version from package.json
VERSION=$(node -p "require('./package.json').version")

# Path to Swift main file
SWIFT_MAIN="cli/Sources/TerminatorCLI/main.swift"

# Create temporary file with version injection
echo "// AUTO-GENERATED VERSION - DO NOT EDIT" > "${SWIFT_MAIN}.tmp"
echo "let appVersion = \"${VERSION}\"" >> "${SWIFT_MAIN}.tmp"
echo "" >> "${SWIFT_MAIN}.tmp"

# Append the rest of the file, skipping existing version lines
tail -n +7 "${SWIFT_MAIN}" | sed "s/version: \"[^\"]*\"/version: \"${VERSION}\"/g" >> "${SWIFT_MAIN}.tmp"

# Replace original file
mv "${SWIFT_MAIN}.tmp" "${SWIFT_MAIN}"

echo "✅ Injected version ${VERSION} into Swift CLI"
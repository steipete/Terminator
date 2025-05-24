#!/bin/bash
# Exit immediately if a command exits with a non-zero status.
set -e

# Define paths
SWIFT_PROJECT_DIR="$(pwd)" # Assumes script is run from swift-cli directory
NPM_PACKAGE_DIR="../npm-package"
UNIVERSAL_BIN_DIR="${NPM_PACKAGE_DIR}/bin"
UNIVERSAL_BIN_PATH="${UNIVERSAL_BIN_DIR}/terminator"
PRODUCT_NAME="terminator"

# Swift compiler and linker flags for optimization and size reduction
# -Osize: Optimize for code size.
# -wmo: Whole Module Optimization.
# -Xlinker -dead_strip: Remove unused code at the link stage.
# -Xswiftc -static-stdlib: Statically link the Swift standard library (can increase size but removes external dependencies - consider if needed, often not for CLI tools that can rely on system Swift libs)
# For now, let's not use -static-stdlib to keep size smaller if possible. If dynamic linking becomes an issue, we can add it.
# SWIFT_BUILD_FLAGS="-Osize -wmo -Xlinker -dead_strip"
# The `swift build -c release` command already applies optimizations.
# -Osize needs to be passed via -Xswiftc
# -wmo is default for release builds
# -dead_strip is generally good.
RELEASE_SWIFT_FLAGS="-Xswiftc -Osize"
RELEASE_LINKER_FLAGS="-Xlinker -dead_strip"


echo "🚀 Starting universal release build for ${PRODUCT_NAME}..."

# Clean previous release builds if they exist
echo "🧹 Cleaning previous release builds..."
rm -rf .build/arm64-apple-macosx/release
rm -rf .build/x86_64-apple-macosx/release
rm -f "${UNIVERSAL_BIN_PATH}"

# Build for arm64
echo "🏗️ Building for arm64-apple-macosx..."
swift build --arch arm64 -c release ${RELEASE_SWIFT_FLAGS} ${RELEASE_LINKER_FLAGS} --product ${PRODUCT_NAME}
ARM64_BINARY_PATH=".build/arm64-apple-macosx/release/${PRODUCT_NAME}"
if [ ! -f "${ARM64_BINARY_PATH}" ]; then
    echo "❌ ERROR: arm64 binary not found at ${ARM64_BINARY_PATH}"
    exit 1
fi
echo "✅ arm64 build complete."

# Build for x86_64
echo "🏗️ Building for x86_64-apple-macosx..."
swift build --arch x86_64 -c release ${RELEASE_SWIFT_FLAGS} ${RELEASE_LINKER_FLAGS} --product ${PRODUCT_NAME}
X86_64_BINARY_PATH=".build/x86_64-apple-macosx/release/${PRODUCT_NAME}"
if [ ! -f "${X86_64_BINARY_PATH}" ]; then
    echo "❌ ERROR: x86_64 binary not found at ${X86_64_BINARY_PATH}"
    exit 1
fi
echo "✅ x86_64 build complete."

# Create universal binary using lipo
echo "🔗 Creating universal binary..."
mkdir -p "${UNIVERSAL_BIN_DIR}"
lipo -create -output "${UNIVERSAL_BIN_PATH}" "${ARM64_BINARY_PATH}" "${X86_64_BINARY_PATH}"
if [ ! -f "${UNIVERSAL_BIN_PATH}" ]; then
    echo "❌ ERROR: Universal binary not created at ${UNIVERSAL_BIN_PATH}"
    exit 1
fi
echo "✅ Universal binary created at ${UNIVERSAL_BIN_PATH}"

# Strip symbols for further size reduction (optional, but good for release)
echo "✂️ Stripping symbols from universal binary..."
strip "${UNIVERSAL_BIN_PATH}"
echo "✅ Symbols stripped."

# Verify the universal binary
echo "🔎 Verifying universal binary..."
lipo -info "${UNIVERSAL_BIN_PATH}"
file "${UNIVERSAL_BIN_PATH}"

# Set execute permissions on the script itself (though this should be done externally once)
# chmod +x "$0"

echo "🎉 Universal release build for ${PRODUCT_NAME} complete!"
echo "Binary available at: ${UNIVERSAL_BIN_PATH}" 
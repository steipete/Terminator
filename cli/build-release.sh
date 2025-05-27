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
# -wmo: Whole Module Optimization (default in release).
# -Xlinker -dead_strip: Remove unused code at the link stage.
# -Xlinker -S: Strip debug symbols.
# -Xswiftc -gnone: Disable debug info generation.
# -Xswiftc -whole-module-optimization: Ensure WMO is enabled.
RELEASE_SWIFT_FLAGS="-Xswiftc -Osize -Xswiftc -gnone -Xswiftc -whole-module-optimization"
RELEASE_LINKER_FLAGS="-Xlinker -dead_strip -Xlinker -S -Xlinker -x"


echo "🚀 Starting universal release build for ${PRODUCT_NAME}..."

# Inject version from package.json
echo "📝 Injecting version from package.json..."
if [ -f "../scripts/inject-version.sh" ]; then
    (cd .. && ./scripts/inject-version.sh)
else
    echo "⚠️  Version injection script not found, using hardcoded version"
fi

# Run linting checks first
echo "🔍 Running SwiftLint..."
if command -v swiftlint >/dev/null 2>&1; then
    swiftlint --strict --quiet || echo "⚠️  SwiftLint found issues but continuing build..."
else
    echo "⚠️  SwiftLint not installed, skipping linting"
fi

echo "📐 Running SwiftFormat check..."
if command -v swiftformat >/dev/null 2>&1; then
    swiftformat --lint . || echo "⚠️  SwiftFormat found formatting issues but continuing build..."
else
    echo "⚠️  SwiftFormat not installed, skipping format check"
fi

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
# Use more aggressive stripping: -S removes debug symbols, -x removes local symbols
strip -S -x "${UNIVERSAL_BIN_PATH}"
echo "✅ Symbols stripped."

# Verify the universal binary
echo "🔎 Verifying universal binary..."
lipo -info "${UNIVERSAL_BIN_PATH}"
file "${UNIVERSAL_BIN_PATH}"

# Set execute permissions on the script itself (though this should be done externally once)
# chmod +x "$0"

echo "🎉 Universal release build for ${PRODUCT_NAME} complete!"
echo "Binary available at: ${UNIVERSAL_BIN_PATH}" 
#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SWIFT_PROJECT_PATH="$PROJECT_ROOT/cli"
FINAL_BINARY_NAME="terminator"
FINAL_BINARY_PATH="$PROJECT_ROOT/bin/$FINAL_BINARY_NAME"

ARM64_BINARY_TEMP="$PROJECT_ROOT/bin/${FINAL_BINARY_NAME}-arm64"
X86_64_BINARY_TEMP="$PROJECT_ROOT/bin/${FINAL_BINARY_NAME}-x86_64"

# Ensure bin directory exists
mkdir -p "$PROJECT_ROOT/bin"

# Inject version from package.json
echo "📝 Injecting version from package.json..."
if [ -f "$PROJECT_ROOT/scripts/inject-version.sh" ]; then
    (cd "$PROJECT_ROOT" && ./scripts/inject-version.sh)
else
    echo "⚠️  Version injection script not found, using hardcoded version"
fi

# Swift compiler flags for size optimization
# -Osize: Optimize for binary size.
# -wmo: Whole Module Optimization, allows more aggressive optimizations.
# -Xlinker -dead_strip: Remove dead code at the linking stage.
SWIFT_OPTIMIZATION_FLAGS="-Xswiftc -Osize -Xswiftc -wmo -Xlinker -dead_strip -Xlinker -no_uuid"

echo "🧹 Cleaning previous build artifacts..."
(cd "$SWIFT_PROJECT_PATH" && swift package reset) || echo "'swift package reset' encountered an issue, attempting rm -rf..."
rm -rf "$SWIFT_PROJECT_PATH/.build"
rm -f "$ARM64_BINARY_TEMP" "$X86_64_BINARY_TEMP" "$FINAL_BINARY_PATH.tmp"

echo "🏗️ Building for arm64 (Apple Silicon)..."
(cd "$SWIFT_PROJECT_PATH" && swift build --arch arm64 -c release $SWIFT_OPTIMIZATION_FLAGS)
cp "$SWIFT_PROJECT_PATH/.build/arm64-apple-macosx/release/$FINAL_BINARY_NAME" "$ARM64_BINARY_TEMP"
echo "✅ arm64 build complete: $ARM64_BINARY_TEMP"

echo "🏗️ Building for x86_64 (Intel)..."
(cd "$SWIFT_PROJECT_PATH" && swift build --arch x86_64 -c release $SWIFT_OPTIMIZATION_FLAGS)
cp "$SWIFT_PROJECT_PATH/.build/x86_64-apple-macosx/release/$FINAL_BINARY_NAME" "$X86_64_BINARY_TEMP"
echo "✅ x86_64 build complete: $X86_64_BINARY_TEMP"

echo "🔗 Creating universal binary..."
lipo -create -output "$FINAL_BINARY_PATH.tmp" "$ARM64_BINARY_TEMP" "$X86_64_BINARY_TEMP"

echo "🤏 Stripping symbols for further size reduction..."
# -S: Remove debugging symbols
# -x: Remove non-global symbols
strip -Sx "$FINAL_BINARY_PATH.tmp"

# Replace the old binary with the new one
mv "$FINAL_BINARY_PATH.tmp" "$FINAL_BINARY_PATH"

# Code sign with entitlements
# Source signing configuration for consistent TCC permissions
CODESIGN_CONFIG="$SWIFT_PROJECT_PATH/.codesign-config"
if [ -f "$CODESIGN_CONFIG" ]; then
    source "$CODESIGN_CONFIG"
    SIGNING_IDENTITY="$DEFAULT_SIGNING_IDENTITY"
    echo "📋 Using signing identity from config: $SIGNING_IDENTITY"
else
    # Fallback to Apple Development certificate
    SIGNING_IDENTITY="Apple Development: Peter Steinberger (2ZAC4GM7GD)"
    echo "⚠️  No codesign config found, using default: $SIGNING_IDENTITY"
fi

if [ -f "$SWIFT_PROJECT_PATH/terminator.entitlements" ]; then
    echo "🔏 Code signing with Apple Development certificate and entitlements..."
    codesign --force --sign "$SIGNING_IDENTITY" --entitlements "$SWIFT_PROJECT_PATH/terminator.entitlements" "$FINAL_BINARY_PATH"
    echo "✅ Code signing complete with Apple Development certificate"
else
    echo "⚠️  No entitlements file found, signing with Apple Development certificate only"
    codesign --force --sign "$SIGNING_IDENTITY" "$FINAL_BINARY_PATH"
fi

echo "🗑️ Cleaning up temporary architecture-specific binaries..."
rm -f "$ARM64_BINARY_TEMP" "$X86_64_BINARY_TEMP"

echo "🔍 Verifying final universal binary..."
lipo -info "$FINAL_BINARY_PATH"
ls -lh "$FINAL_BINARY_PATH"

echo "🎉 Universal binary '$FINAL_BINARY_PATH' created and optimized successfully!"
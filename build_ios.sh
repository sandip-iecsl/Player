#!/bin/bash

# Aura Player iOS Build Script
# Run this script on a Mac with Xcode installed

echo "🎵 Building Aura Player for iOS..."

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter is not installed. Please install Flutter first."
    exit 1
fi

# Check if we're on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "❌ This script must be run on macOS to build iOS apps."
    exit 1
fi

# Clean previous builds
echo "🧹 Cleaning previous builds..."
flutter clean

# Get dependencies
echo "📦 Getting dependencies..."
flutter pub get

# Run code analysis
echo "🔍 Running code analysis..."
flutter analyze

# Run tests
echo "🧪 Running tests..."
flutter test

# Build iOS app (debug, no code signing)
echo "🔨 Building iOS app (debug)..."
flutter build ios --debug --no-codesign

echo "✅ Debug build completed!"
echo "📱 To build for release and create IPA:"
echo "   1. Set up your Apple Developer account"
echo "   2. Configure code signing in Xcode"
echo "   3. Run: flutter build ipa --release"

# Uncomment the following lines once you have proper code signing set up:
# echo "🔨 Building release IPA..."
# flutter build ipa --release --export-options-plist=ios/ExportOptions.plist
# echo "✅ IPA file created at: build/ios/ipa/aura_player.ipa"
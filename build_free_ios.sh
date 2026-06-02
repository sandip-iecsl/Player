#!/bin/bash

# 🆓 Free iOS Build Script for Aura Player
# This creates a development IPA that can be installed manually

echo "🎵 Building Aura Player for iOS (FREE VERSION)..."
echo ""

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter is not installed. Please install Flutter first."
    exit 1
fi

# Check if we're on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "❌ This script must be run on macOS to build iOS apps."
    echo "💡 Alternative: Use the GitHub Actions workflow for cloud builds"
    exit 1
fi

echo "🧹 Cleaning previous builds..."
flutter clean

echo "📦 Getting dependencies..."
flutter pub get

echo "🔍 Running code analysis..."
flutter analyze

echo "🧪 Running tests..."
flutter test

echo ""
echo "🔨 Building iOS app (Development - No Code Signing)..."
flutter build ios --debug --no-codesign

echo ""
echo "📦 Creating development IPA..."

# Navigate to build directory
cd build/ios/iphoneos

# Create IPA directory if it doesn't exist
mkdir -p ../ipa

# Create the IPA file
echo "🗜️  Compressing app bundle..."
zip -r ../ipa/aura_player_development.ipa Runner.app

echo ""
echo "✅ FREE iOS build completed successfully!"
echo ""
echo "📍 IPA Location: build/ios/ipa/aura_player_development.ipa"
echo ""
echo "📱 Installation Options:"
echo ""
echo "1. 🖥️  Xcode (Mac):"
echo "   - Connect iPhone via USB"
echo "   - Open Xcode → Window → Devices and Simulators"
echo "   - Drag the IPA file to your device"
echo ""
echo "2. 🛠️  3uTools (Windows/Mac):"
echo "   - Download 3uTools (free)"
echo "   - Connect iPhone"
echo "   - Go to Apps → Install → Select IPA"
echo ""
echo "3. 📱 AltStore (Recommended):"
echo "   - Install AltStore on computer and iPhone"
echo "   - Use AltStore to install IPA"
echo "   - Automatic refresh every 7 days"
echo ""
echo "⚠️  Important Notes:"
echo "   - This is a DEVELOPMENT build (unsigned)"
echo "   - Valid for 7 days, then needs reinstallation"
echo "   - Can install on up to 3 devices per Apple ID"
echo "   - NO Apple Developer account required"
echo "   - Completely FREE!"
echo ""
echo "🎉 Your Aura Player app is ready for manual installation!"

# Open the IPA directory
if command -v open &> /dev/null; then
    echo ""
    echo "📂 Opening IPA directory..."
    open build/ios/ipa/
fi
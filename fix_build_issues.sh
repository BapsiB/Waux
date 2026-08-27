#!/bin/bash

echo "🔧 WAUX Build Issue Fixer"
echo "=========================="

echo "1. Clearing Xcode caches..."
rm -rf ~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex
rm -rf ~/Library/Developer/Xcode/DerivedData/SDKStatCaches.noindex
rm -rf ~/Library/Developer/Xcode/DerivedData/WAUX-*

echo "2. Cleaning project..."
xcodebuild clean -project WAUX.xcodeproj

echo "3. Creating module cache directory..."
mkdir -p ~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex

echo "✅ Cache clearing complete!"
echo ""
echo "Next steps:"
echo "1. Restart Xcode completely"
echo "2. Open WAUX.xcodeproj in Xcode"
echo "3. Try building the project (⌘+B)"
echo ""
echo "If you still get Spatial module errors:"
echo "1. Go to Build Settings in Xcode"
echo "2. Search for 'Other Swift Flags'"
echo "3. Add: -Xfrontend -disable-verify-module-interface"
echo ""
echo "This should resolve the module cache issues."


#!/bin/bash

# Script to update the app icon with newly exported PNG files
# This script copies the PNG files to the Xcode project and updates the Contents.json

set -e  # Exit on any error

echo "🔄 Updating app icon with new PNG files..."

# Check if icon_output directory exists
if [ ! -d "icon_output" ]; then
    echo "❌ Error: icon_output directory not found!"
    echo "Please run 
    ./export_logo.sh first to generate the PNG files."
    exit 1
fi

# Check if PNG files exist
if [ ! -f "icon_output/icon_16x16.png" ]; then
    echo "❌ Error: PNG files not found in icon_output directory!"
    echo "Please run ./export_logo.sh first to generate the PNG files."
    exit 1
fi

# Copy PNG files to the app icon directory
echo "📁 Copying PNG files to app icon directory..."
cp icon_output/icon_*.png WAUX/Assets.xcassets/AppIcon.appiconset/

echo "✅ PNG files copied successfully!"

# Update the Contents.json file
echo "📝 Updating Contents.json file..."
cat > WAUX/Assets.xcassets/AppIcon.appiconset/Contents.json << 'EOF'
{
  "images": [
    {
      "filename": "icon_16x16.png",
      "idiom": "mac",
      "scale": "1x",
      "size": "16x16"
    },
    {
      "filename": "icon_32x32.png",
      "idiom": "mac",
      "scale": "2x",
      "size": "16x16"
    },
    {
      "filename": "icon_32x32.png",
      "idiom": "mac",
      "scale": "1x",
      "size": "32x32"
    },
    {
      "filename": "icon_64x64.png",
      "idiom": "mac",
      "scale": "2x",
      "size": "32x32"
    },
    {
      "filename": "icon_128x128.png",
      "idiom": "mac",
      "scale": "1x",
      "size": "128x128"
    },
    {
      "filename": "icon_256x256.png",
      "idiom": "mac",
      "scale": "2x",
      "size": "128x128"
    },
    {
      "filename": "icon_256x256.png",
      "idiom": "mac",
      "scale": "1x",
      "size": "256x256"
    },
    {
      "filename": "icon_512x512.png",
      "idiom": "mac",
      "scale": "2x",
      "size": "256x256"
    },
    {
      "filename": "icon_512x512.png",
      "idiom": "mac",
      "scale": "1x",
      "size": "512x512"
    },
    {
      "filename": "icon_1024x1024.png",
      "idiom": "mac",
      "scale": "2x",
      "size": "512x512"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  }
}
EOF

echo "✅ Contents.json updated successfully!"

echo ""
echo "🎉 App icon update complete!"
echo ""
echo "📋 Next steps:"
echo "1. Open your project in Xcode"
echo "2. Clean the build folder (Product → Clean Build Folder)"
echo "3. Build and run your app to see the new icon"
echo ""
echo "💡 The new icon should appear in:"
echo "   • Dock (when app is running)"
echo "   • Finder (in Applications folder)"
echo "   • Spotlight search results"
echo "   • App switcher (Cmd+Tab)"

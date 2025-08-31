#!/bin/bash

# Single script to export SVG logo and update app icon
# This script converts your SVG to PNG and immediately updates your app icon

set -e  # Exit on any error

echo "🎨 Exporting SVG logo and updating app icon..."

# Check if SVG file exists
if [ ! -f "assets/logo.svg" ]; then
    echo "❌ Error: assets/logo.svg not found!"
    echo "Please make sure the SVG file is in the assets/ directory."
    exit 1
fi

# Check if rsvg-convert is available
if ! command -v rsvg-convert &> /dev/null; then
    echo "❌ Error: rsvg-convert not found!"
    echo "Please install librsvg: brew install librsvg"
    exit 1
fi

# Create temporary output directory
echo "📁 Creating temporary directory..."
mkdir -p temp_icons

# Convert to all required sizes
echo "🔄 Converting SVG to PNG files..."
echo "  📐 Converting to 16x16..."
rsvg-convert -w 16 -h 16 assets/logo.svg -o temp_icons/icon_16x16.png

echo "  📐 Converting to 32x32..."
rsvg-convert -w 32 -h 32 assets/logo.svg -o temp_icons/icon_32x32.png

echo "  📐 Converting to 64x64..."
rsvg-convert -w 64 -h 64 assets/logo.svg -o temp_icons/icon_64x64.png

echo "  📐 Converting to 128x128..."
rsvg-convert -w 128 -h 128 assets/logo.svg -o temp_icons/icon_128x128.png

echo "  📐 Converting to 256x256..."
rsvg-convert -w 256 -h 256 assets/logo.svg -o temp_icons/icon_256x256.png

echo "  📐 Converting to 512x512..."
rsvg-convert -w 512 -h 512 assets/logo.svg -o temp_icons/icon_512x512.png

echo "  📐 Converting to 1024x1024..."
rsvg-convert -w 1024 -h 1024 assets/logo.svg -o temp_icons/icon_1024x1024.png

echo "✅ PNG files created successfully!"

# Copy PNG files to the app icon directory
echo "📁 Updating app icon..."
cp temp_icons/icon_*.png WAUX/Assets.xcassets/AppIcon.appiconset/

echo "✅ PNG files copied to app icon directory!"

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

# Clean up temporary files
echo "🧹 Cleaning up temporary files..."
rm -rf temp_icons

echo ""
echo "🎉 Logo update complete!"
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

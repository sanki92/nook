#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

NAME=Nook
VERSION="${VERSION:-1.0.0}"
FLAGS=(-O -swift-version 5)
mkdir -p build

if [[ "${1:-}" == "--check" ]]; then
  swiftc "${FLAGS[@]}" Sources/Core/*.swift Sources/Checks/main.swift -o build/checks
  exec build/checks
fi

LIBRARY=()
for file in Sources/App/*.swift; do [[ "$file" != */main.swift ]] && LIBRARY+=("$file"); done

APP="build/$NAME.app"
rm -rf "$APP" build/AppIcon.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
BINARIES=()
for arch in ${ARCHS:-arm64 x86_64}; do
  swiftc "${FLAGS[@]}" -target "$arch-apple-macos14.0" Sources/Core/*.swift Sources/App/*.swift -o "build/$NAME-$arch"
  BINARIES+=("build/$NAME-$arch")
done
lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/$NAME"
swiftc "${FLAGS[@]}" Sources/Core/*.swift "${LIBRARY[@]}" Sources/Icon/main.swift -o build/icon
build/icon build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>app.nook.widget</string>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/$NAME.app"
  cp -R "$APP" "$HOME/Applications/"
  echo "Installed to $HOME/Applications/$NAME.app"
fi

if [[ "${1:-}" == "--zip" ]]; then
  rm -f "build/$NAME.zip"
  ditto -c -k --keepParent "$APP" "build/$NAME.zip"
  echo "Packed build/$NAME.zip"
fi

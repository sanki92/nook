#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

TARGET=arm64-apple-macos14.0
FLAGS=(-O -swift-version 5 -target "$TARGET")
mkdir -p build

if [[ "${1:-}" == "--check" ]]; then
  swiftc "${FLAGS[@]}" Sources/Core/*.swift Sources/Checks/main.swift -o build/checks
  exec build/checks
fi

APP="build/Claude Agents.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc "${FLAGS[@]}" Sources/Core/*.swift Sources/App/*.swift -o "$APP/Contents/MacOS/ClaudeAgents"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Claude Agents</string>
  <key>CFBundleIdentifier</key><string>local.claude-agent-widget</string>
  <key>CFBundleExecutable</key><string>ClaudeAgents</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/Claude Agents.app"
  cp -R "$APP" "$HOME/Applications/"
  echo "Installed to $HOME/Applications/Claude Agents.app"
fi

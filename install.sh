#!/bin/bash
set -euo pipefail

REPO="${NOOK_REPO:-https://github.com/GITHUB_USER/nook.git}"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "Nook runs on macOS only."
  exit 1
fi

if (( $(sw_vers -productVersion | cut -d. -f1) < 14 )); then
  echo "Nook needs macOS 14 Sonoma or later."
  exit 1
fi

if ! xcode-select -p >/dev/null 2>&1; then
  echo "Nook is built on your Mac with Apple's free Command Line Tools."
  echo "An installer window is opening now. When it finishes, run this command again."
  xcode-select --install >/dev/null 2>&1 || true
  exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "Downloading Nook..."
git clone --quiet --depth 1 "$REPO" "$work/nook"

echo "Building Nook for your Mac..."
ARCHS="$(uname -m)" "$work/nook/build.sh" --install >/dev/null

pkill -x Nook >/dev/null 2>&1 || true
open "$HOME/Applications/Nook.app"

echo "Nook is running on your desktop."
echo "Right-click it to change its size or turn on Open at Login."

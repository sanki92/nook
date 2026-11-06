#!/bin/bash
set -Eeuo pipefail

main() {
  local repo="${NOOK_REPO:-https://github.com/GITHUB_USER/nook.git}"

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

  local arch=x86_64
  if [[ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" == "1" ]]; then arch=arm64; fi

  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT
  trap 'echo; echo "Nook could not be installed. You can download it instead: https://github.com/GITHUB_USER/nook/releases/latest"' ERR

  echo "Downloading Nook..."
  GIT_TERMINAL_PROMPT=0 git clone --quiet --depth 1 "$repo" "$work/nook"

  if pgrep -x Nook >/dev/null; then
    pkill -x Nook || true
    while pgrep -x Nook >/dev/null; do sleep 0.2; done
  fi

  echo "Building Nook for your Mac..."
  ARCHS="$arch" "$work/nook/build.sh" --install >/dev/null

  open "$HOME/Applications/Nook.app"
  echo "Nook is running on your desktop."
  echo "Right-click it to change its size or turn on Open at Login."
}

main "$@"

#!/bin/sh

set -eu

swift build -c release
ln -sf "$(pwd)/.build/release/xcode-bsp" /usr/local/bin/xcode-bsp

echo "Installed symlink: /usr/local/bin/xcode-bsp"
echo "Next: run 'xcode-bsp config' in your Xcode project root to generate .bsp/xcode-bsp.json."
echo "Optional: run 'xcode-bsp config --executable-path /custom/path/to/xcode-bsp' to override argv[0]."

#!/bin/sh

set -eu

swift build -c release
ln -sf "$(pwd)/.build/release/xcode-bsp" /usr/local/bin/xcode-bsp

echo '{
     "name": "xcode-bsp",
     "argv": ["/usr/local/bin/xcode-bsp"],
     "version": "0.2.0",
     "bspVersion": "2.0.0",
     "languages": ["swift", "objective-c", "objective-cpp", "c", "cpp"]
}' | pbcopy

echo "Configuration copied to the buffer, create .bsp/xcode-bsp.json in your project's root"

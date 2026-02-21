#!/bin/sh

set -eu

swift build -c release

source_executable="$(pwd)/.build/release/xcode-bsp"
default_install_dir="/usr/local/bin"

printf "Where should the executable be installed? [%s]: " "$default_install_dir"
IFS= read -r install_dir
if [ -z "$install_dir" ]; then
    install_dir="$default_install_dir"
fi

# Resolve shell path expansions from user input (for example: "~", "~/...", "$HOME/...").
eval "install_dir=$install_dir"

install_path="${install_dir%/}/xcode-bsp"
install_parent_dir="$(dirname "$install_path")"
mkdir -p "$install_parent_dir"
cp "$source_executable" "$install_path"
chmod +x "$install_path"

if [ ! -x "$install_path" ]; then
    echo "Failed to install executable at: $install_path" >&2
    exit 1
fi

echo "Installed executable: $install_path"
echo "Next: run 'xcode-bsp config' in your Xcode project root to generate .bsp/xcode-bsp.json."
echo "Optional: run 'xcode-bsp config --executable-path /custom/path/to/xcode-bsp' to override argv[0]."

#!/bin/bash
# Safety Filter (.sft) Extension Installer for VLC

echo "==============================================="
echo "Installing VLC Safety Filter (.sft) Extension"
echo "==============================================="

OS="$(uname -s)"

if [ "$OS" = "Darwin" ]; then
    TARGET_DIR="$HOME/Library/Application Support/org.videolan.vlc/lua/extensions"
elif [ "$OS" = "Linux" ]; then
    TARGET_DIR="$HOME/.local/share/vlc/lua/extensions"
else
    echo "Windows detected. Please copy lua/extensions/sft_filter.lua to %APPDATA%\\vlc\\lua\\extensions\\"
    exit 0
fi

mkdir -p "$TARGET_DIR"
cp "lua/extensions/sft_filter.lua" "$TARGET_DIR/sft_filter.lua"

echo "✅ Extension installed to: $TARGET_DIR/sft_filter.lua"
echo "Restart VLC and navigate to View -> Safety Filter (.sft) to launch."
echo "==============================================="

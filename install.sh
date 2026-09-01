#!/bin/bash
# Safety Filter (.sft) Installer for VLC
# Installs both the extension (GUI) and interface (background looper) scripts.

set -e

echo "==============================================="
echo "  VLC Safety Filter (.sft) Installer"
echo "==============================================="

OS="$(uname -s)"

if [ "$OS" = "Darwin" ]; then
    EXT_DIR="$HOME/Library/Application Support/org.videolan.vlc/lua/extensions"
    INTF_DIR="$HOME/Library/Application Support/org.videolan.vlc/lua/intf"
elif [ "$OS" = "Linux" ]; then
    EXT_DIR="$HOME/.local/share/vlc/lua/extensions"
    INTF_DIR="$HOME/.local/share/vlc/lua/intf"
else
    echo "Windows detected."
    echo "Please copy:"
    echo "  lua/extensions/sft_filter.lua -> %APPDATA%\\vlc\\lua\\extensions\\"
    echo "  lua/intf/sft_looper.lua       -> %APPDATA%\\vlc\\lua\\intf\\"
    exit 0
fi

# Create directories
mkdir -p "$EXT_DIR"
mkdir -p "$INTF_DIR"

# Copy extension (GUI editor)
cp "lua/extensions/sft_filter.lua" "$EXT_DIR/sft_filter.lua"
echo "✅ Extension installed:  $EXT_DIR/sft_filter.lua"

# Copy intf script (background looper)
cp "lua/intf/sft_looper.lua" "$INTF_DIR/sft_looper.lua"
echo "✅ Interface installed:  $INTF_DIR/sft_looper.lua"

echo ""
echo "==============================================="
echo "  IMPORTANT: How to enable the background filter"
echo "==============================================="
echo ""
echo "The extension (GUI) will appear automatically in:"
echo "  VLC > Extensions > Safety Filter (.sft)"
echo ""
echo "To enable the background skip/mute engine, launch VLC with:"
echo ""

if [ "$OS" = "Darwin" ]; then
    echo "  /Applications/VLC.app/Contents/MacOS/VLC --extraintf=luaintf --lua-intf=sft_looper"
    echo ""
    echo "Or create an alias in your ~/.zshrc:"
    echo '  alias vlc="/Applications/VLC.app/Contents/MacOS/VLC --extraintf=luaintf --lua-intf=sft_looper"'
else
    echo "  vlc --extraintf=luaintf --lua-intf=sft_looper"
fi

echo ""
echo "Or set it permanently:"
echo "  VLC > Preferences > Show All > Interface > Main interfaces"
echo '  Add "luaintf" to Extra interface modules'
echo "  Under Lua > Lua interface = sft_looper"
echo ""
echo "Then restart VLC."
echo "==============================================="

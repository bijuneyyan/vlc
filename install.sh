#!/bin/bash
# ==============================================================================
# Safety Filter (.sft) — Automated One-Click Installer for VLC
# Supports:
#   1. Web one-line install: curl -fsSL https://raw.githubusercontent.com/bijuneyyan/vlc/main/install.sh | bash
#   2. Local git / zip install: ./install.sh or double-clicking Install.command
# ==============================================================================

set -e

REPO_RAW_URL="https://raw.githubusercontent.com/bijuneyyan/vlc/main"

echo "======================================================="
echo "       🎬 VLC Safety Filter (.sft) Installer"
echo "======================================================="

OS="$(uname -s)"

if [ "$OS" = "Darwin" ]; then
    EXT_DIR="$HOME/Library/Application Support/org.videolan.vlc/lua/extensions"
    INTF_DIR="$HOME/Library/Application Support/org.videolan.vlc/lua/intf"
    VLCRC_DIR="$HOME/Library/Preferences/org.videolan.vlc"
    VLCRC_FILE="$VLCRC_DIR/vlcrc"
elif [ "$OS" = "Linux" ]; then
    EXT_DIR="$HOME/.local/share/vlc/lua/extensions"
    INTF_DIR="$HOME/.local/share/vlc/lua/intf"
    VLCRC_DIR="$HOME/.config/vlc"
    VLCRC_FILE="$VLCRC_DIR/vlcrc"
else
    echo "❌ Windows auto-installer not supported via bash."
    echo "Please manually copy lua/extensions/sft_filter.lua and lua/intf/sft_looper.lua to %APPDATA%\\vlc\\lua\\"
    exit 1
fi

# 1. Create target directories
mkdir -p "$EXT_DIR"
mkdir -p "$INTF_DIR"
mkdir -p "$VLCRC_DIR"

# 2. Install sft_filter.lua (GUI Extension)
if [ -f "lua/extensions/sft_filter.lua" ]; then
    cp "lua/extensions/sft_filter.lua" "$EXT_DIR/sft_filter.lua"
else
    echo "⬇️  Downloading sft_filter.lua from GitHub..."
    curl -fsSL "$REPO_RAW_URL/lua/extensions/sft_filter.lua" -o "$EXT_DIR/sft_filter.lua"
fi
echo "✅ Installed GUI Extension: $EXT_DIR/sft_filter.lua"

# 3. Install sft_looper.lua (Background Looper)
if [ -f "lua/intf/sft_looper.lua" ]; then
    cp "lua/intf/sft_looper.lua" "$INTF_DIR/sft_looper.lua"
else
    echo "⬇️  Downloading sft_looper.lua from GitHub..."
    curl -fsSL "$REPO_RAW_URL/lua/intf/sft_looper.lua" -o "$INTF_DIR/sft_looper.lua"
fi
echo "✅ Installed Background Looper: $INTF_DIR/sft_looper.lua"

# 4. Auto-configure VLC Preferences (vlcrc) so no manual setup is required
echo "⚙️  Auto-configuring VLC preferences..."

if [ ! -f "$VLCRC_FILE" ]; then
    # Create clean vlcrc configuration file
    cat << 'EOF' > "$VLCRC_FILE"
[main]
extraintf=luaintf
lua-intf=sft_looper
EOF
else
    # Update existing vlcrc

    # Configure extraintf=luaintf
    if grep -q "^extraintf=" "$VLCRC_FILE"; then
        if ! grep -q "luaintf" "$VLCRC_FILE"; then
            sed -i.bak 's/^extraintf=\(.*\)/extraintf=\1:luaintf/' "$VLCRC_FILE"
        fi
    elif grep -q "^#extraintf=" "$VLCRC_FILE"; then
        sed -i.bak 's/^#extraintf=.*/extraintf=luaintf/' "$VLCRC_FILE"
    else
        echo "extraintf=luaintf" >> "$VLCRC_FILE"
    fi

    # Configure lua-intf=sft_looper
    if grep -q "^lua-intf=" "$VLCRC_FILE"; then
        if ! grep -q "sft_looper" "$VLCRC_FILE"; then
            sed -i.bak 's/^lua-intf=.*/lua-intf=sft_looper/' "$VLCRC_FILE"
        fi
    elif grep -q "^#lua-intf=" "$VLCRC_FILE"; then
        sed -i.bak 's/^#lua-intf=.*/lua-intf=sft_looper/' "$VLCRC_FILE"
    else
        echo "lua-intf=sft_looper" >> "$VLCRC_FILE"
    fi

    rm -f "$VLCRC_FILE.bak"
fi

echo "✅ Auto-configured VLC configuration ($VLCRC_FILE)"

# 5. Show user-friendly completion message
echo ""
echo "======================================================="
echo "  🎉 Installation Complete & Ready to Use!"
echo "======================================================="
echo "  1. Open (or restart) VLC Media Player."
echo "  2. Play any video with a matching .sft file (e.g. movie.sft next to movie.mp4)."
echo "  3. Open VLC menu -> Extensions -> Safety Filter (.sft) to edit filters."
echo "======================================================="

# Native macOS notification if run on Darwin desktop
if [ "$OS" = "Darwin" ] && command -v osascript >/dev/null 2>&1; then
    osascript -e 'display notification "Safety Filter (.sft) has been installed and configured!" with title "VLC Safety Filter"' 2>/dev/null || true
fi

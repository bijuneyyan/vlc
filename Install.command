#!/bin/bash
# Double-clickable installer for macOS Finder users
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"
bash ./install.sh
echo ""
read -p "Press [Enter] to exit..."

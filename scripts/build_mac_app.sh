#!/usr/bin/env bash

# Build Radflow Desktop for Mac (Universal Binary)
# Run this from the root of the project: bash scripts/build_mac_app.sh

echo "Installing PyInstaller and dependencies..."
python3 -m pip install pyinstaller zeroconf pyautogui pyperclip

echo "Building Mac Universal App..."
# target-architecture universal2 builds for BOTH Apple Silicon and Intel Mac
pyinstaller --noconfirm --onedir --windowed --name "Radflow Desktop" \
  --target-architecture universal2 \
  --clean \
  scripts/ledis_desktop_bridge.py

echo "Build complete! Your Mac app is located at: dist/Radflow Desktop.app"
echo "You can double click it to run it in the background."

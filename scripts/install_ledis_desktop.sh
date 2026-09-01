#!/usr/bin/env bash
# =============================================================================
# LEDIS Desktop Bridge — one-time macOS installer
#
# Installs the wireless-mic bridge as a background LaunchAgent that:
#   • auto-starts when the Mac logs in
#   • restarts automatically if it ever crashes
#   • runs invisibly (no window, nothing to click, nothing to remember)
#
# After running this ONCE, the doctor never touches this Mac again:
# open the iPhone app → connect → speak → text types at the cursor.
#
# Usage:  bash install_ledis_desktop.sh
# =============================================================================

set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)/ledis_desktop_bridge.py"
INSTALL_DIR="$HOME/Library/Application Support/LEDIS"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST="$PLIST_DIR/com.ledis.bridge.plist"
PY="${PYTHON:-/usr/bin/env python3}"

echo "── LEDIS Desktop Bridge installer (macOS) ─────────────────────────"

# 1. Resolve a real python3 path
PY_BIN="$(command -v python3 || true)"
if [ -z "$PY_BIN" ]; then
  echo "✗ python3 not found. Install Python 3 from https://python.org and re-run."
  exit 1
fi
echo "• Python: $PY_BIN"

# 2. Install dependencies (user site, no sudo)
echo "• Installing Python packages (zeroconf pyautogui pyperclip)…"
"$PY_BIN" -m pip install --quiet --user zeroconf pyautogui pyperclip || {
  echo "✗ pip install failed. Try:  python3 -m pip install --user zeroconf pyautogui pyperclip"
  exit 1
}

# 3. Copy the bridge into place
mkdir -p "$INSTALL_DIR" "$PLIST_DIR"
cp "$SRC" "$INSTALL_DIR/ledis_desktop_bridge.py"
echo "• Bridge copied to: $INSTALL_DIR"

# 4. LaunchAgent — auto-start at login, keep alive
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.ledis.bridge</string>
  <key>ProgramArguments</key>
  <array>
    <string>$PY_BIN</string>
    <string>$INSTALL_DIR/ledis_desktop_bridge.py</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$INSTALL_DIR/bridge.log</string>
  <key>StandardErrorPath</key><string>$INSTALL_DIR/bridge.log</string>
</dict>
</plist>
PLIST

# 5. Load it now (restart-safe)
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
echo "• LaunchAgent installed and running (auto-starts at every login)."

echo
echo "✔ Done. On the Mac: nothing more to do — ever."
echo "  (First time only: System Settings → Privacy & Security → Accessibility →"
echo "   enable your terminal/python so the bridge can paste keystrokes.)"
echo
echo "  Logs: $INSTALL_DIR/bridge.log"
echo "  Stop/remove anytime:  launchctl unload $PLIST"

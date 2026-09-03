#!/usr/bin/env python3
"""
RadFlow Desktop Bridge (Windows / macOS / Linux)
==============================================

Companion for the RadFlow iOS "Wireless Remote" tab.

1. Advertises itself on the local Wi-Fi via Bonjour/Zeroconf (`_ledis._tcp`),
   so the iPhone discovers it automatically — no IP entry needed.
2. Accepts TCP connections on port 48484 and receives newline-delimited JSON:
       {"type": "text", "text": "..."}
3. Types each received text at the current cursor position in whatever app is
   focused (EMR, PACS, Word, browser, terminal...).

Install & run:
    pip install zeroconf pyautogui pyperclip
    python3 radflow_desktop_bridge.py

Notes:
- macOS: grant Accessibility permission to your terminal (System Settings ->
  Privacy & Security -> Accessibility) so synthetic keystrokes are allowed.
- Windows/Linux: pyautogui handles Ctrl+V pasting natively.
"""

import json
import os
import plistlib
import socket
import struct
import subprocess
import sys
import threading

from zeroconf import Zeroconf, ServiceInfo, IPVersion

try:
    import pyautogui
    import pyperclip
except ImportError:
    sys.exit("Missing deps. Run:  pip install zeroconf pyautogui pyperclip")

PORT = 48484
SERVICE_TYPE = "_ledis._tcp.local."
HOST_LABEL = socket.gethostname().replace(".local", "") or "RadFlow Desktop"
SERVICE_NAME = f"{HOST_LABEL}._ledis._tcp.local."

pyautogui.FAILSAFE = True  # slam mouse to a screen corner to abort a runaway paste


def primary_lan_ip() -> str:
    """Return the machine's primary LAN IPv4 (not 127.0.0.1)."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))  # no traffic is actually sent
        ip = s.getsockname()[0]
    except OSError:
        ip = "127.0.0.1"
    finally:
        s.close()
    return ip


def type_at_cursor(text: str) -> None:
    """Paste at the cursor (fast, unicode-safe); fall back to typing.
    A trailing space keeps consecutive spoken chunks separated naturally."""
    text = text + " "
    # Step 1: copy to clipboard
    import subprocess
    proc = subprocess.Popen(["pbcopy"], stdin=subprocess.PIPE)
    proc.communicate(text.encode("utf-8"))

    # Step 2: simulate Cmd+V
    if sys.platform == "darwin":
        try:
            # Use Quartz CGEvents — most reliable on modern macOS
            import Quartz
            src = Quartz.CGEventSourceCreate(Quartz.kCGEventSourceStateHIDSystemState)
            # Key code 9 = 'v'
            cmd_down = Quartz.CGEventCreateKeyboardEvent(src, 9, True)
            cmd_up = Quartz.CGEventCreateKeyboardEvent(src, 9, False)
            Quartz.CGEventSetFlags(cmd_down, Quartz.kCGEventFlagMaskCommand)
            Quartz.CGEventSetFlags(cmd_up, Quartz.kCGEventFlagMaskCommand)
            Quartz.CGEventPost(Quartz.kCGHIDEventTap, cmd_down)
            Quartz.CGEventPost(Quartz.kCGHIDEventTap, cmd_up)
            print(f"[RadFlow] Pasted via Quartz CGEvents")
            return
        except Exception as e:
            print(f"[RadFlow] Quartz CGEvents failed: {e}")

        try:
            # Fallback: AppleScript
            subprocess.run([
                "osascript", "-e",
                'tell application "System Events" to keystroke "v" using command down'
            ], check=True, timeout=3)
            print(f"[RadFlow] Pasted via osascript")
            return
        except Exception as e:
            print(f"[RadFlow] osascript failed: {e}")

    # Last resort: pyautogui
    try:
        pyperclip.copy(text)
        if sys.platform == "darwin":
            pyautogui.hotkey("command", "v")
        else:
            pyautogui.hotkey("ctrl", "v")
    except Exception:
        try:
            pyautogui.write(text, interval=0.005)
        except Exception as exc:
            print(f"[RadFlow] Could not type text: {exc}")


def handle_client(conn: socket.socket, addr) -> None:
    print(f"[RadFlow] iPhone connected from {addr[0]}")
    buffer = b""
    with conn:
        while True:
            try:
                chunk = conn.recv(4096)
            except OSError:
                break
            if not chunk:
                break
            buffer += chunk
            while b"\n" in buffer:
                line, buffer = buffer.split(b"\n", 1)
                if not line.strip():
                    continue
                try:
                    message = json.loads(line.decode("utf-8"))
                except json.JSONDecodeError:
                    continue
                if message.get("type") == "text":
                    text = message.get("text", "")
                    if text:
                        print(f"[RadFlow] Typing {len(text)} chars at cursor…")
                        type_at_cursor(text)
    print(f"[RadFlow] iPhone {addr[0]} disconnected")


def tcp_server() -> None:
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("", PORT))
    server.listen(8)
    print(f"[RadFlow] Listening on 0.0.0.0:{PORT}")
    while True:
        conn, addr = server.accept()
        threading.Thread(target=handle_client, args=(conn, addr), daemon=True).start()


def advertise() -> tuple[Zeroconf, ServiceInfo]:
    ip = primary_lan_ip()
    zc = Zeroconf()
    info = ServiceInfo(
        SERVICE_TYPE,
        SERVICE_NAME,
        addresses=[socket.inet_aton(ip)],
        port=PORT,
        properties={"app": "ledis", "version": "1"},
        server=f"{HOST_LABEL.replace(' ', '-')}.local.",
    )
    zc.register_service(info)
    print("=" * 56)
    print(" RadFlow Desktop Bridge")
    print(f"  Machine : {HOST_LABEL}")
    print(f"  Address : {ip}:{PORT}")
    print("  Status  : Visible to the iPhone on this Wi-Fi")
    print("=" * 56)
    return zc, info


def setup_autostart() -> None:
    """Configures macOS launchd to automatically start this app on login."""
    if sys.platform != "darwin":
        return
        
    executable_path = sys.executable
    if not executable_path:
        return
        
    plist_label = "com.radflow.desktop.autostart"
    launch_agents_dir = os.path.expanduser("~/Library/LaunchAgents")
    plist_path = os.path.join(launch_agents_dir, f"{plist_label}.plist")
    
    os.makedirs(launch_agents_dir, exist_ok=True)
    
    # If running from a .app bundle, launch the .app using open -W
    if "/Contents/MacOS" in executable_path:
        app_path = executable_path.split("/Contents/MacOS")[0]
        prog_args = ["/usr/bin/open", "-W", app_path]
    else:
        prog_args = [executable_path]
        
    plist_content = {
        "Label": plist_label,
        "ProgramArguments": prog_args,
        "RunAtLoad": True,
        "KeepAlive": True
    }
    
    try:
        if os.path.exists(plist_path):
            with open(plist_path, "rb") as f:
                existing_plist = plistlib.load(f)
            if existing_plist == plist_content:
                return  # Already up to date
    except Exception:
        pass
        
    try:
        with open(plist_path, "wb") as f:
            plistlib.dump(plist_content, f)
        subprocess.run(["launchctl", "unload", plist_path], capture_output=True)
        subprocess.run(["launchctl", "load", plist_path], capture_output=True)
        print("[RadFlow] Configured auto-start LaunchAgent.")
    except Exception as e:
        print(f"[RadFlow] Failed to set up auto-start: {e}")


def main() -> None:
    setup_autostart()
    zc, info = advertise()
    try:
        tcp_server()
    except KeyboardInterrupt:
        pass
    finally:
        zc.unregister_service(info)
        zc.close()
        print("[RadFlow] Bridge stopped.")


if __name__ == "__main__":
    main()

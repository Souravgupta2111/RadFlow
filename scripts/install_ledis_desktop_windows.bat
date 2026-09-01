@echo off
REM =============================================================================
REM LEDIS Desktop Bridge - one-time Windows installer
REM
REM Copies the bridge to %APPDATA%\LEDIS, installs Python deps, and places a
REM hidden auto-start entry in the user's Startup folder. After running this
REM ONCE, the bridge starts invisibly at every login - nothing to click.
REM
REM Usage: double-click, or run from a terminal:  install_ledis_desktop_windows.bat
REM =============================================================================

setlocal

set SRC=%~dp0ledis_desktop_bridge.py
set DESTDIR=%APPDATA%\LEDIS
set STARTUP=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup

echo -- LEDIS Desktop Bridge installer (Windows) -------------------------

where python >nul 2>nul
if errorlevel 1 (
  echo [X] Python not found. Install Python 3 from https://python.org
  echo     and tick "Add python.exe to PATH" during setup, then re-run.
  pause
  exit /b 1
)

echo [+] Installing Python packages ^(zeroconf pyautogui pyperclip^)...
python -m pip install --quiet zeroconf pyautogui pyperclip
if errorlevel 1 (
  echo [X] pip install failed. Run manually:
  echo     python -m pip install zeroconf pyautogui pyperclip
  pause
  exit /b 1
)

if not exist "%DESTDIR%" mkdir "%DESTDIR%"
copy /y "%SRC%" "%DESTDIR%\ledis_desktop_bridge.py" >nul
echo [+] Bridge copied to %DESTDIR%

REM Hidden auto-start: wscript runs the python window invisibly at login.
> "%DESTDIR%\start_hidden.vbs" (
  echo Set sh = CreateObject^("WScript.Shell"^)
  echo sh.Run "cmd /c python ""%DESTDIR%\ledis_desktop_bridge.py"" >> ""%DESTDIR%\bridge.log"" 2>&1", 0, False
)

copy /y "%DESTDIR%\start_hidden.vbs" "%STARTUP%\LEDIS Bridge.vbs" >nul
echo [+] Auto-start installed ^(runs invisibly at every login^).

REM Start it right now so no reboot is needed.
wscript "%DESTDIR%\start_hidden.vbs"
echo [+] Bridge started.

echo.
echo [OK] Done. On this PC: nothing more to do - ever.
echo      Phone app: connect, tap the mic, speak. Text types at the cursor.
echo      Remove anytime: delete "LEDIS Bridge.vbs" from the Startup folder.
echo      Logs: %DESTDIR%\bridge.log
pause

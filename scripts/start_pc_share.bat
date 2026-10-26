@echo off
setlocal
cd /d "%~dp0\.."
py -c "import qrcode" >nul 2>nul
if errorlevel 1 (
  py -m pip install -r scripts\requirements-pc-share.txt
  if errorlevel 1 (
    echo Failed to install the QR-code dependency.
    pause
    exit /b 1
  )
)
py scripts\pc_lan_share_server.py
pause

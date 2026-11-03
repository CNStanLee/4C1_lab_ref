@echo off
rem Double-click to find the AUP-ZU3 serial port and open it in COMTool.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0serial_zu3.ps1" %*
if errorlevel 1 pause

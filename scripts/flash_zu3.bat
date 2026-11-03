@echo off
rem Double-click to download the AUP-ZU3 PYNQ image and write it to a microSD card.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0flash_zu3.ps1" %*
if errorlevel 1 pause

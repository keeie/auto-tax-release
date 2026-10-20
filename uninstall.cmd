@echo off
chcp 65001 >nul
title auto-tax 삭제
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1"
echo.
pause

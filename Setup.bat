@echo off
rem Double-click this file to install caelestia-win. No administrator rights needed.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1"

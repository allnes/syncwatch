@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\bootstrap_and_run.ps1"

@echo off
setlocal
rem ============================================================
rem  Installs/updates all mod zips in this folder into Factorio.
rem  Default target: %APPDATA%\Factorio\mods  (Steam Factorio)
rem  Custom target:  install-mods.bat "D:\SomeOther\Factorio\mods"
rem ============================================================

set "MODS=%APPDATA%\Factorio\mods"
if not "%~1"=="" set "MODS=%~1"

if not exist "%MODS%" (
    echo.
    echo ERROR: mods folder not found: %MODS%
    echo Start Factorio once so it creates its folders, or pass the
    echo mods folder path as an argument to this script.
    echo.
    pause
    exit /b 1
)

echo.
echo Copying mod zips to: %MODS%
echo.
copy /Y "%~dp0*.zip" "%MODS%" >nul
if errorlevel 1 (
    echo ERROR: copy failed. Is Factorio running? Close it and retry.
    pause
    exit /b 1
)

for %%F in ("%~dp0*.zip") do echo   installed %%~nxF

echo.
echo Done. Start Factorio - it loads the highest version of each mod
echo automatically. If you were in the middle of a multiplayer session,
echo restart the game before rejoining.
echo.
pause

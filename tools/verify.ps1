# tools/verify.ps1 - headless verification for E-Tech before building/shipping.
# Lives OUTSIDE E-Tech/ on purpose: the mod portal rejects zips containing
# scripts, and build.ps1 packages everything under E-Tech/ except its own
# exclusion list.
#
# Steps:
#   1. Lua syntax check of every .lua in E-Tech/ (python + luaparser)
#   2. Changelog format lint (tools/lint-changelog.py)
#   3. factorio --dump-data with the CURRENT mods folder (catches data-stage
#      errors; requires the zip to be built first via E-Tech/build.ps1)
#
# Usage:  powershell -File tools\verify.ps1 [-SkipDump]

param([switch]$SkipDump)
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$mod = Join-Path $repo "E-Tech"
$fail = 0

Write-Host "== 1/3 Lua syntax =="
Get-ChildItem $mod -Recurse -Filter *.lua | ForEach-Object {
    python -c "from luaparser import ast; import sys; ast.parse(open(sys.argv[1],encoding='utf-8').read())" $_.FullName
    if ($LASTEXITCODE -ne 0) { Write-Host "SYNTAX FAIL: $($_.FullName)"; $script:fail++ }
}
if ($fail -eq 0) { Write-Host "all lua files parse" }

Write-Host "== 2/3 Changelog lint =="
python (Join-Path $PSScriptRoot "lint-changelog.py")
if ($LASTEXITCODE -ne 0) { $fail++ }

if (-not $SkipDump) {
    Write-Host "== 3/3 dump-data =="
    $factorio = "C:\Program Files (x86)\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
    if (Test-Path $factorio) {
        & $factorio --dump-data | Out-Null
        $log = Join-Path $env:APPDATA "Factorio\factorio-current.log"
        $errors = Select-String -Path $log -Pattern "^\s*[\d.]+ Error" -CaseSensitive
        if ($errors) {
            Write-Host "dump-data ERRORS:"; $errors | ForEach-Object Line; $fail++
        } else {
            Write-Host "dump-data clean"
        }
    } else {
        Write-Host "factorio.exe not found - skipped dump-data"
    }
}

if ($fail -gt 0) { Write-Host "VERIFY FAILED ($fail)"; exit 1 }
Write-Host "VERIFY OK"

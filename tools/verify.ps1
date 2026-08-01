# tools/verify.ps1 - headless verification for E-Tech before building/shipping.
# Lives OUTSIDE E-Tech/ on purpose: the mod portal rejects zips containing
# scripts, and build.ps1 packages everything under E-Tech/ except its own
# exclusion list.
#
# Steps:
#   1. Lua syntax check of every .lua in E-Tech/ (python + luaparser)
#   2. Changelog format lint + info.json version cross-check
#      (tools/lint-changelog.py)
#   3. Locale coverage lint (tools/lint-locale.py): settings missing their
#      strings, code referencing keys that do not exist, and dead keys
#   4. luacheck, when it is installed locally (CI runs it on every push)
#   5. factorio --dump-data with the CURRENT mods folder (catches data-stage
#      errors; requires the zip to be built first via E-Tech/build.ps1)
#
# NOT covered here: loading under other mod COMBINATIONS. Step 5 tests exactly
# one point - whatever happens to be enabled right now - while the whole point
# of E-Tech's guards is the matrix around it. That is tools/verify-matrix.ps1:
# vanilla / Space Age / AAI / AAI+Space Age / AAI+K2 / Factorissimo, each in a
# throwaway mod directory. Run it before a release; it takes minutes.
#
# Usage:  powershell -File tools\verify.ps1 [-SkipDump]

param([switch]$SkipDump)
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$mod = Join-Path $repo "E-Tech"
$fail = 0

Write-Host "== 1/5 Lua syntax =="
Get-ChildItem $mod -Recurse -Filter *.lua | ForEach-Object {
    python -c "from luaparser import ast; import sys; ast.parse(open(sys.argv[1],encoding='utf-8').read())" $_.FullName
    if ($LASTEXITCODE -ne 0) { Write-Host "SYNTAX FAIL: $($_.FullName)"; $script:fail++ }
}
if ($fail -eq 0) { Write-Host "all lua files parse" }

Write-Host "== 2/5 Changelog lint =="
python (Join-Path $PSScriptRoot "lint-changelog.py")
if ($LASTEXITCODE -ne 0) { $fail++ }

Write-Host "== 3/5 Locale lint =="
python (Join-Path $PSScriptRoot "lint-locale.py")
if ($LASTEXITCODE -ne 0) { $fail++ }

Write-Host "== 4/5 luacheck =="
$luacheck = Get-Command luacheck -ErrorAction SilentlyContinue
if ($luacheck) {
    & $luacheck.Source $mod --config (Join-Path $repo ".luacheckrc")
    if ($LASTEXITCODE -ne 0) { $fail++ }
} else {
    Write-Host "luacheck not installed locally - skipped (CI runs it on push)"
}

if (-not $SkipDump) {
    Write-Host "== 5/5 dump-data =="
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
Write-Host "(mod-combination matrix: powershell -File tools\verify-matrix.ps1)"

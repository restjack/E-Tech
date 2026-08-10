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
#      strings, code referencing keys that do not exist, dead keys, and
#      prototypes shipped with no name in locale/ (that last one reads a
#      data-raw dump, so it is only as fresh as the last dump - step 6 re-runs
#      it against the dump step 5 writes)
#   4. luacheck, when it is installed locally (CI runs it on every push)
#   5. factorio --dump-data with the CURRENT mods folder (catches data-stage
#      errors; requires the zip to be built first via E-Tech/build.ps1)
#   7. runtime behaviour (tools/verify-runtime.ps1): runs the game headless,
#      builds a real Factorissimo factory and asserts the hub actually moves
#      items. Steps 1-6 all prove the mod LOADS; this one proves it WORKS.
#
# NOT covered here: loading under other mod COMBINATIONS. Step 5 tests exactly
# one point - whatever happens to be enabled right now - while the whole point
# of E-Tech's guards is the matrix around it. That is tools/verify-matrix.ps1:
# vanilla / Space Age / AAI / AAI+Space Age / AAI+K2 / Factorissimo, each in a
# throwaway mod directory. Run it before a release; it takes minutes.
#
# Usage:  powershell -File tools\verify.ps1 [-SkipDump]

param([switch]$SkipDump, [switch]$SkipRuntime)
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$mod = Join-Path $repo "E-Tech"
$fail = 0
# Every step that can skip itself records WHY here, and the summary prints them
# next to "VERIFY OK". A green run that quietly did half the work is worse than
# a red one: the whole value of the word OK is that it means the same thing
# every time. Costs nothing and removes the need to read the scrollback.
$skipped = @()

Write-Host "== 1/6 Lua syntax =="
Get-ChildItem $mod -Recurse -Filter *.lua | ForEach-Object {
    python -c "from luaparser import ast; import sys; ast.parse(open(sys.argv[1],encoding='utf-8').read())" $_.FullName
    if ($LASTEXITCODE -ne 0) { Write-Host "SYNTAX FAIL: $($_.FullName)"; $script:fail++ }
}
if ($fail -eq 0) { Write-Host "all lua files parse" }

Write-Host "== 2/6 Changelog lint =="
python (Join-Path $PSScriptRoot "lint-changelog.py")
if ($LASTEXITCODE -ne 0) { $fail++ }

Write-Host "== 3/6 Locale lint =="
python (Join-Path $PSScriptRoot "lint-locale.py")
if ($LASTEXITCODE -ne 0) { $fail++ }

Write-Host "== 3b/6 GUI element names =="
# Naming a GUI element after one of LuaGuiElement's own properties is not a
# warning - the engine refuses to create it, and the player gets a
# non-recoverable mod error the moment they open the window. Shipped exactly
# that in 0.24.1 ("tabs"). The runtime harness cannot catch it: --benchmark has
# no player, so no relative GUI is ever opened.
python (Join-Path $PSScriptRoot "lint-gui-names.py")
if ($LASTEXITCODE -ne 0) { $fail++ }

Write-Host "== 4/6 luacheck =="
# Prefer whatever is on PATH. Failing that, fall back to a luarocks install
# under the user profile - which is what `winget install DEVCOM.Lua` plus
# `luarocks install luacheck` leaves behind, PATH untouched. The rock's entry
# point is an extensionless Lua script, so it is run through lua.exe with the
# luarocks tree on LUA_PATH; nothing is added to the environment permanently.
$luacheckCmd = Get-Command luacheck -ErrorAction SilentlyContinue
$luaExe = Join-Path $env:LOCALAPPDATA "Programs\Lua\bin\lua.exe"
$rocks = Join-Path $env:APPDATA "luarocks"
$luacheckScript = Join-Path $rocks "bin\luacheck"
$config = Join-Path $repo ".luacheckrc"

if ($luacheckCmd) {
    & $luacheckCmd.Source $mod --config $config
    if ($LASTEXITCODE -ne 0) { $fail++ }
} elseif ((Test-Path $luaExe) -and (Test-Path $luacheckScript)) {
    $env:LUA_PATH = "$rocks\share\lua\5.4\?.lua;$rocks\share\lua\5.4\?\init.lua;;"
    $env:LUA_CPATH = "$rocks\lib\lua\5.4\?.dll;;"
    & $luaExe $luacheckScript $mod --config $config
    if ($LASTEXITCODE -ne 0) { $fail++ }
} else {
    Write-Host "luacheck not installed locally - skipped (CI runs it on push)"
    $skipped += "luacheck (not installed locally; CI runs it on push)"
}

if ($SkipDump) { $skipped += "dump-data and the prototype-locale check (-SkipDump)" }
if ($SkipRuntime) { $skipped += "runtime behaviour (-SkipRuntime)" }

if (-not $SkipDump) {
    Write-Host "== 5/6 dump-data =="
    $factorio = "C:\Program Files (x86)\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
    if (Test-Path $factorio) {
        # Own write-data directory, like verify-runtime.ps1 and
        # verify-matrix.ps1. Factorio holds an exclusive lock on its user data,
        # so with the game open this step died on "Couldn't create lock file" -
        # which reads like a broken script rather than "close Factorio". The
        # MOD directory stays the live one on purpose: the whole point of this
        # step is dumping whatever pack is actually installed.
        $work = Join-Path $env:TEMP "etech-verify-dump"
        $userData = Join-Path $work "userdata"
        $config = Join-Path $work "config.ini"
        New-Item -ItemType Directory -Force -Path $userData | Out-Null
        @"
[path]
read-data=__PATH__executable__/../../data
write-data=$($userData -replace '\\', '/')
"@ | Out-File $config -Encoding utf8

        & $factorio --dump-data --config $config `
            --mod-directory (Join-Path $env:APPDATA "Factorio\mods") | Out-Null
        $log = Join-Path $userData "factorio-current.log"

        # lint-locale.py reads the dump from the live script-output folder, so
        # put the fresh one where it looks.
        $dump = Join-Path $userData "script-output\data-raw-dump.json"
        $liveOutput = Join-Path $env:APPDATA "Factorio\script-output"
        if (Test-Path $dump) {
            New-Item -ItemType Directory -Force -Path $liveOutput | Out-Null
            Copy-Item $dump $liveOutput -Force
        }
        $errors = Select-String -Path $log -Pattern "^\s*[\d.]+ Error" -CaseSensitive
        if ($errors) {
            Write-Host "dump-data ERRORS:"; $errors | ForEach-Object Line; $fail++
        } else {
            Write-Host "dump-data clean"
        }

        # Step 3 ran before the dump existed, so its prototype-name check used
        # whatever dump was lying around. Re-run it against the one just
        # written - this is the check that catches a prototype shipped with no
        # locale name, which nothing in the Lua source references.
        Write-Host "== 6/6 prototype locale names (fresh dump) =="
        python (Join-Path $PSScriptRoot "lint-locale.py")
        if ($LASTEXITCODE -ne 0) { $fail++ }
    } else {
        Write-Host "factorio.exe not found - skipped dump-data"
        $skipped += "dump-data and the prototype-locale check (factorio.exe not found)"
    }
}

if (-not $SkipRuntime) {
    Write-Host "== 7/7 runtime behaviour =="
    # Actually runs the game: builds a Factorissimo factory, stocks it, places
    # the hub devices and asserts items moved. Everything above this line proves
    # the mod LOADS; this is the only step that proves it WORKS. Needs the built
    # zip (same as the dump step) and Factorissimo in the mods folder; skips
    # itself with a message when either is missing.
    $runtime = & powershell -File (Join-Path $PSScriptRoot "verify-runtime.ps1")
    $runtime | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { $fail++ }
    # verify-runtime exits 0 when it cannot run at all (no factorio.exe, no
    # Factorissimo). That is right for it and wrong for the summary here.
    if ($runtime -match "skipped") { $skipped += "runtime behaviour (see its own message above)" }
}

if ($fail -gt 0) { Write-Host "VERIFY FAILED ($fail)"; exit 1 }
if ($skipped.Count -gt 0) {
    Write-Host "VERIFY OK, but $($skipped.Count) check(s) did NOT run:"
    $skipped | ForEach-Object { Write-Host "  - $_" }
} else {
    Write-Host "VERIFY OK (every check ran)"
}
Write-Host "(mod-combination matrix: powershell -File tools\verify-matrix.ps1)"

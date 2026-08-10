# tools/verify-runtime.ps1 - does E-Tech's factory hub actually move items?
#
# WHY. verify.ps1 proves the mod LOADS; verify-matrix.ps1 proves it loads
# alongside five other mod combinations. Neither runs a single tick, so every
# control-stage change - the code that teleports items across a factory wall -
# has only ever been checked by a person opening the game and looking in a
# chest. This runs the game instead.
#
# HOW. A throwaway mod directory under %TEMP% gets E-Tech, Factorissimo (and the
# Space Age family, which Factorissimo wants), plus the tiny test mod in
# tools/runtime-test. Factorio then:
#   1. --create   builds a map; the test mod's on_init places a real factory,
#                 stocks its interior, and puts an outlet/inlet/sensor outside
#   2. --benchmark runs that map for a fixed number of ticks, during which the
#                 test mod asserts and log()s one line per assertion
# The live mods folder and its mod-list.json are never touched, same rule as
# verify-matrix.ps1.
#
# Requires E-Tech to have been built first (E-Tech/build.ps1), because it copies
# the built zip out of the live mods folder.
#
# Usage:  powershell -File tools\verify-runtime.ps1 [-Ticks 1800] [-KeepWork]

param(
    [int]$Ticks = 1800,
    [switch]$KeepWork
)

$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$mods = Join-Path $env:APPDATA "Factorio\mods"
$work = Join-Path $env:TEMP "etech-verify-runtime"
$factorio = "C:\Program Files (x86)\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"

# Its own write-data directory, via its own config.ini. Two reasons, both
# learned the hard way: Factorio takes an exclusive lock on its user data
# directory, so with the game open this run dies on "Couldn't create lock file"
# and the failure looks like a mod problem; and reading assertions out of the
# LIVE factorio-current.log means racing whatever the game is writing to it.
# Isolated, this runs happily while Eli is playing.
$userData = Join-Path $work "userdata"
$config = Join-Path $work "config.ini"
$log = Join-Path $userData "factorio-current.log"

if (-not (Test-Path $factorio)) {
    Write-Host "factorio.exe not found - skipped"
    exit 0
}

$info = Get-Content (Join-Path $repo "E-Tech\info.json") -Raw | ConvertFrom-Json
$etechZip = Join-Path $mods "E-Tech_$($info.version).zip"
if (-not (Test-Path $etechZip)) {
    Write-Host "E-Tech_$($info.version).zip not in the mods folder - run E-Tech\build.ps1 first"
    exit 1
}

# Highest-sorting <prefix>_<version>.zip in the live mods folder.
function Resolve-ModZip([string]$prefix) {
    $hit = Get-ChildItem $mods -Filter "$prefix`_*.zip" -ErrorAction SilentlyContinue |
        Sort-Object Name | Select-Object -Last 1
    return $hit
}

$factorissimo = Resolve-ModZip "factorissimo-2-notnotmelon"
if (-not $factorissimo) {
    Write-Host "factorissimo-2-notnotmelon zip not found in $mods - the factory hub"
    Write-Host "does not even load without it, so there is nothing to test. Skipped."
    exit 0
}

if (Test-Path $work) { Remove-Item -Recurse -Force $work }
$modDir = Join-Path $work "mods"
New-Item -ItemType Directory -Force -Path $modDir | Out-Null
New-Item -ItemType Directory -Force -Path $userData | Out-Null

# read-data stays with the game (that is where base/space-age live); everything
# writable is redirected into the scratch directory.
@"
[path]
read-data=__PATH__executable__/../../data
write-data=$($userData -replace '\\', '/')
"@ | Out-File $config -Encoding utf8

Copy-Item $etechZip $modDir
Copy-Item $factorissimo.FullName $modDir
Copy-Item (Join-Path $PSScriptRoot "runtime-test") (Join-Path $modDir "etech-runtime-test_0.1.0") -Recurse

# Space Age and friends ship inside the game's data directory: they are switched
# on by naming them here, not by copying anything.
$modList = @{
    mods = @(
        @{ name = "base";                       enabled = $true },
        @{ name = "elevated-rails";             enabled = $true },
        @{ name = "quality";                    enabled = $true },
        @{ name = "space-age";                  enabled = $true },
        @{ name = "recycler";                   enabled = $true },
        @{ name = "factorissimo-2-notnotmelon"; enabled = $true },
        @{ name = "E-Tech";                     enabled = $true },
        @{ name = "etech-runtime-test";         enabled = $true }
    )
}
$modList | ConvertTo-Json -Depth 4 | Out-File (Join-Path $modDir "mod-list.json") -Encoding utf8

$save = Join-Path $work "runtime-test.zip"

Write-Host "== 1/2 create map (runs the test mod's world setup) =="
& $factorio --create $save --mod-directory $modDir --config $config | Out-Null
if (-not (Test-Path $save)) {
    Write-Host "RUNTIME TEST FAILED - --create produced no save; last errors:"
    Select-String -Path $log -Pattern "^\s*[\d.]+ Error" -CaseSensitive |
        Select-Object -Last 10 | ForEach-Object Line
    exit 1
}

Write-Host "== 2/2 run $Ticks ticks =="
& $factorio --benchmark $save --benchmark-ticks $Ticks --benchmark-runs 1 `
    --mod-directory $modDir --config $config | Out-Null

$lines = Select-String -Path $log -Pattern "\[ETECH-TEST\]" | ForEach-Object { $_.Line }
if (-not $lines) {
    Write-Host "RUNTIME TEST FAILED - the test mod logged nothing."
    Write-Host "Either it never loaded or the run ended before tick $Ticks."
    Select-String -Path $log -Pattern "^\s*[\d.]+ Error" -CaseSensitive |
        Select-Object -Last 10 | ForEach-Object Line
    exit 1
}

$lines | ForEach-Object { Write-Host $_ }
$failed = $lines | Where-Object { $_ -match "\] FAIL " }
$done = $lines | Where-Object { $_ -match "\] DONE " }

if (-not $KeepWork) { Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue }

if ($failed) { Write-Host "RUNTIME TEST FAILED ($($failed.Count) assertion(s))"; exit 1 }
if (-not $done) {
    Write-Host "RUNTIME TEST INCONCLUSIVE - assertions never reached; raise -Ticks"
    exit 1
}
Write-Host "RUNTIME TEST OK"

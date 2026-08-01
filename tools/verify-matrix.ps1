# tools/verify-matrix.ps1 - load E-Tech under several mod combinations.
#
# WHY. E-Tech's central promise is that it behaves correctly whether or not AAI
# Industry, Krastorio 2, Space Age, Factorissimo or Jetpack are present - nearly
# every guard in the codebase exists to serve that promise. Until 0.21.1 nothing
# tested it: verify.ps1 ran --dump-data against whatever mods happened to be
# enabled, which is one point in a six-dimensional space. The three modules that
# hardcoded recipe ingredients with no existence guard (found in the 2026-07-31
# audit) are exactly the failure a matrix run catches on the first attempt.
#
# HOW. Each profile gets its OWN scratch mod directory under %TEMP%, populated
# with copies of the zips it needs, and Factorio is pointed at it with
# --mod-directory. Nothing writes to %APPDATA%\Factorio\mods - the live mod
# folder and its mod-list.json are never touched, per the standing rule that
# mods are enabled in-game only.
#
# Space Age, Quality, Elevated rails and Recycler ship inside the game's own
# data directory, so they are toggled by naming them in the scratch
# mod-list.json rather than by copying anything.
#
# Requires E-Tech to have been built first (E-Tech/build.ps1), because it copies
# the built zip out of the live mods folder.
#
# Usage:  powershell -File tools\verify-matrix.ps1 [-Profiles vanilla,aai-k2] [-KeepWork]

param(
    [string[]]$Profiles,
    [switch]$KeepWork
)

$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$mods = Join-Path $env:APPDATA "Factorio\mods"
$log = Join-Path $env:APPDATA "Factorio\factorio-current.log"
$work = Join-Path $env:TEMP "etech-verify-matrix"
$factorio = "C:\Program Files (x86)\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"

$info = Get-Content (Join-Path $repo "E-Tech\info.json") -Raw | ConvertFrom-Json
$etechZip = Join-Path $mods "E-Tech_$($info.version).zip"

# Built-in mods that live in the game's data directory. Always named in
# mod-list.json so Factorio does not auto-enable one we meant to leave out.
$builtin = @("elevated-rails", "quality", "space-age", "recycler")

# Each profile: which extra mod zips to copy in (by name prefix), and whether
# the Space Age family is on. Chosen to cover every branch E-Tech guards on.
$profileSpecs = [ordered]@{
    "vanilla"       = @{ zips = @();                                                    spaceAge = $false }
    "space-age"     = @{ zips = @();                                                    spaceAge = $true  }
    "aai"           = @{ zips = @("aai-industry");                                      spaceAge = $false }
    "aai-space-age" = @{ zips = @("aai-industry");                                      spaceAge = $true  }
    # Krastorio2 hard-depends on its assets, its menu simulations and flib.
    "aai-k2"        = @{ zips = @("aai-industry", "Krastorio2", "Krastorio2Assets",
                                  "Krastorio2MenuSimulations", "flib");             spaceAge = $false }
    "factorissimo"  = @{ zips = @("factorissimo-2-notnotmelon");                        spaceAge = $true  }
}

function Resolve-ModZip([string]$prefix) {
    # Highest-sorting <prefix>_<version>.zip in the live mods folder.
    #
    # Regex, not -Filter: the wildcard "Krastorio2_*.zip" also matches
    # "krastorio2_extended_endgame_2.1.1.zip", and sorting then picked the
    # add-on over the mod itself. The version part must be digits and dots
    # only, which pins the match to the mod named exactly $prefix.
    $pattern = "^" + [regex]::Escape($prefix) + "_[0-9][0-9.]*\.zip$"
    Get-ChildItem $mods -Filter "*.zip" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match $pattern } |
        Sort-Object Name | Select-Object -Last 1
}

if (-not (Test-Path $factorio)) {
    Write-Host "factorio.exe not found at $factorio - nothing to run."
    exit 0
}
if (-not (Test-Path $etechZip)) {
    Write-Host "E-Tech_$($info.version).zip is not in $mods."
    Write-Host "Run E-Tech\build.ps1 first - this script loads the BUILT zip, not the source folder."
    exit 1
}

$selected = if ($Profiles) { $Profiles } else { @($profileSpecs.Keys) }
$failed = @()
$skipped = @()

foreach ($name in $selected) {
    if (-not $profileSpecs.Contains($name)) {
        Write-Host "unknown profile '$name' - known: $($profileSpecs.Keys -join ', ')"
        $failed += $name
        continue
    }
    $spec = $profileSpecs[$name]
    Write-Host ""
    Write-Host "== profile: $name =="

    # Resolve every required zip before touching anything, so a missing
    # dependency skips the profile cleanly instead of half-building it.
    $resolved = @()
    $missing = @()
    foreach ($prefix in $spec.zips) {
        $zip = Resolve-ModZip $prefix
        if ($zip) { $resolved += $zip } else { $missing += $prefix }
    }
    if ($missing.Count -gt 0) {
        Write-Host "  SKIPPED - not installed: $($missing -join ', ')"
        $skipped += $name
        continue
    }

    $dir = Join-Path $work $name
    if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
    New-Item -ItemType Directory -Force $dir | Out-Null
    Copy-Item $etechZip $dir
    foreach ($zip in $resolved) { Copy-Item $zip.FullName $dir }

    $entries = @('{"name":"base","enabled":true}')
    foreach ($b in $builtin) {
        $on = if ($spec.spaceAge) { "true" } else { "false" }
        $entries += "{`"name`":`"$b`",`"enabled`":$on}"
    }
    $entries += '{"name":"E-Tech","enabled":true}'
    foreach ($zip in $resolved) {
        # <name>_<version>.zip -> <name>
        $modName = $zip.BaseName -replace "_[0-9][0-9.]*$", ""
        $entries += "{`"name`":`"$modName`",`"enabled`":true}"
    }
    $listed = ($spec.zips + @("E-Tech")) -join ", "
    Write-Host "  mods: $listed$(if ($spec.spaceAge) { ' + Space Age' })"
    Set-Content (Join-Path $dir "mod-list.json") "{`"mods`":[$($entries -join ',')]}" -Encoding utf8

    if (Test-Path $log) { Remove-Item -Force $log }
    & $factorio --mod-directory $dir --dump-data 2>&1 | Out-Null

    $errors = @()
    if (Test-Path $log) {
        # Dependency errors continue on the lines AFTER the "Error" line, so
        # take a few lines of trailing context or the reason is invisible.
        $errors = Select-String -Path $log -Pattern "^\s*[\d.]+ Error" -CaseSensitive -Context 0, 4
    }
    if ($errors) {
        Write-Host "  FAILED:"
        foreach ($e in $errors) {
            Write-Host "    $($e.Line)"
            foreach ($after in $e.Context.PostContext) {
                if ($after -match "^\s*[\d.]+ ") { break }  # next log line, stop
                if ($after.Trim()) { Write-Host "    $after" }
            }
        }
        $failed += $name
    } else {
        # Surface E-Tech's own warnings even on success - the recipe guard
        # substituting an ingredient is exactly what this run exists to reveal.
        $notes = Select-String -Path $log -Pattern "\[E-Tech\] recipe-guard" -ErrorAction SilentlyContinue
        if ($notes) {
            Write-Host "  loaded, with recipe-guard activity:"
            $notes | ForEach-Object { Write-Host "    $($_.Line.Trim())" }
        } else {
            Write-Host "  loaded clean"
        }
    }
}

if (-not $KeepWork -and (Test-Path $work)) { Remove-Item -Recurse -Force $work }

Write-Host ""
if ($skipped.Count -gt 0) { Write-Host "skipped (mods not installed): $($skipped -join ', ')" }
if ($failed.Count -gt 0) {
    Write-Host "MATRIX FAILED: $($failed -join ', ')"
    exit 1
}
Write-Host "MATRIX OK"

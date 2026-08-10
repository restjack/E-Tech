# build.ps1 - repackage E-Tech into the Factorio mods folder as name_version.zip
# with forward-slash entry paths (Factorio requires them cross-platform).
# Run from anywhere:  powershell -File build.ps1 [-Force]
#
# -Force allows overwriting an already-archived release of the same version.
# Without it, rebuilding without bumping refuses rather than replacing the
# archived copy of what was actually shipped.

param([switch]$Force)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$src = $PSScriptRoot
$info = Get-Content (Join-Path $src "info.json") -Raw | ConvertFrom-Json
$name = $info.name
$version = $info.version
$root = "$name`_$version"
$mods = Join-Path $env:APPDATA "Factorio\mods"
$zip = Join-Path $mods "$root.zip"
# Built to a temp name in the same folder and renamed into place at the end.
# Writing the zip directly under its real name leaves a window - seconds, but
# real - where the mods folder holds a half-written archive, and a Factorio
# launched in that window fails with "Reading file info in package ... failed".
# Watched exactly that happen to another mod being rebuilt while Eli launched.
# A rename within one volume is atomic, so the game only ever sees the old
# complete zip or the new complete one.
$zipTemp = Join-Path $mods "$root.zip.building"

if (Test-Path $zipTemp) { Remove-Item -Force $zipTemp }
# The installed zip is deliberately NOT deleted here. It used to be, which meant
# any failure between that point and the rename left the mods folder with no
# E-Tech at all - the build clobbered the working copy on its way to failing.
# Move-Item -Force at the end replaces it in one step, so the folder holds the
# old complete zip right up until it holds the new one. (Flagged by the Memory
# Storage session, which found the same shape in its installer.)

# Files to package. Excludes build script, docs, and the releases archive.
$excludeFiles = @("build.ps1", "AAI-CHANGE-INVENTORY.md")
$excludeDirs = @("releases")

$fs = [System.IO.File]::Open($zipTemp, [System.IO.FileMode]::CreateNew)
$arch = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
Get-ChildItem $src -File -Recurse | Where-Object {
  $rel = $_.FullName.Substring($src.Length + 1)
  $top = $rel.Split([char]92)[0]
  ($excludeFiles -notcontains $rel) -and ($excludeDirs -notcontains $top)
} | ForEach-Object {
  $rel = $_.FullName.Substring($src.Length + 1) -replace "\\", "/"
  $entryName = "$root/$rel"
  $entry = $arch.CreateEntry($entryName, [System.IO.Compression.CompressionLevel]::Optimal)
  $es = $entry.Open()
  $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
  $es.Write($bytes, 0, $bytes.Length)
  $es.Close()
}
$arch.Dispose()
$fs.Close()

# Prove the archive opens and carries info.json BEFORE it takes the real name.
# The atomic rename guarantees a reader never sees a half-written file; it does
# not guarantee the finished file is any good. Publishing a structurally broken
# zip fails at load with the same unhelpful "Reading file info in package ...
# failed" as the race did. Idea taken from the Memory Storage session, which
# added the same gate to its installer today.
# OpenRead THROWS on a truncated or corrupt archive rather than returning
# something to inspect, so the check has to be wrapped: uncaught, it would crash
# the build and leave the broken .tmp sitting in the mods folder - the gate
# meant to keep a bad file out would have left one there. The verdict is
# recorded, the archive is closed, and only then is the temp removed; deleting
# while it is still open fails on Windows with a sharing violation.
$verdict = $null
try {
    $check = [System.IO.Compression.ZipFile]::OpenRead($zipTemp)
    try {
        $entryCount = $check.Entries.Count
        $hasInfo = @($check.Entries | Where-Object { $_.FullName -eq "$root/info.json" }).Count -eq 1
        if (-not $hasInfo) { $verdict = "info.json missing from $root/" }
        elseif ($entryCount -lt 2) { $verdict = "only $entryCount entr(ies)" }
    } finally {
        $check.Dispose()
    }
} catch {
    $verdict = "will not open ($($_.Exception.Message))"
}
if ($verdict) {
    Remove-Item -Force $zipTemp -ErrorAction SilentlyContinue
    throw "Built archive failed its integrity check - $verdict - not published, the installed zip is untouched"
}

# File.Replace is the atomic swap on Windows and overwrites; Move-Item -Force
# does NOT reliably overwrite here (it threw "Cannot create a file when that
# file already exists" the moment the destination stopped being pre-deleted).
# Replace needs the destination to exist, so the first ever build falls back to
# a plain move. No backup file is kept - $null as the third argument.
if (Test-Path $zip) {
    # [NullString]::Value, not $null: PowerShell marshals a bare $null into an
    # empty string and Replace rejects it with "The path is not of a legal form".
    try {
        [System.IO.File]::Replace($zipTemp, $zip, [NullString]::Value)
    } catch [System.IO.IOException] {
        Remove-Item -Force $zipTemp -ErrorAction SilentlyContinue
        throw ("Cannot replace $zip - Factorio has it open. Close the game, or " +
               "bump the version so the build writes a new filename. " +
               "The installed zip is untouched. ($($_.Exception.Message))")
    }
} else {
    Move-Item -LiteralPath $zipTemp -Destination $zip
}
Write-Host "Built $zip"

# Archive a copy of every built version in the project folder so old
# versions can be revisited (source folder only holds the latest code).
$releases = Join-Path $src "releases"
New-Item -ItemType Directory -Force $releases | Out-Null
$archived = Join-Path $releases "$root.zip"
if ((Test-Path $archived) -and -not $Force) {
    # The archive is the record of what was actually shipped as this version.
    # Silently replacing it means the folder no longer says what it claims to.
    Write-Host "releases\$root.zip already exists - NOT overwritten."
    Write-Host "Bump the version in info.json (and add a changelog entry), or re-run with -Force."
} else {
    Copy-Item $zip $archived -Force
    Write-Host "Archived to releases\$root.zip"
}

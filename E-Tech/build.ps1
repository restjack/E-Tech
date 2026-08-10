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
if (Test-Path $zip) { Remove-Item -Force $zip }

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
$check = [System.IO.Compression.ZipFile]::OpenRead($zipTemp)
$entryCount = $check.Entries.Count
$hasInfo = @($check.Entries | Where-Object { $_.FullName -eq "$root/info.json" }).Count -eq 1
$check.Dispose()
if (-not $hasInfo -or $entryCount -lt 2) {
    Remove-Item -Force $zipTemp
    throw "Built archive failed its integrity check ($entryCount entries, info.json present: $hasInfo) - not published"
}

Move-Item -LiteralPath $zipTemp -Destination $zip -Force
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

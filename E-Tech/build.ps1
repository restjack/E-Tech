# build.ps1 - repackage E-Tech into the Factorio mods folder as name_version.zip
# with forward-slash entry paths (Factorio requires them cross-platform).
# Run from anywhere:  powershell -File build.ps1

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

if (Test-Path $zip) { Remove-Item -Force $zip }

# Files to package. Excludes build script, docs, and the releases archive.
$excludeFiles = @("build.ps1", "AAI-CHANGE-INVENTORY.md")
$excludeDirs = @("releases")

$fs = [System.IO.File]::Open($zip, [System.IO.FileMode]::CreateNew)
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
Write-Host "Built $zip"

# Archive a copy of every built version in the project folder so old
# versions can be revisited (source folder only holds the latest code).
$releases = Join-Path $src "releases"
New-Item -ItemType Directory -Force $releases | Out-Null
Copy-Item $zip (Join-Path $releases "$root.zip") -Force
Write-Host "Archived to releases\$root.zip"

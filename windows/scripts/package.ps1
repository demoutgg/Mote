param(
    [string]$Version = "0.7.3"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $root

cmake -S windows -B build -A x64
cmake --build build --config Release

New-Item -ItemType Directory -Force -Path dist | Out-Null
$zip = "dist/Lingolite-$Version-windows-x64.zip"
Compress-Archive -Path "build/Release/Lingolite.exe" -DestinationPath $zip -Force

Get-FileHash $zip -Algorithm SHA256 | Format-List
Write-Host "Packaged $zip"

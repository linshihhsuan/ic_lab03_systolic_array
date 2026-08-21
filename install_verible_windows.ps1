param(
    [string]$Version = "v0.0-4084-gf3e4d98b"
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$target = Join-Path $scriptDir "scripts\install_verible_windows.ps1"

if (-not (Test-Path $target)) {
    throw "Target installer not found: $target"
}

& powershell -NoProfile -ExecutionPolicy Bypass -File $target -Version $Version

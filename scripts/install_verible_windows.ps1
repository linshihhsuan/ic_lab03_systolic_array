param(
    [string]$Version = "v0.0-4084-gf3e4d98b"
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..")).Path
$installRoot = Join-Path $repoRoot ".tools\verible"
$zipName = "verible-$Version-win64.zip"
$zipPath = Join-Path $installRoot $zipName
$url = "https://github.com/chipsalliance/verible/releases/download/$Version/$zipName"

Write-Host "[1/4] Downloading $zipName ..."
New-Item -ItemType Directory -Force -Path $installRoot | Out-Null
Invoke-WebRequest -Uri $url -OutFile $zipPath

Write-Host "[2/4] Extracting to $installRoot ..."
Expand-Archive -Path $zipPath -DestinationPath $installRoot -Force

$lintExe = Get-ChildItem -Path $installRoot -Recurse -Filter "verible-verilog-lint.exe" | Select-Object -First 1
if (-not $lintExe) {
    throw "verible-verilog-lint.exe not found under $installRoot"
}

$binDir = $lintExe.Directory.FullName
$pathParts = @($env:Path -split ';')
if ($pathParts -notcontains $binDir) {
    Write-Host "[3/4] Updating User PATH ..."
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ([string]::IsNullOrWhiteSpace($userPath)) {
        [Environment]::SetEnvironmentVariable("Path", $binDir, "User")
    } elseif (($userPath -split ';') -notcontains $binDir) {
        [Environment]::SetEnvironmentVariable("Path", "$userPath;$binDir", "User")
    }
    $env:Path = "$env:Path;$binDir"
} else {
    Write-Host "[3/4] User PATH already contains Verible bin."
}

Write-Host "[4/4] Verifying installation ..."
& $lintExe.FullName --version

Write-Host "Done."
Write-Host "BinDir=$binDir"

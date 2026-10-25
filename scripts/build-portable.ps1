# Usage:
#   .\scripts\build-portable.ps1 -Profile Debug
#   .\scripts\build-portable.ps1 -Profile Release
#
# Builds tty7 locally and creates a Windows portable ZIP under dist/.
[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Profile = 'Debug',
    [string]$Target = 'x86_64-pc-windows-msvc'
)

$ErrorActionPreference = 'Stop'

$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $Root

$TargetArch = @{
    'x86_64-pc-windows-msvc' = 'x64'
    'aarch64-pc-windows-msvc' = 'arm64'
}[$Target]
if (-not $TargetArch) {
    throw "unsupported Windows target: $Target"
}

$CargoProfile = if ($Profile -eq 'Release') { 'release' } else { 'debug' }
$CargoArgs = @('build', '--locked', '--target', $Target)
if ($Profile -eq 'Release') {
    $CargoArgs += '--release'
}

Write-Host "Building tty7 ($Profile, $Target)..."
& cargo @CargoArgs
if ($LASTEXITCODE -ne 0) {
    throw "cargo build failed with exit code $LASTEXITCODE"
}

$UpdaterArgs = @(
    'build', '--locked', '--features', 'updater',
    '--bin', 'tty7-updater', '--target', $Target
)
if ($Profile -eq 'Release') {
    $UpdaterArgs += '--release'
}
& cargo @UpdaterArgs
if ($LASTEXITCODE -ne 0) {
    throw "tty7-updater build failed with exit code $LASTEXITCODE"
}

$Version = (Select-String -Path 'Cargo.toml' -Pattern '^version\s*=\s*"([^"]+)"').Matches[0].Groups[1].Value
$Name = "tty7-$Version-windows-$TargetArch-portable-$($Profile.ToLowerInvariant())"
$Dist = Join-Path $Root 'dist'
$Stage = Join-Path $Dist $Name
$TargetDir = Join-Path $Root "target/$Target/$CargoProfile"

Remove-Item -LiteralPath $Stage -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Stage | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Stage 'completions') | Out-Null

foreach ($Binary in 'tty7-app.exe', 'tty7.exe', 'tty7-updater.exe') {
    $Source = Join-Path $TargetDir $Binary
    if (-not (Test-Path -LiteralPath $Source)) {
        throw "built binary is missing: $Source"
    }
    Copy-Item -LiteralPath $Source -Destination (Join-Path $Stage $Binary)
}

Copy-Item 'assets/completions/*.json' (Join-Path $Stage 'completions')
Copy-Item 'LICENSE' (Join-Path $Stage 'LICENSE.txt')
Copy-Item 'README.md' (Join-Path $Stage 'README.md')

foreach ($File in 'conpty.dll', 'OpenConsole.exe') {
    $Source = "assets/windows/conpty/$TargetArch/$File"
    if (-not (Test-Path -LiteralPath $Source)) {
        throw "missing bundled ConPTY file: $Source"
    }
    Copy-Item -LiteralPath $Source -Destination (Join-Path $Stage $File)
}
Copy-Item 'assets/windows/conpty/LICENSE.txt' (Join-Path $Stage 'LICENSE-ConPTY.txt')

# Optional Linux musl server for WSL. Put the matching asset in
# bundled-server/ before running the script to include it in the package.
$ServerAsset = @{
    'x86_64-pc-windows-msvc'  = 'tty7-server-linux-x86_64-musl'
    'aarch64-pc-windows-msvc' = 'tty7-server-linux-aarch64-musl'
}[$Target]
$ServerSource = Join-Path $Root "bundled-server/$ServerAsset"
if (Test-Path -LiteralPath $ServerSource) {
    $ServerDir = Join-Path $Stage 'server'
    New-Item -ItemType Directory -Force -Path $ServerDir | Out-Null
    Copy-Item -LiteralPath $ServerSource -Destination (Join-Path $ServerDir $ServerAsset)
    Write-Host "Included WSL server: $ServerAsset"
} else {
    Write-Warning "WSL server not found at $ServerSource; this package cannot serve WSL distros"
}

Set-Content -LiteralPath (Join-Path $Stage '.tty7-portable') -Value 'portable-v1' -NoNewline -Encoding ascii

New-Item -ItemType Directory -Force -Path $Dist | Out-Null
$Archive = Join-Path $Dist "$Name.zip"
Remove-Item -LiteralPath $Archive -Force -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $Stage '*') -DestinationPath $Archive -Force

Write-Host "Portable package: $Archive"

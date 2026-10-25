# Builds a local Windows Debug portable package.
[CmdletBinding()]
param(
    [string]$Target = 'x86_64-pc-windows-msvc'
)

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'build-portable.ps1') -Profile Debug -Target $Target
exit $LASTEXITCODE

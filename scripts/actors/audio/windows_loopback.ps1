param([string]$Source, [string]$Output, [string]$Stop, [string]$Ready)
$ErrorActionPreference = 'Stop'
try {
    Add-Type -Path $Source
    [KiwiLoopback]::Run($Output, $Stop, $Ready)
} catch {
    [System.IO.File]::WriteAllText($Ready, 'ERROR: ' + $_.Exception.Message)
    exit 1
}

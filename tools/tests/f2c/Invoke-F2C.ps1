[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Preflight','Monitor','Archive')][string]$Mode,
    [Parameter(Mandatory=$true)][string]$Rpt,
    [Parameter(Mandatory=$true)][string]$Session,
    [Parameter(Mandatory=$true)][string]$EvidenceDirectory,
    [string]$Manifest = '',
    [ValidateRange(1,900)][int]$TimeoutSeconds = 360
)
$ErrorActionPreference = 'Stop'
if (-not $Manifest) { $Manifest = Join-Path $PSScriptRoot 'manifest.json' }
# Arguments are passed as an array, never interpreted as PowerShell/Python source.
$arguments = @("$PSScriptRoot\monitor.py",'--mode',$Mode,'--rpt',$Rpt,'--session',$Session,
    '--evidence',$EvidenceDirectory,'--manifest',$Manifest,'--timeout',"$TimeoutSeconds")
& python @arguments
if ($LASTEXITCODE -ne 0) { throw "F2C $Mode did not complete cleanly (exit $LASTEXITCODE). Review evidence/status.json or findings.json." }

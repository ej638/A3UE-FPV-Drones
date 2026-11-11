param(
    [Parameter(Mandatory=$true)][string[]]$RptPath,
    [Parameter(Mandatory=$true)][string]$Destination,
    [string]$Candidate = '.hemttout/build/addons/fpv_ai_drones.pbo',
    [string[]]$VendorPbo = @(),
    [switch]$Final
)
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath $Destination) { throw 'Use a new destination folder; existing evidence is preserved.' }
$dest = New-Item -ItemType Directory -Path $Destination
$manifest = [System.Collections.Generic.List[object]]::new()
$index = 0
foreach ($source in $RptPath) {
    $absolute = (Resolve-Path -LiteralPath $source).Path
    $index++
    $name = '{0:D2}-{1}-{2}' -f $index, $(if ($Final) {'final'} else {'partial'}), [IO.Path]::GetFileName($absolute)
    $target = Join-Path $dest.FullName $name
    # Snapshot exactly the length at open. Read-sharing allows Arma to keep writing.
    $share = [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete
    $inputStream = [IO.FileStream]::new($absolute, [IO.FileMode]::Open, [IO.FileAccess]::Read, $share)
    try {
        $initialLength = $inputStream.Length
        $remaining = $initialLength
        $outputStream = [IO.FileStream]::new($target, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
        try {
            $buffer = [byte[]]::new(65536)
            while ($remaining -gt 0) {
                $read = $inputStream.Read($buffer, 0, [int][Math]::Min($buffer.Length, $remaining))
                if ($read -eq 0) { throw 'Source truncated during copy; preserve this partial copy and retry into a new folder.' }
                $outputStream.Write($buffer, 0, $read)
                $remaining -= $read
            }
        } finally { $outputStream.Dispose() }
        $manifest.Add([pscustomobject]@{kind='rpt'; source=$absolute; copy=$name; bytes=$initialLength;
            sourceBytesAfter=$inputStream.Length; finalRequested=[bool]$Final; sha256=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash})
    } finally { $inputStream.Dispose() }
}
$candidatePath = (Resolve-Path -LiteralPath $Candidate).Path
$candidateTarget = Join-Path $dest.FullName 'candidate-fpv_ai_drones.pbo'
Copy-Item -LiteralPath $candidatePath -Destination $candidateTarget
$manifest.Add([pscustomobject]@{kind='candidate';source=$candidatePath;copy='candidate-fpv_ai_drones.pbo';sha256=(Get-FileHash -LiteralPath $candidateTarget -Algorithm SHA256).Hash})
foreach ($vendor in $VendorPbo) {
    $vendorPath = (Resolve-Path -LiteralPath $vendor).Path
    $manifest.Add([pscustomobject]@{kind='vendor-readonly';source=$vendorPath;sha256=(Get-FileHash -LiteralPath $vendorPath -Algorithm SHA256).Hash;bytes=(Get-Item -LiteralPath $vendorPath).Length})
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $dest.FullName 'manifest.json') -Encoding UTF8
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'results-template.md') -Destination (Join-Path $dest.FullName 'results.md')
Write-Output ('Evidence preserved in ' + $dest.FullName + '; fill results.md and run the parser. Final complete RPTs require normal process exit first.')

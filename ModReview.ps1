[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string] $Path = "$env:APPDATA\.minecraft\mods",

    [string] $ExportCsv
)

<#[
.SYNOPSIS
    Read-only, offline review of Minecraft mod JAR files.
.DESCRIPTION
    Calculates SHA-256 hashes and checks JAR contents for a small set of
    review indicators. A hit is a lead for manual review, not proof that a
    mod is cheating or malicious. The script does not run, extract, delete,
    quarantine, upload, or modify scanned files or Windows security settings.
.PARAMETER Path
    A mods folder. Defaults to the standard .minecraft\mods folder.
.PARAMETER ExportCsv
    Optional path for a CSV report. No report is written unless requested.
.EXAMPLE
    .\ModReview.ps1 -Path "$env:APPDATA\.minecraft\mods"
.EXAMPLE
    .\ModReview.ps1 -Path "D:\Prism\instances\Test\.minecraft\mods" -ExportCsv .\report.csv
]#>

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    throw "Mods folder not found: $Path"
}
$Path = (Resolve-Path -LiteralPath $Path).Path

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

# These terms can also occur in legitimate mods, documentation, or libraries.
# Keep this list transparent and inspect every reported match in context.
$Indicators = @(
    'AimAssist', 'AutoClicker', 'AutoCrystal', 'AutoTotem', 'AutoAnchor',
    'TriggerBot', 'SilentAim', 'PingSpoof', 'FakeLag', 'Velocity',
    'ChestSteal', 'Reach', 'KillAura', 'SelfDestruct'
)

function Get-JarReview {
    param([System.IO.FileInfo] $File)

    $hits = [System.Collections.Generic.List[string]]::new()
    $scanError = $null
    $archive = $null

    try {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($File.FullName)
        $entryCount = 0
        foreach ($entry in $archive.Entries) {
            $entryCount++
            if ($entryCount -gt 5000) { $scanError = 'Entry limit reached (5000)'; break }
            if ($entry.Length -gt 8MB) { continue }
            if ($entry.FullName -notmatch '\.(class|json|mf|toml|properties|accesswidener)$') { continue }

            $stream = $null
            $memory = $null
            try {
                $stream = $entry.Open()
                $memory = [System.IO.MemoryStream]::new()
                $stream.CopyTo($memory)
                $bytes = $memory.ToArray()
                # Class files and metadata commonly contain UTF-8/ASCII strings.
                $content = [System.Text.Encoding]::UTF8.GetString($bytes)
                foreach ($term in $Indicators) {
                    if ($content.IndexOf($term, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                        $label = "$term [$($entry.FullName)]"
                        if (-not $hits.Contains($label)) { $hits.Add($label) }
                    }
                }
            }
            finally {
                if ($memory) { $memory.Dispose() }
                if ($stream) { $stream.Dispose() }
            }
        }
    }
    catch {
        $scanError = $_.Exception.Message
    }
    finally {
        if ($archive) { $archive.Dispose() }
    }

    $hash = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash
    [PSCustomObject]@{
        FileName   = $File.Name
        FullPath   = $File.FullName
        SizeBytes  = $File.Length
        SHA256     = $hash
        Result     = if ($scanError) { 'Could not fully scan' } elseif ($hits.Count) { 'Review indicators found' } else { 'No indicators found' }
        Indicators = ($hits -join '; ')
        ScanNote   = $scanError
    }
}

Write-Host "ModReview — offline mod folder review" -ForegroundColor Cyan
Write-Host "Folder: $Path"
Write-Host "Scanning JARs (read-only)...`n"

$files = @(Get-ChildItem -LiteralPath $Path -File -Filter '*.jar' | Sort-Object Name)
if ($files.Count -eq 0) {
    Write-Host 'No .jar files found.' -ForegroundColor Yellow
    return
}

$results = @(
    foreach ($file in $files) {
        Write-Host "Scanning $($file.Name)"
        Get-JarReview -File $file
    }
)

$results | Format-Table FileName, Result, SHA256 -AutoSize -Wrap
$flagged = @($results | Where-Object { $_.Result -ne 'No indicators found' })
Write-Host "`nScanned $($results.Count) JAR(s); $($flagged.Count) need review."
Write-Host 'A matching string is not proof of cheating or malware. Review the mod and match context.' -ForegroundColor Yellow

if ($ExportCsv) {
    $csvParent = Split-Path -Parent $ExportCsv
    if ($csvParent -and -not (Test-Path -LiteralPath $csvParent -PathType Container)) {
        throw "CSV output folder does not exist: $csvParent"
    }
    $results | Export-Csv -LiteralPath $ExportCsv -NoTypeInformation -Encoding UTF8
    Write-Host "CSV report saved to: $ExportCsv" -ForegroundColor Green
}

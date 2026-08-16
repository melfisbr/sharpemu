. (Join-Path $PSScriptRoot "common.ps1")
$repo=Find-RepoRoot
$eboot=Get-EbootPath
if(-not (Test-Path -LiteralPath $eboot -PathType Leaf)) { throw "DBFZ eboot missing: $eboot" }
$hash=(Get-FileHash -Algorithm SHA256 -LiteralPath $eboot).Hash.ToLowerInvariant()
if($hash -ne "106b594c4e84401b096ec8b41a088fbf4e3862aee2faf030e4e6767df5cd1018") { throw "Unexpected DBFZ eboot SHA256=$hash" }

$packageRoot=(Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$inventory=Import-Csv -LiteralPath (Join-Path $packageRoot "data\DBFZ_EBOOT_IMPORT_AUDIT.csv")
if($inventory.Count -ne 2766) { throw "Expected 2766 eboot imports; CSV rows=$($inventory.Count)" }

$nidSet=[System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$exportOwners=@{}
$csFiles=@(Get-ChildItem -LiteralPath (Join-Path $repo "src") -Recurse -File -Filter *.cs)
$rx=[regex]'Nid\s*=\s*"([^"]+)"'
foreach($f in $csFiles) {
    $text=Get-Content -LiteralPath $f.FullName -Raw
    foreach($m in $rx.Matches($text)) {
        $nid=$m.Groups[1].Value
        [void]$nidSet.Add($nid)
        if(-not $exportOwners.ContainsKey($nid)) { $exportOwners[$nid]=[System.Collections.Generic.List[string]]::new() }
        $exportOwners[$nid].Add($f.FullName.Substring($repo.Length+1))
    }
}

$rows=[System.Collections.Generic.List[object]]::new()
$present=0
foreach($r in $inventory) {
    $nid=$r.NID
    $has=$nidSet.Contains($nid)
    if($has) { $present++ }
    $owners=if($has) { [string]::Join(';', $exportOwners[$nid]) } else { '' }
    $rows.Add([pscustomobject]@{
        NID=$nid
        FullSymbol=$r.FullSymbol
        RelocationRefCount=$r.RelocationRefCount
        DirectSysAbiExportCurrent=$has
        CurrentSourceFiles=$owners
        PriorStatus=$r.V1_8_12Status
    })
}
$missing=$inventory.Count-$present
$outDir=Join-Path $repo ("DBFZ_EBOOT_SRC_AUDIT_V1_8_14_2_"+(Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$rows | Export-Csv -LiteralPath (Join-Path $outDir "DBFZ_CURRENT_EBOOT_SRC_AUDIT.csv") -NoTypeInformation -Encoding utf8

$critical=@(
    @("hyVLT2VlOYk","sceNgs2ParseWaveformData"),
    @("gEpBkcwxUjw","sceKernelAprResolveFilepathsToIdsAndFileSizes"),
    @("1-LFLmRFxxM","sceKernelMkdir"),
    @("1G3lF1Gg1k8","sceKernelOpen"),
    @("n3kSX62fgNo","Pad unknown identity"),
    @("FzQS6DREDfk","SharePlay unknown identity"),
    @("AQkj7C0f3PY","sceNgs2SystemResetOption"),
    @("5wjxESwX68I","sceShareFeatureProhibit"),
    @("T64o-315wbg","sceShareSetScreenshotOverlayImage")
)
$criticalLines=@()
foreach($c in $critical) {
    $criticalLines += "$($c[0]) $($c[1]) DirectExport=$($nidSet.Contains($c[0]))"
}
$summary=@(
    "Dragon Ball FighterZ EBOOT/SRC Current Audit V1.8.14",
    "EbootSHA256=$hash",
    "EbootUniqueImports=$($inventory.Count)",
    "CurrentDirectSysAbiExports=$present",
    "CurrentNoDirectSysAbiExport=$missing",
    "CurrentCsFiles=$($csFiles.Count)",
    "Critical:"
) + $criticalLines
$summary | Set-Content -LiteralPath (Join-Path $outDir "SUMMARY.txt") -Encoding utf8
Write-Host ($summary -join "`n")
Write-Host "[DBFZ-AUDIT-18142] AUDIT OUTPUT: $outDir"

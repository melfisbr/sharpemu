param([string]$RepositoryRoot=(Get-Location).Path)

. "$PSScriptRoot\common.ps1"

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$rad = Find-RadVideo64 -RepositoryRoot $root -DeepSearch

if ([string]::IsNullOrWhiteSpace($rad)) {
    throw "[V72.4.3.2.31.6] RAD REQUIRED: radvideo64.exe not found."
}

$radRoot = Split-Path -Parent $rad
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$out = Join-Path $root ("SharpEmu_V72_4_3_2_31_6_RAD_RUNTIME_AUDIT_" + $stamp)
New-Item -ItemType Directory -Force -Path $out | Out-Null

Write-Host "[V72.4.3.2.31.6] Auditing installed RAD files for a true in-process decoder path..." -ForegroundColor Cyan
Write-Host ("[V72.4.3.2.31.6] RAD_ROOT=" + $radRoot)

$files = @(
    Get-ChildItem -LiteralPath $radRoot -File -Recurse -ErrorAction SilentlyContinue |
    Sort-Object FullName
)

$rows = foreach ($file in $files) {
    $hash = ""
    try { $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash } catch {}
    [pscustomobject]@{
        Name = $file.Name
        Extension = $file.Extension
        Length = $file.Length
        Version = $file.VersionInfo.FileVersion
        Product = $file.VersionInfo.ProductName
        Company = $file.VersionInfo.CompanyName
        SHA256 = $hash
        FullName = $file.FullName
    }
}

$rows | Export-Csv -LiteralPath (Join-Path $out "RAD_RUNTIME_FILES.csv") -NoTypeInformation -Encoding UTF8

$dlls = @($files | Where-Object { $_.Extension -in @(".dll",".exe") })
$toolCandidates = @(
    (Get-Command dumpbin.exe -ErrorAction SilentlyContinue),
    (Get-Command llvm-readobj.exe -ErrorAction SilentlyContinue),
    (Get-Command objdump.exe -ErrorAction SilentlyContinue)
) | Where-Object { $null -ne $_ }

$exportOut = Join-Path $out "RAD_PE_EXPORTS.txt"
"RAD PE EXPORT AUDIT" | Set-Content -LiteralPath $exportOut -Encoding UTF8
("RAD_ROOT=" + $radRoot) | Add-Content -LiteralPath $exportOut -Encoding UTF8
("PE_FILES=" + $dlls.Count) | Add-Content -LiteralPath $exportOut -Encoding UTF8
("EXPORT_TOOLS_FOUND=" + (($toolCandidates | ForEach-Object Source) -join ";")) | Add-Content -LiteralPath $exportOut -Encoding UTF8

foreach ($file in $dlls) {
    "" | Add-Content -LiteralPath $exportOut
    ("===== " + $file.FullName + " =====") | Add-Content -LiteralPath $exportOut

    $done = $false
    $dumpbin = Get-Command dumpbin.exe -ErrorAction SilentlyContinue
    if ($null -ne $dumpbin) {
        try {
            (& $dumpbin.Source /nologo /exports $file.FullName 2>&1) |
                Add-Content -LiteralPath $exportOut
            $done = $true
        }
        catch {}
    }

    if (-not $done) {
        $llvm = Get-Command llvm-readobj.exe -ErrorAction SilentlyContinue
        if ($null -ne $llvm) {
            try {
                (& $llvm.Source --coff-exports $file.FullName 2>&1) |
                    Add-Content -LiteralPath $exportOut
                $done = $true
            }
            catch {}
        }
    }

    if (-not $done) {
        $objdump = Get-Command objdump.exe -ErrorAction SilentlyContinue
        if ($null -ne $objdump) {
            try {
                (& $objdump.Source -p $file.FullName 2>&1) |
                    Add-Content -LiteralPath $exportOut
                $done = $true
            }
            catch {}
        }
    }

    if (-not $done) {
        "[no PE export tool available on host]" |
            Add-Content -LiteralPath $exportOut
    }
}

$interesting = @(
    $files | Where-Object {
        $_.Name -match '(?i)bink|rad' -or
        $_.Extension -ieq ".dll"
    }
)

$summary = @(
    "SharpEmu V72.4.3.2.31.6 RAD RUNTIME AUDIT",
    "===========================================",
    ("RAD_PLAYER=" + $rad),
    ("RAD_ROOT=" + $radRoot),
    ("TOTAL_FILES=" + $files.Count),
    ("PE_FILES=" + $dlls.Count),
    ("DLL_FILES=" + @($files | Where-Object Extension -ieq ".dll").Count),
    ("INTERESTING_BINK_RAD_FILES=" + $interesting.Count),
    "",
    "INTERESTING FILES:"
)
$summary += @($interesting | ForEach-Object { $_.FullName })

[IO.File]::WriteAllLines(
    (Join-Path $out "SUMMARY.txt"),
    [string[]]$summary,
    (New-Object Text.UTF8Encoding($true)))

$zip = $out + ".zip"
if (Test-Path -LiteralPath $zip) {
    Remove-Item -LiteralPath $zip -Force
}
Compress-Archive -LiteralPath $out -DestinationPath $zip -CompressionLevel Optimal

Get-Content -LiteralPath (Join-Path $out "SUMMARY.txt")
Write-Host ""
Write-Host ("[V72.4.3.2.31.6] RAD RUNTIME AUDIT ZIP: " + $zip) -ForegroundColor Green
Write-Host "[V72.4.3.2.31.6] Send this ZIP back. It determines whether a real in-process RAD/Bink runtime can be integrated without using the external BinkPlay window."

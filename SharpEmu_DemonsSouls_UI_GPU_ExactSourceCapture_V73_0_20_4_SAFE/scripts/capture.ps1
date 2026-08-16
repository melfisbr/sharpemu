param(
    [Parameter(Mandatory=$true)][string]$RepoRoot,
    [string]$Eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$repo=[IO.Path]::GetFullPath($RepoRoot)
$pkg=[IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'..'))

& ([IO.Path]::Combine($pkg,'scripts\validate.ps1'))
& ([IO.Path]::Combine($pkg,'scripts\precheck.ps1')) `
    -RepoRoot $repo `
    -Eboot $Eboot

$base=$null
foreach($candidate in @([IO.Path]::Combine($repo,'src'),$repo)){
    $vp=[IO.Path]::Combine(
        $candidate,
        'SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs')
    $ag=[IO.Path]::Combine(
        $candidate,
        'SharpEmu.Libs\Agc\AgcExports.cs')
    if([IO.File]::Exists($vp) -and [IO.File]::Exists($ag)){
        $base=$candidate
        break
    }
}
if($null -eq $base){throw 'Source layout not recognized.'}

$presenter=[IO.Path]::Combine(
    $base,
    'SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs')
$agc=[IO.Path]::Combine(
    $base,
    'SharpEmu.Libs\Agc\AgcExports.cs')

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$out=Join-Path $repo ("SharpEmu_V73_0_20_4_EXACT_UI_GPU_SOURCE_$stamp")
New-Item -ItemType Directory -Force -Path $out | Out-Null

# Full exact source. No normalization: copied byte-for-byte.
Copy-Item -LiteralPath $presenter -Destination (Join-Path $out 'VulkanVideoPresenter.cs') -Force
Copy-Item -LiteralPath $agc -Destination (Join-Path $out 'AgcExports.cs') -Force

$ph=(Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash
$ah=(Get-FileHash -LiteralPath $agc -Algorithm SHA256).Hash
$eh=(Get-FileHash -LiteralPath $Eboot -Algorithm SHA256).Hash

$summary=@(
    'version=73.0.20.4',
    'mode=read-only-exact-source-capture',
    "eboot_sha256=$eh",
    "presenter_sha256=$ph",
    "agc_sha256=$ah",
    "presenter_bytes=$((Get-Item -LiteralPath $presenter).Length)",
    "agc_bytes=$((Get-Item -LiteralPath $agc).Length)"
)
[IO.File]::WriteAllLines(
    (Join-Path $out 'SUMMARY.txt'),
    $summary,
    [Text.UTF8Encoding]::new($false))

# Focused contexts are supplemental; the full files above are authoritative.
$patterns=@(
    'TryResolveDccMetadataAlias',
    'TryCreateGuestDrawTexture',
    'residentMatches',
    'IsGpuGuestImageAvailable',
    'gpuWriterPending',
    'preferGpuResident',
    'TryBuildUntrackedTextureProbe',
    'MarkTextureContentCached',
    'MaxTrackedGuestImageBytes',
    'unresolved_dcc_cpu_snapshot_suppressed',
    'texture_dcc_alias_hit',
    'texture_dcc_alias_miss'
)

$focus=Join-Path $out 'FOCUSED_CONTEXT.txt'
foreach($p in $patterns){
    Add-Content -LiteralPath $focus -Value ("===== PATTERN: $p =====")
    $hits=@(
        Select-String `
            -LiteralPath @($agc,$presenter) `
            -Pattern $p `
            -SimpleMatch `
            -Context 15,30
    )
    foreach($hit in $hits){
        Add-Content -LiteralPath $focus -Value $hit.ToString()
        Add-Content -LiteralPath $focus -Value ''
    }
}

# Git provenance/diff is useful to reconstruct accumulated changes, but failure
# here is non-fatal (e.g. source not in a git worktree).
try {
    $gitHead=& git -C $repo rev-parse HEAD 2>&1
    [IO.File]::WriteAllLines(
        (Join-Path $out 'GIT_HEAD.txt'),
        [string[]]@($gitHead),
        [Text.UTF8Encoding]::new($false))

    $gitStatus=& git -C $repo status --short 2>&1
    [IO.File]::WriteAllLines(
        (Join-Path $out 'GIT_STATUS.txt'),
        [string[]]@($gitStatus),
        [Text.UTF8Encoding]::new($false))

    $diff=& git -C $repo --no-pager diff -- `
        'src/SharpEmu.Libs/Agc/AgcExports.cs' `
        'src/SharpEmu.Libs/VideoOut/VulkanVideoPresenter.cs' 2>&1
    [IO.File]::WriteAllLines(
        (Join-Path $out 'CURRENT_SOURCE_DIFF.txt'),
        [string[]]@($diff),
        [Text.UTF8Encoding]::new($false))
} catch {
    [IO.File]::WriteAllText(
        (Join-Path $out 'GIT_CAPTURE_ERROR.txt'),
        $_.Exception.Message,
        [Text.UTF8Encoding]::new($false))
}

# Explicit proof this collector did not write either source file.
$phAfter=(Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash
$ahAfter=(Get-FileHash -LiteralPath $agc -Algorithm SHA256).Hash
if($phAfter -ne $ph -or $ahAfter -ne $ah){
    throw 'READ-ONLY INVARIANT FAILED: a source hash changed during capture.'
}

$zip=$out+'.zip'
Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zip -Force

Write-Host '[V73.0.20.4] READ-ONLY CAPTURE PASSED.' -ForegroundColor Green
Write-Host "Presenter unchanged: $phAfter"
Write-Host "AgcExports unchanged: $ahAfter"
Write-Host "[V73.0.20.4] RESULT: $zip" -ForegroundColor Green

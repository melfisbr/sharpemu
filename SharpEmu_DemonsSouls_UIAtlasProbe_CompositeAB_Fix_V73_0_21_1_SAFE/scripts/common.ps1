Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Resolve-SourceBase([string]$RepoRoot) {
    $repo=[IO.Path]::GetFullPath($RepoRoot)
    foreach($candidate in @([IO.Path]::Combine($repo,'src'),$repo)) {
        $vp=[IO.Path]::Combine($candidate,'SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs')
        $ag=[IO.Path]::Combine($candidate,'SharpEmu.Libs\Agc\AgcExports.cs')
        if([IO.File]::Exists($vp) -and [IO.File]::Exists($ag)) {
            return $candidate
        }
    }
    throw 'Source layout not recognized.'
}

function Get-ProbeMethodSlice([string]$Source) {
    $sig='private static bool TryBuildUntrackedTextureProbe('
    $next='private static ulong ComputeSparseSubmittedContentProbe'
    $start=$Source.IndexOf($sig,[StringComparison]::Ordinal)
    if($start -lt 0){ throw 'TryBuildUntrackedTextureProbe signature not found.' }
    if($Source.IndexOf($sig,$start+1,[StringComparison]::Ordinal) -ge 0){
        throw 'TryBuildUntrackedTextureProbe signature is not unique.'
    }
    $end=$Source.IndexOf($next,$start,[StringComparison]::Ordinal)
    if($end -lt 0){ throw 'ComputeSparseSubmittedContentProbe boundary not found.' }
    return [pscustomobject]@{
        Start=$start
        End=$end
        Text=$Source.Substring($start,$end-$start)
    }
}

function New-PatchedPresenter([string]$Source) {
    $slice=Get-ProbeMethodSlice $Source
    if($slice.Text.Contains('SHARPEMU_DEMONSSOULS_LARGE_SPARSE_PROBE_V73_0_21_1') -or
       $slice.Text.Contains('SHARPEMU_DEMONSSOULS_LARGE_SPARSE_PROBE_V73_0_21')) {
        return [pscustomobject]@{ Changed=$false; Text=$Source; Reason='marker-present' }
    }

    $guardPattern='(?ms)(probe\s*=\s*default\s*;\s*if\s*\(\s*texture\.Address\s*==\s*0\s*\|\|\s*byteCount\s*==\s*0\s*)\|\|\s*byteCount\s*>\s*MaxTrackedGuestImageBytes(\s*\))'
    $matches=[Text.RegularExpressions.Regex]::Matches($slice.Text,$guardPattern)
    if($matches.Count -eq 0) {
        if($slice.Text -notmatch 'byteCount\s*>\s*MaxTrackedGuestImageBytes') {
            return [pscustomobject]@{ Changed=$false; Text=$Source; Reason='size-guard-already-absent' }
        }
        throw 'Probe size guard exists but bounded structural form was not recognized.'
    }
    if($matches.Count -ne 1) {
        throw "Probe guard is not unique inside method: $($matches.Count)"
    }

    $replacement='$1)'  # temporary; we replace with evaluator below to keep original spacing
    $newSlice=[Text.RegularExpressions.Regex]::Replace(
        $slice.Text,
        $guardPattern,
        {
            param($m)
            $prefix=$m.Groups[1].Value
            $suffix=$m.Groups[2].Value
            $comment=@"
        // SHARPEMU_DEMONSSOULS_LARGE_SPARSE_PROBE_V73_0_21_1
        // Sparse probing samples only small fixed windows; logical resource
        // size alone must not disable the baseline used for cache coherency.
"@
            # Insert the marker immediately before the if statement, preserving
            # the original probe assignment and indentation.
            $probePos=$prefix.IndexOf('if',[StringComparison]::Ordinal)
            if($probePos -lt 0){ throw 'Internal replacement error: if not found.' }
            $beforeIf=$prefix.Substring(0,$probePos)
            $ifPart=$prefix.Substring($probePos)
            return $beforeIf + $comment + $ifPart + $suffix
        },
        1
    )

    if($newSlice -match 'byteCount\s*>\s*MaxTrackedGuestImageBytes') {
        throw 'Dry-run invariant failed: size guard still present.'
    }
    if(([Text.RegularExpressions.Regex]::Matches(
        $newSlice,
        'SHARPEMU_DEMONSSOULS_LARGE_SPARSE_PROBE_V73_0_21_1')).Count -ne 1) {
        throw 'Dry-run invariant failed: marker count is not 1.'
    }

    $patched=$Source.Substring(0,$slice.Start)+$newSlice+$Source.Substring($slice.End)
    return [pscustomobject]@{ Changed=$true; Text=$patched; Reason='bounded-method-rewrite' }
}

function Write-Utf8NoBom([string]$Path,[string]$Text) {
    [IO.File]::WriteAllText($Path,$Text,[Text.UTF8Encoding]::new($false))
}

function New-SourceCapture([string]$RepoRoot,[string]$Base,[string]$Reason) {
    $repo=[IO.Path]::GetFullPath($RepoRoot)
    $stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
    $dir=[IO.Path]::Combine($repo,"SharpEmu_V73_0_21_1_SOURCE_CAPTURE_$stamp")
    [IO.Directory]::CreateDirectory($dir) | Out-Null

    $files=@(
        [IO.Path]::Combine($Base,'SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'),
        [IO.Path]::Combine($Base,'SharpEmu.Libs\Agc\AgcExports.cs')
    )
    foreach($f in $files) {
        if([IO.File]::Exists($f)) {
            [IO.File]::Copy($f,[IO.Path]::Combine($dir,[IO.Path]::GetFileName($f)),$true)
        }
    }

    $presenter=[IO.Path]::Combine($Base,'SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs')
    $agc=[IO.Path]::Combine($Base,'SharpEmu.Libs\Agc\AgcExports.cs')
    $lines=@(
        'version=73.0.21.1',
        "reason=$Reason",
        "presenter_sha256=$((Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash)",
        "agc_sha256=$((Get-FileHash -LiteralPath $agc -Algorithm SHA256).Hash)"
    )
    [IO.File]::WriteAllLines(
        [IO.Path]::Combine($dir,'SUMMARY.txt'),
        $lines,
        [Text.UTF8Encoding]::new($false))

    try {
        $src=[IO.File]::ReadAllText($presenter)
        $slice=Get-ProbeMethodSlice $src
        Write-Utf8NoBom ([IO.Path]::Combine($dir,'TryBuildUntrackedTextureProbe.txt')) $slice.Text
    } catch {
        Write-Utf8NoBom ([IO.Path]::Combine($dir,'METHOD_CAPTURE_ERROR.txt')) $_.Exception.ToString()
    }

    $zip=$dir+'.zip'
    Compress-Archive -Path ([IO.Path]::Combine($dir,'*')) -DestinationPath $zip -Force
    Write-Host "[V73.0.21.1] SOURCE CAPTURE: $zip" -ForegroundColor Yellow
    return $zip
}

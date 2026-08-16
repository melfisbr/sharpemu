Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Resolve-RepoRootV730221 {
    param([string]$RepositoryRoot="")
    if([string]::IsNullOrWhiteSpace($RepositoryRoot)){
        $RepositoryRoot=(Get-Location).Path
    }
    $repo=[IO.Path]::GetFullPath($RepositoryRoot)
    $marker=[IO.Path]::Combine($repo,'src','SharpEmu.CLI','SharpEmu.CLI.csproj')
    if(-not [IO.File]::Exists($marker)){
        throw "[V73.0.22.1] Repository root invalid: $repo"
    }
    return $repo
}

function Get-AgcPathV730221 {
    param([string]$Root)
    $path=[IO.Path]::Combine($Root,'src','SharpEmu.Libs','Agc','AgcExports.cs')
    if(-not [IO.File]::Exists($path)){
        throw "[V73.0.22.1] Missing AgcExports.cs: $path"
    }
    return $path
}

function Get-PresenterPathV730221 {
    param([string]$Root)
    return [IO.Path]::Combine(
        $Root,'src','SharpEmu.Libs','VideoOut','VulkanVideoPresenter.cs')
}

function Get-CompositeMergeStateV730221 {
    param([string]$Text)
    $oldSuppress='if (hasCurrentFrameDisplayWriter && !_replayTargetlessComposites)'
    $oldReplay='if (_replayTargetlessComposites && hasCurrentFrameDisplayWriter)'

    $newSuppress=@'
if (hasCurrentFrameDisplayWriter &&
                            !_replayTargetlessComposites &&
                            !KernelMemoryCompatExports.IsConfiguredApplicationTitle("PPSA01341"))
'@.Trim()

    $newReplay=@'
if ((_replayTargetlessComposites ||
                             KernelMemoryCompatExports.IsConfiguredApplicationTitle("PPSA01341")) &&
                            hasCurrentFrameDisplayWriter)
'@.Trim()

    $oldSuppressCount=([regex]::Matches(
        $Text,[regex]::Escape($oldSuppress))).Count
    $oldReplayCount=([regex]::Matches(
        $Text,[regex]::Escape($oldReplay))).Count
    $newSuppressCount=([regex]::Matches(
        $Text,[regex]::Escape($newSuppress))).Count
    $newReplayCount=([regex]::Matches(
        $Text,[regex]::Escape($newReplay))).Count

    if($newSuppressCount -eq 1 -and
       $newReplayCount -eq 1 -and
       $oldSuppressCount -eq 0 -and
       $oldReplayCount -eq 0){
        return 'Applied'
    }

    if($oldSuppressCount -eq 1 -and
       $oldReplayCount -eq 1 -and
       $newSuppressCount -eq 0 -and
       $newReplayCount -eq 0){
        return 'Baseline'
    }

    return "Unsupported(oldSuppress=$oldSuppressCount oldReplay=$oldReplayCount newSuppress=$newSuppressCount newReplay=$newReplayCount)"
}

function Convert-AgcCompositeMergeV730221 {
    param([string]$Text)

    $state=Get-CompositeMergeStateV730221 -Text $Text
    if($state -eq 'Applied'){
        return $Text
    }
    if($state -ne 'Baseline'){
        throw "[V73.0.22.1] AGC merge state is $state"
    }

    $oldSuppress='if (hasCurrentFrameDisplayWriter && !_replayTargetlessComposites)'
    $oldReplay='if (_replayTargetlessComposites && hasCurrentFrameDisplayWriter)'

    $newSuppress=@'
if (hasCurrentFrameDisplayWriter &&
                            !_replayTargetlessComposites &&
                            !KernelMemoryCompatExports.IsConfiguredApplicationTitle("PPSA01341"))
'@.Trim()

    $newReplay=@'
if ((_replayTargetlessComposites ||
                             KernelMemoryCompatExports.IsConfiguredApplicationTitle("PPSA01341")) &&
                            hasCurrentFrameDisplayWriter)
'@.Trim()

    $beforeOpen=([regex]::Matches($Text,[regex]::Escape('{'))).Count
    $beforeClose=([regex]::Matches($Text,[regex]::Escape('}'))).Count

    $patched=$Text.Replace($oldSuppress,$newSuppress)
    $patched=$patched.Replace($oldReplay,$newReplay)

    $afterState=Get-CompositeMergeStateV730221 -Text $patched
    if($afterState -ne 'Applied'){
        throw "[V73.0.22.1] In-memory merge verification failed: $afterState"
    }

    $afterOpen=([regex]::Matches($patched,[regex]::Escape('{'))).Count
    $afterClose=([regex]::Matches($patched,[regex]::Escape('}'))).Count
    if($beforeOpen -ne $afterOpen -or $beforeClose -ne $afterClose){
        throw '[V73.0.22.1] In-memory merge changed brace count.'
    }

    foreach($preserved in @(
        'CanonicalMemory(',
        'RecordProducedLabelsInRange(',
        'SubmitOrderedGuestActionAfterQueueCompletion('
    )){
        if($Text.Contains($preserved) -and -not $patched.Contains($preserved)){
            throw "[V73.0.22.1] Preserved AGC feature disappeared: $preserved"
        }
    }

    if($Text.Contains('SHARPEMU_V74_0_25_WRITE_DATA_PACKET_POSITION') -and
       -not $patched.Contains('SHARPEMU_V74_0_25_WRITE_DATA_PACKET_POSITION')){
        throw '[V73.0.22.1] V74.0.25 marker was not preserved.'
    }

    return $patched
}

function Get-Utf8Sha256V730221 {
    param([string]$Text)
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes($Text)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{
        return (($sha.ComputeHash($bytes) |
            ForEach-Object {$_.ToString('X2')}) -join '')
    } finally {
        $sha.Dispose()
    }
}

function New-AgcCaptureV730221 {
    param(
        [string]$Root,
        [string]$AgcPath,
        [string]$Reason
    )
    $stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
    $dir=[IO.Path]::Combine(
        $Root,
        "SharpEmu_V73_0_22_1_AGC_CAPTURE_$stamp")
    [IO.Directory]::CreateDirectory($dir) | Out-Null

    [IO.File]::Copy(
        $AgcPath,
        [IO.Path]::Combine($dir,'AgcExports.cs'),
        $true)

    $hash=(Get-FileHash -LiteralPath $AgcPath -Algorithm SHA256).Hash
    [IO.File]::WriteAllLines(
        [IO.Path]::Combine($dir,'SUMMARY.txt'),
        [string[]]@(
            'version=73.0.22.1',
            "reason=$Reason",
            "agc_sha256=$hash"
        ),
        [Text.UTF8Encoding]::new($false))

    $zip=$dir+'.zip'
    Compress-Archive `
        -Path ([IO.Path]::Combine($dir,'*')) `
        -DestinationPath $zip `
        -Force

    Write-Host "[V73.0.22.1] AGC CAPTURE: $zip" -ForegroundColor Yellow
    return $zip
}

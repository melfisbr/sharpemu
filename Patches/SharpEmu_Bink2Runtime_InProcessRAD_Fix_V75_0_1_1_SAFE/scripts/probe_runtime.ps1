param([string]$RuntimeDll='')
. (Join-Path $PSScriptRoot 'common.ps1')

$explicitRequested=
    -not[string]::IsNullOrWhiteSpace($RuntimeDll)

$candidates=@(Get-RuntimeCandidates $RuntimeDll)
if($candidates.Count -eq 0){
    $state=Write-RuntimeState @{
        runtime_found=$false
        runtime_dll=''
        runtime_sha256=''
        runtime_machine=''
        runtime_exports=''
        runtime_probe_status='not-found'
        runtime_mode='external-rad-fallback'
        probed_at=(Get-Date).ToString('o')
    }

    Write-Tag 'BinkRuntimeCandidate=NOT_FOUND'
    Write-Tag 'ProbeResult=NON_FATAL'
    Write-Tag 'AdapterCanStillBuild=True'
    Write-Tag 'RuntimeMode=external-rad-fallback'
    Write-Host ''
    Write-Host 'Nenhum bink2w64.dll x64 compativel foi encontrado.'
    Write-Host 'Isso NAO bloqueia mais RUN_3: o adapter sera compilado/deployado e o SharpEmu preservara o fallback RAD externo.'
    Write-Host ''
    Write-Host 'Para ativar o decoder RAD in-process, use um bink2w64.dll x64 legitimamente obtido:'
    Write-Host "  $script:PackageRoot\ThirdParty\BinkRuntime\bink2w64.dll"
    Write-Host 'ou:'
    Write-Host '  $env:SHARPEMU_BINK_RUNTIME_DLL = "C:\caminho\bink2w64.dll"'
    exit 0
}

$accepted=$null
foreach($candidate in $candidates){
    $runtimeProbe=Test-BinkRuntime $candidate
    $machineText=
        if($runtimeProbe.Machine -eq 0x8664){'x64'}
        elseif($runtimeProbe.Machine -eq 0x014C){'x86'}
        else{('0x{0:X4}' -f $runtimeProbe.Machine)}

    Write-Tag "RuntimeCandidate='$($runtimeProbe.Path)' machine=$machineText exports_ok=$($runtimeProbe.ExportsOk) exports='$($runtimeProbe.Exports)'"

    if($runtimeProbe.IsX64 -and
       $runtimeProbe.ExportsOk -and
       $null -eq $accepted){
        $accepted=$runtimeProbe.Path
    }
}

if($null -eq $accepted){
    $state=Write-RuntimeState @{
        runtime_found=$false
        runtime_dll=''
        runtime_sha256=''
        runtime_machine=''
        runtime_exports=''
        runtime_probe_status='candidates-incompatible'
        runtime_mode='external-rad-fallback'
        probed_at=(Get-Date).ToString('o')
    }

    Write-Tag 'CompatibleRuntime=NOT_FOUND'
    Write-Tag 'AdapterCanStillBuild=True'
    Write-Tag 'RuntimeMode=external-rad-fallback'
    Write-Host 'Necessario para native RAD: PE x64 + BinkOpen/BinkClose/BinkWait/BinkDoFrame/BinkCopyToBuffer/BinkNextFrame.'

    if($explicitRequested){
        exit 3
    }
    exit 0
}

$state=Write-RuntimeState @{
    runtime_found=$true
    runtime_dll=$accepted
    runtime_sha256=(Get-Sha $accepted)
    runtime_machine='x64'
    runtime_exports='BinkOpen,BinkClose,BinkWait,BinkDoFrame,BinkCopyToBuffer,BinkNextFrame'
    runtime_probe_status='compatible'
    runtime_mode='native-rad-ready'
    probed_at=(Get-Date).ToString('o')
}
Write-Tag "CompatibleRuntime='$accepted'"
Write-Tag "RuntimeSHA256=$($state.runtime_sha256)"
Write-Tag 'RuntimeMode=native-rad-ready'
Write-Tag 'RUNTIME PROBE PASSED'

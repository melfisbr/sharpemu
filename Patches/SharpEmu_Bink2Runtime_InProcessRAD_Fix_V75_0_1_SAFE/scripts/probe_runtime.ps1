param([string]$RuntimeDll='')
. (Join-Path $PSScriptRoot 'common.ps1')

$candidates=@(Get-RuntimeCandidates $RuntimeDll)
if($candidates.Count -eq 0){
    Write-Tag 'BinkRuntimeCandidate=NOT_FOUND'
    Write-Host ''
    Write-Host 'Coloque um bink2w64.dll x64 legitimamente obtido em:'
    Write-Host "  $script:PackageRoot\ThirdParty\BinkRuntime\bink2w64.dll"
    Write-Host 'ou defina:'
    Write-Host '  $env:SHARPEMU_BINK_RUNTIME_DLL = "C:\caminho\bink2w64.dll"'
    exit 2
}

$accepted=$null
foreach($candidate in $candidates){
    $probe=Test-BinkRuntime $candidate
    $machineText=
        if($probe.Machine -eq 0x8664){'x64'}
        elseif($probe.Machine -eq 0x014C){'x86'}
        else{('0x{0:X4}' -f $probe.Machine)}

    Write-Tag "RuntimeCandidate='$($probe.Path)' machine=$machineText exports_ok=$($probe.ExportsOk) exports='$($probe.Exports)'"

    if($probe.IsX64 -and $probe.ExportsOk -and $null -eq $accepted){
        $accepted=$probe.Path
    }
}

if($null -eq $accepted){
    Write-Tag 'CompatibleRuntime=NOT_FOUND'
    Write-Host 'Necessario: PE x64 + BinkOpen/BinkClose/BinkWait/BinkDoFrame/BinkCopyToBuffer/BinkNextFrame.'
    exit 3
}

$state=[ordered]@{
    version=$script:Version
    runtime_dll=$accepted
    runtime_sha256=(Get-Sha $accepted)
    runtime_machine='x64'
    runtime_exports='BinkOpen,BinkClose,BinkWait,BinkDoFrame,BinkCopyToBuffer,BinkNextFrame'
    probed_at=(Get-Date).ToString('o')
}
$state|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Get-StatePath) -Encoding UTF8
Write-Tag "CompatibleRuntime='$accepted'"
Write-Tag "RuntimeSHA256=$($state.runtime_sha256)"
Write-Tag 'RUNTIME PROBE PASSED'

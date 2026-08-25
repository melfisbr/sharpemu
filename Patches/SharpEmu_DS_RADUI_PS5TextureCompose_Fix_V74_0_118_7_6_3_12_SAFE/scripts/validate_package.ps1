param()
. (Join-Path $PSScriptRoot 'common.ps1')

$manifest=Join-Path $script:PackageRoot 'manifest.sha256'
if(-not(Test-Path -LiteralPath $manifest)){throw "$script:Tag manifest missing"}

$entries=@(
    Get-Content -LiteralPath $manifest |
        Where-Object{$_ -and (-not $_.StartsWith('#'))}
)
foreach($line in $entries){
    if($line -notmatch '^([0-9A-Fa-f]{64})  (.+)$'){
        throw "$script:Tag malformed manifest: $line"
    }
    $expected=$matches[1].ToUpperInvariant()
    $path=Join-Path $script:PackageRoot $matches[2].Replace('/','\')
    if(-not(Test-Path -LiteralPath $path)){
        throw "$script:Tag manifest file missing: $path"
    }
    $actual=(Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToUpperInvariant()
    if($actual -ne $expected){
        throw "$script:Tag manifest mismatch: $path"
    }
}

$parseFailures=[string[]]@()
foreach($file in Get-ChildItem -LiteralPath $PSScriptRoot -File -Filter '*.ps1'){
    $tokens=$null
    $parseErrors=$null
    [void][Management.Automation.Language.Parser]::ParseFile(
        $file.FullName,[ref]$tokens,[ref]$parseErrors)
    if(@($parseErrors).Count -ne 0){
        $parseFailures += "$($file.Name):$(($parseErrors|ForEach-Object{$_.Message}) -join '; ')"
    }
}
if($parseFailures.Count -ne 0){
    throw "$script:Tag PowerShell parse failed: $($parseFailures -join ' | ')"
}

$hostPayload=Get-HostPayload
$presenterPayload=Get-PresenterPayload

if((Get-Sha $hostPayload) -ne $script:PayloadHostApiSha){
    throw "$script:Tag HostApi payload SHA mismatch"
}
if((Get-Sha $presenterPayload) -ne $script:PayloadPresenterSha){
    throw "$script:Tag Presenter payload SHA mismatch"
}

$hostText=[IO.File]::ReadAllText($hostPayload)
$presenterText=[IO.File]::ReadAllText($presenterPayload)

foreach($marker in @(
    'SHARPEMU_V74_0_118_7_6_3_12_RAD_UI_TEXTURE_CAPTURE',
    '[V74.0.118.7.6.3.12][RAD_UI_TEXTURE_CAPTURE_ROUTE]',
    '[V74.0.118.7.6.3.12][RAD_UI_TEXTURE_CAPTURE_REGION]',
    '[V74.0.118.7.6.3.12][RAD_UI_CHILD_CLOAK]')){
    if(-not$hostText.Contains($marker)){
        throw "$script:Tag HostApi payload marker missing: $marker"
    }
}

foreach($marker in @(
    'SHARPEMU_V74_0_118_7_6_3_12_RAD_UI_TEXTURE_CAPTURE',
    '[V74.0.118.7.6.3.12][RAD_UI_CAPTURE_IMPORT]',
    '[V74.0.118.7.6.3.12][RAD_UI_CAPTURE_BIND]',
    '[V74.0.118.7.6.3.12][RAD_UI_DESCRIPTORLESS_KEEP_GUEST]',
    '[V74.0.118.7.6.3.12][RAD_UI_TEXTURE_GUEST_PRESENT]')){
    if(-not$presenterText.Contains($marker)){
        throw "$script:Tag Presenter payload marker missing: $marker"
    }
}

Invoke-CSharpSyntaxProbe $hostPayload 'RadHostV11876312'
Invoke-CSharpSyntaxProbe $presenterPayload 'PresenterV11876312'

Write-Tag "PACKAGE VALIDATION PASSED ($($entries.Count) hashed files; PowerShell parsed; C# syntax preflight passed)."

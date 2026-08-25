$ErrorActionPreference='Stop'
$packageRoot=Split-Path -Parent $PSScriptRoot
$manifest=Join-Path $packageRoot 'manifest.sha256'
if(-not(Test-Path -LiteralPath $manifest -PathType Leaf)){throw 'manifest.sha256 ausente'}
$entries=Get-Content -LiteralPath $manifest | Where-Object {$_ -and -not $_.StartsWith('#')}
foreach($entry in $entries){
    if($entry -notmatch '^([0-9a-fA-F]{64})  (.+)$'){throw "manifest entry invalida: $entry"}
    $expected=$Matches[1].ToLowerInvariant(); $rel=$Matches[2].Replace('/','\\')
    $path=Join-Path $packageRoot $rel
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "manifest file ausente: $rel"}
    $actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if($actual -ne $expected){throw "hash mismatch: $rel"}
}
$psFiles=Get-ChildItem -LiteralPath (Join-Path $packageRoot 'scripts') -Filter '*.ps1' -File
foreach($file in $psFiles){
    $tokens=$null; $parseErrors=$null
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$parseErrors) | Out-Null
    if($parseErrors.Count -gt 0){throw "PowerShell parse failure: $($file.Name): $($parseErrors[0].Message)"}
    $text=[IO.File]::ReadAllText($file.FullName)
    if($text -match '(?im)^\s*\$(Host|Error|Matches|Args|Input|This|PSItem|PID|PWD|HOME)\s*='){
        throw "read-only/automatic variable assignment: $($file.Name):$($Matches[1])"
    }
    if($file.Name -ne 'validate.ps1' -and $text -match '(?i)Invoke-WebRequest|Invoke-RestMethod|Start-BitsTransfer|curl(?:\.exe)?\s|wget(?:\.exe)?\s'){
        throw "package script contains direct network downloader: $($file.Name)"
    }
}
$helper=Join-Path $packageRoot 'payload\src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.DsPermuteV7625.cs'
$helperText=[IO.File]::ReadAllText($helper)
foreach($contract in @('TryEmitDsPermuteB32V7625','DsBpermuteB32','GroupNonUniformShuffle','Load(_boolType, _exec)','UInt(31)','[V76.0.25][RDNA2-DS-PERMUTE]')){
    if($helperText.IndexOf($contract,[System.StringComparison]::Ordinal) -lt 0){throw "helper contract ausente: $contract"}
}
Write-Host "[V76.0.25-OFW-RDNA2-BINK-CROSSLANE-DECODE] PACKAGE VALIDATION PASSED ($($entries.Count) hashed files; PowerShell parsed; RDNA2 guest Bink contracts passed)."

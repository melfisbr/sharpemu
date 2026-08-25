param()
. (Join-Path $PSScriptRoot 'common.ps1')
$manifest=Join-Path $script:PackageRoot 'manifest.sha256'
if(-not(Test-Path -LiteralPath $manifest)){throw "$script:Tag manifest missing"}
$entries=@(Get-Content -LiteralPath $manifest|Where-Object{$_ -and -not $_.StartsWith('#')})
foreach($line in $entries){
    if($line -notmatch '^([0-9A-Fa-f]{64})  (.+)$'){throw "$script:Tag malformed manifest: $line"}
    $expected=$matches[1].ToUpperInvariant(); $rel=$matches[2]
    $path=Join-Path $script:PackageRoot $rel.Replace('/','\')
    if(-not(Test-Path -LiteralPath $path)){throw "$script:Tag manifest file missing: $path"}
    $actual=Get-Sha $path
    if($actual -ne $expected){throw "$script:Tag manifest mismatch: $rel expected=$expected actual=$actual"}
}
$parseFailures=@()
foreach($file in Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File){
    $tokens=$null; $parseErrors=$null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$parseErrors)
    if(@($parseErrors).Count -ne 0){$parseFailures += "$($file.Name):$(($parseErrors|ForEach-Object{$_.Message}) -join '; ')"}
}
if($parseFailures.Count -ne 0){throw "$script:Tag PowerShell parse failed: $($parseFailures -join ' | ')"}
$automatic=@('Host','Error','Home','Input','Args','PID','PSHOME','PWD','ShellId','StackTrace')
foreach($file in Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File){
    $text=[IO.File]::ReadAllText($file.FullName)
    foreach($name in $automatic){
        $pattern='(?im)(?<![\w:])\$'+[regex]::Escape($name)+'\s*(?:=|\+=|-=|\*=|/=|%=|\+\+|--)'
        if([regex]::IsMatch($text,$pattern)){throw "$script:Tag reserved automatic variable assignment: $($file.Name):`$$name"}
    }
}
Assert-Payloads
foreach($marker in @(
 'SHARPEMU_V74_0_118_7_6_3_12_RAD_UI_TEXTURE_INJECTION',
 '[V74.0.118.7.6.3.12][RAD_UI_DESCRIPTORLESS_SUPPRESS]',
 '[V74.0.118.7.6.3.12][RAD_UI_TEXTURE_VIDEOOUT_PRESENT]',
 '[V74.0.118.7.6.3.12][RAD_UI_TEXTURE_SOURCE]')){
    $found=$false
    foreach($entry in $script:Files.GetEnumerator()){
        if([IO.File]::ReadAllText((Get-PayloadPath $entry.Value.Rel)).Contains($marker)){$found=$true;break}
    }
    if(-not$found){throw "$script:Tag required V3.12 marker missing: $marker"}
}
Write-Tag "PACKAGE VALIDATION PASSED ($($entries.Count) hashed files; 3 exact source payloads; PowerShell parsed; C# syntax probes passed)."

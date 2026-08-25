param()
. (Join-Path $PSScriptRoot 'common.ps1')

$manifest=Join-Path $script:PackageRoot 'manifest.sha256'
if(-not(Test-Path -LiteralPath $manifest -PathType Leaf)){throw "$script:Tag manifest missing"}
$entries=@(Get-Content -LiteralPath $manifest|Where-Object{$_ -and (-not $_.StartsWith('#'))})
foreach($line in $entries){
    if($line -notmatch '^([0-9A-Fa-f]{64})  (.+)$'){throw "$script:Tag malformed manifest: $line"}
    $expected=$matches[1].ToUpperInvariant()
    $path=Join-Path $script:PackageRoot $matches[2].Replace('/','\')
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "$script:Tag manifest file missing: $path"}
    $actual=(Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToUpperInvariant()
    if($actual -ne $expected){throw "$script:Tag manifest mismatch: $path"}
}

$parseFailures=@()
foreach($file in Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File){
    $tokens=$null;$parseErrors=$null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$parseErrors)
    if(@($parseErrors).Count -ne 0){
        $parseFailures += "$($file.Name):$(($parseErrors|ForEach-Object{$_.Message}) -join '; ')"
    }
}
if($parseFailures.Count -ne 0){throw "$script:Tag PowerShell parse failed: $($parseFailures -join ' | ')"}

$pairs=@(Get-TransformPairs)
if($pairs.Count -ne 2){throw "$script:Tag expected 2 HostMovieBridge transforms; got $($pairs.Count)"}
$combined=''
foreach($pair in $pairs){
    $old=[IO.File]::ReadAllText($pair.Old)
    $new=[IO.File]::ReadAllText($pair.New)
    if([string]::IsNullOrWhiteSpace($old) -or [string]::IsNullOrWhiteSpace($new) -or $old -eq $new){
        throw "$script:Tag invalid transform $($pair.Id)"
    }
    $combined += $new
}
foreach($marker in @(
    'SHARPEMU_V75_0_1_3_EXTERNAL_RAD_COMPATIBILITY_FORCE',
    'SHARPEMU_V75_0_1_3_NATIVE_RAD_CASE_EXTERNALIZED',
    '[V75.0.1.3][RAD_EXTERNAL_FORCE]',
    '[V75.0.1.3][RAD_EXTERNAL_FORCE_CASE]')){
    if(-not$combined.Contains($marker)){throw "$script:Tag transform marker missing: $marker"}
}

$preview=Join-Path $script:PackageRoot 'tests\HostMovieBridge.v75013.preview.cs'
if((Get-Sha $preview) -ne $script:PreviewHostSha){throw "$script:Tag preview SHA mismatch"}
Write-Tag "PACKAGE VALIDATION PASSED ($($entries.Count) hashed files; 2 bounded HostMovieBridge transforms; PowerShell parsed)."

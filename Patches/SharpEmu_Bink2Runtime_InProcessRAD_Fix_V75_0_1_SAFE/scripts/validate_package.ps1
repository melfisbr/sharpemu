param()
. (Join-Path $PSScriptRoot 'common.ps1')

$manifest=Join-Path $script:PackageRoot 'manifest.sha256'
if(-not(Test-Path -LiteralPath $manifest)){ throw "$script:Tag manifest missing" }
$entries=@(Get-Content -LiteralPath $manifest|Where-Object{$_ -and (-not $_.StartsWith('#'))})
foreach($line in $entries){
    if($line -notmatch '^([0-9A-Fa-f]{64})  (.+)$'){ throw "$script:Tag malformed manifest: $line" }
    $expected=$matches[1].ToUpperInvariant()
    $path=Join-Path $script:PackageRoot $matches[2].Replace('/','\')
    if(-not(Test-Path -LiteralPath $path)){ throw "$script:Tag manifest file missing: $path" }
    $actual=(Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToUpperInvariant()
    if($actual -ne $expected){ throw "$script:Tag manifest mismatch: $path" }
}

$parseFailures=@()
foreach($file in Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File){
    $tokens=$null
    $parseErrors=$null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$parseErrors)
    if(@($parseErrors).Count -ne 0){
        $parseFailures += "$($file.Name):$(($parseErrors|ForEach-Object{$_.Message}) -join '; ')"
    }
}
if($parseFailures.Count -ne 0){ throw "$script:Tag PowerShell parse failed: $($parseFailures -join ' | ')" }

$source=Get-AdapterSource
$text=[IO.File]::ReadAllText($source)
foreach($marker in @(
    'se_bink_abi_version',
    'se_bink_open_utf8',
    'se_bink_decode_bgra',
    'SHARPEMU_BINK_RUNTIME_DLL',
    'BinkCopyToBuffer',
    'kCopyAll',
    'kDefaultSurfaceBgra')){
    if(-not$text.Contains($marker)){ throw "$script:Tag native source marker missing: $marker" }
}

Write-Tag "PACKAGE VALIDATION PASSED ($($entries.Count) hashed files; PowerShell parsed; native source markers passed)."

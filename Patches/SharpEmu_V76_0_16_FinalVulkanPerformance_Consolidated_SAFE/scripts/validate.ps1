param()
. (Join-Path $PSScriptRoot 'common.ps1')
$manifest=Join-Path $PackageRoot 'manifest.sha256'
if(-not(Test-Path -LiteralPath $manifest -PathType Leaf)){throw 'manifest.sha256 ausente.'}
$lines=Get-Content -LiteralPath $manifest | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
foreach($line in $lines){
    if($line -notmatch '^([0-9a-f]{64})  (.+)$'){throw "Linha de manifest invalida: $line"}
    $expected=$Matches[1]; $rel=$Matches[2].Replace('/','\'); $path=Join-Path $PackageRoot $rel
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Arquivo do manifest ausente: $rel"}
    $actual=Get-Sha256 $path
    if($actual -ne $expected){throw "Hash mismatch: $rel expected=$expected actual=$actual"}
}
# Parse every PowerShell script before allowing apply.
foreach($script in Get-ChildItem -LiteralPath (Join-Path $PackageRoot 'scripts') -Filter '*.ps1' -File){
    $tokens=$null; $errors=$null
    [System.Management.Automation.Language.Parser]::ParseFile($script.FullName,[ref]$tokens,[ref]$errors) | Out-Null
    if($errors.Count -ne 0){throw "PowerShell parse failed: $($script.Name): $($errors[0].Message)"}
}
# Network-downloader audit for package scripts, excluding this validator so the detector never scans its own signatures.
$networkSignatures=@('Invoke-'+'WebRequest','Start-'+'BitsTransfer','curl'+'.exe','wget'+'.exe')
foreach($script in Get-ChildItem -LiteralPath $PackageRoot -Recurse -File | Where-Object { $_.Extension -in @('.ps1','.cmd') -and $_.FullName -ne $PSCommandPath }){
    $text=Read-Text $script.FullName
    foreach($signature in $networkSignatures){if($text.IndexOf($signature,[System.StringComparison]::OrdinalIgnoreCase) -ge 0){throw "Downloader de rede proibido: $($script.FullName)"}}
}
foreach($spec in $HelperSpecs){
    $payload=Join-Path $PackageRoot $spec.Payload
    if(-not(Test-Path -LiteralPath $payload -PathType Leaf)){throw "Payload helper ausente: $($spec.Payload)"}
}
for($i=1;$i -le 15;$i++){foreach($suffix in @('old','new')){if(-not(Test-Path -LiteralPath (Join-Path $PackageRoot ("patchdata\presenter_{0:d2}.{1}.txt" -f $i,$suffix)))){throw "Patchdata presenter ausente $i $suffix"}}}
for($i=1;$i -le 14;$i++){foreach($suffix in @('old','new')){if(-not(Test-Path -LiteralPath (Join-Path $PackageRoot ("patchdata\detile_{0:d2}.{1}.txt" -f $i,$suffix)))){throw "Patchdata detile ausente $i $suffix"}}}
Write-Host "[$PackageTag] PACKAGE VALIDATION PASSED ($($lines.Count) hashed files; PowerShell parsed; 29 adaptive patches + 4 helpers passed)."

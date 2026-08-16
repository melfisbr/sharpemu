param([string]$PackageRoot = "")
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if([string]::IsNullOrWhiteSpace($PackageRoot)){
    $PackageRoot=[System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot,".."))
}else{$PackageRoot=[System.IO.Path]::GetFullPath($PackageRoot)}
$manifestPath=[System.IO.Path]::Combine($PackageRoot,"SHA256SUMS.txt")
if(-not [System.IO.File]::Exists($manifestPath)){throw "[V74.0.26] Missing SHA256SUMS.txt"}

$manifestEntries=@{}
foreach($manifestLine in [System.IO.File]::ReadAllLines($manifestPath)){
    if([string]::IsNullOrWhiteSpace($manifestLine)){continue}
    $manifestMatch=[regex]::Match($manifestLine,'^([0-9A-Fa-f]{64})\s{2}(.+)$')
    if(-not $manifestMatch.Success){throw "[V74.0.26] Invalid manifest line: $manifestLine"}
    $relativePath=$manifestMatch.Groups[2].Value.Replace('/','\')
    if($manifestEntries.ContainsKey($relativePath)){throw "[V74.0.26] Duplicate manifest path: $relativePath"}
    $manifestEntries[$relativePath]=$manifestMatch.Groups[1].Value.ToUpperInvariant()
}
$actualFiles=@(Get-ChildItem -LiteralPath $PackageRoot -Recurse -File | Where-Object {$_.FullName -ne $manifestPath})
if($manifestEntries.Count -ne $actualFiles.Count){throw "[V74.0.26] Manifest coverage mismatch: manifest=$($manifestEntries.Count) actual=$($actualFiles.Count)"}
foreach($actualFile in $actualFiles){
    $relativePath=$actualFile.FullName.Substring($PackageRoot.Length).TrimStart('\')
    if(-not $manifestEntries.ContainsKey($relativePath)){throw "[V74.0.26] File missing from manifest: $relativePath"}
    $actualHash=(Get-FileHash -LiteralPath $actualFile.FullName -Algorithm SHA256).Hash.ToUpperInvariant()
    if($actualHash -ne $manifestEntries[$relativePath]){throw "[V74.0.26] SHA256 mismatch: $relativePath"}
}

$parseFailures=New-Object 'System.Collections.Generic.List[string]'
$reservedNames=@("Host","Args","PID","Matches","Input","Error","PSItem","This")
foreach($scriptFile in @(Get-ChildItem -LiteralPath ([System.IO.Path]::Combine($PackageRoot,"scripts")) -Filter "*.ps1" -File)){
    $tokens=$null
    $parseErrors=$null
    $scriptAst=[System.Management.Automation.Language.Parser]::ParseFile($scriptFile.FullName,[ref]$tokens,[ref]$parseErrors)
    if($parseErrors.Count -gt 0){
        foreach($parseError in $parseErrors){$parseFailures.Add("$($scriptFile.Name):$($parseError.Extent.StartLineNumber): $($parseError.Message)")}
        continue
    }
    $assignments=$scriptAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst]
    },$true)
    foreach($assignment in $assignments){
        if($assignment.Left -is [System.Management.Automation.Language.VariableExpressionAst]){
            $variableName=$assignment.Left.VariablePath.UserPath
            if($reservedNames -contains $variableName){$parseFailures.Add("$($scriptFile.Name): assignment to reserved automatic variable: $variableName")}
        }
    }
}
if($parseFailures.Count -gt 0){throw "[V74.0.26] PowerShell validation failed:`n$([string]::Join("`n",@($parseFailures)))"}

$cmdFiles=@(Get-ChildItem -LiteralPath $PackageRoot -Filter "RUN_*.cmd" -File)
if($cmdFiles.Count -ne 4){throw "[V74.0.26] Expected 4 RUN_*.cmd files; found $($cmdFiles.Count)"}
foreach($cmdFile in $cmdFiles){
    $cmdText=[System.IO.File]::ReadAllText($cmdFile.FullName)
    $targetMatches=[regex]::Matches($cmdText,'(?i)scripts\\([A-Za-z0-9_.-]+\.ps1)')
    if($targetMatches.Count -ne 1){throw "[V74.0.26] CMD target count is not 1: $($cmdFile.Name)"}
    $targetPath=[System.IO.Path]::Combine($PackageRoot,"scripts",$targetMatches[0].Groups[1].Value)
    if(-not [System.IO.File]::Exists($targetPath)){throw "[V74.0.26] CMD target missing: $($cmdFile.Name) -> $targetPath"}
}

$runnerPath=[System.IO.Path]::Combine($PackageRoot,"scripts","run_jobpool_lane_packing.ps1")
$runnerText=[System.IO.File]::ReadAllText($runnerPath)
foreach($requiredToken in @(
    'SHARPEMU_RESERVED_HOST_LANES="$testReserved"',
    'SHARPEMU_WRITE_DATA_PACKET_POSITION="1"',
    'SHARPEMU_BINK_AUTO_BOOT="0"',
    'RUNNER_FORCED_STOP=False',
    'WAIT_RESUME_MAX_MS=',
    'STEADY_TREE_CPU_PERCENT_AFTER_20S='
)){
    if(-not $runnerText.Contains($requiredToken)){throw "[V74.0.26] Runner contract missing: $requiredToken"}
}
if($runnerText -match '(?i)Stop-Process|taskkill'){throw "[V74.0.26] RUN_4 must not auto-kill SharpEmu."}

Write-Host "[V74.0.26] PACKAGE VALIDATION PASSED ($($actualFiles.Count) hashed files; PowerShell AST parsed; CMD targets verified)."

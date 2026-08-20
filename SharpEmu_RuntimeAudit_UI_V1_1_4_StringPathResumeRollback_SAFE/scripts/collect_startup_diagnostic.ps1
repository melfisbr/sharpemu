. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'validate_package.ps1')

$repo = Get-RepoRoot
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$out = Join-Path $repo ('SharpEmu_StartupDiagnostic_V1_1_4_' + $stamp)
New-Item -ItemType Directory -Force -Path $out | Out-Null

$frontend = Get-FrontendPath $repo
$guiProject = Get-GuiProject $repo
$partials = @(Find-RuntimeAuditPartialPaths $repo $frontend)

$info = New-Object System.Collections.Generic.List[string]
$info.Add("Repo=$repo")
$info.Add("Frontend=$frontend")
$info.Add("FrontendSHA256=$(Get-HashSafe $frontend)")
$info.Add("GuiProject=$guiProject")
$info.Add("RuntimeAuditPartialCandidates=$($partials.Count)")
foreach ($p in $partials) { $info.Add("RuntimeAuditPartial=$([string]$p)") }
$info.Add("Dotnet=$(& dotnet --version 2>&1)")
$info.Add("OS=$([Environment]::OSVersion.VersionString)")
Set-Content -LiteralPath (Join-Path $out 'environment.txt') -Value $info -Encoding UTF8

Push-Location $repo
try {
    & dotnet build $guiProject -c Debug -r win-x64 --nologo *> (Join-Path $out 'build.log')
    "BuildExitCode=$LASTEXITCODE" | Set-Content -LiteralPath (Join-Path $out 'build_exit.txt') -Encoding UTF8
}
finally {
    Pop-Location
}

$logs = Join-Path $repo 'RuntimeAuditStartupRecovery'
if (Test-Path -LiteralPath $logs) {
    Copy-Item -LiteralPath $logs -Destination (Join-Path $out 'RuntimeAuditStartupRecovery') -Recurse -Force
}

Copy-Item -LiteralPath $frontend -Destination (Join-Path $out 'MainWindow.axaml.cs') -Force
Copy-Item -LiteralPath $guiProject -Destination (Join-Path $out 'SharpEmu.GUI.csproj') -Force

Get-ChildItem -LiteralPath (Join-Path $repo 'src') -Recurse -File -Filter '*.cs' -ErrorAction SilentlyContinue |
    Select-String -Pattern 'InstallRuntimeAuditButton|Audit\s*&\s*Launch|SharpEmu\.RuntimeAudit' -ErrorAction SilentlyContinue |
    ForEach-Object { "$($_.Path):$($_.LineNumber): $($_.Line.Trim())" } |
    Set-Content -LiteralPath (Join-Path $out 'runtimeaudit_markers.txt') -Encoding UTF8

$zip = $out + '.zip'
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -LiteralPath $out -DestinationPath $zip -CompressionLevel Optimal
Write-Step "STARTUP DIAGNOSTIC CREATED: $zip"

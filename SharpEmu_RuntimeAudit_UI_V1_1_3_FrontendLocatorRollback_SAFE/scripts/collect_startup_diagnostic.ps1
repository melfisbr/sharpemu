. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'validate_package.ps1')

$repo = Get-RepoRoot
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$out = Join-Path $repo ('SharpEmu_StartupDiagnostic_' + $stamp)
New-Item -ItemType Directory -Force -Path $out | Out-Null

$guiProject = Get-GuiProject $repo
$currentFrontend = $null
try { $currentFrontend = Find-PatchedFrontendSource $repo } catch {}

$info = New-Object System.Collections.Generic.List[string]
$info.Add("Repo=$repo")
$info.Add("GuiProject=$guiProject")
$info.Add("Dotnet=$(& dotnet --version 2>&1)")
$info.Add("OS=$([Environment]::OSVersion.VersionString)")
if ($currentFrontend) {
    $info.Add("Frontend=$currentFrontend")
    $info.Add("FrontendSHA256=$(Get-HashSafe $currentFrontend)")
}
Set-Content -LiteralPath (Join-Path $out 'environment.txt') -Value $info -Encoding UTF8

Push-Location $repo
try {
    & dotnet build $guiProject -c Debug -r win-x64 --nologo *> (Join-Path $out 'build.log')
    "BuildExitCode=$LASTEXITCODE" | Set-Content -LiteralPath (Join-Path $out 'build_exit.txt') -Encoding UTF8
}
finally {
    Pop-Location
}

$recoveryLogs = Join-Path $repo 'RuntimeAuditStartupRecovery'
if (Test-Path -LiteralPath $recoveryLogs) {
    Copy-Item -LiteralPath $recoveryLogs -Destination (Join-Path $out 'RuntimeAuditStartupRecovery') -Recurse -Force
}

Copy-Item -LiteralPath $guiProject -Destination (Join-Path $out ([IO.Path]::GetFileName($guiProject))) -Force
if ($currentFrontend) {
    Copy-Item -LiteralPath $currentFrontend -Destination (Join-Path $out ([IO.Path]::GetFileName($currentFrontend))) -Force
}

Get-ChildItem -LiteralPath (Join-Path $repo 'src') -Recurse -File -Filter '*.cs' -ErrorAction SilentlyContinue |
    Select-String -Pattern 'InstallRuntimeAuditButton|Audit\s*&\s*Launch|SharpEmu\.RuntimeAudit|class\s+MainWindow\b' -ErrorAction SilentlyContinue |
    ForEach-Object { "$($_.Path):$($_.LineNumber): $($_.Line.Trim())" } |
    Set-Content -LiteralPath (Join-Path $out 'frontend_markers.txt') -Encoding UTF8

$zip = $out + '.zip'
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -LiteralPath $out -DestinationPath $zip -CompressionLevel Optimal
Write-Step "STARTUP DIAGNOSTIC CREATED: $zip"

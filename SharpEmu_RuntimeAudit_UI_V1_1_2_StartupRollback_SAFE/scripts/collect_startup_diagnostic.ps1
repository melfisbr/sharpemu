. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'validate_package.ps1')

$repo = Get-RepoRoot
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$out = Join-Path $repo ('SharpEmu_StartupDiagnostic_' + $stamp)
New-Item -ItemType Directory -Force -Path $out | Out-Null

$guiProject = Get-GuiProject $repo
$main = Find-CurrentMainWindow $repo
$info = New-Object System.Collections.Generic.List[string]
$info.Add("Repo=$repo")
$info.Add("GuiProject=$guiProject")
$info.Add("MainWindow=$main")
$info.Add("MainWindowSHA256=$(Get-HashSafe $main)")
$info.Add("Dotnet=$(& dotnet --version 2>&1)")
$info.Add("OS=$([Environment]::OSVersion.VersionString)")

$bin = Join-Path $repo 'artifacts\bin\Debug\net10.0\win-x64'
foreach ($n in @('SharpEmu.GUI.exe','SharpEmu.exe','SharpEmu.GUI.dll','SharpEmu.dll')) {
    $p = Join-Path $bin $n
    if (Test-Path -LiteralPath $p) {
        $fi = Get-Item -LiteralPath $p
        $info.Add("$n size=$($fi.Length) sha256=$(Get-HashSafe $p)")
    }
}
Set-Content -LiteralPath (Join-Path $out 'environment.txt') -Value $info -Encoding UTF8

# Build output
Push-Location $repo
try {
    & dotnet build $guiProject -c Debug -r win-x64 --nologo *> (Join-Path $out 'build.log')
    "BuildExitCode=$LASTEXITCODE" | Set-Content -LiteralPath (Join-Path $out 'build_exit.txt') -Encoding UTF8
}
finally { Pop-Location }

# Copy startup recovery logs if any.
$recoveryLogs = Join-Path $repo 'RuntimeAuditStartupRecovery'
if (Test-Path -LiteralPath $recoveryLogs) {
    Copy-Item -LiteralPath $recoveryLogs -Destination (Join-Path $out 'RuntimeAuditStartupRecovery') -Recurse -Force
}

# Copy only small project/frontend source evidence.
Copy-Item -LiteralPath $guiProject -Destination (Join-Path $out ([IO.Path]::GetFileName($guiProject))) -Force
Copy-Item -LiteralPath $main -Destination (Join-Path $out 'MainWindow.cs') -Force

$markers = Get-ChildItem -LiteralPath (Join-Path $repo 'src') -Recurse -File -Filter '*.cs' -ErrorAction SilentlyContinue |
    Select-String -Pattern 'InstallRuntimeAuditButton|Audit\s*&\s*Launch|SharpEmu\.RuntimeAudit' -ErrorAction SilentlyContinue
$markers | ForEach-Object { "$($_.Path):$($_.LineNumber): $($_.Line.Trim())" } |
    Set-Content -LiteralPath (Join-Path $out 'runtimeaudit_markers.txt') -Encoding UTF8

$zip = $out + '.zip'
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -LiteralPath $out -DestinationPath $zip -CompressionLevel Optimal
Write-Step "STARTUP DIAGNOSTIC CREATED: $zip"

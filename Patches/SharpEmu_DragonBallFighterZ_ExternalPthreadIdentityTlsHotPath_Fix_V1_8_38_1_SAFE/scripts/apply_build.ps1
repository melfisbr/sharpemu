param(
    [string]$Game='F:\JOGOSPS5\[DLPSGAME.COM]-PPSA09790\[DLPSGAME.COM]-PPSA09790\PPSA09790-app\eboot.bin',
    [switch]$NoTranscript
)
. (Join-Path $PSScriptRoot "common.ps1")
$t=Start-V1838Transcript "DBFZ_V1_8_38_1_RUN3_APPLY_BUILD.log" -NoTranscript:$NoTranscript
$backup=$null
try {
    & (Join-Path $PSScriptRoot 'precheck.ps1') -Game $Game -NoTranscript
    $s=Read-V1838SourceSet
    $state=Get-V1838State $s.DirectImports $s.Pthread $s.PthreadExt
    if($state -eq 'Baseline'){
        $stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
        $backup=Join-Path $s.Paths.Repo ('.sharpemu-hotfix-backup\DBFZ_ExternalPthreadIdentityTls_V1_8_38_'+$stamp)
        foreach($key in @('DirectImports','Pthread','PthreadExt')){
            $src=$s.Paths[$key]
            $rel=$src.Substring($s.Paths.Repo.Length).TrimStart('\','/')
            $dst=Join-Path $backup $rel
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
            Copy-Item -LiteralPath $src -Destination $dst -Force
        }
        Write-Host "[DBFZ-CPU-1838.1] Backup=$backup"
        $p=Patch-AllV1838 $s
        Write-TextPreserveUtf8Bom $s.Paths.DirectImports $p.DirectImports
        Write-TextPreserveUtf8Bom $s.Paths.Pthread $p.Pthread
        Write-TextPreserveUtf8Bom $s.Paths.PthreadExt $p.PthreadExt
        Write-Host "[DBFZ-CPU-1838.1] Source patch applied."
    } else {
        Write-Host "[DBFZ-CPU-1838.1] Source already applied; no rewrite needed."
    }
    & (Join-Path $PSScriptRoot 'post_audit.ps1') -NoTranscript
    Push-Location $s.Paths.Repo
    try {
        Write-Host "[DBFZ-CPU-1838.1] Building SharpEmu.CLI Debug win-x64..."
        & dotnet build 'src\SharpEmu.CLI\SharpEmu.CLI.csproj' -c Debug -r win-x64 --nologo
        if($LASTEXITCODE -ne 0){throw "dotnet build failed with exit code $LASTEXITCODE"}
    } finally { Pop-Location }
    Write-Host "[DBFZ-CPU-1838.1] APPLY+BUILD PASSED."
} catch {
    if($null -ne $backup -and (Test-Path -LiteralPath $backup)){
        Write-Host "[DBFZ-CPU-1838.1] Failure detected; restoring source snapshot..."
        $repo=Find-RepoRoot
        foreach($rel in @(
            'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.Imports.cs',
            'src\SharpEmu.Libs\Kernel\KernelPthreadCompatExports.cs',
            'src\SharpEmu.Libs\Kernel\KernelPthreadExtendedCompatExports.cs'
        )){
            $src=Join-Path $backup $rel
            $dst=Join-Path $repo $rel
            if(Test-Path -LiteralPath $src){Copy-Item -LiteralPath $src -Destination $dst -Force}
        }
        Write-Host "[DBFZ-CPU-1838.1] Rollback completed from $backup"
    }
    throw
} finally { Stop-V1838Transcript $t }

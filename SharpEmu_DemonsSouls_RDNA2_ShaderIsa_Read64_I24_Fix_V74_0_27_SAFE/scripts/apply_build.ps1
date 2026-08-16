param([string]$RepositoryRoot = "")
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "common.ps1")

$repoRoot=Resolve-RepoRootV74027 -RepositoryRoot $RepositoryRoot
& (Join-Path $PSScriptRoot "precheck.ps1") -RepositoryRoot $repoRoot
$state=Get-ShaderIsaStateV74027 -Root $repoRoot
$paths=@(
    (Get-ShaderTranslatorPathV74027 -Root $repoRoot),
    (Get-SpirvTranslatorPathV74027 -Root $repoRoot),
    (Get-SpirvAluPathV74027 -Root $repoRoot),
    (Get-MslTranslatorPathV74027 -Root $repoRoot),
    (Get-MslAluPathV74027 -Root $repoRoot)
)
$backupRoot=""
if($state -eq "Baseline"){
    $stamp=Get-Date -Format "yyyyMMdd_HHmmss"
    $backupRoot=[System.IO.Path]::Combine($repoRoot,".sharpemu-hotfix-backup","ShaderIsaV74027_$stamp")
    [System.IO.Directory]::CreateDirectory($backupRoot)|Out-Null
    foreach($sourcePath in $paths){Copy-Item -LiteralPath $sourcePath -Destination ([System.IO.Path]::Combine($backupRoot,[System.IO.Path]::GetFileName($sourcePath))) -Force}
    try{
        [System.IO.File]::WriteAllText($paths[0],(Convert-ShaderTranslatorV74027 -Text ([System.IO.File]::ReadAllText($paths[0]))),[System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText($paths[1],(Convert-SpirvTranslatorV74027 -Text ([System.IO.File]::ReadAllText($paths[1]))),[System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText($paths[2],(Convert-SpirvAluV74027 -Text ([System.IO.File]::ReadAllText($paths[2]))),[System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText($paths[3],(Convert-MslTranslatorV74027 -Text ([System.IO.File]::ReadAllText($paths[3]))),[System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText($paths[4],(Convert-MslAluV74027 -Text ([System.IO.File]::ReadAllText($paths[4]))),[System.Text.UTF8Encoding]::new($false))
        if((Get-ShaderIsaStateV74027 -Root $repoRoot) -ne "Applied"){throw "post-write structural verification failed"}
        Write-Host "[V74.0.27] SOURCE PATCH APPLIED: RDNA2 DS read64 + signed I24 VOP2 support installed."
        Write-Host "[V74.0.27] Backup: $backupRoot"
    }catch{
        for($index=0;$index -lt $paths.Count;$index++){
            $backupFile=[System.IO.Path]::Combine($backupRoot,[System.IO.Path]::GetFileName($paths[$index]))
            if([System.IO.File]::Exists($backupFile)){Copy-Item -LiteralPath $backupFile -Destination $paths[$index] -Force}
        }
        throw
    }
}else{Write-Host "[V74.0.27] Source already contains the complete shader ISA repair; no rewrite required."}

try{
    Write-Host "[V74.0.27] Building accumulated Release win-x64..."
    Invoke-DotNetCheckedV74027 -Root $repoRoot -Arguments @("build","src\SharpEmu.CLI\SharpEmu.CLI.csproj","-c","Release","-r","win-x64","--nologo")
    Sync-ReleaseRuntimeAssetsV74027 -Root $repoRoot
}catch{
    if($state -eq "Baseline" -and -not [string]::IsNullOrWhiteSpace($backupRoot)){
        for($index=0;$index -lt $paths.Count;$index++){
            $backupFile=[System.IO.Path]::Combine($backupRoot,[System.IO.Path]::GetFileName($paths[$index]))
            if([System.IO.File]::Exists($backupFile)){Copy-Item -LiteralPath $backupFile -Destination $paths[$index] -Force}
        }
        Write-Host "[V74.0.27] Build failed; all five shader sources restored from backup."
    }
    throw
}
if((Get-ShaderIsaStateV74027 -Root $repoRoot) -ne "Applied"){throw "[V74.0.27] Post-build shader ISA state is not Applied."}
Write-Host "[V74.0.27] SUCCESS - RDNA2 shader ISA repair built."
Write-Host "[V74.0.27] Next: RUN_4_DEMONS_SHADER_ISA_TEST.cmd"

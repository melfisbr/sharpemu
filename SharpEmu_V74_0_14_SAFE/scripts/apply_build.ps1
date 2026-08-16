param([string]$RepositoryRoot="")
. (Join-Path $PSScriptRoot "common.ps1")

$root=Resolve-RepoRootV74014 $RepositoryRoot
& (Join-Path $PSScriptRoot "precheck.ps1") -RepositoryRoot $root

$native=Get-NativeWorkerPathV74014 $root
$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backupRoot=[System.IO.Path]::Combine(
    $root,".sharpemu-hotfix-backup","FastBootStability_V74_0_14_$stamp")
[System.IO.Directory]::CreateDirectory($backupRoot)|Out-Null
$backupNative=[System.IO.Path]::Combine(
    $backupRoot,"DirectExecutionBackend.NativeWorker.cs")
Copy-Item -LiteralPath $native -Destination $backupNative -Force
$sourceChanged=$false

try{
    $limiter=Get-NativeWorkerLimiterStateV74014 -Path $native

    if($limiter.State -eq 'LiteralCap'){
        $defaultCap=[int]$limiter.DefaultCap
        $text=$limiter.Text
        $decl=$limiter.Declaration
        $newDeclaration=$decl.Lhs + '= ReadNativeWorkerMaxConcurrentV74014();'

        $newline="`r`n"
        if(-not $text.Contains("`r`n")){ $newline="`n" }

        $helper=@(
            '',
            "`t// SHARPEMU_V74_0_14_DEMONS_RUNTIME_TBB_LIMIT",
            "`t// Preserve the accumulated repo's existing default ($defaultCap) for other games,",
            "`t// but allow a per-run cap for Demon's Souls startup/stability diagnostics.",
            "`tprivate static int ReadNativeWorkerMaxConcurrentV74014()",
            "`t{",
            "`t`tif (int.TryParse(",
            "`t`t`tEnvironment.GetEnvironmentVariable(`"SHARPEMU_NATIVE_WORKER_MAX_CONCURRENT`"),",
            "`t`t`tout var parsed) &&",
            "`t`t`tparsed > 0)",
            "`t`t{",
            "`t`t`treturn Math.Clamp(parsed, 1, 64);",
            "`t`t}",
            '',
            "`t`treturn $defaultCap;",
            "`t}"
        ) -join $newline

        $patched=$text.Remove($decl.Start,$decl.Length).Insert(
            $decl.Start,$newDeclaration + $helper)
        [System.IO.File]::WriteAllText(
            $native,$patched,[System.Text.UTF8Encoding]::new($true))
        $sourceChanged=$true
        Write-Host "[V74.0.14] Surgical runtime TBB override installed; preserved accumulated default=$defaultCap."
    }
    elseif($limiter.State -eq 'ExistingEnvironmentReader'){
        Write-Host "[V74.0.14] Existing generic environment-aware TBB reader already present; no source rewrite required."
    }
    elseif($limiter.State -eq 'V74014Applied'){
        Write-Host "[V74.0.14] Runtime TBB override already installed; build only."
    }
    else{
        throw "[V74.0.14] Unsafe limiter state at apply time: $($limiter.State)"
    }

    $post=Get-NativeWorkerLimiterStateV74014 -Path $native
    $postText=[System.IO.File]::ReadAllText($native)
    $hasRuntimeOverride=
        ($post.State -eq 'V74014Applied') -or
        ($post.State -eq 'ExistingEnvironmentReader')
    if(-not $hasRuntimeOverride -or
       -not $postText.Contains('SHARPEMU_NATIVE_WORKER_MAX_CONCURRENT')){
        throw "[V74.0.14] NativeWorker runtime limiter verification failed after surgical patch."
    }
    if(-not $postText.Contains('SHARPEMU_V74_0_10_RENDERER_RESOURCE_NATIVE_LANE')){
        throw "[V74.0.14] Renderer/resource lane marker disappeared; refusing cumulative regression."
    }

    Write-Host "[V74.0.14] Building Debug win-x64..."
    Invoke-DotNetCheckedV74014 -Root $root -Arguments @(
        "build","src\SharpEmu.CLI\SharpEmu.CLI.csproj",
        "-c","Debug","-r","win-x64","--nologo")

    Write-Host "[V74.0.14] Building Release win-x64..."
    Invoke-DotNetCheckedV74014 -Root $root -Arguments @(
        "build","src\SharpEmu.CLI\SharpEmu.CLI.csproj",
        "-c","Release","-r","win-x64","--nologo")

    Sync-ReleaseRuntimeAssetsV74014 -Root $root
}
catch{
    if($sourceChanged){
        Copy-Item -LiteralPath $backupNative -Destination $native -Force
        Write-Host "[V74.0.14] Apply/build failed; NativeWorker source restored."
    }
    throw
}

Write-Host "[V74.0.14] Backup: $backupRoot"
Write-Host "[V74.0.14] FINAL native_sha=$((Get-FileHash -LiteralPath $native -Algorithm SHA256).Hash.ToUpperInvariant())"
Write-Host "[V74.0.14] SUCCESS"
Write-Host "[V74.0.14] Next: RUN_4_DEMONS_FASTBOOT_STABILITY.cmd"

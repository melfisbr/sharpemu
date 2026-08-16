param([string]$RepositoryRoot="")
. (Join-Path $PSScriptRoot "common.ps1")

$root=Resolve-RepoRoot $RepositoryRoot

& (Join-Path $PSScriptRoot "precheck.ps1") `
    -RepositoryRoot $root

$presenter=Get-PresenterPath $root
$state=Get-ComputePhysicalLineState $presenter

$installed=
    $state.RestoreCount-eq 1 -and
    -not $state.Collapsed -and
    $state.HostExecutable -and
    $state.AssignmentExecutable -and
    $state.ResolveExecutable -and
    $state.NullGuardExecutable

$backupRoot=$null
$backupPresenter=$null

if(-not $installed){
    $stamp=Get-Date -Format "yyyyMMdd_HHmmss"

    $backupRoot=[System.IO.Path]::Combine(
        $root,
        ".sharpemu-hotfix-backup",
        "ComputeTexturePhysicalLine_V74_0_6_2_$stamp")

    [System.IO.Directory]::CreateDirectory(
        $backupRoot)|Out-Null

    $backupPresenter=[System.IO.Path]::Combine(
        $backupRoot,
        "VulkanVideoPresenter.cs")

    Copy-Item -LiteralPath $presenter -Destination $backupPresenter -Force

    try{
        $lines=$state.Lines
        $index=$state.MarkerIndex

        if($index-lt 0 -or $index-ge$lines.Length){
            throw "[V74.0.6.2] Invalid collapsed-line index: $index"
        }

        $collapsedLine=$lines[$index]

        if(-not $collapsedLine.TrimStart().StartsWith("//") -or
           -not $collapsedLine.Contains(
               "SHARPEMU_V73_20_COMPUTE_BINK_YUV_BINDING") -or
           -not $collapsedLine.Contains(
               "var hostMovieTextures = FindHostMovieTextureBindings(dispatch.Textures);") -or
           -not $collapsedLine.Contains(
               "resources.Textures[index] =") -or
           -not $collapsedLine.Contains(
               "ResolveTextureResource(texture);")){
            throw "[V74.0.6.2] Line $index is not the exact known collapsed compute block."
        }

        $indent=$collapsedLine.Substring(
            0,
            $collapsedLine.Length-$collapsedLine.TrimStart().Length)

        $replacement=@(
            $indent+'// SHARPEMU_V73_20_COMPUTE_BINK_YUV_BINDING',
            $indent+'// SHARPEMU_V74_0_6_2_COMPUTE_TEXTURE_RESOLVE_RESTORE',
            $indent+'// V73.20 had this entire compute mapping loop collapsed behind //.',
            $indent+'var hostMovieTextures = FindHostMovieTextureBindings(dispatch.Textures);',
            $indent+'if (hostMovieTextures.Luma >= 0 && hostMovieTextures.Chroma >= 0)',
            $indent+'{',
            $indent+'    // SHARPEMU_V73_20_COMPUTE_BINK_TRACE',
            $indent+'    if (Interlocked.Increment(ref _v7320ComputeBinkBindingTraceCount) <= 64)',
            $indent+'    {',
            $indent+'        var luma = dispatch.Textures[hostMovieTextures.Luma];',
            $indent+'        var chroma = dispatch.Textures[hostMovieTextures.Chroma];',
            $indent+'        Console.Error.WriteLine(',
            $indent+'            $"[V73.20][BINK] bink2.compute_yuv_binding " +',
            $indent+'            $"file=''{Path.GetFileName(_hostMovieFramePath)}'' " +',
            $indent+'            $"y={hostMovieTextures.Luma}:0x{luma.Address:X16}:{luma.Width}x{luma.Height} " +',
            $indent+'            $"uv={hostMovieTextures.Chroma}:0x{chroma.Address:X16}:{chroma.Width}x{chroma.Height} " +',
            $indent+'            $"host={_hostMovieFrameWidth}x{_hostMovieFrameHeight}");',
            $indent+'    }',
            $indent+'}',
            '',
            $indent+'for (var index = 0; index < dispatch.Textures.Count; index++)',
            $indent+'{',
            $indent+'    var texture = dispatch.Textures[index];',
            $indent+'    resources.Textures[index] =',
            $indent+'        index == hostMovieTextures.Luma',
            $indent+'            ? CreateHostMovieTextureResource(texture, plane: 0)',
            $indent+'            : index == hostMovieTextures.Chroma',
            $indent+'                ? CreateHostMovieTextureResource(texture, plane: 1)',
            $indent+'                : ResolveTextureResource(texture);',
            '',
            $indent+'    if (resources.Textures[index] is null)',
            $indent+'    {',
            $indent+'        throw new InvalidOperationException(',
            $indent+'            $"compute texture resource remained null: " +',
            $indent+'            $"index={index} addr=0x{texture.Address:X16} " +',
            $indent+'            $"size={texture.Width}x{texture.Height} " +',
            $indent+'            $"fmt={texture.Format}/{texture.NumberType} " +',
            $indent+'            $"storage={(texture.IsStorage ? 1 : 0)}");',
            $indent+'    }',
            $indent+'}'
        )

        $newLines=New-Object System.Collections.Generic.List[string]

        for($i=0;$i-lt$index;$i++){
            $newLines.Add($lines[$i])
        }

        foreach($line in $replacement){
            $newLines.Add([string]$line)
        }

        for($i=$index+1;$i-lt$lines.Length;$i++){
            $newLines.Add($lines[$i])
        }

        $encoding=Get-Utf8EncodingForExistingFile $presenter

        [System.IO.File]::WriteAllLines(
            $presenter,
            $newLines.ToArray(),
            $encoding)

        $verify=Get-ComputePhysicalLineState $presenter

        if($verify.MarkerCount-ne 1 -or
           $verify.RestoreCount-ne 1 -or
           $verify.Collapsed -or
           -not $verify.HostExecutable -or
           -not $verify.ForExecutable -or
           -not $verify.AssignmentExecutable -or
           -not $verify.ResolveExecutable -or
           -not $verify.NullGuardExecutable){
            throw (
                "[V74.0.6.2] Physical-line verification failed: " +
                "marker=$($verify.MarkerCount) restore=$($verify.RestoreCount) " +
                "collapsed=$($verify.Collapsed) host=$($verify.HostExecutable) " +
                "for=$($verify.ForExecutable) assign=$($verify.AssignmentExecutable) " +
                "resolve=$($verify.ResolveExecutable) null=$($verify.NullGuardExecutable)"
            )
        }

        Write-Host "[V74.0.6.2] Replaced exactly one 1549-character collapsed compute source line."
        Write-Host "[V74.0.6.2] Compute host-movie binding is now an executable physical C# line."
        Write-Host "[V74.0.6.2] Compute texture assignment/ResolveTextureResource loop is executable."
        Write-Host "[V74.0.6.2] Per-texture null invariant is executable before descriptor creation."
        Write-Host "[V74.0.6.2] Backup: $backupRoot"
    } catch {
        if($null-ne$backupPresenter -and
           [System.IO.File]::Exists($backupPresenter)){
            Copy-Item -LiteralPath $backupPresenter -Destination $presenter -Force
        }

        Write-Host "[V74.0.6.2] Apply failed; VulkanVideoPresenter.cs restored."
        throw
    }
} else {
    Write-Host "[V74.0.6.2] Compute physical-line restore already installed; building only."
}

try{
    Write-Host "[V74.0.6.2] Building Debug win-x64..."

    Invoke-DotNetChecked $root @(
        "build",
        "src\SharpEmu.CLI\SharpEmu.CLI.csproj",
        "-c","Debug",
        "-r","win-x64",
        "--nologo")
} catch {
    if($null-ne$backupPresenter -and
       [System.IO.File]::Exists($backupPresenter)){
        Copy-Item -LiteralPath $backupPresenter -Destination $presenter -Force
    }

    Write-Host "[V74.0.6.2] Build failed; VulkanVideoPresenter.cs restored."
    throw
}

$final=Get-ComputePhysicalLineState $presenter

Write-Host "[V74.0.6.2] FINAL collapsed=$($final.Collapsed)"
Write-Host "[V74.0.6.2] FINAL host_exec=$($final.HostExecutable)"
Write-Host "[V74.0.6.2] FINAL for_exec=$($final.ForExecutable)"
Write-Host "[V74.0.6.2] FINAL assign_exec=$($final.AssignmentExecutable)"
Write-Host "[V74.0.6.2] FINAL resolve_exec=$($final.ResolveExecutable)"
Write-Host "[V74.0.6.2] FINAL null_guard_exec=$($final.NullGuardExecutable)"
Write-Host "[V74.0.6.2] SUCCESS"
Write-Host "[V74.0.6.2] Next: RUN_DEMONS_COMPUTE_RESTORE_V74_0_6_2.cmd"

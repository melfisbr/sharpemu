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
            throw "[V74.0.6.3] Invalid collapsed-line index: $index"
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
            throw "[V74.0.6.3] Line $index is not the exact known collapsed compute block."
        }

        $indent=$collapsedLine.Substring(
            0,
            $collapsedLine.Length-$collapsedLine.TrimStart().Length)

        # V74.0.6.3: construct actual physical C# lines explicitly.
        # Do not use a PowerShell @() replacement array here: V74.0.6.2
        # demonstrated that its runtime representation could be stringified
        # back into a single physical line.
        $builder=New-Object System.Text.StringBuilder

        [void]$builder.AppendLine($indent+'// SHARPEMU_V73_20_COMPUTE_BINK_YUV_BINDING')
        [void]$builder.AppendLine($indent+'// SHARPEMU_V74_0_6_3_COMPUTE_TEXTURE_RESOLVE_RESTORE')
        [void]$builder.AppendLine($indent+'// V73.20 had this compute mapping loop collapsed behind //.')
        [void]$builder.AppendLine($indent+'var hostMovieTextures = FindHostMovieTextureBindings(dispatch.Textures);')
        [void]$builder.AppendLine($indent+'if (hostMovieTextures.Luma >= 0 && hostMovieTextures.Chroma >= 0)')
        [void]$builder.AppendLine($indent+'{')
        [void]$builder.AppendLine($indent+'    // SHARPEMU_V73_20_COMPUTE_BINK_TRACE')
        [void]$builder.AppendLine($indent+'    if (Interlocked.Increment(ref _v7320ComputeBinkBindingTraceCount) <= 64)')
        [void]$builder.AppendLine($indent+'    {')
        [void]$builder.AppendLine($indent+'        var luma = dispatch.Textures[hostMovieTextures.Luma];')
        [void]$builder.AppendLine($indent+'        var chroma = dispatch.Textures[hostMovieTextures.Chroma];')
        [void]$builder.AppendLine($indent+'        Console.Error.WriteLine(')
        [void]$builder.AppendLine($indent+'            $"[V73.20][BINK] bink2.compute_yuv_binding " +')
        [void]$builder.AppendLine($indent+'            $"y={hostMovieTextures.Luma}:0x{luma.Address:X16}:{luma.Width}x{luma.Height} " +')
        [void]$builder.AppendLine($indent+'            $"uv={hostMovieTextures.Chroma}:0x{chroma.Address:X16}:{chroma.Width}x{chroma.Height} " +')
        [void]$builder.AppendLine($indent+'            $"host={_hostMovieFrameWidth}x{_hostMovieFrameHeight}");')
        [void]$builder.AppendLine($indent+'    }')
        [void]$builder.AppendLine($indent+'}')
        [void]$builder.AppendLine()
        [void]$builder.AppendLine($indent+'for (var index = 0; index < dispatch.Textures.Count; index++)')
        [void]$builder.AppendLine($indent+'{')
        [void]$builder.AppendLine($indent+'    var texture = dispatch.Textures[index];')
        [void]$builder.AppendLine($indent+'    var resolvedTexture =')
        [void]$builder.AppendLine($indent+'        index == hostMovieTextures.Luma')
        [void]$builder.AppendLine($indent+'            ? CreateHostMovieTextureResource(texture, plane: 0)')
        [void]$builder.AppendLine($indent+'            : index == hostMovieTextures.Chroma')
        [void]$builder.AppendLine($indent+'                ? CreateHostMovieTextureResource(texture, plane: 1)')
        [void]$builder.AppendLine($indent+'                : ResolveTextureResource(texture);')
        [void]$builder.AppendLine()
        [void]$builder.AppendLine($indent+'    if (resolvedTexture is null)')
        [void]$builder.AppendLine($indent+'    {')
        [void]$builder.AppendLine($indent+'        throw new InvalidOperationException(')
        [void]$builder.AppendLine($indent+'            $"compute texture resource remained null: " +')
        [void]$builder.AppendLine($indent+'            $"index={index} addr=0x{texture.Address:X16} " +')
        [void]$builder.AppendLine($indent+'            $"size={texture.Width}x{texture.Height} " +')
        [void]$builder.AppendLine($indent+'            $"fmt={texture.Format}/{texture.NumberType} " +')
        [void]$builder.AppendLine($indent+'            $"storage={(texture.IsStorage ? 1 : 0)}");')
        [void]$builder.AppendLine($indent+'    }')
        [void]$builder.AppendLine()
        [void]$builder.AppendLine($indent+'    resources.Textures[index] = resolvedTexture;')
        [void]$builder.AppendLine($indent+'}')

        $replacementText=$builder.ToString()

        # Work at character offsets of the exact physical line. This avoids
        # every PowerShell array-enumeration/stringification ambiguity.
        $fullText=[System.IO.File]::ReadAllText($presenter)

        $markerPos=$fullText.IndexOf(
            "SHARPEMU_V73_20_COMPUTE_BINK_YUV_BINDING",
            [System.StringComparison]::Ordinal)

        if($markerPos-lt 0){
            throw "[V74.0.6.3] V73.20 marker disappeared before physical replacement."
        }

        $lineStart=$fullText.LastIndexOf("`n",$markerPos)
        if($lineStart-lt 0){
            $lineStart=0
        } else {
            $lineStart++
        }

        $lineEnd=$fullText.IndexOf("`n",$markerPos)
        if($lineEnd-lt 0){
            $lineEnd=$fullText.Length
        } else {
            $lineEnd++
        }

        $physicalLine=$fullText.Substring(
            $lineStart,
            $lineEnd-$lineStart)

        if(-not $physicalLine.TrimStart().StartsWith("//") -or
           -not $physicalLine.Contains("var hostMovieTextures") -or
           -not $physicalLine.Contains("resources.Textures[index] =") -or
           -not $physicalLine.Contains("ResolveTextureResource(texture);")){
            throw "[V74.0.6.3] Character-range target is not the known collapsed compute line."
        }

        $newText=
            $fullText.Substring(0,$lineStart) +
            $replacementText +
            $fullText.Substring($lineEnd)

        $encoding=Get-Utf8EncodingForExistingFile $presenter
        [System.IO.File]::WriteAllText(
            $presenter,
            $newText,
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
                "[V74.0.6.3] Physical-line verification failed: " +
                "marker=$($verify.MarkerCount) restore=$($verify.RestoreCount) " +
                "collapsed=$($verify.Collapsed) host=$($verify.HostExecutable) " +
                "for=$($verify.ForExecutable) assign=$($verify.AssignmentExecutable) " +
                "resolve=$($verify.ResolveExecutable) null=$($verify.NullGuardExecutable)"
            )
        }

        Write-Host "[V74.0.6.3] Replaced exactly one 1549-character collapsed compute source line."
        Write-Host "[V74.0.6.3] Compute host-movie binding is now an executable physical C# line."
        Write-Host "[V74.0.6.3] Compute texture assignment/ResolveTextureResource loop is executable."
        Write-Host "[V74.0.6.3] Per-texture null invariant is executable before descriptor creation."
        Write-Host "[V74.0.6.3] Backup: $backupRoot"
    } catch {
        if($null-ne$backupPresenter -and
           [System.IO.File]::Exists($backupPresenter)){
            Copy-Item -LiteralPath $backupPresenter -Destination $presenter -Force
        }

        Write-Host "[V74.0.6.3] Apply failed; VulkanVideoPresenter.cs restored."
        throw
    }
} else {
    Write-Host "[V74.0.6.3] Compute physical-line restore already installed; building only."
}

try{
    Write-Host "[V74.0.6.3] Building Debug win-x64..."

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

    Write-Host "[V74.0.6.3] Build failed; VulkanVideoPresenter.cs restored."
    throw
}

$final=Get-ComputePhysicalLineState $presenter

Write-Host "[V74.0.6.3] FINAL collapsed=$($final.Collapsed)"
Write-Host "[V74.0.6.3] FINAL host_exec=$($final.HostExecutable)"
Write-Host "[V74.0.6.3] FINAL for_exec=$($final.ForExecutable)"
Write-Host "[V74.0.6.3] FINAL assign_exec=$($final.AssignmentExecutable)"
Write-Host "[V74.0.6.3] FINAL resolve_exec=$($final.ResolveExecutable)"
Write-Host "[V74.0.6.3] FINAL null_guard_exec=$($final.NullGuardExecutable)"
Write-Host "[V74.0.6.3] SUCCESS"
Write-Host "[V74.0.6.3] Next: RUN_DEMONS_COMPUTE_RESTORE_V74_0_6_3.cmd"

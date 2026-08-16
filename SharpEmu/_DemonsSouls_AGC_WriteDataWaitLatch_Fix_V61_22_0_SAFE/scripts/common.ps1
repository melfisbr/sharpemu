Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

function Resolve-SharpEmuRepoRoot {
    param([string]$RepositoryRoot)

    if (-not [string]::IsNullOrWhiteSpace($RepositoryRoot)) {
        $candidate = [System.IO.Path]::GetFullPath($RepositoryRoot)
        if ((Test-Path (Join-Path $candidate "SharpEmu.slnx")) -and
            (Test-Path (Join-Path $candidate "src\SharpEmu.Libs\Agc\AgcExports.cs"))) {
            return $candidate
        }
        throw "RepositoryRoot nao aponta para a raiz do SharpEmu: $candidate"
    }

    $cursor = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
    for ($i = 0; $i -lt 8; $i++) {
        if ((Test-Path (Join-Path $cursor "SharpEmu.slnx")) -and
            (Test-Path (Join-Path $cursor "src\SharpEmu.Libs\Agc\AgcExports.cs"))) {
            return $cursor
        }
        $parent = [System.IO.Directory]::GetParent($cursor)
        if ($null -eq $parent) { break }
        $cursor = $parent.FullName
    }

    throw "Nao foi possivel localizar a raiz do SharpEmu. Execute a partir do repositorio ou passe -RepositoryRoot."
}

function Get-PackageRoot {
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
}

function Read-Utf8Text {
    param([Parameter(Mandatory=$true)][string]$Path)
    return [System.IO.File]::ReadAllText($Path)
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Text
    )
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $utf8)
}

function Normalize-Lf {
    param([string]$Text)
    return $Text.Replace("`r`n", "`n").Replace("`r", "`n")
}

function Restore-Newlines {
    param([string]$Text, [bool]$UseCrLf)
    if ($UseCrLf) { return $Text.Replace("`n", "`r`n") }
    return $Text
}

function Get-ApplyTarget {
    param([string]$RepositoryRoot)
    return Join-Path $RepositoryRoot "src\SharpEmu.Libs\Agc\AgcExports.cs"
}

function Get-WaitRegistryTarget {
    param([string]$RepositoryRoot)
    return Join-Path $RepositoryRoot "src\SharpEmu.Libs\Agc\GpuWaitRegistry.cs"
}

function Get-OldWriteDataBlock {
    return @'
                var wroteData = destination is 1 or 2 or 4 or 5;
                for (uint index = 0; wroteData && index < dwordCount; index++)
                {
                    var targetAddress = destinationAddress +
                        (incrementAddress ? (ulong)index * sizeof(uint) : 0);
                    wroteData = TryWriteUInt32(ctx, targetAddress, values[index]);
                }
'@
}

function Get-NewWriteDataBlock {
    return @'
                var wroteData = destination is 1 or 2 or 4 or 5;
                var trackWaitLabels =
                    wroteData &&
                    _gpuWaitSuspendEnabled &&
                    GpuWaitRegistry.CountForMemory(ctx.Memory) != 0;
                for (uint index = 0; wroteData && index < dwordCount; index++)
                {
                    var targetAddress = destinationAddress +
                        (incrementAddress ? (ulong)index * sizeof(uint) : 0);
                    var wroteValue = TryWriteUInt32(ctx, targetAddress, values[index]);
                    if (!wroteValue)
                    {
                        wroteData = false;
                        break;
                    }

                    // V61.22.0 WRITE_DATA active-wait latch:
                    // If WRITE_DATA is the producer of a label that already has a
                    // suspended WAIT_REG_MEM, record the value at the exact ordered
                    // write point. This preserves the satisfied edge even if the guest
                    // resets the label before the wait monitor polls memory.
                    if (trackWaitLabels &&
                        GpuWaitRegistry.SnapshotInRange(
                            ctx.Memory, targetAddress, (ulong)sizeof(uint)).Count != 0)
                    {
                        var latched = GpuWaitRegistry.RecordProduced(
                            ctx.Memory, targetAddress, values[index]);
                        if (latched)
                        {
                            Console.Error.WriteLine(
                                $"[LOADER][INFO] agc.write_data_wait_latched " +
                                $"addr=0x{targetAddress:X16} value=0x{values[index]:X8} " +
                                $"queue={state.QueueName} submission={state.ActiveSubmissionId}");
                        }
                    }
                }
'@
}

function Get-WriteDataMethodSlice {
    param([string]$NormalizedText)
    $startToken = "    private static void ApplySubmittedWriteData("
    $endToken = "    private static (uint Destination, bool IncrementAddress, bool WriteConfirm, uint CachePolicy)`n        DecodeStandardWriteDataControl"
    $start = $NormalizedText.IndexOf($startToken, [System.StringComparison]::Ordinal)
    if ($start -lt 0) { return $null }
    $end = $NormalizedText.IndexOf($endToken, $start, [System.StringComparison]::Ordinal)
    if ($end -lt 0) { return $null }
    return $NormalizedText.Substring($start, $end - $start)
}

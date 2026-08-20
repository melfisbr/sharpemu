. "$PSScriptRoot\common.ps1"
& "$PSScriptRoot\validate_package.ps1"
$s = Get-LauncherState
if ($s.OldCalls -eq 0 -and $s.Marker -and $s.NewCalls -gt 0) {
    Write-Host "$script:Tag Launcher ja corrigido; nenhuma alteracao necessaria." -ForegroundColor Cyan
    Test-PowerShellParse $script:Target
    exit 0
}
if ($s.OldCalls -lt 1) { throw "$script:Tag Nao foram encontradas chamadas ArgumentList.Add para converter." }

$before = Get-TargetText
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$repoRoot = Split-Path -Parent $script:PatchesRoot
$backupDir = Join-Path $repoRoot ".sharpemu-hotfix-backup\AttractGuestStateCompletionLauncherV7407721_$stamp"
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
$backup = Join-Path $backupDir 'run_test.ps1'
[System.IO.File]::WriteAllText($backup, $before, [System.Text.UTF8Encoding]::new($false))

$helper = @'
# V74.0.77.2.1 PS51 ProcessStartInfo.Arguments compatibility
function ConvertTo-PS51ProcessArgument {
    param([AllowNull()][string]$Value)
    if ($null -eq $Value -or $Value.Length -eq 0) { return '""' }
    if ($Value -notmatch '[\s\"]') { return $Value }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    $slashes = 0
    foreach ($ch in $Value.ToCharArray()) {
        if ($ch -eq '\') {
            $slashes++
            continue
        }
        if ($ch -eq '"') {
            if ($slashes -gt 0) { [void]$sb.Append(('\' * ($slashes * 2))) }
            [void]$sb.Append('\"')
            $slashes = 0
            continue
        }
        if ($slashes -gt 0) {
            [void]$sb.Append(('\' * $slashes))
            $slashes = 0
        }
        [void]$sb.Append($ch)
    }
    if ($slashes -gt 0) { [void]$sb.Append(('\' * ($slashes * 2))) }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function Add-PS51ProcessArgument {
    param(
        [Parameter(Mandatory=$true)][System.Diagnostics.ProcessStartInfo]$Psi,
        [AllowNull()][string]$Value
    )
    $encoded = ConvertTo-PS51ProcessArgument $Value
    if ([string]::IsNullOrWhiteSpace($Psi.Arguments)) {
        $Psi.Arguments = $encoded
    } else {
        $Psi.Arguments = $Psi.Arguments + ' ' + $encoded
    }
}
# /V74.0.77.2.1 PS51 ProcessStartInfo.Arguments compatibility

'@

$pattern = '(?im)\$psi\.ArgumentList\.Add\s*\(([^\r\n;]+?)\)'
$converted = [regex]::Replace($before, $pattern, 'Add-PS51ProcessArgument -Psi $psi -Value ($1)')
$remaining = ([regex]::Matches($converted, '(?i)\.ArgumentList\.Add\s*\(')).Count
if ($remaining -ne 0) {
    throw "$script:Tag Conversao incompleta: ainda restam $remaining chamadas ArgumentList.Add. Nenhum arquivo foi alterado."
}
$after = $helper + $converted
[System.IO.File]::WriteAllText($script:Target, $after, [System.Text.UTF8Encoding]::new($false))

try {
    Test-PowerShellParse $script:Target
    $post = Get-LauncherState
    if (-not $post.Marker -or $post.OldCalls -ne 0 -or $post.NewCalls -lt $s.OldCalls) {
        throw "$script:Tag Pos-validacao estrutural falhou: old=$($post.OldCalls) new=$($post.NewCalls) marker=$($post.Marker)"
    }
    $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $script:Target).Hash.ToLowerInvariant()
    Write-Host "$script:Tag LAUNCHER FIX APPLIED." -ForegroundColor Green
    Write-Host "$script:Tag converted_argument_calls=$($post.NewCalls)"
    Write-Host "$script:Tag target_sha256=$sha"
    Write-Host "$script:Tag backup=$backup"
} catch {
    Copy-Item -LiteralPath $backup -Destination $script:Target -Force
    throw
}

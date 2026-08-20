param([string]$RepoRoot='')
$script:PackageRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'common.ps1')
$repo = Resolve-SharpEmuRepo $RepoRoot
$patches = Join-Path $repo 'Patches'
$pointer = Join-Path $patches '.V74_0_75_processing_flow_last_backup.txt'
if (-not (Test-Path -LiteralPath $pointer)) { throw "$script:Tag Nenhum backup V74.0.75 registrado." }
$backupRoot = (Get-Content -LiteralPath $pointer -Raw).Trim()
if (-not (Test-Path -LiteralPath $backupRoot)) { throw "$script:Tag Backup nao encontrado: $backupRoot" }
foreach ($rel in @($script:PresenterRel, $script:AgcRel)) {
    $src = Join-Path $backupRoot $rel
    $dst = Join-Path $repo $rel
    if (-not (Test-Path -LiteralPath $src)) { throw "$script:Tag Backup incompleto: $src" }
    Copy-Item -LiteralPath $src -Destination $dst -Force
}
Remove-Item -LiteralPath $pointer -Force
Write-Host "$script:Tag ROLLBACK PASSED."
Write-Host "$script:Tag presenter_sha256=$(Get-Sha256 (Join-Path $repo $script:PresenterRel))"
Write-Host "$script:Tag agc_sha256=$(Get-Sha256 (Join-Path $repo $script:AgcRel))"

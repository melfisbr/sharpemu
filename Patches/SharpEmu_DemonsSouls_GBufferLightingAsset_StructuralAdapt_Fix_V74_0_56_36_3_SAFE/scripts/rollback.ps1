param(
    [string]$RepositoryRoot = (Get-Location).Path
)

. "$PSScriptRoot\common.ps1"

$repo = Resolve-RepoV74056363 $RepositoryRoot
$root = Join-Path $repo '.sharpemu-hotfix-backup'

$backup = Get-ChildItem `
    -LiteralPath $root `
    -Directory `
    -Filter 'GBufferLightingV74056363_*' `
    -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $backup) {
    throw ('{0} no V56.36.3 backup found' -f $script:Tag)
}

$restored = 0

$map = @(
    @('AgcExports.cs', $script:AgcRelative),
    @('VulkanVideoPresenter.cs', $script:PresenterRelative)
)

foreach ($entry in $map) {
    $backupPath = Join-Path $backup.FullName $entry[0]

    if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
        Copy-Item `
            -LiteralPath $backupPath `
            -Destination (Join-Path $repo $entry[1]) `
            -Force

        $restored++
    }
}

Write-Host (
    '{0} ROLLBACK COMPLETED restored={1} from {2}' -f `
    $script:Tag, `
    $restored, `
    $backup.FullName
) -ForegroundColor Green

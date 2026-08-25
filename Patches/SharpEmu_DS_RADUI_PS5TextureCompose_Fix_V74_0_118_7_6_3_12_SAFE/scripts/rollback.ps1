param()
. (Join-Path $PSScriptRoot 'common.ps1')

$repo=Get-RepositoryRoot
$pointer=Get-BackupPointer
if(-not(Test-Path -LiteralPath $pointer)){
    throw "$script:Tag backup pointer missing"
}
$backupRoot=(Get-Content -LiteralPath $pointer -Raw).Trim()

$restore=@(
    [pscustomobject]@{
        Relative=$script:RelativeHostApi
        Expected=$script:ExpectedHostApiSha
    },
    [pscustomobject]@{
        Relative=$script:RelativePresenter
        Expected=$script:ExpectedPresenterSha
    }
)

Get-Process SharpEmu -ErrorAction SilentlyContinue|Stop-Process -Force

foreach($item in $restore){
    $source=Join-Path $backupRoot $item.Relative
    $target=Join-Path $repo $item.Relative
    if(-not(Test-Path -LiteralPath $source)){
        throw "$script:Tag backup file missing: $source"
    }
    Copy-Item -LiteralPath $source -Destination $target -Force
    $sha=Get-Sha $target
    if($sha -ne $item.Expected){
        throw "$script:Tag rollback SHA mismatch target=$target expected=$($item.Expected) actual=$sha"
    }
}

Remove-Item -LiteralPath (Get-StatePath) -Force -ErrorAction SilentlyContinue
Write-Tag "ROLLBACK PASSED backup=$backupRoot"

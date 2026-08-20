Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
function PackageRoot { return (Split-Path -Parent $PSScriptRoot) }
function Patches { return (Split-Path -Parent (PackageRoot)) }
function RepoRoot { return (Split-Path -Parent (Patches)) }
function ImeDialogSource { return (Join-Path (RepoRoot) 'src\SharpEmu.Libs\Ime\ImeDialogExports.cs') }
function ImeExportsSource { return (Join-Path (RepoRoot) 'src\SharpEmu.Libs\Ime\ImeExports.cs') }
function CliProject { return (Join-Path (RepoRoot) 'src\SharpEmu.CLI\SharpEmu.CLI.csproj') }
function ExePath { return (Join-Path (RepoRoot) 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe') }
function PayloadSource { return (Join-Path (PackageRoot) 'payload\ImeDialogExports.cs') }
function Sha([string]$p) { return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash }
function CountText([string]$text,[string]$needle) {
    if ([string]::IsNullOrEmpty($needle)) { return 0 }
    $count=0; $start=0
    while (($i=$text.IndexOf($needle,$start,[StringComparison]::Ordinal)) -ge 0) { $count++; $start=$i+$needle.Length }
    return $count
}

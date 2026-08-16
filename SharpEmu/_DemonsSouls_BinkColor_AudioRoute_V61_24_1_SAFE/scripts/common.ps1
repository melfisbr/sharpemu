Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Repo([string]$r){if([string]::IsNullOrWhiteSpace($r)){return (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path};return (Resolve-Path -LiteralPath $r).Path}

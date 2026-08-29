$ErrorActionPreference='Stop'
$Tag='V76.3.19.0-SHADER-FRONTEND-HOTSET'
$Repo='C:\Users\Edpo\Documents\GitHub\sharpemu'
$Patches=Join-Path $Repo 'Patches'
$PackageRoot=Split-Path -Parent $PSScriptRoot

$TranslatorRel='src\SharpEmu.ShaderCompiler\Gen5ShaderTranslator.cs'
$PresenterRel='src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$AgcRel='src\SharpEmu.Libs\Agc\AgcExports.cs'
$CliRel='src\SharpEmu.CLI\DemonsSoulsGpuQueueEnvelopeV74011224.cs'
$Project=Join-Path $Repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'

$TranslatorPath=Join-Path $Repo $TranslatorRel
$PresenterPath=Join-Path $Repo $PresenterRel
$AgcPath=Join-Path $Repo $AgcRel
$CliPath=Join-Path $Repo $CliRel

$KnownTranslatorBaseline='6ab9a170fde5f6fc587f427bd0538e0a65a21ac93d3ef7f804cfd0cedc492a6b'

function Fail([string]$m){throw "[$Tag] $m"}
function Ensure-Repo{
 foreach($p in @($TranslatorPath,$PresenterPath,$AgcPath,$CliPath,$Project)){
  if(-not(Test-Path -LiteralPath $p -PathType Leaf)){Fail "arquivo ausente: $p"}
 }
 New-Item -ItemType Directory -Force -Path $Patches|Out-Null
}
function Get-HashLower([string]$p){(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()}
function Read-Utf8Preserve([string]$p){
 $b=[IO.File]::ReadAllBytes($p)
 $bom=$b.Length-ge3 -and $b[0]-eq0xEF -and $b[1]-eq0xBB -and $b[2]-eq0xBF
 $o=if($bom){3}else{0}
 [pscustomobject]@{Text=[Text.Encoding]::UTF8.GetString($b,$o,$b.Length-$o);HasBom=$bom}
}
function Write-Utf8Preserve([string]$p,[string]$t,[bool]$bom){
 $enc=New-Object System.Text.UTF8Encoding($bom)
 [IO.File]::WriteAllText($p,$t,$enc)
}

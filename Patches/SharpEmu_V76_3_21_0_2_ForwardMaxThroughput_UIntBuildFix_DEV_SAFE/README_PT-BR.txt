SharpEmu V76.3.21.0.2
Forward Max Throughput — UInt BuildFix / DEV SAFE

CORRECAO
A V21.0.1 passou VALIDATE + PRECHECK, mas a V21.0 original mudou:
  private const int MaxFramesInFlight = 2;
para um static readonly int configuravel.

O VkCommandBufferAllocateInfo.CommandBufferCount e uint. Quando o valor era
const=2, C# permitia a conversao constante. Depois da promocao para readonly,
o build passou a exigir cast explicito.

V21.0.2 instala ANTES do merge original:
  CommandBufferCount = (uint)MaxFramesInFlight,

Essa mudanca e semanticamente neutra para o baseline atual e corrige somente
a tipagem necessaria para o MaxFramesInFlight configuravel.

PRESERVADO
- V21.0 Forward Max Throughput completo
- V21.0.1 semantic dual-queue bridge
- V20.x dual physical queues / timeline / range hazards
- Async AGC command processor
- Compute Chain4
- producer/watched-write fastpaths
- resident shader/global/resource caches
- safe memcpy
- Bink
- Debug build

ROLLBACK
O V21.0 original continua fazendo rollback de Presenter + AGC + CLI em falha.
O wrapper V21.0.2 adicionalmente restaura o Presenter ao SHA anterior.

REQUISITO
A pasta original:
  SharpEmu_V76_3_21_0_ForwardMaxThroughput_AdaptiveMerge_DEV_SAFE
deve continuar em:
  C:\Users\Edpo\Documents\GitHub\sharpemu\Patches

O pacote V21.0.1 nao precisa ser executado novamente.

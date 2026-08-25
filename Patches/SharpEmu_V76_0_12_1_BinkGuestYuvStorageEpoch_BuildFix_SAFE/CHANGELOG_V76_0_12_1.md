# V76.0.12.1

- Adiciona epoch por sessão ao Bink guest-owned.
- Registra o VkImage final Y/UV somente depois de uma escrita storage GPU da sessão atual.
- Rejeita produtores Y/UV inicializados por sessão Bink anterior.
- Suprime upload CPU para os planos finais Y/UV GPU-owned.
- Corrige neutral black de Y=16 para Y=0 no contrato full-range do Bink2.
- Mantém host decoder desabilitado e preserva strict guest GPU ordering existente.


## V76.0.12.1 BuildFix
- Corrige sobrescrita de `$HelperHash` por `$helperHash` (PowerShell é case-insensitive).
- Precheck agora distingue corretamente helper ausente (`ReadyCopy`) de helper aplicado.
- Apply/verify preservam o hash esperado durante toda a execução.
- Payload C# V76.0.12 permanece inalterado.

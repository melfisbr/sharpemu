# V76.0.12

- Adiciona epoch por sessão ao Bink guest-owned.
- Registra o VkImage final Y/UV somente depois de uma escrita storage GPU da sessão atual.
- Rejeita produtores Y/UV inicializados por sessão Bink anterior.
- Suprime upload CPU para os planos finais Y/UV GPU-owned.
- Corrige neutral black de Y=16 para Y=0 no contrato full-range do Bink2.
- Mantém host decoder desabilitado e preserva strict guest GPU ordering existente.

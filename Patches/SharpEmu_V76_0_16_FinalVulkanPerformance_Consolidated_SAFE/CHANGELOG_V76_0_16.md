# CHANGELOG V76.0.16 Final Consolidated

## V76.0.14
- Persistent mapping no detile host-visible.
- Size classes grandes mais compactas no detile e pools host/device.

## V76.0.15
- Dual physical queue habilitável por default quando suportada.
- Hazard tracker por recurso guest usando timeline semaphores.
- Remoção da espera global por mera troca de lane quando o acesso rastreado é independente.
- Present usa dependência compute específica quando rastreável.

## V76.0.16
- Política explícita de present mode.
- Latest-ready collapse para reduzir backlog/latência.
- Exclusão do Bink guest-owned do collapse para preservar A/V V76.0.13.

Nenhum decoder host é ativado e os contratos Bink V76.0.12/13 permanecem intactos.

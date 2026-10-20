# HyperImage Converter

## What This Is

Conversor de imagens em lote para macOS 26+, em Swift/SwiftUI, que recria as funções do FastStone Photo Resizer
com interface nativa. Janela única com abas Converter, Comprimir e AI Upscale (Upscayl/Real-ESRGAN), mais modo
avançado com resize, crop, ajustes, texto/marca d'água, bordas e 10 formatos de saída. Distribuído no site witchmymac.

## Core Value

Converter qualquer lote de imagens sem perder dados nem travar: o original nunca é destruído por engano e o
resultado sempre corresponde ao que a interface prometeu.

## Requirements

### Validated

- ✓ Motor de conversão com 10 formatos de saída, 12 filtros de reamostragem, ajustes, texto, bordas — existente
- ✓ Lista de entrada com pastas virtuais, navegador lateral, serviço do Finder — existente
- ✓ Abas Converter / Comprimir / AI Upscale no layout simplificado — existente
- ✓ Interface em português e inglês — existente
- ✓ 106 testes (motor + fluxos do app) passando — existente

### Active

Milestone v1.0 "Polir e caçar bugs" — ver REQUIREMENTS.md.

### Out of Scope

- Novos recursos grandes (novos formatos, edição interativa) — foco do milestone é estabilidade
- Notarização Apple — requer conta paga de desenvolvedor; assinatura ad hoc continua
- Animação multi-frame (GIF/TIFF) na saída — mudança de motor grande, fica para v2

## Context

- Brownfield: mapa do código em `.planning/codebase/` (CONCERNS.md lista os problemas priorizados).
- Build exige Xcode: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build|test`.
- Regras do usuário: imutabilidade, arquivos pequenos, tratamento de erros, testes primeiro.

## Constraints

- **Plataforma**: macOS 26+, Swift 6.2, sem dependências SwiftPM — manter assim
- **Licenças**: Upscayl AGPL roda como processo separado; só modelos redistribuíveis
- **Idioma**: textos novos em pt (origem) + en no `Localizable.xcstrings`

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| GSD modo YOLO, fases grossas, só verificador | Usuário quer execução independente | — Pending |
| Milestone v1.0 = polimento e correção de bugs | Pedido do usuário: "tudo deve funcionar legal" | — Pending |

## Evolution

Atualizado nas transições de fase e marcos de milestone.

---
*Last updated: 2026-10-20 after initialization*

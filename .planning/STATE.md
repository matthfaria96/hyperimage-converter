---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: released
stopped_at: 1.0.0 pronta para publicar (tag local v1.0.0)
last_updated: "2026-10-24T23:45:00.000Z"
last_activity: 2026-10-25
progress:
  total_phases: 6
  completed_phases: 3
  total_plans: 10
  completed_plans: 10
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-10-20)

**Core value:** Converter qualquer lote sem perder dados nem travar; o resultado corresponde ao que a UI promete.
**Current focus:** Phase 1 - Segurança de dados e entradas hostis

## Current Position

Release: 1.0.0 (build 2), primeira versão pública, tag local `v1.0.0`
Status: pronta para o coordenador publicar (GitHub Release + witchmymac.com)
Last activity: 2026-10-24

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**

- Total plans completed: 10

## Accumulated Context

### Roadmap Evolution

- Phase 02.1 inserted after Phase 2: Usuário pediu de volta as funções do FastStone que sumiram com o layout simplificado (URGENT)
- Phase 02.1.1 inserted after Phase 02.1: Usuário pediu design premium nativo macOS 26 com animações em toda ação (URGENT)

### Decisions

- Milestone v1.0 = polimento e correção de bugs; fases ordenadas por risco
- Testes escritos junto de cada fase; TEST-01 fecha na Phase 4

### Pending Todos

None yet.

### Blockers/Concerns

- Itens de CONCERNS.md fora do v1 (GIF/TIFF animado, thumbnails RAW, notarização) ficam para v2

## Release 1.0.0 (2026-10-24)

- Merge de origin/main (README em inglês; o README do main foi mantido e refeito em `docs:`).
- Painel de opções: Comprimir abre com seção titulada (mesma altura nos três modos), fundo único do formulário e da
  barra de resumo (sem emenda no modo escuro), texto do resumo alinhado ao texto dos cards, linha de status na altura
  do rodapé da lista, progresso mostra "—" antes do primeiro arquivo.
- Estimativa: uma amostra por tipo de arquivo (o maior de cada tipo, até 4), não mais os 3 primeiros da lista
  (antes prometia 1 % no Comprimir quando o lote economizava 45 %). Teste em `EstimateTests`.
- Ícone: squircle n = 5 de 824 px centrado no canvas de 1024 (antes 10 px acima e cantos circulares), aro de vidro.
- README.md em inglês + README.pt-BR.md com instalação (install.sh, DMG + xattr, DMG + Ajustes).
- Hook de debug `HYPERIMAGE_FAKE_KEY=1`: janelas desenhadas como ativas sem tirar o foco (capturas com
  `screencapture -l`). Não falsificar `NSApplication.isActive` (o app abortou em `_NSMenuBarBackingView hitTest:`).
- Testes: 191 passando (139 + 22 Swift Testing, 30 XCTest), build sem warnings.

## Release 1.0.1 (2026-10-25)

- Atualizações dentro do app com Sparkle 2.10 (SwiftPM): `Sources/HyperImage/Updates/AppUpdater.swift`, item
  "Verificar Atualizações…" no menu do app e botão no Sobre; feed `https://witchmymac.com/appcast/hyperimage.xml`,
  chaves SU* em `Resources/Info.plist`. Cópias de teste (outro bundle id) só verificam com `HYPERIMAGE_UPDATES=1`.
- `build-app.sh` embute `Sparkle.framework` em Contents/Frameworks (+ rpath, assinatura ad hoc com runtime) e a
  licença MIT, listada em Sobre → Licenças de código aberto.
- 1.0.1 (build 3) publicada como v1.0.1 (DMG `HyperImage-1.0.1.dmg`, assinado com sign-app.sh); release 1.0.0
  apagada. Quem está na 1.0.0 instala a 1.0.1 à mão uma vez.

## Session Continuity

Last session: 2026-10-24
Stopped at: 1.0.0 pronta; publicar DMG `HyperImage-1.0.0.dmg` e capturas do site
Resume file: None

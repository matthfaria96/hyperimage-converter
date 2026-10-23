# Roadmap: HyperImage Converter

## Overview

Milestone v1.0 "Polir e caçar bugs": tornar o app confiável em lote, sem perda de dados nem travamentos. A ordem segue o risco: primeiro segurança dos originais e entradas hostis, depois recursos e ciclo de vida, depois correção dos resultados, e por fim UX/estado e fechamento dos testes.

## Phases

- [x] **Phase 1: Segurança de dados e entradas hostis** - Originais nunca sobrescritos por engano; arquivos de opções malformados não derrubam o app (completed 2026-10-20)
- [x] **Phase 2: Recursos e ciclo de vida** - Lotes grandes sem estourar memória, sair do app encerra o upscale, build limpo (completed 2026-10-23)
- [ ] **Phase 3: Correção dos resultados** - O resultado corresponde ao que a interface promete (limite de tamanho, modo Comprimir, erros claros)
- [ ] **Phase 4: UX, estado e testes finais** - Resultados e desfazer coerentes, folhas sem conflito, smoke de UI e cobertura de testes

## Phase Details

### Phase 1: Segurança de dados e entradas hostis
**Goal**: O usuário nunca perde um original por engano e nenhum arquivo de opções malformado derruba o app
**Depends on**: Nothing (first phase)
**Requirements**: SAFE-01, SAFE-02, SAFE-03, ROB-01, ROB-02
**Success Criteria** (what must be TRUE):
  1. Converter/Comprimir um arquivo sem pasta de saída nem sufixo, no mesmo formato, não sobrescreve o original sem confirmação explícita (é tratado ou recusado com mensagem)
  2. No aviso de sobrescrever, apertar Return não sobrescreve (a ação padrão não é destrutiva)
  3. Abrir um `.ccf`/`.hyperoptions` com NaN, Inf ou valores enormes mostra um erro e o app continua aberto
  4. Dimensões de resize/canvas/crop/borda acima do limite seguro são rejeitadas com mensagem clara
  5. Após upscale concluído, com erro ou cancelado, nenhum arquivo temporário sobra
**Plans**: TBD
**UI hint**: yes

### Phase 2: Recursos e ciclo de vida
**Goal**: Lotes pesados e o encerramento do app se comportam de forma previsível, com build sem warnings
**Depends on**: Phase 1
**Requirements**: ROB-03, ROB-04, ROB-05, CORR-04
**Success Criteria** (what must be TRUE):
  1. Um lote de imagens de alta resolução (dezenas de MP) termina sem estouro de memória, com concorrência reduzida conforme o tamanho
  2. Sair do app durante o AI Upscale deixa nenhum `upscayl-bin` rodando
  3. `swift build` termina sem warnings, incluindo ConversionRunner.swift:49
  4. `HYPERIMAGE_UPSCAYL` é ignorada em build release e só vale em debug
**Plans**: TBD

### Phase 02.1: Restaurar funções do FastStone no layout novo (INSERTED)

**Goal:** Todas as funções do FastStone Photo Resizer (spec em `../Clones/FSResizer-spec/SPEC.md`) voltam a ser alcançáveis no layout novo de janela única, com o mesmo visual de cards
**Requirements**: FS-01, FS-02, FS-03, FS-04, FS-05
**Success Criteria** (what must be TRUE):
  1. A aba "Renomear" no cabeçalho renomeia os originais por template (`#`, `*`, `$P`, `$Y $M $D $H $N $S`, nº inicial, caixa da extensão) ou por buscar e substituir, com pré-visualização Antigo → Novo antes de executar
  2. Converter e Comprimir têm "Renomear a saída" com template e nº inicial; a ordem da lista define a numeração
  3. O arquivo selecionado mostra miniatura, L×A, tamanho e data, com chave para ocultar
  4. Durante e depois do lote aparecem tamanho antigo/novo, proporção, economia e tempo decorrido/restante
  5. As 10 etapas da edição avançada aparecem no painel com chave individual, e o botão abre a etapa clicada
  6. Textos novos em pt e en, testes do motor de renomeação e do fluxo passam, smoke de UI passa
**Depends on:** Phase 2
**Plans:** 6 plans

Plans:
- [ ] 02.1-01-PLAN.md — Restore rename engine (D-03), undo record, rename-on-convert in OutputPlanner with SAFE-01 tests
- [ ] 02.1-02-PLAN.md — Persisted rename state, apply/undo actions, TemplateField/RenamePanel/RenamePreviewSheet/RenameSummary
- [ ] 02.1-03-PLAN.md — ConvertMode.rename tab (⌘4) wired to the mandatory preview, "Renomear a saída" in Save card, UI smoke
- [ ] 02.1-04-PLAN.md — Selected-file preview card (FS-03) and batch statistics in the summary (FS-04)
- [ ] 02.1-05-PLAN.md — Edição avançada card with the 10 steps, switches, and open-on-step (FS-05)
- [ ] 02.1-06-PLAN.md — pt + en strings, About/README, full verification (tests, 0 warnings, smoke pt/en)

### Phase 3: Correção dos resultados
**Goal**: O arquivo gerado corresponde ao que a interface prometeu, e falhas dizem o motivo real
**Depends on**: Phase 2
**Requirements**: CORR-01, CORR-02, CORR-03
**Success Criteria** (what must be TRUE):
  1. Com "Limitar tamanho" ativo, o limite é respeitado, ou o arquivo mostra aviso quando não é possível (PNG/TIFF/BMP, crop sem perdas, qualidade mínima)
  2. No modo Comprimir, nenhum formato é trocado em silêncio; o texto da UI descreve o comportamento real
  3. Crop fora dos limites, WebP acima de 16 383 px e backend de upscale ausente mostram mensagens específicas (o backend ausente aparece uma única vez)
**Plans**: TBD
**UI hint**: yes

### Phase 4: UX, estado e testes finais
**Goal**: A interface reflete o estado real, as folhas não se atropelam e os riscos corrigidos ficam cobertos por testes
**Depends on**: Phase 3
**Requirements**: UX-01, UX-02, UX-03, UX-04, UX-05, TEST-01
**Success Criteria** (what must be TRUE):
  1. Ao mudar formato, qualidade ou modo, badges, tamanhos e links "Mostrar no Finder" antigos desaparecem
  2. Desfazer restaura só os itens removidos (sem apagar arquivos adicionados depois) e fica desativado durante o lote
  3. O aviso de sobrescrever e a folha de erros do fim do lote nunca ficam escondidos nem substituem outra folha aberta
  4. Pasta ausente no navegador mostra "Pasta não encontrada"; ajustes que falham ao carregar avisam o usuário
  5. `scripts/ui-smoke.sh` passa em todas as abas e folhas, e a suíte cobre parser hostil, saída in-place, limites de tamanho, desfazer e cancelamento do upscale
**Plans**: TBD
**UI hint**: yes

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Segurança de dados e entradas hostis | 2/2 | Complete    | 2026-10-20 |
| 2. Recursos e ciclo de vida | 2/2 | Complete    | 2026-10-23 |
| 3. Correção dos resultados | 0/0 | Not started | - |
| 4. UX, estado e testes finais | 0/0 | Not started | - |

Nota: testes de cada fase são escritos junto com a correção (TDD); TEST-01 é fechado na Phase 4 como verificação de cobertura.

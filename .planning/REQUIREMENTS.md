# Requirements: HyperImage Converter

**Defined:** 2026-10-20
**Core Value:** Converter qualquer lote sem perder dados nem travar; o resultado corresponde ao que a UI promete.

## v1 Requirements

### Segurança de dados (SAFE)

- [x] **SAFE-01**: O app nunca grava a saída por cima do arquivo de origem sem confirmação explícita (saída = entrada é detectada e tratada)
- [x] **SAFE-02**: O botão padrão (Return) do aviso de sobrescrever não é a ação destrutiva
- [x] **SAFE-03**: Arquivos temporários do upscale são limpos em sucesso, erro e cancelamento

### Robustez (ROB)

- [x] **ROB-01**: Arquivos `.ccf`/`.hyperoptions` malformados (NaN, Inf, valores enormes) nunca derrubam o app; mostram erro
- [x] **ROB-02**: Dimensões vindas de opções são limitadas a valores seguros
- [x] **ROB-03**: Lotes grandes de imagens de alta resolução não estouram memória (orçamento de concorrência por tamanho)
- [x] **ROB-04**: Sair do app durante o AI Upscale encerra o `upscayl-bin`
- [x] **ROB-05**: Build sem warnings (incluindo ConversionRunner.swift:49)

### Correção (CORR)

- [ ] **CORR-01**: "Limitar tamanho do arquivo" é respeitado ou o usuário é avisado quando não dá (formatos sem perdas, crop sem perdas, qualidade mínima)
- [x] **CORR-02**: Modo Comprimir não troca o formato silenciosamente; o texto da UI corresponde ao comportamento — feito em 2026-10-23 (PSD/RAW etc. são recusados com motivo; Comprimir nunca troca o formato)
- [ ] **CORR-03**: Mensagens de erro específicas (crop, WebP, backend do upscale ausente uma vez só)
- [x] **CORR-04**: Variável de ambiente `HYPERIMAGE_UPSCAYL` só vale em build de debug

### UX e estado (UX)

- [ ] **UX-01**: Resultados antigos somem quando formato/qualidade/modo mudam
- [ ] **UX-02**: Desfazer remove/restaura só a mudança feita (não um snapshot inteiro) e fica desativado durante o lote
- [ ] **UX-03**: Aviso de sobrescrever e fim do lote não ficam escondidos atrás de/por cima de folhas abertas
- [ ] **UX-04**: Pasta do navegador ausente mostra mensagem; ajustes que falham ao carregar avisam
- [ ] **UX-05**: Smoke de UI (`scripts/ui-smoke.sh`) passa em todas as abas e folhas

### Funções do FastStone (FS)

- [x] ~~**FS-01**: Aba Renomear em lote~~ — removida a pedido do usuário em 2026-10-23 ("inútil"); fica só "Renomear a saída" (FS-02)
- [x] **FS-02**: Renomear a saída ao converter/comprimir com template e nº inicial
- [x] **FS-03**: Pré-visualização do arquivo selecionado (miniatura, L×A, KB, data)
- [x] **FS-04**: Detalhes do progresso (antigo/novo, proporção, economia, decorrido/restante)
- [x] **FS-05**: Etapas da edição avançada visíveis e ativáveis direto no painel

### Interface nativa (UI)

- [ ] **UI-01**: Estrutura nativa macOS 26 (split view, toolbar com modos, inspector) com Liquid Glass e controles de sistema padronizados em todas as telas
- [ ] **UI-02**: Toda ação do usuário tem animação (modo, opções, lista, progresso, conclusão), com Reduce Motion respeitado
- [ ] **UI-03**: Problemas visuais P-01..P-15 corrigidos e verificados em capturas light/dark/estreita

### Testes (TEST)

- [ ] **TEST-01**: Testes cobrem parser com entradas hostis, saída in-place, limites de tamanho, desfazer e cancelamento do upscale

## v2 Requirements

- **ANIM-01**: Preservar GIF animado e TIFF multipágina na saída
- **PERF-01**: Thumbnails de RAW/arquivos grandes sem decodificar a imagem inteira
- **REL-01**: Notarização e CI

## Out of Scope

| Feature | Reason |
|---------|--------|
| Novos formatos | Milestone focado em estabilidade |
| Notarização | Requer conta paga |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| SAFE-01 | Phase 1 | Complete |
| SAFE-02 | Phase 1 | Complete |
| SAFE-03 | Phase 1 | Complete |
| ROB-01 | Phase 1 | Complete |
| ROB-02 | Phase 1 | Complete |
| ROB-03 | Phase 2 | Complete |
| ROB-04 | Phase 2 | Complete |
| ROB-05 | Phase 2 | Complete |
| CORR-04 | Phase 2 | Complete |
| CORR-01 | Phase 3 | Pending |
| CORR-02 | Phase 3 | Complete |
| CORR-03 | Phase 3 | Pending |
| UX-01 | Phase 4 | Pending |
| UX-02 | Phase 4 | Pending |
| UX-03 | Phase 4 | Pending |
| UX-04 | Phase 4 | Pending |
| UX-05 | Phase 4 | Pending |
| TEST-01 | Phase 4 | Pending |
| FS-01 | Phase 02.1 | Complete |
| FS-02 | Phase 02.1 | Complete |
| FS-03 | Phase 02.1 | Complete |
| FS-04 | Phase 02.1 | Complete |
| FS-05 | Phase 02.1 | Complete |
| UI-01 | Phase 02.1.1 | Pending |
| UI-02 | Phase 02.1.1 | Pending |
| UI-03 | Phase 02.1.1 | Pending |

**Coverage:**
- v1 requirements: 26 total
- Mapped to phases: 26
- Unmapped: 0

---
*Requirements defined: 2026-10-20*

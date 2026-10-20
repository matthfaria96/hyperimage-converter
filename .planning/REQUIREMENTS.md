# Requirements: HyperImage Converter

**Defined:** 2026-10-20
**Core Value:** Converter qualquer lote sem perder dados nem travar; o resultado corresponde ao que a UI promete.

## v1 Requirements

### Segurança de dados (SAFE)

- [ ] **SAFE-01**: O app nunca grava a saída por cima do arquivo de origem sem confirmação explícita (saída = entrada é detectada e tratada)
- [ ] **SAFE-02**: O botão padrão (Return) do aviso de sobrescrever não é a ação destrutiva
- [ ] **SAFE-03**: Arquivos temporários do upscale são limpos em sucesso, erro e cancelamento

### Robustez (ROB)

- [ ] **ROB-01**: Arquivos `.ccf`/`.hyperoptions` malformados (NaN, Inf, valores enormes) nunca derrubam o app; mostram erro
- [ ] **ROB-02**: Dimensões vindas de opções são limitadas a valores seguros
- [ ] **ROB-03**: Lotes grandes de imagens de alta resolução não estouram memória (orçamento de concorrência por tamanho)
- [ ] **ROB-04**: Sair do app durante o AI Upscale encerra o `upscayl-bin`
- [ ] **ROB-05**: Build sem warnings (incluindo ConversionRunner.swift:49)

### Correção (CORR)

- [ ] **CORR-01**: "Limitar tamanho do arquivo" é respeitado ou o usuário é avisado quando não dá (formatos sem perdas, crop sem perdas, qualidade mínima)
- [ ] **CORR-02**: Modo Comprimir não troca o formato silenciosamente; o texto da UI corresponde ao comportamento
- [ ] **CORR-03**: Mensagens de erro específicas (crop, WebP, backend do upscale ausente uma vez só)
- [ ] **CORR-04**: Variável de ambiente `HYPERIMAGE_UPSCAYL` só vale em build de debug

### UX e estado (UX)

- [ ] **UX-01**: Resultados antigos somem quando formato/qualidade/modo mudam
- [ ] **UX-02**: Desfazer remove/restaura só a mudança feita (não um snapshot inteiro) e fica desativado durante o lote
- [ ] **UX-03**: Aviso de sobrescrever e fim do lote não ficam escondidos atrás de/por cima de folhas abertas
- [ ] **UX-04**: Pasta do navegador ausente mostra mensagem; ajustes que falham ao carregar avisam
- [ ] **UX-05**: Smoke de UI (`scripts/ui-smoke.sh`) passa em todas as abas e folhas

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
| SAFE-01 | Phase 1 | Pending |
| SAFE-02 | Phase 1 | Pending |
| SAFE-03 | Phase 1 | Pending |
| ROB-01 | Phase 1 | Pending |
| ROB-02 | Phase 1 | Pending |
| ROB-03 | Phase 2 | Pending |
| ROB-04 | Phase 2 | Pending |
| ROB-05 | Phase 2 | Pending |
| CORR-04 | Phase 2 | Pending |
| CORR-01 | Phase 3 | Pending |
| CORR-02 | Phase 3 | Pending |
| CORR-03 | Phase 3 | Pending |
| UX-01 | Phase 4 | Pending |
| UX-02 | Phase 4 | Pending |
| UX-03 | Phase 4 | Pending |
| UX-04 | Phase 4 | Pending |
| UX-05 | Phase 4 | Pending |
| TEST-01 | Phase 4 | Pending |

**Coverage:**
- v1 requirements: 18 total
- Mapped to phases: 18
- Unmapped: 0

---
*Requirements defined: 2026-10-20*

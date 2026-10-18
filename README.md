# HyperImage Converter

Conversor e renomeador de imagens em lote para macOS 26+, em Swift/SwiftUI. Recria as funções do
FastStone Photo Resizer (spec em `../Clones/FSResizer-spec/SPEC.md`) com a interface nativa do Mac.

## Build e testes
```sh
./build-app.sh              # gera build/HyperImage Converter.app (universal, assinado ad hoc)
./build-app.sh --install    # e copia para /Applications
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```
O Xcode é necessário (as Command Line Tools não trazem os plugins de macro do SwiftUI).

## Estrutura
- `Sources/HyperImageCore`: motor sem UI. Modelos de opções, geometria (resize/crop/canvas), reamostrador
  separável com os 12 filtros, ajustes via Core Image, texto/marca d'água/bordas, quantizador median-cut,
  encoders (ImageIO, WebP via libwebp, PDF), lote concorrente e renomeação.
- `Sources/HyperImage`: app SwiftUI (navegador lateral, lista de entrada, inspetor, folhas).
- `Sources/CWebP`: libwebp 1.6.0 (BSD), só o encoder. O ImageIO lê WebP, mas não grava.

## Diferenças em relação ao original
- Saída: além dos 8 formatos originais, também HEIC e AVIF.
- Entrada: tudo o que o ImageIO lê (incluindo RAW). PCX, WMF/EMF e FAX não são suportados pelo macOS.
- JPEG: subamostragem, suavização e Huffman não são expostos pelo ImageIO, então foram omitidos. "Usar a qualidade
  do original" estima a qualidade a partir da tabela DQT. O recorte JPEG sem perdas não foi implementado
  (a opção fica guardada, mas o recorte é sempre recodificado).
- As opções são salvas como JSON (`.hyperoptions`); `.ccf` não é importado.

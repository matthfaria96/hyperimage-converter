# HyperImage Converter

Conversor e renomeador de imagens em lote para macOS 26+, em Swift/SwiftUI. Recria as funções do
FastStone Photo Resizer (spec em `../Clones/FSResizer-spec/SPEC.md`) com a interface nativa do Mac.

## Build e testes
```sh
./build-app.sh              # gera build/HyperImage Converter.app (universal, assinado ad hoc)
./build-app.sh --install    # e copia para /Applications
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```
Depois de instalado, o Finder ganha "Converter com HyperImage" no menu de contexto (Ações Rápidas/Serviços), que
manda as imagens e pastas selecionadas para a lista de entrada. Se não aparecer, ative em Ajustes do Sistema →
Teclado → Atalhos de Teclado → Serviços.

O Xcode é necessário (as Command Line Tools não trazem os plugins de macro do SwiftUI).

## Estrutura
- `Sources/HyperImageCore`: motor sem UI. Modelos de opções, geometria (resize/crop/canvas), reamostrador
  separável com os 12 filtros, ajustes via Core Image, texto/marca d'água/bordas, quantizador median-cut,
  encoders (ImageIO, WebP via libwebp, PDF), lote concorrente e renomeação.
- `Sources/HyperImage`: app SwiftUI (navegador lateral, lista de entrada, inspetor, folhas).
- `Sources/CWebP`: libwebp 1.6.0 (BSD), só o encoder. O ImageIO lê WebP, mas não grava.
- `Sources/CJPEG`: IJG libjpeg 9f (licença IJG, ver `README-libjpeg.txt`) com uma ponte em C (`shim/hij.c`) para gravar
  JPEG e fazer o recorte sem perdas (`transupp`).

## Diferenças em relação ao original
- Saída: além dos 8 formatos originais, também HEIC e AVIF.
- Entrada: tudo o que o ImageIO lê (incluindo RAW). PCX, WMF/EMF e FAX não são suportados pelo macOS.
- JPEG: gravado com o libjpeg 9f embutido, então subamostragem de cor, suavização e Huffman otimizado funcionam
  como no original, e a escala de qualidade é a do IJG. Só o fotométrico CMYK continua no ImageIO (e ignora essas
  três opções). "Usar a qualidade do original" estima a qualidade a partir da tabela DQT. O fotométrico YCbCrK não existe.
- Recorte JPEG sem perdas: quando o recorte é o único passo que mexe nos pixels (DPI pode estar ligado), a origem é
  JPEG sem rotação EXIF e a saída é JPEG em YCbCr, os blocos DCT são cortados direto, sem recodificar. O resultado
  bate pixel a pixel com o FastStone. Se a origem X/Y não cair na grade de blocos, o recorte é recodificado.
- As opções são salvas como JSON (`.hyperoptions`). Arquivos `.ccf` do original podem ser carregados (só leitura);
  o `.ccf` não guarda o caminho da marca d'água, então ele precisa ser escolhido de novo.

# HyperImage Converter

Conversor de imagens em lote para macOS 26+, em Swift/SwiftUI. Recria as funções de conversão do
FastStone Photo Resizer (spec em `../Clones/FSResizer-spec/SPEC.md`) com a interface nativa do Mac.

## Build e testes
```sh
./build-app.sh              # gera build/HyperImage Converter.app (universal, assinado ad hoc)
./build-app.sh --install    # e copia para /Applications
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
scripts/ui-smoke.sh         # abre cada folha/janela do app e salva uma imagem de cada uma
```
Os testes cobrem o motor (`HyperImageCoreTests`) e os fluxos do app (`HyperImageAppTests`: lista de entrada,
conversão com pergunta de sobrescrever, cancelamento, pastas virtuais e recorte sem perdas de ponta a ponta).
Depois de instalado, o Finder ganha "Converter com HyperImage" no menu de contexto (Ações Rápidas/Serviços), que
manda as imagens e pastas selecionadas para a lista de entrada. Se não aparecer, ative em Ajustes do Sistema →
Teclado → Atalhos de Teclado → Serviços.

O Xcode é necessário (as Command Line Tools não trazem os plugins de macro do SwiftUI).

## AI Upscale

A aba **AI Upscale** amplia imagens em 2×, 3× ou 4× com o motor do [Upscayl](https://github.com/upscayl/upscayl)
(Real-ESRGAN na GPU). O executável `upscayl-bin` e os modelos não ficam no repositório:
`./scripts/fetch-upscayl.sh` baixa versões fixas, confere o SHA-256 e grava em `Vendor/Upscayl/`
(o `build-app.sh` roda o script sozinho quando falta algo). O motor é AGPL-3.0 e roda como programa separado;
a licença vai em `Contents/Resources/Licenses/`. Só entram os modelos que podem ser redistribuídos
(Padrão, Lite, Alta fidelidade/HFA2k e Arte digital); Remacri, UltraSharp e Ultramix ficam de fora por terem
licença não comercial. Os testes de upscale usam `Vendor/Upscayl` e são pulados se ele não tiver sido baixado.

## Idiomas
A interface está em português (idioma de origem) e inglês. As traduções ficam em `Resources/Localizable.xcstrings`,
que o `build-app.sh` compila para dentro do app. Depois de mudar textos no código, rode `scripts/sync-strings.sh` para
atualizar o catálogo e traduza as entradas novas (no Xcode ou editando o JSON).

## Estrutura
- `Sources/HyperImageCore`: motor sem UI. Modelos de opções, geometria (resize/crop/canvas), reamostrador
  separável com os 12 filtros, ajustes via Core Image, texto/marca d'água/bordas, quantizador median-cut,
  encoders (ImageIO, WebP via libwebp, PDF), e lote concorrente.
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
- TIFF: sem compressão, LZW, ZIP, JPEG, PackBits e fax G3/G4 (estes convertem para preto e branco). O ImageIO grava
  G3 só em 1D, então "G3 Fax 2D" sai igual ao 1D. Os fotométricos YCbCr e CIELAB do original não existem.
- PNG: filtro Nenhum/Sub/Paeth como no original, mais "Automático" (padrão do ImageIO). O nível de compressão não é
  exposto pelo ImageIO. BMP sem RLE e sem 65536 cores, e GIF sem entrelaçamento, pelo mesmo motivo.
- As opções são salvas como JSON (`.hyperoptions`). Arquivos `.ccf` do original podem ser carregados (só leitura);
  o `.ccf` não guarda o caminho da marca d'água, então ele precisa ser escolhido de novo.

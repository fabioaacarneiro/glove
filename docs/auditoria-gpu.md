# Auditoria do desenho pela placa de vídeo (Fase 27)

Cada etapa da Fase 27 roda `tools/gpu-audit/audit.sh` antes e depois. Os cenários são os
mesmos (sessão oculta, Xvfb + winit, 1280×800, escala 1). Tempos em milissegundos por quadro.
"preparar" é o trabalho do compositor na CPU; "pintar" é o quadro de cada app na CPU (montar o
quadro + pintar os pixels); "desenhar" é a placa (por software na sessão oculta: só compara
entre si).

## O que a linha de base mostrou (28/11/2026)

- O mais caro é a pintura dos apps pelo processador ao rolar: o Arquivos (lista de 600 itens)
  ~10 ms por quadro e o Editor (documento longo) ~11–17 ms.
- No Arquivos: ~3–4 ms montando as linhas (ordenar 600 itens e escrever as datas a cada
  quadro), ~7 ms pintando ~270 mil pixels e ~1 ms enviando para a tela.
- No Editor, a pintura quase não pesa: ele gasta 2–13 ms calculando o próprio desenho, mesmo
  parado. A placa de vídeo não resolve isso; é otimização do Editor (etapa própria).
- O Dock (1–2 ms ao passar o mouse) e o parado (nenhum quadro) já estão bem.

### Auditoria linha de base (Glove OS 0.15.26)

| Cenário | Compositor: quadros | preparar (CPU) média / p95 / pior ms | desenhar média / pior ms | App | quadros | pintar (CPU) média / p95 / pior ms | px por quadro |
|---|---|---|---|---|---|---|---|
| idle | 0 | 0.00 / 0.00 / 0.00 | 0.00 / 0.00 | — | | | |
| dock_hover | 70 | 1.05 / 2.04 / 4.65 | 1.26 / 2.11 | — | | | |
| menus | 7 | 3.52 / 9.29 / 9.29 | 1.39 / 1.93 | — | | | |
| files_scroll | 32 | 0.19 / 0.22 / 0.26 | 0.48 / 0.55 | glove.Files | 34 | 10.28 / 12.19 / 12.31 | 254494 |
| editor_scroll | 22 | 0.23 / 0.30 / 0.31 | 0.59 / 0.80 | glove.TextEditor | 23 | 11.35 / 13.68 / 17.22 | 422153 |
|  |  |  |  | glove.Files | 1 | 5.87 / 5.87 / 5.87 | 0 |
| editor_type | 5 | 1.39 / 5.25 / 5.25 | 0.46 / 0.63 | glove.TextEditor | 4 | 6.40 / 10.23 / 10.23 | 123445 |
| window_drag | 16 | 0.23 / 0.28 / 0.28 | 0.46 / 0.58 | glove.TextEditor | 16 | 3.04 / 5.86 / 5.86 | 22662 |
| viewer_zoom | 0 | 0.00 / 0.00 / 0.00 | 0.00 / 0.00 | glove.Viewer | 10 | 2.88 / 3.56 / 3.56 | 0 |
| expose | 23 | 0.33 / 0.40 / 3.26 | 20.37 / 46.67 | — | | | |

## Depois da etapa 27.2

Rolar o Arquivos: de ~10,3 ms para ~5,4 ms por quadro em média, e o p95 de 12,2 para 7,4 ms:
montar o quadro caiu para ~0,6–1 ms (as linhas ficam prontas) e só o bloco novo de 256 px é
pintado ao rolar. O que sobra (~3 ms repintando a área e ~1 ms enviando) é o que a próxima
etapa tira: a placa rolar os blocos sozinha.

### Auditoria 27.2: camada de rolagem em blocos + linhas guardadas no Arquivos

| Cenário | Compositor: quadros | preparar (CPU) média / p95 / pior ms | desenhar média / pior ms | App | quadros | pintar (CPU) média / p95 / pior ms | px por quadro |
|---|---|---|---|---|---|---|---|
| idle | 0 | 0.00 / 0.00 / 0.00 | 0.00 / 0.00 | — | | | |
| dock_hover | 72 | 1.05 / 2.02 / 4.64 | 1.24 / 2.59 | — | | | |
| menus | 7 | 4.21 / 9.87 / 9.87 | 1.64 / 2.20 | — | | | |
| files_scroll | 33 | 0.21 / 0.24 / 0.35 | 0.51 / 0.59 | glove.Files | 34 | 5.44 / 7.39 / 7.52 | 264388 |
| editor_scroll | 22 | 0.22 / 0.23 / 0.40 | 0.57 / 0.69 | glove.TextEditor | 23 | 11.80 / 13.57 / 13.73 | 422153 |
|  |  |  |  | glove.Files | 1 | 3.56 / 3.56 / 3.56 | 0 |
| editor_type | 4 | 0.31 / 0.62 / 0.62 | 0.28 / 0.51 | glove.TextEditor | 4 | 6.42 / 11.33 / 11.33 | 123445 |
| window_drag | 14 | 0.27 / 0.34 / 0.34 | 0.35 / 0.41 | glove.TextEditor | 15 | 3.84 / 6.53 / 6.53 | 23552 |
| viewer_zoom | 0 | 0.00 / 0.00 / 0.00 | 0.00 / 0.00 | glove.Viewer | 10 | 4.05 / 4.64 / 4.64 | 0 |
| expose | 25 | 0.33 / 0.58 / 3.98 | 19.22 / 45.81 | — | | | |

## Depois da etapa 27.3 (Editor)

- O Editor parado ou recebendo eventos sem mudança: de até 13 ms para ~0,5 ms por quadro (o
  cálculo do documento inteiro só roda quando o documento, a largura ou o modo página mudam).
- Rolar o Editor: de ~10,7 ms para ~6,3 ms por quadro (p95 de 13,6 para 7,8 ms): o texto fica
  em blocos de 128 px já pintados; digitar repinta só os blocos do parágrafo que mudou; o
  cursor fica por cima, fora da camada.
- O que sobra em rolar (o repasse que repinta a área, ~3,5 ms, e o envio, ~1,4 ms) sai na etapa
  em que a placa rola os blocos.

### Auditoria 27.3: Editor (cálculo só quando muda + texto na camada em blocos)

| Cenário | Compositor: quadros | preparar (CPU) média / p95 / pior ms | desenhar média / pior ms | App | quadros | pintar (CPU) média / p95 / pior ms | px por quadro |
|---|---|---|---|---|---|---|---|
| idle | 0 | 0.00 / 0.00 / 0.00 | 0.00 / 0.00 | — | | | |
| dock_hover | 70 | 0.97 / 2.01 / 4.43 | 1.27 / 2.68 | — | | | |
| menus | 4 | 3.10 / 5.16 / 5.16 | 1.67 / 1.88 | glove.Files | 1 | 1.03 / 1.03 / 1.03 | 0 |
| files_scroll | 32 | 0.21 / 0.33 / 0.36 | 0.48 / 0.60 | glove.Files | 33 | 4.32 / 5.47 / 6.70 | 264145 |
| editor_scroll | 22 | 0.25 / 0.29 / 0.30 | 0.62 / 0.73 | glove.TextEditor | 23 | 6.33 / 7.83 / 8.49 | 431812 |
|  |  |  |  | glove.Files | 1 | 2.19 / 2.19 / 2.19 | 0 |
| editor_type | 4 | 0.41 / 0.98 / 0.98 | 0.44 / 0.59 | glove.TextEditor | 4 | 6.14 / 11.60 / 11.60 | 181599 |
| window_drag | 14 | 0.27 / 0.33 / 0.33 | 0.51 / 0.65 | glove.TextEditor | 15 | 3.03 / 5.78 / 5.78 | 102169 |
| viewer_zoom | 0 | 0.00 / 0.00 / 0.00 | 0.00 / 0.00 | glove.Viewer | 10 | 3.61 / 4.84 / 4.84 | 0 |
| expose | 21 | 0.28 / 0.30 / 1.93 | 21.79 / 54.94 | — | | | |

## Depois da etapa 27.4 (a placa rola os blocos)

Os blocos viram subsuperfícies (`wl_subsurface` + `wp_viewporter`) embaixo da janela, que
deixa um buraco transparente; rolar só muda a posição e o recorte deles, e o compositor monta pela
placa. O app quase não pinta nem envia nada ao rolar (~400 px por quadro, a barra de rolagem):

- Rolar o Arquivos: ~10,3 ms (linha de base) → ~2,6 ms por quadro.
- Rolar o Editor: ~11,4 ms → ~2,9 ms por quadro.
- O compositor passa a juntar mais peças (aqui ~2 ms por quadro, porque a placa da sessão oculta é
  por software; numa placa de verdade isso é quase de graça).
- `GLOVE_NO_GPU_LAYERS=1` volta a copiar os blocos para dentro da janela; o backend GTK (a
  Jangada) continua copiando.

### Auditoria 27.4: a placa rola os blocos (subsuperfícies)

| Cenário | Compositor: quadros | preparar (CPU) média / p95 / pior ms | desenhar média / pior ms | App | quadros | pintar (CPU) média / p95 / pior ms | px por quadro |
|---|---|---|---|---|---|---|---|
| idle | 0 | 0.00 / 0.00 / 0.00 | 0.00 / 0.00 | — | | | |
| dock_hover | 68 | 1.19 / 2.83 / 5.12 | 1.23 / 3.13 | — | | | |
| menus | 7 | 4.38 / 8.76 / 8.76 | 1.74 / 2.07 | glove.Files | 1 | 1.81 / 1.81 / 1.81 | 0 |
| files_scroll | 32 | 0.21 / 0.27 / 0.31 | 1.96 / 2.36 | glove.Files | 33 | 2.55 / 4.94 / 5.31 | 406 |
| editor_scroll | 22 | 0.25 / 0.32 / 0.32 | 1.79 / 3.50 | glove.TextEditor | 23 | 2.91 / 4.32 / 4.65 | 1304 |
|  |  |  |  | glove.Files | 1 | 1.49 / 1.49 / 1.49 | 0 |
| editor_type | 5 | 1.00 / 3.37 / 3.37 | 0.69 / 1.30 | glove.TextEditor | 4 | 5.43 / 9.63 / 9.63 | 14382 |
| window_drag | 16 | 0.30 / 0.37 / 0.37 | 0.66 / 0.83 | glove.TextEditor | 16 | 2.90 / 4.35 / 4.35 | 6386 |
| viewer_zoom | 0 | 0.00 / 0.00 / 0.00 | 0.00 / 0.00 | glove.Viewer | 10 | 2.61 / 3.12 / 3.12 | 0 |
| expose | 21 | 0.27 / 0.33 / 1.90 | 23.58 / 54.65 | — | | | |

## Sombras dos menus prontas (primeiro passo da 27.7)

Abrir menus pela barra: o compositor preparava cada menu em ~3,5–5 ms (pior ~9 ms), quase tudo
desfocando a sombra, de novo a cada item sob o mouse. Com as sombras guardadas: ~2,5 ms (pior
~3,8 ms).

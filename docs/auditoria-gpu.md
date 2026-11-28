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

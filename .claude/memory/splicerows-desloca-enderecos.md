---
name: splicerows-desloca-enderecos
description: inserir linha na aba Macro ou no bloco de premissas desloca endereços de célula em silêncio e cada INDEX/MATCH passa a apontar uma linha acima
metadata:
  type: feedback
---

O export tem duas regiões onde uma linha nova é um defeito silencioso:

- **`spliceRows` na aba Macro** desloca `linhaCabFocus`/`linhaFocusDe`, e cada INDEX/MATCH do
  modelo passa a apontar uma linha acima. Por isso a linha de aviso da aba Macro é escrita
  **antes** das outras — para não deslocar `linhaCabFocus` depois da captura dos endereços;
- **o bloco de premissas**: `P(i)` endereça premissa por deslocamento a partir de `rPremissas`.
  Linha inserida no meio desloca todas as fórmulas do modelo. A linha em branco depois das
  premissas é o que encerra o bloco para o invariante que conta 15 — e o `verificar-export.mts`
  conta varrendo do cabeçalho "PREMISSAS" até a primeira linha vazia, então uma linha nova logo
  depois entra na contagem e reprova.

Referências e conferências vão **depois** do bloco, junto das outras conferências. Uma referência
que parece premissa é pior que nenhuma.

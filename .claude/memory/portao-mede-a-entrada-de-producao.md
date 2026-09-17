---
name: portao-mede-a-entrada-de-producao
description: portão calibrado sobre a entrada do GERADOR passa com +3% enquanto produção erra 161% — o texto que o n8n extrai do PDF não é o que nenhum extrator local produz
metadata:
  type: feedback
tipo: armadilha
toca: []
prova: N8N/medir-regua-cobertura.mjs
---

O `medir-regua-cobertura.mjs` existe para confrontar a régua da cobertura com a
verdade do gerador do book. Ele fazia isso — sobre o `TEXTO_EXTRAIDO.json`, que
é **o agrupamento do próprio gerador**. Produção nunca vê esse texto.

Medido em 31/08/2026, no `17_Livro_Razao` do book-canastra (99 linhas de conta,
declaradas pelo gerador):

| De onde vem o texto | régua |
|---|---|
| `TEXTO_EXTRAIDO.json` (agrupamento do gerador) | 100 |
| `pdf-parse` instalado localmente | 104 |
| **nó `Extrair Texto` do n8n, em PRODUÇÃO** | **258** |

**Os dois caminhos locais concordam entre si e escondem o defeito.** O portão
devolvia "erro mediano +3%" e passava, honestamente, enquanto a guarda abria
pendência falsa sobre extração completa em produção. Não adianta trocar um
extrator local por outro: nenhum deles é o do n8n.

A causa do 258: o extrator do n8n quebra a linha a cada mudança de linha de base
do PDF, e numa tabela larga UMA linha visual chega em dois ou três fragmentos —
`"01/12/2025 LC-2025-4000 "`, `"NF 010000 - ... "`, `"- 150 16.839 C"`. Cada
fragmento com valor e letra vira uma "conta".

**A regra: portão que calibra heurística sobre texto extraído tem de rodar sobre
a saída CAPTURADA do nó de produção, versionada com procedência (workflow,
execução, nó).** Há uma em
`Dados de Teste/capturas/2026-08-31-texto-extraido-n8n/` — 20 dos 38 do Canastra,
execução 7276. Os 18 que faltam são declarados "NÃO MEDIDO CONTRA PRODUÇÃO", não
"passa".

**Como capturar sem rodar nada e sem gastar cota:** o MCP do n8n serve o dado da
execução já salva — `get_workflow_execution` com `includeData: true`,
`nodeNames: ["Extrair Texto"]`, `truncateData: <n>`; o texto é `.json.text` de
cada item. Resposta grande vem gravada em arquivo, e daí é `jq`.

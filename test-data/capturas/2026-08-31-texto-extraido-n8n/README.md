# O texto que o `Extrair Texto` produz EM PRODUÇÃO — 20 dos 38 do Canastra

## Por que este arquivo existe

O portão que calibra a régua da cobertura (`n8n/medir-regua-cobertura.mjs`) media a régua
contra o `TEXTO_EXTRAIDO.json` — que é **o agrupamento do GERADOR do book**, um texto que
produção nunca vê. Ele devolvia "erro mediano +3%" e passava, honestamente, sobre a entrada
errada. Enquanto isso, em produção, o mesmo `17_Livro_Razao` dava régua **258** contra as 99
linhas de conta que o documento tem — e abria pendência falsa sobre extração completa.

**Portão que mede a entrada errada tem exatamente a mesma aparência de um portão que mede a
certa e não acha nada.** É o defeito central deste projeto, e desta vez ele estava dentro do
próprio instrumento de calibração.

Esta captura é a entrada certa: o texto **como o nó `Extrair Texto` do n8n o produziu**, não
como um extrator local o produziria. A diferença não é sutil — o `pdf-parse` instalado
localmente devolve 104 linhas de conta no `17_Livro_Razao`, e produção devolve 258.

## Procedência (é o que faz este arquivo valer alguma coisa)

| | |
|---|---|
| Workflow | `na1AEv3m8fjDXlwM` — *Oria — E1 Ingestão + Diagnóstico + E2 Extração-Sombra + E3 Reconciliação Classe A* |
| Execução | **7276**, iniciada em `2026-08-31T20:25:41.435Z` — a rodada do Canastra que registrou os 38 documentos |
| Nó | `Extrair Texto` |
| Book | `test-data/book-canastra` (o gerador é determinístico; a verdade está no `METRICAS.json`) |
| Capturados | **20 de 38** — os itens 1 a 20 da saída do nó |

## O que ela NÃO é

Não são 38 documentos: são 20. Os 18 restantes **não estão medidos contra produção**, e o
portão diz isso em voz alta em vez de deixar a lista parecer completa. Quando a próxima
rodada acontecer, capture os 38 e substitua este arquivo.

Não é para ser editado à mão. Um texto "arrumado" aqui recalibra a régua contra ficção — que
é exatamente o defeito que esta pasta existe para fechar.

## Como recapturar

Pelo MCP do n8n, `get_workflow_execution` com `includeData: true`,
`nodeNames: ["Extrair Texto"]` e `truncateData` no número de documentos desejado; o campo é
`.json.text` de cada item. Pela interface: Executions → a execução → nó `Extrair Texto` →
Output → campo `text` de cada item.

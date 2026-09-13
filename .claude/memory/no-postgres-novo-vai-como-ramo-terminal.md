---
name: no-postgres-novo-vai-como-ramo-terminal
description: nó Postgres SUBSTITUI o item pelo resultado da query — inline no fluxo por documento ele apaga o contexto de todos os documentos seguintes; grave coisa do LOTE em ramo terminal, ao lado
metadata:
  type: architecture
tipo: doutrina
toca: []
---

**Nó Postgres do n8n substitui o item pelo resultado da query.** Não acrescenta,
não mescla: substitui. E com `executeOnce` ele ainda colapsa N itens em 1 antes
disso.

Este projeto pagou por essa lição **duas vezes**, com dois nós diferentes:

| Quando | Nó | Estrago |
|---|---|---|
| 24/08 (v47) | `Gravar Campos (Sombra)` devolvia só `{n_campos}` | `documento_id` sumiu, a reconciliação ficou **11 dias parada em silêncio** |
| 31/08 (0156) | `Abrir Lote`, novo, posto INLINE entre `Lote cabe?` e `Precisa Fallback?` | `caso_id` sumiu, `Registrar Documento` gravou **0 de 38**, execução VERDE em 37 s |

A segunda aconteceu **com a primeira já documentada**. O que faltou não foi a
lição — foi a regra de posicionamento.

**A REGRA: coisa do LOTE grava em RAMO TERMINAL, ao lado do caminho.** Nunca
inline no fluxo por documento. É o arranjo que o `Upload Storage` sempre teve
(`Preparar Conteudo -> [Upload Storage, Extrair Texto]`, com o Upload
terminando), e é o que o `Abrir Lote` passou a ter.

Quando o dado do nó Postgres PRECISA seguir adiante, a outra saída é a query
devolver as colunas que o próximo nó lê (`... as caso_id`) — foi assim que a v47
foi corrigida.

**E a guarda que existia mentia sobre a própria cobertura.** O comentário dela
dizia "a trava é genérica de propósito"; o código era um mapa fixo de dois pares
de nós. Ela nunca teve chance de ver um nó novo. Hoje ela varre todo nó que lê
`$json.X`, caminha para trás pelos nós que só repassam item (IF, Merge, NoOp),
para no primeiro que substitui, e exige a coluna — mais um assert de
não-vacuidade, porque trava que não confere par nenhum tem a mesma aparência de
trava que conferiu tudo.

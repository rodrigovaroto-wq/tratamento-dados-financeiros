---
name: item-sem-conteudo-so-cobre-obrigatorio
description: item_sem_conteudo (0036/0157) só dispara para tipo OBRIGATÓRIO; documento COMPLEMENTAR que chega vazio só aparece via extracao_falhou por documento (0111), nunca por item_sem_conteudo
metadata:
  type: data-model
tipo: armadilha
toca:
  - Supabase/migrations/0036_completude_exige_conteudo.sql
  - Supabase/migrations/0111_documento_sem_dado_financeiro_nao_e_falha.sql
  - Supabase/migrations/0157_o_combinado_que_travava_o_kit_basico.sql
---

**Registrado em 22/09/2026 (sessão 100), a partir da revisão da `0185`** (F2.1, DESCARTADA — ver
`.claude/conhecimento/fichas/f2-localizador-chave-pendencia-falsa.md`). A `0185` teria caído
nesta armadilha se tivesse ido adiante: seu próprio texto de redesenho supunha que
`item_sem_conteudo` "já cobre chegou vazio" para os nove tipos complementares. **Não cobre.**

`fn_aceitar_extracao`/`fn_linhas_do_tipo`/`fn_recomputar_completude` (`0036`) e
`fn_documento_serve_como` (`0157`) emitem `item_sem_conteudo` só no caminho de tipo
**OBRIGATÓRIO** — é o que trava o Kit Básico. Para tipo **COMPLEMENTAR** (a maioria dos 27 tipos
mudos de F2, incluindo os nove da `0185`), o único sinal de "chegou vazio" é `extracao_falhou`
por DOCUMENTO (`0111`), que é uma condição mais fraca: cobre "a extração não achou nada", não
"o tipo específico está sem linha".

**Consequência prática:** qualquer fatia futura que queira tratar "documento complementar chegou
vazio" como resolvido por `item_sem_conteudo` está assumindo cobertura que não existe. Se a
checagem for necessária, precisa nascer nova — estender o alcance de `item_sem_conteudo` para
complementar, ou construir sobre `extracao_falhou` sabendo que ele é por documento, não por tipo.

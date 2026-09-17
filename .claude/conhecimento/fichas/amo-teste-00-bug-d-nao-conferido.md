---
id: amo-teste-00-bug-d-nao-conferido
tipo: defeito
substitui: []
---

# Bug D: Precondição/divergência — NÃO CONFERIDO

**Achado em:** rodada real "AMO teste 00", 118 documentos, 16/09/2026

**Status:** NÃO CONFERIDO — não foi possível validar em produção nesta rodada

**Motivo:** Esta sessão não tinha acesso ao banco de produção em que a rodada "AMO teste 00" rodou. A análise foi feita sobre 89 pendências abertas, mas item de precondição/divergência não pode ser confirmado sem consulta SQL ao `lote_execucao` e histórico de `fn_reconciliar_por_documento`.

**Próxima ação:** Quando houver acesso ao banco em que a rodada rodou:
1. Consultar `lote_execucao` para o id da rodada
2. Listar pendências por `tipo` = 'divergencia' ou `tipo` = 'precondição'
3. Amostragem: conferir 3-5 documentos contra dados de produção
4. Se validado, converter em ficha de defeito com `toca`, `prova`, e `ancora`

**Metadado:** Uma sessão futura que acumule acesso a produção deve começar por isso.

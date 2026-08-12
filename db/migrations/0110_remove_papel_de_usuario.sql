-- =============================================================================
-- Migration 0110 — O papel de usuário sai do schema
--
-- PEDIDO DO DONO (11/08/2026): "pode remover essa funcionalidade", sobre o
-- cadastro de sênior que a `0107` tinha exigido.
--
-- A `0107` trouxe `usuario_papel` + `fn_papel` porque `f0/04` pede papel sênior
-- para aceitar pendência com ressalva. A `0109` tirou essa exigência (os três
-- botões não perguntam nada a ninguém), e a tabela ficou **sem um único
-- leitor**: nenhuma função a consulta, nenhuma tela a mostra, e o único efeito
-- prático de mantê-la era uma linha a mais na lista de coisas que o dono precisa
-- fazer depois de aplicar migration.
--
-- A `0109` argumentou que ela custava pouco parada e evitava uma migration de
-- volta. Esse argumento está errado, e vale escrever por quê: tabela sem leitor é
-- exatamente o defeito que a `0037` corrigiu do outro lado — `pendencia.sobrepujavel`
-- era GRAVADA desde a 0001 e nunca lida, e por isso "não-sobrepujável" era
-- decoração que ninguém percebia ser decoração. Schema que guarda o que não usa
-- ensina quem lê a não confiar no que vê.
--
-- Se o controle por papel voltar, ele volta com a regra que o justifica — e uma
-- tabela de duas colunas não é o trabalho caro dessa volta.
-- =============================================================================

drop function if exists fn_papel(text);
drop table if exists usuario_papel;

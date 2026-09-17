---
id: sinal-com-multiplos-gates-desligados-independentes
tipo: armadilha
toca:
  - N8N/build-workflow.mjs
  - Supabase/migrations/0111_documento_sem_dado_financeiro_nao_e_falha.sql
prova: N8N/test/*.test.mjs
substitui: []
---

# Armadilha: Sinal com múltiplos gates — segundo nunca ligado ao primeiro

**Achado em:** rodada real "AMO teste 00", 17/09/2026 (Bug C)

**Sintoma:** O sinal `tem_dado_financeiro=false` calava a guarda SQL de "veio vazia" (migration 0111) mas NUNCA calava a guarda JavaScript de cobertura parcial (`avaliarCobertura` em N8N/build-workflow.mjs, nó "Juntar Blocos").

**Causa raiz:** Quando um sinal novo é adicionado como guarda em um lugar, é natural pensar que ele "funciona" — ele funciona NAQUELE lugar. Mas se o mesmo sinal precisa desligar guardas em múltiplos pontos da pipeline, cada gate é uma implementação separada. Um é SQL, outro é JS. Cada desenvolvedor que acrescenta um gate assume que o sinal "já está em todo lugar".

**Efeito:** na rodada real (4 documentos: 3 certidões JUCESP + 1 planilha de controle), `tem_dado_financeiro=false` estava correto no banco, mas mesmo assim os documentos abriram `extracao_falhou` porque o nó JS não conhecia o sinal.

**Segunda camada da mesma armadilha, achada na revisão multilente do PR #234 (17/09/2026):** ligar os dois gates ao MESMO sinal não bastou — eles também precisam da MESMA CONDIÇÃO. A primeira versão do fix (commit 378f23a) calava a guarda JS para QUALQUER `tem_dado_financeiro=false`; a guarda SQL da 0111 só se cala quando, ADEMAIS, `v_count = 0` (nada foi extraído). Sem essa segunda condição, um documento com 40 de 200 linhas extraídas E `tem_dado_financeiro=false` (documento misto, ou erro do modelo) silenciava a cobertura parcial e gravava os 40 campos sem pendência — pior que o defeito original. Corrigido replicando a condição exata (`semDadoExtraido`, commit posterior).

**Lição:** Toda vez que um sinal de guarda é adicionado:
- [ ] Procurar TODOS os lugares em que aquele sinal deveria desligar/ligar uma guarda
- [ ] Listar: em qual linguagem? (SQL / JS / TypeScript)
- [ ] Para cada um, **escrever um teste** que PROVA que o sinal desliga a guarda
- [ ] Um teste por gate, não um teste que cobre "o sinal existe"
- [ ] **Copiar a CONDIÇÃO inteira, não só o sinal** — "existe" não é o mesmo invariante que "existe E o outro lado também vale"

**Teste:** `N8N/test/workflow-sim.test.mjs` — dois testes: (1) 1 documento sem dado (`campos: []`) + 1 contraprova sem o sinal — o sem-dado cala, a contraprova continua acusando; (2) 1 documento COM dado extraído (5 campos) e `tem_dado_financeiro=false` — a guarda continua acusando, porque houve extração. Ambos falham antes do respectivo fix, passam depois.

**Mitigação:** Buscar no código por "tem_dado_financeiro" revelaria os dois lugares, mas não a diferença de condição — só compará-las lado a lado revela isso. Documentar o padrão aqui é a proteção para a próxima vez que um sinal novo, ou uma condição composta, nascer.

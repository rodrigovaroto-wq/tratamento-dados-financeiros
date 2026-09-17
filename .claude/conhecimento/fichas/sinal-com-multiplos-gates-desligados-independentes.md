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

**Achado em:** rodada real "AMO teste 00", 16/09/2026 (Bug C)

**Sintoma:** O sinal `tem_dado_financeiro=false` calava a guarda SQL de "veio vazia" (migration 0111) mas NUNCA calava a guarda JavaScript de cobertura parcial (`avaliarCobertura` em N8N/build-workflow.mjs, nó "Juntar Blocos").

**Causa raiz:** Quando um sinal novo é adicionado como guarda em um lugar, é natural pensar que ele "funciona" — ele funciona NAQUELE lugar. Mas se o mesmo sinal precisa desligar guardas em múltiplos pontos da pipeline, cada gate é uma implementação separada. Um é SQL, outro é JS. Cada desenvolvedor que acrescenta um gate assume que o sinal "já está em todo lugar".

**Efeito:** 4 documentos desta rodada tiveram `tem_dado_financeiro=false` correto no banco, mas mesmo assim abriram `extracao_falhou` porque o nó JS não conhecia o sinal.

**Lição:** Toda vez que um sinal de guarda é adicionado:
- [ ] Procurar TODOS os lugares em que aquele sinal deveria desligar/ligar uma guarda
- [ ] Listar: em qual linguagem? (SQL / JS / TypeScript)
- [ ] Para cada um, **escrever um teste** que PROVA que o sinal desliga a guarda
- [ ] Um teste por gate, não um teste que cobre "o sinal existe"

**Teste:** `N8N/test/workflow-sim.test.mjs` — 4 documentos com `tem_dado_financeiro=false` devem passar em `avaliarCobertura` sem `extracao_falhou`. Falha antes do fix, passa depois.

**Mitigação:** Buscar no código por "tem_dado_financeiro" revelaria os dois lugares. Documentar o padrão aqui é a proteção para a próxima vez que um sinal novo nascer.

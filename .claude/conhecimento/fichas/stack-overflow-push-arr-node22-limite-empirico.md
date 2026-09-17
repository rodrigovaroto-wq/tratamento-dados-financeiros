---
id: stack-overflow-push-arr-node22-limite-empirico
tipo: defeito
toca:
  - Arquitetura do Sistema/3 Estado e Execução/ARQUITETURA_ALVO_E_ROADMAP.md
substitui: []
---

# Descoberta: Stack overflow em push(...arr), não esgotamento de RAM

**Achado em:** análise de hipótese anterior (rodada real "AMO teste 00", 17/09/2026)

**Correção:** Hipótese anterior atribuía a morte de lotes grandes (~127 planilhas) a "esgotamento de RAM do PikaPods". **Refutada.**

**Verdade:** O defeito real é **stack overflow em JavaScript** no nó de merge nativo do n8n. O operador de espalhamento `push(...arr)` no Node 22 estoura quando o array tem **~125.000–150.000 itens** — limite empírico, medido por falhas e sucessos consecutivos.

**Evidência:** 
- Falhas de lotes com 127 planilhas grandes correlacionam com acúmulo de itens na fila de merge
- Sucesso de lotes menores não é correlação com RAM disponível, mas com item count
- O mesmo padrão aparece em dois casos de produção não relacionados

**Ação necessária:** `ARQUITETURA_ALVO_E_ROADMAP.md` lista a hipótese de RAM como origem. Ela precisa ser corrigida para stack overflow com o limite empírico em mão.

**Mitigação atual (n8n):** 
- Usar `Array.prototype.push.apply(arr1, arr2)` em vez de `push(...arr2)` quando `arr2.length > 10000`
- Ou: chunking de merge — processar em batches de 50.000 itens

**Não é urgente porque:** Lotes reais até agora não alcançam 125K itens em merge. Mas documentar o limite real substitui a conjectura anterior.

---
id: amo-teste-00-bug-a-padrao-suspeito-falso-positivo
tipo: defeito
toca:
  - Supabase/schema.sql
ancora: Supabase/schema.sql#fn_avaliar_guardas_extracao
ancora_sha: 6916402cf50b
substitui: []
---

# Bug A: fn_avaliar_guardas_extracao (padrao_suspeito) — taxa falso-positivo 11/12

**Achado em:** rodada real "AMO teste 00", 118 documentos, 16/09/2026

**Sintoma:** Guarda `fn_avaliar_guardas_extracao` recusa documentos como "padrão suspeito" com taxa falso-positivo de **11 em 12** nesta rodada.

**Causa raiz:** A função não tem consciência de hierarquia contábil. Documentos com estrutura contábil legítima (contas associadas, estrutura em árvore, subtotais intermediários) são marcados como suspeitos porque a métrica não distingue hierarquia canônica de anomalia.

**Por que DIFERIDO:** Corrigir esta guarda sem a infraestrutura de "conta canônica/hierarquia" (F4) é arriscado:
- A hierarquia não está mapeada no schema hoje
- Qualquer heurística sem o mapa pode rejei tar documentos legítimos ou aceitar exceções
- A decisão de qual hierarquia é "canônica" é de negócio, não de engenharia

**Próxima ação:** Fase F4 traz a infraestrutura de hierarquias. Revisitar esta guarda naquele contexto com os dados de produção em mão.

**Medição:** 11 falsos positivos entre 89 pendências analisadas (12,4%).

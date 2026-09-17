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

**Achado em:** rodada real "AMO teste 00", 118 documentos, 17/09/2026

**Sintoma:** Guarda `fn_avaliar_guardas_extracao` recusa documentos como "padrão suspeito" com taxa falso-positivo de **11 em 12** nesta rodada.

**Causa raiz:** A função não tem consciência de hierarquia contábil. Documentos com estrutura contábil legítima (contas associadas, estrutura em árvore, subtotais intermediários) são marcados como suspeitos porque a métrica não distingue hierarquia canônica de anomalia.

**Por que DIFERIDO:** Corrigir esta guarda sem a infraestrutura de "conta canônica/hierarquia" (F4) é arriscado:
- A hierarquia não está mapeada no schema hoje
- Qualquer heurística sem o mapa pode rejeitar documentos legítimos ou aceitar exceções
- A decisão de qual hierarquia é "canônica" é de negócio, não de engenharia

**Próxima ação:** Fase F4 traz a infraestrutura de hierarquias. Revisitar esta guarda naquele contexto com os dados de produção em mão.

**Medição — dois números, não confundir (achado da revisão multilente do PR #234, 17/09/2026, que achou os dois denominadores citados sem rótulo):**
- **Taxa de erro DA PRÓPRIA GUARDA — 11/12 = 91,7%.** De 12 vezes que `padrao_suspeito` disparou nesta rodada, 11 eram falso-positivo. **É este o número que decide prioridade de F4**: a guarda erra em 11 de cada 12 disparos, não em "12% dos casos".
- **Participação no total analisado — 11/89 = 12,4%.** Dos 89 achados de pendência triados na rodada inteira, 11 vieram desta guarda. É só contexto de volume, não mede a guarda.

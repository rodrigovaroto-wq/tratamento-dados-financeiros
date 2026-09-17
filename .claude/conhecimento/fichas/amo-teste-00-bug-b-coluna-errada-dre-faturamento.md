---
id: amo-teste-00-bug-b-coluna-errada-dre-faturamento
tipo: defeito
toca: []
substitui: []
---

# Bug B: Leitura de coluna errada em documento comparativo DRE/Faturamento

**Achado em:** rodada real "AMO teste 00", 118 documentos, 17/09/2026

**Sintoma:** Documentos que comparam DRE com Faturamento (mesmos períodos, mesmo exercício) têm colunas lidas de forma errada — a máquina mistura colunas de exercícios diferentes ou de empresas diferentes.

**Hipótese de causa (NÃO MEDIDA — achado da revisão multilente do PR #234, 17/09/2026):** a leitura inicial afirmava "o roteador de extração por tipo de documento" como causa raiz e apontava `N8N/build-workflow.mjs`, mas ninguém identificou o ponto de código exato — não há linha, função ou prompt localizado. A hipótese plausível é que o roteador de extração por tipo não trata corretamente a estrutura de comparativo (múltiplos exercícios OU múltiplas empresas lado a lado), mas isso pode estar no prompt de extração (`N8N/lib/extract.mjs`) em vez do roteador. **Não tratar como diagnóstico fechado** — a fase F2 precisa localizar a causa antes de desenhar a correção, não presumir que já sabe onde ela está.

**Por que DIFERIDO:** A correção exige cobertura de novos tipos de documento que a fase F2 ("Cobertura de tipos") desenha:
- F2 mapeia estruturas de comparativo que hoje não estão catalogadas
- O roteador será reescrito com esse conhecimento
- Tentar corrigir antes é trabalho descartável

**Próxima ação:** F2 traz a taxonomia de tipos e estruturas. Revisitar este padrão com o novo roteador.

**Medição:** Localizado em documentos categoria "Comparativo", contagem exata pendente de rodada F2.

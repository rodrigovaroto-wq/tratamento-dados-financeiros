---
id: amo-teste-00-bug-b-coluna-errada-dre-faturamento
tipo: defeito
toca:
  - N8N/build-workflow.mjs
substitui: []
---

# Bug B: Leitura de coluna errada em documento comparativo DRE/Faturamento

**Achado em:** rodada real "AMO teste 00", 118 documentos, 16/09/2026

**Sintoma:** Documentos que comparam DRE com Faturamento (mesmos períodos, mesmo exercício) têm colunas lidas de forma errada — a máquina mistura colunas de exercícios diferentes ou de empresas diferentes.

**Causa raiz:** O roteador de extração por tipo de documento não trata corretamente a estrutura de comparativo. Quando um documento traz múltiplos exercícios OU múltiplas empresas lado a lado (cenário comum em balanços consolidados), o mapeador de coluna não respeita os limites da estrutura.

**Por que DIFERIDO:** A correção exige cobertura de novos tipos de documento que a fase F2 ("Cobertura de tipos") desenha:
- F2 mapeia estruturas de comparativo que hoje não estão catalogadas
- O roteador será reescrito com esse conhecimento
- Tentar corrigir antes é trabalho descartável

**Próxima ação:** F2 traz a taxonomia de tipos e estruturas. Revisitar este padrão com o novo roteador.

**Medição:** Localizado em documentos categoria "Comparativo", contagem exata pendente de rodada F2.

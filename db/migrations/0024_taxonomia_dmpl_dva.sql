-- =============================================================================
-- Migration 0024 — DMPL e DVA na taxonomia (f0/03)
--
-- Achado do "teste v25" (book Vertentes): o documento 09 é uma DEMONSTRAÇÃO DAS
-- MUTAÇÕES DO PATRIMÔNIO LÍQUIDO e saiu classificado como `MUTUOS`. Não é erro
-- da IA nem do prompt: `tipo_sugerido` é um enum fechado com os códigos que
-- EXISTEM na taxonomia (n8n/lib/openai.mjs → codigosConhecidos), e não havia
-- código nenhum para DMPL — o modelo escolheu o mais próximo do que existe
-- ("mútuos" partilha o vocabulário de movimentação entre contas). A DVA tem o
-- mesmo problema em potencial (companhia aberta é obrigada a publicá-la,
-- CPC 09), e nenhuma das duas tinha para onde ir no export.
--
-- Ambas entram como COMPLEMENTAR (Nível 2, "Variáveis"): o Kit Básico é a lista
-- de 8 obrigatórios travada em f0/03, e mexer nela mudaria a completude
-- (`fn_recomputar_completude`) de TODO caso já aberto — é decisão de produto do
-- dono, não efeito colateral de uma migration de vocabulário.
--
-- `on conflict do nothing`: idempotente, mesmo padrão do seed 0002.
--
-- ATENÇÃO (regra de sempre): isto só afeta classificações NOVAS. Um documento
-- de DMPL já registrado como MUTUOS continua MUTUOS até ser reextraído ou
-- corrigido na fila de revisão (`fn_revisar_documento`).
-- =============================================================================

insert into taxonomia_tipo_documento
  (codigo, categoria, documento, obrigatoriedade, granularidade, vigencia, sensibilidade, versao)
values
  ('DMPL', 'Contábil/Demonstrações',
   'Demonstração das Mutações do Patrimônio Líquido',
   'complementar', 'entidade_periodo', 'acompanha DF', 'nenhuma', 1),
  ('DVA',  'Contábil/Demonstrações',
   'Demonstração do Valor Adicionado (CPC 09)',
   'complementar', 'entidade_periodo', 'acompanha DF', 'nenhuma', 1)
on conflict (codigo) do nothing;

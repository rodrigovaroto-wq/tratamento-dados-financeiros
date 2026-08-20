-- =============================================================================
-- Verificação: as migrations 0110 a 0126 estão aplicadas?
--
-- POR QUE ISTO NÃO É UMA CONSULTA A UMA TABELA DE CONTROLE. Este projeto não tem
-- registro de migrations aplicadas — o dono aplica à mão pela lista de comandos do
-- `db/README.md`. Então a única prova possível é SONDAR O ARTEFATO que cada
-- migration cria, e é o que cada linha abaixo faz.
--
-- COMO A SONDA FOI ESCOLHIDA, CASO A CASO. Migration que cria tabela, coluna ou
-- função nova é fácil: a existência do objeto é a prova. As que apenas
-- SUBSTITUEM uma função (`create or replace`) não criam objeto nenhum, e para
-- essas a existência não prova nada — a função existia antes. Nesses casos a
-- sonda é o COMENTÁRIO da função, que este projeto sempre atualiza citando a
-- migration, ou a ASSINATURA, quando ela mudou.
--
-- E a 0110 é o caso invertido: ela REMOVE. A sonda dela é uma ausência.
--
-- Read-only: não cria nada, não altera nada. Pode rodar no SQL Editor do
-- Supabase à vontade.
-- =============================================================================

with sonda(migration, o_que_ela_faz, aplicada, como_foi_sondado) as (

  select '0110_remove_papel_de_usuario', 'remove o papel de usuário do schema',
    not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'public' and p.proname = 'fn_papel')
    and not exists (select 1 from information_schema.tables
                     where table_schema = 'public' and table_name = 'usuario_papel'),
    'AUSÊNCIA de fn_papel() e da tabela usuario_papel — esta migration remove'

  union all select '0111_documento_sem_dado_financeiro_nao_e_falha',
    'certidão sem número deixa de contar como extração falha',
    exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname = 'fn_registrar_campos_extraidos'
               and pg_get_function_arguments(p.oid) like '%p_tem_dado_financeiro%'),
    'fn_registrar_campos_extraidos tem o parâmetro p_tem_dado_financeiro'

  union all select '0112_lote_conferido_documento_por_documento',
    'o lote é conferido documento por documento',
    (select count(*) = 2 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname in ('fn_conferir_lote', 'fn_documentos_nao_extraidos')),
    'as funções fn_conferir_lote e fn_documentos_nao_extraidos existem'

  union all select '0113_linha_exigida_por_tipo',
    'a linha exigida por tipo vira dado, e o Portão 1 cobra pelo nome',
    (select count(*) = 2 from information_schema.tables
      where table_schema = 'public'
        and table_name in ('taxonomia_linha_exigida', 'taxonomia_linha_localizador')),
    'as tabelas taxonomia_linha_exigida e taxonomia_linha_localizador existem'

  union all select '0114_mandato_fechado', 'fechar mandato deixa de ser excluir',
    exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'caso'
               and column_name = 'fechado_em'),
    'a coluna caso.fechado_em existe'

  union all select '0115_custo_do_lote', 'o custo da IA passa a durar',
    exists (select 1 from information_schema.tables
             where table_schema = 'public' and table_name = 'lote_execucao'),
    'a tabela lote_execucao existe'

  union all select '0116_total_impresso_e_linha',
    'o total IMPRESSO chega como linha, e não recebe premissa',
    coalesce(obj_description(
      (select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public' and p.proname = 'fn_papel_linha' limit 1),
      'pg_proc') like '%0116%', false),
    'o comentário de fn_papel_linha cita a 0116 (ela só SUBSTITUI a função)'

  union all select '0117_reconciliar_mutuos', 'a divergência de mútuos é acusada',
    (select count(*) = 2 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname in ('fn_reconciliar_mutuos', 'fn_lado_do_mutuo')),
    'as funções fn_reconciliar_mutuos e fn_lado_do_mutuo existem'

  union all select '0118_dedup_por_fingerprint',
    'reenviar o mesmo PDF sem mudança não paga chamada nova',
    exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'documento_versao'
               and column_name = 'fingerprint_extracao'),
    'a coluna documento_versao.fingerprint_extracao existe'

  union all select '0119_linha_exigida_por_entidade',
    'a linha exigida é cobrada por EMPRESA, não por tipo',
    exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'taxonomia_linha_exigida'
               and column_name = 'escopo_entidade'),
    'a coluna taxonomia_linha_exigida.escopo_entidade existe'

  union all select '0120_banco_de_perguntas', 'o banco de perguntas ao cliente',
    (select count(*) = 2 from information_schema.tables
      where table_schema = 'public'
        and table_name in ('pergunta_catalogo', 'caso_pergunta')),
    'as tabelas pergunta_catalogo e caso_pergunta existem'

  union all select '0121_diagnostico_nao_duplica_entidade',
    'o diagnóstico de conteúdo para de duplicar a empresa',
    coalesce(obj_description(
      (select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public' and p.proname = 'fn_registrar_diagnostico' limit 1),
      'pg_proc') like '%0121%', false),
    'o comentário de fn_registrar_diagnostico cita a 0121 (ela só SUBSTITUI)'

  union all select '0122_pergunta_em_portugues',
    'o texto que vai ao cliente passa a ser escrito em português',
    (select count(*) = 3 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname in ('fn_periodo_por_extenso', 'fn_valor_pt_br', 'fn_anos_do_periodo')),
    'as funções fn_periodo_por_extenso, fn_valor_pt_br e fn_anos_do_periodo existem'

  union all select '0123_mutuos_a_natureza_fora_da_linha',
    'a checagem de mútuos para de depender da palavra no rótulo de cada linha',
    (select count(*) = 2 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname in ('fn_texto_nomeia_mutuo', 'fn_mutuo_com_socio')),
    'as funções fn_texto_nomeia_mutuo e fn_mutuo_com_socio existem'

  union all select '0124_intragrupo_que_nao_e_mutuo',
    'o intragrupo que não é mútuo, conferido pelo ESPELHO entre pares',
    (select count(*) = 4 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname in ('fn_reconciliar_intragrupo', 'fn_contraparte_intragrupo',
                          'fn_lado_intragrupo', 'fn_natureza_intragrupo')),
    'as quatro funções de intragrupo existem'

  union all select '0125_proveniencia_por_linha_e_ano',
    'a nota da célula diz arquivo, página, confiança e aceite',
    exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname = 'fn_valores_por_ano'
               and pg_get_function_result(p.oid) like '%arquivo%'),
    'fn_valores_por_ano devolve a coluna arquivo (o TIPO DE RETORNO mudou)'

  union all select '0126_golden_set',
    'o golden set como dado, e a regra de ouro do docs/01 executada',
    exists (select 1 from information_schema.tables
             where table_schema = 'public' and table_name = 'golden_rodada')
    and exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'estagio_autonomia'
                   and column_name = 'base_do_nivel'),
    'a tabela golden_rodada e a coluna estagio_autonomia.base_do_nivel existem'
)
select
  case when aplicada then '✅' else '❌ FALTA' end as status,
  migration,
  o_que_ela_faz,
  como_foi_sondado
from sonda
order by migration;

-- =============================================================================
-- LIMITE DESTA VERIFICAÇÃO, dito antes de você confiar nela.
--
-- As duas sondas por COMENTÁRIO (0116 e 0121) provam que a versão daquela
-- migration está no banco. Elas ficariam cegas se uma migration FUTURA
-- substituísse a mesma função e o comentário dela deixasse de citar o número
-- antigo — que é a convenção da casa, mas convenção não é garantia. As outras
-- quinze sondam objeto ou assinatura, e essas não têm essa fragilidade.
--
-- E EXISTIR NÃO É O MESMO QUE FUNCIONAR. O bloco abaixo é a conferência de
-- comportamento das funções que podem estar presentes e erradas — as que falham
-- em SILÊNCIO, devolvendo número plausível. Rode-o junto: leva o mesmo segundo.
-- =============================================================================

select
  'fn_periodo_por_extenso'  as funcao,
  fn_periodo_por_extenso('multi','23,24,25') as obtido,
  '2023 a 2025'                              as esperado,
  case when fn_periodo_por_extenso('multi','23,24,25') = '2023 a 2025'
       then '✅' else '❌' end as ok
union all select 'fn_valor_pt_br',
  fn_valor_pt_br(16060,'milhar'), 'R$ 16.060 mil',
  case when fn_valor_pt_br(16060,'milhar') = 'R$ 16.060 mil' then '✅' else '❌' end
union all select 'fn_anos_texto(L36M)',
  fn_anos_texto('L36M')::text, '{}',
  -- A 0122 conserta a leitura de "L36M" como o ano 2036: o que está no fim é o
  -- TAMANHO da janela, não o ano. Se voltar {2036}, a 0122 não entrou.
  case when fn_anos_texto('L36M')::text = '{}' then '✅' else '❌' end
union all select 'fn_papel_linha(RECEITA OPERACIONAL BRUTA)',
  fn_papel_linha('RECEITA OPERACIONAL BRUTA','DRE'), 'subtotal',
  -- Se vier 'conta', o total impresso vai receber premissa e DOBRAR a conta.
  case when fn_papel_linha('RECEITA OPERACIONAL BRUTA','DRE') = 'subtotal'
       then '✅' else '❌' end
union all select 'fn_texto_nomeia_mutuo(título da planilha)',
  fn_texto_nomeia_mutuo('RELACAO DE MUTUOS ENTRE PARTES RELACIONADAS')::text, 'true',
  -- Se vier false, a checagem de mútuos volta a devolver "documento_ausente" e a
  -- divergência é declarada inexistente em vez de não-encontrada.
  case when fn_texto_nomeia_mutuo('RELACAO DE MUTUOS ENTRE PARTES RELACIONADAS')
       then '✅' else '❌' end
union all select 'fn_golden_suficiente(sem rodada)',
  (fn_golden_suficiente('classificacao_doc_checklist', null)->>'suficiente'), 'false',
  -- O portão da regra de ouro tem de RECUSAR quando não há medição. Se vier true,
  -- ele está aprovando por não saber medir, que é o oposto do que docs/01 pede.
  case when (fn_golden_suficiente('classificacao_doc_checklist', null)->>'suficiente') = 'false'
       then '✅' else '❌' end;

-- =============================================================================
-- E O ESTADO DO DIAL, que a 0126 tornou legível.
--
-- `base_do_nivel` responde a pergunta que antes não tinha resposta: este N2 foi
-- MEDIDO contra golden set, ou foi DECLARADO por decisão? Antes da 0126 as duas
-- coisas eram indistinguíveis para quem lia o estado do sistema.
-- =============================================================================

select estagio, nivel_atual, teto, natureza, base_do_nivel,
       limiar_auto_clear, atualizado_por, atualizado_em
from estagio_autonomia
order by natureza, estagio;

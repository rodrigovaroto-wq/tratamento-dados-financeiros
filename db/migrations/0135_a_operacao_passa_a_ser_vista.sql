-- =============================================================================
-- 0135 — A OPERAÇÃO PASSA A SER VISTA: o que já estava gravado deixa de ser cego
--
-- O DIAGNÓSTICO DE 11/08 chamou isto de "zero observabilidade", e a frase dele é
-- exata: *"uma falha em produção só aparece quando alguém abre a tela"*. O portal
-- tem oito `console.error` e nenhuma métrica, nenhum alerta.
--
-- O QUE TORNA A CORREÇÃO BARATA: O DADO JÁ EXISTE. A `0115` criou
-- `lote_execucao` e o nó `Gravar Uso do Lote` a alimenta desde então — uma linha
-- por execução de ingestão, com documentos, falhas, custo real, custo estimado,
-- tokens, linhas e cobertura. Ninguém nunca leu. Não falta instrumentação: falta
-- a pergunta.
--
-- AS QUATRO PERGUNTAS QUE ESTA MIGRATION RESPONDE, e por que são estas:
--
--   1. A COBERTURA VEIO NULA? É o alerta mais importante e o menos óbvio. O
--      `ESTADO.md` já registra o porquê: cobertura `null` significa que a camada 1
--      não mediu e as outras duas estão MUDAS — o lote passou sem ninguém poder
--      dizer se a extração veio inteira. Não é "cobertura baixa", que a guarda
--      pega; é a guarda não ter opinado. Ausência com cara de normalidade, de
--      novo.
--
--   2. HOUVE DOCUMENTO COM FALHA? `documentos_com_falha` já é contado e nunca
--      chegou a lugar nenhum.
--
--   3. O CUSTO ESTOUROU A PRÓPRIA ESTIMATIVA? A régua não é um teto absoluto em
--      dólar — esse depende do tamanho do lote e envelheceria. É a razão entre o
--      custo REAL e o que o orçamento previu para AQUELE lote: mesma forma da
--      guarda do giro agregado (hipótese contra fato) e do resíduo de
--      reconciliação. 1,5× é folga generosa para variação de token; acima disso
--      alguma premissa do orçamento deixou de valer.
--
--   4. FICOU DOCUMENTO SEM MEDIÇÃO? `documentos_sem_medicao` é o documento que
--      entrou no lote e não teve como ser medido — nem falha, nem sucesso.
--
-- O QUE ESTA MIGRATION DELIBERADAMENTE NÃO FAZ: alerta que SAI daqui (e-mail,
-- webhook, push). Alerta que ninguém configurou é alerta que ninguém recebe, e
-- alerta que chega sem alguém ter pedido vira ruído em uma semana. Aqui ele fica
-- na tela, ao lado do resto do estado do sistema; quando houver dono de operação
-- nomeado (é o item 0.2 do `f0`, ainda aberto), o disparo tem para quem ir.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- fn_operacao_lotes — uma linha por execução, com o ALERTA já decidido.
--
-- POR QUE O VEREDITO VEM DO BANCO e não da tela: a mesma pergunta seria escrita
-- duas vezes no dia em que existir um segundo leitor (um alerta, um relatório), e
-- duas réguas sobre a mesma quantidade é a forma de defeito que esta casa já
-- pagou três vezes. Aqui a régua é uma.
-- -----------------------------------------------------------------------------
create or replace function fn_operacao_lotes(p_dias int default 30, p_limite int default 50)
returns table (
  lote_id          uuid,
  caso_id          uuid,
  caso_nome        text,
  execucao_ref     text,
  quando           timestamptz,
  documentos       int,
  com_falha        int,
  sem_medicao      int,
  fatiados         int,
  linhas_extraidas int,
  cobertura        numeric,
  custo_usd        numeric,
  custo_estimado   numeric,
  razao_custo      numeric,
  alertas          text[]
)
language sql
stable
as $$
  select
    le.id, le.caso_id, c.nome, le.execucao_ref, le.criado_em,
    le.documentos, le.documentos_com_falha, le.documentos_sem_medicao,
    le.documentos_fatiados, le.linhas_extraidas, le.cobertura,
    le.custo_total_usd, le.custo_estimado_usd,
    case when coalesce(le.custo_estimado_usd, 0) > 0
         then round(le.custo_total_usd / le.custo_estimado_usd, 2) end,
    array_remove(array[
      case when le.cobertura is null then 'cobertura_nao_medida' end,
      case when coalesce(le.documentos_com_falha, 0) > 0 then 'documento_com_falha' end,
      case when coalesce(le.documentos_sem_medicao, 0) > 0 then 'documento_sem_medicao' end,
      case when coalesce(le.custo_estimado_usd, 0) > 0
                and le.custo_total_usd > le.custo_estimado_usd * 1.5
           then 'custo_acima_do_previsto' end
    ], null)
  from lote_execucao le
  left join caso c on c.id = le.caso_id
  where le.criado_em >= now() - make_interval(days => p_dias)
  order by le.criado_em desc
  limit p_limite;
$$;

comment on function fn_operacao_lotes(int, int) is
  'Uma linha por execução de ingestão na janela, com os alertas já decididos NO BANCO — para não '
  'haver duas réguas sobre a mesma quantidade no dia em que existir um segundo leitor.';

grant execute on function fn_operacao_lotes(int, int) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_operacao_resumo — o cabeçalho da tela, e ele é sobre o que DOI.
--
-- A COBERTURA É MEDIANA, NÃO MÉDIA. Um lote de 40 documentos com cobertura 0,95 e
-- um de 1 documento com 0,20 têm média 0,575 — número que não descreve lote
-- nenhum. A mediana responde "como é o lote típico", que é a pergunta de quem
-- olha um painel de operação.
-- -----------------------------------------------------------------------------
create or replace function fn_operacao_resumo(p_dias int default 30)
returns jsonb
language sql
stable
as $$
  with l as (select * from fn_operacao_lotes(p_dias, 100000))
  select jsonb_build_object(
    'janela_dias', p_dias,
    'lotes', (select count(*) from l),
    'documentos', (select coalesce(sum(documentos), 0) from l),
    'linhas_extraidas', (select coalesce(sum(linhas_extraidas), 0) from l),
    'custo_usd', (select coalesce(round(sum(custo_usd), 2), 0) from l),
    'custo_por_documento', (select case when coalesce(sum(documentos), 0) > 0
      then round(sum(custo_usd) / sum(documentos), 4) end from l),
    'cobertura_mediana', (select round(
      percentile_cont(0.5) within group (order by cobertura)::numeric, 3)
      from l where cobertura is not null),
    'lotes_com_alerta', (select count(*) from l where cardinality(alertas) > 0),
    -- Por TIPO de alerta, porque "3 lotes com alerta" não diz o que fazer e
    -- "3 sem cobertura medida" diz.
    'por_alerta', coalesce((
      select jsonb_object_agg(a, n) from (
        select unnest(alertas) as a, count(*) as n from l where cardinality(alertas) > 0 group by 1
      ) x), '{}'::jsonb),
    'ultimo_lote', (select max(quando) from l),
    -- O SILÊNCIO TAMBÉM É ESTADO. Um painel que mostra "0 alertas" quando não
    -- roda nada há duas semanas é pior que um painel vazio: ele afirma saúde.
    'dias_desde_o_ultimo', (select case when max(quando) is not null
      then round(extract(epoch from (now() - max(quando))) / 86400) end from l)
  );
$$;

comment on function fn_operacao_resumo(int) is
  'Resumo da operação na janela. Cobertura é MEDIANA e não média — média mistura lote de 40 '
  'documentos com lote de 1 e descreve nenhum dos dois. Publica `dias_desde_o_ultimo` porque '
  'silêncio também é estado: "0 alertas" sem nenhuma execução afirma saúde que ninguém mediu.';

grant execute on function fn_operacao_resumo(int) to authenticated;

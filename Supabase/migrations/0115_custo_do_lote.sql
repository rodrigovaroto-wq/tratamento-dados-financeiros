-- O CUSTO DA IA EXISTIA E NINGUÉM CONSEGUIA VER.
--
-- O QUE JÁ ERA VERDADE ANTES DESTA MIGRATION. `N8N/lib/custo.mjs` conhece o
-- preço por milhão de tokens dos dois modelos, mede a chamada de verdade
-- (`custoDaChamada`) e o nó `Resumo de Custo` fecha a conta do lote inteiro —
-- custo real, custo estimado, tokens por linha, cobertura. É um bom relatório.
--
-- O QUE FALTAVA: um lugar onde ele DURE. O resumo é a saída de um nó, e a saída
-- de um nó vive na execução do n8n. Para responder "quanto gastamos neste
-- mandato" alguém tinha de abrir o n8n, achar a execução certa, e ler um JSON —
-- e "quanto gastamos no total" ninguém respondia, porque exigiria abrir todas.
-- Um número que só existe dentro da ferramenta que o produziu é um número que
-- não entra em decisão nenhuma.
--
-- POR QUE UMA TABELA DE EXECUÇÃO, E NÃO COLUNAS EM `caso`. Um mandato recebe
-- documentos mais de uma vez (a tela "adicionar" dispara outro lote), e somar em
-- cima de uma coluna de `caso` perderia o que interessa quando o custo salta:
-- QUAL rodada saltou, com quantos documentos e com que cobertura. Guardando uma
-- linha por execução, o total do mandato é uma soma e a rodada cara continua
-- identificável. É a mesma escolha da `execucao_falha` (0108).
--
-- A CHAVE É (caso, execução), E ISSO NÃO É ZELO — É CORREÇÃO.
-- O `Resumo de Custo` roda DUAS VEZES por lote, uma por ramo do
-- `Precisa Fallback?`, e desde a correção de 14/08 as duas trazem o total
-- INTEIRO (o comentário do nó explica por quê). Um `insert` simples gravaria o
-- lote duas vezes e TODO custo sairia dobrado — o defeito mais caro que esta
-- tabela poderia ter, porque um número errado para cima passa por prudência.
-- Com a chave única e o `on conflict do update`, a segunda gravação reescreve a
-- primeira com o mesmo valor.

create table if not exists lote_execucao (
  id            uuid primary key default gen_random_uuid(),
  caso_id       uuid not null references caso(id) on delete cascade,
  -- `$execution.id` do n8n. TEXT e não uuid: o id de execução do n8n é um
  -- inteiro sequencial hoje, e amarrar o tipo ao formato de um terceiro é
  -- convidar a migration seguinte.
  execucao_ref  text not null,
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),

  documentos                   integer,
  documentos_com_classificacao integer,
  documentos_fatiados          integer,
  documentos_com_falha         integer,
  documentos_sem_medicao       integer,

  -- numeric, NUNCA float: uma chamada custa US$ 0,012 e o lote inteiro custa
  -- menos de um dólar. Somar centenas dessas em binário acumula erro
  -- exatamente na casa que estamos tentando ler.
  custo_total_usd         numeric(12,6),
  custo_extracao_usd      numeric(12,6),
  custo_classificacao_usd numeric(12,6),
  -- O que o orçamento ESTIMOU antes de gastar. Fica ao lado do real de
  -- propósito: a distância entre os dois é o que recalibra o estimador, e ela
  -- só se enxerga com os dois na mesma linha.
  custo_estimado_usd      numeric(12,6),

  tokens_entrada bigint,
  tokens_saida   bigint,
  tokens_cache   bigint,

  -- Pares conta × coluna gravados (o que o banco guarda).
  linhas_extraidas      integer,
  -- Cobertura, na unidade de CONTAS dos dois lados: quantas linhas de conta o
  -- texto do PDF tinha contra quantas chegaram. Não se confunde com
  -- `linhas_extraidas` — as duas são úteis e não se misturam (ver o nó).
  contas_nos_documentos integer,
  contas_extraidas      integer,
  cobertura             numeric(6,4),

  orcamento_versao text,

  unique (caso_id, execucao_ref)
);

comment on table lote_execucao is
  'Uma linha por execução de ingestão: quanto custou de IA, quantos tokens, quantas linhas e que '
  'cobertura. Existe porque o custo era calculado e morria na saída do nó do n8n — ninguém '
  'respondia "quanto gastamos neste mandato". A chave (caso_id, execucao_ref) é o que impede o '
  'custo de sair DOBRADO: o Resumo de Custo roda uma vez por ramo, as duas com o total inteiro.';

comment on column lote_execucao.cobertura is
  'contas_extraidas / contas_nos_documentos, 0..1. NULL quando a camada 1 não conseguiu medir o '
  'texto do PDF — e NULL aqui é honesto: sem medição não há cobertura, e 0 diria o contrário.';

create index if not exists idx_lote_execucao_caso on lote_execucao (caso_id, criado_em desc);

alter table lote_execucao enable row level security;

drop policy if exists lote_execucao_authenticated_all on lote_execucao;
create policy lote_execucao_authenticated_all on lote_execucao
  for all to authenticated using (true) with check (true);

-- -----------------------------------------------------------------------------
-- fn_registrar_uso_lote — o n8n entrega o resumo INTEIRO, em jsonb.
--
-- POR QUE UM jsonb E NÃO VINTE PARÂMETROS. O `Resumo de Custo` já produz
-- exatamente este objeto; passá-lo direto significa que acrescentar um campo ao
-- relatório não pede uma migration de assinatura, e que a ordem dos argumentos
-- nunca pode ser trocada por engano no `queryReplacement` — que é o erro que
-- vinte `$n` posicionais convidam a cometer.
--
-- A FUNÇÃO IGNORA O QUE NÃO CONHECE, e é de propósito: o nó é espelhado no JSON
-- importado do n8n, que pode estar uma versão à frente ou atrás do banco. Campo
-- novo num nó novo não pode derrubar a gravação do lote.
-- -----------------------------------------------------------------------------
create or replace function fn_registrar_uso_lote(
  p_caso_id      uuid,
  p_execucao_ref text,
  p_resumo       jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_id uuid;
  v_num numeric;
begin
  if p_caso_id is null then
    return jsonb_build_object('gravado', false, 'motivo', 'caso_id ausente');
  end if;
  if nullif(btrim(coalesce(p_execucao_ref, '')), '') is null then
    -- SEM REFERÊNCIA DE EXECUÇÃO NÃO SE GRAVA. É a chave que impede a
    -- duplicidade; sem ela, a segunda passada viraria uma segunda linha e o
    -- custo do mandato sairia dobrado — exatamente o que esta tabela existe
    -- para não deixar acontecer.
    return jsonb_build_object('gravado', false, 'motivo', 'execucao_ref ausente');
  end if;

  -- Cobertura recalculada aqui, e não lida do resumo: é uma divisão, e divisão
  -- feita em dois lugares é divisão que diverge. O resumo continua trazendo a
  -- dele — se um dia os dois discordarem, a diferença é o sintoma.
  v_num := nullif((p_resumo->>'contas_nos_documentos')::numeric, 0);

  insert into lote_execucao (
    caso_id, execucao_ref,
    documentos, documentos_com_classificacao, documentos_fatiados,
    documentos_com_falha, documentos_sem_medicao,
    custo_total_usd, custo_extracao_usd, custo_classificacao_usd, custo_estimado_usd,
    tokens_entrada, tokens_saida, tokens_cache,
    linhas_extraidas, contas_nos_documentos, contas_extraidas, cobertura,
    orcamento_versao
  ) values (
    p_caso_id, btrim(p_execucao_ref),
    (p_resumo->>'documentos')::int,
    (p_resumo->>'documentos_com_classificacao')::int,
    (p_resumo->>'documentos_fatiados')::int,
    (p_resumo->>'documentos_com_falha')::int,
    (p_resumo->>'documentos_sem_medicao')::int,
    (p_resumo->>'custo_total_usd')::numeric,
    (p_resumo->>'custo_extracao_usd')::numeric,
    (p_resumo->>'custo_classificacao_usd')::numeric,
    (p_resumo->>'custo_estimado_usd')::numeric,
    (p_resumo#>>'{tokens,entrada}')::bigint,
    (p_resumo#>>'{tokens,saida}')::bigint,
    (p_resumo#>>'{tokens,cache}')::bigint,
    (p_resumo->>'linhas_extraidas')::int,
    (p_resumo->>'contas_nos_documentos')::int,
    (p_resumo->>'contas_extraidas')::int,
    case when v_num is null then null
         else round((p_resumo->>'contas_extraidas')::numeric / v_num, 4) end,
    p_resumo->>'orcamento_versao'
  )
  on conflict (caso_id, execucao_ref) do update set
    atualizado_em                = now(),
    documentos                   = excluded.documentos,
    documentos_com_classificacao = excluded.documentos_com_classificacao,
    documentos_fatiados          = excluded.documentos_fatiados,
    documentos_com_falha         = excluded.documentos_com_falha,
    documentos_sem_medicao       = excluded.documentos_sem_medicao,
    custo_total_usd              = excluded.custo_total_usd,
    custo_extracao_usd           = excluded.custo_extracao_usd,
    custo_classificacao_usd      = excluded.custo_classificacao_usd,
    custo_estimado_usd           = excluded.custo_estimado_usd,
    tokens_entrada               = excluded.tokens_entrada,
    tokens_saida                 = excluded.tokens_saida,
    tokens_cache                 = excluded.tokens_cache,
    linhas_extraidas             = excluded.linhas_extraidas,
    contas_nos_documentos        = excluded.contas_nos_documentos,
    contas_extraidas             = excluded.contas_extraidas,
    cobertura                    = excluded.cobertura,
    orcamento_versao             = excluded.orcamento_versao
  returning id into v_id;

  return jsonb_build_object(
    'gravado', true,
    'lote_execucao_id', v_id,
    'custo_total_usd', (p_resumo->>'custo_total_usd')::numeric
  );
end;
$$;

comment on function fn_registrar_uso_lote(uuid, text, jsonb) is
  'Grava (ou reescreve) o resumo de custo/cobertura de UMA execução de ingestão. Idempotente por '
  '(caso_id, execucao_ref): o Resumo de Custo roda uma vez por ramo do lote e as duas passadas '
  'trazem o total inteiro — sem isto, todo custo sairia dobrado.';

grant execute on function fn_registrar_uso_lote(uuid, text, jsonb) to authenticated;

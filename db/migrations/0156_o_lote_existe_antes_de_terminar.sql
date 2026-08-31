-- 0156 — O LOTE PASSA A EXISTIR NO BANCO ANTES DE TERMINAR
--
-- O DEFEITO, medido na rodada de 190 documentos de 27/08 e confirmado no código
-- em 31/08. A linha de `lote_execucao` é escrita por `fn_registrar_uso_lote`, e
-- essa função é chamada por UM nó só — o `Gravar Uso do Lote` —, que fica no fim
-- da cadeia:
--
--   Reconciliar (Classe A) -> Reconciliar Lote -> Resumo de Custo
--     -> Gravar Uso do Lote -> Conferir Lote
--
-- Ou seja: a rodada só deixa rastro se a rodada der certo. Quando o araucária
-- ficou 1h52 de pé e foi cancelado à mão, `lote_execucao` ficou VAZIA — e com
-- ela foi embora `documentos_fatiados`, que era exatamente o número de que a
-- investigação precisava para responder se a sub-extração era teto do modelo ou
-- fatiamento que não rodou. O n8n descarta os dados de uma execução cancelada,
-- então não havia segunda via.
--
-- É a forma mais pura do defeito que este projeto persegue: **a observabilidade
-- da rodada dependia de a rodada não falhar.** Rodada que morre é justamente a
-- que mais precisa ser explicada, e era a única que não explicava nada.
--
-- A CORREÇÃO É DE MOMENTO, NÃO DE CONTEÚDO. A tabela e a função de fechamento
-- não mudam de propósito; ganham um IRMÃO que abre a linha assim que o lote é
-- aceito pelo orçamento, com o que já se sabe naquele instante (quantos
-- documentos entraram, quantas chamadas o orçamento previu, que fração da cota
-- do dia isso representa). O fechamento continua fazendo o que fazia, e agora
-- carimba `fechado_em`.
--
-- `fechado_em` NULO É A INFORMAÇÃO. Uma linha aberta e nunca fechada diz, sem
-- ambiguidade: "esta execução começou, tinha este plano, e não chegou ao fim".
-- Antes, esse estado e "nunca rodou" eram o mesmo: nenhuma linha.
--
-- POR QUE NÃO BASTAVA UM `insert` NO NÓ. `fn_registrar_uso_lote` já é upsert por
-- (caso_id, execucao_ref) e o comentário da 0115 explica por quê: o Resumo de
-- Custo roda uma vez por RAMO, e um insert simples dobraria o custo do mandato.
-- A abertura entra pela mesma porta e pela mesma chave, então abrir duas vezes
-- (os dois ramos) reescreve a mesma linha em vez de criar uma segunda.

begin;

-- -----------------------------------------------------------------------------
-- AS COLUNAS DO PLANO
-- -----------------------------------------------------------------------------
-- Elas ficam ao lado das realizadas de propósito, pela mesma razão que
-- `custo_estimado_usd` já ficava ao lado de `custo_total_usd` desde a 0115: a
-- distância entre o previsto e o realizado é o que recalibra o estimador, e ela
-- só se enxerga com os dois na mesma linha.
alter table lote_execucao
  add column if not exists fechado_em            timestamptz,
  add column if not exists documentos_planejados integer,
  add column if not exists chamadas_planejadas   integer,
  -- Fração da cota DIÁRIA do provedor que o orçamento previu para este lote.
  -- numeric e não float pela mesma regra do resto da tabela.
  add column if not exists cota_fracao_planejada numeric(6,4);

comment on column lote_execucao.fechado_em is
  'Quando a cadeia chegou ao fim. NULO significa que a execução começou e não terminou — '
  'cancelada, morta por cota, ou parada num nó. Antes desta coluna, "começou e morreu" e '
  '"nunca rodou" tinham a mesma aparência: nenhuma linha na tabela.';
comment on column lote_execucao.chamadas_planejadas is
  'Chamadas de IA que o Orcamento do Lote previu, contando os blocos do fatiamento. Comparada '
  'com o consumo real, é o que diz se o estimador acerta; sozinha, é o que diz quanto da cota '
  'do dia esta execução reservou antes de começar.';

-- -----------------------------------------------------------------------------
-- fn_abrir_lote_execucao — a linha nasce quando o lote é aceito
-- -----------------------------------------------------------------------------
-- Chamada pelo nó `Abrir Lote`, logo depois de `Lote cabe?` aprovar. Deliberada-
-- mente TOLERANTE: ela nunca é o motivo de um lote não rodar. Um `raise` aqui
-- transformaria a instrumentação em ponto de falha, o que é o oposto do que ela
-- existe para fazer — e este repositório já pagou por gate que reprova por ruído.
create or replace function fn_abrir_lote_execucao(
  p_caso_id      uuid,
  p_execucao_ref text,
  p_plano        jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_id uuid;
begin
  if p_caso_id is null then
    return jsonb_build_object('aberto', false, 'motivo', 'caso_id ausente');
  end if;
  -- SEM REFERÊNCIA DE EXECUÇÃO NÃO SE ABRE, pelo mesmo motivo da 0115: é a chave
  -- que impede a duplicidade. Sem ela, cada ramo abriria a sua linha.
  if nullif(btrim(coalesce(p_execucao_ref, '')), '') is null then
    return jsonb_build_object('aberto', false, 'motivo', 'execucao_ref ausente');
  end if;

  insert into lote_execucao (
    caso_id, execucao_ref,
    documentos_planejados, chamadas_planejadas, cota_fracao_planejada,
    custo_estimado_usd, orcamento_versao
  ) values (
    p_caso_id, btrim(p_execucao_ref),
    (p_plano->>'documentos_planejados')::int,
    (p_plano->>'chamadas_planejadas')::int,
    (p_plano->>'cota_fracao_planejada')::numeric,
    (p_plano->>'custo_estimado_usd')::numeric,
    p_plano->>'orcamento_versao'
  )
  on conflict (caso_id, execucao_ref) do update set
    atualizado_em = now(),
    -- SÓ O PLANO É REESCRITO AQUI. As colunas do realizado ficam intocadas: se
    -- os dois ramos abrirem o lote e um deles chegar depois do fechamento (o n8n
    -- não garante ordem entre ramos), reescrever o realizado com nulo apagaria a
    -- medição da execução que terminou. `coalesce` mantém o que já havia quando
    -- a segunda abertura vier sem o campo.
    documentos_planejados = coalesce(excluded.documentos_planejados, lote_execucao.documentos_planejados),
    chamadas_planejadas   = coalesce(excluded.chamadas_planejadas, lote_execucao.chamadas_planejadas),
    cota_fracao_planejada = coalesce(excluded.cota_fracao_planejada, lote_execucao.cota_fracao_planejada),
    custo_estimado_usd    = coalesce(excluded.custo_estimado_usd, lote_execucao.custo_estimado_usd),
    orcamento_versao      = coalesce(excluded.orcamento_versao, lote_execucao.orcamento_versao)
  returning id into v_id;

  return jsonb_build_object('aberto', true, 'lote_execucao_id', v_id);
end $$;

comment on function fn_abrir_lote_execucao(uuid, text, jsonb) is
  'Abre a linha de lote_execucao no instante em que o orçamento aceita o lote, com o PLANO. '
  'Existe porque a linha só era escrita no fim da cadeia: a rodada de 190 documentos de 27/08 '
  'foi cancelada e não deixou rastro nenhum, levando junto documentos_fatiados — o número de que '
  'a investigação precisava. Observabilidade que depende de a rodada dar certo não é '
  'observabilidade.';

-- -----------------------------------------------------------------------------
-- O FECHAMENTO CARIMBA A HORA
-- -----------------------------------------------------------------------------
-- Uma correção CIRÚRGICA em `fn_registrar_uso_lote`: acrescenta `fechado_em` ao
-- insert e ao update, e nada mais. O corpo dela continua sendo o da 0115 — o
-- caminho de gravação do custo não é assunto desta migration, e mexer nele de
-- passagem seria alargar a fatia.
--
-- As colunas do PLANO não entram na lista de update: o fechamento não as conhece
-- e escrevê-las com nulo apagaria o que a abertura gravou.
do $$
declare
  v_src text;
  v_novo text;
begin
  select pg_get_functiondef(p.oid) into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_registrar_uso_lote';

  if v_src is null then
    raise exception 'fn_registrar_uso_lote não existe — aplique a 0115 antes desta migration';
  end if;

  if position('fechado_em' in v_src) > 0 then
    return;  -- já aplicada; a migration é idempotente
  end if;

  -- A SUBSTITUIÇÃO É ANCORADA EM TEXTO QUE SÓ EXISTE UMA VEZ, e ela CONFERE
  -- antes de trocar. Um replace cego sobre corpo de função é como uma correção
  -- vira uma função homônima com o corpo errado — o defeito que a sonda de corpo
  -- (0147) existe para pegar depois, e que é mais barato não cometer.
  if position('    orcamento_versao' in v_src) = 0 then
    raise exception 'fn_registrar_uso_lote não tem a forma esperada da 0115 — '
                    'o corpo mudou e a substituição precisa ser revista';
  end if;

  v_novo := replace(v_src,
    E'    orcamento_versao\n  ) values (',
    E'    orcamento_versao, fechado_em\n  ) values (');
  v_novo := replace(v_novo,
    E'    p_resumo->>\'orcamento_versao\'\n  )',
    E'    p_resumo->>\'orcamento_versao\', now()\n  )');
  v_novo := replace(v_novo,
    E'  on conflict (caso_id, execucao_ref) do update set\n    atualizado_em                = now(),',
    E'  on conflict (caso_id, execucao_ref) do update set\n    atualizado_em                = now(),\n    fechado_em                   = now(),');

  if v_novo = v_src then
    raise exception 'a substituição de fn_registrar_uso_lote não mudou nada — '
                    'as âncoras não casaram e o carimbo de fechamento ficaria de fora';
  end if;

  execute v_novo;
end $$;

-- -----------------------------------------------------------------------------
-- A SONDA
-- -----------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('lote_abre_antes_de_fechar', '0156', 'funcao', 'fn_abrir_lote_execucao', null, null,
   'Sem ela o nó Abrir Lote falha, e a execução volta a só existir no banco se chegar ao fim — '
   'que foi como a rodada de 190 documentos de 27/08 não deixou rastro nenhum ao ser cancelada.',
   'informativo', 590),
  -- O MARCADOR É A COLUNA, e é o que distingue a função com o carimbo da função
  -- homônima da 0115: `create or replace` sobre um corpo velho deixa a
  -- assinatura idêntica e nenhuma sonda de catálogo simples veria a diferença.
  ('lote_carimba_fechamento', '0156', 'corpo', 'fn_registrar_uso_lote', 'fechado_em', null,
   'O fechamento não carimba a hora, e `fechado_em` fica nulo mesmo na execução que terminou — '
   'o que faz toda rodada parecer morta e inverte o sinal que esta migration existe para criar.',
   'informativo', 595)
on conflict (chave) do update
  set migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
      marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
      porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0156',
       revisado_em = date '2026-08-31',
       observacao = 'Revisão de 31/08/2026: a 0156 faz a linha de lote_execucao NASCER quando o '
                    'orçamento aceita o lote, com o plano (documentos, chamadas previstas, fração '
                    'da cota diária), e o fechamento passa a carimbar fechado_em. Antes, a linha '
                    'só era escrita no fim da cadeia: a rodada de 190 de 27/08 foi cancelada e '
                    'lote_execucao ficou vazia, levando junto documentos_fatiados — exatamente o '
                    'número de que a investigação precisava. fechado_em nulo passa a ser a '
                    'informação: começou e não terminou, que antes era indistinguível de nunca '
                    'ter rodado.'
 where id;

commit;

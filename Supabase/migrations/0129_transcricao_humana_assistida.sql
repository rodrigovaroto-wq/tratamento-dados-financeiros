-- =============================================================================
-- Migration 0129 — TRANSCRIÇÃO HUMANA ASSISTIDA, e a contaminação que ela criaria
--
-- O FECHAMENTO Nº 2 DO `Arquitetura do Sistema/1 Visão e Doutrina/01`, QUE ERA O ÚNICO DOS OITO SEM CÓDIGO.
--
-- A doutrina lista oito "fechamentos fail-safe", e o segundo é: *"Gate de captura
-- com saída. Input ilegível/corrompido → **transcrição humana assistida**, nunca
-- dead-end de pendência infinita."*
--
-- O gate existe (a `0010`/`0020` abrem `arquivo_ilegivel` quando o diagnóstico diz
-- que o arquivo não se lê). A SAÍDA existe em outra forma: a pendência pode ser
-- reenviada ao cliente ou rejeitada, então não há beco sem saída. **A transcrição
-- assistida em si nunca foi construída** — e ela é a saída que serve quando o
-- cliente não tem outra via do arquivo, que em reestruturação é o caso comum.
--
-- A FORMA: PLANILHA MODELO, PREENCHIDA PELO ANALISTA (decisão do dono). Não é uma
-- tela de digitação linha a linha: ninguém digita balanço em formulário web se
-- puder usar Excel, e o portal já sabe gerar e ler `.xlsx` por todo lado. A
-- planilha é ferramenta de mesa e não sai da casa, então ela pode usar o
-- vocabulário interno (conceito da taxonomia, seção canônica) sem o cuidado de
-- linguagem que a `0122` teve de dar às perguntas ao cliente.
--
-- =============================================================================
-- A CONTAMINAÇÃO QUE ESTA MIGRATION TEM DE FECHAR NO MESMO ATO
-- =============================================================================
--
-- Linha transcrita por humano mora em `campo_extraido`, do lado das linhas que a
-- IA extraiu. E `fn_golden_campos` (0126) mede a extração comparando
-- `campo_extraido` com o rótulo do golden set.
--
-- **Sem uma distinção, a primeira transcrição contaminaria a medição da
-- autonomia.** Uma linha que um humano digitou olhando o documento bate com o
-- rótulo do golden set quase sempre — e o número sairia creditado à extração. O
-- sistema mediria a si mesmo por cima do trabalho humano, e a concordância subiria
-- justamente nos documentos mais difíceis, que são os que precisam de transcrição.
--
-- É a forma exata da armadilha que o cabeçalho do `medir-auto-aceite.mts` descreve
-- ("está medindo o próprio instrumento") e que a `0126` fechou com
-- `golden_documento.origem`. Aqui ela reapareceria por outra porta.
--
-- Então: `campo_extraido.origem_valor` distingue `extracao` de
-- `transcricao_humana`, e `fn_golden_campos` passa a EXCLUIR o que foi transcrito.
-- A coluna nasce com default `extracao`, então nenhuma linha existente muda de
-- significado.
--
-- =============================================================================
-- AS TRÊS DECISÕES
-- =============================================================================
--
-- 1. A TRANSCRIÇÃO É VERSÃO NOVA, não escrita por cima da antiga. É a doutrina da
--    `0026`: "reextração é versão nova, e substitui em vez de acumular". Uma
--    transcrição é uma leitura NOVA do mesmo arquivo, e `fn_versao_com_extracao`
--    (0102) a elege como vigente porque ela tem linhas. A versão ilegível fica
--    preservada, com suas zero linhas, contando a história.
--
-- 2. AS GUARDAS DE EXTRAÇÃO NÃO RODAM. As três guardas da `0013`/`0016` — padrão
--    suspeito, baixa confiança, extração vazia — existem para pegar alucinação de
--    modelo. Aplicá-las a um humano digitando seria acusar de fabricação alguém
--    que está lendo o papel: "quatro contas com o mesmo valor" é padrão suspeito
--    numa saída de IA e é rotina num balanço com contas zeradas. O que substitui a
--    guarda é a autoria: cada linha transcrita tem nome, e `origem_valor` diz que
--    ela não veio de máquina.
--
-- 3. A LINHA TRANSCRITA JÁ NASCE ACEITA, e isso NÃO fura a anti-ancoragem. O
--    fechamento #5 exige "evento de aceite humano explícito" antes de um número
--    entrar na base de modelagem. Aqui o humano não está aceitando a sugestão de
--    uma máquina: ele é a FONTE do número. Pedir que ele depois "aceite" o que ele
--    mesmo digitou seria um clique cerimonial — e cerimônia vazia é o que ensina a
--    clicar sem ler. O aceite fica registrado com o nome dele, que é o que a
--    doutrina de fato pede.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- origem_valor — de onde veio este número.
-- -----------------------------------------------------------------------------
alter table campo_extraido
  add column if not exists origem_valor text not null default 'extracao';

alter table campo_extraido drop constraint if exists campo_extraido_origem_valor_check;
alter table campo_extraido
  add constraint campo_extraido_origem_valor_check
  check (origem_valor in ('extracao', 'transcricao_humana'));

comment on column campo_extraido.origem_valor is
  'De onde veio o número: extracao (a IA leu o arquivo) ou transcricao_humana (uma pessoa digitou, '
  'porque o arquivo não se lê — fechamento #2 do Arquitetura do Sistema/1 Visão e Doutrina/01). Existe porque sem ela a primeira '
  'transcrição contaminaria fn_golden_campos: linha digitada por humano bate com o rótulo do golden '
  'set quase sempre, e o acerto sairia creditado à EXTRAÇÃO. Default extracao: nenhuma linha '
  'existente muda de significado.';

create index if not exists idx_campo_extraido_origem_valor
  on campo_extraido (documento_versao_id, origem_valor);

-- -----------------------------------------------------------------------------
-- fn_linhas_para_transcrever — o que a planilha modelo tem de perguntar.
--
-- Devolve as linhas que o Portão 1 vai COBRAR daquele tipo de documento — e o
-- ponto de mostrá-las na planilha é que elas são a única parte previsível: o
-- analista não pode descobrir depois, na fila de pendências, que faltou a linha de
-- caixa. O resto do documento ele acrescenta em linhas livres, porque só ele sabe
-- o que o papel tem.
--
-- Note que são POUCAS de propósito (três num balanço): a `taxonomia_linha_exigida`
-- é o mínimo exigido, não um gabarito de demonstração. Uma planilha que fingisse
-- listar todas as contas de um balanço estaria inventando a estrutura do documento
-- do cliente.
-- -----------------------------------------------------------------------------
create or replace function fn_linhas_para_transcrever(p_documento_id uuid)
returns table (
  conceito        text,
  rotulo          text,
  descricao       text,
  secao_canonica  text,
  checagem        text,
  severidade      text
)
language sql
stable
as $$
  select le.conceito, le.rotulo, le.descricao, le.secao_canonica, le.checagem,
         coalesce(le.severidade, 'importante')
  from documento d
  join taxonomia_linha_exigida le on le.tipo_taxonomia = d.tipo_taxonomia
  where d.id = p_documento_id and le.ativo
  order by coalesce(le.severidade, 'importante'), le.conceito;
$$;

comment on function fn_linhas_para_transcrever(uuid) is
  'As linhas que o Portão 1 vai COBRAR deste tipo de documento, para a planilha de transcrição '
  'listá-las. São poucas de propósito: taxonomia_linha_exigida é o MÍNIMO exigido, não um gabarito '
  'de demonstração — planilha que fingisse listar todas as contas de um balanço estaria inventando '
  'a estrutura do documento do cliente. O resto vai em linha livre.';

grant execute on function fn_linhas_para_transcrever(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_registrar_transcricao_humana — a saída do gate de captura.
--
-- RECUSA RETORNADA, não exceção (padrão 0036/0037/0038/0041/0126/0128): exceção
-- desfaria o registro da própria tentativa.
-- -----------------------------------------------------------------------------
create or replace function fn_registrar_transcricao_humana(
  p_documento_id uuid,
  p_linhas       jsonb,
  p_autor        text,
  p_motivo       text default null
)
returns jsonb
language plpgsql
as $$
declare
  v_caso_id     uuid;
  v_ref         text;
  v_nome        text;
  v_origem      origem_arquivo;
  v_hash        text;
  v_n_versao    int;
  v_versao_id   uuid;
  v_item        jsonb;
  v_valor       numeric;
  v_n           int := 0;
  v_pendencia   uuid;
  v_autor       text := nullif(trim(coalesce(p_autor, '')), '');
begin
  if v_autor is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'Transcrição sem autor não é transcrição. O número passa a valer como fato '
                       'na base de modelagem, e a única coisa que o sustenta é quem o digitou — '
                       'não há guarda de máquina para isso, por desenho.');
  end if;

  if p_linhas is null or jsonb_typeof(p_linhas) <> 'array' or jsonb_array_length(p_linhas) = 0 then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'Nenhuma linha para transcrever. Gravar uma versão vazia criaria um documento '
                       'que parece transcrito e não tem número nenhum — o pior dos dois estados.');
  end if;

  select d.caso_id into v_caso_id from documento d where d.id = p_documento_id;
  if v_caso_id is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('Documento %s não existe.', p_documento_id));
  end if;

  -- A versão de referência é a mais recente: dela saem o arquivo e o nome, para a
  -- versão transcrita apontar para o MESMO arquivo. Transcrição não é upload novo.
  select dv.arquivo_ref, dv.nome_original, dv.origem_arquivo, dv.hash
    into v_ref, v_nome, v_origem, v_hash
  from documento_versao dv
  where dv.documento_id = p_documento_id
  order by dv.n_versao desc
  limit 1;

  if v_ref is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'O documento não tem nenhuma versão. Transcrição é leitura nova de um arquivo '
                       'que já está no sistema, não um caminho para inserir arquivo.');
  end if;

  -- VERSÃO NOVA (doutrina da 0026): a transcrição é uma leitura nova do mesmo
  -- arquivo, e `fn_versao_com_extracao` (0102) a elege como vigente por ela ter
  -- linhas. A versão ilegível fica preservada, com suas zero linhas, contando a
  -- história de por que houve transcrição.
  select coalesce(max(dv.n_versao), 0) + 1 into v_n_versao
    from documento_versao dv where dv.documento_id = p_documento_id;

  insert into documento_versao
    (documento_id, n_versao, origem_arquivo, arquivo_ref, nome_original, hash,
     legibilidade, nota_legibilidade)
  values (p_documento_id, v_n_versao, v_origem, v_ref, v_nome, v_hash,
          -- A legibilidade da VERSÃO TRANSCRITA é 'ok': o conteúdo dela é legível
          -- por construção, foi uma pessoa que o escreveu. O arquivo continua
          -- ilegível, e é a versão anterior que guarda esse fato.
          'ok',
          format('Transcrição humana assistida por %s%s', v_autor,
                 case when p_motivo is null then '' else ' — ' || p_motivo end))
  returning id into v_versao_id;

  -- AS GUARDAS DE EXTRAÇÃO NÃO RODAM AQUI, e por isso não se chama
  -- `fn_registrar_campos_extraidos`. Elas existem para pegar alucinação de modelo;
  -- "quatro contas com o mesmo valor" é padrão suspeito numa saída de IA e é rotina
  -- num balanço com contas zeradas. O que substitui a guarda é a AUTORIA.
  for v_item in select * from jsonb_array_elements(p_linhas)
  loop
    v_valor := case when (v_item->>'valor_num') ~ '^-?\d+(\.\d+)?$'
                    then (v_item->>'valor_num')::numeric else null end;

    insert into campo_extraido
      (documento_versao_id, chave, valor_texto, valor_num, unidade, moeda,
       secao, secao_canonica, entidade_coluna, periodo_coluna, ordem,
       origem_pagina, origem_linha,
       -- Confiança NULA de propósito: confiança é a autoavaliação de um modelo, e
       -- não existe equivalente para uma pessoa. Escrever 1.0 aqui inventaria uma
       -- medida e faria a linha transcrita passar em qualquer filtro de limiar.
       confianca,
       origem_valor, status_aceite, aceito_por, aceito_em)
    values (
      v_versao_id,
      coalesce(nullif(trim(v_item->>'chave'), ''), '(sem rótulo)'),
      v_item->>'valor_texto', v_valor,
      v_item->>'unidade', v_item->>'moeda',
      v_item->>'secao', v_item->>'secao_canonica',
      v_item->>'entidade_coluna', v_item->>'periodo_coluna',
      case when (v_item->>'ordem') ~ '^\d+$' then (v_item->>'ordem')::int else v_n end,
      case when (v_item->>'origem_pagina') ~ '^\d+$' then (v_item->>'origem_pagina')::int end,
      v_item->>'origem_linha',
      null,
      'transcricao_humana', 'aceito', v_autor, now());
    v_n := v_n + 1;
  end loop;

  -- A SAÍDA FOI TOMADA: a pendência de ilegibilidade fecha, com o nome de quem a
  -- fechou. É isto que faz o gate deixar de ser "dead-end de pendência infinita" —
  -- e é a única metade do fechamento #2 que já existia pela metade.
  select p.id into v_pendencia from pendencia p
   where p.documento_id = p_documento_id
     and p.tipo = 'arquivo_ilegivel'
     and p.estado <> 'resolvida'
   limit 1;
  if v_pendencia is not null then
    update pendencia
       set estado = 'resolvida', resolvida_em = now(),
           resolvida_por = v_autor
     where id = v_pendencia;
  end if;

  insert into decisao (caso_id, tipo, autor, motivo, payload)
    values (v_caso_id, 'aprovacao', v_autor,
      format('Transcrição humana assistida de "%s": %s linha(s) digitadas a partir do arquivo '
             'ilegível.%s', coalesce(v_nome, '?'), v_n,
             case when p_motivo is null then '' else ' Motivo: ' || p_motivo end),
      jsonb_build_object('documento_id', p_documento_id, 'documento_versao_id', v_versao_id,
                         'n_versao', v_n_versao, 'linhas', v_n,
                         'pendencia_resolvida', v_pendencia));

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values (v_autor, 'transcricao_humana', 'documento_versao:'||v_versao_id,
            jsonb_build_object('documento_id', p_documento_id, 'linhas', v_n,
                               'n_versao', v_n_versao,
                               'porque', 'fechamento #2 do Arquitetura do Sistema/1 Visão e Doutrina/01: gate de captura COM SAIDA. As '
                                         'guardas de extracao nao rodam (elas pegam alucinacao de '
                                         'modelo) e origem_valor marca as linhas para elas nao '
                                         'contaminarem a medicao da extracao.'));

  -- A completude precisa saber que as linhas chegaram, senão o Portão 1 continua
  -- cobrando o que já foi transcrito.
  perform fn_recomputar_completude(v_caso_id);

  -- E a classificação contábil roda sobre a versão nova, como roda sobre qualquer
  -- outra: em sombra, sem tocar em nada.
  perform fn_classificar_contabil(v_versao_id);

  return jsonb_build_object(
    'documento_versao_id', v_versao_id,
    'n_versao', v_n_versao,
    'linhas', v_n,
    'pendencia_resolvida', v_pendencia,
    'autor', v_autor);
end;
$$;

comment on function fn_registrar_transcricao_humana(uuid, jsonb, text, text) is
  'A SAÍDA do gate de captura (fechamento #2 do Arquitetura do Sistema/1 Visão e Doutrina/01), que era o único dos oito fechamentos sem '
  'código. Cria VERSÃO NOVA (doutrina da 0026), marca as linhas com origem_valor='
  '''transcricao_humana'' para elas não contaminarem fn_golden_campos, NÃO roda as guardas de '
  'extração (elas pegam alucinação de modelo, e acusariam um humano de fabricar por ler um balanço '
  'com contas zeradas), grava confiança NULA (não existe autoavaliação de pessoa) e resolve a '
  'pendência de ilegibilidade com o nome de quem a fechou.';

grant execute on function fn_registrar_transcricao_humana(uuid, jsonb, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- E A MEDIÇÃO DA EXTRAÇÃO PASSA A IGNORAR O QUE FOI TRANSCRITO.
--
-- fn_golden_campos — corpo da 0126 com UMA cláusula acrescentada. Ver o comentário
-- no lugar exato. Sem ela, a funcionalidade que esta migration cria estragaria a
-- medição que a migration anterior criou, e o estrago seria invisível: o número
-- subiria, e subir é o que ninguém investiga.
-- -----------------------------------------------------------------------------
create or replace function fn_golden_campos(
  p_rodada uuid,
  p_origem golden_origem default 'real'
)
returns table (
  tipo                       text,
  n_rotulado                 int,
  n_exato                    int,
  n_dentro_tolerancia        int,
  n_errado                   int,
  n_ausente                  int,
  acerto                     numeric,
  n_auto_aceito              int,
  n_auto_aceito_sem_rotulo   int,
  cobertura_conferida        numeric,
  n_sem_consenso             int
)
language sql
stable
as $$
  with docs as (
    select gd.documento_id, d.tipo_taxonomia, fn_versao_com_extracao(d.id) as versao_id
    from golden_documento gd
    join documento d on d.id = gd.documento_id
    where gd.rodada_id = p_rodada and gd.origem = p_origem
  ),
  -- Consenso do CAMPO. Regra diferente da do documento, de propósito: aqui basta
  -- que os rotuladores que julgaram este campo concordem. O Arquitetura do Sistema/2 Especificação/f0/06 pede dois
  -- rotuladores "nos casos ambíguos", então o segundo confere uma AMOSTRA das
  -- linhas — exigir que ele tenha julgado todas jogaria fora o rótulo do
  -- primeiro em tudo o que a amostra não cobriu.
  rotulo as (
    select gc.documento_id,
           fn_normalizar_texto(gc.chave)            as chave_norm,
           coalesce(gc.periodo_coluna, '')          as periodo,
           coalesce(gc.entidade_coluna, '')         as entidade,
           min(gc.valor_correto)                    as valor_correto,
           max(gc.tolerancia)                       as tolerancia,
           (count(distinct gc.valor_correto) = 1)   as consenso
    from golden_campo gc
    join docs on docs.documento_id = gc.documento_id
    where gc.rodada_id = p_rodada and gc.valor_correto is not null
    group by 1, 2, 3, 4
  ),
  maquina as (
    select docs.documento_id, docs.tipo_taxonomia,
           fn_normalizar_texto(ce.chave)      as chave_norm,
           coalesce(ce.periodo_coluna, '')    as periodo,
           coalesce(ce.entidade_coluna, '')   as entidade,
           -- Mesma regra de desempate da fn_valores_por_ano (0125): quando o
           -- mesmo par volta duas vezes, vale a ocorrência de maior módulo.
           (array_agg(ce.valor_num order by abs(ce.valor_num) desc))[1] as valor_num,
           bool_or(ce.status_aceite = 'aceito' and ce.aceito_por like 'sistema:auto_aceite%')
             as auto_aceito
    from docs
    join campo_extraido ce on ce.documento_versao_id = docs.versao_id
    where ce.valor_num is not null
      -- 0129: LINHA TRANSCRITA POR HUMANO SAI DA MEDIÇÃO DA EXTRAÇÃO.
      --
      -- Ela mora na mesma tabela das linhas que a IA leu, e sem este filtro a
      -- primeira transcrição contaminaria o número: linha digitada por uma pessoa
      -- olhando o documento bate com o rótulo do golden set quase sempre, e o
      -- acerto sairia creditado à EXTRAÇÃO. Pior, subiria justamente nos
      -- documentos mais difíceis — os que precisaram de transcrição.
      --
      -- É a mesma armadilha que golden_documento.origem fecha do outro lado
      -- (rotular book sintético mede o instrumento), reaparecendo por outra porta.
      and ce.origem_valor = 'extracao'
    group by 1, 2, 3, 4, 5
  ),
  par as (
    select docs.tipo_taxonomia as tipo, r.consenso,
           m.valor_num, r.valor_correto, r.tolerancia
    from rotulo r
    join docs on docs.documento_id = r.documento_id
    left join maquina m
      on m.documento_id = r.documento_id and m.chave_norm = r.chave_norm
     and m.periodo = r.periodo and m.entidade = r.entidade
  ),
  -- A cobertura olha o conjunto INVERSO: linha auto-aceita da máquina que nenhum
  -- rótulo confere.
  cob as (
    select m.tipo_taxonomia as tipo,
           count(*) filter (where m.auto_aceito)::int as n_auto,
           count(*) filter (where m.auto_aceito and r.valor_correto is null)::int as n_auto_sem
    from maquina m
    left join rotulo r
      on r.documento_id = m.documento_id and r.chave_norm = m.chave_norm
     and r.periodo = m.periodo and r.entidade = m.entidade
    group by 1
  )
  select coalesce(p.tipo, c.tipo),
         count(p.consenso) filter (where p.consenso)::int,
         count(*) filter (where p.consenso and p.valor_num is not null
                            and p.valor_num = p.valor_correto)::int,
         count(*) filter (where p.consenso and p.valor_num is not null
                            and p.valor_num <> p.valor_correto
                            and abs(p.valor_num - p.valor_correto) <= p.tolerancia)::int,
         count(*) filter (where p.consenso and p.valor_num is not null
                            and abs(p.valor_num - p.valor_correto) > p.tolerancia)::int,
         count(*) filter (where p.consenso and p.valor_num is null)::int,
         case when count(*) filter (where p.consenso) = 0 then null
              else round(count(*) filter (where p.consenso and p.valor_num is not null
                                            and abs(p.valor_num - p.valor_correto)
                                                <= p.tolerancia)::numeric
                         / count(*) filter (where p.consenso), 4) end,
         coalesce(max(c.n_auto), 0),
         coalesce(max(c.n_auto_sem), 0),
         case when coalesce(max(c.n_auto), 0) = 0 then null
              else round((max(c.n_auto) - max(c.n_auto_sem))::numeric / max(c.n_auto), 4) end,
         count(*) filter (where not p.consenso)::int
  from par p full outer join cob c on c.tipo = p.tipo
  group by 1;
$$;
grant execute on function fn_golden_campos(uuid, golden_origem) to authenticated;

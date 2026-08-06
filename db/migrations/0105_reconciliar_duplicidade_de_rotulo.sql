-- =============================================================================
-- Migration 0105 — A MESMA CONTA COM DOIS RÓTULOS: detectar, dizer o tamanho, e
-- não apagar nada.
--
-- O QUE ACONTECEU. A sessão 40 auditou o arquivo que o dono exportou e achou o
-- balanço do modelo em 195.090 contra 95.780 informados. A maior parte era subtotal
-- somado junto com os componentes, e isso foi corrigido no gerador de planilha
-- (detecção estrutural, uma detecção e dois consumidores). Sobrou um resíduo de
-- outra natureza, que o gerador NÃO pode resolver:
--
--   "Prejuízos acumulados"            −39.150
--   "Resultados Acumulados"           −39.150
--   "Capital social subscrito"         45.000
--   "Capital social subscrito e integralizado"  30.000
--
-- São a MESMA conta transposta com nomes diferentes — dois documentos do mesmo
-- caso (o balanço e o balancete/combinado) escrevem o mesmo fato de dois jeitos, e
-- a extração, fiel a cada documento, grava as duas. Somadas, inflam o patrimônio.
--
-- POR QUE ISTO NÃO É TRABALHO DO EXPORT, e por que não se resolve por semelhança.
-- O export já faz o que lhe cabe: cada grupo do balanço segue o TOTAL INFORMADO no
-- documento, e a diferença aparece numa linha de reconciliação (sessão 40). Isso
-- deixa o NÚMERO certo e o resíduo VISÍVEL, mas não diz qual das duas linhas é a
-- conta. E adivinhar por semelhança de valor apagaria conta legítima: duas
-- provisões de mesmo valor, duas reservas de mesmo valor, dois mútuos espelhados
-- entre credor e devedor — todos existem em demonstração real.
--
-- ENTÃO O QUE ESTA MIGRATION FAZ: uma checagem de reconciliação que ACHA os pares
-- candidatos e abre pendência dizendo quanto o grupo está dobrado se eles forem a
-- mesma conta. Decisão humana, com o número na frente. É a mesma doutrina da
-- Classe A/B: o sistema mostra a divergência, não escolhe por ninguém.
--
-- O CRITÉRIO É ESTREITO DE PROPÓSITO — falso positivo aqui gasta o tempo do
-- analista, e o barato demais desmoraliza a fila de revisão:
--   • mesma `secao_canonica` (conta de ativo não duplica conta de passivo);
--   • rótulos DIFERENTES, valor idêntico ao centavo, na MESMA coluna
--     (entidade × período) — e em TODAS as colunas em que os dois aparecem;
--   • pelo menos duas colunas coincidentes, ou uma só quando os dois rótulos
--     compartilham radical estrutural (`fn_tokens_estruturais` da 0103: "Prejuízos
--     acumulados" × "Resultados Acumulados" não compartilham; "Capital social
--     subscrito" × "Capital social subscrito e integralizado" sim). Duas colunas
--     idênticas por coincidência já é improvável; uma coluna só, com radical
--     compartilhado, é o caso do rótulo reescrito;
--   • valor não nulo e não zero (zero coincide por natureza);
--   • as duas linhas com papel 'conta' — subtotal já é tratado pela detecção
--     estrutural do export, e cobrar duas vezes a mesma coisa polui a fila.
--
-- E NÃO MEXE EM DADO: nenhuma linha é apagada, nenhum valor é reescrito. A saída é
-- uma pendência `divergencia_reconciliacao` com os dois rótulos, o valor e o total
-- dobrado. Quem decide é o dono, na tela de revisão.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- fn_pares_duplicados_do_caso — os pares candidatos, com o que sustenta cada um.
--
-- Separada da checagem porque é ela que a tela vai querer listar (uma pendência
-- agrega o caso inteiro; a tela precisa do par a par), e porque assim o teste
-- SQL confere o CRITÉRIO sem passar pela máquina de pendência.
-- -----------------------------------------------------------------------------
create or replace function fn_pares_duplicados_do_caso(p_caso_id uuid, p_entidade text default null)
returns table (
  secao_canonica text,
  rotulo_a       text,
  rotulo_b       text,
  colunas        int,
  valor          numeric,
  radical_comum  boolean
)
language sql
stable
as $$
  with ocorrencias as (
    select
      ce.secao_canonica,
      fn_normalizar_texto(ce.chave)                as rotulo,
      coalesce(ce.entidade_coluna, e.razao_social) as ent_col,
      coalesce(ce.periodo_coluna, p.referencia)    as per_col,
      ce.valor_num,
      ce.chave,
      ce.secao,
      ce.unidade,
      d.tipo_taxonomia
    from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d         on d.id = dv.documento_id
    left join entidade e     on e.id = d.entidade_id
    left join periodo p      on p.id = d.periodo_id
    where d.caso_id = p_caso_id
      and ce.valor_num is not null
      and ce.valor_num <> 0
      and ce.secao_canonica is not null
      and ce.secao_canonica <> 'NAO_CLASSIFICAVEL'
      -- Só a versão VIGENTE de cada documento (0102): ocorrência de versão
      -- superada faria uma reextração parecer duplicidade.
      and dv.n_versao = (select max(dv2.n_versao) from documento_versao dv2
                          where dv2.documento_id = d.id)
      and (p_entidade is null
           or fn_mesma_entidade(coalesce(ce.entidade_coluna, e.razao_social), p_entidade))
  ),
  contas as (
    -- Subtotal e derivado ficam fora: o export já trata subtotal informado por
    -- estrutura, e cobrar de novo aqui duplicaria a fila de revisão.
    select * from ocorrencias o
    where fn_papel_linha(o.chave, o.tipo_taxonomia, o.unidade) = 'conta'
  ),
  -- Uma linha por (seção, rótulo, coluna): se o mesmo rótulo aparece em dois
  -- documentos com o mesmo valor, isso é concordância, não duplicidade.
  por_coluna as (
    select secao_canonica, rotulo, ent_col, per_col, min(chave) as chave,
           -- A SUBSEÇÃO DECLARADA pelo documento, agregada: é ela que denuncia o
           -- par subtotal × componente (ver o filtro `subtotal_de` abaixo).
           array_agg(distinct fn_normalizar_texto(coalesce(secao, ''))) as secoes,
           max(valor_num) as valor_num
    from contas
    group by secao_canonica, rotulo, ent_col, per_col
    having count(distinct valor_num) = 1
  ),
  pares as (
    select
      a.secao_canonica,
      a.rotulo as rotulo_a, b.rotulo as rotulo_b,
      min(a.chave) as chave_a, min(b.chave) as chave_b,
      count(*)     as colunas_iguais,
      max(abs(a.valor_num)) as valor,
      -- É o par SUBTOTAL × COMPONENTE? O documento diz: a subseção declarada de um
      -- é o rótulo do outro. Medido no book (extração fiel): "Obrigações
      -- Tributárias" × "Parcelamentos tributários - longo prazo", "Empréstimos e
      -- Financiamentos" × "Financiamentos - FINAME/BNDES", "Partes Relacionadas" ×
      -- "Mútuos a pagar", "Investimentos" × "Participações em outras sociedades".
      -- São grupo com UM componente, não conta duplicada — e o export já os exclui
      -- da soma pela detecção estrutural. Cobrar de novo aqui encheria a fila de
      -- revisão com o que já está resolvido, que é exatamente o que a 0023 desfez.
      bool_or(a.rotulo = any(b.secoes) or b.rotulo = any(a.secoes)) as subtotal_de,
      -- MESMA SUBSEÇÃO DECLARADA? Dois rótulos para o MESMO fato estão, por
      -- construção, no mesmo lugar da demonstração. Quando o documento os coloca em
      -- subseções diferentes, ele está dizendo que são coisas diferentes — e é o
      -- que restou de falso positivo no book depois do filtro de subtotal:
      -- "Créditos tributários - ICMS sobre ativo permanente" (Realizável a Longo
      -- Prazo) e "Veículos e empilhadeiras" (Imobilizado), ambos 3.900 nos dois
      -- exercícios. Coincidência de valor, contas distintas.
      bool_or(a.secoes && b.secoes) as mesma_subsecao,
      -- O SINAL DE SUBSEÇÃO EXISTE NESTE DOCUMENTO? Sem ele o filtro `subtotal_de`
      -- não tem como disparar, e aí "Arrendamentos" × "Arrendamentos a pagar - CPC
      -- 06 (R2)" (grupo com um componente) fica indistinguível de rótulo reescrito —
      -- os dois têm radical contido. Medido no `fixture_modelagem_v35.sql`, que não
      -- traz `secao`: era o único par que ele devolvia, e era falso positivo.
      -- Então o ramo de UMA coluna (que se sustenta no radical) exige a subseção
      -- declarada; o de DUAS colunas não precisa dela, porque ali a evidência é
      -- aritmética e independente do nome.
      bool_or(coalesce(array_to_string(a.secoes, '') || array_to_string(b.secoes, ''), '') <> '') as tem_secao
    from por_coluna a
    join por_coluna b
      on b.secao_canonica = a.secao_canonica
     and b.ent_col = a.ent_col and b.per_col = a.per_col
     and b.rotulo > a.rotulo                       -- par sem repetir a ordem
     and b.valor_num = a.valor_num                 -- idêntico ao centavo
    group by a.secao_canonica, a.rotulo, b.rotulo
  ),
  -- Uma coluna em que os dois aparecem e DISCORDAM derruba o par: contas que
  -- coincidem num ano e divergem no outro são contas diferentes, ponto.
  discordantes as (
    select a.secao_canonica, a.rotulo as rotulo_a, b.rotulo as rotulo_b
    from por_coluna a
    join por_coluna b
      on b.secao_canonica = a.secao_canonica
     and b.ent_col = a.ent_col and b.per_col = a.per_col
     and b.rotulo > a.rotulo
     and b.valor_num <> a.valor_num
  )
  select
    pr.secao_canonica,
    pr.chave_a,
    pr.chave_b,
    pr.colunas_iguais::int,
    pr.valor,
    (fn_tokens_estruturais(pr.chave_a) <@ fn_tokens_estruturais(pr.chave_b)
     or fn_tokens_estruturais(pr.chave_b) <@ fn_tokens_estruturais(pr.chave_a)) as radical_comum
  from pares pr
  where not pr.subtotal_de
    and pr.mesma_subsecao
    and not exists (
    select 1 from discordantes dc
    where dc.secao_canonica = pr.secao_canonica
      and dc.rotulo_a = pr.rotulo_a and dc.rotulo_b = pr.rotulo_b
  )
    and (pr.colunas_iguais >= 2
         or (pr.tem_secao
             and (fn_tokens_estruturais(pr.chave_a) <@ fn_tokens_estruturais(pr.chave_b)
                  or fn_tokens_estruturais(pr.chave_b) <@ fn_tokens_estruturais(pr.chave_a))))
  order by pr.valor desc, pr.secao_canonica, pr.chave_a, pr.chave_b;
$$;

comment on function fn_pares_duplicados_do_caso(uuid, text) is
  'Pares de rótulos DIFERENTES, na mesma seção canônica, com valor idêntico nas mesmas colunas — '
  'candidatos a ser a MESMA conta transposta duas vezes (achado do v35: "Prejuízos acumulados" e '
  '"Resultados Acumulados", ambos -39.150). Não decide nada: alimenta a checagem de reconciliação, '
  'que abre pendência para decisão humana. Critério estreito de propósito — falso positivo aqui '
  'gasta o tempo do analista.';

-- -----------------------------------------------------------------------------
-- fn_reconciliar_duplicidade — a checagem, na forma das outras (Classe A).
--
-- É por CASO/ENTIDADE, não por período: a duplicidade é um fato da estrutura dos
-- documentos, não de um exercício. O período da pendência fica nulo por isso.
-- -----------------------------------------------------------------------------
create or replace function fn_reconciliar_duplicidade(
  p_caso_id     uuid,
  p_entidade_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_entidade    text;
  v_pares       record;
  v_n           int := 0;
  v_total       numeric := 0;
  v_detalhe     jsonb := '[]'::jsonb;
  v_descricao   text;
  v_resultado   text;
  v_documento   uuid;
begin
  select razao_social into v_entidade from entidade where id = p_entidade_id;

  for v_pares in
    select * from fn_pares_duplicados_do_caso(p_caso_id, v_entidade)
  loop
    v_n := v_n + 1;
    v_total := v_total + v_pares.valor;
    v_detalhe := v_detalhe || jsonb_build_array(jsonb_build_object(
      'secao_canonica', v_pares.secao_canonica,
      'rotulo_a', v_pares.rotulo_a, 'rotulo_b', v_pares.rotulo_b,
      'valor', v_pares.valor, 'colunas_iguais', v_pares.colunas,
      'radical_comum', v_pares.radical_comum));
  end loop;

  -- Um documento qualquer da entidade, só para a pendência ter onde ancorar o
  -- link da tela. A duplicidade é entre documentos, então não há "o" documento.
  select d.id into v_documento
  from documento d
  where d.caso_id = p_caso_id
    and (p_entidade_id is null or d.entidade_id = p_entidade_id)
  order by d.criado_em
  limit 1;

  if v_n = 0 then
    v_resultado := 'ok';
    v_descricao := 'Nenhum par de rótulos duplicados na entidade.';
  else
    v_resultado := 'divergencia';
    v_descricao := format(
      '%s par(es) de rótulos podem ser a MESMA conta transposta duas vezes (%s no total). '
      || 'Se forem, a soma do grupo está dobrada nesse valor. Pares: %s. '
      || 'NADA foi apagado: decida qual rótulo é a conta e trate o outro na revisão.',
      v_n, to_char(v_total, 'FM999G999G999D00'),
      (select string_agg(format('%s = %s (%s)', x->>'rotulo_a', x->>'rotulo_b',
                                to_char((x->>'valor')::numeric, 'FM999G999G999D00')), '; ')
         from jsonb_array_elements(v_detalhe) x));
  end if;

  return fn_registrar_reconciliacao(
    p_caso_id, p_entidade_id, null, 'duplicidade_de_rotulo', 'A', v_documento,
    jsonb_build_object('pares', v_detalhe), null,
    v_resultado, v_total, null,
    jsonb_build_object('criterio', 'mesma secao_canonica, valor idêntico na mesma coluna, '
      || 'papel conta, e (>=2 colunas coincidentes ou radical estrutural compartilhado)'),
    v_descricao);
end;
$$;

comment on function fn_reconciliar_duplicidade(uuid, uuid) is
  'Checagem de reconciliação: acha a MESMA conta transposta com dois rótulos e abre pendência com '
  'o valor dobrado. Não apaga nem reescreve dado — decisão humana. Por caso/entidade (a '
  'duplicidade é fato da estrutura dos documentos, não de um exercício), daí periodo_id nulo.';

-- -----------------------------------------------------------------------------
-- O ponto de entrada, reemitido com a checagem nova. O corpo é o da 0022 mais o
-- bloco de duplicidade — reemitir inteiro (em vez de um `alter`) é o padrão deste
-- repositório para função: a definição vigente fica legível num arquivo só.
--
-- A checagem roda para os documentos de BALANÇO/BALANCETE/COMBINADO: é onde a
-- transposição com dois nomes aparece (patrimônio e passivo não circulante no
-- v35). Rodá-la em todo tipo de documento repetiria a mesma pendência a cada
-- extração de DRE, faturamento e nota.
-- -----------------------------------------------------------------------------
create or replace function fn_reconciliar_por_documento(p_documento_id uuid)
returns jsonb
language plpgsql
as $$
declare
  v_caso_id     uuid;
  v_entidade_id uuid;
  v_periodo_id  uuid;
  v_tipo        text;
  v_checagens   jsonb := '[]'::jsonb;
  v_periodos    uuid[];
  v_per         uuid;
  v_res         jsonb;

begin
  select caso_id, entidade_id, periodo_id, tipo_taxonomia
    into v_caso_id, v_entidade_id, v_periodo_id, v_tipo
  from documento where id = p_documento_id;

  if v_caso_id is null then
    return jsonb_build_object('executado', false, 'motivo', 'documento não encontrado');
  end if;

  select array_agg(p.id order by (p.id = v_periodo_id) desc, p.referencia)
    into v_periodos
  from periodo p
  where p.caso_id = v_caso_id
    and (p.id = v_periodo_id or fn_periodos_compativeis(p.id, v_periodo_id));
  if v_periodos is null or cardinality(v_periodos) = 0 then
    v_periodos := array[v_periodo_id];
  end if;

  -- Classe A (0009)
  if v_tipo in ('BALANCO', 'BALANCETE', 'COMBINADO') then
    foreach v_per in array v_periodos loop
      v_res := fn_reconciliar_ativo_passivo_pl(v_caso_id, v_entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res);
  end if;
  if v_tipo in ('BALANCO', 'BALANCETE', 'COMBINADO', 'FLUXO_CAIXA') then
    foreach v_per in array v_periodos loop
      v_res := fn_reconciliar_caixa_bp_fluxo(v_caso_id, v_entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res);
  end if;

  -- Classe B (0015/0021)
  if v_tipo in ('DRE', 'FATURAMENTO_24M') then
    foreach v_per in array v_periodos loop
      v_res := fn_reconciliar_receita_dre_vs_faturamento(v_caso_id, v_entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res);
  end if;
  if v_tipo in ('DRE', 'MAPA_DIVIDA') then
    foreach v_per in array v_periodos loop
      v_res := fn_reconciliar_despfin_dre_vs_divida(v_caso_id, v_entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res);
  end if;

  -- Duplicidade de rótulo (0105). Sem loop de período: é por caso/entidade.
  if v_tipo in ('BALANCO', 'BALANCETE', 'COMBINADO') then
    v_checagens := v_checagens || jsonb_build_array(
      fn_reconciliar_duplicidade(v_caso_id, v_entidade_id));
  end if;

  return jsonb_build_object('executado', true, 'documento_id', p_documento_id, 'checagens', v_checagens);
end;
$$;

-- -----------------------------------------------------------------------------
-- VERIFICAÇÃO EMBUTIDA. Três asserts, cada um provado não-vazio: desligando o
-- critério que ele cobre, o assert reprova (é o que `db/test/run.sh` refaz).
-- -----------------------------------------------------------------------------
do $$
declare
  v_caso uuid := gen_random_uuid();
  v_ent  uuid := gen_random_uuid();
  v_per  uuid := gen_random_uuid();
  v_doc  uuid := gen_random_uuid();
  v_ver  uuid := gen_random_uuid();
  v_n    int;
  v_res  jsonb;
begin
  insert into caso (id, nome, produto) values (v_caso, 'VERIF 0105', 'reestruturacao');
  insert into entidade (id, caso_id, razao_social) values (v_ent, v_caso, 'ACME LTDA.');
  insert into periodo (id, caso_id, tipo, referencia) values (v_per, v_caso, 'multi', '24,25');
  insert into documento (id, caso_id, entidade_id, periodo_id, tipo_taxonomia, status, confianca, fonte)
    values (v_doc, v_caso, v_ent, v_per, 'BALANCO', 'valido', 0.97, 'verificacao');
  insert into documento_versao (id, documento_id, n_versao, arquivo_ref, nome_original, hash)
    values (v_ver, v_doc, 1, 'x', 'BALANCO.pdf', md5(v_ver::text));

  insert into campo_extraido
    (documento_versao_id, chave, valor_num, unidade, confianca, secao, secao_canonica, periodo_coluna, status_aceite)
  values
    -- (1) O PAR DO v35: rótulos sem radical comum, valor idêntico em DOIS anos.
    (v_ver, 'Prejuízos acumulados',  -39150, 'milhar', 0.97, 'PL', 'patrimonio_liquido', '2025', 'aceito'),
    (v_ver, 'Resultados Acumulados', -39150, 'milhar', 0.97, 'PL', 'patrimonio_liquido', '2025', 'aceito'),
    (v_ver, 'Prejuízos acumulados',  -21249, 'milhar', 0.97, 'PL', 'patrimonio_liquido', '2024', 'aceito'),
    (v_ver, 'Resultados Acumulados', -21249, 'milhar', 0.97, 'PL', 'patrimonio_liquido', '2024', 'aceito'),
    -- (2) DUAS PROVISÕES DE MESMO VALOR num ano só, sem radical comum: NÃO é par.
    (v_ver, 'Provisão para contingências cíveis',       2000, 'milhar', 0.97, 'PNC', 'passivo_nao_circulante', '2025', 'aceito'),
    (v_ver, 'Provisão para riscos trabalhistas',        2000, 'milhar', 0.97, 'PNC', 'passivo_nao_circulante', '2025', 'aceito'),
    -- (3) RÓTULO REESCRITO (radical contido), uma coluna só: É par.
    (v_ver, 'Capital social subscrito',                45000, 'milhar', 0.97, 'PL', 'patrimonio_liquido', '2025', 'aceito'),
    (v_ver, 'Capital social subscrito integralizado',  45000, 'milhar', 0.97, 'PL', 'patrimonio_liquido', '2025', 'aceito'),
    -- (4) MESMA SEÇÃO, valores DIFERENTES: nunca é par.
    (v_ver, 'Reserva legal',                            1200, 'milhar', 0.97, 'PL', 'patrimonio_liquido', '2025', 'aceito'),
    (v_ver, 'Reserva estatutária',                      3050, 'milhar', 0.97, 'PL', 'patrimonio_liquido', '2025', 'aceito'),
    -- (5) SUBTOTAL × SEU ÚNICO COMPONENTE (a `secao` do componente É o rótulo do
    -- subtotal). Foi o que o book mostrou em 5 pares por entidade: grupo com um
    -- componente, já excluído da soma pela detecção estrutural do export.
    (v_ver, 'Obrigações Tributárias',                   8706, 'milhar', 0.97, 'PNC', 'passivo_nao_circulante', '2025', 'aceito'),
    (v_ver, 'Parcelamentos tributários - longo prazo',  8706, 'milhar', 0.97, 'Obrigações Tributárias', 'passivo_nao_circulante', '2025', 'aceito'),
    (v_ver, 'Obrigações Tributárias',                   7000, 'milhar', 0.97, 'PNC', 'passivo_nao_circulante', '2024', 'aceito'),
    (v_ver, 'Parcelamentos tributários - longo prazo',  7000, 'milhar', 0.97, 'Obrigações Tributárias', 'passivo_nao_circulante', '2024', 'aceito'),
    -- (6) CONTAS DISTINTAS EM SUBSEÇÕES DIFERENTES, mesmo valor nos dois anos. É o
    -- último falso positivo que o book tinha ("Créditos tributários - ICMS sobre
    -- ativo permanente" no Realizável a Longo Prazo × "Veículos e empilhadeiras" no
    -- Imobilizado, ambos 3.900): coincidência de valor, contas diferentes.
    (v_ver, 'Créditos tributários - ICMS',              3900, 'milhar', 0.97, 'Realizável a Longo Prazo', 'ativo_nao_circulante', '2025', 'aceito'),
    (v_ver, 'Veículos e empilhadeiras',                 3900, 'milhar', 0.97, 'Imobilizado', 'ativo_nao_circulante', '2025', 'aceito'),
    (v_ver, 'Créditos tributários - ICMS',              3400, 'milhar', 0.97, 'Realizável a Longo Prazo', 'ativo_nao_circulante', '2024', 'aceito'),
    (v_ver, 'Veículos e empilhadeiras',                 3400, 'milhar', 0.97, 'Imobilizado', 'ativo_nao_circulante', '2024', 'aceito');

  select count(*) into v_n from fn_pares_duplicados_do_caso(v_caso, 'ACME LTDA.')
   where rotulo_a = 'Prejuízos acumulados' and rotulo_b = 'Resultados Acumulados';
  if v_n <> 1 then
    raise exception '0105: o par do v35 (Prejuízos acumulados = Resultados Acumulados, -39.150 em dois anos) NÃO foi detectado (achou %)', v_n;
  end if;

  select count(*) into v_n from fn_pares_duplicados_do_caso(v_caso, 'ACME LTDA.')
   where rotulo_a like 'Provisão%' or rotulo_b like 'Provisão%';
  if v_n <> 0 then
    raise exception '0105: duas provisões de MESMO VALOR num ano só viraram par — é falso positivo, e falso positivo aqui apaga conta legítima (achou %)', v_n;
  end if;

  select count(*) into v_n from fn_pares_duplicados_do_caso(v_caso, 'ACME LTDA.')
   where rotulo_a like 'Capital social%' and rotulo_b like 'Capital social%';
  if v_n <> 1 then
    raise exception '0105: rótulo REESCRITO (radical estrutural contido) numa coluna só não foi detectado (achou %)', v_n;
  end if;

  select count(*) into v_n from fn_pares_duplicados_do_caso(v_caso, 'ACME LTDA.')
   where rotulo_a like 'Reserva%' and rotulo_b like 'Reserva%';
  if v_n <> 0 then
    raise exception '0105: rótulos de valores DIFERENTES viraram par (achou %)', v_n;
  end if;

  select count(*) into v_n from fn_pares_duplicados_do_caso(v_caso, 'ACME LTDA.')
   where rotulo_a like 'Obriga%' or rotulo_b like 'Parcelamento%';
  if v_n <> 0 then
    raise exception '0105: SUBTOTAL x COMPONENTE virou par de duplicidade — o export já o exclui por estrutura, e cobrar de novo aqui enche a fila de revisão (achou %)', v_n;
  end if;

  select count(*) into v_n from fn_pares_duplicados_do_caso(v_caso, 'ACME LTDA.')
   where rotulo_a like 'Créditos%' or rotulo_b like 'Veículos%';
  if v_n <> 0 then
    raise exception '0105: contas em SUBSEÇÕES DIFERENTES com o mesmo valor viraram par — o documento diz que são coisas diferentes (achou %)', v_n;
  end if;

  -- Sem SUBSEÇÃO declarada, radical contido numa coluna só não é par: é o formato
  -- do grupo com um componente ("Arrendamentos" × "Arrendamentos a pagar"), e foi o
  -- falso positivo que o fixture do v35 (sem `secao`) devolvia.
  insert into campo_extraido
    (documento_versao_id, chave, valor_num, unidade, confianca, secao, secao_canonica, periodo_coluna, status_aceite)
  values
    (v_ver, 'Arrendamentos',                        3118, 'milhar', 0.97, null, 'passivo_circulante', '2025', 'aceito'),
    (v_ver, 'Arrendamentos a pagar - CPC 06 (R2)',  3118, 'milhar', 0.97, null, 'passivo_circulante', '2025', 'aceito');
  select count(*) into v_n from fn_pares_duplicados_do_caso(v_caso, 'ACME LTDA.')
   where rotulo_a like 'Arrendamentos%' or rotulo_b like 'Arrendamentos%';
  if v_n <> 0 then
    raise exception '0105: sem subseção declarada, radical contido numa coluna só virou par — é o grupo com um componente, não conta duplicada (achou %)', v_n;
  end if;

  -- A checagem abre pendência e NÃO apaga dado.
  v_res := fn_reconciliar_duplicidade(v_caso, v_ent);
  if coalesce(v_res->>'resultado', '') <> 'divergencia' then
    raise exception '0105: a checagem não acusou divergência com dois pares na base (%)', v_res;
  end if;
  select count(*) into v_n from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:duplicidade_de_rotulo' and estado <> 'resolvida';
  if v_n <> 1 then
    raise exception '0105: a checagem não abriu (ou duplicou) a pendência (achou %)', v_n;
  end if;
  select count(*) into v_n from campo_extraido where documento_versao_id = v_ver;
  if v_n <> 20 then
    raise exception '0105: a checagem MEXEU no dado — devia haver 20 linhas, há % (ela só pode LER)', v_n;
  end if;

  -- Idempotência: rodar de novo não duplica a pendência (é o que a reextração faz).
  perform fn_reconciliar_duplicidade(v_caso, v_ent);
  select count(*) into v_n from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:duplicidade_de_rotulo' and estado <> 'resolvida';
  if v_n <> 1 then
    raise exception '0105: reexecutar duplicou a pendência (achou %)', v_n;
  end if;

  delete from caso where id = v_caso;
  raise notice '0105 OK — par do v35 detectado; recusados: provisões de igual valor, valores diferentes, subtotal x componente, subseções diferentes; dado intacto; idempotente';
end $$;

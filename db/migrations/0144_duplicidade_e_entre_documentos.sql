-- 0144 — DUPLICIDADE DE RÓTULO É FATO ENTRE DOCUMENTOS. DENTRO DE UM, É A
-- HIERARQUIA DELE.
--
-- ACHADO NA RODADA v48. Seis das 27 pendências abertas eram
-- `duplicidade_de_rotulo`, e a medição as derrubou todas de uma vez. Os 33 pares
-- que a 0105 devolvia no caso real têm, TODOS, a mesma assinatura:
--
--     33 de 33 pares · os dois rótulos no MESMO documento
--     32 de 33 pares · a distância entre eles em `ordem` é 1 (linhas vizinhas)
--
-- E a lista fala por si:
--
--     "Disponível"            = "Caixa"
--     "Empréstimos"           = "FINAME - longo prazo"
--     "Obrigações Tributárias"= "IPTU e taxas a recolher"
--     "Provisões"             = "Provisão para contingências trabalhistas e cíveis"
--     "Investimentos"         = "Participações em outras sociedades - avaliadas ao custo"
--
-- Não é a mesma conta transposta duas vezes: é o SUBTOTAL DE GRUPO seguido do seu
-- único componente. Grupo de um filho, o filho vale o grupo, os dois valores
-- coincidem ao centavo — e é assim que um balanço se escreve.
--
-- POR QUE O FILTRO QUE JÁ EXISTIA DEIXOU PASSAR. A 0105 previu exatamente este
-- par e o barrou com `subtotal_de`: "a subseção declarada de um é o rótulo do
-- outro". O filtro depende de `campo_extraido.secao` trazer o grupo IMEDIATO — e
-- na v48 `secao` chega ACHATADA, com o subtotal e as folhas dele todos marcados
-- com a seção de topo ("Ativo Circulante"). É a MESMA causa raiz que a 0143
-- documentou para a checagem de árvore, aparecendo pela segunda vez em outro
-- lugar. Duas guardas diferentes, o mesmo sinal faltando embaixo das duas.
--
-- O QUE MUDA, E POR QUE É UM CRITÉRIO E NÃO UM REMENDO. A 0105 abre dizendo o que
-- ela existe para pegar, e a frase é literal: "dois documentos do mesmo caso (o
-- balanço e o balancete/combinado) escrevem o mesmo fato de dois jeitos, e a
-- extração, fiel a cada documento, grava as duas. Somadas, inflam o patrimônio."
-- O dano é INTERDOCUMENTAL por definição — é a soma de duas fontes que dobra o
-- número. Dentro de UM documento não há nada a somar duas vezes: a demonstração é
-- internamente consistente por construção, cada conta aparece uma vez, e se não
-- aparecesse a seção não fecharia — que é trabalho da `fn_conferir_arvore`, não
-- desta checagem. A própria 0105 diz isso do lado do export: "subtotal já é
-- tratado pela detecção estrutural do export, e cobrar duas vezes a mesma coisa
-- polui a fila".
--
-- Então o par passa a exigir que NENHUM documento contenha os dois rótulos. Onde
-- um documento contém os dois, ele é a autoridade sobre a relação entre eles, e o
-- que ele está dizendo é hierarquia.
--
-- MEDIDO ANTES DE APLICAR, contra o caso real da v48: dos 39 pares brutos, 38
-- estão no mesmo documento e caem; o único entre documentos distintos
-- ("2.1.01.001 - fornecedores nacionais" × um lançamento de reversão de provisão,
-- 17.945 numa coluna só, sem radical comum) já caía nos filtros que a 0105 tinha.
-- Saldo: seis pendências falsas a menos e nenhum achado verdadeiro perdido.
--
-- REEMISSÃO INTEIRA, e não patch com âncora como a 0141/0142/0143: aquelas tocam
-- funções de centenas de linhas cujo corpo vigente não está legível em arquivo
-- nenhum. Esta é uma função `language sql` de ~130 linhas que a 0105 traz por
-- extenso; reemitir deixa a definição vigente conferível num arquivo só, que é o
-- padrão deste repositório quando ele é praticável.

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
      d.tipo_taxonomia,
      d.id                                         as doc_id
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
           -- 0144: DE QUAIS DOCUMENTOS este rótulo veio. É o que sustenta o
           -- filtro `mesmo_documento` — o critério novo, e o mais forte dos três.
           array_agg(distinct doc_id) as docs,
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
      -- 0144: OS DOIS RÓTULOS SAEM DO MESMO DOCUMENTO?
      --
      -- Se saem, ele é a autoridade sobre a relação entre eles — e o que ele está
      -- dizendo é hierarquia, não duplicidade. Uma demonstração é internamente
      -- consistente por construção: cada conta aparece uma vez, e se aparecesse
      -- duas a seção não fecharia, que é trabalho da `fn_conferir_arvore` (0133),
      -- não desta checagem. O dano que a 0105 existe para achar é a soma de DUAS
      -- FONTES — o balanço e o balancete escrevendo o mesmo fato de dois jeitos.
      --
      -- Medido na v48: 33 de 33 pares candidatos estavam no mesmo documento, 32
      -- deles em linhas VIZINHAS (`ordem` a distância 1). Subtotal de grupo
      -- seguido do seu único componente, e não conta transposta duas vezes.
      bool_or(a.docs && b.docs) as mesmo_documento,
      -- É o par SUBTOTAL × COMPONENTE? O documento diz: a subseção declarada de um
      -- é o rótulo do outro. Medido no book (extração fiel): "Obrigações
      -- Tributárias" × "Parcelamentos tributários - longo prazo", "Empréstimos e
      -- Financiamentos" × "Financiamentos - FINAME/BNDES", "Partes Relacionadas" ×
      -- "Mútuos a pagar", "Investimentos" × "Participações em outras sociedades".
      -- São grupo com UM componente, não conta duplicada — e o export já os exclui
      -- da soma pela detecção estrutural. Cobrar de novo aqui encheria a fila de
      -- revisão com o que já está resolvido, que é exatamente o que a 0023 desfez.
      --
      -- 0144: ESTE FILTRO CONTINUA, MAS NÃO SE PODE MAIS CONTAR COM ELE SOZINHO.
      -- Ele depende de `secao` trazer o grupo IMEDIATO, e na v48 `secao` chega
      -- ACHATADA (subtotal e folhas com a seção de topo) — a mesma causa raiz que
      -- a 0143 documentou. Com o sinal ausente, `subtotal_de` nunca dispara.
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
  where not pr.mesmo_documento
    and not pr.subtotal_de
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
  'Pares de rótulos DIFERENTES, em DOCUMENTOS DIFERENTES, na mesma seção canônica, com valor '
  'idêntico nas mesmas colunas — candidatos a ser a MESMA conta transposta duas vezes (achado do '
  'v35: "Prejuízos acumulados" e "Resultados Acumulados", ambos -39.150). Dois rótulos no MESMO '
  'documento são a hierarquia DELE (0144), não duplicidade. Não decide nada: alimenta a checagem '
  'de reconciliação, que abre pendência para decisão humana. Critério estreito de propósito — '
  'falso positivo aqui gasta o tempo do analista.';

-- O `criterio` que a checagem grava na trilha passa a mentir se ficar como está —
-- e é ele que alguém lê, seis meses depois, para entender por que a pendência
-- abriu (ou não abriu). Reemitida só por isso: o corpo é o da 0105.
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
    jsonb_build_object('criterio', 'rótulos em DOCUMENTOS DIFERENTES (0144), mesma secao_canonica, '
      || 'valor idêntico na mesma coluna, papel conta, e (>=2 colunas coincidentes ou radical '
      || 'estrutural compartilhado)'),
    v_descricao);
end;
$$;

comment on function fn_reconciliar_duplicidade(uuid, uuid) is
  'Checagem de reconciliação: acha a MESMA conta transposta com dois rótulos EM DOCUMENTOS '
  'DIFERENTES e abre pendência com o valor dobrado. Não apaga nem reescreve dado — decisão '
  'humana. Por caso/entidade (a duplicidade é fato da estrutura dos documentos, não de um '
  'exercício), daí periodo_id nulo.';

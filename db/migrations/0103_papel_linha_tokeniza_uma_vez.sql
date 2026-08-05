-- =============================================================================
-- Migration 0103 — `fn_papel_linha` tokeniza o rótulo UMA vez, não nove
--
-- A TERCEIRA FATIA DO MESMO PROBLEMA, e as três são de naturezas diferentes:
--
--   0101  parou de REPETIR o trabalho de fora — a conferência executava a
--         listagem cinco vezes, duas delas uma vez por vínculo.
--   0102  parou de ler ocorrência de versão SUPERADA — cada reextração somava um
--         jogo inteiro de ocorrências ao caso, e o custo é linear nelas.
--   0103  (esta) para de repetir o trabalho de DENTRO de cada rótulo.
--
-- POR QUE AINDA FALTAVA. Eu medi a 0101 contra um caso de 55 rótulos DISTINTOS e
-- comemorei 9,3 s → 100 ms. O caso real do dono tem ~250. Refeita a medição com a
-- forma certa (14 documentos, 770 ocorrências, 750 linhas lógicas, oito tipos de
-- documento), as duas funções da tela voltaram a ~1,9 s CADA — o teto de 8 s de
-- novo, agora com as DUAS cancelando na mesma tela, que foi o que o dono viu.
--
-- Fixture menor que a produção mede o instrumento, não o sistema. O teste de
-- escala foi corrigido junto, e é ele que trava isto daqui em diante.
--
-- O QUE SOBROU DE CARO, e agora é o gargalo inteiro: `fn_papel_linha` chama
-- `fn_rotulo_estrutural` NOVE VEZES (ativo, passivo, patrimônio, passivo+PL,
-- ativo circulante, ativo não circulante, passivo circulante, passivo não
-- circulante, realizável a longo prazo). E cada chamada REFAZ do zero a mesma
-- coisa: normaliza o texto, troca pontuação por espaço, quebra em palavras,
-- descarta ligação e ruído, ordena. Nove tokenizações idênticas do mesmo rótulo,
-- para nove comparações que poderiam usar a primeira.
--
-- A TOKENIZAÇÃO VIRA FUNÇÃO PRÓPRIA e passa a ser feita uma vez. É a mesma
-- regra, no mesmo lugar: `fn_rotulo_estrutural` é reemitida em cima do helper, de
-- modo que continua existindo UMA definição de "quais palavras deste rótulo
-- contam" — a reconciliação (0034) e o papel da linha (0042) seguem obrigados a
-- concordar, que é o motivo de `fn_rotulo_estrutural` ter sido reaproveitada em
-- vez de copiada.
--
-- NENHUM RESULTADO MUDA. Os 283 asserts do run.sh passam sem uma linha alterada.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- fn_tokens_estruturais — as palavras que CONTAM num rótulo, ordenadas.
--
-- Corpo extraído de `fn_rotulo_estrutural` (0034), sem mudança de regra: a
-- pontuação vira espaço ANTES do split ("TOTAL DO ATIVO (CIRCULANTE + NÃO
-- CIRCULANTE)" não pode produzir o token "(circulante"), e a lista de descarte
-- é a mesma — ligação, ruído de rodapé e "líquido", que sai porque "PATRIMÔNIO
-- LÍQUIDO" e "PATRIMÔNIO" são o mesmo grupo.
--
-- Ordenada e sem repetição para que a comparação seja igualdade de array, que é
-- o que as duas funções já faziam cada uma por conta.
-- -----------------------------------------------------------------------------
create or replace function fn_tokens_estruturais(p_chave text)
returns text[]
language sql
immutable
as $$
  select coalesce((
    select array_agg(distinct w order by w)
    from unnest(
      regexp_split_to_array(
        regexp_replace(fn_normalizar_texto(p_chave), '[^a-z0-9]+', ' ', 'g'),
        '\s+')
    ) as w
    where w <> ''
      and w not in ('total','totais','geral','gerais','soma','somatorio','subtotal',
                    'de','do','da','dos','das','e','o','a','os','as','em','no','na',
                    'liquido','liquida','consolidado','consolidada','combinado','combinada')
  ), array[]::text[]);
$$;

comment on function fn_tokens_estruturais(text) is
  'Palavras estruturais de um rótulo (sem ligação, ruído de rodapé e a palavra "total"), '
  'ordenadas e sem repetição. Extraída de fn_rotulo_estrutural na 0102 para ser calculada UMA '
  'vez por rótulo: fn_papel_linha comparava nove grupos e pagava nove tokenizações iguais.';

grant execute on function fn_tokens_estruturais(text) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_rotulo_estrutural — mesma regra, agora em cima do helper.
--
-- Continua sendo a função que a reconciliação chama. Reemiti-la aqui é o que
-- garante que só exista UMA definição de tokenização: se ela ficasse com a cópia
-- antiga, o papel da linha e a reconciliação poderiam divergir no primeiro
-- caractere que só uma das duas tratasse — e a que divergisse em silêncio seria
-- descoberta em produção, como quase tudo neste arquivo.
-- -----------------------------------------------------------------------------
create or replace function fn_rotulo_estrutural(p_chave text, p_tokens_exigidos text[])
returns boolean
language sql
immutable
as $$
  select fn_tokens_estruturais(p_chave)
       = coalesce((select array_agg(distinct t order by t) from unnest(p_tokens_exigidos) as t),
                  array[]::text[]);
$$;

comment on function fn_rotulo_estrutural(text, text[]) is
  'Um rótulo É o total de um grupo quando, tiradas ligação e a palavra "total", sobram '
  'exatamente as palavras estruturais do grupo. Tradução do `soEstrutural` do classificador '
  'TypeScript (0034); desde a 0102 apoiada em fn_tokens_estruturais.';

-- -----------------------------------------------------------------------------
-- fn_papel_linha — uma tokenização, nove comparações.
--
-- Estrutura idêntica à da 0042, na mesma ordem de decisão (derivado → série
-- mensal → subtotal por prefixo → subtotal por grupo → subtotais da DRE e do
-- Fluxo → conta). A única mudança é que os nove grupos são comparados contra o
-- array já calculado, em vez de nove chamadas que refazem o mesmo trabalho.
--
-- Os arrays literais estão ORDENADOS aqui, porque a comparação é de igualdade de
-- array; passá-los por `fn_tokens_estruturais` seria mais defensivo, mas a
-- ordenação de três palavras é verificável de olho e o teste da 0042 cobre cada
-- um dos nove casos com o rótulo real do documento.
-- -----------------------------------------------------------------------------
create or replace function fn_papel_linha(
  p_chave text,
  p_tipo_taxonomia text default null,
  p_unidade text default null
)
returns text
language sql
immutable
as $$
  with n as (
    select fn_normalizar_texto(p_chave) as t,
           fn_tokens_estruturais(p_chave) as toks
  )
  select case
    -- ---- DERIVADO: indicador gerencial, não dinheiro ------------------------
    when (select t from n) ~ '^(indice|indices) '
      or (select t from n) ~ '^media (mensal|diaria|anual)'
      or (select t from n) ~ '^ticket medio'
      or (select t from n) ~ '^prazo medio'
      or (select t from n) ~ '^(margem|rentabilidade|retorno) '
      or (select t from n) ~ '^capital circulante liquido'
      or (select t from n) ~ '^(giro|rotacao) (de|do|da) '
      or (select t from n) ~ 'indicador gerencial'
      then 'derivado'

    -- ---- SÉRIE MENSAL: insumo da curva de sazonalidade ----------------------
    when p_tipo_taxonomia = 'FATURAMENTO_24M' and fn_mes_do_rotulo(p_chave) is not null
      then 'serie_mensal'

    -- ---- SUBTOTAL: já é a soma de outras linhas -----------------------------
    -- (a) prefixo "total"/"subtotal"/"soma"
    when (select t from n) ~ '^(total|totais|subtotal|soma) ' or (select t from n) in ('total','totais','subtotal')
      then 'subtotal'
    -- (b) o total do grupo SEM a palavra "total" (0034), agora contra os tokens
    --     já calculados. Arrays em ordem alfabética — é igualdade de array.
    when (select toks from n) in (
        array['ativo'],
        array['passivo'],
        array['patrimonio'],
        array['passivo','patrimonio'],
        array['ativo','circulante'],
        array['ativo','circulante','nao'],
        array['circulante','passivo'],
        array['circulante','nao','passivo'],
        array['longo','prazo','realizavel'])
      then 'subtotal'
    -- (c) as linhas de RESULTADO da DRE e os subtotais do Fluxo, lista fechada
    when (select t from n) in (
        'receita operacional liquida','receita liquida','receita liquida de vendas',
        'lucro bruto','prejuizo bruto',
        'resultado operacional antes do resultado financeiro',
        'resultado antes dos tributos sobre o lucro','resultado antes dos tributos',
        'lucro liquido do exercicio','prejuizo liquido do exercicio',
        'lucro liquido','prejuizo liquido','resultado do exercicio',
        'resultado financeiro liquido','resultado financeiro')
      then 'subtotal'
    when (select t from n) ~ '^caixa liquido (gerado|aplicado|gerado pelas)'
      or (select t from n) ~ '^(aumento|reducao|variacao) liquida? (de|do|da) caixa'
      then 'subtotal'

    else 'conta'
  end;
$$;

comment on function fn_papel_linha(text, text, text) is
  'Papel da linha na modelagem: conta | subtotal | derivado | serie_mensal. Lista FECHADA de '
  'padrões (não heurística de semelhança) porque errar para subtotal esconde conta de verdade e '
  'errar para conta deixa passar dupla contagem. 0102: tokeniza o rótulo uma vez e compara os '
  'nove grupos contra o resultado, em vez de nove chamadas a fn_rotulo_estrutural.';

grant execute on function fn_papel_linha(text, text, text) to authenticated;

-- =============================================================================
-- E A MARCA DE SOBREPOSIÇÃO: comparação de ARRAY, não chamada de função por par.
--
-- Com o papel resolvido, o que sobrou de caro foi `sobreposicao_suspeita`. Ela
-- avalia `fn_rotulo_contido` para cada par de linhas da mesma seção com o mesmo
-- valor — e a função, a cada chamada, quebra OS DOIS rótulos em palavras e
-- calcula os radicais outra vez. Num caso com muitas colisões de valor isso são
-- milhares de tokenizações repetidas dos mesmos poucos rótulos.
--
-- Os radicais viram coluna calculada UMA vez por linha lógica, e o teste de
-- contenção vira o operador `<@` do Postgres. Zero chamada de função dentro do
-- laço de pares.
--
-- A REGRA É EXATAMENTE A MESMA, e vale escrever por que: `fn_rotulo_contido`
-- dizia "todo radical de 5 letras do rótulo curto aparece no longo, e o curto tem
-- ao menos uma palavra de 4+ letras". `radicais_curto <@ radicais_longo` é a
-- primeira metade, literalmente; a segunda vira uma coluna booleana. A função
-- continua existindo, reimplementada sobre os mesmos helpers — ela é a definição
-- pública da regra e é o que os testes chamam.
-- =============================================================================

create or replace function fn_radicais_rotulo(p_chave text)
returns text[]
language sql
immutable
as $$
  select coalesce((
    select array_agg(distinct left(w, 5) order by left(w, 5))
    from unnest(regexp_split_to_array(
      regexp_replace(fn_normalizar_texto(p_chave), '[^a-z0-9]+', ' ', 'g'), '\s+')) as w
    where w <> ''
  ), array[]::text[]);
$$;

comment on function fn_radicais_rotulo(text) is
  'Radicais de 5 letras das palavras de um rótulo, ordenados e sem repetição. Extraído de '
  'fn_rotulo_contido na 0102 para ser calculado uma vez por linha lógica em vez de duas vezes '
  'por PAR de linhas comparadas.';

create or replace function fn_tem_palavra_longa(p_chave text)
returns boolean
language sql
immutable
as $$
  select exists (
    select 1
    from unnest(regexp_split_to_array(
      regexp_replace(fn_normalizar_texto(p_chave), '[^a-z0-9]+', ' ', 'g'), '\s+')) as w
    where length(w) >= 4
  );
$$;

comment on function fn_tem_palavra_longa(text) is
  'O rótulo tem ao menos uma palavra de 4+ letras? Metade da regra de fn_rotulo_contido: sem '
  'isto, "de" contido em qualquer coisa marcaria sobreposição em toda linha.';

-- fn_rotulo_contido continua sendo a definição pública da regra — só passa a
-- usar os mesmos dois helpers, para não existirem duas versões dela.
create or replace function fn_rotulo_contido(p_curto text, p_longo text)
returns boolean
language sql
immutable
as $$
  select fn_tem_palavra_longa(p_curto)
     and fn_radicais_rotulo(p_curto) <@ fn_radicais_rotulo(p_longo);
$$;

comment on function fn_rotulo_contido(text, text) is
  'O primeiro rótulo é uma descrição mais grossa do segundo (radicais de 5 letras contidos, com '
  'ao menos uma palavra de 4+ letras)? Usado por sobreposicao_suspeita: valor igual sozinho acusa '
  'coincidência, e guarda que acusa coincidência é guarda que se aprende a ignorar.';

grant execute on function fn_radicais_rotulo(text) to authenticated;
grant execute on function fn_tem_palavra_longa(text) to authenticated;
grant execute on function fn_rotulo_contido(text, text) to authenticated;

create or replace function fn_linhas_para_modelagem(p_caso_id uuid)
returns table (
  secao_canonica text,
  chave          text,
  rotulo_norm    text,
  entidade       text,
  valor_ultimo   numeric,
  n_ocorrencias  bigint,
  papel          text,
  unidade        text,
  moeda          text,
  documentos     text[],
  sobreposicao_suspeita boolean
)
language sql
stable
as $$
  -- marca-0102
  -- marca-0103
  --
  -- AS DUAS MARCAS FICAM. `fn_diagnostico_modelagem` (0102) confere se a correção
  -- daquela migration está INSTALADA NO BANCO procurando `marca-0102` no corpo da
  -- função — é o teste que separa "mergeado" de "aplicado", e foi ele que pegou
  -- esta reemissão. Trocar a marca por uma nova apagaria a resposta da pergunta
  -- que ela faz; a 0103 reemite o corpo e MANTÉM o filtro de versão vigente, então
  -- a marca da 0102 continua verdadeira.
  with bruto as (
    select
      ce.secao_canonica,
      ce.chave,
      fn_normalizar_texto(ce.chave) as rotulo_norm,
      coalesce(ce.entidade_coluna, e.razao_social) as entidade,
      ce.valor_num,
      ce.unidade,
      ce.moeda,
      d.tipo_taxonomia
    from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
    left join entidade e on e.id = d.entidade_id
    where d.caso_id = p_caso_id
      and ce.valor_num is not null
      -- 0102: só a versão VIGENTE de cada documento. Sem isto, cada reextração
      -- soma um jogo inteiro de ocorrências ao caso — inflando n_ocorrencias,
      -- deixando valor_ultimo vir de versão superada, e devolvendo o caso ao
      -- statement_timeout que a 0101 tinha acabado de destravar.
      and dv.id = fn_versao_com_extracao(d.id)
  ),
  -- O PAPEL É PROPRIEDADE DO RÓTULO, NÃO DA OCORRÊNCIA (0101).
  --
  -- `fn_papel_linha` depende só de (chave, tipo do documento, unidade) e custa
  -- ~1,6 ms por chamada. Avaliá-la por ocorrência era pagar 760 vezes por uma
  -- resposta que tem ~250 valores distintos. Aqui ela roda uma vez por combinação
  -- distinta e o resultado volta por join — é a mesma resposta, porque a função é
  -- `immutable`.
  papel_do_rotulo as (
    select distinct chave, tipo_taxonomia, unidade,
           fn_papel_linha(chave, tipo_taxonomia, unidade) as papel
    from (select distinct chave, tipo_taxonomia, unidade from bruto) d
  ),
  ocorrencia as (
    select b.*, p.papel
    from bruto b
    join papel_do_rotulo p
      on p.chave = b.chave
     and p.tipo_taxonomia is not distinct from b.tipo_taxonomia
     and p.unidade is not distinct from b.unidade
  ),
  base as (
    select
      o.secao_canonica,
      (array_agg(o.chave order by length(o.chave)))[1] as chave,
      o.rotulo_norm,
      max(o.entidade) as entidade,
      -- valor da ocorrência de MAIOR MÓDULO, COM O SINAL (0042).
      (array_agg(o.valor_num order by abs(o.valor_num) desc nulls last))[1] as valor_ultimo,
      count(*) as n_ocorrencias,
      max(o.unidade) as unidade,
      max(o.moeda) as moeda,
      array_agg(distinct o.tipo_taxonomia) as documentos,
      -- papel da ocorrência de MAIOR PRIORIDADE (fn_papel_prioridade): no empate
      -- entre documentos, o lado seguro é não projetar.
      (array_agg(o.papel order by fn_papel_prioridade(o.papel)))[1] as papel
    from ocorrencia o
    group by o.secao_canonica, o.rotulo_norm
  ),
  -- SOBREPOSIÇÃO SUSPEITA, por join (0101). Mesma regra da 0042: outra linha da
  -- MESMA seção, MESMO valor, e um rótulo descrevendo o outro de forma mais
  -- grossa (`Provisões` × `Provisão para passivo a descoberto de controlada`).
  -- A função não escolhe por ninguém: MARCA, e quem decide é o analista.
  -- 0103: os radicais viram coluna calculada UMA vez por linha lógica, e a
  -- contenção vira o operador `<@`. Antes `fn_rotulo_contido` era avaliada por
  -- PAR de linhas e re-tokenizava OS DOIS rótulos a cada par — com muitas
  -- colisões de valor, milhares de tokenizações dos mesmos poucos rótulos.
  base_r as (
    select b.*,
           fn_radicais_rotulo(b.chave) as radicais,
           fn_tem_palavra_longa(b.chave) as tem_longa
    from base b
  ),
  pares as (
    select b.secao_canonica, b.rotulo_norm as r1, o.rotulo_norm as r2
    from base_r b
    join base_r o
      on coalesce(o.secao_canonica, '') = coalesce(b.secao_canonica, '')
     and o.valor_ultimo = b.valor_ultimo
     -- cada par NÃO ORDENADO uma vez só (antes: duas, uma em cada direção)
     and b.rotulo_norm < o.rotulo_norm
    where b.papel = 'conta' and o.papel = 'conta'
      and ((b.tem_longa and b.radicais <@ o.radicais)
        or (o.tem_longa and o.radicais <@ b.radicais))
  ),
  sobrepostas as (
    select secao_canonica, r1 as rotulo_norm from pares
    union
    select secao_canonica, r2 from pares
  )
  select b.secao_canonica, b.chave, b.rotulo_norm, b.entidade, b.valor_ultimo,
         b.n_ocorrencias, b.papel, b.unidade, b.moeda, b.documentos,
         (s.rotulo_norm is not null) as sobreposicao_suspeita
  from base_r b
  left join sobrepostas s
    on s.rotulo_norm = b.rotulo_norm
   and coalesce(s.secao_canonica, '') = coalesce(b.secao_canonica, '')
  order by b.secao_canonica nulls last, b.rotulo_norm;
$$;

comment on function fn_linhas_para_modelagem(uuid) is
  'Linhas lógicas do caso para a tela de Modelagem, com PAPEL (conta/subtotal/derivado/'
  'serie_mensal), valor COM SINAL, unidade/moeda, documentos de origem e marca de sobreposição. '
  'Existe como função porque campo_extraido não tem caso_id — o escopo por caso mora aqui. '
  '0101: papel calculado uma vez por rótulo e sobreposição por join, para caber no '
  'statement_timeout. 0102: só a versão VIGENTE de cada documento (reextração deixava a versão '
  'superada somando ocorrência e podendo ditar o valor_ultimo).';

grant execute on function fn_linhas_para_modelagem(uuid) to authenticated;

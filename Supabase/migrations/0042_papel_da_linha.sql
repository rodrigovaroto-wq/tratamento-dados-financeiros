-- =============================================================================
-- Migration 0042 — A linha diz O QUE ELA É antes de ser projetada
--
-- O QUE A RODADA REAL (Teste v35, 14 documentos) MOSTROU. A tela de Modelagem
-- listou 236 linhas e tratou TODAS como conta projetável. Nos prints:
--
--   • `Ativo Circulante 67.878` aparece entre os 32 componentes dela; `Passivo
--     Circulante 92.539` entre os 44; `Patrimônio Líquido 39.375` ao lado de
--     Capital Social e Reservas; `RECEITA OPERACIONAL LÍQUIDA 143.380` dentro de
--     Receita Bruta junto de `Vendas de produtos - mercado interno 158.900`.
--     Um clique em "aplicar a todas" projeta o TOTAL **e** as PARTES, e o Excel
--     soma o mesmo dinheiro duas vezes. Dupla contagem é o defeito mais caro
--     deste projeto: ela não parece erro, parece um número maior.
--   • Os 12 `Faturamento Janeiro…Dezembro` entraram como 12 linhas a projetar.
--     Eles são o INSUMO da curva de sazonalidade, não contas: projetá-los ao lado
--     da receita anual conta a mesma receita três vezes (mês + venda + líquida).
--   • `Índice de liquidez corrente 1`, `Média mensal 2024`, `Ticket médio por
--     pedido 38` são indicadores gerenciais — não são dinheiro e não se projetam.
--
-- A DECISÃO DO DONO: subtotal NUNCA é projetado (no Excel ele vira a SOMA dos
-- componentes projetados, então se move sozinho); série mensal alimenta a
-- sazonalidade; indicador fica marcado como derivado.
--
-- E A REGRA MORA AQUI, NÃO NA TELA. `fn_vincular_linha_premissa` e
-- `fn_aplicar_premissa_em_lote` passam a RECUSAR linha que não é conta. Se a
-- proteção existisse só no React, a próxima consulta nova a furaria — é o mesmo
-- raciocínio que fez `fn_linhas_para_modelagem` existir na 0039.
--
-- DOIS DEFEITOS QUE APARECERAM NO CAMINHO, e que a fixture escondia:
--
--   1. `fn_sazonalidade_do_caso` (0040) lê o mês com `left(chave, 3)`. Na fixture
--      os rótulos são "jan/2024" e a curva sai com 12 meses; na EXTRAÇÃO REAL o
--      modelo escreveu "Faturamento Janeiro", `left(...,3)` = "fat", e a curva
--      volta VAZIA. O teste passava porque a fixture usava o rótulo que EU
--      inventei, não o que o extrator produz — exatamente a armadilha que o
--      CLAUDE.md descreve. `fn_mes_do_rotulo` passa a procurar a PALAVRA do mês
--      em qualquer posição, contra lista fechada.
--   2. `fn_linhas_para_modelagem` mostra `max(abs())`, então `(-) Depreciação
--      acumulada` aparece como +52.300. Documentei aquilo como "serve só para
--      reconhecer a conta" — e serve —, mas é a coluna que o analista usa para
--      escolher a premissa, e redutor exibido como positivo engana.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- fn_mes_do_rotulo — o mês que o rótulo nomeia, ou null.
--
-- Por PALAVRA, contra lista FECHADA, em qualquer posição. As três decisões:
--
--   • palavra inteira, não prefixo: `left(chave,3)` reprovava "Faturamento
--     Janeiro" e um `like '%mar%'` aprovaria "Marcas e patentes" — o pior dos
--     dois mundos, cada um numa direção;
--   • qualquer posição, porque o rótulo do mês vem de três formas conhecidas
--     ("jan/2024", "jan/2024 — jan/2025", "Faturamento Janeiro") e nenhuma delas
--     é estável: quem escreve o rótulo é o modelo de extração;
--   • o ANO continua vindo de `periodo_coluna`, como na 0040 — o rótulo diz o
--     mês, a coluna diz o exercício.
-- -----------------------------------------------------------------------------
create or replace function fn_mes_do_rotulo(p_chave text)
returns int
language sql
immutable
as $$
  with palavras as (
    select unnest(regexp_split_to_array(
      regexp_replace(fn_normalizar_texto(p_chave), '[^a-z0-9]+', ' ', 'g'), '\s+')) as w
  )
  select min(m.mes) from palavras p
  join (values
    ('jan',1),('janeiro',1),   ('fev',2),('fevereiro',2),
    ('mar',3),('marco',3),     ('abr',4),('abril',4),
    ('mai',5),('maio',5),      ('jun',6),('junho',6),
    ('jul',7),('julho',7),     ('ago',8),('agosto',8),
    ('set',9),('setembro',9),  ('out',10),('outubro',10),
    ('nov',11),('novembro',11),('dez',12),('dezembro',12)
  ) as m(nome, mes) on m.nome = p.w;
$$;

comment on function fn_mes_do_rotulo(text) is
  'Mês que o rótulo nomeia (1-12) ou null. Palavra inteira contra lista fechada, em qualquer '
  'posição: left(chave,3) reprovava "Faturamento Janeiro" (rótulo real da extração do v35) e um '
  'LIKE aprovaria "Marcas e patentes".';

-- -----------------------------------------------------------------------------
-- fn_papel_linha — conta, subtotal, derivado ou série mensal.
--
-- POR QUE LISTA FECHADA E NÃO HEURÍSTICA. Errar para `subtotal`/`derivado`
-- ESCONDE uma conta de verdade da tela (o analista não consegue projetá-la e não
-- sabe por quê); errar para `conta` deixa a dupla contagem passar. Os dois erros
-- são graves, e uma heurística de semelhança comete os dois. Então: prefixo
-- "total" (nenhuma conta de verdade começa com "total"), `fn_rotulo_estrutural`
-- da 0034 para o total de grupo sem a palavra "total", e conjuntos FECHADOS para
-- as linhas de resultado da DRE e os subtotais do Fluxo.
--
-- `fn_rotulo_estrutural` é reaproveitada de propósito: é a MESMA função que a
-- reconciliação usa para achar "ATIVO" e "PASSIVO E PATRIMÔNIO LÍQUIDO". Duas
-- definições de "o que é o total do grupo" divergiriam, e aí a reconciliação e a
-- modelagem discordariam sobre o mesmo rótulo.
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
  with n as (select fn_normalizar_texto(p_chave) as t)
  select case
    -- ---- DERIVADO: indicador gerencial, não dinheiro ------------------------
    -- Lista fechada de padrões. `Índice de liquidez corrente 0,65`, `Média mensal
    -- 2024`, `Ticket médio por pedido` e os prazos médios do capital de giro são
    -- RESULTADO de contas, não contas: projetá-los produziria um indicador
    -- projetado por premissa própria, divergindo das linhas que o compõem.
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
    -- Só dentro do documento de faturamento mensal: "Faturamento Janeiro" numa
    -- DRE não existe, e um rótulo com palavra de mês num balanço ("Provisão de
    -- férias — dezembro") é conta de verdade.
    when p_tipo_taxonomia = 'FATURAMENTO_24M' and fn_mes_do_rotulo(p_chave) is not null
      then 'serie_mensal'

    -- ---- SUBTOTAL: já é a soma de outras linhas -----------------------------
    -- (a) prefixo "total"/"subtotal"/"soma": cobre "TOTAL DO ATIVO", "TOTAL DO
    --     EXERCÍCIO 2025", "TOTAL — saldo devedor", "TOTAL".
    when (select t from n) ~ '^(total|totais|subtotal|soma) ' or (select t from n) in ('total','totais','subtotal')
      then 'subtotal'
    -- (b) o total do grupo SEM a palavra "total" (0034): "ATIVO", "Ativo
    --     Circulante", "PASSIVO E PATRIMÔNIO LÍQUIDO", "Patrimônio Líquido".
    when fn_rotulo_estrutural(p_chave, array['ativo'])
      or fn_rotulo_estrutural(p_chave, array['passivo'])
      or fn_rotulo_estrutural(p_chave, array['patrimonio'])
      or fn_rotulo_estrutural(p_chave, array['passivo','patrimonio'])
      or fn_rotulo_estrutural(p_chave, array['ativo','circulante'])
      or fn_rotulo_estrutural(p_chave, array['ativo','nao','circulante'])
      or fn_rotulo_estrutural(p_chave, array['passivo','circulante'])
      or fn_rotulo_estrutural(p_chave, array['passivo','nao','circulante'])
      or fn_rotulo_estrutural(p_chave, array['realizavel','longo','prazo'])
      then 'subtotal'
    -- (c) as linhas de RESULTADO da DRE e os subtotais do Fluxo, por conjunto
    --     fechado. São subtotais por definição contábil: "LUCRO BRUTO" é receita
    --     menos custo, e projetá-lo à parte o faria discordar das duas.
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
  'errar para conta deixa passar dupla contagem. Reaproveita fn_rotulo_estrutural (0034) para o '
  'total de grupo sem a palavra "total" — a mesma função que a reconciliação usa.';

-- A 0040 reemitida em cima do helper. UMA definição de "que mês é este rótulo",
-- usada pela curva e pelo papel da linha — duas cópias divergiriam, e a que
-- divergisse em silêncio seria a da curva.
create or replace function fn_sazonalidade_do_caso(p_caso_id uuid)
returns table (mes int, fracao numeric, n_observacoes bigint)
language sql
stable
as $$
  with mensal as (
    select fn_mes_do_rotulo(ce.chave) as mes, abs(ce.valor_num) as valor
    from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
    where d.caso_id = p_caso_id
      and d.tipo_taxonomia = 'FATURAMENTO_24M'
      and ce.valor_num is not null
      -- A linha de TOTAL não é um mês. Continua sendo o `fn_mes_do_rotulo` que a
      -- exclui (nenhuma palavra de mês em "TOTAL DO EXERCÍCIO"); este filtro é
      -- REDUNDANTE de propósito, para um rótulo como "Total jan-dez", e está
      -- anotado como redundante para ninguém escrever um teste acreditando estar
      -- provando ele — foi o que aconteceu na primeira versão do teste da 0040.
      and fn_normalizar_texto(ce.chave) not like 'total%'
      -- 0042: e a linha DERIVADA também não é um mês. "Média mensal" não casa
      -- palavra de mês, mas "Ticket médio por pedido 2024" tampouco deveria
      -- entrar numa curva de faturamento se algum dia casar.
      and fn_papel_linha(ce.chave, d.tipo_taxonomia, ce.unidade) <> 'derivado'
  ),
  somado as (
    select mes, sum(valor) as valor, count(*) as n
    from mensal where mes is not null
    group by mes
  ),
  total as (select sum(valor) as t from somado)
  select s.mes,
         case when t.t is null or t.t = 0 then null else s.valor / t.t end as fracao,
         s.n as n_observacoes
  from somado s cross join total t
  -- Só devolve curva COMPLETA: 12 meses ou nada. Curva parcial distribuiria o
  -- ano inteiro nos meses que existem, inflando cada um — pior que não ter curva.
  where (select count(*) from somado) = 12
  order by s.mes;
$$;


-- -----------------------------------------------------------------------------
-- fn_rotulo_contido — um rótulo DESCREVE o outro, mais grosso?
--
-- POR QUE ISTO PRECISOU EXISTIR. A primeira versão de `sobreposicao_suspeita`
-- marcava qualquer par com o MESMO valor na mesma seção, e contra o book isso
-- acusou dezenas de pares que não têm nada a ver um com o outro: "(-) Mão de obra
-- direta e encargos" e "Amortização de empréstimos" valem 21.400 os dois, e
-- "Banco Atlântico Sul — Antecipação de recebíveis" e "— Capital de giro" têm
-- 6.180.000 de saldo cada. Valor igual, em seção grande, é coincidência comum —
-- e guarda que acusa coincidência é a guarda que o analista aprende a ignorar
-- (foi o que aconteceu com o Sinal 1 no v24, e a 0022 teve de refiná-lo).
--
-- A SOBREPOSIÇÃO REAL tem forma: o rótulo curto é uma descrição MAIS GROSSA do
-- mesmo saldo — "Provisões" × "Provisão para passivo a descoberto de controlada",
-- "Arrendamentos" × "Arrendamentos a pagar - CPC 06 (R2)". Os dois casos do v35
-- compartilham a palavra que abre o rótulo; os falsos, não.
--
-- Compara por RADICAL de 5 letras porque plural e flexão mudam a palavra sem
-- mudar a conta ("provisoes" × "provisao"), e exige pelo menos uma palavra de 4+
-- letras para "de"/"e"/"a" não casarem tudo com tudo.
-- -----------------------------------------------------------------------------
create or replace function fn_rotulo_contido(p_curto text, p_longo text)
returns boolean
language sql
immutable
as $$
  with c as (
    select distinct left(w, 5) as r, length(w) as n
    from unnest(regexp_split_to_array(
      regexp_replace(fn_normalizar_texto(p_curto), '[^a-z0-9]+', ' ', 'g'), '\s+')) as w
    where w <> ''
  ),
  l as (
    select distinct left(w, 5) as r
    from unnest(regexp_split_to_array(
      regexp_replace(fn_normalizar_texto(p_longo), '[^a-z0-9]+', ' ', 'g'), '\s+')) as w
    where w <> ''
  )
  select exists (select 1 from c where c.n >= 4)
     and not exists (select 1 from c where c.r not in (select r from l));
$$;

comment on function fn_rotulo_contido(text, text) is
  'O primeiro rótulo é uma descrição mais grossa do segundo (radicais de 5 letras contidos, com ao '
  'menos uma palavra de 4+ letras)? Usado por sobreposicao_suspeita: valor igual sozinho acusa '
  'coincidência, e guarda que acusa coincidência é guarda que se aprende a ignorar.';

-- -----------------------------------------------------------------------------
-- fn_papel_prioridade — qual papel ganha quando as ocorrências discordam.
--
-- A linha lógica junta ocorrências de vários documentos, e elas podem ter papéis
-- diferentes (o mesmo rótulo impresso como total num documento e como conta em
-- outro). O empate resolve para o lado SEGURO, que é NÃO PROJETAR: subtotal
-- ganha de série mensal, que ganha de derivado, que ganha de conta.
--
-- É uma função, e não um `min()` sobre o texto, porque `min()` daria 'conta'
-- (ordem alfabética) — exatamente o lado errado — e a próxima pessoa a ler
-- `min(papel)` não teria como saber que a ordem alfabética estava sendo usada
-- como regra de negócio.
-- -----------------------------------------------------------------------------
create or replace function fn_papel_prioridade(p_papel text)
returns int
language sql
immutable
as $$
  select case p_papel
    when 'subtotal' then 0
    when 'serie_mensal' then 1
    when 'derivado' then 2
    else 3
  end;
$$;

-- -----------------------------------------------------------------------------
-- fn_linhas_para_modelagem — com PAPEL, SINAL e PROVENIÊNCIA.
--
-- O tipo de retorno muda, então precisa de drop (create or replace não altera a
-- assinatura de saída).
-- -----------------------------------------------------------------------------
drop function if exists fn_linhas_para_modelagem(uuid);

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
  with base as (
    select
      ce.secao_canonica,
      (array_agg(ce.chave order by length(ce.chave)))[1] as chave,
      fn_normalizar_texto(ce.chave) as rotulo_norm,
      max(coalesce(ce.entidade_coluna, e.razao_social)) as entidade,
      -- 0042: o valor da ocorrência de MAIOR MÓDULO, COM O SINAL. A 0039 usava
      -- `max(abs())` e `(-) Depreciação acumulada` aparecia como +52.300 na
      -- coluna que o analista lê para escolher a premissa.
      (array_agg(ce.valor_num order by abs(ce.valor_num) desc nulls last))[1] as valor_ultimo,
      count(*) as n_ocorrencias,
      -- Unidade e moeda são o que impede somar milhar com real: o mapa da dívida
      -- vem em `unidade` e o balanço em `milhar`, e no v35 as duas coisas
      -- apareceram lado a lado na tela sem nenhum aviso.
      max(ce.unidade) as unidade,
      max(ce.moeda) as moeda,
      array_agg(distinct d.tipo_taxonomia) as documentos,
      -- O papel vem da ocorrência de MAIOR PRIORIDADE (fn_papel_prioridade): no
      -- empate entre documentos, o lado seguro é não projetar.
      (array_agg(fn_papel_linha(ce.chave, d.tipo_taxonomia, ce.unidade)
                 order by fn_papel_prioridade(fn_papel_linha(ce.chave, d.tipo_taxonomia, ce.unidade))))[1] as papel
    from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
    left join entidade e on e.id = d.entidade_id
    where d.caso_id = p_caso_id
      and ce.valor_num is not null
    group by ce.secao_canonica, fn_normalizar_texto(ce.chave)
  )
  select b.secao_canonica, b.chave, b.rotulo_norm, b.entidade, b.valor_ultimo,
         b.n_ocorrencias, b.papel, b.unidade, b.moeda, b.documentos,
         -- SOBREPOSIÇÃO SUSPEITA: outra linha da MESMA seção, MESMO valor, e um
         -- rótulo descrevendo o outro de forma mais grossa (fn_rotulo_contido).
         -- É o caso real do v35 — `Provisões 12.399` (balanço sintético) e
         -- `Provisão para passivo a descoberto de controlada 12.399` (balancete
         -- analítico) são o MESMO dinheiro descrito em dois níveis, e projetar as
         -- duas dobra a conta. A função não escolhe por ninguém: MARCA, e quem
         -- decide é o analista, com a origem do documento na frente.
         exists (
           select 1 from base o
           where o.rotulo_norm <> b.rotulo_norm
             and coalesce(o.secao_canonica,'') = coalesce(b.secao_canonica,'')
             and o.valor_ultimo = b.valor_ultimo
             and b.papel = 'conta' and o.papel = 'conta'
             and (fn_rotulo_contido(o.chave, b.chave) or fn_rotulo_contido(b.chave, o.chave))
         ) as sobreposicao_suspeita
  from base b
  order by b.secao_canonica nulls last, b.rotulo_norm;
$$;

comment on function fn_linhas_para_modelagem(uuid) is
  'Linhas lógicas do caso para a tela de Modelagem, com PAPEL (conta/subtotal/derivado/'
  'serie_mensal), valor COM SINAL, unidade/moeda, documentos de origem e marca de sobreposição. '
  'Existe como função porque campo_extraido não tem caso_id — o escopo por caso mora aqui.';

grant execute on function fn_linhas_para_modelagem(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_papel_do_rotulo_no_caso — o papel da linha lógica, para as guardas.
--
-- Existe separada porque `fn_vincular_linha_premissa` recebe o RÓTULO, não a
-- linha inteira, e precisa saber o papel sem varrer a lista toda.
-- -----------------------------------------------------------------------------
create or replace function fn_papel_do_rotulo_no_caso(p_caso_id uuid, p_rotulo_norm text)
returns text
language sql
stable
as $$
  select (array_agg(fn_papel_linha(ce.chave, d.tipo_taxonomia, ce.unidade)
                    order by fn_papel_prioridade(fn_papel_linha(ce.chave, d.tipo_taxonomia, ce.unidade))))[1]
  from campo_extraido ce
  join documento_versao dv on dv.id = ce.documento_versao_id
  join documento d on d.id = dv.documento_id
  where d.caso_id = p_caso_id
    and ce.valor_num is not null
    and fn_normalizar_texto(ce.chave) = p_rotulo_norm;
$$;

grant execute on function fn_papel_do_rotulo_no_caso(uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_vincular_linha_premissa — a guarda de papel entra aqui, no banco.
--
-- Corpo da 0038 com UMA verificação nova. Recusa RETORNADA, como as demais.
-- -----------------------------------------------------------------------------
create or replace function fn_vincular_linha_premissa(
  p_caso_id uuid,
  p_secao_canonica text,
  p_rotulo text,
  p_entidade text,
  p_premissa text,
  p_autor text,
  p_sazonalidade text default null
)
returns jsonb
language plpgsql
as $$
declare
  v_rotulo_norm text := fn_normalizar_texto(p_rotulo);
  v_papel text;
begin
  -- 0042: papel primeiro. Vincular premissa a subtotal é o caminho da dupla
  -- contagem, e ela não parece erro no arquivo — parece um número maior.
  -- Desvincular (premissa null) é SEMPRE permitido: limpar configuração antiga
  -- não pode ser bloqueado pela regra nova.
  if p_premissa is not null then
    v_papel := fn_papel_do_rotulo_no_caso(p_caso_id, v_rotulo_norm);
    if v_papel is not null and v_papel <> 'conta' then
      return jsonb_build_object('recusado', true, 'papel', v_papel,
        'motivo_recusa', case v_papel
          when 'subtotal' then
            format('"%s" é um SUBTOTAL — já é a soma de outras linhas. No Excel ele sai como a '
                   'soma dos componentes projetados, então se move sozinho; projetá-lo por '
                   'premissa própria contaria o mesmo dinheiro duas vezes.', p_rotulo)
          when 'serie_mensal' then
            format('"%s" é uma linha da SÉRIE MENSAL de faturamento — ela alimenta a curva de '
                   'sazonalidade (que sai do próprio histórico do caso), não é uma conta a '
                   'projetar. Projetá-la contaria a receita de novo, mês a mês.', p_rotulo)
          else
            format('"%s" é um indicador DERIVADO (resultado de outras contas, não dinheiro). '
                   'Projetá-lo por premissa própria o faria divergir das linhas que o compõem.',
                   p_rotulo)
        end);
    end if;
  end if;

  if p_premissa is not null and not exists (
    select 1 from caso_premissa where caso_id = p_caso_id and premissa_codigo = p_premissa and ativo
  ) then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('A premissa "%s" não está ATIVA neste caso. Ative-a (com valores) '
                              'antes de vincular linha — senão a linha sairia "projetada" por uma '
                              'premissa vazia, o que é projetar com zero.', p_premissa));
  end if;
  if p_sazonalidade is not null and not exists (
    select 1 from caso_premissa where caso_id = p_caso_id and premissa_codigo = p_sazonalidade and ativo
  ) then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('A sazonalidade "%s" não está ativa neste caso.', p_sazonalidade));
  end if;

  insert into caso_linha_premissa (caso_id, secao_canonica, rotulo_norm, entidade,
                                   premissa_codigo, sazonalidade_codigo, atualizado_por, atualizado_em)
    values (p_caso_id, p_secao_canonica, v_rotulo_norm, p_entidade, p_premissa, p_sazonalidade, p_autor, now())
  on conflict (caso_id, rotulo_norm, coalesce(entidade, ''), coalesce(secao_canonica, '')) do update
    set premissa_codigo = excluded.premissa_codigo,
        sazonalidade_codigo = excluded.sazonalidade_codigo,
        atualizado_por = excluded.atualizado_por, atualizado_em = now();

  return jsonb_build_object('caso_id', p_caso_id, 'rotulo', v_rotulo_norm, 'premissa', p_premissa);
end;
$$;

grant execute on function fn_vincular_linha_premissa(uuid, text, text, text, text, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_aplicar_premissa_em_lote — o lote pega as CONTAS e DECLARA o que deixou.
--
-- A 0038 devolvia só `n_linhas`. Agora devolve também quantas ficaram de fora e
-- por qual papel: um lote que vincula 32 de 33 linhas sem dizer nada faria o
-- analista procurar a linha que faltou; um que diz "1 subtotal ficou de fora,
-- porque no Excel ele é a soma" ensina a regra na hora em que ela importa.
-- -----------------------------------------------------------------------------
create or replace function fn_aplicar_premissa_em_lote(
  p_caso_id uuid,
  p_secao_canonica text,
  p_premissa text,
  p_autor text,
  p_sazonalidade text default null
)
returns jsonb
language plpgsql
as $$
declare
  v_n int := 0;
  v_ignoradas jsonb := '[]'::jsonb;
  v_r jsonb;
  v_linha record;
begin
  if not exists (
    select 1 from caso_premissa where caso_id = p_caso_id and premissa_codigo = p_premissa and ativo
  ) then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('A premissa "%s" não está ativa neste caso.', p_premissa));
  end if;

  -- Percorre a linha LÓGICA (a mesma que a tela lista), não a ocorrência: era
  -- `select distinct ce.secao_canonica, ce.chave` e isso vinculava duas vezes o
  -- mesmo rótulo escrito com grafias diferentes.
  for v_linha in
    select l.secao_canonica, l.chave, l.entidade, l.papel
    from fn_linhas_para_modelagem(p_caso_id) l
    where coalesce(l.secao_canonica, '') = coalesce(p_secao_canonica, '')
  loop
    if v_linha.papel <> 'conta' then
      v_ignoradas := v_ignoradas || jsonb_build_object('linha', v_linha.chave, 'papel', v_linha.papel);
      continue;
    end if;
    v_r := fn_vincular_linha_premissa(p_caso_id, v_linha.secao_canonica, v_linha.chave,
                                      v_linha.entidade, p_premissa, p_autor, p_sazonalidade);
    if coalesce((v_r->>'recusado')::boolean, false) then
      return v_r;  -- recusa de premissa/sazonalidade: valeria para todas
    end if;
    v_n := v_n + 1;
  end loop;

  insert into decisao (caso_id, tipo, autor, motivo, payload)
    values (p_caso_id, 'override', p_autor,
            format('Premissa "%s" aplicada em lote a %s linha(s) da seção "%s" (%s fora por papel)',
                   p_premissa, v_n, coalesce(p_secao_canonica, '(sem seção)'),
                   jsonb_array_length(v_ignoradas)),
            jsonb_build_object('premissa', p_premissa, 'secao_canonica', p_secao_canonica,
                               'n_linhas', v_n, 'sazonalidade', p_sazonalidade,
                               'ignoradas', v_ignoradas));

  return jsonb_build_object('caso_id', p_caso_id, 'secao_canonica', p_secao_canonica,
                            'premissa', p_premissa, 'n_linhas', v_n,
                            'n_ignoradas', jsonb_array_length(v_ignoradas),
                            'ignoradas', v_ignoradas);
end;
$$;

grant execute on function fn_aplicar_premissa_em_lote(uuid, text, text, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_premissa_valores_sugeridos — a macro chega PREENCHIDA, do Focus.
--
-- No v35 as 5 premissas macro nasceram ativas e VAZIAS, e premissa ativa sem
-- valor bloqueia o export completo (`fn_conferir_modelagem`). O banco já tem a
-- expectativa do Focus versionada (`indice_macro_expectativa`, seed da 0025/0028)
-- e os códigos do catálogo são os MESMOS da série (IPCA, SELIC, IGPM, PIB,
-- CAMBIO_USD) — então pedir para alguém digitar à mão um número que o banco
-- afirma é pedir para errar de digitação.
--
-- ANO QUE O FOCUS NÃO COBRE FICA DE FORA. Ausência é ausência: preencher com a
-- última mediana conhecida projetaria uma expectativa que ninguém publicou.
-- -----------------------------------------------------------------------------
create or replace function fn_premissa_valores_sugeridos(
  p_codigo text,
  p_ano_inicial int,
  p_anos int default 5
)
returns jsonb
language sql
stable
as $$
  select coalesce(jsonb_object_agg(x.ano::text, x.mediana), '{}'::jsonb)
  from (
    -- Uma mediana por ano: a coleta MAIS RECENTE. `indice_macro_expectativa` é
    -- append-only por (serie, ano_ref, coletado_em) — o seed tem IPCA/2026 em
    -- duas coletas, e sem o distinct on a mais velha poderia ganhar.
    select distinct on (e.ano_ref) e.ano_ref as ano, e.mediana
    from indice_macro_expectativa e
    where e.serie = p_codigo
      and e.ano_ref between p_ano_inicial and p_ano_inicial + p_anos - 1
    order by e.ano_ref, e.coletado_em desc
  ) x;
$$;

comment on function fn_premissa_valores_sugeridos(text, int, int) is
  'Valores por ano que o Focus afirma para uma premissa macro (mediana da coleta mais recente de '
  'cada ano). Ano sem expectativa publicada fica FORA — ausência é ausência.';

grant execute on function fn_premissa_valores_sugeridos(text, int, int) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_ativar_premissa — macro sem valor passa a nascer com o valor do Focus.
--
-- Corpo da 0038 com o preenchimento no meio. Só age quando a premissa é macro E
-- o chamador não mandou valor: valor digitado pelo analista SEMPRE ganha do
-- Focus — ele pode estar usando cenário próprio, e sobrescrever a escolha
-- humana com um default do sistema é o oposto da doutrina deste projeto.
-- -----------------------------------------------------------------------------
create or replace function fn_ativar_premissa(
  p_caso_id uuid,
  p_codigo  text,
  p_valores jsonb,
  p_origem  text,
  p_autor   text
)
returns jsonb
language plpgsql
as $$
declare
  v_nome     text;
  v_natureza text;
  v_valores  jsonb := coalesce(p_valores, '{}'::jsonb);
  v_origem   text := p_origem;
  v_ano      int;
  v_anos     int;
begin
  select nome, natureza::text into v_nome, v_natureza
  from premissa_catalogo where codigo = p_codigo and ativo;
  if v_nome is null then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values (p_autor, 'premissa_recusada', 'caso:'||p_caso_id,
              jsonb_build_object('codigo', p_codigo, 'porque', 'codigo inexistente ou inativo no catalogo'));
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('A premissa "%s" não existe no catálogo (ou está inativa). '
                              'Premissa nova entra por semente no catálogo, não por caso.', p_codigo));
  end if;

  if v_natureza = 'macro' and v_valores = '{}'::jsonb then
    select coalesce(ultimo_exercicio_real, extract(year from now())::int) + 1,
           coalesce(anos_projetados, 5)
      into v_ano, v_anos
    from caso_modelagem where caso_id = p_caso_id;
    -- Sem parâmetros do caso ainda: usa o ano corrente + 1 e 5 anos. A tela pede
    -- os parâmetros no passo 1, mas o analista pode ativar a premissa antes, e
    -- devolver vazio aqui só empurraria o trabalho para ele.
    v_ano := coalesce(v_ano, extract(year from now())::int + 1);
    v_anos := coalesce(v_anos, 5);
    v_valores := fn_premissa_valores_sugeridos(p_codigo, v_ano, v_anos);
    if v_valores <> '{}'::jsonb then
      v_origem := 'focus';
    end if;
  end if;

  insert into caso_premissa (caso_id, premissa_codigo, valores, origem, ativo, atualizado_por, atualizado_em)
    values (p_caso_id, p_codigo, v_valores, v_origem, true, p_autor, now())
  on conflict (caso_id, premissa_codigo) do update
    set valores = excluded.valores, origem = excluded.origem, ativo = true,
        atualizado_por = excluded.atualizado_por, atualizado_em = now();

  insert into decisao (caso_id, tipo, autor, motivo, payload)
    values (p_caso_id, 'override', p_autor,
            format('Premissa "%s" ativada/ajustada na modelagem%s', v_nome,
                   case when v_origem = 'focus' then ' (valores do Focus)' else '' end),
            jsonb_build_object('premissa', p_codigo, 'valores', v_valores, 'origem', v_origem));

  return jsonb_build_object('caso_id', p_caso_id, 'premissa', p_codigo, 'ativo', true,
                            'valores', v_valores, 'origem', v_origem);
end;
$$;

grant execute on function fn_ativar_premissa(uuid, text, jsonb, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_conferir_modelagem — o denominador passa a ser o que é PROJETÁVEL.
--
-- No v35 a tela dizia "0 de 236 linhas com premissa". O alvo real é bem menor —
-- subtotal, série mensal e indicador nunca vão receber premissa —, e um
-- denominador que inclui o que não é para configurar transforma a conferência
-- num número que nunca fecha. Número que nunca fecha é número que se ignora.
-- -----------------------------------------------------------------------------
create or replace function fn_conferir_modelagem(p_caso_id uuid)
returns jsonb
language plpgsql
stable
as $$
declare
  v_linhas_total int;
  v_linhas_com   int;
  v_nao_projetaveis jsonb;
  v_premissas    int;
  v_sem_valor    text[];
  v_orfaos       text[];
  v_param        jsonb;
begin
  select count(*) into v_linhas_total
  from fn_linhas_para_modelagem(p_caso_id) l where l.papel = 'conta';

  -- E o que NÃO é projetável fica NOMEADO por papel, em vez de desaparecer da
  -- conta: quem olha precisa saber que 236 viraram N porque o resto é subtotal,
  -- série mensal e indicador — não porque alguma linha se perdeu.
  select jsonb_object_agg(papel, n) into v_nao_projetaveis
  from (select l.papel, count(*) as n from fn_linhas_para_modelagem(p_caso_id) l
        where l.papel <> 'conta' group by l.papel) x;

  -- CONTA POR JOIN, não por contagem de vínculos (a primeira versão dava
  -- `linhas_com_premissa: 4` sobre `linhas_do_caso: 3`), e só sobre linha
  -- PROJETÁVEL — vínculo antigo apontando para subtotal não pode inflar a
  -- cobertura.
  select count(distinct l.rotulo_norm) into v_linhas_com
  from caso_linha_premissa l
  where l.caso_id = p_caso_id and l.premissa_codigo is not null
    and exists (
      select 1 from fn_linhas_para_modelagem(p_caso_id) m
      where m.rotulo_norm = l.rotulo_norm and m.papel = 'conta'
    );

  select array_agg(distinct l.rotulo_norm order by l.rotulo_norm) into v_orfaos
  from caso_linha_premissa l
  where l.caso_id = p_caso_id and l.premissa_codigo is not null
    and not exists (
      select 1 from fn_linhas_para_modelagem(p_caso_id) m
      where m.rotulo_norm = l.rotulo_norm
    );

  select count(*) into v_premissas from caso_premissa where caso_id = p_caso_id and ativo;

  select array_agg(premissa_codigo order by premissa_codigo) into v_sem_valor
  from caso_premissa
  where caso_id = p_caso_id and ativo and (valores is null or valores = '{}'::jsonb);

  select to_jsonb(m) into v_param from caso_modelagem m where m.caso_id = p_caso_id;

  return jsonb_build_object(
    'parametros', v_param,
    'premissas_ativas', v_premissas,
    'premissas_sem_valor', to_jsonb(coalesce(v_sem_valor, array[]::text[])),
    'linhas_do_caso', v_linhas_total,
    'linhas_nao_projetaveis', coalesce(v_nao_projetaveis, '{}'::jsonb),
    'linhas_com_premissa', v_linhas_com,
    'linhas_sem_premissa', greatest(v_linhas_total - v_linhas_com, 0),
    'vinculos_orfaos', to_jsonb(coalesce(v_orfaos, array[]::text[])),
    'pronto', v_param is not null and v_premissas > 0 and coalesce(array_length(v_sem_valor, 1), 0) = 0
  );
end;
$$;

grant execute on function fn_conferir_modelagem(uuid) to authenticated;

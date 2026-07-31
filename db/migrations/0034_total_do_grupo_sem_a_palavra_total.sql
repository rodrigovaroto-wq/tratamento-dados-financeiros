-- =============================================================================
-- 0034 — O total do grupo raramente se chama "total", e a A.1 exigia a palavra
--
-- CAUSA RAIZ, achada no teste v35 pela mensagem que a 0033 passou a escrever.
-- Ela dizia, literalmente, na pendência:
--
--   "2024: falta o Passivo+PL (coluna de entidade: (qualquer); coluna de
--    período: 31/12/2024). Rótulos que a extração TROUXE e que poderiam ser um
--    total: "ATIVO", "Ativo Circulante", "Ativo Não Circulante", "Créditos
--    tributários - ICMS sobre ativo permanente", "Passivo Circulante",
--    "PASSIVO E PATRIMÔNIO LÍQUIDO" …"
--
-- Está tudo ali. O documento traz o total do grupo com o rótulo **"PASSIVO E
-- PATRIMÔNIO LÍQUIDO"** — sem a palavra "total". E `fn_valor_conceito_col` era
-- chamada com `array['passivo','patrimonio','total']`, que exige os TRÊS
-- tokens. O rótulo certo estava na base, extraído, com valor, e a busca não o
-- via. Idem no lado esquerdo: o rótulo é **"ATIVO"**, e a busca pedia
-- `['ativo','total']`.
--
-- Isto NÃO é exotismo de um documento: é a convenção da maioria dos balanços
-- brasileiros — o grupo abre com o nome em caixa alta carregando o total, e a
-- linha "TOTAL DO ..." no rodapé é opcional. O classificador em TypeScript já
-- sabia disso desde sempre (`ancoraBalanco`, regra `soEstrutural`: um rótulo
-- feito só de palavras estruturais É a âncora do grupo). Quem não sabia era o
-- SQL. As duas metades do sistema discordavam, e a metade que decide se a
-- reconciliação roda era a que estava errada.
--
-- SEGUNDA CAUSA, no fallback que deveria ter salvado o caso. Sem linha de
-- total, a A.1 somava as seções com
-- `fn_soma_secao(v_versao, array['passivo','patrimonio'], …)`. Só que
-- `fn_soma_secao` exige que a seção contenha TODOS os termos (é
-- `not exists (termo where secao not like termo)`), e não existe seção chamada
-- "passivo patrimônio": existem "Passivo Circulante", "Passivo Não Circulante"
-- e "Patrimônio Líquido". O fallback era, na prática, INALCANÇÁVEL — nunca
-- somou nada desde que foi escrito. O lado do Ativo funcionava por acaso, com
-- um único termo (`array['ativo']`).
--
-- EFEITO MEDIDO: no v35, 2 das 3 reconciliações de balanço saíram como
-- `precondicao_nao_satisfeita`; no v33 tinham sido 5. Nenhum balanço do lote foi
-- conferido contra a identidade Ativo = Passivo + PL — a checagem contábil mais
-- básica que existe, e a razão de ser da Classe A.
--
-- O QUE MUDA
--   1. `fn_rotulo_estrutural` — um rótulo é o total do grupo quando, retiradas
--      as palavras de ligação e a própria palavra "total", sobram EXATAMENTE as
--      palavras estruturais do grupo. É a tradução fiel do `soEstrutural` do
--      TypeScript, e é o que distingue "ATIVO" (é o total) de "Ativo
--      Circulante" (é uma seção) e de "Créditos tributários - ICMS sobre ativo
--      permanente" (não é nem uma coisa nem outra).
--   2. A.1 tenta, nesta ordem: (a) a linha com "total" no rótulo, como antes;
--      (b) a linha ESTRUTURAL do grupo; (c) a soma das seções — agora com o
--      lado direito somando `passivo` e `patrimonio` SEPARADAMENTE e juntando,
--      que é o que o fallback sempre quis dizer.
--
-- POR QUE A ORDEM IMPORTA E NÃO FOI INVERTIDA: quando as duas linhas existem,
-- "TOTAL DO PASSIVO E DO PATRIMÔNIO LÍQUIDO" é o rodapé conferido do documento
-- e "PASSIVO E PATRIMÔNIO LÍQUIDO" é o cabeçalho do grupo. Elas devem ser
-- iguais, mas se divergirem é o rodapé que vale. Manter (a) antes de (b)
-- preserva isso.
--
-- NADA FOI AFROUXADO NO CAMINHO (a). A busca com "total" continua idêntica; o
-- que entrou é um caminho NOVO e mais estrito que ela — `fn_rotulo_estrutural`
-- casa um conjunto FECHADO de rótulos, não um `like`. Um rótulo como "ICMS
-- sobre ativo permanente", que um `like '%ativo%'` pegaria, é recusado.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- fn_rotulo_estrutural — o rótulo é, ele mesmo, o total de um grupo?
--
-- Regra: normaliza, quebra em palavras, joga fora ligação e ruído de rodapé
-- ("total", "geral", "soma", artigos, preposições, pontuação) e compara o que
-- sobra com o conjunto exigido. Comparação por CONJUNTO, não por substring:
-- é isso que faz "Ativo Circulante" ser recusado enquanto "Total do Ativo" e
-- "ATIVO" são aceitos.
--
-- `p_tokens_exigidos` são as palavras que TÊM de sobrar. Sobrar qualquer outra
-- coisa reprova — é a diferença entre um total e uma conta que menciona a
-- palavra.
-- -----------------------------------------------------------------------------
create or replace function fn_rotulo_estrutural(p_chave text, p_tokens_exigidos text[])
returns boolean
language sql
immutable
as $$
  with palavras as (
    select unnest(
      regexp_split_to_array(
        -- pontuação e conectivos viram espaço ANTES do split: "TOTAL DO ATIVO
        -- (CIRCULANTE + NÃO CIRCULANTE)" não pode virar o token "(circulante".
        regexp_replace(fn_normalizar_texto(p_chave), '[^a-z0-9]+', ' ', 'g'),
        '\s+')
    ) as w
  ),
  uteis as (
    select distinct w from palavras
    where w <> ''
      -- Ruído de rodapé e ligação. "liquido" entra aqui porque "PATRIMÔNIO
      -- LÍQUIDO" e "PATRIMÔNIO" são o mesmo grupo, e exigir a palavra faria o
      -- segundo rótulo ser recusado sem motivo contábil nenhum.
      and w not in ('total','totais','geral','gerais','soma','somatorio','subtotal',
                    'de','do','da','dos','das','e','o','a','os','as','em','no','na',
                    'liquido','liquida','consolidado','consolidada','combinado','combinada')
  )
  select coalesce(
    (select array_agg(w order by w) from uteis) =
    (select array_agg(t order by t) from (select distinct unnest(p_tokens_exigidos) as t) x),
    false);
$$;

comment on function fn_rotulo_estrutural(text, text[]) is
  'Um rótulo É o total de um grupo quando, tiradas ligação e a palavra "total", '
  'sobram exatamente as palavras estruturais do grupo. Tradução do `soEstrutural` '
  'do classificador TypeScript, que o SQL não tinha (0034).';

-- -----------------------------------------------------------------------------
-- fn_valor_estrutural_col — a linha cujo RÓTULO é o total do grupo, na coluna.
-- Mesma semântica de coluna do `fn_valor_conceito_col`, inclusive o sentinela
-- E'\x01' ("a coluna era exigida e não existe" ⇒ nenhum resultado).
-- -----------------------------------------------------------------------------
create or replace function fn_valor_estrutural_col(
  p_documento_versao_id uuid,
  p_tokens text[],
  p_entidade_coluna text default null,
  p_periodo_coluna text default null
)
returns campo_extraido
language sql
stable
as $$
  select ce.*
  from campo_extraido ce
  where ce.documento_versao_id = p_documento_versao_id
    and ce.valor_num is not null
    and p_entidade_coluna is distinct from E'\x01'
    and p_periodo_coluna is distinct from E'\x01'
    and (p_entidade_coluna is null
         or fn_normalizar_texto(ce.entidade_coluna) = fn_normalizar_texto(p_entidade_coluna))
    and (p_periodo_coluna is null
         or fn_normalizar_texto(ce.periodo_coluna) = fn_normalizar_texto(p_periodo_coluna))
    and fn_rotulo_estrutural(ce.chave, p_tokens)
  -- Se houver mais de um (o cabeçalho do grupo E o rodapé "TOTAL DO ..."), o
  -- de MAIOR rótulo vem primeiro: é o rodapé, a linha conferida do documento.
  order by coalesce(ce.confianca, 0) desc, length(ce.chave) desc
  limit 1;
$$;

grant execute on function fn_rotulo_estrutural(text, text[]) to authenticated;
grant execute on function fn_valor_estrutural_col(uuid, text[], text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- A.1 — Ativo Total = Passivo + PL. Corpo da 0033 com os dois caminhos novos.
-- -----------------------------------------------------------------------------
create or replace function fn_reconciliar_ativo_passivo_pl(
  p_caso_id       uuid,
  p_entidade_id   uuid,
  p_periodo_id    uuid,
  p_tolerancia_abs numeric default 100,
  p_tolerancia_pct numeric default 0.005
)
returns jsonb
language plpgsql
as $$
declare
  v_doc_id     uuid;
  v_versao     uuid;
  v_col_ent    text;
  v_ano        int;
  v_col_per    text;
  v_ativo      campo_extraido;
  v_passivo_pl campo_extraido;
  v_passivo    campo_extraido;
  v_pl         campo_extraido;
  v_esq        numeric;
  v_dir        numeric;
  v_soma       record;
  v_soma_pl    record;
  v_div_abs    numeric;
  v_tol        numeric;
  v_pior_abs   numeric := null;
  v_pior_pct   numeric := null;
  v_resultado  text := 'ok';
  v_partes     text[] := '{}';
  v_n_anos     int := 0;
  v_fonte_a    jsonb;
  v_fonte_b    jsonb;
  v_desc       text;
  v_orig_esq   text;
  v_orig_dir   text;
  v_faltas     text[] := '{}';
begin
  v_doc_id := fn_documento_balanco(p_caso_id, p_entidade_id, p_periodo_id);

  if v_doc_id is null then
    return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
      'ativo_passivo_pl', 'A', null, null, null, 'documento_ausente', null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      'Nenhum Balanço Patrimonial, Combinado ou Balancete classificado para esta '
      || 'entidade/período — nada a reconciliar (a cobrança do documento é do checklist).');
  end if;

  v_versao  := fn_versao_atual(v_doc_id);
  v_col_ent := fn_coluna_entidade(v_versao, p_entidade_id);

  foreach v_ano in array fn_anos_alvo(p_periodo_id) loop
    v_col_per := case when v_ano is null then null
                      else fn_coluna_periodo_do_ano(v_versao, v_ano) end;
    v_orig_esq := null;
    v_orig_dir := null;
    v_esq := null;
    v_dir := null;

    -- ---- lado esquerdo: ATIVO ------------------------------------------------
    -- (a) a linha que diz "total" no rótulo.
    select * into v_ativo from fn_valor_conceito_col(v_versao,
      array['ativo', 'total'], array['circulante', 'nao circulante'], v_col_ent, v_col_per);
    if v_ativo.id is not null then
      v_esq := v_ativo.valor_num;
      v_orig_esq := format('linha "%s"', v_ativo.chave);
    else
      -- (b) 0034: o rótulo ESTRUTURAL — "ATIVO", que é como a maioria dos
      -- balanços brasileiros imprime o total do grupo.
      select * into v_ativo from fn_valor_estrutural_col(v_versao,
        array['ativo'], v_col_ent, v_col_per);
      if v_ativo.id is not null then
        v_esq := v_ativo.valor_num;
        v_orig_esq := format('linha "%s" (total do grupo, sem a palavra "total")', v_ativo.chave);
      else
        -- (c) soma das contas da seção.
        select * into v_soma from fn_soma_secao(v_versao, array['ativo'], v_col_ent, v_col_per,
          array['passivo', 'patrimonio'], array['total do ativo']);
        v_esq := case when coalesce(v_soma.n_linhas, 0) > 0 then v_soma.soma end;
        v_orig_esq := case when v_esq is null then null
          else format('soma da seção ATIVO (%s linhas, sem linha de total impressa)', v_soma.n_linhas) end;
      end if;
    end if;

    -- ---- lado direito: PASSIVO + PL -----------------------------------------
    select * into v_passivo_pl from fn_valor_conceito_col(v_versao,
      array['passivo', 'patrimonio', 'total'], array['circulante'], v_col_ent, v_col_per);
    if v_passivo_pl.id is not null then
      v_dir := v_passivo_pl.valor_num;
      v_orig_dir := format('linha "%s"', v_passivo_pl.chave);
    else
      -- 0034: "PASSIVO E PATRIMÔNIO LÍQUIDO" — o rótulo do v35, que a busca com
      -- "total" não via.
      select * into v_passivo_pl from fn_valor_estrutural_col(v_versao,
        array['passivo', 'patrimonio'], v_col_ent, v_col_per);
      if v_passivo_pl.id is not null then
        v_dir := v_passivo_pl.valor_num;
        v_orig_dir := format('linha "%s" (total do grupo, sem a palavra "total")', v_passivo_pl.chave);
      else
        select * into v_passivo from fn_valor_conceito_col(v_versao,
          array['passivo', 'total'], array['patrimonio', 'circulante', 'nao circulante'],
          v_col_ent, v_col_per);
        select * into v_pl from fn_valor_conceito_col(v_versao,
          array['patrimonio', 'liquido', 'total'], array['circulante'], v_col_ent, v_col_per);
        if v_passivo.id is null then
          select * into v_passivo from fn_valor_estrutural_col(v_versao,
            array['passivo'], v_col_ent, v_col_per);
        end if;
        if v_pl.id is null then
          select * into v_pl from fn_valor_estrutural_col(v_versao,
            array['patrimonio'], v_col_ent, v_col_per);
        end if;
        if v_passivo.id is not null and v_pl.id is not null then
          v_dir := v_passivo.valor_num + v_pl.valor_num;
          v_orig_dir := format('linhas "%s" + "%s"', v_passivo.chave, v_pl.chave);
        else
          -- 0034: o fallback de soma, agora ALCANÇÁVEL. Era
          -- `fn_soma_secao(array['passivo','patrimonio'])`, que exige a seção
          -- conter os DOIS termos — e não existe seção "passivo patrimônio".
          -- As seções reais são "Passivo Circulante", "Passivo Não Circulante"
          -- e "Patrimônio Líquido", então são DUAS somas que se juntam.
          select * into v_soma from fn_soma_secao(v_versao, array['passivo'],
            v_col_ent, v_col_per, array['patrimonio'],
            array['total do passivo', 'passivo e patrimonio']);
          select * into v_soma_pl from fn_soma_secao(v_versao, array['patrimonio'],
            v_col_ent, v_col_per, '{}',
            array['total do passivo', 'passivo e patrimonio']);
          if coalesce(v_soma.n_linhas, 0) + coalesce(v_soma_pl.n_linhas, 0) > 0 then
            v_dir := coalesce(v_soma.soma, 0) + coalesce(v_soma_pl.soma, 0);
            v_orig_dir := format('soma das seções PASSIVO (%s linhas) + PL (%s linhas), sem linha de total impressa',
                                 coalesce(v_soma.n_linhas, 0), coalesce(v_soma_pl.n_linhas, 0));
          end if;
        end if;
      end if;
    end if;

    if v_esq is null or v_dir is null then
      v_faltas := v_faltas || format('%s: falta %s%s',
        coalesce(v_ano::text, 'período do documento'),
        case
          when v_esq is null and v_dir is null then 'o Ativo Total E o Passivo+PL'
          when v_esq is null then 'o Ativo Total'
          else 'o Passivo+PL'
        end,
        case
          when v_col_per is null and v_col_ent is null then ''
          else format(' (coluna de entidade: %s; coluna de período: %s)',
                      coalesce(nullif(v_col_ent, E'\x01'), '(qualquer)'),
                      coalesce(nullif(v_col_per, E'\x01'), '(qualquer)'))
        end);
      continue;
    end if;

    v_n_anos := v_n_anos + 1;
    v_div_abs := abs(v_esq - v_dir);
    v_tol := greatest(p_tolerancia_abs, abs(v_esq) * p_tolerancia_pct);
    if v_div_abs > v_tol then
      v_resultado := 'divergente';
      v_partes := v_partes || format('%s: Ativo %s [%s] vs Passivo+PL %s [%s] (diferença de %s)',
        coalesce(v_ano::text, 'período do documento'), v_esq, v_orig_esq, v_dir, v_orig_dir, v_div_abs);
      if v_pior_abs is null or v_div_abs > v_pior_abs then
        v_pior_abs := v_div_abs;
        v_pior_pct := case when v_esq <> 0 then v_div_abs / abs(v_esq) end;
      end if;
    else
      v_partes := v_partes || format('%s: confere (Ativo %s [%s] = Passivo+PL %s [%s])',
        coalesce(v_ano::text, 'período do documento'), v_esq, v_orig_esq, v_dir, v_orig_dir);
    end if;
    v_fonte_a := jsonb_build_object('chave', coalesce(v_ativo.chave, 'soma da seção ATIVO'),
      'valor', v_esq, 'ano', v_ano, 'origem', v_orig_esq, 'documento_versao_id', v_versao);
    v_fonte_b := jsonb_build_object('valor', v_dir, 'ano', v_ano, 'origem', v_orig_dir,
      'documento_versao_id', v_versao);
  end loop;

  if v_n_anos = 0 then
    return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
      'ativo_passivo_pl', 'A', v_doc_id, null, null, 'precondicao_nao_satisfeita', null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      'O Balanço foi encontrado, mas nenhum exercício teve os DOIS lados. '
      || case when array_length(v_faltas, 1) is null then ''
              else array_to_string(v_faltas, '; ') || '. ' end
      || 'Rótulos que a extração TROUXE e que poderiam ser um total: '
      || fn_rotulos_candidatos(v_versao)
      || '. Se o rótulo certo está nessa lista, o defeito é o padrão de casamento; '
      || 'se não está, a extração não trouxe a linha e o caminho é reextrair.');
  end if;

  v_desc := format('Ativo Total vs Passivo+Patrimônio Líquido em %s ano(s): %s.',
                   v_n_anos, array_to_string(v_partes, '; '));
  if array_length(v_faltas, 1) is not null then
    v_desc := v_desc || format(' Exercícios NÃO checados: %s.', array_to_string(v_faltas, '; '));
  end if;

  return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
    'ativo_passivo_pl', 'A', v_doc_id, v_fonte_a, v_fonte_b, v_resultado,
    v_pior_abs, v_pior_pct,
    jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct,
                       'anos_checados', v_n_anos,
                       'anos_nao_checados', coalesce(array_length(v_faltas, 1), 0)),
    v_desc);
end;
$$;

-- =============================================================================
-- VERIFICAÇÃO EMBUTIDA — a migration prova, no banco em que roda, o que afirma.
-- Se `fn_rotulo_estrutural` voltar a aceitar demais ou de menos, a migration se
-- recusa a aplicar. Os rótulos abaixo são os REAIS do teste v35.
-- =============================================================================
do $$
begin
  -- Aceita o total do grupo nas duas formas que um balanço imprime.
  if not fn_rotulo_estrutural('ATIVO', array['ativo']) then
    raise exception '0034: "ATIVO" deveria ser o total do grupo Ativo';
  end if;
  if not fn_rotulo_estrutural('TOTAL DO ATIVO', array['ativo']) then
    raise exception '0034: "TOTAL DO ATIVO" deveria ser o total do grupo Ativo';
  end if;
  if not fn_rotulo_estrutural('PASSIVO E PATRIMÔNIO LÍQUIDO', array['passivo','patrimonio']) then
    raise exception '0034: "PASSIVO E PATRIMÔNIO LÍQUIDO" deveria ser o total do grupo Passivo+PL';
  end if;
  if not fn_rotulo_estrutural('TOTAL DO PASSIVO E DO PATRIMÔNIO LÍQUIDO', array['passivo','patrimonio']) then
    raise exception '0034: o rodapé "TOTAL DO PASSIVO E DO PATRIMÔNIO LÍQUIDO" deveria ser aceito';
  end if;
  -- E RECUSA o que só menciona a palavra — é aqui que um `like '%ativo%'`
  -- erraria, e é a razão de a regra ser por CONJUNTO e não por substring.
  if fn_rotulo_estrutural('Ativo Circulante', array['ativo']) then
    raise exception '0034: "Ativo Circulante" é uma SEÇÃO, não o total do grupo';
  end if;
  if fn_rotulo_estrutural('Ativo Não Circulante', array['ativo']) then
    raise exception '0034: "Ativo Não Circulante" é uma SEÇÃO, não o total do grupo';
  end if;
  if fn_rotulo_estrutural('Créditos tributários - ICMS sobre ativo permanente', array['ativo']) then
    raise exception '0034: uma conta que MENCIONA "ativo" não é o total do grupo';
  end if;
  if fn_rotulo_estrutural('Passivo Circulante', array['passivo','patrimonio']) then
    raise exception '0034: "Passivo Circulante" não é o total do grupo Passivo+PL';
  end if;
  if fn_rotulo_estrutural('Patrimônio Líquido', array['passivo','patrimonio']) then
    raise exception '0034: só o PL não é o total do grupo Passivo+PL';
  end if;
  -- …mas só o PL É o total do grupo PL, que é o que o fallback de duas somas usa.
  if not fn_rotulo_estrutural('Patrimônio Líquido', array['patrimonio']) then
    raise exception '0034: "Patrimônio Líquido" deveria ser o total do grupo PL';
  end if;
  raise notice '0034 ok: o total do grupo é reconhecido sem a palavra "total", e uma conta que só menciona a palavra continua recusada';
end $$;

-- =============================================================================
-- SEGUNDA CORREÇÃO DESTA MIGRATION — a guarda anti-alucinação acusava o balanço
-- MAIS CORRETO possível.
--
-- O DEFEITO, medido no v35. A fila de revisão trouxe, duas vezes:
--
--   "4 contas diferentes, na MESMA coluna, vieram com o MESMO valor material
--    (14529.00) — padrão típico de fabricação/alucinação, não de dado real."
--
-- As quatro contas eram: "ATIVO", "TOTAL DO ATIVO", "PASSIVO E PATRIMÔNIO
-- LÍQUIDO" e "TOTAL DO PASSIVO E DO PATRIMÔNIO LÍQUIDO". Elas têm o mesmo valor
-- **porque o balanço fecha** — é a identidade contábil, não coincidência e
-- muito menos alucinação. A guarda dispara exatamente quando a extração
-- acertou tudo, inclusive as quatro linhas de total, e o alerta é 100% falso.
--
-- POR QUE ISSO É CARO. O comentário da própria guarda (0022) diz: "o teste v24
-- gerou 5 alertas falsos, que é o pior resultado possível numa guarda (o
-- analista aprende a ignorar o aviso)". A 0022 corrigiu contando por COLUNA em
-- vez de por lote. Sobrou o caso em que as repetições são estruturais dentro da
-- MESMA coluna — e ele não é raro: acontece em todo balanço bem extraído.
--
-- A CORREÇÃO. As linhas que são TOTAL DE GRUPO deixam de contar como "contas
-- diferentes com o mesmo valor" — elas não são contas, são a mesma grandeza
-- escrita de novo. Usa o `fn_rotulo_estrutural` desta migration, então a regra
-- é a mesma que a reconciliação usa, e não um segundo vocabulário para manter
-- em sincronia. O limiar de 4 não muda: o que muda é o que entra na contagem.
--
-- O QUE NÃO MUDA: quatro CONTAS de verdade com o mesmo valor material seguem
-- disparando. A guarda continua existindo para o que ela foi feita — o modelo
-- que preenche uma coluna inteira com o mesmo número.
-- =============================================================================
create or replace function fn_contas_repetindo_valor(p_documento_versao_id uuid)
returns table (valor numeric, n_contas int)
language sql
stable
as $$
  select ce.valor_num, count(distinct ce.chave)::int
  from campo_extraido ce
  where ce.documento_versao_id = p_documento_versao_id
    and ce.valor_num is not null
    and ce.valor_num <> 0
    -- MATERIAL: 1% do maior valor da versão. Valores pequenos (18, 40, 180)
    -- coincidem à toa e geraram os falsos da v24.
    and abs(ce.valor_num) >= (
      select greatest(coalesce(max(abs(c2.valor_num)), 0) * 0.01, 1)
      from campo_extraido c2 where c2.documento_versao_id = p_documento_versao_id
    )
    -- …e NÃO são totais de grupo. Ativo = Passivo + PL faz essas quatro linhas
    -- terem o mesmo valor por construção contábil.
    and not fn_rotulo_estrutural(ce.chave, array['ativo'])
    and not fn_rotulo_estrutural(ce.chave, array['passivo','patrimonio'])
  group by ce.valor_num, coalesce(ce.entidade_coluna, ''), coalesce(ce.periodo_coluna, '')
  order by count(distinct ce.chave) desc
  limit 1;
$$;

grant execute on function fn_contas_repetindo_valor(uuid) to authenticated;

-- A guarda propriamente dita: o corpo da 0029 com a consulta inline trocada
-- pela função acima. Nada mais muda.
create or replace function fn_registrar_campos_extraidos(
  p_documento_versao_id uuid,
  p_campos jsonb,
  p_nivel nivel_autonomia default 'N0',
  p_falha_motivo text default null
)
returns int
language plpgsql
as $$
declare
  v_count            int := 0;
  v_item             jsonb;
  v_valor             numeric;
  v_confianca          numeric;
  v_status_aceite      text;
  v_aceito_por         text;
  v_aceito_em          timestamptz;
  v_n_auto_aceitos     int := 0;
  v_valores_nao_zero   numeric[] := '{}';
  v_n_baixa_confianca  int := 0;
  v_max_repeticoes     int := 0;
  v_valor_repetido      numeric;
  v_documento_id       uuid;
  v_caso_id            uuid;
  v_nome_original      text;
  v_pendencia_id       uuid;
  -- 0029: o auto-aceite deixa de acontecer DENTRO do loop. Estas duas variáveis
  -- são o que permite decidir o aceite DEPOIS das guardas.
  v_guarda_disparou    boolean := false;
begin
  if p_campos is not null and jsonb_typeof(p_campos) = 'array' then
    for v_item in select * from jsonb_array_elements(p_campos)
    loop
      v_valor := case when (v_item->>'valor_num') ~ '^-?\d+(\.\d+)?$' then (v_item->>'valor_num')::numeric else null end;
      v_confianca := case when (v_item->>'confianca') ~ '^-?\d+(\.\d+)?$' then (v_item->>'confianca')::numeric else null end;

      -- 0029: TODA linha entra como 'pendente'. O auto-aceite de >=95% (pedido do
      -- dono, cont.¹⁴) acontece DEPOIS das guardas — ver o bloco de promoção mais
      -- abaixo. Aceitar aqui era aceitar ANTES de saber se a extração é suspeita.
      v_status_aceite := 'pendente';
      v_aceito_por := null;
      v_aceito_em := null;
      if v_confianca is not null and v_confianca >= 0.95 then
        v_n_auto_aceitos := v_n_auto_aceitos + 1;  -- elegíveis; só viram aceitos se nenhuma guarda disparar
      end if;

      insert into campo_extraido
        (documento_versao_id, chave, valor_texto, valor_num, unidade, confianca,
         origem_pagina, origem_linha, ordem, nivel_autonomia, secao, secao_canonica, entidade_coluna, periodo_coluna,
         status_aceite, aceito_por, aceito_em)
      values (
        p_documento_versao_id,
        coalesce(v_item->>'chave', '(sem rótulo)'),
        v_item->>'valor_texto',
        v_valor,
        v_item->>'unidade',
        v_confianca,
        case when (v_item->>'origem_pagina') ~ '^\d+$' then (v_item->>'origem_pagina')::int else null end,
        v_item->>'origem_linha',
        -- ordem: posição da linha NO DOCUMENTO. É o sinal que permite reconhecer
        -- um subtotal impresso ACIMA dos seus componentes.
        case when (v_item->>'ordem') ~ '^\d+$' then (v_item->>'ordem')::int else null end,
        p_nivel,
        v_item->>'secao',
        v_item->>'secao_canonica',
        v_item->>'entidade_coluna',
        v_item->>'periodo_coluna',
        v_status_aceite,
        v_aceito_por,
        v_aceito_em
      );
      v_count := v_count + 1;

      if v_valor is not null and v_valor <> 0 then
        v_valores_nao_zero := array_append(v_valores_nao_zero, v_valor);
      end if;
      if v_confianca is not null and v_confianca < 0.7 then
        v_n_baixa_confianca := v_n_baixa_confianca + 1;
      end if;
    end loop;
  end if;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:n8n', 'extracao_sombra', 'documento_versao:'||p_documento_versao_id,
            jsonb_build_object('campos', v_count, 'nivel', p_nivel, 'falha_motivo', p_falha_motivo, 'auto_aceitos', v_n_auto_aceitos));

  select d.id, d.caso_id, dv.nome_original into v_documento_id, v_caso_id, v_nome_original
  from documento_versao dv join documento d on d.id = dv.documento_id
  where dv.id = p_documento_versao_id;

  if v_documento_id is null then
    -- 0029: ANTES isto era `return v_count` puro, e o efeito era o pior possível.
    -- Quando `Registrar Documento` falhava, o nó seguinte montava a requisição com
    -- `documento_versao_id = null`, a extração era EXECUTADA (dinheiro gasto) e
    -- caía aqui: a função retornava 0 com sucesso e JOGAVA FORA o `p_falha_motivo`
    -- antes do Sinal 3. Documento inexistente, chamada paga, zero pendência, zero
    -- rastro fora do log do n8n. O comentário antigo dizia "nunca deveria acontecer
    -- (FK)" — mas FK não dispara com `null`.
    --
    -- Não há `caso_id` para abrir pendência (é justamente o que falta), então o
    -- registro vai para `evento_auditoria`, que é append-only e não exige caso, e
    -- um `warning` fica no log do Postgres. A PREVENÇÃO é a montada: o nó
    -- `Montar Req Extracao` agora recusa montar requisição sem versão.
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values ('sistema:n8n', 'extracao_orfa', 'documento_versao:'||coalesce(p_documento_versao_id::text,'null'),
              jsonb_build_object('campos_descartados', v_count, 'falha_motivo', p_falha_motivo,
                                 'porque', 'documento_versao inexistente: campos e motivo nao tinham onde ser gravados'));
    raise warning 'fn_registrar_campos_extraidos: documento_versao % inexistente; % campo(s) e o motivo "%" foram descartados',
      p_documento_versao_id, v_count, coalesce(p_falha_motivo, '(sem motivo)');
    return v_count;
  end if;

  if v_count > 0 then
    -- ----- Sinal 1 (0013): mesmo valor não-zero repetido em muitas contas -----
    -- Sinal 1 refinado (0022): conta quantas contas DISTINTAS repetem o MESMO
    -- valor DENTRO DA MESMA COLUNA (entidade × período) e só considera valores
    -- MATERIAIS. Antes a contagem era sobre o lote inteiro: num documento
    -- combinado (5 empresas × 2 anos) o mesmo valor legitimamente reaparece em
    -- cada coluna, e valores pequenos (18, 40, 180) coincidem à toa — o teste
    -- v24 gerou 5 alertas falsos, que é o pior resultado possível numa guarda
    -- (o analista aprende a ignorar o aviso).
    -- Sinal 1 refinado de novo (0034): a consulta saiu daqui para
    -- `fn_contas_repetindo_valor`, que EXCLUI os totais de grupo. Elas tinham o
    -- mesmo valor por construção — Ativo = Passivo + PL — e a guarda acusava o
    -- balanço mais correto possível: no v35, "ATIVO", "TOTAL DO ATIVO",
    -- "PASSIVO E PATRIMÔNIO LÍQUIDO" e "TOTAL DO PASSIVO E DO PATRIMÔNIO
    -- LÍQUIDO" valiam 14529 cada, e o alerta era 100% falso.
    select valor, n_contas into v_valor_repetido, v_max_repeticoes
      from fn_contas_repetindo_valor(p_documento_versao_id);

    select id into v_pendencia_id from pendencia
      where caso_id = v_caso_id and motivo = 'extracao:padrao_suspeito:' || v_documento_id and estado <> 'resolvida'
      limit 1;
    if coalesce(v_max_repeticoes, 0) >= 4 then
      v_guarda_disparou := true;
      if v_pendencia_id is null then
        insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
          values (v_caso_id, 'extracao', 'extracao_padrao_suspeito', 'importante', true,
            format('%s contas diferentes, na MESMA coluna, vieram com o MESMO valor material (%s) — padrão '
                   'típico de fabricação/alucinação, não de dado real. Conferir contra o arquivo original.',
                   v_max_repeticoes, round(v_valor_repetido, 2)),
            v_documento_id, 'extracao:padrao_suspeito:' || v_documento_id);
      end if;
    elsif v_pendencia_id is not null then
      update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:extracao'
        where id = v_pendencia_id;
    end if;

    -- ----- Sinal 2 (0013): parcela relevante das linhas com confiança baixa -----
    select id into v_pendencia_id from pendencia
      where caso_id = v_caso_id and motivo = 'extracao:baixa_confianca:' || v_documento_id and estado <> 'resolvida'
      limit 1;
    if v_n_baixa_confianca >= 3 and v_n_baixa_confianca::numeric / v_count >= 0.3 then
      v_guarda_disparou := true;
      if v_pendencia_id is null then
        insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
          values (v_caso_id, 'extracao', 'extracao_baixa_confianca', 'importante', true,
            format('%s de %s linhas extraídas vieram com confiança abaixo de 70%%. Revisar antes de aceitar.',
                   v_n_baixa_confianca, v_count),
            v_documento_id, 'extracao:baixa_confianca:' || v_documento_id);
      end if;
    elsif v_pendencia_id is not null then
      update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:extracao'
        where id = v_pendencia_id;
    end if;
  end if;

  -- ----- Sinal 3 (0016): a própria chamada de extração falhou/veio truncada -----
  select id into v_pendencia_id from pendencia
    where caso_id = v_caso_id and motivo = 'extracao:falhou:' || v_documento_id and estado <> 'resolvida'
    limit 1;
  -- 0029: `v_count = 0` entra na condição. A 0016 fechou "a chamada de extração
  -- falhou"; NÃO fechou "a chamada respondeu JSON válido com `linhas: []`". Nesse
  -- caso `p_falha_motivo` é nulo e `v_count` é zero, então NENHUM dos três sinais
  -- rodava: o documento ficava com tipo, confiança alta, `em_validacao`, zero linhas
  -- e zero pendências — indistinguível de um documento que legitimamente não tem
  -- números. E o pipeline PRODUZ esse estado de propósito: `.xlsx` e mime não
  -- previsto mandam uma string de aviso para a IA em vez do arquivo, pagam a chamada
  -- e recebem zero linhas. Uma cláusula aqui fecha os três casos de uma vez.
  if p_falha_motivo is not null or v_count = 0 then
    v_guarda_disparou := true;  -- extração falha/vazia nunca auto-aceita
    if v_pendencia_id is null then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
        values (v_caso_id, 'extracao', 'extracao_falhou', 'importante', true,
          format('Extração de "%s" falhou ou veio incompleta (%s linhas gravadas). Motivo: %s',
                 coalesce(v_nome_original, '?'), v_count,
                 coalesce(p_falha_motivo,
                          'a chamada respondeu sem erro, mas não trouxe NENHUMA linha. '
                          'Causa mais comum: formato que o pipeline ainda não converte em texto '
                          '(.xlsx/.docx) — nesses casos a IA recebe um aviso em vez do arquivo.')),
          v_documento_id, 'extracao:falhou:' || v_documento_id);
    end if;
  elsif v_pendencia_id is not null then
    update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:extracao'
      where id = v_pendencia_id;
  end if;

  -- ----- Auto-aceite (0029): DEPOIS das guardas, nunca antes -----------------
  -- O defeito que isto corrige: a 0027 gravava `status_aceite='aceito'` dentro do
  -- loop, para toda linha com confiança >=95%, e só DEPOIS rodava as três guardas
  -- (padrão suspeito / baixa confiança / extração falhou). Nenhuma guarda revertia
  -- o aceite. Efeito: uma extração alucinada — cujo padrão típico é justamente vir
  -- com confiança ALTA e o mesmo valor repetido em muitas contas — entrava na base
  -- como FATO ACEITO, e o Sinal 1 abria uma pendência ao lado sem desfazer nada.
  --
  -- Isso furava a anti-ancoragem, que é o princípio inegociável do projeto
  -- (docs/01, f0/06): nenhum número sugerido por IA vira fato sem aceite. Uma
  -- guarda que dispara depois do aceite não é guarda, é legenda.
  if v_n_auto_aceitos > 0 and not v_guarda_disparou then
    update campo_extraido
      set status_aceite = 'aceito',
          aceito_por = 'sistema:auto_aceite (confiança >=95%, sem guarda disparada)',
          aceito_em = now()
      where documento_versao_id = p_documento_versao_id
        and confianca >= 0.95
        and status_aceite = 'pendente';

    insert into decisao (caso_id, tipo, autor, motivo, payload)
      values (v_caso_id, 'aprovacao', 'sistema:auto_aceite',
        format('%s linha(s) auto-aceitas por confiança >=95%% na extração de "%s" — nenhuma guarda disparou.',
               v_n_auto_aceitos, coalesce(v_nome_original, '?')),
        jsonb_build_object('documento_id', v_documento_id, 'documento_versao_id', p_documento_versao_id,
                           'n_auto_aceitos', v_n_auto_aceitos));
  elsif v_n_auto_aceitos > 0 then
    -- Havia linhas elegíveis, mas uma guarda disparou: ficam PENDENTES e o motivo
    -- fica registrado, para não parecer que o auto-aceite simplesmente não rodou.
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values ('sistema:auto_aceite', 'auto_aceite_suprimido', 'documento_versao:'||p_documento_versao_id,
              jsonb_build_object('n_elegiveis', v_n_auto_aceitos,
                                 'porque', 'guarda de extracao disparou; linhas seguem pendentes de revisao humana'));
  end if;

  return v_count;
end;
$$;

do $LOTE$
declare
  v_ver uuid := '00000000-0000-0000-0000-0000cafe0034';
  v_doc uuid := '00000000-0000-0000-0000-0000cafe0035';
  v_caso uuid := '00000000-0000-0000-0000-0000cafe0036';
  v_n int;
begin
  -- VERIFICAÇÃO EMBUTIDA com o caso REAL do v35: as quatro linhas de total do
  -- balanço da Componentes 2025, todas valendo 14529. Se a guarda voltar a
  -- contá-las, esta migration se recusa a aplicar.
  insert into caso (id, nome) values (v_caso, 'checagem 0034') on conflict (id) do nothing;
  insert into documento (id, caso_id, tipo_taxonomia, status)
    values (v_doc, v_caso, 'BALANCO', 'em_validacao') on conflict (id) do nothing;
  insert into documento_versao (id, documento_id, n_versao, nome_original, arquivo_ref)
    values (v_ver, v_doc, 1, 'chk0034.pdf', 'checagem/0034') on conflict (id) do nothing;
  delete from campo_extraido where documento_versao_id = v_ver;
  insert into campo_extraido (documento_versao_id, chave, valor_num, periodo_coluna, ordem)
  values
    (v_ver, 'ATIVO',                                    14529, '2025', 1),
    (v_ver, 'TOTAL DO ATIVO',                           14529, '2025', 2),
    (v_ver, 'PASSIVO E PATRIMÔNIO LÍQUIDO',             14529, '2025', 3),
    (v_ver, 'TOTAL DO PASSIVO E DO PATRIMÔNIO LÍQUIDO', 14529, '2025', 4),
    (v_ver, 'Caixa e bancos',                            1200, '2025', 5);

  select coalesce(max(n_contas), 0) into v_n from fn_contas_repetindo_valor(v_ver);
  if v_n >= 4 then
    raise exception '0034: a identidade contábil (Ativo = Passivo+PL) voltou a ser contada como alucinação — % contas', v_n;
  end if;

  -- E a contraprova: quatro CONTAS de verdade com o mesmo valor continuam
  -- disparando. Sem isto, a correção acima poderia ter simplesmente desligado
  -- a guarda.
  delete from campo_extraido where documento_versao_id = v_ver;
  insert into campo_extraido (documento_versao_id, chave, valor_num, periodo_coluna, ordem)
  values
    (v_ver, 'Fornecedores nacionais',  9999, '2025', 1),
    (v_ver, 'Salários a pagar',        9999, '2025', 2),
    (v_ver, 'ICMS a recolher',         9999, '2025', 3),
    (v_ver, 'Provisões trabalhistas',  9999, '2025', 4);
  select coalesce(max(n_contas), 0) into v_n from fn_contas_repetindo_valor(v_ver);
  if v_n < 4 then
    raise exception '0034: quatro CONTAS reais com o mesmo valor deveriam continuar disparando — veio %', v_n;
  end if;

  delete from campo_extraido where documento_versao_id = v_ver;
  delete from documento_versao where id = v_ver;
  delete from documento where id = v_doc;
  delete from caso where id = v_caso;
  raise notice '0034 ok: a identidade contábil deixa de virar alerta de alucinação, e quatro contas reais continuam disparando';
end $LOTE$;

-- =============================================================================
-- 0033 — A pré-condição de Ativo × Passivo+PL dizia que falhou, nunca por quê
--
-- O DEFEITO. No teste v33, CINCO reconciliações A.1 saíram como
-- `precondicao_nao_satisfeita` com esta descrição, literal:
--
--   "O Balanço foi encontrado, mas não foi possível localizar nem a linha de
--    Ativo Total / Passivo+PL nem contas de seção suficientes para somá-los
--    (rótulos extraídos não bateram com os padrões esperados)."
--
-- Está correta e é inútil. Ela não diz qual LADO faltou (Ativo? Passivo+PL?
-- os dois?), nem em qual ANO, nem qual coluna de entidade/período foi tentada,
-- nem — o que decide a investigação — QUAIS rótulos de total a extração de
-- fato trouxe. Quem recebe essa pendência tem de abrir o PDF e o SQL Editor
-- lado a lado e adivinhar qual `like` não casou. Cinco vezes.
--
-- E há um segundo silêncio, no caminho de SUCESSO. Quando os dois lados são
-- encontrados, a descrição publica só os números:
--
--   "2025: Ativo 158801 vs Passivo+PL 126673 (diferença de 32128)"
--
-- Sem dizer DE ONDE veio cada lado. E a origem muda completamente o que se
-- investiga: o lado direito pode ter vindo (a) da linha combinada "TOTAL DO
-- PASSIVO E DO PATRIMÔNIO LÍQUIDO", (b) da soma de duas linhas de total
-- separadas, ou (c) do FALLBACK que soma as contas da seção. No caso (c) uma
-- seção inteira que a extração não classificou some da soma, e a "divergência"
-- não é divergência do documento — é buraco da extração. Hoje os três casos
-- saem com o mesmo texto.
--
-- O QUE MUDA. A função passa a acumular o motivo por ano e a publicá-lo:
--   • pré-condição não satisfeita  → nomeia o lado que faltou, o ano, a coluna
--     tentada, e LISTA os rótulos candidatos que existem na extração (os que
--     contêm ativo/passivo/patrimônio/total). É a linha que faltava: o rótulo
--     que não casou está nessa lista, à vista.
--   • qualquer resultado           → cada ano declara a ORIGEM dos dois lados
--     ("linha 'TOTAL DO ATIVO'" × "soma da seção ATIVO (24 linhas)").
--
-- O QUE NÃO MUDA, de propósito: nenhum critério de casamento foi afrouxado.
-- Alargar o `like` para fazer a pré-condição passar é fabricar um casamento —
-- o número entraria como conferido sem ninguém ter visto qual linha foi usada.
-- Esta migration só faz a falha se explicar; se algum padrão precisar mudar,
-- a lista de rótulos publicada aqui é o insumo para decidir isso com dado.
--
-- REPRODUÇÃO — e o que NÃO foi possível reproduzir. Rodei a A.1 contra o book
-- sintético inteiro (test-data/book-vertentes, via o arnês e2e, que aplica as
-- migrations reais e grava pelas funções reais): as SETE entidades/períodos
-- deram `ok`. Ou seja, a pré-condição do v33 NÃO falha por rótulo do book —
-- ela falhou pelo que a extração da OpenAI emitiu naquele lote, que não está
-- versionado aqui. Não inventei fixture para "provar" o defeito: o teste desta
-- migration exercita o CAMINHO da falha com uma extração deliberadamente
-- pobre, e o que ele afirma é que a mensagem passa a nomear o rótulo — não que
-- o v33 falhou por um motivo que eu não tenho como medir.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- fn_rotulos_candidatos — os rótulos que a extração trouxe e que POderiam ter
-- sido um total de Ativo / Passivo / PL. É o que transforma "não bateu" em "não
-- bateu com estes aqui".
--
-- Limite de 12: a mensagem vai para uma pendência que um humano lê. Uma lista
-- de 200 rótulos é o mesmo silêncio com outra roupa.
--
-- NÃO FILTRA POR COLUNA — e a decisão é deliberada. Filtrar reproduziria aqui
-- exatamente o defeito que se quer diagnosticar: quando a causa da falha é o
-- casamento de COLUNA (entidade/período), o rótulo certo EXISTE e some da
-- lista, e a pendência voltaria a dizer "não achei nada". Foi essa família que
-- a 0030 corrigiu no balanço combinado. Então a coluna vai ANOTADA em cada
-- rótulo: se o rótulo aparece com a coluna "2024" e a busca era em "2025", o
-- humano lê a causa direto na mensagem.
-- -----------------------------------------------------------------------------
create or replace function fn_rotulos_candidatos(
  p_documento_versao_id uuid
)
returns text
language sql
stable
as $$
  with cand as (
    select distinct
      ce.chave,
      coalesce(nullif(ce.entidade_coluna, ''), '—') as ec,
      coalesce(nullif(ce.periodo_coluna, ''), '—')  as pc
    from campo_extraido ce
    where ce.documento_versao_id = p_documento_versao_id
      and ce.valor_num is not null
      and (fn_normalizar_texto(ce.chave) like '%total%'
           or fn_normalizar_texto(ce.chave) like '%ativo%'
           or fn_normalizar_texto(ce.chave) like '%passivo%'
           or fn_normalizar_texto(ce.chave) like '%patrimonio%')
    order by ce.chave
    limit 12
  )
  select case when count(*) = 0
    then 'nenhum rótulo com ativo/passivo/patrimônio/total foi extraído desta versão'
    else string_agg(format('"%s" [entidade: %s; período: %s]', chave, ec, pc), ', ' order by chave)
  end
  from cand;
$$;

comment on function fn_rotulos_candidatos(uuid) is
  'Rótulos extraídos que poderiam ser um total de Ativo/Passivo/PL, com a coluna de '
  'entidade/período de cada um. Existe para a pendência de pré-condição poder NOMEAR '
  'o que não casou — inclusive quando o que não casou foi a COLUNA (0033).';

-- -----------------------------------------------------------------------------
-- A.1 — Ativo Total = Passivo + PL, agora declarando origem e causa.
-- Corpo idêntico ao da 0023 salvo pelo que está marcado com "0033".
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
  -- 0033: origem de cada lado e o registro do que faltou, por ano.
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

    select * into v_ativo from fn_valor_conceito_col(v_versao,
      array['ativo', 'total'], array['circulante', 'nao circulante'], v_col_ent, v_col_per);
    if v_ativo.id is null then
      -- Sem linha "TOTAL DO ATIVO": soma as contas da seção ATIVO.
      select * into v_soma from fn_soma_secao(v_versao, array['ativo'], v_col_ent, v_col_per,
        array['passivo', 'patrimonio'], array['total do ativo']);
      v_esq := case when coalesce(v_soma.n_linhas, 0) > 0 then v_soma.soma end;
      -- 0033: a origem importa tanto quanto o número. Uma soma de seção que
      -- perdeu uma seção inteira produz uma "divergência" que não é do
      -- documento; a linha impressa, não.
      v_orig_esq := case when v_esq is null then null
        else format('soma da seção ATIVO (%s linhas, sem linha de total impressa)', v_soma.n_linhas) end;
    else
      v_esq := v_ativo.valor_num;
      v_orig_esq := format('linha "%s"', v_ativo.chave);
    end if;

    select * into v_passivo_pl from fn_valor_conceito_col(v_versao,
      array['passivo', 'patrimonio', 'total'], array['circulante'], v_col_ent, v_col_per);
    if v_passivo_pl.id is not null then
      v_dir := v_passivo_pl.valor_num;
      v_orig_dir := format('linha "%s"', v_passivo_pl.chave);
    else
      select * into v_passivo from fn_valor_conceito_col(v_versao,
        array['passivo', 'total'], array['patrimonio', 'circulante', 'nao circulante'],
        v_col_ent, v_col_per);
      select * into v_pl from fn_valor_conceito_col(v_versao,
        array['patrimonio', 'liquido', 'total'], array['circulante'], v_col_ent, v_col_per);
      if v_passivo.id is not null and v_pl.id is not null then
        v_dir := v_passivo.valor_num + v_pl.valor_num;
        v_orig_dir := format('linhas "%s" + "%s"', v_passivo.chave, v_pl.chave);
      else
        select * into v_soma from fn_soma_secao(v_versao,
          array['passivo', 'patrimonio'], v_col_ent, v_col_per,
          '{}', array['total do passivo']);
        v_dir := case when coalesce(v_soma.n_linhas, 0) > 0 then v_soma.soma end;
        v_orig_dir := case when v_dir is null then null
          else format('soma das seções PASSIVO+PL (%s linhas, sem linha de total impressa)', v_soma.n_linhas) end;
      end if;
    end if;

    if v_esq is null or v_dir is null then
      -- 0033: era um `continue` mudo. Guarda O QUE faltou, para a mensagem final.
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
      continue; -- este ano não tem os dois lados; tenta o próximo
    end if;

    v_n_anos := v_n_anos + 1;
    v_div_abs := abs(v_esq - v_dir);
    v_tol := greatest(p_tolerancia_abs, abs(v_esq) * p_tolerancia_pct);
    if v_div_abs > v_tol then
      v_resultado := 'divergente';
      -- 0033: a origem de cada lado entra no texto. "Ativo 158.801 vs
      -- Passivo+PL 126.673" não diz se o lado direito é uma linha impressa ou
      -- uma soma que perdeu seção — e são investigações diferentes.
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
    -- 0033: nomeia o lado, o ano, a coluna — e os rótulos que EXISTEM. O rótulo
    -- que não casou está nessa lista, e é o que decide se o defeito é da
    -- extração (não trouxe a linha) ou do padrão de casamento (trouxe com outro
    -- nome). Sem ela, as duas hipóteses custam o mesmo: abrir o PDF.
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
  -- 0033: anos que ficaram de fora também aparecem — um "confere" que só olhou
  -- 1 de 2 exercícios não é a mesma coisa que um que olhou os dois.
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

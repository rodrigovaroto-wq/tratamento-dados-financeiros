-- =============================================================================
-- 0165 — "PASSIVO" sozinho JÁ É Passivo + PL, e a A.1 somava o PL duas vezes
--
-- CAUSA RAIZ, MEDIDA CONTRA OS PDFs REAIS que o dono anexou em 14/09/2026 —
-- não contra fixture inventada (regra 4).
--
-- O lote real do caso "teste 143" (44 documentos da AMOBELEZA / GENERAL
-- CORPORATE / GENERAL TABACO / OMNIBEAUTY) abriu ONZE pendências de
-- `reconciliacao:ativo_passivo_pl`, uma por entidade × exercício, todas dizendo
-- que o balanço não fecha. Nenhuma delas era verdade.
--
-- `AMOBELEZA - BALANÇO 2024.pdf`, lido linha a linha:
--
--     ATIVO                     118.591.566,53 D
--     PASSIVO                   118.591.566,53 C   <- IGUAL ao ativo
--       PASSIVO CIRCULANTE      119.620.673,17 C
--       PASSIVO NÃO-CIRCULANTE    8.362.115,49 C
--       PATRIMÔNIO LÍQUIDO        9.391.222,13 D   <- negativo (prejuízo)
--
--     119.620.673,17 + 8.362.115,49 - 9.391.222,13 = 118.591.566,53
--
-- Ou seja: a linha "PASSIVO" deste ERP **já é** Passivo Circulante + Passivo
-- Não-Circulante + Patrimônio Líquido. Ela não é o passivo exigível — é o total
-- do LADO DIREITO do balanço, do mesmo jeito que "ATIVO" é o total do esquerdo.
-- É convenção de plano de contas brasileiro (o grupo "2 - PASSIVO" contendo
-- "2.3 - Patrimônio Líquido" como subgrupo), não peculiaridade de um arquivo:
-- conferida nos TRÊS balanços com camada de texto que o dono mandou, de DUAS
-- empresas diferentes e dois modelos de relatório diferentes.
--
-- O QUE A FUNÇÃO FAZIA. Os dois primeiros localizadores do lado direito pedem
-- rótulo com "total" ou o par estrutural ['passivo','patrimonio'] — "PASSIVO"
-- sozinho não casa nenhum dos dois. Caía então no terceiro caminho, que busca
-- o passivo pelo rótulo ESTRUTURAL ['passivo'] (casa "PASSIVO" bare), busca o
-- PL por ['patrimonio'] (casa "PATRIMÔNIO LÍQUIDO"), e SOMA os dois:
--
--     118.591.566,53 + (-9.391.222,13) = 109.200.344,40
--
-- que é exatamente o "Passivo+PL" que o painel do dono mostrou, com a
-- "diferença de 9.391.222,13" — o PL, contado duas vezes. Com PL negativo a
-- conta fica ABAIXO do ativo; com PL positivo fica ACIMA. As onze pendências do
-- lote são as duas direções do mesmo defeito.
--
-- A CORREÇÃO, e por que ela é estreita de propósito: quando o passivo veio do
-- casamento ESTRUTURAL (rótulo que é só a palavra do grupo) **e o valor dele já
-- bate com o Ativo dentro da tolerância da própria checagem**, ele É o total do
-- grupo — usar direto, sem somar o PL. O valor desambigua o rótulo, que sozinho
-- é ambíguo.
--
-- O QUE NÃO MUDA, e é o que mantém a checagem honesta:
--
--   • rótulo que DIZ "Passivo Total" (e exclui patrimônio) continua sendo
--     tratado como exigível e somado ao PL. Se ESSE bater com o ativo, é um
--     balanço que não fecha por PL — divergência de verdade, e continua
--     reportada;
--   • "PASSIVO" bare que NÃO bate com o ativo continua somando com o PL, que é
--     o comportamento de quem usa a convenção do exigível;
--   • nenhum outro caminho (linha combinada, soma de seções, lado do ativo) é
--     tocado.
--
-- MEDIÇÃO DO INVARIANTE (regra 2): `Supabase/test/passivo_bare_e_o_grupo.test.sql`
-- monta um balanço com os números REAIS do PDF acima. Com a correção desligada
-- (voltando o ramo para a soma incondicional) ele reprova, dizendo
-- "divergente / 9391222.13"; com ela ligada, `resultado = ok`. E o mesmo
-- arquivo trava o contrapositivo: um balanço em que o "PASSIVO" bare é
-- exigível de verdade continua somando o PL.
--
-- Idempotente: `create or replace`.
-- =============================================================================

begin;

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
  -- 0165: o "PASSIVO" bare veio do casamento ESTRUTURAL (e não de um rótulo que
  -- diz "Passivo Total")? É essa a única via ambígua — ver o comentário grande
  -- da migration.
  v_passivo_estrutural boolean := false;
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
    v_passivo_estrutural := false;

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
          v_passivo_estrutural := v_passivo.id is not null;
        end if;
        if v_pl.id is null then
          select * into v_pl from fn_valor_estrutural_col(v_versao,
            array['patrimonio'], v_col_ent, v_col_per);
        end if;
        -- 0165: "PASSIVO" BARE QUE JÁ BATE COM O ATIVO É O TOTAL DO GRUPO.
        -- Ver o cabeçalho desta migration para a medição. Só vale para o rótulo
        -- ESTRUTURAL: um rótulo que DIZ "Passivo Total" (e exclui patrimônio)
        -- está afirmando exigível, e nele a igualdade com o Ativo seria um
        -- balanço que não fecha — que é divergência de verdade, e continua
        -- sendo reportada pelo ramo de baixo.
        if v_passivo_estrutural and v_esq is not null
           and abs(v_passivo.valor_num - v_esq)
               <= greatest(p_tolerancia_abs, abs(v_esq) * p_tolerancia_pct) then
          v_dir := v_passivo.valor_num;
          v_orig_dir := format('linha "%s" (total do grupo, já inclui o Patrimônio Líquido)',
                               v_passivo.chave);
        elsif v_passivo.id is not null and v_pl.id is not null then
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

comment on function fn_reconciliar_ativo_passivo_pl(uuid, uuid, uuid, numeric, numeric) is
  'A.1 — Ativo Total = Passivo + PL. 0165: "PASSIVO" bare cujo valor já bate com o Ativo é o '
  'total do LADO DIREITO (já inclui o PL) e não é somado ao PL de novo — medido nos balanços '
  'reais do caso "teste 143", onde essa soma dupla abriu 11 divergências falsas.';

-- -----------------------------------------------------------------------------
-- O CATÁLOGO DA SONDA — o painel de produção não vê o que o catálogo não lista.
--
-- `v_passivo_estrutural` é IDENTIFICADOR ESTRUTURAL, não comentário decorativo:
-- é a variável que carrega a única distinção que esta migration introduz (o
-- passivo veio do casamento estrutural ou de um rótulo que diz "total"?). Um
-- `create or replace` com o corpo velho apaga esse nome; a sonda vê.
--
-- Um requisito de COMPORTAMENTO não entra aqui, e o motivo é honesto: exercitar
-- esta função exige um caso com documento, versão e campos extraídos — é
-- fixture de mandato, não de instalação. Quem prova o comportamento é
-- `Supabase/test/passivo_bare_e_o_grupo.test.sql`, no CI, com os números do
-- balanço real. O que a sonda responde é o contrapositivo útil: se o marcador
-- sumiu, a migration não está aplicada, sem dúvida.
-- -----------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('passivo_bare_nao_soma_pl_duas_vezes', '0165', 'corpo', 'fn_reconciliar_ativo_passivo_pl',
   'v_passivo_estrutural', null,
   'A checagem A.1 somava o Patrimônio Líquido DUAS vezes em todo balanço cuja linha "PASSIVO" '
   'é o total do lado direito (convenção de plano de contas brasileiro, medida nos balanços '
   'reais do caso "teste 143": ATIVO 118.591.566,53 = PASSIVO 118.591.566,53). Sem esta '
   'migration o lote da AMO abre ONZE pendências de balanço que não fecha, todas falsas, e o '
   'analista perde a confiança na checagem que existe justamente para ele confiar.',
   'bloqueante', 630)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0165', revisado_em = current_date,
       observacao = 'A 0165 muda o corpo de fn_reconciliar_ativo_passivo_pl e nada mais — um '
                    'requisito de corpo (v_passivo_estrutural) basta para a sonda. O '
                    'comportamento é provado no CI (passivo_bare_e_o_grupo.test.sql), com os '
                    'números do balanço real, porque exercitá-lo exige fixture de mandato.';

commit;

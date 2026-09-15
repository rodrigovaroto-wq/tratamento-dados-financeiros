-- =============================================================================
-- 0176 — o balcão ambíguo (que desde a 0175 pode ter CNPJ) parou de absorver
-- quem é CONFIRMADO, e a pendência do balcão parou de citar nome apagado
--
-- Este arquivo mede os CINCO defeitos que a revisão da 0175 achou (ver o
-- cabeçalho de Supabase/migrations/0176_o_balcao_nao_absorve_quem_e_confirmado.sql
-- para a medição completa, com números, contra o estado da 0175 SEM esta
-- correção). Os nomes/CNPJ da OMNIBEAUTY são os reais do caso
-- bf0246bb-c93b-4d08-a7df-5d356c9d6275 ("teste 143", regra 4 do CLAUDE.md); a
-- "metalúrgica" e o CNPJ do rodapé de contador são o CENÁRIO que o próprio
-- comentário de fn_entidade_aprender_cnpj/fn_registrar_diagnostico já citava
-- desde a 0169/0172 como o motivo de nunca aprender CNPJ fora do ramo
-- confirmado — não há dado de produção desse par específico, e o comentário
-- de cada bloco abaixo diz isso quando é o caso (regra 4 do CLAUDE.md).
--
-- O QUE ESTE ARQUIVO MEDE:
--   1. CRÍTICO caso B: uma entidade CONFIRMADA (documento e nome próprios,
--      validada pelo ramo `else` de fn_registrar_diagnostico) que recebe pelo
--      diagnóstico o MESMO CNPJ que um balcão ambíguo já tinha aprendido NÃO
--      é fundida/deletada dentro do balcão — fica pendência, não fusão;
--   2. CRÍTICO caso A: um documento NOVO que chega na PORTA DE REGISTRO com
--      um CNPJ que já pertence a um balcão ambíguo NÃO é absorvido por ele —
--      nasce com entidade própria (sem o CNPJ colidido);
--   3. MÉDIO 1: dentro do balcão, o renomeio por CNPJ só roda com o CNPJ que
--      o `aprender` de fato confirmou nesta entidade — uma entidade que já
--      tinha OUTRO CNPJ gravado não é "renomeada por CNPJ" citando um CNPJ
--      que não é dela;
--   4. ALTO: a pendência `entidade_ambigua_respondida`, depois de o bloco do
--      balcão fundir duas entidades, cita o NOME CORRENTE da sobrevivente —
--      não o nome (apagado) de quem foi fundida;
--   5. contrapositivo, para as quatro correções acima não terem afrouxado a
--      convergência: dois balcões da MESMA empresa ainda convergem em UM só
--      quando o CNPJ chega pelos dois — a MESMA propriedade central de
--      `Supabase/test/balcao_ambiguo_e_cnpj.test.sql` (não repetida aqui em
--      detalhe; aquele arquivo continua sendo a referência, com os 18
--      asserts dele intactos depois desta migration).
-- =============================================================================

create or replace function teste_assert_0176(p_cond boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_cond then
    raise notice 'ok    %', p_nome;
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

do $$
declare
  v_caso      uuid;
  v_r         jsonb;
  v_marcas    uuid; v_surubiju uuid; v_balcao1 uuid;
  v_doc_b1    uuid; v_ver_b1 uuid;
  v_met       uuid; v_doc_met uuid; v_ver_met uuid;
  v_n         int;
  v_ev        jsonb;
  v_pend_colisao_n int;
  c_cnpj  constant text := '36.193.378/0001-04';
  c_m     constant text := 'OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE MARCAS LTDA';
  c_s     constant text := 'OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE SURUBIJU';
  c_t     constant text := 'OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE';
  -- A "metalúrgica" NÃO é dado do lote real — é o cenário genérico que a
  -- 0169/0172 já citavam por escrito (CNPJ do rodapé do contador, empresa
  -- cliente diferente). Nome deliberadamente SEM raiz comum com a OMNIBEAUTY,
  -- para não casar por nome com nenhuma candidata (fn_mesma_entidade).
  c_met   constant text := 'VERTENTES METALURGICA LTDA';
  c_met2  constant text := 'OUTRA METALURGICA NOVA SA';
begin
  raise notice '--- ARRANJO: um balcão ambíguo (OMNIBEAUTY) que já aprendeu o CNPJ ---';
  v_caso := (fn_upsert_caso('0176 — balcao nao absorve confirmada'))::uuid;

  v_r := fn_registrar_documento(v_caso, c_m, 'ano', '2024', 'BALANCO', 0.99,
    'nome_arquivo', 'supabase_storage', 's/0176-marcas.pdf', 'BAL.pdf', true, 'HASH-0176T-M', 'ok');
  v_marcas := (select entidade_id from documento where id = (v_r->>'documento_id')::uuid);
  v_r := fn_registrar_documento(v_caso, c_s, 'ano', '2024', 'BALANCO', 0.99,
    'nome_arquivo', 'supabase_storage', 's/0176-surubiju.pdf', 'BAL.pdf', true, 'HASH-0176T-S', 'ok');
  v_surubiju := (select entidade_id from documento where id = (v_r->>'documento_id')::uuid);

  v_r := fn_registrar_documento(v_caso, c_t, 'ano', '2024', 'BALANCO', 0.99,
    'nome_arquivo', 'supabase_storage', 's/0176-balcao.pdf', 'BAL.pdf', true, 'HASH-0176T-B', 'ok');
  v_doc_b1 := (v_r->>'documento_id')::uuid;
  v_ver_b1 := (v_r->>'documento_versao_id')::uuid;
  v_balcao1 := (select entidade_id from documento where id = v_doc_b1);
  perform teste_assert_0176(fn_entidade_e_balcao_ambiguo(v_caso, v_balcao1),
    'PRÉ-CONDIÇÃO: o balcão nasce ambíguo (0162)');

  -- Balcão aprende o CNPJ sem fusão (é o primeiro a tê-lo no caso) — o caso
  -- (a) do cabeçalho da 0175.
  perform fn_registrar_diagnostico(v_doc_b1, v_ver_b1, c_t, true, 'BALANCO', 'anual', '12M24',
    'ok', null, 'resumo', 'justificativa', p_cnpj => c_cnpj);
  perform teste_assert_0176(
    (select fn_cnpj_canonico(cnpj) from entidade where id = v_balcao1) = fn_cnpj_canonico(c_cnpj),
    'PRÉ-CONDIÇÃO: o balcão aprendeu o CNPJ (0175)');
  perform teste_assert_0176(fn_entidade_e_balcao_ambiguo(v_caso, v_balcao1),
    'PRÉ-CONDIÇÃO: e continua ambíguo — só o NOME dele nunca foi confirmado');

  raise notice '--- 1. CRÍTICO caso B: entidade CONFIRMADA traz o mesmo CNPJ pelo diagnóstico ---';
  -- Documento e nome PRÓPRIOS, registrado e confirmado pelo caminho normal —
  -- em NADA relacionado ao balcão por nome (fn_mesma_entidade não casa).
  v_r := fn_registrar_documento(v_caso, c_met, 'ano', '2024', 'BALANCO', 0.99,
    'nome_arquivo', 'supabase_storage', 's/0176-met.pdf', 'BAL.pdf', true, 'HASH-0176T-MET', 'ok');
  v_doc_met := (v_r->>'documento_id')::uuid;
  v_ver_met := (v_r->>'documento_versao_id')::uuid;
  v_met := (select entidade_id from documento where id = v_doc_met);
  perform teste_assert_0176(v_met is distinct from v_balcao1,
    'PRÉ-CONDIÇÃO: a metalúrgica nasce como entidade PRÓPRIA, distinta do balcão');

  select count(*) into v_n from entidade where caso_id = v_caso;
  perform teste_assert_0176(v_n = 4, 'PRÉ-CONDIÇÃO: quatro entidades antes do diagnóstico da metalúrgica',
    format('%s entidade(s)', v_n));

  -- O diagnóstico CONFIRMA o nome da metalúrgica (ramo `else`) e traz o
  -- MESMO CNPJ que o balcão já tinha aprendido — o cenário do rodapé.
  perform fn_registrar_diagnostico(v_doc_met, v_ver_met, c_met, true, 'BALANCO', 'anual', '12M24',
    'ok', null, 'resumo', 'justificativa', p_cnpj => c_cnpj);

  -- ESTE É O ASSERT QUE REPROVA COM A 0176 DESLIGADA (medido nesta sessão,
  -- contra o estado da 0175 sem esta correção): a metalúrgica desaparecia
  -- (fn_fundir_entidade a deleta), `exists(...)` virava `false`.
  perform teste_assert_0176(exists (select 1 from entidade where id = v_met),
    'a metalúrgica CONFIRMADA continua existindo — o balcão NÃO a absorveu via CNPJ',
    'SEM a 0176: fundida e deletada dentro do balcão, sem pendência nenhuma acusando');

  select count(*) into v_n from entidade where caso_id = v_caso;
  perform teste_assert_0176(v_n = 4,
    'e o caso continua com QUATRO entidades — nenhuma fusão aconteceu',
    format('%s entidade(s) (esperado 4)', v_n));

  perform teste_assert_0176((select cnpj from entidade where id = v_met) is null,
    'e a metalúrgica NÃO ficou com o CNPJ do balcão — ele não é dela, é coincidência/rodapé');

  select count(*) into v_pend_colisao_n from pendencia
   where caso_id = v_caso and motivo = 'entidade_cnpj_colide_balcao:' || v_balcao1 and estado <> 'resolvida';
  perform teste_assert_0176(v_pend_colisao_n = 1,
    'e uma pendência de colisão de CNPJ foi aberta — a regra 1 do CLAUDE.md (ausência não vira dado): '
      || 'o sistema NÃO decide sozinho de quem é o CNPJ, mas também não cala a colisão',
    format('%s pendência(s)', v_pend_colisao_n));

  perform teste_assert_0176(exists (
      select 1 from evento_auditoria
       where acao = 'entidade_cnpj_colisao_recusada' and entidade_ref = 'entidade:' || v_balcao1),
    'com rastro em evento_auditoria (entidade_cnpj_colisao_recusada)');

  raise notice '--- 2. CRÍTICO caso A: documento NOVO chega na PORTA DE REGISTRO com o mesmo CNPJ ---';
  select count(*) into v_n from entidade where caso_id = v_caso;
  perform teste_assert_0176(v_n = 4, 'PRÉ-CONDIÇÃO: quatro entidades antes do registro novo',
    format('%s entidade(s)', v_n));

  v_r := fn_registrar_documento(v_caso, c_met2, 'ano', '2024', 'BALANCO', 0.99,
    'nome_arquivo', 'supabase_storage', 's/0176-met2.pdf', 'BAL.pdf', true, 'HASH-0176T-MET2', 'ok',
    p_cnpj => c_cnpj);

  -- ESTE É O ASSERT QUE REPROVA COM A 0176 DESLIGADA (medido nesta sessão):
  -- o documento novo era registrado DENTRO do balcão — `entidade_id` do
  -- documento apontava para o balcão, e o caso continuava com 4 entidades em
  -- vez de virar 5 (a metalúrgica-2 nunca ganhava linha própria).
  select count(*) into v_n from entidade where caso_id = v_caso;
  perform teste_assert_0176(v_n = 5,
    'o documento novo GANHOU entidade própria — não foi absorvido pelo balcão',
    format('%s entidade(s) (esperado 5)', v_n));

  perform teste_assert_0176(
    (select e.id from documento d join entidade e on e.id = d.entidade_id
       where d.id = (v_r->>'documento_id')::uuid) is distinct from v_balcao1,
    'e a entidade do documento novo é DIFERENTE do balcão');

  perform teste_assert_0176(
    (select e.cnpj from documento d join entidade e on e.id = d.entidade_id
       where d.id = (v_r->>'documento_id')::uuid) is null,
    'e essa entidade nova NÃO ficou com o CNPJ colidido — tratado como ausente para esta chamada, '
      || 'exatamente como se o balcão nunca tivesse este CNPJ');

  select count(*) into v_pend_colisao_n from pendencia
   where caso_id = v_caso and motivo = 'entidade_cnpj_colide_balcao:' || v_balcao1 and estado <> 'resolvida';
  perform teste_assert_0176(v_pend_colisao_n = 1,
    'a pendência de colisão continua sendo UMA só (idempotente por balcão, não por documento)',
    format('%s pendência(s)', v_pend_colisao_n));

  raise notice '--- 3. MÉDIO 1: o renomeio dentro do balcão usa o CNPJ CONFIRMADO, não o bruto ---';
  -- Um SEGUNDO balcão, com CNPJ VELHO já aprendido — distinto do CNPJ novo
  -- que vai chegar por um documento seguinte com nome mais completo.
  declare
    v_balcao2 uuid; v_doc_b2a uuid; v_ver_b2a uuid; v_doc_b2b uuid; v_ver_b2b uuid;
    c_cnpj_velho constant text := '11.222.333/0001-81';
    c_m2 constant text := 'DELTA DESENVOLVIMENTO E GESTAO DE MARCAS LTDA';
    c_s2 constant text := 'DELTA DESENVOLVIMENTO E GESTAO DE SURUBIJU';
    c_t2 constant text := 'DELTA DESENVOLVIMENTO E GESTAO DE';
    c_t2_completo constant text := 'DELTA DESENVOLVIMENTO E GESTAO DE LTDA';
  begin
    perform fn_registrar_documento(v_caso, c_m2, 'ano', '2024', 'BALANCO', 0.99,
      'nome_arquivo', 'supabase_storage', 's/0176-delta-m.pdf', 'BAL.pdf', true, 'HASH-0176T-DM', 'ok');
    perform fn_registrar_documento(v_caso, c_s2, 'ano', '2024', 'BALANCO', 0.99,
      'nome_arquivo', 'supabase_storage', 's/0176-delta-s.pdf', 'BAL.pdf', true, 'HASH-0176T-DS', 'ok');

    v_r := fn_registrar_documento(v_caso, c_t2, 'ano', '2024', 'BALANCO', 0.99,
      'nome_arquivo', 'supabase_storage', 's/0176-delta-b1.pdf', 'BAL.pdf', true, 'HASH-0176T-DB1', 'ok');
    v_doc_b2a := (v_r->>'documento_id')::uuid;
    v_ver_b2a := (v_r->>'documento_versao_id')::uuid;
    v_balcao2 := (select entidade_id from documento where id = v_doc_b2a);

    perform fn_registrar_diagnostico(v_doc_b2a, v_ver_b2a, c_t2, true, 'BALANCO', 'anual', '12M24',
      'ok', null, 'resumo', 'justificativa', p_cnpj => c_cnpj_velho);
    perform teste_assert_0176(
      (select fn_cnpj_canonico(cnpj) from entidade where id = v_balcao2) = fn_cnpj_canonico(c_cnpj_velho),
      'PRÉ-CONDIÇÃO: o segundo balcão aprendeu o CNPJ VELHO');

    -- Segundo documento do MESMO balcão, nome mais completo, mas com um CNPJ
    -- DIFERENTE (o da OMNIBEAUTY, só para ser um CNPJ "estranho" a este
    -- balcão) — fn_entidade_aprender_cnpj devolve SEM tocar nada (guarda da
    -- 0169: nunca sobrescreve).
    v_r := fn_registrar_documento(v_caso, c_t2, 'ano', '2023', 'BALANCO', 0.99,
      'nome_arquivo', 'supabase_storage', 's/0176-delta-b2.pdf', 'BAL.pdf', true, 'HASH-0176T-DB2', 'ok');
    v_doc_b2b := (v_r->>'documento_id')::uuid;
    v_ver_b2b := (v_r->>'documento_versao_id')::uuid;

    perform fn_registrar_diagnostico(v_doc_b2b, v_ver_b2b, c_t2_completo, true, 'BALANCO', 'anual', '12M23',
      'ok', null, 'resumo', 'justificativa', p_cnpj => c_cnpj);

    -- ESTE É O ASSERT QUE REPROVA COM A 0176 DESLIGADA (medido nesta
    -- sessão): o balcão era renomeado para o nome mais completo com um
    -- evento `entidade_renomeada_por_cnpj` citando `{"cnpj": "<cnpj novo,
    -- estranho>"}`, enquanto `entidade.cnpj` continuava o VELHO.
    perform teste_assert_0176(
      (select razao_social from entidade where id = v_balcao2) = c_t2,
      'o balcão NÃO foi renomeado — o "aprender" não confirmou o CNPJ novo NESTA entidade, então '
        || 'o renomeio nem tentou rodar',
      coalesce((select razao_social from entidade where id = v_balcao2), '(nulo)'));

    perform teste_assert_0176(
      (select fn_cnpj_canonico(cnpj) from entidade where id = v_balcao2) = fn_cnpj_canonico(c_cnpj_velho),
      'e o CNPJ do balcão continua sendo o VELHO — nunca sobrescrito (0169)');

    perform teste_assert_0176(not exists (
        select 1 from evento_auditoria
         where entidade_ref = 'entidade:' || v_balcao2
           and acao in ('entidade_renomeada_por_cnpj', 'entidade_renomeio_recusado')),
      'e NENHUM evento de renomeio nasceu — nem sucesso nem recusa: o renomeio nem chegou a ser '
        || 'tentado com um CNPJ que não é desta entidade');
  end;

  raise notice '--- 4. ALTO: a pendência ambigua_respondida cita o NOME CORRENTE, não o apagado ---';
  -- Reusa o desenho da 0175 (dois balcões da OMNIBEAUTY convergindo) com um
  -- corte de nome adicional, para medir a pendência do SEGUNDO balcão depois
  -- da fusão.
  declare
    v_balcao3 uuid; v_balcao4 uuid; v_doc3 uuid; v_ver3 uuid; v_doc4 uuid; v_ver4 uuid;
    c_t3  constant text := 'OMNIBEAUTY DESENVOLVIMENTO E';
    c_t4  constant text := 'OMNIBEAUTY DESENVOLVIMENTO';
    v_desc text;
    v_pend_ent uuid;
  begin
    v_r := fn_registrar_documento(v_caso, c_t3, 'ano', '2024', 'BALANCO', 0.99,
      'nome_arquivo', 'supabase_storage', 's/0176-alto-b1.pdf', 'BAL.pdf', true, 'HASH-0176T-AB1', 'ok');
    v_doc3 := (v_r->>'documento_id')::uuid;
    v_ver3 := (v_r->>'documento_versao_id')::uuid;
    v_balcao3 := (select entidade_id from documento where id = v_doc3);

    v_r := fn_registrar_documento(v_caso, c_t4, 'ano', '2024', 'BALANCO', 0.99,
      'nome_arquivo', 'supabase_storage', 's/0176-alto-b2.pdf', 'BAL.pdf', true, 'HASH-0176T-AB2', 'ok');
    v_doc4 := (v_r->>'documento_id')::uuid;
    v_ver4 := (v_r->>'documento_versao_id')::uuid;
    v_balcao4 := (select entidade_id from documento where id = v_doc4);

    perform teste_assert_0176(v_balcao3 is distinct from v_balcao4,
      'PRÉ-CONDIÇÃO: dois balcões distintos nasceram (cortes diferentes do mesmo nome)');

    -- balcao3 aprende o CNPJ primeiro (sem fusão). CNPJ VÁLIDO (DV conferido
    -- por fn_cnpj_canonico) e DIFERENTE dos usados nos blocos anteriores
    -- deste arquivo — evitaria colidir com entidade_caso_cnpj_unico.
    perform fn_registrar_diagnostico(v_doc3, v_ver3, c_m, true, 'BALANCO', 'anual', '12M24',
      'ok', null, 'resumo', 'justificativa', p_cnpj => '55.667.788/0001-86');
    -- balcao4 traz o MESMO CNPJ pelo diagnóstico, nomeando SURUBIJU (exata
    -- única candidata) — dispara a fusão (balcao4 → balcao3) E a pendência
    -- entidade_ambigua_respondida, no MESMO diagnóstico.
    perform fn_registrar_diagnostico(v_doc4, v_ver4, c_s, true, 'BALANCO', 'anual', '12M24',
      'ok', null, 'resumo', 'justificativa', p_cnpj => '55.667.788/0001-86');

    perform teste_assert_0176(not exists (select 1 from entidade where id = v_balcao4),
      'PRÉ-CONDIÇÃO: balcao4 foi fundido em balcao3 (convergência da 0175, preservada)');

    select descricao, entidade_id into v_desc, v_pend_ent from pendencia
     where caso_id = v_caso and motivo = 'diagnostico:entidade_ambigua_respondida:' || v_doc4
       and estado <> 'resolvida';

    perform teste_assert_0176(v_pend_ent = v_balcao3,
      'a pendência aponta para o balcão SOBREVIVENTE (balcao3)');

    -- ESTE É O ASSERT QUE REPROVA COM A 0176 DESLIGADA (medido nesta sessão,
    -- rodando Supabase/test/balcao_ambiguo_e_cnpj.test.sql contra o estado
    -- da 0175): a descrição citava o nome do balcão FUNDIDO — que não existe
    -- MAIS na tabela entidade — em vez do nome corrente do sobrevivente.
    perform teste_assert_0176(
      v_desc like '%numa entidade própria ("' || (select razao_social from entidade where id = v_balcao3) || '")%',
      'e a descrição cita o NOME CORRENTE do sobrevivente — nunca um nome que já foi apagado',
      coalesce(v_desc, '(nulo)'));

    -- NÃO usa "not like c_t4": c_t4 ("OMNIBEAUTY DESENVOLVIMENTO") é PREFIXO
    -- de c_t3 ("OMNIBEAUTY DESENVOLVIMENTO E", o nome corrente do
    -- sobrevivente) — qualquer texto que cite c_t3 contém c_t4 como
    -- substring, então essa checagem daria falso positivo por desenho do
    -- próprio cenário. O que prova a correção é a citação ENTRE ASPAS do
    -- nome exato (checado acima); aqui só confirma que não é o nome exato
    -- COMPLETO do fundido, com aspas nas DUAS pontas.
    perform teste_assert_0176(v_desc not like '%("' || c_t4 || '")%',
      'e NÃO cita, entre aspas, o nome EXATO do balcão FUNDIDO (c_t4) — que não existe mais na '
        || 'tabela entidade — como se fosse o nome da entidade em que o documento foi registrado',
      coalesce(v_desc, '(nulo)'));
  end;

  raise notice 'BALCAO NAO ABSORVE CONFIRMADA OK — os cinco defeitos da revisão da 0175 seguem '
               'corrigidos, e a convergência balcão↔balcão continua intacta '
               '(Supabase/test/balcao_ambiguo_e_cnpj.test.sql)';
end $$;

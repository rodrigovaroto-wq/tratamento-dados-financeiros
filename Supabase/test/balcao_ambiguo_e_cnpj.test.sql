-- =============================================================================
-- 0175 — dentro do balcão ambíguo, o CNPJ decide antes do nome
--
-- OS NOMES SÃO OS REAIS DA OMNIBEAUTY (regra 4), com o MESMO CNPJ real
-- (36.193.378/0001-04) do caso bf0246bb-c93b-4d08-a7df-5d356c9d6275 ("teste
-- 143") — os mesmos usados em cnpj_identidade.test.sql, cnpj_renomeia.test.sql
-- e alias_truncado.test.sql. As DUAS variantes "balcão" (a bare "…DE" e a
-- ainda mais curta "…GESTAO", sem o "DE" final) são fixture: não são uma das
-- quatro linhas exatas do export do dono, mas são o MESMO nome real cortado
-- em mais um ponto — o algoritmo (`fn_mesma_entidade`, prefixo de tokens) é
-- o mesmo que produziu as quatro variantes originais, e é exatamente esse
-- corte adicional que faz nascerem DOIS balcões em vez de um só (ver o bloco
-- 0 abaixo, que prova as duas pré-condições de casamento antes de montar o
-- arranjo). Nenhuma fixture aqui simula o BUG — apenas o dado de entrada, e o
-- bug é o comportamento medido no bloco 2.
--
-- O QUE ESTE ARQUIVO MEDE:
--   0. pré-condição algorítmica: "…GESTAO" (sem "DE") casa com MARCAS e com
--      SURUBIJU tanto quanto "…DE" casa — e MARCAS × SURUBIJU continua sem
--      casar entre si (a mesma não-formação de grupo do resto da família
--      OMNIBEAUTY);
--   1. o ARRANJO REAL: MARCAS e SURUBIJU entram como empresas de verdade
--      (documentos próprios, pelo caminho normal de registro); os dois nomes
--      "balcão" entram DEPOIS, cada um pelo caminho normal também
--      (fn_registrar_documento), e cada um cria uma entidade NOVA marcada
--      ambígua, com pendência bloqueante — EXATAMENTE como a 0153/0162
--      criam, sem chamar nenhuma função de ambiguidade à mão;
--   2. O DEFEITO MEDIDO CONTRA O ESTADO DA 0174 (comentado no fim deste
--      arquivo o resultado sem a correção): os dois documentos, um em cada
--      balcão, trazem o MESMO CNPJ pelo diagnóstico — e SEM a 0175 os dois
--      balcões continuam INTACTOS, 4 entidades e 2 pendências abertas, sem
--      exceção nenhuma (ausência silenciosa, ao contrário do crash da 0174);
--   3. COM a correção: os dois balcões CONVERGEM em UM só — 4 entidades
--      caem para 3, o segundo balcão deixa de existir, e a pendência dele
--      fecha com o rastro de fn_fundir_entidade;
--   4. E o que NÃO converge, por desenho, com o número que sustenta a
--      asserção mais fraca declarada no MAPA: a pendência do balcão
--      SOBREVIVENTE continua aberta (o nome dele continua ambíguo — só
--      ganhou identidade fiscal), e ele mantém o próprio nome truncado
--      porque a guarda de homônima (0171) recusa adotar o nome de MARCAS ou
--      de SURUBIJU, que já existem como entidades de verdade com esses
--      nomes exatos.
-- =============================================================================

create or replace function teste_assert_balcao(p_cond boolean, p_nome text, p_detalhe text default null)
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
  c_cnpj  constant text := '36.193.378/0001-04';
  c_m     constant text := 'OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE MARCAS LTDA';
  c_s     constant text := 'OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE SURUBIJU';
  c_t     constant text := 'OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE';
  c_t2    constant text := 'OMNIBEAUTY DESENVOLVIMENTO E GESTAO';
  v_caso      uuid;
  v_r         jsonb;
  v_doc3      uuid; v_ver3 uuid; v_doc4 uuid; v_ver4 uuid;
  v_marcas    uuid; v_surubiju uuid; v_balcao1 uuid; v_balcao2 uuid;
  v_n         int;
  v_pend_n    int;
begin
  raise notice '--- 0. PRÉ-CONDIÇÃO ALGORÍTMICA: o corte extra cria a MESMA ambiguidade ---';
  -- Sem isto o arranjo abaixo não mede nada: se "…GESTAO" não casasse com as
  -- duas candidatas tanto quanto "…DE", o segundo balcão nem nasceria.
  perform teste_assert_balcao(
    fn_mesma_entidade(c_t2, c_m) and fn_mesma_entidade(c_t2, c_s)
    and fn_mesma_entidade(c_t, c_m) and fn_mesma_entidade(c_t, c_s),
    'as duas variantes "balcão" (…DE e …GESTAO) casam com MARCAS e com SURUBIJU');
  perform teste_assert_balcao(not fn_mesma_entidade(c_m, c_s),
    'e MARCAS × SURUBIJU continuam SEM casar entre si — é essa não-formação de grupo que faz '
      || 'o nome ambíguo virar balcão em vez de fundir (0168)');

  raise notice '--- 1. O ARRANJO REAL: dois balcões ambíguos nascidos de variantes do mesmo nome ---';
  v_caso := (fn_upsert_caso('0175 — dois balcoes, mesmo CNPJ'))::uuid;

  -- MARCAS e SURUBIJU entram como empresas de VERDADE, cada uma com o
  -- documento próprio, pelo caminho normal de registro.
  v_r := fn_registrar_documento(v_caso, c_m, 'ano', '2024', 'BALANCO', 0.99,
    'nome_arquivo', 'supabase_storage', 's/marcas.pdf', 'BAL.pdf', true, 'HASH-0175-M', 'ok');
  v_marcas := (select entidade_id from documento where id = (v_r->>'documento_id')::uuid);
  v_r := fn_registrar_documento(v_caso, c_s, 'ano', '2024', 'BALANCO', 0.99,
    'nome_arquivo', 'supabase_storage', 's/surubiju.pdf', 'BAL.pdf', true, 'HASH-0175-S', 'ok');
  v_surubiju := (select entidade_id from documento where id = (v_r->>'documento_id')::uuid);
  perform teste_assert_balcao(v_marcas is distinct from v_surubiju,
    'PRÉ-CONDIÇÃO: MARCAS e SURUBIJU são duas empresas distintas — não casam entre si (0168)');

  -- Primeiro documento "balcão": o nome bare "…DE" casa com as DUAS acima e
  -- não forma grupo com elas — cria uma entidade NOVA marcada ambígua, com
  -- pendência bloqueante, pelo caminho NORMAL (o gatilho trg_entidade_ambigua,
  -- ninguém chama fn_pendencia_entidade_ambigua à mão).
  v_r := fn_registrar_documento(v_caso, c_t, 'ano', '2024', 'BALANCO', 0.99,
    'nome_arquivo', 'supabase_storage', 's/balcao1.pdf', 'BAL.pdf', true, 'HASH-0175-B1', 'ok');
  v_doc3 := (v_r->>'documento_id')::uuid;
  v_ver3 := (v_r->>'documento_versao_id')::uuid;
  v_balcao1 := (select entidade_id from documento where id = v_doc3);

  perform teste_assert_balcao(
    v_balcao1 is distinct from v_marcas and v_balcao1 is distinct from v_surubiju,
    'o primeiro balcão nasce como entidade PRÓPRIA — não cai em MARCAS nem em SURUBIJU (0153)');
  perform teste_assert_balcao(fn_entidade_e_balcao_ambiguo(v_caso, v_balcao1),
    'e é reconhecido como balcão ambíguo (0162) — pendência entidade_ambigua aberta');

  -- Segundo documento "balcão": um corte AINDA MAIS curto do MESMO nome real,
  -- que TAMBÉM casa com as duas e não forma grupo — cria uma SEGUNDA entidade
  -- ambígua, distinta da primeira (o casamento exato do ramo (1) não se
  -- aplica: o texto é diferente do primeiro balcão).
  v_r := fn_registrar_documento(v_caso, c_t2, 'ano', '2024', 'BALANCO', 0.99,
    'nome_arquivo', 'supabase_storage', 's/balcao2.pdf', 'BAL.pdf', true, 'HASH-0175-B2', 'ok');
  v_doc4 := (v_r->>'documento_id')::uuid;
  v_ver4 := (v_r->>'documento_versao_id')::uuid;
  v_balcao2 := (select entidade_id from documento where id = v_doc4);

  perform teste_assert_balcao(
    v_balcao2 is distinct from v_balcao1
    and v_balcao2 is distinct from v_marcas and v_balcao2 is distinct from v_surubiju,
    'o segundo balcão TAMBÉM nasce como entidade própria, DISTINTA do primeiro balcão',
    format('balcao1=%s balcao2=%s', v_balcao1, v_balcao2));
  perform teste_assert_balcao(fn_entidade_e_balcao_ambiguo(v_caso, v_balcao2),
    'e também é reconhecido como balcão ambíguo — DOIS balcões abertos ao mesmo tempo, o '
      || 'cenário real medido em produção');

  select count(*) into v_n from entidade where caso_id = v_caso;
  perform teste_assert_balcao(v_n = 4,
    'PRÉ-CONDIÇÃO FINAL: quatro entidades no caso — MARCAS, SURUBIJU e os DOIS balcões',
    format('%s entidade(s)', v_n));

  select count(*) into v_pend_n from pendencia
    where caso_id = v_caso and motivo like 'entidade_ambigua:%' and estado <> 'resolvida';
  perform teste_assert_balcao(v_pend_n = 2,
    'e DUAS pendências entidade_ambigua bloqueantes abertas — exatamente o sintoma relatado '
      || '(evento_auditoria com DOIS entidade_ambigua novos)',
    format('%s pendência(s)', v_pend_n));

  raise notice '--- 2. O MESMO CNPJ chega pelo diagnóstico de CADA balcão ---';
  -- Cada documento está no SEU balcão, e o diagnóstico de conteúdo NOMEIA o
  -- próprio balcão (fn_mesma_entidade casa por construção, 0162) — o mesmo
  -- jeito como o CNPJ chega em QUALQUER lugar do sistema desde a 0169: pelo
  -- ÚNICO caminho garantido para todo documento.
  perform fn_registrar_diagnostico(v_doc3, v_ver3, c_m, true, 'BALANCO', 'anual', '12M24',
    'ok', null, 'resumo', 'justificativa', p_cnpj => c_cnpj);
  perform fn_registrar_diagnostico(v_doc4, v_ver4, c_s, true, 'BALANCO', 'anual', '12M24',
    'ok', null, 'resumo', 'justificativa', p_cnpj => c_cnpj);

  perform teste_assert_balcao(true, 'os dois diagnósticos rodaram sem exceção nenhuma');

  raise notice '--- 3. ASSERT CENTRAL: os dois balcões CONVERGEM em UM só ---';
  -- ESTE É O BLOCO QUE REPROVA COM A 0175 DESLIGADA: sem ela, `v_n` continua
  -- 4 (nenhuma fusão) e `v_balcao2` continua existindo — medido contra o
  -- estado da 0174 antes de escrever a correção (ver o comentário no fim
  -- deste arquivo com os números exatos).
  select count(*) into v_n from entidade where caso_id = v_caso;
  perform teste_assert_balcao(v_n = 3,
    'as QUATRO entidades caem para TRÊS — os dois balcões convergiram em um só',
    format('%s entidade(s) no caso (esperado 3)', v_n));

  perform teste_assert_balcao(not exists (select 1 from entidade where id = v_balcao2),
    'o segundo balcão não existe mais — foi fundido no primeiro (que aprendeu o CNPJ primeiro)');

  perform teste_assert_balcao(
    (select fn_cnpj_canonico(cnpj) from entidade where id = v_balcao1) = fn_cnpj_canonico(c_cnpj),
    'e o balcão sobrevivente ficou com o CNPJ aprendido');

  perform teste_assert_balcao(exists (
      select 1 from evento_auditoria
       where acao = 'entidade_fundida'
         and entidade_ref = 'entidade:' || v_balcao1
         and (antes->>'entidade_id') = v_balcao2::text),
    'com o rastro de fn_fundir_entidade — a fusão pela porta do balcão ambíguo não é mais '
      || 'calada que a fusão pelas outras portas (0174/0169)');

  raise notice '--- 4. ASSERÇÃO MAIS FRACA, para o comportamento que NÃO converge por desenho ---';
  -- Também vale sozinha (regra 7): se por algum motivo o assert central acima
  -- precisasse ser revisto, este é o MÍNIMO que a correção promete — deixar
  -- de haver DUAS pendências entidade_ambigua abertas ao mesmo tempo.
  select count(*) into v_pend_n from pendencia
    where caso_id = v_caso and motivo like 'entidade_ambigua:%' and estado <> 'resolvida';
  perform teste_assert_balcao(v_pend_n = 1,
    'de DUAS pendências entidade_ambigua abertas para UMA — a do balcão sobrevivente, cujo '
      || 'NOME continua ambíguo (só ganhou identidade fiscal), não a de quem foi fundido',
    format('%s pendência(s) aberta(s) (esperado 1)', v_pend_n));

  perform teste_assert_balcao(fn_entidade_e_balcao_ambiguo(v_caso, v_balcao1),
    'e essa pendência que sobra é exatamente a do SOBREVIVENTE — o CNPJ resolve a IDENTIDADE '
      || 'da empresa, não a pergunta "qual é o nome certo dela", que continua em aberto');

  perform teste_assert_balcao(
    (select razao_social from entidade where id = v_balcao1) = c_t,
    'e o sobrevivente NÃO adotou o nome de MARCAS nem de SURUBIJU — a guarda de homônima '
      || '(0171) recusa, porque as duas já existem como entidades de verdade com esses nomes '
      || 'exatos (ver Supabase/test/cnpj_renomeia.test.sql, bloco 10, para a mesma guarda)',
    coalesce((select razao_social from entidade where id = v_balcao1), '(nulo)'));

  perform teste_assert_balcao(exists (
      select 1 from evento_auditoria
       where acao = 'entidade_renomeio_recusado' and entidade_ref = 'entidade:' || v_balcao1),
    'e a recusa de renomeio fica com rastro, pela mesma fn_entidade_talvez_renomear (0173)');

  raise notice 'BALCAO AMBIGUO E CNPJ OK — dois balcoes da mesma empresa convergem quando o '
               'CNPJ chega, mesmo sem o nome nunca resolver a ambiguidade sozinho';
end $$;

-- =============================================================================
-- MEDIDO COM A CORREÇÃO DESLIGADA (contra o estado da 0174, antes de escrever
-- esta migration, rodando o arranjo acima manualmente): SEM o bloco novo
-- dentro de `fn_registrar_diagnostico` (o `if p_cnpj is not null then
-- v_entidade_id := fn_entidade_aprender_cnpj(...); ... end if;` que a 0175
-- acrescenta antes da lógica de nome), o resultado depois dos dois
-- diagnósticos era:
--
--   entidades no caso:                4 (esperado 3)
--   balcão 2 ainda existe:            true (esperado false)
--   pendências entidade_ambigua:      2 abertas (esperado 1)
--   cnpj do balcão 1:                 NULL (nunca aprendido)
--
-- Os QUATRO asserts do bloco 3 (a partir de "as QUATRO entidades caem para
-- TRÊS") reprovam nessa configuração — o primeiro a rodar (`v_n = 3`) já para
-- a execução com `FALHOU: as QUATRO entidades caem para TRÊS — os dois
-- balcões convergiram em um só  — 4 entidade(s) no caso (esperado 3)`, porque
-- `raise exception` interrompe o bloco `do $$ ... $$` no primeiro assert que
-- falha (é o mesmo formato de teste_assert_* usado em todo Supabase/test/).
-- Religada a correção, os 18 asserts deste arquivo passam.
-- =============================================================================

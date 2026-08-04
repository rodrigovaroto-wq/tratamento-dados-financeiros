-- =============================================================================
-- Testes da Modelagem contra o CASO REAL de produção (0102, e a trava da 0042)
--
-- Roda sobre `db/test/fixture_modelagem_v35.sql`, que é o caso "Teste v35"
-- reconstruído a partir da captura da tela em produção — 249 linhas lógicas, 760
-- ocorrências, 14 documentos, com os rótulos que o extrator REALMENTE escreveu.
--
-- SÃO TRÊS COISAS DIFERENTES SENDO TRAVADAS AQUI, e vale separar:
--
--   1. CLASSIFICAÇÃO CONTRA RÓTULO REAL. `fn_papel_linha` nunca tinha sido
--      conferida contra rótulo de produção — só contra rótulo de fixture escrito
--      à mão. A 0042 registra o preço disso: `fn_mes_do_rotulo` passava na
--      fixture ("jan/2024") e voltava vazia na extração real ("Faturamento
--      Janeiro"). Aqui os quatro papéis são contados contra os 249 rótulos reais.
--   2. VERSÃO VIGENTE (0102). Reextração criava `documento_versao` nova e as
--      ocorrências da versão SUPERADA continuavam entrando no agrupamento.
--   3. O TETO DE TEMPO (0101), agora medido na forma real do caso e não só na
--      sintética de 55 rótulos de `modelagem_escala.test.sql`.
--
-- ARMADILHA HERDADA de modelagem_escala.test.sql, e que continua valendo: `set
-- local statement_timeout` DENTRO de um bloco `DO` NÃO tem efeito sobre o próprio
-- bloco — o `DO` é UMA instrução e o cronômetro já começou. O teto tem de ser
-- armado FORA, no nível do psql. Daí os blocos separados.
-- =============================================================================

\set ON_ERROR_STOP on

\i db/test/fixture_modelagem_v35.sql

create or replace function teste_assert_v35(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_ok then
    raise notice 'ok    %', p_nome;
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

-- -----------------------------------------------------------------------------
-- 1. A classificação dos 249 rótulos REAIS sai exatamente como a produção mostrou
-- -----------------------------------------------------------------------------
do $$
declare
  v_caso uuid := current_setting('v35.caso')::uuid;
  v_n    int;
  v_p    text;
  v_esp  jsonb;
  v_obt  jsonb;
begin
  raise notice '--- 1. papel dos 249 rótulos reais, contra o que a tela de produção mostrou ---';

  select count(*) into v_n from fn_linhas_para_modelagem(v_caso);
  perform teste_assert_v35(v_n = 249,
    'as 760 ocorrências agrupam nas 249 linhas lógicas que a captura mostra', v_n::text);

  -- Os quatro números vêm da captura de 04/08/2026 (README da captura e sessão 32
  -- do HANDOFF): 203 contas, 28 subtotais, 12 séries mensais, 6 derivados.
  --
  -- MUDAR UM DESTES NÚMEROS É PERMITIDO E ÀS VEZES CERTO — `Arrendamentos` e
  -- `Provisões` são cabeçalho de grupo tratado como conta, e o HANDOFF mantém
  -- isso aberto. O que este assert impede é mudar sem querer: quem reclassificar
  -- um rótulo real tem de vir aqui e dizer qual, no diff.
  v_esp := jsonb_build_object('conta', 203, 'subtotal', 28, 'serie_mensal', 12, 'derivado', 6);
  select jsonb_object_agg(papel, n) into v_obt
    from (select papel, count(*) n from fn_linhas_para_modelagem(v_caso) group by papel) x;
  perform teste_assert_v35(v_obt = v_esp,
    'a classificação bate campo a campo com a produção (203/28/12/6)',
    'obtido ' || v_obt::text || ', esperado ' || v_esp::text);

  raise notice '--- 2. e os rótulos que custaram a acertar, um por um ---';

  -- O total do grupo SEM a palavra "total" (0034/0042). Se `fn_rotulo_estrutural`
  -- regredir, ATIVO volta a ser conta projetável e a dupla contagem renasce.
  select papel into v_p from fn_linhas_para_modelagem(v_caso)
   where rotulo_norm = fn_normalizar_texto('ATIVO') limit 1;
  perform teste_assert_v35(v_p = 'subtotal', 'ATIVO é subtotal (total do grupo sem a palavra "total")', v_p);

  select papel into v_p from fn_linhas_para_modelagem(v_caso)
   where rotulo_norm = fn_normalizar_texto('TOTAL DO ATIVO') limit 1;
  perform teste_assert_v35(v_p = 'subtotal', 'TOTAL DO ATIVO é subtotal', v_p);

  -- O rótulo que a fixture antiga escondia: `left(chave,3)` dava "fat".
  select papel into v_p from fn_linhas_para_modelagem(v_caso)
   where rotulo_norm = fn_normalizar_texto('Faturamento Janeiro') limit 1;
  perform teste_assert_v35(v_p = 'serie_mensal',
    'Faturamento Janeiro é série mensal — o rótulo REAL, não "jan/2024"', v_p);

  select count(*) into v_n from fn_linhas_para_modelagem(v_caso) where papel = 'serie_mensal';
  perform teste_assert_v35(v_n = 12, 'os 12 meses entram como série mensal, nem 11 nem 13', v_n::text);

  select papel into v_p from fn_linhas_para_modelagem(v_caso)
   where rotulo_norm = fn_normalizar_texto('Índice de liquidez corrente') limit 1;
  perform teste_assert_v35(v_p = 'derivado', 'Índice de liquidez corrente é derivado', v_p);

  -- E uma conta de verdade continua conta: errar para subtotal ESCONDE a linha do
  -- analista, que é o outro lado do defeito e não dá erro nenhum.
  select papel into v_p from fn_linhas_para_modelagem(v_caso)
   where rotulo_norm = fn_normalizar_texto('Vendas de produtos - mercado interno') limit 1;
  perform teste_assert_v35(v_p = 'conta',
    'Vendas de produtos - mercado interno segue projetável', coalesce(v_p, '(não achou o rótulo)'));

  raise notice '--- 3. a curva de sazonalidade sai dos rótulos reais, com 12 meses ---';
  select count(*) into v_n from fn_sazonalidade_do_caso(v_caso);
  perform teste_assert_v35(v_n = 12,
    'a curva vem completa a partir de "Faturamento <mês>" (era vazia com left(chave,3))', v_n::text);

  raise notice '--- 4. o valor exibido conserva o SINAL (0042) ---';
  -- Redutor exibido como positivo engana quem escolhe a premissa, e a coluna é
  -- justamente a que o analista usa para reconhecer a conta.
  perform teste_assert_v35(
    (select valor_ultimo from fn_linhas_para_modelagem(v_caso)
      where rotulo_norm = fn_normalizar_texto('PREJUÍZO LÍQUIDO DO EXERCÍCIO') limit 1) < 0,
    'PREJUÍZO LÍQUIDO DO EXERCÍCIO continua negativo, não |valor|');
end $$;

-- -----------------------------------------------------------------------------
-- 2. VERSÃO VIGENTE (0102) — reextração não soma, substitui
-- -----------------------------------------------------------------------------
do $$
declare
  v_caso  uuid := current_setting('v35.caso')::uuid;
  v_doc   uuid;
  v_ver   uuid;
  v_n0    bigint;
  v_v0    numeric;
  v_n1    bigint;
  v_v1    numeric;
  v_k     bigint;
  v_diag  jsonb;
  v_papel text;
begin
  raise notice '--- 5. uma REEXTRAÇÃO não pode somar ocorrência nem ditar o valor ---';

  select n_ocorrencias, valor_ultimo into v_n0, v_v0
    from fn_linhas_para_modelagem(v_caso)
   where rotulo_norm = fn_normalizar_texto('Estoques') limit 1;
  perform teste_assert_v35(v_n0 is not null, 'a linha Estoques existe na fixture real', v_n0::text);

  -- A versão nova de um documento que JÁ tem extração: é o que a 0026 cria em
  -- toda reextração. O valor é absurdo de propósito — com o defeito ligado ele
  -- ganha o `max(abs())` e aparece na tela.
  --
  -- `Estoques` aparece em VÁRIOS documentos do caso (é o normal: balanço,
  -- balancete, combinado). Reextrair UM documento não zera a linha, substitui a
  -- contribuição DAQUELE documento — então o número esperado depois é
  -- `antes − k + 1`, onde k é o que a versão superada trazia. Escrever "= 1" aqui
  -- seria um número mágico que passaria por acidente com outro fixture.
  select dv.documento_id into v_doc
    from documento_versao dv
    join documento d on d.id = dv.documento_id
    join campo_extraido ce on ce.documento_versao_id = dv.id
   where d.caso_id = v_caso and ce.chave = 'Estoques'
   limit 1;

  select count(*) into v_k
    from campo_extraido ce
   where ce.documento_versao_id = fn_versao_com_extracao(v_doc)
     and ce.chave = 'Estoques' and ce.valor_num is not null;
  perform teste_assert_v35(v_k > 0, 'a versão que vai ser superada trazia ocorrência de Estoques', v_k::text);

  insert into documento_versao(documento_id, n_versao, origem_arquivo, arquivo_ref, hash, legibilidade)
  select v_doc, max(n_versao) + 1, 'supabase_storage', 'v35/estoques-reextraido.pdf',
         'HASH-V35-REEXTRAIDO', 'ok'
    from documento_versao where documento_id = v_doc
  returning id into v_ver;

  insert into campo_extraido(documento_versao_id, chave, valor_num, unidade, moeda,
                             secao_canonica, confianca, ordem)
  values (v_ver, 'Estoques', 777777, 'milhar', 'BRL', 'ativo_circulante', 0.99, 1);

  select n_ocorrencias, valor_ultimo into v_n1, v_v1
    from fn_linhas_para_modelagem(v_caso)
   where rotulo_norm = fn_normalizar_texto('Estoques') limit 1;

  -- Com o defeito ligado seria `antes + 1` (a versão superada continua somando).
  -- Corrigido, é `antes − k + 1`: a contribuição da versão velha SAI e a da nova
  -- entra. A diferença entre as duas expressões é exatamente o defeito.
  perform teste_assert_v35(v_n1 = v_n0 - v_k + 1,
    'a reextração SUBSTITUI a contribuição do documento em vez de somar a ela',
    'antes ' || v_n0::text || ', versão superada trazia ' || v_k::text ||
    ', depois ' || v_n1::text || ' (com o defeito seria ' || (v_n0 + 1)::text || ')');
  perform teste_assert_v35(v_v1 = 777777,
    'e o valor é o da versão vigente, não o maior módulo entre as duas', v_v1::text);

  -- A GUARDA tem de ver o mesmo que a tela (0100) — a discordância entre as duas
  -- é o que derrubava o "aplicar em lote".
  --
  -- HONESTIDADE SOBRE O QUE ESTE ASSERT PROVA: ele NÃO prova o filtro de versão da
  -- guarda. Rodei com o filtro removido só dela e este assert PASSOU, porque o
  -- papel é função de (chave, tipo do documento) e a versão superada pertence ao
  -- mesmo documento — o cabeçalho da 0102 declara isso por extenso. O que ele
  -- guarda é o invariante da 0100 contra OUTRAS regressões (a queda de seção, a
  -- prioridade de papel), e isso ele guarda de verdade.
  select papel into v_papel from fn_linhas_para_modelagem(v_caso)
   where rotulo_norm = fn_normalizar_texto('Estoques') limit 1;
  perform teste_assert_v35(
    fn_papel_do_rotulo_no_caso(v_caso, fn_normalizar_texto('Estoques'), 'ativo_circulante') = v_papel,
    'a guarda de papel concorda com a tela depois da reextração (0100 + 0102)',
    'guarda ' || coalesce(fn_papel_do_rotulo_no_caso(v_caso, fn_normalizar_texto('Estoques'),
      'ativo_circulante'), '(null)') || ', tela ' || coalesce(v_papel, '(null)'));

  raise notice '--- 6. o diagnóstico NOMEIA a versão superada em vez de escondê-la ---';
  v_diag := fn_diagnostico_modelagem(v_caso);
  perform teste_assert_v35((v_diag->>'ocorrencias_superadas')::int > 0,
    'fn_diagnostico_modelagem reporta as ocorrências de versão superada', v_diag::text);
  perform teste_assert_v35((v_diag->>'documentos_com_versao_superada')::int = 1,
    'e diz em QUANTOS documentos isso acontece', v_diag::text);
  perform teste_assert_v35(
    (v_diag->'correcoes_instaladas'->>'fn_linhas_para_modelagem')::boolean,
    'e confirma que a correção da 0102 está instalada no banco (merge não é apply)', v_diag::text);

  raise notice '--- 7. versão REGISTRADA e ainda não extraída NÃO apaga a tela ---';
  -- É a janela entre fn_registrar_documento e fn_registrar_campos_extraidos. Com
  -- `max(n_versao)` puro em vez de "última COM extração", a tela ficaria em branco
  -- aqui — exibindo "este caso não tem linha extraída" num caso cheio, que é o
  -- sintoma que a 0101 e a 0102 existem para matar.
  v_k := v_n1;   -- o que a tela mostra AGORA, antes da versão vazia entrar

  insert into documento_versao(documento_id, n_versao, origem_arquivo, arquivo_ref, hash, legibilidade)
  select v_doc, max(n_versao) + 1, 'supabase_storage', 'v35/sem-extracao.pdf',
         'HASH-V35-SEM-EXTRACAO', 'ok'
    from documento_versao where documento_id = v_doc;

  select n_ocorrencias into v_n1 from fn_linhas_para_modelagem(v_caso)
   where rotulo_norm = fn_normalizar_texto('Estoques') limit 1;
  perform teste_assert_v35(v_n1 = v_k,
    'a linha continua igual com a versão vazia registrada por cima',
    'antes ' || v_k::text || ', depois ' || coalesce(v_n1::text, '(sumiu)'));
  perform teste_assert_v35(
    (select count(*) from fn_linhas_para_modelagem(v_caso)) > 200,
    'e o caso NÃO virou "sem linha extraída" por causa de uma versão vazia',
    (select count(*)::text from fn_linhas_para_modelagem(v_caso)));
end $$;

-- -----------------------------------------------------------------------------
-- 3. O TETO DE TEMPO, na forma real do caso.
--
-- O teto vem armado do psql, fora do `DO`, e é o próprio Postgres que reprova. Não
-- há número mágico de milissegundos comparado com relógio de CI: ou cabe nos 8 s
-- que o Supabase impõe ao papel `authenticated`, ou não cabe. Com a 0101+0102 a
-- medição na fixture real é ~640 ms para cada função — uma ordem de grandeza de
-- folga, então isto não é teste instável.
--
-- E a página chama AS DUAS no mesmo `Promise.all`, concorrentes: a folga precisa
-- caber duas vezes, o que é a outra razão para não medir contra 8 s no limite.
--
-- O QUE ESTE BLOCO PEGA, MEDIDO E NÃO SUPOSTO. Religando o par PRÉ-0101 inteiro
-- (leitor lento + conferência que o executa cinco vezes) sobre esta fixture, as
-- três medições que fiz deram `canceling statement due to statement timeout` —
-- 3 de 3. Religando só a conferência pré-0101 sobre o leitor rápido da 0102, dá
-- 1,7 s sem vínculo e 2,3 s com 202 vínculos: **passa**. Então este bloco pega
-- regressão do LEITOR, que é o custo dominante; quem pega a conferência
-- sozinha, com margem de 12,3 s contra 8 s, é `modelagem_escala.test.sql`, na
-- fixture sintética de 55 rótulos. Os dois arquivos se cobrem, e nenhum dos dois
-- cobre tudo — daí valerem os dois.
-- -----------------------------------------------------------------------------
set statement_timeout = '8s';

do $$
declare
  v_caso uuid := current_setting('v35.caso')::uuid;
  v_r    jsonb;
  v_n    int;
begin
  raise notice '--- 8. as duas funções da tela cabem no teto de 8s do Supabase ---';

  select count(*) into v_n from fn_linhas_para_modelagem(v_caso);
  perform teste_assert_v35(v_n > 200,
    'fn_linhas_para_modelagem responde dentro do teto na forma real do caso', v_n::text);

  v_r := fn_conferir_modelagem(v_caso);
  perform teste_assert_v35(v_r is not null and (v_r->>'linhas_do_caso')::int > 200,
    'fn_conferir_modelagem responde dentro do teto (era 9,3s em produção: cancelada, '
    'e a tela lia o cancelamento como caso vazio)', coalesce(v_r::text, '(null)'));

  -- Rápida E certa: a conferência conta a mesma população que a tela mostra.
  perform teste_assert_v35(
    (v_r->>'linhas_do_caso')::int = (select count(*) from fn_linhas_para_modelagem(v_caso)
                                      where papel = 'conta'),
    'e a conferência conta exatamente as linhas projetáveis que a tela lista', v_r::text);

  raise notice 'TODOS OS TESTES DA MODELAGEM v35 PASSARAM';
end $$;

set statement_timeout = 0;

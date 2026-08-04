-- Teste de ESCALA da tela de Modelagem (db/migrations/0101).
-- Rodar via db/test/run.sh (que aplica as migrations antes).
--
-- O QUE ESTE ARQUIVO TRAVA, e por que ele não é um teste de desempenho comum.
--
-- Na rodada de 04/08/2026 a seção 3 anunciou "Este caso ainda não tem linha
-- extraída com valor" num caso com 760 ocorrências. Não faltava dado nem
-- migration: `fn_conferir_modelagem` levava 9,3 s, o Supabase cancela em 8 s
-- (`statement_timeout` do papel `authenticated`), e a chamada voltava
--
--     canceling statement due to statement timeout
--
-- Ou seja: o limite de tempo NÃO é detalhe de performance neste sistema — é uma
-- regra de correção. Passar dele não deixa a tela lenta, deixa a tela MENTINDO,
-- porque uma consulta cancelada chega ao portal como ausência de dado.
--
-- Por isso o teste roda com `statement_timeout` ARMADO no mesmo teto da produção
-- e deixa o próprio Postgres reprovar. Não há número mágico de milissegundos
-- comparado com relógio de máquina de CI: ou cabe no teto que o Supabase impõe,
-- ou não cabe. Com a 0101 a folga é de duas ordens de grandeza (~100 ms contra
-- 8.000), então isto não é um teste instável — é um teste que só falha quando o
-- defeito volta.
--
-- ARMADILHA QUE ESTE ARQUIVO JÁ CAIU, e que fica registrada porque custa uma
-- rodada inteira descobrir: `set local statement_timeout` DENTRO de um bloco `DO`
-- NÃO tem efeito sobre o próprio bloco. O `DO` é UMA instrução, o cronômetro já
-- começou a contar quando ele foi despachado, e mudar o parâmetro no meio não
-- rearma nada. Na primeira versão deste teste o teto estava lá, parecia
-- funcionar, e o teste passava com o defeito RELIGADO — 9,5 s medidos e nenhuma
-- reprovação. O teto tem de ser posto FORA, no nível do psql, para valer sobre a
-- instrução que executa as funções. Daí os dois blocos: um monta a fixture sem
-- teto, outro exercita as funções com o teto armado.
--
-- O caso montado tem a FORMA do v35: 14 documentos, o mesmo rótulo repetido entre
-- eles (é o que cria linha lógica com várias ocorrências), várias seções e
-- vínculos já gravados — que é o que fazia `fn_conferir_modelagem` reexecutar a
-- função inteira uma vez por vínculo.

\set ON_ERROR_STOP on

create or replace function teste_assert_escala(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_ok then
    raise notice 'ok    %', p_nome;
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

do $$
declare
  v_caso uuid;
  v_ver  uuid;
  v_r    jsonb;
  v_lote jsonb;
  v_n    int;
  v_secoes text[] := array['ativo_circulante','ativo_nao_circulante','passivo_circulante',
                           'passivo_nao_circulante','patrimonio_liquido','receita_bruta',
                           'custos','despesas_operacionais','atividades_operacionais'];
begin
  raise notice '--- 1. um caso do TAMANHO do v35: 14 documentos, 770 ocorrências ---';
  -- Nome ÚNICO por execução: `fn_upsert_caso` reaproveita o caso pelo nome, e um
  -- segundo `run.sh` no mesmo banco somaria mais 14 documentos ao caso anterior —
  -- a contagem daria 1540 e o teste reprovaria por motivo errado (foi o que
  -- aconteceu ao escrever este arquivo). O banco do run.sh é descartável, mas o
  -- teste não pode depender disso para estar certo.
  v_caso := (fn_upsert_caso('Escala da modelagem ' || clock_timestamp()::text))::uuid;
  for d in 1..14 loop
    v_r := fn_registrar_documento(v_caso, 'ESCALA LTDA.', 'anual', '2025', 'BALANCO', 0.95,
      'nome_arquivo', 'supabase_storage', 'e/'||d||'.pdf', 'BP '||d||'.pdf', true,
      'HASH-ESCALA-'||d, 'ok');
    v_ver := (v_r->>'documento_versao_id')::uuid;
    v_lote := '[]'::jsonb;
    for i in 1..55 loop
      v_lote := v_lote || jsonb_build_object(
        'ordem', i,
        'chave', 'Conta analitica numero '||i,
        'valor_num', (1000 + (i*37) % 500)::text,
        'unidade', 'milhar', 'moeda', 'BRL', 'confianca', '0.97',
        'secao_canonica', v_secoes[1 + (i % array_length(v_secoes, 1))]);
    end loop;
    perform fn_registrar_campos_extraidos(v_ver, v_lote, 'N2');
  end loop;

  select count(*) into v_n
  from campo_extraido ce
  join documento_versao dv on dv.id = ce.documento_versao_id
  join documento d on d.id = dv.documento_id
  where d.caso_id = v_caso and ce.valor_num is not null;
  perform teste_assert_escala(v_n = 770, 'o caso tem 770 ocorrências extraídas', v_n::text);

  -- Vínculos gravados: é o que fazia a conferência reexecutar a função por linha.
  perform fn_ativar_premissa(v_caso, 'CRESC_REAL', jsonb_build_object('2026', 5), 'digitado', 'escala');
  perform fn_aplicar_premissa_em_lote(v_caso, 'receita_bruta', 'CRESC_REAL', 'escala');
  perform fn_aplicar_premissa_em_lote(v_caso, 'ativo_circulante', 'CRESC_REAL', 'escala');
  perform fn_aplicar_premissa_em_lote(v_caso, 'custos', 'CRESC_REAL', 'escala');

  -- O caso viaja para o bloco seguinte por parâmetro de sessão: o teto precisa
  -- ser armado ENTRE os dois, fora de qualquer `DO`.
  perform set_config('escala.caso', v_caso::text, false);
  raise notice 'fixture montada — %', v_caso;
end $$;

-- O TETO, no nível do psql: é a instrução `DO` abaixo que ele cronometra.
set statement_timeout = '8s';

do $$
declare
  v_caso uuid := current_setting('escala.caso')::uuid;
  v_r    jsonb;
  v_n    int;
begin
  raise notice '--- 2. as duas funções da tela cabem no teto de 8s do Supabase ---';

  select count(*) into v_n from fn_linhas_para_modelagem(v_caso);
  perform teste_assert_escala(v_n = 55,
    'fn_linhas_para_modelagem responde dentro do teto, e agrupa as 770 ocorrências em 55 linhas',
    v_n::text);

  v_r := fn_conferir_modelagem(v_caso);
  perform teste_assert_escala(v_r is not null and (v_r->>'linhas_do_caso')::int = 55,
    'fn_conferir_modelagem responde dentro do teto (era 9,3s: cancelada, e a tela lia como caso vazio)',
    coalesce(v_r::text, '(null)'));

  -- E a conferência tem de continuar CERTA, não só rápida: as três seções que
  -- receberam lote estão contadas na cobertura.
  perform teste_assert_escala((v_r->>'linhas_com_premissa')::int > 0,
    'e a conferência continua contando a cobertura (rápida E certa)', v_r::text);

  raise notice '--- 3. o papel é propriedade do RÓTULO, e não muda com a repetição ---';
  -- 14 ocorrências do mesmo rótulo têm de produzir UMA linha lógica com UM papel.
  -- Se alguém voltar a calcular papel por ocorrência sem agrupar, isto continua
  -- passando — mas o teto do bloco 2 reprova. Os dois asserts se cobrem.
  select count(distinct papel) into v_n from fn_linhas_para_modelagem(v_caso);
  perform teste_assert_escala(v_n >= 1, 'as linhas têm papel atribuído', v_n::text);

  select n_ocorrencias into v_n from fn_linhas_para_modelagem(v_caso)
   where chave = 'Conta analitica numero 1';
  perform teste_assert_escala(v_n = 14,
    'a linha lógica junta as 14 ocorrências do mesmo rótulo', v_n::text);

  raise notice 'TODOS OS TESTES DE ESCALA DA MODELAGEM PASSARAM';
end $$;

set statement_timeout = 0;

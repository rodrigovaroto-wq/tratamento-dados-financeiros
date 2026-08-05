-- =============================================================================
-- DIAGNÓSTICO DE AMBIENTE da tela de Modelagem — rodar no SQL Editor do Supabase
--
-- POR QUE ESTE ARQUIVO EXISTE. Depois da `0101` e da `0102` aplicadas e
-- CONFIRMADAS (`fn_diagnostico_modelagem` devolveu `correcoes_instaladas` tudo
-- `true`, 249 linhas, 760 ocorrências, zero versão superada), a tela CONTINUOU
-- mostrando, nas duas RPC da Modelagem:
--
--     canceling statement due to statement timeout
--
-- Isso separa duas coisas que até aqui estavam juntas: **a lógica SQL não é mais
-- o gargalo, e o que sobra é ambiente.**
--
-- O QUE FOI MEDIDO para poder afirmar isso, contra `db/test/fixture_modelagem_v35.sql`
-- — que é reconstrução FIEL do caso (mesmas 249 linhas, mesmas 760 ocorrências, e a
-- mesma classificação 203/28/12/6 que a produção devolve):
--
--   • como superusuário .................................... 498 ms
--   • como `authenticated`, com RLS aplicada ............... 492 ms
--   • as 7 chamadas do `Promise.all` da página, simultâneas . 480-492 ms cada
--   • plano: índice em (documento_versao_id), 14 laços — o custo acompanha os
--     documentos DO CASO, não o tamanho de `campo_extraido`, então a tabela
--     crescer com casos antigos NÃO degrada
--
-- Nenhuma dessas medições chega perto de 8 s. RLS, concorrência das sete chamadas
-- e volume da tabela ficam **descartados por medição, não por palpite** — e é por
-- isso que a investigação passa a ser de ambiente.
--
-- SOBRAM QUATRO CAUSAS, e este arquivo distingue as quatro:
--
--   A. o portal aponta para OUTRO projeto Supabase do que o SQL Editor onde as
--      migrations foram aplicadas — aí `correcoes_instaladas` vem `true` aqui e o
--      portal segue chamando as funções velhas. É a que explica tudo sem sobra;
--   B. o `statement_timeout` do papel `authenticated` é MENOR que os 8 s
--      presumidos — a `0101` foi dimensionada contra 8 s;
--   C. a instância está estrangulada de CPU (crédito de tier compartilhado), e
--      640 ms viram segundos;
--   D. o render que gerou o print é ANTERIOR à aplicação das migrations.
--
-- COMO RODAR. O bloco 1 é UMA consulta e devolve UM resultado — cole, mande, e
-- copie a saída inteira (o SQL Editor mostra só o resultado da última consulta de
-- um lote, por isso tudo está reunido numa só). O bloco 2 são os `explain
-- analyze`, para rodar DEPOIS, um por vez. Nada aqui escreve: é tudo leitura,
-- exceto uma tabela TEMPORÁRIA de sessão, que morre quando a aba fecha.
-- =============================================================================

-- =============================================================================
-- BLOCO 1 — cole daqui até o "fim do bloco 1" e mande de uma vez
-- =============================================================================

create temporary table if not exists diag_modelagem(ordem int, item text, valor text);
truncate diag_modelagem;

do $$
declare
  v_caso uuid := 'c4581e51-3ee5-413d-ba04-6d6149fff0c7';  -- TROQUE se for outro caso
  v_tem_pss boolean := to_regclass('public.pg_stat_statements') is not null;
  v_timeout text;
  r record;
begin
  -- ---------------------------------------------------------------------------
  -- A. QUAL BANCO É ESTE
  --
  -- Compare com o host do `NEXT_PUBLIC_SUPABASE_URL` configurado na Vercel. Se
  -- forem projetos diferentes, a resposta é essa e não há mais nada a procurar.
  -- ---------------------------------------------------------------------------
  insert into diag_modelagem values
    (10, 'A. banco',            current_database()),
    (11, 'A. usuário',          current_user),
    (12, 'A. servidor',         coalesce(inet_server_addr()::text, '(socket local)')),
    (13, 'A. versão',           coalesce(substring(version() from 'PostgreSQL [0-9.]+'), version())),
    (14, 'A. cluster_name',     coalesce(current_setting('cluster_name', true), '(não exposto)'));

  -- ---------------------------------------------------------------------------
  -- B. O TETO DE TEMPO — a pergunta que mais importa depois da A.
  --
  -- A `0101` foi escrita contra 8 s, que é o default do Supabase para
  -- `authenticated`. Teto menor muda a conta: a folga medida (640 ms contra 8 s)
  -- pode simplesmente não existir neste projeto.
  -- ---------------------------------------------------------------------------
  for r in
    select rolname, coalesce(array_to_string(rolconfig, ' | '), '(herda do banco)') as cfg
    from pg_roles
    where rolname in ('anon','authenticated','service_role','authenticator','postgres')
    order by rolname
  loop
    insert into diag_modelagem values (20, 'B. papel ' || r.rolname, r.cfg);
  end loop;

  for r in
    select coalesce(d.datname,'(todos)') as db, coalesce(ro.rolname,'(todos)') as ro,
           array_to_string(s.setconfig, ' | ') as cfg
    from pg_db_role_setting s
    left join pg_database d on d.oid = s.setdatabase
    left join pg_roles ro   on ro.oid = s.setrole
  loop
    insert into diag_modelagem values (21, 'B. setting ' || r.db || '/' || r.ro, r.cfg);
  end loop;

  -- O que o papel do portal VÊ na prática, depois de todas as heranças.
  -- `set local` exige transação e o SQL Editor não garante uma; `set` + `reset`
  -- funciona nos dois casos, e o bloco DO já é atômico.
  set role authenticated;
  v_timeout := current_setting('statement_timeout');
  reset role;
  insert into diag_modelagem values (22, 'B. statement_timeout de authenticated', v_timeout);

  -- ---------------------------------------------------------------------------
  -- C. O QUE O PORTAL REALMENTE EXPERIMENTOU — a evidência decisiva, e histórica.
  --
  -- `pg_stat_statements` vem habilitado por default no Supabase e guarda o tempo
  -- REAL das chamadas que o PostgREST fez. Não é simulação minha nem medição num
  -- container que não é o servidor: é o relógio da própria produção.
  --
  --   média na casa dos 600 ms → a função está rápida, o timeout vem de outro
  --                              lugar (A ou D);
  --   média em milhares de ms  → a produção é MUITO mais lenta que o medido, e a
  --                              causa é C.
  --
  -- Consulta por `execute` porque a extensão pode não estar ativa — e erro de
  -- relação inexistente abortaria o lote inteiro, levando os outros blocos com ele.
  -- ---------------------------------------------------------------------------
  if not v_tem_pss then
    insert into diag_modelagem values (30, 'C. pg_stat_statements',
      'NÃO ATIVA. Rode: create extension if not exists pg_stat_statements; '
      'depois recarregue a tela de Modelagem e rode este diagnóstico de novo '
      '(a tabela começa vazia).');
  else
    for r in execute $q$
      select round(mean_exec_time)::text || ' ms média · ' ||
             round(min_exec_time)::text  || ' ms mín · '  ||
             round(max_exec_time)::text  || ' ms máx · '  ||
             calls::text || ' chamadas' as m,
             left(regexp_replace(query, '\s+', ' ', 'g'), 70) as q
      from pg_stat_statements
      where query ilike '%fn_linhas_para_modelagem%'
         or query ilike '%fn_conferir_modelagem%'
         or query ilike '%fn_sazonalidade_do_caso%'
      order by mean_exec_time desc
      limit 15
    $q$
    loop
      insert into diag_modelagem values (30, 'C. ' || r.q, r.m);
    end loop;
    if not exists (select 1 from diag_modelagem where ordem = 30) then
      insert into diag_modelagem values (30, 'C. pg_stat_statements',
        'ativa, mas sem registro destas RPC — o contador pode ter sido zerado, ou '
        'a tela não foi carregada depois disso.');
    end if;
  end if;

  -- ---------------------------------------------------------------------------
  -- D. NÃO HÁ DUAS DEFINIÇÕES DISPUTANDO A CHAMADA
  --
  -- `create or replace` só substitui a função de assinatura IDÊNTICA. Um overload
  -- antigo — um parâmetro extra, ou o mesmo nome noutro schema do `search_path` —
  -- continuaria existindo, e o PostgREST poderia resolver a chamada para ele: a
  -- função corrigida estaria no banco, instalada, e sem ser usada.
  --
  -- Tem de aparecer UMA linha por nome, em `public`. `marca-0102` falsa é o
  -- ESPERADO em `fn_conferir_modelagem` (a 0102 não a reemitiu, ela é da 0101) e
  -- em `fn_papel_linha` (é da 0042) — para essas duas o que vale é o bloco 6 do
  -- `fn_diagnostico_modelagem`, no campo `conferir_modelagem_e_0101`.
  -- ---------------------------------------------------------------------------
  for r in
    select n.nspname || '.' || p.oid::regprocedure::text as assinatura,
           case when pg_get_functiondef(p.oid) like '%marca-0102%'
                then 'marca-0102' else 'sem marca' end as marca
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where p.proname in ('fn_linhas_para_modelagem','fn_conferir_modelagem',
                        'fn_versao_com_extracao','fn_papel_linha',
                        'fn_sazonalidade_do_caso','fn_valores_por_ano',
                        'fn_papel_do_rotulo_no_caso','fn_linhas_do_tipo')
    order by p.proname, n.nspname
  loop
    insert into diag_modelagem values (40, 'D. ' || r.assinatura, r.marca);
  end loop;

  -- ---------------------------------------------------------------------------
  -- E. o diagnóstico de DADO da 0102, junto, para a saída ser autocontida
  -- ---------------------------------------------------------------------------
  insert into diag_modelagem values
    (50, 'E. fn_diagnostico_modelagem', fn_diagnostico_modelagem(v_caso)::text);
end $$;

select item, valor from diag_modelagem order by ordem, item;

-- ======================= fim do bloco 1 ======================================


-- =============================================================================
-- BLOCO 2 — os `explain analyze`, no papel do portal. Rode DEPOIS, um por vez.
--
-- O número que interessa é o `Execution Time` da última linha. Referência medida
-- contra a reconstrução fiel do caso: **~490 ms**. Se aqui vier na mesma ordem de
-- grandeza, a função está boa e o timeout da tela não vem dela — o que empurra a
-- resposta para A (outro projeto) ou D (render anterior ao apply). Se vier em
-- milhares de ms, é C (instância estrangulada), e aí a correção é de plano da
-- infra, não de SQL.
-- =============================================================================

-- set role authenticated;
-- explain (analyze, buffers) select count(*) from fn_linhas_para_modelagem('c4581e51-3ee5-413d-ba04-6d6149fff0c7');
-- explain (analyze, buffers) select fn_conferir_modelagem('c4581e51-3ee5-413d-ba04-6d6149fff0c7');
-- reset role;

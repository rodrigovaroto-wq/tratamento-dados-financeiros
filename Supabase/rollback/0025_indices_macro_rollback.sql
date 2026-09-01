-- =============================================================================
-- ROLLBACK da migration 0025 (índices macroeconômicos)
--
-- ⚠️ APAGA OS DADOS COLETADOS. As três tabelas somem com o conteúdo. Como a
-- coleta é reprodutível (o workflow rebaixa 11 anos de série a cada execução),
-- nada disso é insubstituível — mas confira que está no banco CERTO antes de
-- rodar. `select current_database();` responde isso.
--
-- Seguro de rodar mais de uma vez: todo drop é `if exists`.
-- Não toca em NADA das migrations 0001–0024 — só nos objetos que a 0025 criou.
-- =============================================================================

-- As funções primeiro: nenhuma outra migration depende delas, e assim o drop
-- das tabelas não precisa arrastar dependência junto.
drop function if exists fn_indice_macro_anual(int);
drop function if exists fn_divergencias_indice_macro(numeric);
drop function if exists fn_registrar_expectativa_macro(jsonb);
drop function if exists fn_registrar_indice_macro(jsonb);

-- As tabelas-filhas antes da tabela de catálogo (as duas referenciam
-- `indice_macro_serie`). Os índices caem junto com as tabelas.
drop table if exists indice_macro_expectativa;
drop table if exists indice_macro_obs;
drop table if exists indice_macro_serie;

-- Conferência: as duas consultas abaixo têm de voltar VAZIAS.
--   select table_name from information_schema.tables
--    where table_name like 'indice_macro%';
--   select routine_name from information_schema.routines
--    where routine_name ~ 'macro';
--
-- Note o `~ 'macro'` e não `like '%indice_macro%'`: `fn_registrar_expectativa_macro`
-- não tem "indice_macro" no nome e escapava do filtro mais estreito — a
-- conferência diria "limpo" com uma função ainda de pé.

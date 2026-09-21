-- Testes da 0182 — as nove exigências de conteúdo para os tipos que antes não
-- tinham NENHUMA linha em taxonomia_linha_exigida (fatia F2.1 do roadmap:
-- AGING_AP, AGING_AR, EXTRATO_BANCARIO, GARANTIAS, AVAIS_FIANCAS,
-- CONTINGENCIAS, DEBITOS_TRIB, ESTOQUE, HEADCOUNT).
--
-- Mesma costura do Supabase/test/linha_exigida.test.sql (0113): registrar →
-- extrair → conferir, nunca escrever pendência/estado final na mão — passaria
-- com a correção desligada. Para cada tipo, a propriedade travada é a MESMA
-- que a 0113 já trava para MUTUOS/FAT_INTRAGRUPO/CONTRATO_SOCIAL:
--
--   • documento do tipo, COM conteúdo, mas SEM a linha exigida (rótulo
--     genérico, nenhum termo do localizador) → fn_exigencias_do_caso marca
--     satisfeita=false e o passo (2b) de fn_recomputar_completude abre
--     pendência linha_exigida_ausente que se declara PROPOSTA;
--   • o MESMO documento, com uma versão nova que TRAZ a linha (rótulo que
--     casa o localizador) → satisfeita=true e a pendência resolve sozinha.
--
-- Um caso por tipo (nove no total), loop em cima de um array de literais —
-- não é fixture inventada para provar bug de produção (regra 4 do CLAUDE.md):
-- é o mesmo tipo de rótulo real que os outros 18 asserts de linha_exigida.test.sql
-- já usam para os seis tipos 'codigo' e os três 'proposta' anteriores.

\set ON_ERROR_STOP on

create or replace function teste_assert_letv(p_ok boolean, p_nome text, p_detalhe text default null)
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
  v_tipo record;
  v_caso uuid;
  v_r jsonb;
  v_ver uuid;
  v_n int;
  v_txt text;
  v_sat boolean;
begin
  for v_tipo in
    select * from (values
      ('AGING_AP',        'saldo_em_aberto_fornecedor', 'Saldo em aberto - Fornecedor ABC Ltda.'),
      ('AGING_AR',        'saldo_em_aberto_cliente',    'Saldo em aberto - Cliente XYZ Comércio'),
      ('EXTRATO_BANCARIO','saldo_em_conta',             'Saldo em 31/12/2025'),
      ('GARANTIAS',       'valor_garantia',              'Garantia hipotecária - imóvel matrícula 123'),
      ('AVAIS_FIANCAS',   'valor_aval_fianca',           'Fiança bancária prestada pelo sócio'),
      ('CONTINGENCIAS',   'valor_contingencia',          'Contingência trabalhista - Processo 0001234-56'),
      ('DEBITOS_TRIB',    'valor_debito_tributario',     'Tributo ICMS em atraso'),
      ('ESTOQUE',         'valor_estoque',               'Estoque de produtos acabados'),
      ('HEADCOUNT',       'quantidade_headcount',        'Headcount ativo - Janeiro/2025')
    ) as t(tipo_taxonomia, conceito, chave_ok)
  loop
    raise notice '--- % (%): sem a linha exigida ---', v_tipo.tipo_taxonomia, v_tipo.conceito;

    v_caso := (fn_upsert_caso('Caso tipos variáveis — ' || v_tipo.tipo_taxonomia))::uuid;
    v_r := fn_registrar_documento(
      v_caso, 'Entidade Teste 0182', 'anual', '2025', v_tipo.tipo_taxonomia, 0.9, 'nome_arquivo',
      'supabase_storage', 'bucket/' || lower(v_tipo.tipo_taxonomia) || '-ausente.pdf',
      v_tipo.tipo_taxonomia || ' ausente.pdf', true, 'HASH-0182-' || v_tipo.tipo_taxonomia || '-A', 'ok');
    v_ver := (v_r->>'documento_versao_id')::uuid;
    -- Conteúdo presente (não é o caso do item_sem_conteudo da 0036), mas o
    -- rótulo não casa NENHUM termo dos localizadores da 0182.
    perform fn_registrar_campos_extraidos(v_ver, jsonb_build_array(jsonb_build_object(
      'chave', 'Linha genérica sem termo relevante', 'valor_num', '10', 'confianca', '0.9')), 'N0');

    select x.satisfeita into v_sat
      from fn_exigencias_do_caso(v_caso) x
     where x.tipo_taxonomia = v_tipo.tipo_taxonomia and x.conceito = v_tipo.conceito;
    perform teste_assert_letv(v_sat is not null and not v_sat,
      v_tipo.tipo_taxonomia || '/' || v_tipo.conceito || ': satisfeita=false sem a linha',
      coalesce(v_sat::text, 'exigência não apareceu em fn_exigencias_do_caso'));

    -- Prefixo, não igualdade: desde a 0119 o motivo ganha o sufixo da
    -- entidade (granularidade por entidade), como o próprio
    -- linha_exigida.test.sql já documenta e casa.
    select count(*), min(descricao) into v_n, v_txt from pendencia
     where caso_id = v_caso and tipo = 'linha_exigida_ausente' and estado <> 'resolvida'
       and motivo like 'completude:linha_exigida:' || v_tipo.tipo_taxonomia || ':' || v_tipo.conceito || '%';
    perform teste_assert_letv(v_n = 1,
      v_tipo.tipo_taxonomia || '/' || v_tipo.conceito || ': abre exatamente uma pendência',
      'achou ' || v_n);
    perform teste_assert_letv(v_txt like '%PROPOSTA%',
      v_tipo.tipo_taxonomia || '/' || v_tipo.conceito || ': a pendência se declara PROPOSTA',
      left(coalesce(v_txt, 'null'), 160));

    raise notice '--- % (%): a linha aparece numa versão nova ---', v_tipo.tipo_taxonomia, v_tipo.conceito;
    v_r := fn_registrar_documento(
      v_caso, 'Entidade Teste 0182', 'anual', '2025', v_tipo.tipo_taxonomia, 0.9, 'nome_arquivo',
      'supabase_storage', 'bucket/' || lower(v_tipo.tipo_taxonomia) || '-presente.pdf',
      v_tipo.tipo_taxonomia || ' presente.pdf', true, 'HASH-0182-' || v_tipo.tipo_taxonomia || '-B', 'ok');
    v_ver := (v_r->>'documento_versao_id')::uuid;
    perform fn_registrar_campos_extraidos(v_ver, jsonb_build_array(jsonb_build_object(
      'chave', v_tipo.chave_ok, 'valor_num', '10', 'confianca', '0.9')), 'N0');

    select x.satisfeita into v_sat
      from fn_exigencias_do_caso(v_caso) x
     where x.tipo_taxonomia = v_tipo.tipo_taxonomia and x.conceito = v_tipo.conceito;
    perform teste_assert_letv(coalesce(v_sat, false),
      v_tipo.tipo_taxonomia || '/' || v_tipo.conceito || ': satisfeita=true com "' || v_tipo.chave_ok || '"',
      coalesce(v_sat::text, 'null'));

    select count(*) into v_n from pendencia
     where caso_id = v_caso and tipo = 'linha_exigida_ausente' and estado <> 'resolvida'
       and motivo like 'completude:linha_exigida:' || v_tipo.tipo_taxonomia || ':' || v_tipo.conceito || '%';
    perform teste_assert_letv(v_n = 0,
      v_tipo.tipo_taxonomia || '/' || v_tipo.conceito || ': a pendência resolve sozinha com a linha',
      'ainda aberta: ' || v_n);
  end loop;

  raise notice 'linha_exigida_tipos_variaveis OK — as 9 exigências da 0182 (AGING_AP/AGING_AR/'
    'EXTRATO_BANCARIO/GARANTIAS/AVAIS_FIANCAS/CONTINGENCIAS/DEBITOS_TRIB/ESTOQUE/HEADCOUNT) '
    'cobram sem a linha e resolvem sozinhas quando ela aparece';
end $$;

drop function teste_assert_letv(boolean, text, text);

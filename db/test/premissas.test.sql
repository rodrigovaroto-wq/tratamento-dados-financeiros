-- Testes do catálogo de premissas e da escolha de modelagem (db/migrations/0038).
-- Rodar via db/test/run.sh (que aplica as migrations antes).
--
-- O que estes testes travam:
--   • o catálogo separa BASE COMUM (vale para todo setor) de premissa DE SETOR, e
--     a sugestão por setor devolve as duas coisas — nunca só uma;
--   • setor é SUGESTÃO, não restrição: um caso atípico pode usar premissa de
--     outro setor (em reestruturação, o atípico é a regra);
--   • não se vincula linha a premissa que o caso não ativou — senão a linha sai
--     "projetada" por uma premissa vazia, que é projetar com ZERO (a mesma
--     armadilha do "SEM FOCUS" que o macro já combate);
--   • o aplicar-em-lote roda no banco e DIZ quantas linhas pegou (lote que pega
--     zero linha não pode parecer sucesso);
--   • toda escolha de premissa deixa rastro em `decisao`/`evento_auditoria`:
--     projeção é decisão de análise, e alguém vai perguntar por que a receita
--     cresceu 8%.

\set ON_ERROR_STOP on

create or replace function teste_assert_pr(p_ok boolean, p_nome text, p_detalhe text default null)
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
  v_r jsonb;
  v_doc jsonb;
  v_ver uuid;
  v_n int;
  v_txt text;
begin
  raise notice '--- 1. o catálogo tem base comum E premissas de setor ---';
  select count(*) into v_n from premissa_catalogo where cardinality(setores) = 0;
  perform teste_assert_pr(v_n >= 25,
    'base comum semeada (macro, receita, custo, giro, dívida, tributo, sócios)',
    format('base comum: %s', v_n));

  select count(distinct s) into v_n from premissa_catalogo, unnest(setores) s;
  perform teste_assert_pr(v_n >= 18,
    'e os setores que o dono pediu ("todos os mais comuns")', format('setores distintos: %s', v_n));

  -- Sazonalidade é PREMISSA, não detalhe de implementação — o dono foi explícito.
  perform teste_assert_pr(
    exists (select 1 from premissa_catalogo where codigo = 'SAZONALIDADE' and natureza = 'sazonalidade'),
    'sazonalidade está no catálogo COMO premissa');

  raise notice '--- 2. fn_premissas_sugeridas: base + setor, nunca só o setor ---';
  select count(*) into v_n from fn_premissas_sugeridas('varejo');
  perform teste_assert_pr(v_n > (select count(*) from premissa_catalogo where 'varejo' = any(setores)),
    'a sugestão de varejo inclui a base comum, não só as de varejo', format('sugeridas: %s', v_n));

  perform teste_assert_pr(
    exists (select 1 from fn_premissas_sugeridas('varejo') where codigo = 'SSS'),
    'e traz o same-store-sales, que é a que manda no varejo');
  perform teste_assert_pr(
    not exists (select 1 from fn_premissas_sugeridas('varejo') where codigo = 'VACANCIA'),
    'e NÃO traz vacância (é de imobiliário) — sugestão é dirigida, não uma lista de tudo');
  perform teste_assert_pr(
    exists (select 1 from fn_premissas_sugeridas('varejo') where codigo = 'IPCA'),
    'IPCA aparece em qualquer setor (base comum)');

  select count(*) into v_n from fn_premissas_sugeridas(null);
  perform teste_assert_pr(v_n = (select count(*) from premissa_catalogo where cardinality(setores) = 0 and ativo),
    'sem setor definido, sugere só a base comum — que é a resposta certa para "ainda não sei"',
    format('%s', v_n));

  raise notice '--- 3. parâmetros do caso, com trilha ---';
  v_caso := (fn_upsert_caso('Caso modelagem premissas'))::uuid;
  v_r := fn_definir_modelagem(v_caso, 'VERTENTES METALÚRGICA LTDA.', 2025, 'IPCA', 'industria',
                              'analista@oria', 5);
  perform teste_assert_pr((v_r->>'setor') = 'industria', 'os parâmetros gravam', v_r::text);
  perform teste_assert_pr(
    exists (select 1 from evento_auditoria where acao = 'modelagem_parametros'
              and entidade_ref = 'caso:'||v_caso),
    'e trocar parâmetro de modelagem deixa rastro (muda todo número projetado)');

  -- Upsert: redefinir não cria caso_modelagem duplicado.
  perform fn_definir_modelagem(v_caso, 'VERTENTES METALÚRGICA LTDA.', 2024, 'IGPM', 'industria',
                               'analista@oria', 5);
  select count(*) into v_n from caso_modelagem where caso_id = v_caso;
  perform teste_assert_pr(v_n = 1, 'redefinir os parâmetros ATUALIZA, não duplica', format('%s', v_n));

  raise notice '--- 4. ativar premissa: fora do catálogo é RECUSADO ---';
  v_r := fn_ativar_premissa(v_caso, 'PREMISSA_QUE_NAO_EXISTE', '{"2026": 0.05}'::jsonb, 'digitado', 'analista@oria');
  perform teste_assert_pr((v_r->>'recusado') = 'true',
    'premissa fora do catálogo é recusada (premissa nova entra por semente)', v_r::text);
  perform teste_assert_pr(
    exists (select 1 from evento_auditoria where acao = 'premissa_recusada'),
    'e a tentativa fica na trilha');

  v_r := fn_ativar_premissa(v_caso, 'CRESC_REAL', '{"2026": 0.03, "2027": 0.04}'::jsonb, 'digitado', 'analista@oria');
  perform teste_assert_pr((v_r->>'ativo') = 'true', 'premissa do catálogo ativa normalmente', v_r::text);
  select count(*) into v_n from decisao where caso_id = v_caso and tipo = 'override';
  perform teste_assert_pr(v_n >= 1, 'e gera decisão registrada — projeção é decisão de análise');

  raise notice '--- 5. vincular linha: premissa NÃO ativa no caso é recusada ---';
  -- A guarda que impede o pior caso: linha "projetada" por premissa sem valor
  -- nenhum é linha projetada com ZERO, e zero não se denuncia.
  v_r := fn_vincular_linha_premissa(v_caso, 'receita_bruta', 'Receita de vendas', 'VERTENTES METALÚRGICA LTDA.',
                                    'MARGEM_BRUTA', 'analista@oria');
  perform teste_assert_pr((v_r->>'recusado') = 'true',
    'vincular a premissa não ativada no caso é recusado', v_r::text);
  perform teste_assert_pr((v_r->>'motivo_recusa') like '%projetar com zero%',
    'e o motivo diz por que isso importa', v_r->>'motivo_recusa');

  v_r := fn_vincular_linha_premissa(v_caso, 'receita_bruta', 'Receita de vendas', 'VERTENTES METALÚRGICA LTDA.',
                                    'CRESC_REAL', 'analista@oria');
  perform teste_assert_pr((v_r->>'premissa') = 'CRESC_REAL', 'com a premissa ativa, vincula', v_r::text);

  -- O rótulo é guardado NORMALIZADO: "Receita  de Vendas" e "receita de vendas"
  -- são a mesma linha do ponto de vista da modelagem.
  v_r := fn_vincular_linha_premissa(v_caso, 'receita_bruta', 'RECEITA  DE VENDAS', 'VERTENTES METALÚRGICA LTDA.',
                                    'CRESC_REAL', 'analista@oria');
  select count(*) into v_n from caso_linha_premissa where caso_id = v_caso;
  perform teste_assert_pr(v_n = 1,
    'a mesma linha com grafia diferente ATUALIZA o vínculo, não cria um segundo',
    format('vínculos: %s', v_n));

  raise notice '--- 6. setor é SUGESTÃO: premissa de outro setor pode ser usada ---';
  -- Em reestruturação o caso atípico é a regra. A sugestão dirige; ela não proíbe.
  perform fn_ativar_premissa(v_caso, 'REVPAR', '{"2026": 180}'::jsonb, 'digitado', 'analista@oria');
  v_r := fn_vincular_linha_premissa(v_caso, 'receita_bruta', 'Receita de hospedagem', null,
                                    'REVPAR', 'analista@oria');
  perform teste_assert_pr((v_r->>'premissa') = 'REVPAR',
    'um caso de indústria pode usar premissa de hotelaria se o analista quiser', v_r::text);

  raise notice '--- 7. aplicar em lote roda no banco e DIZ quantas linhas pegou ---';
  v_doc := fn_registrar_documento(
    v_caso, 'VERTENTES METALÚRGICA LTDA.', 'anual', '2025', 'DRE', 0.95, 'nome_arquivo',
    'supabase_storage', 'bucket/dre.pdf', 'DRE 2025.pdf', true, 'HASH-DRE-PREM', 'ok');
  v_ver := (v_doc->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, jsonb_build_array(
    jsonb_build_object('ordem', 0, 'chave', 'Vendas de produtos', 'valor_num', '1000',
                       'unidade', 'milhar', 'moeda', 'BRL', 'confianca', '0.9', 'secao_canonica', 'receita_bruta'),
    jsonb_build_object('ordem', 1, 'chave', 'Prestação de serviços', 'valor_num', '400',
                       'unidade', 'milhar', 'moeda', 'BRL', 'confianca', '0.9', 'secao_canonica', 'receita_bruta'),
    jsonb_build_object('ordem', 2, 'chave', 'Custo dos produtos vendidos', 'valor_num', '-600',
                       'unidade', 'milhar', 'moeda', 'BRL', 'confianca', '0.9', 'secao_canonica', 'custos')
  ));

  v_r := fn_aplicar_premissa_em_lote(v_caso, 'receita_bruta', 'CRESC_REAL', 'analista@oria');
  perform teste_assert_pr((v_r->>'n_linhas')::int = 2,
    'o lote pega as 2 linhas de receita_bruta e diz quantas foram', v_r::text);
  perform teste_assert_pr(
    exists (select 1 from caso_linha_premissa
            where caso_id = v_caso and rotulo_norm = fn_normalizar_texto('Vendas de produtos')
              and premissa_codigo = 'CRESC_REAL'),
    'e cada linha ficou vinculada de fato');

  -- Lote em seção SEM linha devolve zero — e zero tem de ser visível, não passar
  -- por sucesso silencioso.
  v_r := fn_aplicar_premissa_em_lote(v_caso, 'atividades_investimento', 'CRESC_REAL', 'analista@oria');
  perform teste_assert_pr((v_r->>'n_linhas')::int = 0,
    'lote em seção sem linha devolve 0 — o número é a conferência do lote', v_r::text);

  -- Lote com premissa não ativa: recusa, sem vincular nada.
  v_r := fn_aplicar_premissa_em_lote(v_caso, 'custos', 'PMP', 'analista@oria');
  perform teste_assert_pr((v_r->>'recusado') = 'true',
    'lote com premissa não ativa no caso é recusado', v_r::text);
  perform teste_assert_pr(
    not exists (select 1 from caso_linha_premissa where caso_id = v_caso and premissa_codigo = 'PMP'),
    'e nada foi vinculado pela metade');

  raise notice '--- 8. a conferência diz o que falta ANTES de exportar ---';
  v_r := fn_conferir_modelagem(v_caso);
  perform teste_assert_pr((v_r->>'linhas_do_caso')::int = 3,
    'conhece as 3 linhas extraídas do caso', v_r::text);
  perform teste_assert_pr((v_r->>'linhas_com_premissa')::int = 2,
    'e conta como cobertas SÓ as que existem de fato (as 2 de receita)', v_r::text);
  perform teste_assert_pr((v_r->>'linhas_sem_premissa')::int = 1,
    'sobrando o CPV como linha que não seria projetada', v_r::text);
  -- Os vínculos configurados antes de o documento chegar ("Receita de vendas",
  -- "Receita de hospedagem") não cobrem linha nenhuma — e isso é dito, não
  -- escondido: é a diferença entre "configurei" e "está coberto".
  perform teste_assert_pr((v_r->'vinculos_orfaos') @> to_jsonb(fn_normalizar_texto('Receita de hospedagem')),
    'e os vínculos órfãos são NOMEADOS (configuração apontando para linha que não existe)',
    v_r->>'vinculos_orfaos');
  perform teste_assert_pr((v_r->>'pronto') = 'true',
    'com parâmetros e premissas com valor, está pronto para o completo', v_r::text);

  -- Premissa ativa SEM valor bloqueia: projetar por premissa vazia é projetar
  -- com zero, e o arquivo não deve sair assim sem ninguém saber.
  perform fn_ativar_premissa(v_caso, 'SGA_PCT', '{}'::jsonb, 'digitado', 'analista@oria');
  v_r := fn_conferir_modelagem(v_caso);
  perform teste_assert_pr((v_r->'premissas_sem_valor') @> '["SGA_PCT"]'::jsonb,
    'premissa ativa sem valor é NOMEADA', v_r::text);
  perform teste_assert_pr((v_r->>'pronto') = 'false',
    'e ela impede o "pronto" — projeção com premissa vazia é projeção com zero', v_r::text);

  raise notice '--- 9. fn_linhas_para_modelagem NÃO vaza linha de outro caso (0039) ---';
  -- `campo_extraido` não tem `caso_id` — o vínculo passa por documento_versao →
  -- documento. Com a RLS aberta a qualquer autenticado, uma consulta sem esse
  -- join traz as linhas de TODOS os mandatos, e nada barra. Foi o defeito da
  -- primeira versão da tela de Modelagem; a função existe para o escopo por caso
  -- ter um lugar só, coberto por este teste.
  declare
    v_outro uuid;
    v_doc2 jsonb;
  begin
    v_outro := (fn_upsert_caso('Caso VIZINHO — não deve aparecer'))::uuid;
    v_doc2 := fn_registrar_documento(
      v_outro, 'Outra Empresa Ltda.', 'anual', '2025', 'DRE', 0.95, 'nome_arquivo',
      'supabase_storage', 'bucket/outro.pdf', 'DRE Outro 2025.pdf', true, 'HASH-OUTRO', 'ok');
    perform fn_registrar_campos_extraidos((v_doc2->>'documento_versao_id')::uuid, jsonb_build_array(
      jsonb_build_object('ordem', 0, 'chave', 'LINHA DO CASO VIZINHO', 'valor_num', '99999',
                         'unidade', 'milhar', 'moeda', 'BRL', 'confianca', '0.9',
                         'secao_canonica', 'receita_bruta')
    ));

    perform teste_assert_pr(
      not exists (select 1 from fn_linhas_para_modelagem(v_caso) where chave = 'LINHA DO CASO VIZINHO'),
      'a linha do caso vizinho NÃO aparece nas linhas deste caso');
    perform teste_assert_pr(
      exists (select 1 from fn_linhas_para_modelagem(v_outro) where chave = 'LINHA DO CASO VIZINHO'),
      'e aparece no caso a que pertence');

    select count(*) into v_n from fn_linhas_para_modelagem(v_caso);
    perform teste_assert_pr(v_n = 3,
      'este caso continua com as suas 3 linhas lógicas', format('%s', v_n));
  end;

  raise notice '--- 10. sazonalidade DERIVADA do histórico do caso (0040) ---';
  declare
    v_cs uuid;
    v_dfat jsonb;
    v_soma numeric;
    v_meses int;
    v_linhas jsonb := '[]'::jsonb;
    v_m int;
  begin
    v_cs := (fn_upsert_caso('Caso sazonalidade'))::uuid;
    v_dfat := fn_registrar_documento(
      v_cs, 'Sazonal Ltda.', 'L24M', '24,25', 'FATURAMENTO_24M', 0.95, 'nome_arquivo',
      'supabase_storage', 'bucket/fat.pdf', 'Faturamento 24M.pdf', true, 'HASH-FAT-SAZ', 'ok');

    -- Curva com dezembro forte, como varejo de verdade: 100 nos onze primeiros
    -- meses e 200 em dezembro. Total 1300 → dezembro é 200/1300.
    for v_m in 1..12 loop
      v_linhas := v_linhas || jsonb_build_array(jsonb_build_object(
        'ordem', v_m, 'chave',
        (array['jan','fev','mar','abr','mai','jun','jul','ago','set','out','nov','dez'])[v_m] || '/2025',
        'valor_num', case when v_m = 12 then '200' else '100' end,
        'unidade', 'milhar', 'moeda', 'BRL', 'confianca', '0.95',
        'secao_canonica', 'receita_bruta'));
    end loop;
    -- E a linha de TOTAL, que NÃO pode entrar na base (dobraria o ano).
    v_linhas := v_linhas || jsonb_build_array(jsonb_build_object(
      'ordem', 13, 'chave', 'TOTAL DO EXERCÍCIO', 'valor_num', '1300',
      'unidade', 'milhar', 'moeda', 'BRL', 'confianca', '0.95', 'secao_canonica', 'receita_bruta'));

    perform fn_registrar_campos_extraidos((v_dfat->>'documento_versao_id')::uuid, v_linhas);

    select count(*), sum(fracao) into v_meses, v_soma from fn_sazonalidade_do_caso(v_cs);
    perform teste_assert_pr(v_meses = 12, 'a curva tem os 12 meses', format('%s', v_meses));
    perform teste_assert_pr(abs(v_soma - 1) < 0.0001,
      'e as frações somam 1 (é isso que o gerador multiplica pelo valor anual)', format('%s', v_soma));

    select fracao into v_soma from fn_sazonalidade_do_caso(v_cs) where mes = 12;
    perform teste_assert_pr(abs(v_soma - (200.0/1300.0)) < 0.0001,
      'dezembro pesa 200/1300 — a curva é a da empresa, não um duodécimo uniforme',
      format('%s', v_soma));

    -- A linha de TOTAL ficou fora da base. O mecanismo que a exclui é o PARSER DE
    -- MÊS ("tot" não casa com mês nenhum), não o filtro `not like 'total%'` — que é
    -- redundante e está anotado como tal na 0040. Escrevi o assert original
    -- acreditando provar o filtro; ao religar o defeito, ele passou, porque o
    -- parser já fazia o trabalho. Este é o que prova o que diz: 13 linhas entraram,
    -- 12 meses saíram, cada um com UMA observação.
    select fracao into v_soma from fn_sazonalidade_do_caso(v_cs) where mes = 1;
    perform teste_assert_pr(abs(v_soma - (100.0/1300.0)) < 0.0001,
      'janeiro pesa 100/1300 — a linha TOTAL não inflou o denominador',
      format('%s', v_soma));
    perform teste_assert_pr(
      not exists (select 1 from fn_sazonalidade_do_caso(v_cs) where n_observacoes <> 1),
      'e nenhum mês recebeu duas observações (a TOTAL não virou mês)');

    -- Caso SEM documento mensal: zero linhas, e o gerador deixa a linha sem
    -- distribuição dizendo por quê. Ratear 1/12 moveria caixa de dezembro para
    -- março e erraria a necessidade de giro no mês que importa.
    perform teste_assert_pr(
      not exists (select 1 from fn_sazonalidade_do_caso(v_caso)),
      'caso sem faturamento mensal devolve curva VAZIA, não 1/12 inventado');
  end;

  raise notice 'TODOS OS TESTES DE PREMISSAS PASSARAM';
end $$;

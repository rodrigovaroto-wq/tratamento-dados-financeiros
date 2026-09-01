-- =============================================================================
-- ROTEIRO DE MODELAGEM EM UMA COLADA — para o teste da tela sem digitar 30 vezes
--
-- POR QUE ESTE ARQUIVO EXISTE. Configurar a modelagem do v35 pela tela são ~11
-- premissas com 5 caixas de ano cada, 4 lotes por seção e 5 vínculos de linha:
-- perto de 70 interações para chegar ao ponto em que o teste de verdade começa,
-- que é ABRIR O ARQUIVO. Trabalho que dá 70 cliques é trabalho que não se repete
-- — e um teste que não se repete não vira regressão.
--
-- O QUE ELE NÃO É: um caminho paralelo ao portal. Cada passo abaixo chama a MESMA
-- função que a tela chama (`fn_definir_modelagem`, `fn_ativar_premissa`,
-- `fn_aplicar_premissa_em_lote`, `fn_vincular_linha_premissa`), então as guardas
-- valem todas: subtotal continua sendo recusado, premissa não ativa continua
-- sendo recusada, e cada decisão continua indo para `decisao`. Se este script
-- passar e a tela não, a diferença está na TELA — que é exatamente o que um teste
-- de interface tem de conseguir isolar.
--
-- COMO RODAR: troque o `v_caso` da primeira linha do bloco pelo id do seu caso
-- (ele é o uuid da URL da tela, `/casos/<id>/modelagem`; ou
-- `select id, nome from caso order by criado_em desc;`) e cole tudo no SQL
-- Editor do Supabase. Ele imprime, ao fim, o que a caixa de
-- conferência da tela vai mostrar.
--
-- É REVERSÍVEL: `fn_desativar_premissa` (0104) desfaz premissa por premissa, com
-- os vínculos junto — inclusive pelo botão "Remover" da tela.
--
-- DE ONDE VÊM OS NÚMEROS. Os marcados REALIZADO foram calculados do próprio caso
-- (as 249 linhas do v35), não arbitrados:
--
--   receita base (as 7 contas de `receita_bruta`) .............. 142.940
--   matérias-primas 78.200 / receita ............................. 54,7%
--   SG&A somado 20.090 / receita ................................. 14,1%
--   duplicatas a receber 32.000 -> × 360 / receita ................ 81 dias
--   estoques 24.610 .............................................. 62 dias
--   fornecedores 23.559 .......................................... 59 dias
--
-- ATENÇÃO ao 62: NÃO é o PME de manual (76 dias sobre CMV). `dias_de_giro`
-- divide pela RECEITA (decisão da 7.5, ver `export-modelagem.ts`), então o número
-- tem de ser o de receita — senão o estoque projetado sai errado.
--
-- O QUE FOI DEIXADO DE FORA DE PROPÓSITO, e o motivo é o mesmo nos dois:
-- `ALIQUOTA` e `TAXA_DIVIDA` são `pct_de_linha`, e toda premissa de percentual
-- incide sobre a RECEITA. A alíquota realizada (43%) aplicaria 43% da receita
-- como imposto; a taxa da dívida (15,1% a.a.) aplicaria 15% da receita como
-- juro. Os dois números são bons; a base é que é errada para eles.
-- =============================================================================

\set ON_ERROR_STOP on

do $$
declare
  -- >>> TROQUE AQUI PELO ID DO SEU CASO <<<
  v_caso  uuid := 'c4581e51-3ee5-413d-ba04-6d6149fff0c7';
  v_autor text := 'roteiro:sql';
  v_r     jsonb;
  v_n     int := 0;
  v_falhas text[] := array[]::text[];
  i        int;
begin
  -- Recusa não aborta o roteiro: ela é JUNTADA e relatada no fim. Abortar na
  -- primeira perderia as outras 20 configurações e esconderia se o problema é um
  -- rótulo só ou o caso inteiro.
  if not exists (select 1 from caso where id = v_caso) then
    raise exception 'Caso % não existe neste banco. Troque o v_caso no topo do bloco.', v_caso;
  end if;

  -- ---------------------------------------------------------------------------
  -- 1. PARÂMETROS DO MANDATO (passo 1 da tela)
  -- ---------------------------------------------------------------------------
  v_r := fn_definir_modelagem(v_caso, 'VERTENTES METALÚRGICA LTDA.', 2025, 'IPCA',
                              'industria', v_autor, 5);
  if coalesce((v_r->>'recusado')::boolean, false) then
    v_falhas := v_falhas || format('parâmetros: %s', v_r->>'motivo_recusa');
  end if;
  raise notice '1. parâmetros: entidade VERTENTES, último real 2025, IPCA, indústria, 5 anos (2026-2030)';

  -- ---------------------------------------------------------------------------
  -- 2. PREMISSAS (passo 2 da tela)
  --
  -- IPCA entra SEM valor de propósito: premissa macro sem valor puxa a
  -- expectativa do Focus que está no banco, e grava `origem = 'focus'`.
  -- ---------------------------------------------------------------------------
  declare
    v_premissas jsonb := jsonb_build_object(
      'IPCA',           '{}'::jsonb,                                              -- Focus
      'CRESC_NOMINAL',  '{"2026":8,"2027":7,"2028":6,"2029":6,"2030":6}'::jsonb,  -- julgamento
      'CUSTO_MP',       '{"2026":6,"2027":5,"2028":5,"2029":5,"2030":5}'::jsonb,  -- julgamento
      'CUSTO_VARIAVEL', '{"2026":54.7,"2027":54.7,"2028":54.7,"2029":54.7,"2030":54.7}'::jsonb, -- REALIZADO
      'SGA_PCT',        '{"2026":14.1,"2027":14.1,"2028":14.1,"2029":14.1,"2030":14.1}'::jsonb, -- REALIZADO
      'PMR',            '{"2026":81,"2027":81,"2028":81,"2029":81,"2030":81}'::jsonb,           -- REALIZADO
      'PME',            '{"2026":62,"2027":62,"2028":62,"2029":62,"2030":62}'::jsonb,           -- REALIZADO
      'PMP',            '{"2026":59,"2027":59,"2028":59,"2029":59,"2030":59}'::jsonb,           -- REALIZADO
      'CAPEX_PCT',      '{"2026":4,"2027":4,"2028":4,"2029":4,"2030":4}'::jsonb,                -- julgamento
      'DIVIDA_MOV',     '{"2026":-8000,"2027":-8000,"2028":-6000,"2029":-6000,"2030":-6000}'::jsonb, -- julgamento, em MILHARES
      'SAZONALIDADE',   '{"2026":100,"2027":100,"2028":100,"2029":100,"2030":100}'::jsonb
    );
    v_cod text;
  begin
    for v_cod in select jsonb_object_keys(v_premissas) loop
      v_r := fn_ativar_premissa(v_caso, v_cod, v_premissas->v_cod, 'digitado', v_autor);
      if coalesce((v_r->>'recusado')::boolean, false) then
        v_falhas := v_falhas || format('premissa %s: %s', v_cod, v_r->>'motivo_recusa');
      elsif v_r->>'origem' = 'focus' then
        raise notice '2. % ativada com valores do FOCUS: %', v_cod, v_r->'valores';
      end if;
    end loop;
    raise notice '2. % premissas ativadas', (select count(*) from jsonb_object_keys(v_premissas));
  end;

  -- A SAZONALIDADE recebe 100 em cada ano por um motivo prático, não conceitual:
  -- a curva mensal vem do próprio caso (0040) e a premissa não tem valor a
  -- digitar — mas `fn_conferir_modelagem` trata premissa ativa com `valores`
  -- vazio como "sem valor preenchido" e isso SEGURA o "pronto" da tela. O 100
  -- (= 100% do valor anual distribuído pela curva) mantém a conferência honesta
  -- sem inventar número que o modelo use. Está anotado como pendência: quem
  -- deveria mudar é a conferência, que precisa saber que premissa de
  -- sazonalidade não tem valor por natureza.

  -- ---------------------------------------------------------------------------
  -- 3. LOTES POR SEÇÃO (passo 3 da tela, botão "aplicar às N contas")
  --
  -- SÓ premissa de CRESCIMENTO entra em lote. `pct_de_linha` e `dias_de_giro`
  -- incidem sobre a receita total: em lote, as N linhas da seção virariam TODAS o
  -- mesmo percentual da receita. Por isso giro e capex são de linha única, no
  -- passo 4.
  --
  -- O lote da receita leva a SAZONALIDADE junto (a função aceita; o formulário da
  -- tela não manda, e lá isso é linha a linha).
  -- ---------------------------------------------------------------------------
  declare
    v_lotes text[][] := array[
      array['receita_bruta',         'CRESC_NOMINAL', 'SAZONALIDADE'],
      array['custos',                'CUSTO_MP',      null],
      array['despesas_operacionais', 'IPCA',          null],
      array['resultado_financeiro',  'IPCA',          null]
    ];
  begin
    for i in 1..array_length(v_lotes, 1) loop
      v_r := fn_aplicar_premissa_em_lote(v_caso, v_lotes[i][1], v_lotes[i][2], v_autor, v_lotes[i][3]);
      if coalesce((v_r->>'recusado')::boolean, false) then
        v_falhas := v_falhas || format('lote %s: %s', v_lotes[i][1], v_r->>'motivo_recusa');
      else
        raise notice '3. lote %: % conta(s) -> %', v_lotes[i][1], v_r->>'n_linhas', v_lotes[i][2];
      end if;
    end loop;
  end;

  -- ---------------------------------------------------------------------------
  -- 4. LINHAS ÚNICAS (passo 3 da tela, seletor da linha + "salvar seção")
  --
  -- Cada uma destas é `pct_de_linha` ou `dias_de_giro`, que incidem sobre a
  -- receita: uma linha por premissa, senão a conta é multiplicada.
  --
  -- Os rótulos são os que o extrator produziu — se algum não existir no SEU caso,
  -- o vínculo é gravado assim mesmo e vira `vinculos_orfaos` na conferência.
  -- Confira o relatório do fim.
  -- ---------------------------------------------------------------------------
  declare
    v_linhas text[][] := array[
      -- seção,                     rótulo,                                                  premissa
      array['custos',               'Matérias-primas e insumos consumidos',                  'CUSTO_VARIAVEL'],
      array['despesas_operacionais','Despesas gerais e administrativas',                     'SGA_PCT'],
      array['ativo_circulante',     'Duplicatas a receber de clientes - mercado interno',    'PMR'],
      array['ativo_circulante',     'Estoques',                                              'PME'],
      array['passivo_circulante',   'Fornecedores',                                          'PMP'],
      array['ativo_nao_circulante', 'Imobilizado',                                           'CAPEX_PCT'],
      array['passivo_nao_circulante','Empréstimos e Financiamentos',                         'DIVIDA_MOV']
    ];
  begin
    for i in 1..array_length(v_linhas, 1) loop
      v_r := fn_vincular_linha_premissa(v_caso, v_linhas[i][1], v_linhas[i][2], null,
                                        v_linhas[i][3], v_autor, null);
      if coalesce((v_r->>'recusado')::boolean, false) then
        v_falhas := v_falhas || format('linha "%s": %s', v_linhas[i][2], v_r->>'motivo_recusa');
      else
        v_n := v_n + 1;
      end if;
    end loop;
    raise notice '4. % linha(s) única(s) vinculada(s)', v_n;
  end;

  -- ---------------------------------------------------------------------------
  -- 5. O RELATÓRIO — o mesmo que a caixa de conferência da tela mostra
  -- ---------------------------------------------------------------------------
  if array_length(v_falhas, 1) is not null then
    raise notice '';
    raise notice '=== % RECUSA(S) — nenhuma delas abortou o roteiro ===', array_length(v_falhas, 1);
    for i in 1..array_length(v_falhas, 1) loop
      raise notice '  - %', v_falhas[i];
    end loop;
  end if;

  v_r := fn_conferir_modelagem(v_caso);
  raise notice '';
  raise notice '=== CONFERÊNCIA (é o que a tela vai mostrar) ===';
  raise notice 'pronto para o export completo: %', v_r->>'pronto';
  raise notice 'contas projetáveis com premissa: % de %',
    v_r->>'linhas_com_premissa', v_r->>'linhas_do_caso';
  raise notice 'premissas ativas: %', v_r->>'premissas_ativas';
  raise notice 'premissas SEM valor: %', v_r->'premissas_sem_valor';
  raise notice 'vínculos órfãos (rótulo que não existe no caso): %', v_r->'vinculos_orfaos';
end $$;

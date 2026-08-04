-- Testes do papel POR SEÇÃO e do lote que não cai inteiro (db/migrations/0100).
-- Rodar via db/test/run.sh (que aplica as migrations antes).
--
-- O DEFEITO QUE ESTE ARQUIVO TRAVA, na forma em que ele apareceu. Na rodada do
-- dono (04/08/2026) o "aplicar em lote" do passo 3 não vinculava nada e a seção
-- inteira sumia da tela. A tela oferecia a linha como conta projetável; a guarda
-- do banco, consultada com um escopo diferente, respondia "isto é série mensal" e
-- recusava; e a recusa da PRIMEIRA linha abortava o lote das outras 43.
--
-- A divergência de escopo é a raiz: `fn_linhas_para_modelagem` agrupa por
-- (seção, rótulo) e `fn_papel_do_rotulo_no_caso` agrupava só por rótulo, no caso
-- inteiro, resolvendo o empate para o papel mais restritivo.
--
-- A montagem abaixo é a forma REAL do caso do v35, não uma invenção: o mesmo
-- rótulo de faturamento chega por dois documentos — pela DRE, dentro de
-- `receita_bruta`, onde é conta; e pelo mapa de faturamento mensal, SEM seção
-- canônica, onde é série mensal. No v35 são 45 linhas sem seção convivendo com as
-- que têm seção, então esse encontro não é canto raro: é o meio da tela.

\set ON_ERROR_STOP on

create or replace function teste_assert_secao(p_ok boolean, p_nome text, p_detalhe text default null)
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
  v_txt  text;
  v_n    int;
begin
  raise notice '--- 1. a montagem: o mesmo rótulo em duas seções, com papéis diferentes ---';
  v_caso := (fn_upsert_caso('Papel por seção'))::uuid;

  -- (a) A DRE: "Faturamento Janeiro" como conta de receita. É assim que a
  --     extração real classifica a linha quando ela vem dentro da demonstração.
  v_r := fn_registrar_documento(v_caso, 'SECAO LTDA.', 'anual', '2025', 'DRE', 0.95,
    'nome_arquivo', 'supabase_storage', 's/dre.pdf', 'DRE SECAO.pdf', true, 'HASH-SECAO-1', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Faturamento Janeiro','valor_num','15493','unidade','milhar',
                       'moeda','BRL','confianca','0.97','secao_canonica','receita_bruta'),
    jsonb_build_object('ordem',1,'chave','Vendas de produtos - mercado interno','valor_num','158900',
                       'unidade','milhar','moeda','BRL','confianca','0.97','secao_canonica','receita_bruta'),
    jsonb_build_object('ordem',2,'chave','Vendas de produtos - mercado externo','valor_num','21400',
                       'unidade','milhar','moeda','BRL','confianca','0.97','secao_canonica','receita_bruta'),
    -- Um subtotal na MESMA seção: ele tem de continuar fora do lote, sem derrubá-lo.
    jsonb_build_object('ordem',3,'chave','RECEITA OPERACIONAL LÍQUIDA','valor_num','143380',
                       'unidade','milhar','moeda','BRL','confianca','0.97','secao_canonica','receita_bruta')
  ), 'N2');

  -- (b) O mapa de faturamento mensal: MESMO rótulo, SEM seção canônica. Aqui ele
  --     é série mensal, e continua tendo de ser protegido.
  v_r := fn_registrar_documento(v_caso, 'SECAO LTDA.', 'anual', '2025', 'FATURAMENTO_24M', 0.95,
    'nome_arquivo', 'supabase_storage', 's/fat.pdf', 'FAT SECAO.pdf', true, 'HASH-SECAO-2', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Faturamento Janeiro','valor_num','15493','unidade','milhar',
                       'moeda','BRL','confianca','0.97')
  ), 'N2');

  select papel into v_txt from fn_linhas_para_modelagem(v_caso)
    where rotulo_norm = fn_normalizar_texto('Faturamento Janeiro') and secao_canonica = 'receita_bruta';
  perform teste_assert_secao(v_txt = 'conta',
    'a TELA mostra o rótulo como conta dentro de receita_bruta', coalesce(v_txt,'(null)'));

  select papel into v_txt from fn_linhas_para_modelagem(v_caso)
    where rotulo_norm = fn_normalizar_texto('Faturamento Janeiro') and secao_canonica is null;
  perform teste_assert_secao(v_txt = 'serie_mensal',
    '…e como série mensal no grupo sem seção — são duas linhas lógicas', coalesce(v_txt,'(null)'));

  raise notice '--- 2. a GUARDA lê o papel da mesma seção que a tela mostrou ---';
  -- É este assert que reprova com o defeito religado: sem a seção, a guarda
  -- resolvia para 'serie_mensal' (papel mais restritivo do caso inteiro) e
  -- recusava a linha que a tela tinha acabado de oferecer.
  v_txt := fn_papel_do_rotulo_no_caso(v_caso, fn_normalizar_texto('Faturamento Janeiro'), 'receita_bruta');
  perform teste_assert_secao(v_txt = 'conta',
    'em receita_bruta a guarda diz CONTA (a tela e o banco concordam)', coalesce(v_txt,'(null)'));

  v_txt := fn_papel_do_rotulo_no_caso(v_caso, fn_normalizar_texto('Faturamento Janeiro'), null);
  perform teste_assert_secao(v_txt = 'serie_mensal',
    'e no grupo sem seção ela continua dizendo SÉRIE MENSAL — a guarda não afrouxou',
    coalesce(v_txt,'(null)'));

  -- Seção que não existe não pode virar a chave que abre a porta.
  v_txt := fn_papel_do_rotulo_no_caso(v_caso, fn_normalizar_texto('RECEITA OPERACIONAL LÍQUIDA'), 'secao_inventada');
  perform teste_assert_secao(v_txt = 'subtotal',
    'seção inexistente cai para o caso inteiro: subtotal continua subtotal', coalesce(v_txt,'(null)'));

  raise notice '--- 3. vincular: aceita na seção certa, recusa onde a linha não é conta ---';
  perform fn_ativar_premissa(v_caso, 'CRESC_REAL', jsonb_build_object('2026', 5), 'digitado', 'teste');

  v_r := fn_vincular_linha_premissa(v_caso, 'receita_bruta', 'Faturamento Janeiro', null,
                                    'CRESC_REAL', 'teste');
  perform teste_assert_secao(not coalesce((v_r->>'recusado')::boolean, false),
    'vincular a linha de receita_bruta é ACEITO', v_r::text);

  v_r := fn_vincular_linha_premissa(v_caso, null, 'Faturamento Janeiro', null, 'CRESC_REAL', 'teste');
  perform teste_assert_secao(coalesce((v_r->>'recusado')::boolean, false) and v_r->>'papel' = 'serie_mensal',
    'a MESMA linha sem seção continua RECUSADA (é a série mensal)', v_r::text);

  v_r := fn_vincular_linha_premissa(v_caso, 'receita_bruta', 'RECEITA OPERACIONAL LÍQUIDA', null,
                                    'CRESC_REAL', 'teste');
  perform teste_assert_secao(coalesce((v_r->>'recusado')::boolean, false) and v_r->>'papel' = 'subtotal',
    'e o subtotal da própria seção continua recusado — a dupla contagem segue fechada', v_r::text);

  raise notice '--- 4. o LOTE não cai inteiro por causa de uma linha ---';
  delete from caso_linha_premissa where caso_id = v_caso;
  v_r := fn_aplicar_premissa_em_lote(v_caso, 'receita_bruta', 'CRESC_REAL', 'teste');
  perform teste_assert_secao(not coalesce((v_r->>'recusado')::boolean, false),
    'o lote de receita_bruta NÃO é recusado', v_r::text);
  -- Três contas (Faturamento Janeiro + as duas de venda); o subtotal fica fora.
  perform teste_assert_secao((v_r->>'n_linhas')::int = 3,
    'vinculou as 3 contas da seção (era 0: a primeira recusa derrubava o resto)', v_r::text);
  perform teste_assert_secao((v_r->>'n_ignoradas')::int = 1,
    'e DECLAROU a linha que ficou de fora, em vez de silenciar', v_r::text);

  select count(*) into v_n from caso_linha_premissa
    where caso_id = v_caso and secao_canonica = 'receita_bruta' and premissa_codigo = 'CRESC_REAL';
  perform teste_assert_secao(v_n = 3, 'e as 3 estão gravadas de verdade', v_n::text);

  raise notice '--- 5. recusa GLOBAL continua abortando o lote (não é a mesma coisa) ---';
  v_r := fn_aplicar_premissa_em_lote(v_caso, 'receita_bruta', 'CUSTO_VARIAVEL', 'teste');
  perform teste_assert_secao(coalesce((v_r->>'recusado')::boolean, false)
      and v_r->>'escopo' = 'premissa',
    'premissa não ativa recusa o lote inteiro, e diz que o escopo é da premissa', v_r::text);

  raise notice 'TODOS OS TESTES DE PAPEL POR SEÇÃO PASSARAM';
end $$;

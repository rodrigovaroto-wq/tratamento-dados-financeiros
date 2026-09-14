-- =============================================================================
-- 0165 — "PASSIVO" sozinho já inclui o Patrimônio Líquido
--
-- OS NÚMEROS DESTE ARQUIVO SÃO DE UM PDF REAL, não inventados (regra 4): o
-- `AMOBELEZA - BALANÇO 2024.pdf` que o dono anexou em 14/09/2026, do lote do
-- caso "teste 143". Transcritos do documento:
--
--     ATIVO                     118.591.566,53 D
--     PASSIVO                   118.591.566,53 C
--       PASSIVO CIRCULANTE      119.620.673,17 C
--       PASSIVO NÃO-CIRCULANTE    8.362.115,49 C
--       PATRIMÔNIO LÍQUIDO       -9.391.222,13     (impresso "9.391.222,13 D")
--
-- E eles FECHAM: 119.620.673,17 + 8.362.115,49 - 9.391.222,13 = 118.591.566,53.
-- O balanço está certo; era a checagem que somava o PL duas vezes.
--
-- O QUE ESTE ARQUIVO MEDE, nos dois sentidos:
--   1. o balanço real fecha (era 'divergente' com diferença de 9.391.222,13);
--   2. o CONTRAPOSITIVO — um "PASSIVO" bare que é exigível de verdade (não bate
--      com o ativo sozinho) continua somando o PL, e continua fechando. Sem
--      este segundo bloco, a correção poderia ter virado "nunca mais soma o PL"
--      e o arquivo passaria igual.
--   3. e o balanço que NÃO fecha de verdade continua sendo reprovado — senão a
--      correção teria comprado o verde cegando a checagem, que é o defeito que
--      este repositório persegue.
-- =============================================================================

create or replace function teste_assert_passivo(p_cond boolean, p_nome text, p_detalhe text default null)
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
  v_caso uuid;
  v_ver  uuid;
  v_r    jsonb;
  v_txt  text;
  v_num  numeric;
begin
  raise notice '--- 1. o balanço REAL da AMOBELEZA fecha (PASSIVO bare = grupo inteiro) ---';
  v_caso := (fn_upsert_caso('Passivo bare é o grupo'))::uuid;

  v_r := fn_registrar_documento(v_caso, 'AMOBELEZA COMERCIO DIGITAL E OFFLINE LTDA', 'ano', '2024',
    'BALANCO', 0.99, 'nome_arquivo', 'supabase_storage', 's/amo2024.pdf',
    'AMOBELEZA - BALANÇO 2024.pdf', true, 'HASH-PASSIVO-BARE-1', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;

  -- Os rótulos são os do documento, em caixa alta e sem a palavra "total" —
  -- é exatamente essa forma que manda a checagem para o caminho estrutural.
  perform fn_registrar_campos_extraidos(v_ver, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','ATIVO','valor_num','118591566.53',
                       'unidade','unidade','moeda','BRL','confianca','0.99','secao','ATIVO'),
    jsonb_build_object('ordem',1,'chave','ATIVO CIRCULANTE','valor_num','118566427.24',
                       'unidade','unidade','moeda','BRL','confianca','0.99','secao','ATIVO'),
    jsonb_build_object('ordem',2,'chave','ATIVO NÃO-CIRCULANTE','valor_num','25139.29',
                       'unidade','unidade','moeda','BRL','confianca','0.99','secao','ATIVO'),
    jsonb_build_object('ordem',3,'chave','PASSIVO','valor_num','118591566.53',
                       'unidade','unidade','moeda','BRL','confianca','0.99','secao','PASSIVO'),
    jsonb_build_object('ordem',4,'chave','PASSIVO CIRCULANTE','valor_num','119620673.17',
                       'unidade','unidade','moeda','BRL','confianca','0.99','secao','PASSIVO'),
    jsonb_build_object('ordem',5,'chave','PASSIVO NÃO-CIRCULANTE','valor_num','8362115.49',
                       'unidade','unidade','moeda','BRL','confianca','0.99','secao','PASSIVO'),
    jsonb_build_object('ordem',6,'chave','PATRIMÔNIO LÍQUIDO','valor_num','-9391222.13',
                       'unidade','unidade','moeda','BRL','confianca','0.99','secao','PATRIMÔNIO LÍQUIDO')
  ), 'N2');

  perform fn_reconciliar_por_documento((v_r->>'documento_id')::uuid);

  select resultado, divergencia_abs into v_txt, v_num from reconciliacao
   where caso_id = v_caso and tipo = 'ativo_passivo_pl'
   order by criado_em desc limit 1;

  -- ESTE É O ASSERT QUE REPROVA COM A CORREÇÃO DESLIGADA: sem ela, o lado
  -- direito vira 118.591.566,53 + (-9.391.222,13) = 109.200.344,40 e a
  -- divergência sai em exatamente 9.391.222,13 — o PL, contado duas vezes.
  perform teste_assert_passivo(v_txt = 'ok',
    'o balanço real da AMOBELEZA fecha: "PASSIVO" bare que bate com o Ativo NÃO soma o PL de novo',
    format('resultado=%s, divergência=%s (o PL do documento é 9.391.222,13)',
           coalesce(v_txt,'(sem registro)'), coalesce(v_num::text,'—')));

  select fonte_b->>'origem' into v_txt from reconciliacao
   where caso_id = v_caso and tipo = 'ativo_passivo_pl'
   order by criado_em desc limit 1;
  perform teste_assert_passivo(v_txt like '%já inclui o Patrimônio Líquido%',
    'e a procedência DIZ por que fechou — quem lê a checagem vê o raciocínio, não só o veredito',
    coalesce(v_txt,'(null)'));

  raise notice '--- 2. CONTRAPOSITIVO: "PASSIVO" bare exigível continua somando o PL ---';
  -- Mesma forma de rótulos, outro regime: aqui o "PASSIVO" é só o exigível
  -- (100 mi), o PL é 50 mi, e o ativo é 150 mi. Se a correção tivesse virado
  -- "nunca mais somar o PL", este bloco reprovaria — é ele que impede a
  -- correção de ser um cheque em branco.
  --
  -- A GRANDEZA É DE BALANÇO DE VERDADE, E NÃO É ENFEITE. A primeira versão
  -- deste bloco usava 150/100/50 e passava por acidente: `p_tolerancia_abs`
  -- vale 100 por padrão, então a diferença de 50 entre o passivo e o ativo
  -- cabia DENTRO da tolerância e o ramo novo era tomado do mesmo jeito. O
  -- assert existia e não media nada — o invariante nascido vazio que este
  -- repositório persegue, desta vez no teste da própria correção.
  v_r := fn_registrar_documento(v_caso, 'EXIGIVEL SEPARADO LTDA', 'ano', '2024',
    'BALANCO', 0.99, 'nome_arquivo', 'supabase_storage', 's/exig.pdf',
    'EXIGIVEL - BALANCO 2024.pdf', true, 'HASH-PASSIVO-BARE-2', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','ATIVO','valor_num','150000000',
                       'unidade','unidade','moeda','BRL','confianca','0.99','secao','ATIVO'),
    jsonb_build_object('ordem',1,'chave','PASSIVO','valor_num','100000000',
                       'unidade','unidade','moeda','BRL','confianca','0.99','secao','PASSIVO'),
    jsonb_build_object('ordem',2,'chave','PATRIMÔNIO LÍQUIDO','valor_num','50000000',
                       'unidade','unidade','moeda','BRL','confianca','0.99','secao','PATRIMÔNIO LÍQUIDO')
  ), 'N2');
  perform fn_reconciliar_por_documento((v_r->>'documento_id')::uuid);

  select resultado into v_txt from reconciliacao
   where caso_id = v_caso and tipo = 'ativo_passivo_pl'
     and entidade_id = (select id from entidade
                         where caso_id = v_caso and razao_social = 'EXIGIVEL SEPARADO LTDA')
   order by criado_em desc limit 1;
  perform teste_assert_passivo(v_txt = 'ok',
    '"PASSIVO" bare que NÃO bate com o ativo continua sendo exigível, e o PL continua entrando',
    coalesce(v_txt,'(sem registro)'));

  raise notice '--- 3. o balanço que não fecha DE VERDADE continua reprovando ---';
  -- Ativo 150 mi, passivo exigível 100 mi, PL 30 mi: faltam 20 mi e ninguém
  -- explica. Se este bloco passasse, a correção teria comprado o verde cegando
  -- a checagem. (Mesma lição de grandeza do bloco 2: com 150/100/30 a
  -- tolerância absoluta de 100 engolia a diferença e o assert não media nada.)
  v_r := fn_registrar_documento(v_caso, 'NAO FECHA LTDA', 'ano', '2024',
    'BALANCO', 0.99, 'nome_arquivo', 'supabase_storage', 's/naofecha.pdf',
    'NAO FECHA - BALANCO 2024.pdf', true, 'HASH-PASSIVO-BARE-3', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','ATIVO','valor_num','150000000',
                       'unidade','unidade','moeda','BRL','confianca','0.99','secao','ATIVO'),
    jsonb_build_object('ordem',1,'chave','PASSIVO','valor_num','100000000',
                       'unidade','unidade','moeda','BRL','confianca','0.99','secao','PASSIVO'),
    jsonb_build_object('ordem',2,'chave','PATRIMÔNIO LÍQUIDO','valor_num','30000000',
                       'unidade','unidade','moeda','BRL','confianca','0.99','secao','PATRIMÔNIO LÍQUIDO')
  ), 'N2');
  perform fn_reconciliar_por_documento((v_r->>'documento_id')::uuid);

  select resultado, divergencia_abs into v_txt, v_num from reconciliacao
   where caso_id = v_caso and tipo = 'ativo_passivo_pl'
     and entidade_id = (select id from entidade
                         where caso_id = v_caso and razao_social = 'NAO FECHA LTDA')
   order by criado_em desc limit 1;
  perform teste_assert_passivo(v_txt = 'divergente' and v_num = 20000000,
    'balanço que não fecha de verdade continua divergente — a correção não cegou a checagem',
    format('resultado=%s, divergência=%s (esperado: divergente / 20000000)',
           coalesce(v_txt,'(sem registro)'), coalesce(v_num::text,'—')));

  raise notice '--- 4. o KIT BÁSICO também conhece o "PASSIVO" bare (0166) ---';
  -- MESMA convenção, CÓDIGO DIFERENTE: a 0165 corrigiu a reconciliação (que
  -- compara VALORES); a exigência `passivo_mais_pl` do checklist só pergunta se
  -- a linha EXISTE, e tinha quatro localizadores — nenhum casava "PASSIVO"
  -- sozinho. Eram cinco pendências `linha_exigida_ausente` no lote real,
  -- cobrando do cliente uma linha que ele já tinha entregado.
  --
  -- O caso do bloco 1 é o fixture: o balanço da AMOBELEZA, cujo único rótulo de
  -- passivo é "PASSIVO". Com o localizador 5 desligado, o assert abaixo reprova.
  select count(*) into v_num
  from fn_exigencias_do_caso(v_caso)
  where tipo_taxonomia = 'BALANCO' and conceito = 'passivo_mais_pl' and satisfeita;
  perform teste_assert_passivo(v_num > 0,
    'a exigência "Passivo + Patrimônio Líquido (total)" é satisfeita por um balanço cujo rótulo '
    || 'é só "PASSIVO"',
    format('%s exigência(s) satisfeita(s) — zero significa que o Kit Básico voltou a cobrar a '
           || 'linha que o documento já traz', v_num));

  -- E O CONTRAPOSITIVO DO LOCALIZADOR: ele casa "PASSIVO" e mais nada. Se
  -- casasse "PASSIVO CIRCULANTE", um balanço com só o circulante extraído
  -- satisfaria a exigência do lado direito INTEIRO — e o Kit Básico passaria a
  -- dizer "recebido" sobre meio balanço.
  perform teste_assert_passivo(
    fn_rotulo_estrutural('PASSIVO', array['passivo']) and
    not fn_rotulo_estrutural('PASSIVO CIRCULANTE', array['passivo']) and
    not fn_rotulo_estrutural('PASSIVO E PATRIMÔNIO LÍQUIDO', array['passivo']),
    'o localizador novo casa "PASSIVO" e NÃO casa "PASSIVO CIRCULANTE" nem "PASSIVO E PL"',
    format('PASSIVO=%s, PASSIVO CIRCULANTE=%s, PASSIVO E PL=%s',
           fn_rotulo_estrutural('PASSIVO', array['passivo']),
           fn_rotulo_estrutural('PASSIVO CIRCULANTE', array['passivo']),
           fn_rotulo_estrutural('PASSIVO E PATRIMÔNIO LÍQUIDO', array['passivo'])));

  raise notice 'PASSIVO BARE OK — o rótulo é ambíguo, quem desambigua é o valor, e o checklist aprendeu junto';
end $$;

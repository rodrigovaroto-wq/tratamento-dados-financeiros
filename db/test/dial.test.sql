-- Testes do dial de autonomia (db/migrations/0041).
-- Rodar via db/test/run.sh (que aplica as migrations antes).
--
-- O QUE ESTES TESTES TRAVAM. Até a 0041, `estagio_autonomia` não tinha um único
-- leitor: o dial de `extracao_linhas_financeiras` dizia N0 ("roda, registra, NÃO
-- influencia decisão") e `fn_registrar_campos_extraidos` auto-aceitava toda linha
-- com confiança >= 0.95 HARDCODED. O sistema declarava uma coisa e fazia outra, e
-- nenhum teste podia notar, porque não havia nada ligando as duas.
--
-- As propriedades travadas aqui são, nesta ordem de importância:
--
--   1. N0/N1 auto-aceita NADA. É o que faz "baixar o dial" ser um freio de
--      verdade, e não um comentário — se isto quebrar, desligar a autonomia por
--      chamada deixa de funcionar sem nada acusar.
--   2. O LIMIAR sai da tabela, não do código: mudar `limiar_auto_clear` muda o
--      resultado sem tocar em uma linha de SQL de função.
--   3. O TETO recusa, e a tentativa fica registrada.
--   4. Guarda disparada continua suprimindo o auto-aceite (o que a 0029 fechou)
--      — a 0041 mexeu justamente nesse bloco, e regressão ali reabre o furo de
--      anti-ancoragem que é o princípio inegociável do projeto.
--
-- Por que os cenários passam por `fn_registrar_campos_extraidos` de verdade em vez
-- de conferir o dial isolado: o defeito era a DESCONEXÃO entre o dial e a extração.
-- Um teste que só lesse `fn_dial` passaria com o 0.95 hardcoded de volta no lugar.

\set ON_ERROR_STOP on

create or replace function teste_assert_dial(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_ok then
    raise notice 'ok    %', p_nome;
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

-- Registra um documento novo e uma extração, e devolve a versão. Cada cenário
-- precisa de uma versão VIRGEM: auto-aceite é decidido no momento da gravação, e
-- reaproveitar versão faria o cenário seguinte medir o aceite do anterior.
create or replace function teste_dial_extrair(p_caso uuid, p_hash text, p_campos jsonb)
returns uuid language plpgsql as $$
declare v_r jsonb; v_ver uuid;
begin
  v_r := fn_registrar_documento(
    p_caso, 'Dial Ltda.', 'anual', '2025', 'BALANCO', 0.95, 'nome_arquivo',
    'supabase_storage', 'bucket/'||p_hash||'.pdf', 'BP '||p_hash||'.pdf', true, p_hash, 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, p_campos, 'N2');
  return v_ver;
end $$;

do $$
declare
  v_caso uuid;
  v_r jsonb;
  v_ver uuid;
  v_n int;
  v_txt text;
  v_campos jsonb;
begin
  v_caso := (fn_upsert_caso('Caso dial de autonomia'))::uuid;

  -- Duas linhas: uma ACIMA do limiar de 0.95, uma abaixo. A de baixo fica em 0.90
  -- (e não em 0.5) de propósito: abaixo de 0.7 ela acionaria o Sinal 2, e o
  -- cenário passaria a medir a guarda em vez do dial.
  v_campos := jsonb_build_array(
    jsonb_build_object('ordem', 0, 'chave', 'Caixa e equivalentes', 'valor_texto', '1.200',
                       'valor_num', '1200', 'unidade', 'milhar', 'moeda', 'BRL', 'confianca', '0.98',
                       'secao_canonica', 'ativo_circulante'),
    jsonb_build_object('ordem', 1, 'chave', 'Adiantamentos diversos', 'valor_texto', '340',
                       'valor_num', '340', 'unidade', 'milhar', 'moeda', 'BRL', 'confianca', '0.90',
                       'secao_canonica', 'ativo_circulante'));

  raise notice '--- 1. a 0041 DECLAROU o dial, e a declaração está na trilha ---';
  v_r := fn_dial('extracao_linhas_financeiras');
  perform teste_assert_dial((v_r->>'nivel_atual') = 'N2',
    'o dial da extração declara N2 (era N0 enquanto o código auto-aceitava)', v_r::text);
  perform teste_assert_dial((v_r->>'limiar_auto_clear')::numeric = 0.95,
    'e o limiar de 0.95 que estava hardcoded agora é dado', v_r::text);
  perform teste_assert_dial((v_r->>'no_teto')::boolean,
    'a extração está NO TETO — não há para onde subir sem decisão de doutrina', v_r::text);
  perform teste_assert_dial(
    exists (select 1 from evento_auditoria
            where acao = 'mudanca_dial'
              and entidade_ref = 'estagio:extracao_linhas_financeiras'
              and ator = 'sistema:0041'),
    'a subida ficou registrada em evento_auditoria (docs/01: versionada e reversível)');
  -- O motivo tem de dizer que este N2 NÃO é autonomia medida. É a ressalva da
  -- 0019, e ela precisa viajar com o registro — sem isso, alguém lê "N2" daqui a
  -- seis meses e conclui que houve medição contra golden set.
  select depois->>'motivo' into v_txt from evento_auditoria
    where acao = 'mudanca_dial' and ator = 'sistema:0041' limit 1;
  perform teste_assert_dial(v_txt like '%golden%',
    'e o motivo registra a ressalva: N2 declarado, não medido', coalesce(v_txt, '(null)'));

  raise notice '--- 2. em N2, a linha acima do limiar é auto-aceita e a de baixo NÃO ---';
  v_ver := teste_dial_extrair(v_caso, 'HASH-N2', v_campos);
  select status_aceite into v_txt from campo_extraido
    where documento_versao_id = v_ver and chave = 'Caixa e equivalentes';
  perform teste_assert_dial(v_txt = 'aceito',
    'confiança 0.98 >= limiar 0.95 em N2: aceita', coalesce(v_txt, '(null)'));
  select status_aceite into v_txt from campo_extraido
    where documento_versao_id = v_ver and chave = 'Adiantamentos diversos';
  perform teste_assert_dial(v_txt = 'pendente',
    'confiança 0.90 < limiar: segue pendente de revisão humana', coalesce(v_txt, '(null)'));
  -- O aceite tem de dizer DE ONDE veio a permissão. Sem o dial no texto, a trilha
  -- não permite reconstruir com que configuração aquela linha virou fato.
  select aceito_por into v_txt from campo_extraido
    where documento_versao_id = v_ver and chave = 'Caixa e equivalentes';
  perform teste_assert_dial(v_txt like '%dial N2%' and v_txt like '%0.95%',
    'e o aceito_por cita o dial e o limiar vigentes', coalesce(v_txt, '(null)'));

  raise notice '--- 3. em N0, NADA é auto-aceito (o freio é freio) ---';
  -- Este é o assert mais importante do arquivo: é o que prova que baixar o dial
  -- desliga a autonomia. Enquanto o 0.95 era hardcoded, N0 não desligava nada.
  v_r := fn_mudar_dial('extracao_linhas_financeiras', 'N0', 'teste:dial',
                       'desligando a autonomia para conferir que o freio existe');
  perform teste_assert_dial(coalesce((v_r->>'recusado')::boolean, false) = false,
    'baixar o dial é sempre permitido (descer nunca precisa de teto)', v_r::text);

  v_ver := teste_dial_extrair(v_caso, 'HASH-N0', v_campos);
  select count(*) into v_n from campo_extraido
    where documento_versao_id = v_ver and status_aceite = 'aceito';
  perform teste_assert_dial(v_n = 0,
    'em N0 nenhuma linha é aceita, nem a de confiança 0.98',
    format('aceitas indevidamente: %s', v_n));
  -- E em N0 não há supressão a registrar: não houve elegível. O evento de
  -- supressão é para guarda disparada (cenário 6), não para dial desligado —
  -- confundir os dois faria a trilha dizer que uma guarda pegou algo.
  perform teste_assert_dial(
    not exists (select 1 from evento_auditoria
                where acao = 'auto_aceite_suprimido'
                  and entidade_ref = 'documento_versao:'||v_ver),
    'e nada é registrado como "suprimido por guarda" — não houve guarda, houve dial');

  raise notice '--- 4. em N1 também não: só N2/N3 auto-aceitam ---';
  perform fn_mudar_dial('extracao_linhas_financeiras', 'N1', 'teste:dial', 'N1 = sugestão, não aceite');
  v_ver := teste_dial_extrair(v_caso, 'HASH-N1', v_campos);
  select count(*) into v_n from campo_extraido
    where documento_versao_id = v_ver and status_aceite = 'aceito';
  perform teste_assert_dial(v_n = 0,
    'N1 é sugestão (docs/01): a linha entra pendente para o humano decidir',
    format('aceitas indevidamente: %s', v_n));

  raise notice '--- 5. o LIMIAR vem da tabela: mudá-lo muda o resultado, SEM tocar em código ---';
  -- 0.98 estava sendo aceita no cenário 2. Com o limiar em 0.99, a MESMA linha,
  -- pela MESMA função, passa a ficar pendente. Nenhum SQL de função mudou entre
  -- os dois cenários — é a definição de "o limiar virou dado".
  perform fn_mudar_dial('extracao_linhas_financeiras', 'N2', 'teste:dial',
                        'subindo o limiar para conferir que ele sai da tabela', 0.99);
  v_ver := teste_dial_extrair(v_caso, 'HASH-LIMIAR', v_campos);
  select status_aceite into v_txt from campo_extraido
    where documento_versao_id = v_ver and chave = 'Caixa e equivalentes';
  perform teste_assert_dial(v_txt = 'pendente',
    'com limiar 0.99, a linha de 0.98 deixa de ser auto-aceita', coalesce(v_txt, '(null)'));

  -- E o caminho de volta: baixando o limiar, a mesma confiança volta a passar.
  perform fn_mudar_dial('extracao_linhas_financeiras', 'N2', 'teste:dial',
                        'voltando o limiar ao valor da 0019', 0.95);
  v_ver := teste_dial_extrair(v_caso, 'HASH-LIMIAR-VOLTA', v_campos);
  select status_aceite into v_txt from campo_extraido
    where documento_versao_id = v_ver and chave = 'Caixa e equivalentes';
  perform teste_assert_dial(v_txt = 'aceito',
    'e com o limiar de volta em 0.95 ela é aceita outra vez', coalesce(v_txt, '(null)'));

  raise notice '--- 6. guarda disparada continua suprimindo o auto-aceite (0029) ---';
  -- A 0041 mexeu no bloco de promoção. Regressão aqui reabre o furo original: uma
  -- extração alucinada — cujo padrão típico é confiança ALTA com o mesmo valor
  -- repetido em muitas contas — voltaria a entrar como FATO ACEITO.
  v_ver := teste_dial_extrair(v_caso, 'HASH-GUARDA', jsonb_build_array(
    jsonb_build_object('ordem', 0, 'chave', 'Clientes', 'valor_num', '9000',
                       'valor_texto', '9.000', 'confianca', '0.99', 'secao_canonica', 'ativo_circulante'),
    jsonb_build_object('ordem', 1, 'chave', 'Estoques', 'valor_num', '9000',
                       'valor_texto', '9.000', 'confianca', '0.99', 'secao_canonica', 'ativo_circulante'),
    jsonb_build_object('ordem', 2, 'chave', 'Adiantamentos', 'valor_num', '9000',
                       'valor_texto', '9.000', 'confianca', '0.99', 'secao_canonica', 'ativo_circulante'),
    jsonb_build_object('ordem', 3, 'chave', 'Outros créditos', 'valor_num', '9000',
                       'valor_texto', '9.000', 'confianca', '0.99', 'secao_canonica', 'ativo_circulante')));

  perform teste_assert_dial(
    exists (select 1 from pendencia where caso_id = v_caso and tipo = 'extracao_padrao_suspeito'
                                      and estado <> 'resolvida'),
    'a guarda de padrão suspeito disparou (4 contas com o mesmo valor material)');
  select count(*) into v_n from campo_extraido
    where documento_versao_id = v_ver and status_aceite = 'aceito';
  perform teste_assert_dial(v_n = 0,
    'e NENHUMA das 4 linhas de confiança 0.99 foi aceita, apesar do dial em N2',
    format('aceitas indevidamente: %s', v_n));
  perform teste_assert_dial(
    exists (select 1 from evento_auditoria
            where acao = 'auto_aceite_suprimido'
              and entidade_ref = 'documento_versao:'||v_ver),
    'a supressão fica registrada — não parece que o auto-aceite simplesmente não rodou');

  raise notice '--- 7. o TETO recusa, e a tentativa fica registrada ---';
  -- docs/01: o teto é por natureza do estágio e nenhuma chamada o sobrepõe.
  -- `extracao_linhas_financeiras` tem teto N2 (semeado na 0002).
  v_r := fn_mudar_dial('extracao_linhas_financeiras', 'N3', 'teste:dial', 'tentando passar do teto');
  perform teste_assert_dial((v_r->>'recusado') = 'true',
    'pedir N3 num estágio de teto N2 é RECUSADO', v_r::text);
  perform teste_assert_dial((v_r->>'motivo_recusa') like '%TETO%',
    'e o motivo nomeia o teto', v_r->>'motivo_recusa');
  select nivel_atual::text into v_txt from estagio_autonomia
    where estagio = 'extracao_linhas_financeiras';
  perform teste_assert_dial(v_txt = 'N2',
    'o nível NÃO mudou', coalesce(v_txt, '(null)'));
  -- Recusar não é apagar o rastro: tentar passar do teto é justamente o que a
  -- trilha precisa guardar (é por isso que a recusa é RETORNADA e não levantada —
  -- exceção desfaria este insert).
  perform teste_assert_dial(
    exists (select 1 from evento_auditoria
            where acao = 'mudanca_dial_recusada'
              and entidade_ref = 'estagio:extracao_linhas_financeiras'
              and ator = 'teste:dial'),
    'a tentativa recusada fica em evento_auditoria');

  raise notice '--- 8. o teto de N1 é respeitado nos estágios que docs/01 nunca solta ---';
  -- Reconciliação Classe B/C e classificação contábil têm teto N1 e NUNCA viram
  -- autônomas. Se este assert cair, a regra de teto virou decorativa.
  v_r := fn_mudar_dial('reconciliacao_classe_bc', 'N2', 'teste:dial', 'tentando automatizar B/C');
  perform teste_assert_dial((v_r->>'recusado') = 'true',
    'reconciliacao_classe_bc não sobe de N1', v_r::text);
  v_r := fn_mudar_dial('classificacao_contabil', 'N2', 'teste:dial', 'tentando automatizar classificação');
  perform teste_assert_dial((v_r->>'recusado') = 'true',
    'classificacao_contabil não sobe de N1', v_r::text);

  raise notice '--- 9. estágio inexistente é recusado, não criado ---';
  v_r := fn_mudar_dial('estagio_que_nao_existe', 'N3', 'teste:dial');
  perform teste_assert_dial((v_r->>'recusado') = 'true',
    'dial de estágio inexistente é recusado', v_r::text);
  select count(*) into v_n from estagio_autonomia where estagio = 'estagio_que_nao_existe';
  perform teste_assert_dial(v_n = 0,
    'e nada foi criado — estágio novo entra por migration, não por chamada');
  perform teste_assert_dial(fn_dial('estagio_que_nao_existe') is null,
    'fn_dial devolve null para estágio inexistente, não um objeto vazio');

  raise notice '--- 10. o estado final é o que a 0041 deixou (o teste não muda produção) ---';
  -- Os cenários acima mexeram no dial. Restaurar aqui não é cosmético: os testes
  -- rodam todos no MESMO banco, e um dial deixado em N0 faria qualquer teste
  -- futuro de auto-aceite passar/reprovar por motivo errado.
  perform fn_mudar_dial('extracao_linhas_financeiras', 'N2', 'teste:dial',
                        'restaurando o estado declarado pela 0041', 0.95);
  v_r := fn_dial('extracao_linhas_financeiras');
  perform teste_assert_dial((v_r->>'nivel_atual') = 'N2' and (v_r->>'limiar_auto_clear')::numeric = 0.95,
    'dial restaurado em N2 / 0.95', v_r::text);

  raise notice 'TODOS OS TESTES DO DIAL PASSARAM';
end $$;

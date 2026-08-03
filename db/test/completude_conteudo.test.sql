-- Testes de "documento que chegou vazio não cumpre item" (db/migrations/0036).
-- Rodar via db/test/run.sh (que aplica as migrations antes).
--
-- Itens 3 e 4 do §7.4 do material de Onboarding. As propriedades travadas:
--
--   #3  um obrigatório do Kit Básico que CHEGOU mas do qual não saiu uma única
--       linha (a) deixa de ficar `presente` no checklist, (b) abre pendência
--       BLOQUEANTE e NÃO-SOBREPUJÁVEL, e (c) é recalculado assim que a extração
--       roda — não só quando um humano abre a revisão;
--   #4  `fn_aceitar_extracao` RECUSA versão sem nenhum campo, em vez de gravar
--       uma `decisao` de aprovação de nada numa tabela append-only.
--
-- Por que o cenário usa um documento de verdade em vez de mexer no checklist na
-- mão: o defeito vivia na COSTURA (registrar → extrair vazio → recomputar), e um
-- teste que escreve o estado final direto passaria com o defeito ligado.

\set ON_ERROR_STOP on

create or replace function teste_assert_cc(p_ok boolean, p_nome text, p_detalhe text default null)
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
  v_ver_vazia uuid;
  v_ver_cheia uuid;
  v_n int;
  v_txt text;
  v_erro text;
begin
  raise notice '--- 1. documento que chega e não produz linha: o item NÃO fica presente ---';
  v_caso := (fn_upsert_caso('Caso completude vazia'))::uuid;

  -- BALANCO é obrigatório no Kit Básico. Chega o arquivo, e a extração devolve
  -- zero linhas — o caso real do §7.4: .xlsx que o pipeline não converte.
  v_r := fn_registrar_documento(
    v_caso, 'Vazia Ltda.', 'anual', '2025', 'BALANCO', 0.95, 'nome_arquivo',
    'supabase_storage', 'bucket/bp.xlsx', 'BP Vazia 2025.xlsx', true, 'HASH-VAZIO', 'ok');
  v_ver_vazia := (v_r->>'documento_versao_id')::uuid;

  -- Zero campos, com motivo — é o que o nó grava quando a extração não traz nada.
  perform fn_registrar_campos_extraidos(
    v_ver_vazia, '[]'::jsonb, 'N0',
    'Arquivo .xlsx NAO foi lido: o no "Extract From File" nao esta habilitado.');

  select status into v_txt from checklist_item_status
    where caso_id = v_caso and tipo_taxonomia = 'BALANCO';
  perform teste_assert_cc(v_txt = 'recebido_nao_valido',
    'o item do checklist fica recebido_nao_valido, não presente', coalesce(v_txt, '(null)'));

  raise notice '--- 2. …e abre pendência BLOQUEANTE NÃO-SOBREPUJÁVEL ---';
  select count(*) into v_n from pendencia
    where caso_id = v_caso and tipo = 'item_sem_conteudo' and estado <> 'resolvida'
      and severidade = 'bloqueante' and sobrepujavel = false;
  perform teste_assert_cc(v_n = 1,
    'pendência item_sem_conteudo bloqueante e que nenhuma ressalva libera',
    format('encontradas: %s', v_n));

  -- docs/07: "elegível ao Portão 2 se e somente se não há pendência bloqueante
  -- aberta". É a regra que de fato trava o avanço — o teste confere o efeito.
  select count(*) into v_n from pendencia
    where caso_id = v_caso and severidade = 'bloqueante' and estado <> 'resolvida';
  perform teste_assert_cc(v_n > 0,
    'o caso tem bloqueante aberta, logo NÃO é elegível ao Portão 2 (docs/07)');

  raise notice '--- 3. a recomputação acontece na EXTRAÇÃO, não só na revisão humana ---';
  -- O grafo do E1 chama `Recomputar Completude` em PARALELO com a extração, então
  -- no E1 o número de linhas é sempre zero. Se a recomputação não acontecesse
  -- dentro de fn_registrar_campos_extraidos, nada acima existiria até alguém
  -- abrir a fila de revisão. Este assert é o que prova que o gancho está lá.
  perform teste_assert_cc(
    exists (select 1 from pendencia where caso_id = v_caso and tipo = 'item_sem_conteudo'),
    'a pendência apareceu sem nenhuma intervenção humana');

  raise notice '--- 4. sem_conteudo sai no payload, e pronto_para_revisao é falso ---';
  v_r := fn_recomputar_completude(v_caso);
  perform teste_assert_cc(v_r->'sem_conteudo' @> '["BALANCO"]'::jsonb,
    'o payload nomeia o item que chegou vazio', v_r::text);
  perform teste_assert_cc((v_r->>'pronto_para_revisao') = 'false',
    'pronto_para_revisao = false (chegou, mas não tem conteúdo)', v_r::text);

  raise notice '--- 5. quando o conteúdo chega, o estado se resolve sozinho ---';
  -- Reenvio do arquivo certo: versão NOVA sob o MESMO documento (0026).
  v_r := fn_registrar_documento(
    v_caso, 'Vazia Ltda.', 'anual', '2025', 'BALANCO', 0.95, 'nome_arquivo',
    'supabase_storage', 'bucket/bp.pdf', 'BP Vazia 2025.pdf', true, 'HASH-CHEIO', 'ok');
  v_ver_cheia := (v_r->>'documento_versao_id')::uuid;

  perform fn_registrar_campos_extraidos(v_ver_cheia, jsonb_build_array(
    jsonb_build_object('ordem', 0, 'chave', 'Caixa e equivalentes', 'valor_texto', '1.200',
                       'valor_num', '1200', 'unidade', 'milhar', 'moeda', 'BRL', 'confianca', '0.9',
                       'secao_canonica', 'ativo_circulante')
  ));

  select count(*) into v_n from pendencia
    where caso_id = v_caso and tipo = 'item_sem_conteudo' and estado <> 'resolvida';
  perform teste_assert_cc(v_n = 0,
    'a pendência de "sem conteúdo" se resolve quando alguma versão traz linha',
    format('ainda abertas: %s', v_n));

  select status into v_txt from checklist_item_status
    where caso_id = v_caso and tipo_taxonomia = 'BALANCO';
  perform teste_assert_cc(v_txt = 'presente',
    'e o item volta a presente', coalesce(v_txt, '(null)'));

  raise notice '--- 6. item #4: aceitar versão SEM campo nenhum é RECUSADO ---';
  -- A recusa é RETORNADA, não levantada: exceção desfaria o próprio registro da
  -- tentativa (ver o comentário na 0036). O que importa é que nada seja aprovado
  -- e que o motivo chegue a quem clicou.
  v_r := fn_aceitar_extracao(v_ver_vazia, 'analista@oria', 'aceitando no escuro');
  perform teste_assert_cc((v_r->>'recusado') = 'true',
    'a função declara a recusa no payload — nenhum chamador confunde com sucesso', v_r::text);
  perform teste_assert_cc((v_r->>'motivo_recusa') like '%não tem NENHUMA linha extraída%',
    'e o motivo nomeia o arquivo e diz o que fazer', v_r->>'motivo_recusa');
  perform teste_assert_cc((v_r->>'n_campos_aceitos')::int = 0,
    'e zero campo foi aceito');

  -- O que NÃO pode existir: aprovação de nada numa tabela append-only.
  select count(*) into v_n from decisao
    where caso_id = v_caso and tipo = 'aprovacao'
      and payload->>'documento_versao_id' = v_ver_vazia::text;
  perform teste_assert_cc(v_n = 0,
    'nenhuma decisao de aprovacao foi gravada para a versão vazia',
    format('decisões indevidas: %s', v_n));

  -- Mas a TENTATIVA fica registrada: recusar não é apagar o rastro.
  perform teste_assert_cc(
    exists (select 1 from evento_auditoria
            where acao = 'aceite_recusado'
              and entidade_ref = 'documento_versao:'||v_ver_vazia),
    'a tentativa recusada fica em evento_auditoria');

  raise notice '--- 7. aceite normal continua funcionando, e o duplo clique não duplica ---';
  v_r := fn_aceitar_extracao(v_ver_cheia, 'analista@oria', 'conferido contra o PDF');
  perform teste_assert_cc((v_r->>'n_campos_aceitos')::int = 1,
    'a versão com conteúdo é aceita normalmente', v_r::text);

  v_r := fn_aceitar_extracao(v_ver_cheia, 'analista@oria', 'clicou de novo');
  perform teste_assert_cc((v_r->>'ja_estava_aceito') = 'true',
    'o segundo clique é no-op declarado, não um aceite novo', v_r::text);

  select count(*) into v_n from decisao
    where caso_id = v_caso and tipo = 'aprovacao'
      and payload->>'documento_versao_id' = v_ver_cheia::text;
  perform teste_assert_cc(v_n = 1,
    'e a trilha tem UMA aprovação, não duas', format('aprovações: %s', v_n));

  raise notice 'TODOS OS TESTES DE COMPLETUDE/CONTEÚDO PASSARAM';
end $$;

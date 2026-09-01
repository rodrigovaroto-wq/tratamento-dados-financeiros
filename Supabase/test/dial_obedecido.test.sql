-- Testes do dial OBEDECIDO (Supabase/migrations/0127).
-- Rodar via Supabase/test/run.sh (que aplica as migrations antes).
--
-- O QUE ESTES TESTES TRAVAM. A 0041 fez o dial mandar em UM estágio. A 0126 fez a
-- mudança do dial ser cobrada. A 0127 fez o dial ser LIDO em mais dois — e sem
-- teste, "ser lido" é a coisa mais fácil de perder numa refatoração futura: basta
-- alguém voltar a comparar com `p_threshold` e nada acusa, porque o número é o
-- mesmo. Foi assim que o 0,95 do dial ficou seis migrations sendo ignorado.
--
-- As propriedades, em ordem de importância:
--
--   1. MUDAR O LIMIAR NO DIAL MUDA O RESULTADO DA CLASSIFICAÇÃO, sem tocar em uma
--      linha de código. É a definição operacional de "o limiar virou dado", e é o
--      único assert que distingue "lê o dial" de "usa um número que por acaso é
--      igual ao do dial".
--   2. BAIXAR A CLASSIFICAÇÃO PARA N1 FORÇA REVISÃO DE TUDO. Era a capacidade que
--      o dial prometia e não entregava: até a 0127, baixar o nível não fazia nada.
--   3. CLASSE B/C EM N0 REGISTRA E NÃO ABRE PENDÊNCIA. É o que N0 significa no
--      Arquitetura do Sistema/1 Visão e Doutrina/01, e a Classe B/C declarava N0 abrindo pendência desde a 0015.
--   4. EM SOMBRA, A PENDÊNCIA QUE JÁ EXISTE NÃO É RESOLVIDA. Este é o assert mais
--      importante do arquivo: sem o ramo que a 0127 acrescentou, silenciar um
--      estágio marcaria as pendências dele como "resolvidas pelo sistema" — a
--      trilha passaria a afirmar que o problema acabou, quando o que acabou foi o
--      direito daquele estágio de falar.
--   5. AUSÊNCIA DE CONFIGURAÇÃO NÃO É PERMISSÃO — e o default seguro é oposto nas
--      duas funções, de propósito.

\set ON_ERROR_STOP on

create or replace function teste_assert_do(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_ok then
    raise notice 'ok    %', p_nome;
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

-- Registra um documento com a confiança pedida e devolve se ele abriu pendência
-- de classificação. Cada chamada usa hash próprio: `fn_registrar_documento` é
-- idempotente por hash, e reaproveitar faria o cenário seguinte medir o anterior.
create or replace function teste_do_classifica(p_caso uuid, p_conf numeric, p_sufixo text)
returns boolean language plpgsql as $$
declare v_r jsonb; v_doc uuid;
begin
  v_r := fn_registrar_documento(
    p_caso, 'Dial Obedecido Ltda.', 'anual', '2025', 'BALANCO', p_conf, 'nome_arquivo',
    'supabase_storage', 'bucket/'||p_sufixo||'.pdf', 'BP '||p_sufixo||'.pdf', true,
    'HASH-DO-'||p_sufixo, 'ok');
  v_doc := (v_r->>'documento_id')::uuid;
  return exists (select 1 from pendencia
                  where documento_id = v_doc and tipo = 'classificacao_pendente'
                    and estado <> 'resolvida');
end $$;

do $$
declare
  v_caso   uuid;
  v_ent    uuid;
  v_per    uuid;
  v_r      jsonb;
  v_n      int;
  v_txt    text;
  v_pend   uuid;
begin
  v_caso := (fn_upsert_caso('Caso dial obedecido 0127'))::uuid;

  -- ==========================================================================
  raise notice '--- 1. os dois leitores, e os defaults seguros opostos ---';
  -- ==========================================================================
  perform teste_assert_do(fn_dial_permite_auto('extracao_linhas_financeiras', 0.98),
    'N2 com confiança acima do limiar: auto permitido');
  perform teste_assert_do(not fn_dial_permite_auto('extracao_linhas_financeiras', 0.50),
    'N2 com confiança abaixo do limiar: auto NEGADO');
  perform teste_assert_do(not fn_dial_permite_auto('extracao_linhas_financeiras', null),
    'confiança nula nunca auto-aceita — "não sei" não é "pode"');
  perform teste_assert_do(not fn_dial_permite_auto('estagio_que_nao_existe', 0.99),
    'estágio SEM linha no dial: auto NEGADO (ausência de configuração não é permissão)');

  perform teste_assert_do(fn_dial_influencia('reconciliacao_classe_a'),
    'estágio em N1 INFLUENCIA — a saída dele chega à fila de alguém');
  perform teste_assert_do(fn_dial_influencia('estagio_que_nao_existe'),
    'estágio SEM linha no dial INFLUENCIA — o default seguro aqui é o OPOSTO do outro',
    'calar achado por falta de configuração esconde problema');

  -- ==========================================================================
  raise notice '--- 2. a 0127 declarou o que a classificação já fazia ---';
  -- ==========================================================================
  v_r := fn_dial('classificacao_doc_checklist');
  perform teste_assert_do((v_r->>'nivel_atual') = 'N2',
    'classificacao_doc_checklist declara N2 (o que ela sempre praticou)', v_r::text);
  perform teste_assert_do((v_r->>'limiar_auto_clear')::numeric = 0.70,
    'com o limiar 0,70 que estava DE FATO em vigor, não o 0,95 que ninguém aplicava',
    v_r::text);
  perform teste_assert_do((v_r->>'base_do_nivel') = 'declarada',
    'e a base é DECLARADA — não há golden set de classificação', v_r::text);
  perform teste_assert_do(
    exists (select 1 from evento_auditoria
             where acao = 'mudanca_dial_sem_medicao'
               and entidade_ref = 'estagio:classificacao_doc_checklist'),
    'a subida da 0127 passou pelo portão da 0126 e ficou registrada como sem medição');

  v_r := fn_dial('reconciliacao_classe_bc');
  perform teste_assert_do((v_r->>'nivel_atual') = 'N1',
    'reconciliacao_classe_bc declara N1 (ela abre pendência desde a 0015)', v_r::text);
  perform teste_assert_do((v_r->>'no_teto')::boolean,
    'e isso a coloca no TETO dela, que o Arquitetura do Sistema/1 Visão e Doutrina/01 marca como nunca autônoma', v_r::text);

  -- ==========================================================================
  raise notice '--- 3. o assert que prova que o limiar saiu do CÓDIGO ---';
  -- ==========================================================================
  -- Confiança 0,80 com limiar 0,70: passa sem humano.
  perform teste_assert_do(not teste_do_classifica(v_caso, 0.80, 'conf80-limiar70'),
    'conf 0,80 com limiar 0,70: NÃO abre pendência de classificação');

  -- O MESMO documento, a MESMA função, o MESMO código — só o dado do dial muda.
  perform fn_mudar_dial('classificacao_doc_checklist', 'N2', 'teste:dial-obedecido',
                        'subindo o limiar para conferir que ele sai da tabela', 0.90);
  perform teste_assert_do(teste_do_classifica(v_caso, 0.80, 'conf80-limiar90'),
    'com o limiar em 0,90, a MESMA confiança de 0,80 passa a abrir pendência',
    'se este assert cair, o limiar voltou para o código e o dial virou enfeite');

  -- E a mensagem diz contra o que a confiança perdeu.
  select p.descricao into v_txt from pendencia p
   where p.tipo = 'classificacao_pendente' and p.caso_id = v_caso
     and p.descricao like '%conf80-limiar90%'
   order by p.criada_em desc limit 1;
  perform teste_assert_do(v_txt like '%limiar do dial=0.90%',
    'e a descrição da pendência nomeia o limiar do dial que reprovou',
    coalesce(v_txt, '(nenhuma pendência encontrada)'));

  perform fn_mudar_dial('classificacao_doc_checklist', 'N2', 'teste:dial-obedecido',
                        'limiar de volta ao que a 0127 declarou', 0.70);

  -- ==========================================================================
  raise notice '--- 4. baixar para N1 força revisão de TUDO (a capacidade que faltava) ---';
  -- ==========================================================================
  -- Baixar é sempre permitido e não passa por portão nenhum.
  v_r := fn_mudar_dial('classificacao_doc_checklist', 'N1', 'teste:dial-obedecido',
                       'N1 = humano confirma todo item (Arquitetura do Sistema/1 Visão e Doutrina/01)');
  perform teste_assert_do(coalesce((v_r->>'recusado')::boolean, false) = false,
    'baixar a classificação para N1 é permitido sem apresentar nada', v_r::text);

  perform teste_assert_do(teste_do_classifica(v_caso, 0.99, 'n1-conf99'),
    'em N1, até a confiança de 0,99 abre pendência — é o que "humano confirma todo item" quer dizer',
    'antes da 0127 baixar o nível não fazia absolutamente nada');

  perform fn_mudar_dial('classificacao_doc_checklist', 'N2', 'teste:dial-obedecido',
                        'restaurando o N2 da 0127', 0.70, null,
                        'arnês de teste restaurando o estado da 0127; não é medição');

  -- ==========================================================================
  raise notice '--- 5. Classe B/C: N1 abre pendência, N0 registra e cala ---';
  -- ==========================================================================
  -- Reaproveita entidade e período se já existirem: os cenários anteriores
  -- chamaram `fn_registrar_documento`, que cria os dois. Inserir à força colide
  -- com a unicidade de `periodo (caso, tipo, referencia)` — e o teste morreria por
  -- uma colisão de arnês, não por um defeito do produto.
  select id into v_ent from entidade
   where caso_id = v_caso and razao_social = 'Dial Obedecido Ltda.';
  if v_ent is null then
    insert into entidade (caso_id, razao_social) values (v_caso, 'Dial Obedecido Ltda.')
      returning id into v_ent;
  end if;
  select id into v_per from periodo where caso_id = v_caso and referencia = '2025';
  if v_per is null then
    insert into periodo (caso_id, tipo, referencia) values (v_caso, 'anual', '2025')
      returning id into v_per;
  end if;

  -- Em N1 (o que a 0127 declarou), a divergência abre pendência.
  v_r := fn_registrar_reconciliacao(
    v_caso, v_ent, v_per, 'teste_classe_b_n1', 'B', null,
    jsonb_build_object('valor', 100), jsonb_build_object('valor', 140),
    'divergente', 40, 0.4, jsonb_build_object('limiar', 5),
    'Divergência de teste da Classe B em N1');
  perform teste_assert_do((v_r->>'pendencia_id') is not null,
    'em N1 a Classe B abre pendência', v_r::text);
  v_pend := (v_r->>'pendencia_id')::uuid;

  select count(*) into v_n from reconciliacao
   where caso_id = v_caso and tipo = 'teste_classe_b_n1' and classe = 'B';
  perform teste_assert_do(v_n = 1, 'e registra a reconciliação', format('%s linha(s)', v_n));

  -- Agora em N0. Baixar é livre.
  perform fn_mudar_dial('reconciliacao_classe_bc', 'N0', 'teste:dial-obedecido',
                        'sombra: registra e não influencia (Arquitetura do Sistema/1 Visão e Doutrina/01)');
  v_r := fn_registrar_reconciliacao(
    v_caso, v_ent, v_per, 'teste_classe_b_n0', 'B', null,
    jsonb_build_object('valor', 100), jsonb_build_object('valor', 180),
    'divergente', 80, 0.8, jsonb_build_object('limiar', 5),
    'Divergência de teste da Classe B em N0');
  perform teste_assert_do((v_r->>'pendencia_id') is null,
    'em N0 a Classe B NÃO abre pendência — é o que sombra significa', v_r::text);

  select count(*) into v_n from reconciliacao
   where caso_id = v_caso and tipo = 'teste_classe_b_n0' and classe = 'B';
  perform teste_assert_do(v_n = 1,
    'e AINDA registra em reconciliacao — "roda e registra" é a outra metade de N0',
    format('%s linha(s)', v_n));

  perform teste_assert_do(
    exists (select 1 from evento_auditoria
             where acao = 'reconciliacao_em_sombra'
               and depois->>'estagio' = 'reconciliacao_classe_bc'),
    'e a sombra fica na trilha — não parece que a checagem simplesmente não rodou');

  -- A Classe A no MESMO momento continua abrindo: o dial é POR ESTÁGIO, e
  -- silenciar B/C não pode silenciar A.
  v_r := fn_registrar_reconciliacao(
    v_caso, v_ent, v_per, 'teste_classe_a_junto', 'A', null,
    jsonb_build_object('valor', 100), jsonb_build_object('valor', 130),
    'divergente', 30, 0.3, jsonb_build_object('limiar', 5),
    'Divergência de teste da Classe A, com a B em sombra');
  perform teste_assert_do((v_r->>'pendencia_id') is not null,
    'a Classe A continua abrindo pendência com a B/C em sombra — o dial é por estágio',
    v_r::text);

  -- ==========================================================================
  raise notice '--- 6. em sombra, a pendência que JÁ EXISTE não é resolvida ---';
  -- ==========================================================================
  -- Este é o ramo que a 0127 acrescentou, e o motivo dele é a trilha. Sem ele, a
  -- chamada abaixo cairia no `elsif` que fecha pendência e marcaria a de N1 como
  -- "resolvida por sistema:reconciliacao" — afirmando que o sintoma acabou quando
  -- o que acabou foi o direito do estágio de falar.
  select estado::text into v_txt from pendencia where id = v_pend;
  perform teste_assert_do(v_txt <> 'resolvida',
    'a pendência aberta em N1 continua aberta depois de o estágio ir para sombra',
    format('estado=%s', coalesce(v_txt, '(null)')));

  -- E a mesma checagem, rodando de novo em sombra com a divergência ainda lá,
  -- não a resolve tampouco.
  perform fn_registrar_reconciliacao(
    v_caso, v_ent, v_per, 'teste_classe_b_n1', 'B', null,
    jsonb_build_object('valor', 100), jsonb_build_object('valor', 140),
    'divergente', 40, 0.4, jsonb_build_object('limiar', 5),
    'A MESMA divergência, agora com o estágio em sombra');
  select estado::text into v_txt from pendencia where id = v_pend;
  perform teste_assert_do(v_txt <> 'resolvida',
    'nem quando a MESMA checagem roda outra vez em sombra: o sintoma não sumiu',
    format('estado=%s', coalesce(v_txt, '(null)')));

  -- Mas quando a divergência REALMENTE desaparece, com o estágio de volta em N1,
  -- a pendência fecha — o caminho normal continua funcionando.
  perform fn_mudar_dial('reconciliacao_classe_bc', 'N1', 'teste:dial-obedecido',
                        'de volta ao N1 da 0127');
  perform fn_registrar_reconciliacao(
    v_caso, v_ent, v_per, 'teste_classe_b_n1', 'B', null,
    jsonb_build_object('valor', 100), jsonb_build_object('valor', 100),
    'ok', 0, 0, jsonb_build_object('limiar', 5), 'Agora fecha');
  select estado::text into v_txt from pendencia where id = v_pend;
  perform teste_assert_do(v_txt = 'resolvida',
    'e com o sintoma DE FATO resolvido e o estágio em N1, a pendência fecha',
    format('estado=%s', coalesce(v_txt, '(null)')));

  -- ==========================================================================
  raise notice '--- 7. o estado final é o que as migrations deixaram ---';
  -- ==========================================================================
  select count(*) into v_n from estagio_autonomia
   where estagio = 'classificacao_doc_checklist'
     and nivel_atual = 'N2' and limiar_auto_clear = 0.70 and base_do_nivel = 'declarada';
  perform teste_assert_do(v_n = 1, 'classificacao_doc_checklist em N2 / 0,70 / declarada');
  select count(*) into v_n from estagio_autonomia
   where estagio = 'reconciliacao_classe_bc' and nivel_atual = 'N1';
  perform teste_assert_do(v_n = 1, 'reconciliacao_classe_bc em N1');

  raise notice 'TODOS OS TESTES DO DIAL OBEDECIDO PASSARAM';
end $$;

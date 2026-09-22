-- Testes do portão D6 — cobertura de tipos (Supabase/migrations/0187).
-- Rodar via Supabase/test/run.sh (que aplica as migrations e carrega as
-- fixtures ANTES — o bloco 4 e o 5 leem o caso canastra).
--
-- O QUE ESTE ARQUIVO TRAVA, em comportamento:
--
--   1. D6 ESTRITO NO BANCO MONTADO DO ZERO: todo tipo ATIVO da taxonomia sai
--      de fn_cobertura_de_tipos com exigência viva ou declaração válida — e a
--      sonda de instalação diz o mesmo.
--   2. A DECLARAÇÃO É O QUE COBRE: tirada a de um tipo, ele vira
--      SEM_COBERTURA e a sonda fica vermelha.
--   3. A DECLARAÇÃO ENVELHECE ALTO: consumidor que não existe em pg_proc, ou
--      declaração para tipo que já tem exigência viva, vira
--      DECLARACAO_QUEBRADA; e o banco recusa consumidor_nomeado sem nome.
--   4. CONTRA A FIXTURE CANASTRA (o arranjo que produção tem — chaves = par de
--      empresas, a palavra só na seção): MUTUOS e FAT_INTRAGRUPO deixam de
--      aparecer como exigência não satisfeita.
--   5. A RESOLUÇÃO DIRIGIDA: a pendência aberta que o Portão 1 abria para
--      esses dois tipos antes da 0187 é resolvida por sistema:0187, com
--      evento de auditoria; a aceita_com_ressalva e as pendências de OUTROS
--      tipos não se mexem.
--   6. CONTRATO_SOCIAL, OS DOIS SENTIDOS: capital social na SEÇÃO satisfaz (e
--      a pendência antiga resolve); SEM capital nem na chave nem na seção
--      continua não satisfeita e a pendência FICA ABERTA — a correção não pode
--      virar "sempre passa". O arranjo positivo NÃO está em fixture nenhuma (o
--      CONTRATO_SOCIAL da canastra não tem linha, 0111): os rótulos abaixo são
--      os LITERAIS medidos no documento de produção em 22/09/2026 (entidade
--      GLOBAL STORE — chave "Total — Valor R$", seção "CLÁUSULA V - Capital
--      social"). O negativo troca só a cláusula. Regra 4: não é fixture
--      inventada para provar o bug, é o rótulo que produção tem.
--
-- O ASSERT NÃO PARA NO PRIMEIRO ERRO. Ele anota e segue, e o bloco final
-- reprova com a CONTAGEM — é o que permite medir quantos asserts cada correção
-- desligada derruba (regra 2), em vez de ver sempre "1".
--
-- TUDO EM UMA TRANSAÇÃO QUE TERMINA EM ROLLBACK: o arquivo reativa exigências,
-- apaga declarações e roda recompute no caso canastra, e nada disso pode
-- vazar para os testes seguintes.

begin;

create temp table _falhas_cobertura (nome text) on commit drop;

create or replace function pg_temp.teste_assert_cob(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if coalesce(p_ok, false) then
    raise notice 'ok    %', p_nome;
  else
    raise notice 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
    insert into _falhas_cobertura values (p_nome);
  end if;
end $$;

do $$
declare
  c_canastra constant uuid := '11111111-3333-3333-3333-111111111111';
  c_tipos    constant text[] := array['MUTUOS', 'FAT_INTRAGRUPO', 'CONTRATO_SOCIAL'];
  v_n        int;
  v_n2       int;
  v_txt      text;
  v_bool     boolean;
  v_decl     taxonomia_tipo_cobertura;
  v_loc      taxonomia_linha_localizador;
  v_r        jsonb;
  v_pend_mut uuid;
  v_pend_fat uuid;
  v_outras   text;
  v_outras2  text;
  v_caso_pos uuid;
  v_caso_neg uuid;
  v_pend_pos uuid;
  v_pend_neg uuid;
  v_ver      uuid;
  v_erro     boolean;
begin
  -- ===========================================================================
  raise notice '--- 1. D6 estrito no banco montado do zero ---';
  select count(*) into v_n from fn_cobertura_de_tipos()
   where veredito in ('SEM_COBERTURA', 'DECLARACAO_QUEBRADA');
  select string_agg(tipo_taxonomia || '=' || veredito, ', ') into v_txt from fn_cobertura_de_tipos()
   where veredito in ('SEM_COBERTURA', 'DECLARACAO_QUEBRADA');
  perform pg_temp.teste_assert_cob(v_n = 0,
    'nenhum tipo ativo SEM_COBERTURA nem DECLARACAO_QUEBRADA', coalesce(v_txt, ''));

  select count(*) into v_n from fn_cobertura_de_tipos();
  select count(*) into v_n2 from taxonomia_tipo_documento where ativo;
  perform pg_temp.teste_assert_cob(v_n = v_n2 and v_n > 0,
    'uma linha por tipo ATIVO — o portão não depende de documento',
    format('%s linhas, %s tipos ativos', v_n, v_n2));

  select veredito into v_txt from fn_cobertura_de_tipos() where tipo_taxonomia = 'BALANCO';
  perform pg_temp.teste_assert_cob(v_txt = 'exigencia_viva',
    'BALANCO é coberto pela exigência viva, não por declaração', v_txt);

  select veredito, consumidor_existe into v_txt, v_bool
    from fn_cobertura_de_tipos() where tipo_taxonomia = 'MUTUOS';
  perform pg_temp.teste_assert_cob(v_txt = 'consumidor_nomeado' and v_bool,
    'MUTUOS tem consumidor nomeado e ele existe (fn_reconciliar_mutuos)',
    format('%s / existe=%s', v_txt, v_bool));

  select presente into v_bool from fn_instalacao_conferir() where chave = 'd6_cobertura_de_tipos_estrita';
  perform pg_temp.teste_assert_cob(v_bool, 'a sonda de instalação responde D6 verde',
    coalesce(v_bool::text, 'requisito ausente do catálogo'));

  -- ===========================================================================
  raise notice '--- 2. sem a declaração, o tipo fica SEM_COBERTURA ---';
  delete from taxonomia_tipo_cobertura where tipo_taxonomia = 'AGING_AP' returning * into v_decl;

  select veredito into v_txt from fn_cobertura_de_tipos() where tipo_taxonomia = 'AGING_AP';
  perform pg_temp.teste_assert_cob(v_txt = 'SEM_COBERTURA',
    'AGING_AP sem declaração e sem exigência viva vira SEM_COBERTURA', v_txt);

  select presente into v_bool from fn_instalacao_conferir() where chave = 'd6_cobertura_de_tipos_estrita';
  perform pg_temp.teste_assert_cob(v_bool = false,
    'e a sonda de instalação fica VERMELHA — não só a função', coalesce(v_bool::text, 'null'));

  if v_decl.tipo_taxonomia is not null then
    insert into taxonomia_tipo_cobertura select (v_decl).*;
  end if;

  -- ===========================================================================
  raise notice '--- 3. declaração que envelheceu vira DECLARACAO_QUEBRADA ---';
  update taxonomia_tipo_cobertura set consumidor = 'fn_que_nao_existe_0187'
   where tipo_taxonomia = 'MUTUOS';
  select veredito, consumidor_existe into v_txt, v_bool
    from fn_cobertura_de_tipos() where tipo_taxonomia = 'MUTUOS';
  perform pg_temp.teste_assert_cob(v_txt = 'DECLARACAO_QUEBRADA' and v_bool = false,
    'consumidor nomeado que não existe em pg_proc é DECLARACAO_QUEBRADA',
    format('%s / existe=%s', v_txt, v_bool));
  update taxonomia_tipo_cobertura set consumidor = 'fn_reconciliar_mutuos'
   where tipo_taxonomia = 'MUTUOS';

  insert into taxonomia_tipo_cobertura (tipo_taxonomia, estado, consumidor, motivo, efeito)
  values ('BALANCO', 'sem_consumidor', null, 'teste', 'teste');
  select veredito into v_txt from fn_cobertura_de_tipos() where tipo_taxonomia = 'BALANCO';
  perform pg_temp.teste_assert_cob(v_txt = 'DECLARACAO_QUEBRADA',
    'declaração para tipo que JÁ tem exigência viva é duplo registro: DECLARACAO_QUEBRADA', v_txt);
  delete from taxonomia_tipo_cobertura where tipo_taxonomia = 'BALANCO';

  v_erro := false;
  begin
    insert into taxonomia_tipo_cobertura (tipo_taxonomia, estado, consumidor, motivo, efeito)
    values ('BALANCO', 'consumidor_nomeado', null, 'teste', 'teste');
  exception when check_violation then
    v_erro := true;
  end;
  perform pg_temp.teste_assert_cob(v_erro,
    'o banco recusa consumidor_nomeado SEM o nome do consumidor');

  -- ===========================================================================
  raise notice '--- 4. canastra: MUTUOS e FAT_INTRAGRUPO deixam de ser cobrados pelo rótulo ---';
  select count(*) into v_n from documento
   where caso_id = c_canastra and tipo_taxonomia in ('MUTUOS', 'FAT_INTRAGRUPO');
  perform pg_temp.teste_assert_cob(v_n = 2,
    'pré-condição: a fixture canastra traz o MUTUOS e o FAT_INTRAGRUPO', 'achou ' || v_n);

  select count(*) into v_n from fn_exigencias_do_caso(c_canastra)
   where tipo_taxonomia = 'MUTUOS' and not satisfeita;
  perform pg_temp.teste_assert_cob(v_n = 0,
    'MUTUOS da canastra (chave = par de empresas) não aparece como exigência não satisfeita',
    'achou ' || v_n);

  select count(*) into v_n from fn_exigencias_do_caso(c_canastra)
   where tipo_taxonomia = 'FAT_INTRAGRUPO' and not satisfeita;
  perform pg_temp.teste_assert_cob(v_n = 0,
    'FAT_INTRAGRUPO da canastra não aparece como exigência não satisfeita', 'achou ' || v_n);

  -- ===========================================================================
  raise notice '--- 5. resolução dirigida contra o estado de ANTES da 0187 ---';
  -- O estado de antes, pela costura real: exigências reativadas e o recompute
  -- que produção já rodou. É o que deixa as pendências abertas que a 0187
  -- encontra no banco.
  update taxonomia_linha_exigida set ativo = true
   where origem = 'proposta'
     and (tipo_taxonomia, conceito) in (('MUTUOS', 'saldo_de_mutuo'),
                                        ('FAT_INTRAGRUPO', 'faturamento_entre_partes'));
  perform fn_recomputar_completude(c_canastra);

  select id into v_pend_mut from pendencia
   where caso_id = c_canastra and tipo = 'linha_exigida_ausente' and estado = 'aberta'
     and motivo like 'completude:linha_exigida:MUTUOS:saldo_de_mutuo%';
  select id into v_pend_fat from pendencia
   where caso_id = c_canastra and tipo = 'linha_exigida_ausente' and estado = 'aberta'
     and motivo like 'completude:linha_exigida:FAT_INTRAGRUPO:faturamento_entre_partes%';
  perform pg_temp.teste_assert_cob(v_pend_mut is not null and v_pend_fat is not null,
    'pré-condição: com a exigência lexical, a canastra abre as DUAS pendências falsas de produção',
    format('mutuos=%s fat=%s', v_pend_mut, v_pend_fat));

  -- A decisão humana que produção tem (lá é um MUTUOS; aqui o FAT, para as
  -- duas situações existirem no mesmo caso).
  update pendencia set estado = 'aceita_com_ressalva' where id = v_pend_fat;

  select string_agg(id::text || ':' || estado::text, ',' order by id) into v_outras
    from pendencia
   where caso_id = c_canastra
     and not (tipo = 'linha_exigida_ausente' and split_part(motivo, ':', 3) = any (c_tipos));

  update taxonomia_linha_exigida set ativo = false
   where origem = 'proposta'
     and (tipo_taxonomia, conceito) in (('MUTUOS', 'saldo_de_mutuo'),
                                        ('FAT_INTRAGRUPO', 'faturamento_entre_partes'));
  v_r := fn_resolver_linha_exigida_superada(c_tipos, 'sistema:0187');

  select estado::text || '/' || coalesce(resolvida_por, '') into v_txt from pendencia where id = v_pend_mut;
  perform pg_temp.teste_assert_cob(v_txt = 'resolvida/sistema:0187',
    'a pendência aberta de MUTUOS é resolvida por sistema:0187', v_txt);

  select count(*) into v_n from evento_auditoria
   where ator = 'sistema:0187' and acao = 'pendencia_resolvida'
     and entidade_ref = 'pendencia:' || v_pend_mut
     and depois->>'razao' = 'exigencia_inativa';
  perform pg_temp.teste_assert_cob(v_n = 1,
    'com UM evento de auditoria que diz a razão (exigência inativa)', 'achou ' || v_n);

  select estado::text into v_txt from pendencia where id = v_pend_fat;
  perform pg_temp.teste_assert_cob(v_txt = 'aceita_com_ressalva',
    'a aceita_com_ressalva NÃO é tocada — é decisão humana', v_txt);

  select string_agg(id::text || ':' || estado::text, ',' order by id) into v_outras2
    from pendencia
   where caso_id = c_canastra
     and not (tipo = 'linha_exigida_ausente' and split_part(motivo, ':', 3) = any (c_tipos));
  perform pg_temp.teste_assert_cob(v_outras2 is not distinct from v_outras,
    'nenhuma pendência de OUTRO tipo muda de estado (dirigida, não recompute)');

  -- ===========================================================================
  raise notice '--- 6. CONTRATO_SOCIAL: capital na cláusula passa, sem capital continua cobrado ---';
  v_caso_pos := (fn_upsert_caso('Caso 0187 — contrato social, capital na cláusula'))::uuid;
  v_ver := (fn_registrar_documento(
    v_caso_pos, 'Global Store Ltda', 'anual', '2025', 'CONTRATO_SOCIAL', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/cs-0187-pos.pdf', 'Contrato Social Global Store.pdf', true,
    'HASH-0187-CS-POS', 'ok')->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "Total — Valor R$", "valor_num": "500000", "secao": "CLÁUSULA V - Capital social", "confianca": "0.9"}
  ]'::jsonb, 'N0');

  v_caso_neg := (fn_upsert_caso('Caso 0187 — contrato social, sem capital'))::uuid;
  v_ver := (fn_registrar_documento(
    v_caso_neg, 'Global Store Ltda', 'anual', '2025', 'CONTRATO_SOCIAL', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/cs-0187-neg.pdf', 'Contrato Social Sem Capital.pdf', true,
    'HASH-0187-CS-NEG', 'ok')->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "Total — Valor R$", "valor_num": "500000", "secao": "CLÁUSULA II - Do objeto social", "confianca": "0.9"}
  ]'::jsonb, 'N0');

  select bool_and(satisfeita), count(*) into v_bool, v_n from fn_exigencias_do_caso(v_caso_pos)
   where tipo_taxonomia = 'CONTRATO_SOCIAL';
  perform pg_temp.teste_assert_cob(v_n >= 1 and v_bool,
    'capital social na SEÇÃO ("CLÁUSULA V - Capital social") satisfaz a exigência',
    format('%s linha(s), satisfeita=%s', v_n, v_bool));

  select count(*) into v_n from pendencia
   where caso_id = v_caso_pos and tipo = 'linha_exigida_ausente' and estado <> 'resolvida';
  perform pg_temp.teste_assert_cob(v_n = 0,
    'e o contrato com o capital na cláusula não abre pendência', 'achou ' || v_n);

  select bool_or(not satisfeita) into v_bool from fn_exigencias_do_caso(v_caso_neg)
   where tipo_taxonomia = 'CONTRATO_SOCIAL';
  perform pg_temp.teste_assert_cob(v_bool,
    'NEGATIVO: sem "capital" nem na chave nem na seção, continua NÃO satisfeita',
    coalesce(v_bool::text, 'exigência nem avaliada'));

  select id into v_pend_neg from pendencia
   where caso_id = v_caso_neg and tipo = 'linha_exigida_ausente' and estado = 'aberta'
     and motivo like 'completude:linha_exigida:CONTRATO_SOCIAL:capital_social%';
  perform pg_temp.teste_assert_cob(v_pend_neg is not null,
    'NEGATIVO: e a pendência de capital social abre');

  -- O estado de antes da 0187 para o contrato positivo: sem o localizador de
  -- seção, o recompute abre a pendência falsa que produção tem.
  delete from taxonomia_linha_localizador l
   using taxonomia_linha_exigida e
   where e.id = l.exigencia_id and e.tipo_taxonomia = 'CONTRATO_SOCIAL'
     and e.conceito = 'capital_social' and l.contra = 'secao'
  returning l.* into v_loc;
  perform fn_recomputar_completude(v_caso_pos);
  select id into v_pend_pos from pendencia
   where caso_id = v_caso_pos and tipo = 'linha_exigida_ausente' and estado = 'aberta'
     and motivo like 'completude:linha_exigida:CONTRATO_SOCIAL:capital_social%';
  perform pg_temp.teste_assert_cob(v_pend_pos is not null,
    'pré-condição: sem o localizador de seção, o contrato de produção abre a pendência falsa');
  if v_loc.id is not null then
    insert into taxonomia_linha_localizador select (v_loc).*;
  end if;

  v_r := fn_resolver_linha_exigida_superada(c_tipos, 'sistema:0187');

  select estado::text || '/' || coalesce(resolvida_por, '') into v_txt from pendencia where id = v_pend_pos;
  perform pg_temp.teste_assert_cob(v_txt = 'resolvida/sistema:0187',
    'com o localizador de volta, a pendência do contrato positivo é resolvida por sistema:0187', v_txt);

  select count(*) into v_n from evento_auditoria
   where ator = 'sistema:0187' and entidade_ref = 'pendencia:' || v_pend_pos
     and depois->>'razao' = 'exigencia_ativa_nao_mais_ausente';
  perform pg_temp.teste_assert_cob(v_n = 1,
    'e o evento diz que a exigência continua ATIVA e agora está satisfeita', 'achou ' || v_n);

  select estado::text into v_txt from pendencia where id = v_pend_neg;
  perform pg_temp.teste_assert_cob(v_txt = 'aberta',
    'NEGATIVO: a pendência do contrato sem capital FICA ABERTA — a resolução não é "resolve tudo"',
    coalesce(v_txt, 'null'));
  perform pg_temp.teste_assert_cob(coalesce((v_r->>'ficaram_abertas')::int, 0) >= 1,
    'e a função conta essa pendência como "ficou aberta"', v_r::text);
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from _falhas_cobertura;
  if v_n > 0 then
    raise exception 'FALHOU: % assert(s) de cobertura de tipos (0187) reprovaram — ver as linhas FALHOU acima', v_n;
  end if;
  raise notice 'TODOS OS TESTES DE COBERTURA DE TIPOS (0187) PASSARAM';
end $$;

rollback;

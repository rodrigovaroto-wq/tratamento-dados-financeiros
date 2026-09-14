-- =============================================================================
-- 0171 — o CNPJ também renomeia, não só funde
--
-- OS NOMES SÃO OS REAIS (regra 4): os quatro nomes da OMNIBEAUTY do caso
-- "teste 143", com o CNPJ real 36.193.378/0001-04.
--
-- O QUE ESTE ARQUIVO MEDE:
--   1. o nome contaminado pelo endereço, mais LONGO, chegando DEPOIS do nome
--      certo, não vence — é o cenário que motivou a fatia;
--   2. e chegando ANTES do nome certo, também não vence — a ordem de chegada
--      não deveria mudar qual nome sobrevive quando o CNPJ prova identidade;
--   3. entre dois nomes SEM sufixo, o que não tem cara de endereço vence
--      mesmo sendo mais curto (SURUBIJU vence SURUBIJU,1930);
--   4. o sufixo societário vence o nome truncado sem sufixo;
--   5. o rastro (entidade_renomeada_por_cnpj) só aparece quando o nome
--      REALMENTE mudou — não em todo documento que casa por CNPJ;
--   6. os ramos de casamento APROXIMADO (sem CNPJ) continuam SEM renomear —
--      escopo desta fatia é só o ramo (0).
-- =============================================================================

create or replace function teste_assert_ren(p_cond boolean, p_nome text, p_detalhe text default null)
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
  c_cnpj  constant text := '36.193.378/0001-04';
  c_t     constant text := 'OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE';
  c_m     constant text := 'OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE MARCAS LTDA';
  c_s     constant text := 'OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE SURUBIJU';
  c_s1930 constant text := 'OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE SURUBIJU, 1930';
  v_caso  uuid;
  v_id    uuid;
  v_nome  text;
  v_n     int;
BEGIN
  raise notice '--- 1. o contaminado (mais LONGO) chega DEPOIS do certo: não vence ---';
  v_caso := (fn_upsert_caso('CNPJ renomeia — contaminado depois'))::uuid;
  v_id := fn_upsert_entidade(v_caso, c_m, c_cnpj);
  v_id := fn_upsert_entidade(v_caso, c_s1930, c_cnpj);
  select razao_social into v_nome from entidade where id = v_id;

  -- ESTE É O ASSERT QUE REPROVA COM A CORREÇÃO DESLIGADA (a chamada abaixo
  -- devolvendo sempre p_atual): sem ela, o nome fica "…DE MARCAS LTDA" de
  -- qualquer forma NESTE sentido de chegada — que é justamente por que este
  -- bloco sozinho não bastaria; ver o bloco 2, no sentido oposto.
  perform teste_assert_ren(v_nome = c_m,
    'o nome contaminado pelo endereço (55 chars) NÃO desloca o certo (52 chars) chegando depois',
    v_nome);

  raise notice '--- 2. o contaminado chega ANTES do certo: também não vence ---';
  -- ESTE é o assert que de fato reprova com a correção desligada: sem ela, o
  -- PRIMEIRO nome a chegar sempre fica (é o que a 0169/0170 já faziam), e
  -- "SURUBIJU, 1930" teria virado o nome definitivo da entidade.
  v_caso := (fn_upsert_caso('CNPJ renomeia — contaminado primeiro'))::uuid;
  v_id := fn_upsert_entidade(v_caso, c_s1930, c_cnpj);
  v_id := fn_upsert_entidade(v_caso, c_m, c_cnpj);
  select razao_social into v_nome from entidade where id = v_id;
  perform teste_assert_ren(v_nome = c_m,
    'e chegando ANTES também não vence — a ORDEM não deveria decidir qual nome fica',
    v_nome);

  raise notice '--- 3. sem sufixo nenhum dos dois: quem não tem cara de endereço vence ---';
  v_caso := (fn_upsert_caso('CNPJ renomeia — SURUBIJU vs SURUBIJU 1930'))::uuid;
  v_id := fn_upsert_entidade(v_caso, c_s, c_cnpj);
  v_id := fn_upsert_entidade(v_caso, c_s1930, c_cnpj);
  select razao_social into v_nome from entidade where id = v_id;
  perform teste_assert_ren(v_nome = c_s,
    '"…DE SURUBIJU" (48 chars, sem endereço) vence "…DE SURUBIJU, 1930" (55 chars, com '
      || 'endereço) — comprimento cru sozinho erraria aqui',
    v_nome);

  raise notice '--- 4. sufixo societário vence o truncado sem sufixo ---';
  v_caso := (fn_upsert_caso('CNPJ renomeia — truncado vs MARCAS'))::uuid;
  v_id := fn_upsert_entidade(v_caso, c_t, c_cnpj);
  v_id := fn_upsert_entidade(v_caso, c_m, c_cnpj);
  select razao_social into v_nome from entidade where id = v_id;
  perform teste_assert_ren(v_nome = c_m,
    '"…DE MARCAS LTDA" (com sufixo) vence o truncado "…DE" (sem sufixo, mais curto)', v_nome);

  raise notice '--- 5. o rastro só aparece quando o nome REALMENTE mudou ---';
  v_caso := (fn_upsert_caso('CNPJ renomeia — rastro'))::uuid;
  v_id := fn_upsert_entidade(v_caso, c_t, c_cnpj);
  v_id := fn_upsert_entidade(v_caso, c_m, c_cnpj);  -- renomeia: …DE → …DE MARCAS LTDA
  v_id := fn_upsert_entidade(v_caso, c_t, c_cnpj);  -- casa de novo, NÃO deveria renomear de volta

  select count(*) into v_n from evento_auditoria
    where acao = 'entidade_renomeada_por_cnpj' and entidade_ref = 'entidade:' || v_id;
  perform teste_assert_ren(v_n = 1,
    'exatamente UM evento de renomeio — o terceiro documento (nome pior) não desfaz o segundo',
    format('%s evento(s)', v_n));

  select razao_social into v_nome from entidade where id = v_id;
  perform teste_assert_ren(v_nome = c_m,
    'e o nome continua o mais completo depois do terceiro documento', v_nome);

  raise notice '--- 6. os ramos de casamento APROXIMADO (sem CNPJ) continuam sem renomear ---';
  -- Escopo desta fatia é só o ramo (0), o CNPJ igual. Sem CNPJ, quem decide
  -- continua sendo a 0168 (escolhe entre os que JÁ EXISTIAM, nunca quem
  -- chega) — este bloco é regressão contra a fatia anterior.
  v_caso := (fn_upsert_caso('CNPJ renomeia — sem CNPJ, 0168 intacta'))::uuid;
  perform fn_upsert_entidade(v_caso, c_m);
  perform fn_upsert_entidade(v_caso, c_s);
  perform fn_upsert_entidade(v_caso, c_t);
  v_id := fn_upsert_entidade(v_caso, c_s1930);
  select razao_social into v_nome from entidade where id = v_id;
  perform teste_assert_ren(v_nome = c_s,
    'sem CNPJ, o resultado da 0168 não mudou: "…DE SURUBIJU" (o mais longo ENTRE OS QUE JÁ '
      || 'EXISTIAM), não "…DE MARCAS LTDA" nem o que chegou por último',
    v_nome);
  perform teste_assert_ren(not exists (
      select 1 from evento_auditoria
       where acao = 'entidade_renomeada_por_cnpj' and entidade_ref = 'entidade:' || v_id),
    'e nenhum evento de renomeio por CNPJ nasceu — não havia CNPJ nenhum envolvido');

  raise notice '--- 7. O CNPJ DO CONTADOR NAO PODE REESCREVER O NOME (achado da revisao) ---';
  -- O cenário está no cabeçalho da própria `fn_upsert_entidade`: o rodapé do
  -- relatório traz o CNPJ do ESCRITÓRIO DE CONTABILIDADE, e documentos de
  -- clientes diferentes chegam com ele. A fusão errada a 0169 já admitia (o
  -- CNPJ manda, e o `entidade_cnpj_casou` registra); o que a 0171 NÃO pode
  -- fazer é piorar o dano reescrevendo o nome de um cliente com o de outro.
  -- MEDIDO antes da guarda: "PADARIA DO JOAO LTDA" virava "METALURGICA SAO
  -- PEDRO COMERCIO LTDA".
  v_caso := (fn_upsert_caso('CNPJ renomeia — CNPJ do contador'))::uuid;
  v_id := fn_upsert_entidade(v_caso, 'PADARIA DO JOAO LTDA', '11.222.333/0001-81');
  perform fn_upsert_entidade(v_caso, 'METALURGICA SAO PEDRO COMERCIO LTDA', '11.222.333/0001-81');
  select razao_social into v_nome from entidade where id = v_id;
  perform teste_assert_ren(v_nome = 'PADARIA DO JOAO LTDA',
    'nomes SEM raiz comum não se renomeiam, mesmo com o CNPJ igual — o CNPJ funde, e fundir '
      || 'errado já é ruim; reescrever o nome por cima seria pior',
    v_nome);

  perform teste_assert_ren(exists (
      select 1 from evento_auditoria ev
      where ev.acao = 'entidade_renomeio_recusado' and ev.entidade_ref = 'entidade:' || v_id),
    'e a RECUSA tem rastro — recusar em silêncio esconderia o CNPJ suspeito de quem revisa');

  raise notice '--- 8. RAIZ SO NA PRIMEIRA PALAVRA nao autoriza renomeio (Araucaria) ---';
  -- O contrapositivo fino: "ARAUCARIA BIOENERGIA SPE" e "ARAUCARIA IMOBILIARIA
  -- SPE" compartilham UMA palavra de três. São o incidente que a 0153 existe
  -- para lembrar — duas empresas reais e distintas — e um CNPJ errado entre
  -- elas não pode virar renomeio.
  v_caso := (fn_upsert_caso('CNPJ renomeia — Araucária, raiz curta'))::uuid;
  v_id := fn_upsert_entidade(v_caso, 'ARAUCÁRIA BIOENERGIA SPE LTDA.', '11.222.333/0001-81');
  perform fn_upsert_entidade(v_caso, 'ARAUCÁRIA IMOBILIÁRIA SPE LTDA.', '11.222.333/0001-81');
  select razao_social into v_nome from entidade where id = v_id;
  perform teste_assert_ren(v_nome = 'ARAUCÁRIA BIOENERGIA SPE LTDA.',
    'uma palavra comum de três NÃO é raiz compartilhada — o prefixo tem de cobrir metade do '
      || 'nome mais curto',
    v_nome);

  raise notice '--- 9. quando so o SUFIXO difere, o mais completo vence ---';
  -- ACHADO DA REVISÃO: o renomeio estava aninhado na guarda
  -- `fn_entidade_canonica(...) is distinct from ...`, e a canônica TIRA o
  -- sufixo — então "ALFA COMERCIO" e "ALFA COMERCIO LTDA" são canonicamente
  -- iguais e o renomeio nunca rodava justamente no caso em que o sinal do
  -- sufixo existe para decidir. MEDIDO: o nome ficava "ALFA COMERCIO".
  v_caso := (fn_upsert_caso('CNPJ renomeia — só o sufixo difere'))::uuid;
  v_id := fn_upsert_entidade(v_caso, 'ALFA COMERCIO', '11.222.333/0001-81');
  perform fn_upsert_entidade(v_caso, 'ALFA COMERCIO LTDA', '11.222.333/0001-81');
  select razao_social into v_nome from entidade where id = v_id;
  perform teste_assert_ren(v_nome = 'ALFA COMERCIO LTDA',
    'a razão social COM sufixo vence a sem — a guarda canônica não pode esconder o caso em que '
      || 'o sufixo É a única diferença',
    v_nome);

  raise notice '--- 10. o renomeio NAO cria homonima no mesmo caso ---';
  -- ACHADO DA REVISÃO, e é o defeito silencioso clássico deste projeto: sem a
  -- guarda, o renomeio deixava DUAS entidades do caso com a razão social
  -- idêntica, e o ramo do casamento EXATO passava a escolher uma delas por
  -- `order by razao_social limit 1` — empate puro entre strings iguais, SEM
  -- registrar ambiguidade. Os documentos se dividem entre duas linhas que a
  -- tela mostra como uma. MEDIDO: 2 entidades homônimas, 0 eventos.
  -- O ARRANJO PRECISA DAS DUAS GUARDAS EM ORDEM: os nomes TÊM de compartilhar
  -- raiz (senão quem barra é a guarda 1 e este bloco mediria a outra coisa), e
  -- mesmo assim a homônima tem de existir. Daí os três nomes com o mesmo
  -- começo e finais distintos — e a primeira tentativa deste bloco usou
  -- "ALFA COM", que é ABSORVIDA pelo casamento aproximado antes de virar
  -- entidade própria, e por isso não reproduzia colisão nenhuma.
  -- A ENTIDADE VIZINHA ENTRA POR INSERT DIRETO, e o motivo é um achado deste
  -- bloco: depois que a guarda passou a exigir relação de TRUNCAMENTO, o
  -- arranjo deixou de ser alcançável por `fn_upsert_entidade` sozinha — todo
  -- nome que é trecho contíguo de outro também casa por `fn_mesma_entidade`, e
  -- por isso seria ABSORVIDO antes de virar entidade própria. Duas entidades
  -- assim só existem por cadastro manual ou importação, que é exatamente o
  -- estado que esta guarda protege. Mesmo padrão que o `entidade_ambigua.test.sql`
  -- já usa para o trio ALFA.
  v_caso := (fn_upsert_caso('CNPJ renomeia — homônima'))::uuid;
  insert into entidade (caso_id, razao_social)
    values (v_caso, 'OMNIBEAUTY GESTAO DE MARCAS LTDA');
  insert into entidade (caso_id, razao_social, cnpj)
    values (v_caso, 'GESTAO DE MARCAS LTDA', '11222333000181')
    returning id into v_id;
  perform fn_upsert_entidade(v_caso, 'OMNIBEAUTY GESTAO DE MARCAS LTDA', '11.222.333/0001-81');

  select count(*) into v_n from entidade e1
   where e1.caso_id = v_caso
     and exists (select 1 from entidade e2
                  where e2.caso_id = v_caso and e2.id <> e1.id
                    and fn_entidade_canonica(e2.razao_social) = fn_entidade_canonica(e1.razao_social));
  perform teste_assert_ren(v_n = 0,
    'nenhuma entidade homônima nasce do renomeio — duas linhas com o mesmo nome são invisíveis '
      || 'na tela e o casamento exato escolhe uma no escuro',
    format('%s entidade(s) com nome repetido', v_n));

  perform teste_assert_ren(exists (
      select 1 from evento_auditoria ev
      where ev.acao = 'entidade_renomeio_recusado' and ev.entidade_ref = 'entidade:' || v_id
        and (ev.depois->>'homonima_existiria')::boolean
        and (ev.depois->>'pode_renomear')::boolean),
    'e a recusa diz QUAL das duas guardas barrou: foi a da homônima (pode_renomear=true E '
      || 'homonima_existiria=true) — sem os DOIS campos o bloco viraria vácuo se a outra guarda '
      || 'passasse a barrar antes');

  raise notice '--- 11. S.A. reconhecido como sufixo societario ---';
  -- ACHADO DA REVISÃO: a primeira versão copiou o padrão da 0030, onde `s\s*a`
  -- não casa PONTO — `S/A` e `SA` eram reconhecidos e **`S.A.` não**, que é a
  -- grafia mais comum. O comentário da função afirmava cobrir S.A.
  perform teste_assert_ren(
    fn_nome_tem_sufixo_societario('METALURGICA SAO PEDRO S.A.')
    and fn_nome_tem_sufixo_societario('METALURGICA SAO PEDRO S/A')
    and fn_nome_tem_sufixo_societario('METALURGICA SAO PEDRO SA'),
    'as três grafias de sociedade anônima (S.A., S/A, SA) são reconhecidas');

  perform teste_assert_ren(
    not fn_nome_tem_sufixo_societario('CONSTRUTORA SAO PEDRO')
    and not fn_nome_tem_sufixo_societario('TRANSPORTES SAO PAULO'),
    'e "SAO" não vira falso positivo de "SA" — o casamento é de token inteiro no FIM');

  raise notice '--- 12. A GUARDA DO RENOMEIO, caso a caso (2a revisao) ---';
  -- A PRIMEIRA VERSÃO DESTA GUARDA MEDIA A COISA ERRADA — comprimento de
  -- prefixo comum, e não relação de truncamento. O token que DECIDE fica
  -- justamente fora dessa conta, e ela errava NOS DOIS SENTIDOS. Os quatro
  -- casos que a derrubaram estão aqui, mais os cinco que ela já acertava:
  -- se alguém trocar o critério de novo, é aqui que reprova.
  perform teste_assert_ren(
    -- AUTORIZA: truncamento (em qualquer ponta) ou contaminação provada
    fn_pode_renomear_por_cnpj('OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE SURUBIJU, 1930',
                              'OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE MARCAS LTDA')
    and fn_pode_renomear_por_cnpj('OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE',
                                  'OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE MARCAS LTDA')
    and fn_pode_renomear_por_cnpj('ALFA COMERCIO', 'ALFA COMERCIO LTDA')
    -- truncamento à ESQUERDA (o mais comum quando a IA lê cabeçalho): a versão
    -- de prefixo comum RECUSAVA este, medido.
    and fn_pode_renomear_por_cnpj('GESTAO DE MARCAS LTDA', 'OMNIBEAUTY GESTAO DE MARCAS LTDA')
    -- "S.A.": a canônica da 0030 deixa dois tokens fantasma ("s", "a") e a
    -- versão anterior RECUSAVA por causa deles, medido.
    and fn_pode_renomear_por_cnpj('OMNIBEAUTY S.A.', 'OMNIBEAUTY GESTAO DE MARCAS LTDA'),
    'AUTORIZA: truncamento à direita, à esquerda, só-o-sufixo, S.A., e o nome contaminado pelo '
      || 'endereço perdendo para o limpo');

  perform teste_assert_ren(
    -- RECUSA: nomes que só COMEÇAM parecido não são truncamento um do outro
    not fn_pode_renomear_por_cnpj('PADARIA DO JOAO LTDA', 'METALURGICA SAO PEDRO COMERCIO LTDA')
    -- este e o próximo são os que a versão de prefixo comum AUTORIZAVA, medido:
    and not fn_pode_renomear_por_cnpj('PADARIA DO JOAO LTDA', 'PADARIA DO JOSE COMERCIO LTDA')
    -- o incidente REAL do araucária, sem o token "SPE" que a IA pode não ler —
    -- e é o caso que a 0153 existe para lembrar
    and not fn_pode_renomear_por_cnpj('ARAUCARIA BIOENERGIA LTDA', 'ARAUCARIA IMOBILIARIA LTDA')
    and not fn_pode_renomear_por_cnpj('ARAUCARIA BIOENERGIA SPE LTDA', 'ARAUCARIA IMOBILIARIA SPE LTDA'),
    'RECUSA: duas empresas que só compartilham o começo do nome — "JOAO" × "JOSE" e '
      || '"BIOENERGIA" × "IMOBILIARIA" são exatamente o token que decide');

  raise notice 'CNPJ RENOMEIA OK — a cara de endereço nunca vence, o sufixo desempata, o '
               'comprimento só decide por último, e a ordem de chegada parou de mandar';
END $$;

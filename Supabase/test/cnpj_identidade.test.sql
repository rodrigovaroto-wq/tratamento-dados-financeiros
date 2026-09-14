-- =============================================================================
-- 0169 — o CNPJ é a identidade; o nome é só o rótulo que a fonte trunca
--
-- OS DADOS SÃO OS REAIS (regra 4): os quatro nomes da OMNIBEAUTY como o dono os
-- viu no export do caso "teste 143", e o CNPJ 36.193.378/0001-04 que aparece
-- nos DOIS balanços que ele anexou. Nada aqui é fixture inventada — é o
-- algoritmo determinístico rodando contra o dado que existiu.
--
-- O QUE ESTE ARQUIVO MEDE:
--   1. os quatro nomes reais COM o CNPJ real: UMA entidade (a 0168 sozinha para
--      em três — ver `alias_truncado.test.sql`);
--   2. e em QUALQUER ordem de chegada — é a propriedade que a 0168 não tinha,
--      porque ela dependia de qual variante chegava primeiro;
--   3. **CNPJ NULO NÃO MUDA NADA**: os mesmos quatro nomes sem CNPJ continuam
--      dando TRÊS, exatamente como na 0168. Sem este bloco, a 0169 poderia ter
--      afrouxado o casamento por nome sem ninguém ver;
--   4. CNPJ DIFERENTE separa mesmo quando o nome casa — e isto corrige, quando
--      há CNPJ, o LIMITE CONHECIDO da 0153 que o `entidade_ambigua.test.sql`
--      mede: hoje "ALFA COMERCIO EXTERIOR LTDA." é absorvida em silêncio por
--      "ALFA COMERCIO LTDA.";
--   5. o contrapositivo da 0153 SEM CNPJ continua valendo (Araucária);
--   6. CNPJ inválido é tratado como AUSENTE, não como identidade — um número
--      inventado pela IA não pode fundir duas empresas de verdade;
--   7. o CNPJ é APRENDIDO com rastro, e nunca sobrescrito.
-- =============================================================================

create or replace function teste_assert_cnpj(p_cond boolean, p_nome text, p_detalhe text default null)
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
  v_a     uuid;
  v_b     uuid;
  v_n     int;
  v_nomes text;
begin
  raise notice '--- 1. os quatro nomes reais COM o CNPJ real: UMA entidade ---';
  v_caso := (fn_upsert_caso('CNPJ — OMNIBEAUTY, ordem do lote'))::uuid;
  perform fn_upsert_entidade(v_caso, c_m,     c_cnpj);
  perform fn_upsert_entidade(v_caso, c_s,     c_cnpj);
  perform fn_upsert_entidade(v_caso, c_t,     c_cnpj);
  perform fn_upsert_entidade(v_caso, c_s1930, c_cnpj);

  select count(*), string_agg(razao_social, ' | ' order by razao_social)
    into v_n, v_nomes from entidade where caso_id = v_caso;

  -- ESTE É O ASSERT QUE REPROVA COM A 0169 DESLIGADA: sem ela saem TRÊS (o que
  -- a 0168 consegue sozinha), e sem a 0168 também, QUATRO — as quatro linhas do
  -- export do dono.
  perform teste_assert_cnpj(v_n = 1,
    'os quatro nomes reais com o mesmo CNPJ são UMA empresa (a 0168 sozinha para em três)',
    format('%s entidade(s): %s', v_n, v_nomes));

  perform teste_assert_cnpj(
    (select fn_cnpj_canonico(cnpj) from entidade where caso_id = v_caso) = '36193378000104',
    'e o CNPJ ficou gravado na entidade, canônico');

  raise notice '--- 2. e em QUALQUER ordem de chegada (a 0168 dependia da ordem) ---';
  v_caso := (fn_upsert_caso('CNPJ — OMNIBEAUTY, ordem invertida'))::uuid;
  perform fn_upsert_entidade(v_caso, c_s1930, c_cnpj);
  perform fn_upsert_entidade(v_caso, c_t,     c_cnpj);
  perform fn_upsert_entidade(v_caso, c_s,     c_cnpj);
  perform fn_upsert_entidade(v_caso, c_m,     c_cnpj);
  select count(*) into v_n from entidade where caso_id = v_caso;
  perform teste_assert_cnpj(v_n = 1,
    'ordem invertida, mesma CONTAGEM — o CNPJ não pergunta quem chegou primeiro',
    format('%s entidade(s)', v_n));

  -- ESTE ERA O LIMITE DECLARADO até a 0171, e o comentário antigo já dizia:
  -- "se um dia alguém ensinar isso à função, este assert reprova — e é o
  -- lugar certo para a decisão ser revista". A 0171 é essa decisão (o dono
  -- pediu, em resposta direta): agora o CNPJ TAMBÉM renomeia para o nome mais
  -- completo, não só funde. A medição do DESEMPATE em si (por que "…DE MARCAS
  -- LTDA" vence "…DE SURUBIJU, 1930" mesmo sendo mais curto) está em
  -- `cnpj_renomeia.test.sql`, não aqui — este bloco só confere que o
  -- resultado final, nesta ordem de chegada, é o nome CERTO.
  perform teste_assert_cnpj(
    (select razao_social from entidade where caso_id = v_caso) = c_m,
    'com a 0171, o nome que sobrevive é o MAIS COMPLETO ("…DE MARCAS LTDA"), não mais o da '
      || 'primeira chegada — ver cnpj_renomeia.test.sql para o desempate',
    (select razao_social from entidade where caso_id = v_caso));

  raise notice '--- 3. CNPJ NULO NÃO MUDA NADA: os mesmos quatro nomes dão TRÊS ---';
  -- A propriedade de segurança desta migration. Enquanto a extração não mandar
  -- CNPJ, todo caminho de nome tem de continuar sendo o da 0168 — se este bloco
  -- reprovar, a 0169 afrouxou o casamento por nome sem ninguém ver.
  v_caso := (fn_upsert_caso('CNPJ — sem CNPJ nenhum'))::uuid;
  perform fn_upsert_entidade(v_caso, c_m);
  perform fn_upsert_entidade(v_caso, c_s);
  perform fn_upsert_entidade(v_caso, c_t);
  perform fn_upsert_entidade(v_caso, c_s1930);
  select count(*) into v_n from entidade where caso_id = v_caso;
  perform teste_assert_cnpj(v_n = 3,
    'sem CNPJ, o resultado é IDÊNTICO ao da 0168 (três) — a 0169 não mexeu no caminho do nome',
    format('%s entidade(s)', v_n));

  -- E A PROPRIEDADE, não só este caso. O assert acima passa numa 0169 que
  -- mantivesse três entidades trocando QUAL sobrevive, ou que parasse de emitir
  -- `entidade_alias_fundido`. O que a fatia realmente promete é ESTRUTURAL:
  -- `fn_entidades_candidatas_cnpj(caso, nome, null)` devolve exatamente as
  -- mesmas linhas que `fn_entidades_candidatas(caso, nome)`. Varrido com
  -- `except` NOS DOIS SENTIDOS contra TODAS as entidades e nomes que a base de
  -- teste já tem — não contra um exemplo escolhido por mim.
  select count(*) into v_n from (
    select e.caso_id, e.razao_social from entidade e
  ) alvo, lateral (
    select 1 from (
      (select * from fn_entidades_candidatas(alvo.caso_id, alvo.razao_social)
       except
       select * from fn_entidades_candidatas_cnpj(alvo.caso_id, alvo.razao_social, null))
      union all
      (select * from fn_entidades_candidatas_cnpj(alvo.caso_id, alvo.razao_social, null)
       except
       select * from fn_entidades_candidatas(alvo.caso_id, alvo.razao_social))
    ) d
  ) div;
  perform teste_assert_cnpj(v_n = 0,
    'PROPRIEDADE: com CNPJ nulo, a lista de candidatas é a MESMA da 0153 — varrida com except '
      || 'nos dois sentidos sobre toda entidade da base de teste',
    format('%s divergência(s)', v_n));

  raise notice '--- 4. CNPJ DIFERENTE separa, mesmo com o nome casando ---';
  -- O LIMITE CONHECIDO da 0153, medido em `entidade_ambigua.test.sql`: com UM
  -- candidato, "ALFA COMERCIO EXTERIOR LTDA." é ABSORVIDA por "ALFA COMERCIO
  -- LTDA." em silêncio, porque uma é subsequência da outra. Com CNPJ, deixa de
  -- ser: o nome não tem autoridade para contradizer o registro fiscal.
  v_caso := (fn_upsert_caso('CNPJ — dois CNPJs, nomes que casam'))::uuid;
  v_a := fn_upsert_entidade(v_caso, 'ALFA COMERCIO LTDA.',          '11.222.333/0001-81');
  v_b := fn_upsert_entidade(v_caso, 'ALFA COMERCIO EXTERIOR LTDA.', '36.193.378/0001-04');
  perform teste_assert_cnpj(v_a is distinct from v_b,
    'CNPJs diferentes = empresas diferentes, mesmo com um nome sendo subsequência do outro '
      || '(o LIMITE CONHECIDO da 0153, corrigido quando há CNPJ)',
    format('a=%s b=%s', v_a, v_b));

  -- E o MESMO arranjo SEM CNPJ continua absorvendo — o limite da 0153 não foi
  -- "consertado no escuro": ele continua lá quando não há identidade fiscal.
  v_caso := (fn_upsert_caso('CNPJ — o limite da 0153 sem CNPJ'))::uuid;
  v_a := fn_upsert_entidade(v_caso, 'ALFA COMERCIO LTDA.');
  v_b := fn_upsert_entidade(v_caso, 'ALFA COMERCIO EXTERIOR LTDA.');
  perform teste_assert_cnpj(v_a = v_b,
    'e SEM CNPJ o limite da 0153 continua exatamente como era (absorção silenciosa)',
    format('a=%s b=%s', v_a, v_b));

  raise notice '--- 5. contrapositivo da 0153 SEM CNPJ: ninguém escolhe no empate ---';
  v_caso := (fn_upsert_caso('CNPJ — Araucária sem CNPJ'))::uuid;
  perform fn_upsert_entidade(v_caso, 'ARAUCÁRIA BIOENERGIA SPE LTDA.');
  perform fn_upsert_entidade(v_caso, 'ARAUCÁRIA IMOBILIÁRIA SPE LTDA.');
  v_id := fn_upsert_entidade(v_caso, 'Araucaria SPE');
  perform teste_assert_cnpj(
    (select razao_social from entidade where id = v_id) = 'Araucaria SPE'
    and exists (select 1 from evento_auditoria ev
                 where ev.acao = 'entidade_ambigua' and ev.entidade_ref = 'entidade:' || v_id),
    'sem CNPJ, o nome que casa com duas empresas continua sem escolher (0153 intacta)',
    coalesce((select razao_social from entidade where id = v_id), '(nulo)'));

  -- E COM CNPJ o mesmo nome ambíguo DECIDE, que é o ganho: o CNPJ responde a
  -- pergunta que o nome não responde.
  v_caso := (fn_upsert_caso('CNPJ — Araucária com CNPJ'))::uuid;
  v_a := fn_upsert_entidade(v_caso, 'ARAUCÁRIA BIOENERGIA SPE LTDA.',  '11.222.333/0001-81');
  perform fn_upsert_entidade(v_caso, 'ARAUCÁRIA IMOBILIÁRIA SPE LTDA.', '36.193.378/0001-04');
  v_id := fn_upsert_entidade(v_caso, 'Araucaria SPE', '11.222.333/0001-81');
  perform teste_assert_cnpj(v_id = v_a,
    'com CNPJ, o nome ambíguo vai para a empresa CERTA em vez de virar uma terceira linha',
    format('foi para "%s"', (select razao_social from entidade where id = v_id)));

  raise notice '--- 6. CNPJ inválido é AUSÊNCIA, não identidade ---';
  -- O CNPJ vai chegar de uma IA lendo PDF escaneado. Um número inventado que
  -- passasse como identidade fundiria duas empresas de verdade, calado.
  v_caso := (fn_upsert_caso('CNPJ — número que não fecha o DV'))::uuid;
  v_a := fn_upsert_entidade(v_caso, 'PRIMEIRA EMPRESA LTDA.',  '36.193.378/0001-05');
  v_b := fn_upsert_entidade(v_caso, 'SEGUNDA COISA LTDA.',     '36.193.378/0001-05');
  perform teste_assert_cnpj(v_a is distinct from v_b,
    'dois nomes SEM relação com o MESMO CNPJ inválido não viram uma empresa — DV que não fecha '
      || 'é ausência',
    format('a=%s b=%s', v_a, v_b));
  perform teste_assert_cnpj(
    (select count(*) from entidade where caso_id = v_caso and cnpj is not null) = 0,
    'e nada de inválido foi gravado na coluna cnpj');

  raise notice '--- 7. o CNPJ é APRENDIDO com rastro, e nunca sobrescrito ---';
  v_caso := (fn_upsert_caso('CNPJ — aprender'))::uuid;
  -- O primeiro documento chega SEM CNPJ (é o caso comum hoje).
  v_a := fn_upsert_entidade(v_caso, 'APRENDE LTDA.');
  perform teste_assert_cnpj((select cnpj from entidade where id = v_a) is null,
    'nasce sem CNPJ quando o documento não traz um');
  -- O segundo, do mesmo nome, traz o CNPJ: a entidade aprende.
  v_b := fn_upsert_entidade(v_caso, 'APRENDE LTDA.', c_cnpj);
  perform teste_assert_cnpj(v_b = v_a
    and (select fn_cnpj_canonico(cnpj) from entidade where id = v_a) = '36193378000104',
    'o segundo documento ENSINA o CNPJ à entidade que já existia');
  perform teste_assert_cnpj(exists (
      select 1 from evento_auditoria ev
      where ev.acao = 'entidade_cnpj_aprendido' and ev.entidade_ref = 'entidade:' || v_a),
    'com rastro em evento_auditoria — aprender calado seria pior que não aprender');
  -- E um terceiro com CNPJ DIFERENTE não sobrescreve: vira outra empresa.
  v_id := fn_upsert_entidade(v_caso, 'APRENDE LTDA.', '11.222.333/0001-81');
  perform teste_assert_cnpj(
    (select fn_cnpj_canonico(cnpj) from entidade where id = v_a) = '36193378000104',
    'e um CNPJ DIFERENTE não sobrescreve o que já estava gravado',
    (select cnpj from entidade where id = v_a));
  perform teste_assert_cnpj(v_id is distinct from v_a,
    'ele vira empresa própria — mesmo nome, registro fiscal diferente');

  raise notice '--- 8. 0170: o CNPJ ATRAVESSA a porta de entrada (fn_registrar_documento) ---';
  -- A 0169 sozinha e' codigo instalado e nunca executado: a porta chamava
  -- `fn_upsert_entidade` com DOIS argumentos e o CNPJ morria ali. Este bloco
  -- prova o FIO INTEIRO, do jeito que producao usa -- nao chamando
  -- `fn_upsert_entidade` direto.
  v_caso := (fn_upsert_caso('CNPJ — pela porta de entrada'))::uuid;
  perform fn_registrar_documento(v_caso, c_m, 'ano', '2024', 'BALANCO', 0.99,
    'openai_conteudo', 'supabase_storage', 's/p1.pdf', 'BAL 2024.pdf', true,
    'HASH-CNPJ-PORTA-1', 'ok', p_cnpj => c_cnpj);
  perform fn_registrar_documento(v_caso, c_s1930, 'ano', '2023', 'BALANCO', 0.99,
    'openai_conteudo', 'supabase_storage', 's/p2.pdf', 'BAL 2023.pdf', true,
    'HASH-CNPJ-PORTA-2', 'ok', p_cnpj => c_cnpj);

  select count(*) into v_n from entidade where caso_id = v_caso;
  perform teste_assert_cnpj(v_n = 1,
    'dois documentos com grafias diferentes e o MESMO CNPJ entram na MESMA empresa pela porta '
      || 'de entrada — e o fio que faz a 0169 deixar de ser codigo dormente',
    format('%s entidade(s): %s', v_n,
      (select string_agg(razao_social, ' | ') from entidade where caso_id = v_caso)));

  perform teste_assert_cnpj(
    (select fn_cnpj_canonico(cnpj) from entidade where caso_id = v_caso) = '36193378000104',
    'e o CNPJ chegou gravado na entidade, vindo da porta e nao de uma chamada direta');

  perform teste_assert_cnpj(
    (select count(*) from documento where caso_id = v_caso) = 2,
    'os dois documentos ficaram na mesma entidade (nenhum ficou orfao no caminho)',
    format('%s documento(s)', (select count(*) from documento where caso_id = v_caso)));

  raise notice 'CNPJ IDENTIDADE OK — o CNPJ manda, o nome só decide quando não há CNPJ, e '
               'ausência não decide nada';
end $$;

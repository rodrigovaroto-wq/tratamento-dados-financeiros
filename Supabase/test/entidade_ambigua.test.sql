-- Testes da ENTIDADE AMBÍGUA (Supabase/migrations/0153).
-- Rodar via Supabase/test/run.sh (que aplica as migrations antes).
--
-- POR QUE ESTE ARQUIVO EXISTE, e a resposta é desconfortável: quando escrevi a
-- 0153, a suíte inteira passou SEM UMA LINHA DE TESTE NOVA. Isso não é sinal de
-- que a mudança é segura — é sinal de que **nenhum teste exercitava a
-- ambiguidade**. O balanço de uma empresa dentro de outra passou por 1.046
-- asserts sem tocar em nenhum.
--
-- O caso reproduzido aqui é o real, com os nomes reais do `book-araucaria`:
-- "Araucaria SPE" (que é o que o nome do arquivo dá) contra
-- "ARAUCÁRIA BIOENERGIA SPE LTDA." e "ARAUCÁRIA IMOBILIÁRIA SPE LTDA.".
--
-- As propriedades travadas:
--
--   #1  O DEFEITO RELIGADO: com as duas empresas na base, o nome ambíguo NÃO
--       entra em nenhuma delas — e o assert diz qual seria a escolhida pela
--       regra antiga (a primeira do alfabeto, BIOENERGIA), para que quem
--       reintroduzir o `order by razao_social` veja o nome dela na reprovação;
--   #2  a AMBIGUIDADE VIRA PENDÊNCIA BLOQUEANTE, nomeando os dois candidatos —
--       pendência que diz "ambíguo" sem dizer contra quem devolve o trabalho
--       inteiro para a mesa;
--   #3  UMA pendência por ENTIDADE, não por documento: cinco balanços da mesma
--       empresa fazem uma pergunta só;
--   #4  o GATILHO existe e roda — a pendência aparece pelo caminho normal de
--       registro, sem ninguém chamar função nenhuma à mão. Checagem instalada e
--       sem chamador é indistinguível de checagem que não achou nada, e este
--       repositório já pagou por isso três vezes;
--   #5  o EXATO ganha do aproximado, mesmo quando o aproximado vem antes no
--       alfabeto — sem isto a correção inverteria de lado e passaria a
--       preferir a empresa errada quando a certa existe;
--   #6  NÃO HÁ REGRESSÃO no casamento aproximado ÚNICO, que é o caso normal e o
--       motivo de `fn_mesma_entidade` ser frouxa: "Vertentes Metalurgica" (nome
--       de arquivo, sem acento) continua sendo a mesma empresa que
--       "VERTENTES METALÚRGICA LTDA." (diagnóstico);
--   #8  o LIMITE CONHECIDO fica medido: com UM candidato, a absorção continua
--       silenciosa. A 0153 resolve o empate entre dois ou mais, não a absorção
--       de "Alfa Comércio Exportação" por "Alfa Comércio". Está aqui com assert
--       para ser um limite CONHECIDO e não uma surpresa de rodada real;
--   #7  `fn_fundir_entidade` leva TUDO junto (documento, checklist, pendência,
--       reconciliação), resolve a pendência de ambiguidade e deixa rastro; e
--       recusa fundir uma entidade nela mesma ou de outro mandato.

\set ON_ERROR_STOP on

create or replace function teste_assert_ent(p_ok boolean, p_nome text, p_detalhe text default null)
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
  v_caso      uuid;
  v_caso2     uuid;
  v_bio       uuid;
  v_imob      uuid;
  v_ambigua   uuid;
  v_ent       uuid;
  v_r         jsonb;
  v_doc       uuid;
  v_doc2      uuid;
  v_n         int;
  v_txt       text;
  v_pend      uuid;
  v_erro      text;
begin
  v_caso := (fn_upsert_caso('Caso 0153 — a entidade ambígua'))::uuid;

  -- ===========================================================================
  raise notice '--- 0. PRÉ-CONDIÇÃO: o nome REALMENTE casa com as duas ---';
  -- ===========================================================================
  --
  -- Sem isto o teste inteiro não mede nada: se `fn_mesma_entidade` deixasse de
  -- casar, os asserts abaixo passariam por ausência de ambiguidade, não por
  -- correção. É a guarda que separa "está certo" de "não está exercitando".
  perform teste_assert_ent(
    fn_mesma_entidade('Araucaria SPE', 'ARAUCÁRIA BIOENERGIA SPE LTDA.')
    and fn_mesma_entidade('Araucaria SPE', 'ARAUCÁRIA IMOBILIÁRIA SPE LTDA.'),
    'PRÉ-CONDIÇÃO: "Araucaria SPE" casa com Bioenergia SPE E com Imobiliária SPE',
    format('bio=%s imob=%s',
           fn_mesma_entidade('Araucaria SPE', 'ARAUCÁRIA BIOENERGIA SPE LTDA.'),
           fn_mesma_entidade('Araucaria SPE', 'ARAUCÁRIA IMOBILIÁRIA SPE LTDA.')));

  -- As duas empresas entram como o araucária as trouxe: pelo diagnóstico da IA,
  -- com a razão social por extenso.
  v_bio  := fn_upsert_entidade(v_caso, 'ARAUCÁRIA BIOENERGIA SPE LTDA.');
  v_imob := fn_upsert_entidade(v_caso, 'ARAUCÁRIA IMOBILIÁRIA SPE LTDA.');
  perform teste_assert_ent(v_bio is not null and v_imob is not null and v_bio <> v_imob,
    'as duas empresas do grupo entram como entidades distintas');

  -- ===========================================================================
  raise notice '--- 1. O DEFEITO RELIGADO: o nome ambíguo não entra em nenhuma ---';
  -- ===========================================================================
  v_ambigua := fn_upsert_entidade(v_caso, 'Araucaria SPE');

  perform teste_assert_ent(v_ambigua <> v_bio,
    'o nome ambíguo NÃO cai na Bioenergia — que é onde o `order by razao_social` o punha',
    'BIOENERGIA vem antes de IMOBILIÁRIA no alfabeto, e era só isso que decidia');
  perform teste_assert_ent(v_ambigua <> v_imob,
    'e também não cai na Imobiliária — não é a outra que ele escolhe, é NENHUMA');
  select razao_social into v_txt from entidade where id = v_ambigua;
  perform teste_assert_ent(v_txt = 'Araucaria SPE',
    'ele fica numa entidade própria, com o nome como veio', v_txt);

  -- ===========================================================================
  raise notice '--- 2. A AMBIGUIDADE É REGISTRADA COM OS CANDIDATOS ---';
  -- ===========================================================================
  select ev.depois->>'candidatos' into v_txt
  from evento_auditoria ev
  where ev.acao = 'entidade_ambigua' and ev.entidade_ref = 'entidade:' || v_ambigua;
  perform teste_assert_ent(v_txt is not null
    and v_txt like '%BIOENERGIA%' and v_txt like '%IMOBILIÁRIA%',
    'o evento nomeia OS DOIS candidatos por extenso', coalesce(v_txt, 'sem evento'));

  -- ===========================================================================
  raise notice '--- 3./4. O GATILHO RODA E A PENDÊNCIA APARECE SOZINHA ---';
  -- ===========================================================================
  --
  -- Registrado pelo caminho NORMAL. Ninguém chama fn_pendencia_entidade_ambigua
  -- aqui — se o gatilho não estiver ligado, este assert reprova.
  v_r := fn_registrar_documento(
    v_caso, 'Araucaria SPE', 'multi', '21,22,23,24,25', 'BALANCO', 0.9, 'nome_arquivo',
    'supabase_storage', 'b/009.pdf',
    '009_Balanco_Patrimonial_Araucaria_SPE_2025x2024x2023x2022x2021.pdf',
    false, 'HASH-153-009', 'ok');
  v_doc := (v_r->>'documento_id')::uuid;

  select id, descricao into v_pend, v_txt from pendencia
  where caso_id = v_caso and motivo = 'entidade_ambigua:' || v_ambigua and estado <> 'resolvida';
  perform teste_assert_ent(v_pend is not null,
    'o GATILHO abriu a pendência pelo caminho normal de registro — ninguém a chamou à mão');
  perform teste_assert_ent(v_txt like '%BIOENERGIA%' and v_txt like '%IMOBILIÁRIA%',
    'e a descrição nomeia os dois candidatos', left(coalesce(v_txt,''), 160));
  perform teste_assert_ent(
    (select tipo::text from pendencia where id = v_pend) = 'entidade_incorreta'
    and (select severidade::text from pendencia where id = v_pend) = 'bloqueante'
    and (select sobrepujavel from pendencia where id = v_pend) = false,
    'a pendência é BLOQUEANTE e não sobrepujável — o número da empresa errada fecha sozinho');

  -- O segundo documento da mesma empresa ambígua NÃO abre pendência nova.
  v_r := fn_registrar_documento(
    v_caso, 'Araucaria SPE', 'multi', '21,22,23,24,25', 'DRE', 0.9, 'nome_arquivo',
    'supabase_storage', 'b/042.pdf',
    '042_Demonstracao_do_Resultado_Araucaria_SPE_2025x2024x2023x2022x2021.pdf',
    false, 'HASH-153-042', 'ok');
  v_doc2 := (v_r->>'documento_id')::uuid;

  select count(*) into v_n from pendencia
  where caso_id = v_caso and motivo = 'entidade_ambigua:' || v_ambigua;
  perform teste_assert_ent(v_n = 1,
    'UMA pendência por entidade, não uma por documento',
    format('abriu %s para 2 documentos da mesma empresa ambígua', v_n));

  -- ===========================================================================
  raise notice '--- 5. O EXATO GANHA DO APROXIMADO QUE VEM ANTES NO ALFABETO ---';
  -- ===========================================================================
  --
  -- Agora "Araucaria SPE" EXISTE como entidade. Um terceiro documento com esse
  -- nome tem de cair NELA — e não na Bioenergia, que continua casando e continua
  -- vindo antes no alfabeto. Sem a prioridade do casamento exato, a correção
  -- inverteria de lado e passaria a errar quando a resposta certa está na base.
  v_ent := fn_upsert_entidade(v_caso, 'Araucaria SPE');
  perform teste_assert_ent(v_ent = v_ambigua,
    'o casamento canônico EXATO ganha do aproximado que vem antes no alfabeto',
    format('esperado %s, veio %s', v_ambigua, v_ent));

  -- E a grafia diferente do MESMO nome também é exata pela forma canônica.
  v_ent := fn_upsert_entidade(v_caso, 'araucária spe ltda.');
  perform teste_assert_ent(v_ent = v_ambigua,
    'acento e sufixo societário não fazem entidade nova (a forma canônica é a mesma)',
    format('esperado %s, veio %s', v_ambigua, v_ent));

  -- ===========================================================================
  raise notice '--- 6. SEM REGRESSÃO: o aproximado ÚNICO continua casando ---';
  -- ===========================================================================
  --
  -- É o motivo de `fn_mesma_entidade` ser frouxa, e a 0153 não podia estragá-lo:
  -- partir a mesma empresa em duas é o outro erro caro.
  v_caso2 := (fn_upsert_caso('Caso 0153 — o casamento que tem de continuar'))::uuid;
  v_ent := fn_upsert_entidade(v_caso2, 'VERTENTES METALÚRGICA LTDA.');
  perform teste_assert_ent(fn_upsert_entidade(v_caso2, 'Vertentes Metalurgica') = v_ent,
    'o nome do arquivo sem acento continua casando a razão social do diagnóstico');
  perform teste_assert_ent(fn_upsert_entidade(v_caso2, 'Metalúrgica') = v_ent,
    'e o nome parcial também, quando há UM candidato só');
  select count(*) into v_n from entidade where caso_id = v_caso2;
  perform teste_assert_ent(v_n = 1,
    'as três grafias continuam sendo UMA empresa', format('viraram %s', v_n));

  -- ===========================================================================
  raise notice '--- 7. fn_fundir_entidade: a saída da pendência ---';
  -- ===========================================================================
  --
  -- O analista decide: os dois documentos são da Imobiliária.
  select count(*) into v_n from documento where caso_id = v_caso and entidade_id = v_ambigua;
  perform teste_assert_ent(v_n = 2,
    'PRÉ-CONDIÇÃO: os dois documentos estão na entidade ambígua', format('%s', v_n));

  v_r := fn_fundir_entidade(v_caso, v_ambigua, v_imob, 'humano:analista');
  perform teste_assert_ent((v_r->>'documentos')::int = 2,
    'a fusão move os DOIS documentos', v_r::text);

  select count(*) into v_n from documento where caso_id = v_caso and entidade_id = v_imob;
  perform teste_assert_ent(v_n = 2, 'e eles estão na Imobiliária agora', format('%s', v_n));
  perform teste_assert_ent(
    not exists (select 1 from entidade where id = v_ambigua),
    'a entidade ambígua deixou de existir');
  perform teste_assert_ent(
    not exists (select 1 from checklist_item_status where entidade_id = v_ambigua)
    and not exists (select 1 from pendencia where entidade_id = v_ambigua)
    and not exists (select 1 from reconciliacao where entidade_id = v_ambigua),
    'e nada ficou apontando para ela — checklist, pendência e reconciliação foram junto');

  select estado::text, resolvida_por into v_txt, v_erro from pendencia where id = v_pend;
  perform teste_assert_ent(v_txt = 'resolvida' and v_erro = 'humano:analista',
    'a pendência de ambiguidade fica resolvida, com o autor', format('%s / %s', v_txt, v_erro));

  select ev.antes->>'razao_social' into v_txt from evento_auditoria ev
  where ev.acao = 'entidade_fundida' and ev.entidade_ref = 'entidade:' || v_imob;
  perform teste_assert_ent(v_txt = 'Araucaria SPE',
    'e o rastro guarda o nome que deixou de existir — nada some calado',
    coalesce(v_txt, 'sem evento'));

  -- As duas recusas.
  begin
    perform fn_fundir_entidade(v_caso, v_imob, v_imob);
    perform teste_assert_ent(false, 'fundir a entidade nela mesma é recusado', 'não levantou');
  exception when others then
    perform teste_assert_ent(SQLERRM like '%nela mesma%',
      'fundir a entidade nela mesma é recusado', SQLERRM);
  end;

  begin
    perform fn_fundir_entidade(v_caso, v_bio, (select id from entidade where caso_id = v_caso2 limit 1));
    perform teste_assert_ent(false, 'fundir entre mandatos é recusado', 'não levantou');
  exception when others then
    perform teste_assert_ent(SQLERRM like '%não encontrada neste mandato%',
      'fundir com entidade de OUTRO mandato é recusado', SQLERRM);
  end;

  -- ===========================================================================
  raise notice '--- 8. AS BORDAS QUE FALTAVAM ---';
  -- ===========================================================================
  --
  -- (a) TRÊS CANDIDATOS, não dois. O grupo do araucária tem quatorze empresas
  -- "Araucária ⟨coisa⟩", e um nome curto casa com várias — o teste acima só
  -- exercitava o par.
  --
  -- AS TRÊS ENTRAM POR INSERT DIRETO, E O MOTIVO É UM ACHADO DESTE TESTE: pelo
  -- `fn_upsert_entidade` elas NÃO viram três. "ALFA COMERCIO" é subsequência de
  -- "ALFA COMERCIO EXTERIOR", então a segunda casa a primeira (UM candidato) e
  -- é ABSORVIDA por ela, em silêncio.
  --
  -- **Isso continua acontecendo depois da 0153, e é limite conhecido dela.** A
  -- 0153 resolve o empate entre DOIS ou mais candidatos; ela não resolve o caso
  -- de UM candidato que é absorção indevida — duas empresas reais cujos nomes
  -- sejam prefixo-subsequência uma da outra viram uma entidade só, sem
  -- pendência. No `book-araucaria` isso não acontece (Bioenergia e Imobiliária
  -- não são subsequência uma da outra), mas num grupo com "Alfa Comércio Ltda."
  -- e "Alfa Comércio e Exportação Ltda." aconteceria. Fica MEDIDO aqui, com
  -- assert, para não virar surpresa de rodada real.
  insert into entidade (caso_id, razao_social) values
    (v_caso2, 'ALFA COMERCIO LTDA.'),
    (v_caso2, 'ALFA COMERCIO EXTERIOR LTDA.'),
    (v_caso2, 'ALFA COMERCIO INTERIOR LTDA.');
  select count(*) into v_n from fn_entidades_candidatas(v_caso2, 'Alfa Comercio');
  perform teste_assert_ent(v_n >= 3,
    'PRÉ-CONDIÇÃO: "Alfa Comercio" casa com TRÊS ou mais', format('%s', v_n));
  -- "Alfa Comercio" é EXATA contra "ALFA COMERCIO LTDA." (o sufixo societário
  -- sai na forma canônica), então ela decide — e é o comportamento certo.
  v_ent := fn_upsert_entidade(v_caso2, 'Alfa Comercio');
  perform teste_assert_ent(
    (select razao_social from entidade where id = v_ent) = 'ALFA COMERCIO LTDA.',
    'com três candidatos, o EXATO ainda decide (o sufixo societário sai na forma canônica)',
    (select razao_social from entidade where id = v_ent));
  -- Já um nome que casa com os três e não é exato de nenhum não decide.
  v_ent := fn_upsert_entidade(v_caso2, 'Alfa Com');
  perform teste_assert_ent(
    (select razao_social from entidade where id = v_ent) = 'Alfa Com',
    'e um nome que casa com os três sem ser exato de nenhum fica em entidade própria',
    (select razao_social from entidade where id = v_ent));

  -- (c) O LIMITE CONHECIDO DA 0153, medido em vez de suposto: com UM candidato,
  -- a absorção continua silenciosa. Se um dia isso for corrigido, este assert
  -- reprova — e é o lugar certo para a decisão ser revista.
  v_caso2 := (fn_upsert_caso('Caso 0153 — o limite da absorção'))::uuid;
  perform fn_upsert_entidade(v_caso2, 'ALFA COMERCIO LTDA.');
  v_ent := fn_upsert_entidade(v_caso2, 'ALFA COMERCIO EXTERIOR LTDA.');
  perform teste_assert_ent(
    (select razao_social from entidade where id = v_ent) = 'ALFA COMERCIO LTDA.',
    'LIMITE CONHECIDO: com UM candidato, a absorção continua silenciosa (a 0153 só cobre o empate)',
    format('"ALFA COMERCIO EXTERIOR LTDA." foi para "%s". Se este assert reprovar, alguém '
           || 'corrigiu a absorção — atualize o comentário e o ESTADO.md.',
           (select razao_social from entidade where id = v_ent)));

  -- (b) NOME VAZIO E NULO não criam entidade nenhuma.
  perform teste_assert_ent(fn_upsert_entidade(v_caso2, null) is null
                       and fn_upsert_entidade(v_caso2, '   ') is null,
    'nome nulo ou em branco não cria entidade');

  raise notice 'entidade_ambigua OK — o nome que casa com duas não entra em nenhuma, a pendência '
               'nasce do gatilho nomeando os candidatos, o exato ganha do alfabeto, o aproximado '
               'único não regrediu, e a fusão leva tudo junto com rastro';
end $$;

-- =============================================================================
-- SEÇÃO NOVA (0162) — O BALCÃO NÃO ESCUTA A RESPOSTA QUE O PRÓPRIO DOCUMENTO
-- TRAZ, E ESTA SEÇÃO PROVA QUE ELE PASSOU A ESCUTAR.
--
-- Bloco separado do `do $$` acima de propósito: as seções 1–8 fundem a
-- entidade ambígua daquele caso em `v_imob` (seção 7) e não podem mudar de
-- significado — este bloco monta o SEU PRÓPRIO caso, do zero, para não
-- depender de nenhum estado deixado por elas.
--
-- O arranjo reproduz o PADRÃO medido no lote `7417` (araucária, 03/09): nome
-- de arquivo ambíguo ("Araucaria SPE", que casa com as duas empresas do
-- grupo) seguido de diagnóstico de conteúdo que nomeia a empresa por extenso
-- — as duas razões sociais são as que a própria 0153 já mede como reais. O
-- QUE NÃO SE TEM é a string exata que o diagnóstico do documento `009`
-- devolveu; isso não é fingido aqui.
-- =============================================================================
do $$
declare
  v_caso        uuid;
  v_bio         uuid;
  v_imob        uuid;
  v_ambigua     uuid;
  v_dummy1      uuid;
  v_dummy2      uuid;
  v_doc         uuid;
  v_doc2        uuid;
  v_doc3        uuid;
  v_ver         uuid;
  v_ver2        uuid;
  v_ver3        uuid;
  v_r           jsonb;
  v_pend_bloq   uuid;
  v_pend_resp   uuid;
  v_n           int;
  v_txt         text;
  v_tipo        text;
  v_sev         text;
  v_sobrep      boolean;
  v_estado      text;
  v_ent_atual   uuid;
begin
  v_caso := (fn_upsert_caso('Caso 0162 — o balcão não escuta a resposta'))::uuid;

  -- As duas empresas reais do grupo, como o diagnóstico as traria (razão
  -- social por extenso) — mesmos nomes que a 0153 já mede em produção.
  v_bio  := fn_upsert_entidade(v_caso, 'ARAUCÁRIA BIOENERGIA SPE LTDA.');
  v_imob := fn_upsert_entidade(v_caso, 'ARAUCÁRIA IMOBILIÁRIA SPE LTDA.');

  -- O documento chega classificado por NOME DE ARQUIVO, com o nome curto que
  -- casa com as duas — exatamente o `009` do lote 7417. Nasce o balcão, e o
  -- GATILHO da 0153 abre a pendência bloqueante pelo caminho normal.
  v_r := fn_registrar_documento(
    v_caso, 'Araucaria SPE', 'multi', '21,22,23,24,25', 'BALANCO', 0.9, 'nome_arquivo',
    'supabase_storage', 'b/009.pdf',
    '009_Balanco_Patrimonial_Araucaria_SPE_2025x2024x2023x2022x2021.pdf',
    false, 'HASH-162-009', 'ok');
  v_doc := (v_r->>'documento_id')::uuid;
  select id into v_ver from documento_versao where documento_id = v_doc order by n_versao desc limit 1;
  select entidade_id into v_ambigua from documento where id = v_doc;

  select id into v_pend_bloq from pendencia
  where caso_id = v_caso and motivo = 'entidade_ambigua:' || v_ambigua and estado <> 'resolvida';
  perform teste_assert_ent(v_pend_bloq is not null and v_ambigua <> v_bio and v_ambigua <> v_imob,
    'PRÉ-CONDIÇÃO: o documento caiu no balcão (nenhuma das duas empresas) e a bloqueante da 0153 abriu');

  -- ===========================================================================
  raise notice '--- 9.1 O CONTEÚDO RESPONDE À PRÓPRIA PERGUNTA ---';
  -- ===========================================================================
  --
  -- O diagnóstico de conteúdo lê o PRÓPRIO documento e nomeia a Imobiliária
  -- por extenso — o mesmo nome que já está cadastrado no caso. Tipo e período
  -- batem com o registrado de propósito, para isolar o comportamento de
  -- ENTIDADE do resto da função.
  v_r := fn_registrar_diagnostico(
    v_doc, v_ver, 'ARAUCÁRIA IMOBILIÁRIA SPE LTDA.', true, 'BALANCO', 'multi',
    '21,22,23,24,25', 'ok', null, 'Balanço patrimonial da Araucária Imobiliária.',
    'O balanço traz o CNPJ e a razão social completa da Imobiliária nas primeiras páginas.');
  perform teste_assert_ent((v_r->>'executado')::boolean, 'o diagnóstico executou', v_r::text);

  select id, descricao into v_pend_resp, v_txt from pendencia
  where caso_id = v_caso and motivo = 'diagnostico:entidade_ambigua_respondida:' || v_doc
    and estado <> 'resolvida';
  perform teste_assert_ent(v_pend_resp is not null,
    'a resposta do documento vira pendência (comportamento, não mecanismo): o conteúdo nomeou uma '
    'das candidatas e isso ficou visível em vez de ser jogado fora');
  perform teste_assert_ent(v_txt like '%ARAUCÁRIA IMOBILIÁRIA SPE LTDA.%',
    'a pendência NOMEIA a empresa que o conteúdo apontou', left(coalesce(v_txt, ''), 200));
  perform teste_assert_ent(v_txt like '%Confirme%' or v_txt like '%confira%' or v_txt like '%revisão%',
    'a pendência diz o que fazer (confirmar pela revisão), não só o achado',
    left(coalesce(v_txt, ''), 300));
  perform teste_assert_ent(v_txt like '%Justificativa do diagnóstico%CNPJ%',
    'a justificativa do diagnóstico (0161) chega junto, quando existe', left(coalesce(v_txt, ''), 400));

  -- ---------------------------------------------------------------------------
  -- O ASSERT MAIS IMPORTANTE DESTE ARQUIVO: a correção NÃO afrouxou a
  -- salvaguarda da 0153. A pendência bloqueante continua bloqueante, não
  -- sobrepujável e aberta, e o documento NÃO foi movido.
  -- ---------------------------------------------------------------------------
  select tipo::text, severidade::text, sobrepujavel, estado::text
    into v_tipo, v_sev, v_sobrep, v_estado
  from pendencia where id = v_pend_bloq;
  perform teste_assert_ent(
    v_tipo = 'entidade_incorreta' and v_sev = 'bloqueante' and v_sobrep = false and v_estado = 'aberta',
    'A PENDÊNCIA BLOQUEANTE DA 0153 CONTINUA INTACTA: bloqueante, não sobrepujável, aberta',
    format('tipo=%s severidade=%s sobrepujavel=%s estado=%s', v_tipo, v_sev, v_sobrep, v_estado));

  v_r := fn_avaliar_portao2(v_caso);
  perform teste_assert_ent((v_r->>'elegivel')::boolean = false,
    'e o PORTÃO 2 CONTINUA FECHADO — a resposta ajuda o revisor, não decide por ele',
    v_r::text);

  select entidade_id into v_ent_atual from documento where id = v_doc;
  perform teste_assert_ent(v_ent_atual = v_ambigua,
    'e o DOCUMENTO NÃO FOI MOVIDO — continua na entidade-balcão, como antes do diagnóstico');

  -- ===========================================================================
  raise notice '--- 9.2 CAMINHO NEGATIVO: nome que não bate com NENHUMA candidata ---';
  -- ===========================================================================
  --
  -- Segundo documento no MESMO balcão (o gatilho não abre pendência nova —
  -- seção 3/4 já prova isso). O diagnóstico aqui aponta uma empresa que não
  -- existe no caso: o conteúdo NÃO respondeu, e silêncio é a resposta certa.
  v_r := fn_registrar_documento(
    v_caso, 'Araucaria SPE', 'multi', '21,22,23,24,25', 'DRE', 0.9, 'nome_arquivo',
    'supabase_storage', 'b/042.pdf',
    '042_Demonstracao_do_Resultado_Araucaria_SPE_2025x2024x2023x2022x2021.pdf',
    false, 'HASH-162-042', 'ok');
  v_doc2 := (v_r->>'documento_id')::uuid;
  select id into v_ver2 from documento_versao where documento_id = v_doc2 order by n_versao desc limit 1;

  v_r := fn_registrar_diagnostico(
    v_doc2, v_ver2, 'Empresa Fantasma Que Não Existe No Mandato LTDA.', true, 'DRE', 'multi',
    '21,22,23,24,25', 'ok', null, null, null);
  perform teste_assert_ent((v_r->>'executado')::boolean, 'o diagnóstico executou', v_r::text);

  select count(*) into v_n from pendencia
  where caso_id = v_caso and motivo = 'diagnostico:entidade_ambigua_respondida:' || v_doc2
    and estado <> 'resolvida';
  perform teste_assert_ent(v_n = 0,
    'nome que não bate com NENHUMA empresa cadastrada: nenhuma pendência nova (ausência não vira dado)',
    format('abriu %s', v_n));

  -- ===========================================================================
  raise notice '--- 9.3 CAMINHO NEGATIVO: nome que casa com DUAS exatas ---';
  -- ===========================================================================
  --
  -- Montado por INSERT direto (fn_upsert_entidade nunca produziria isto — ela
  -- dedupe por casamento aproximado): duas entidades cuja forma CANÔNICA é
  -- IDÊNTICA. Quando o conteúdo aponta um nome que é EXATO contra as DUAS, a
  -- resposta é ambígua de novo — não decide, não abre nada.
  insert into entidade (caso_id, razao_social) values
    (v_caso, 'Teste Empate Estrutural LTDA'), (v_caso, 'TESTE EMPATE ESTRUTURAL LTDA.');
  select id into v_dummy1 from entidade
    where caso_id = v_caso and razao_social = 'Teste Empate Estrutural LTDA';
  select id into v_dummy2 from entidade
    where caso_id = v_caso and razao_social = 'TESTE EMPATE ESTRUTURAL LTDA.';
  select count(*) into v_n from fn_entidades_candidatas(v_caso, 'Teste Empate Estrutural Ltda')
    where exata;
  perform teste_assert_ent(v_n >= 2,
    'PRÉ-CONDIÇÃO: o nome de teste é EXATO contra as duas linhas gêmeas', format('%s', v_n));

  v_r := fn_registrar_documento(
    v_caso, 'Araucaria SPE', 'multi', '21,22,23,24,25', 'NOTAS_EXPL', 0.9, 'nome_arquivo',
    'supabase_storage', 'b/033.pdf',
    '033_Notas_Explicativas_Araucaria_SPE_2025x2024x2023x2022x2021.pdf',
    false, 'HASH-162-033', 'ok');
  v_doc3 := (v_r->>'documento_id')::uuid;
  select id into v_ver3 from documento_versao where documento_id = v_doc3 order by n_versao desc limit 1;

  v_r := fn_registrar_diagnostico(
    v_doc3, v_ver3, 'Teste Empate Estrutural Ltda', true, 'NOTAS_EXPL', 'multi',
    '21,22,23,24,25', 'ok', null, null, null);
  perform teste_assert_ent((v_r->>'executado')::boolean, 'o diagnóstico executou', v_r::text);

  select count(*) into v_n from pendencia
  where caso_id = v_caso and motivo = 'diagnostico:entidade_ambigua_respondida:' || v_doc3
    and estado <> 'resolvida';
  perform teste_assert_ent(v_n = 0,
    'nome que casa EXATO com DUAS candidatas: continua sem decidir, nenhuma pendência nova',
    format('abriu %s', v_n));

  raise notice 'entidade_ambigua (0162) OK — o conteúdo que responde à própria pergunta do balcão '
               'vira pendência que nomeia a empresa, sem mover o documento nem afrouxar a bloqueante '
               'da 0153, e o silêncio nos dois caminhos negativos é honesto';
end $$;

-- =============================================================================
-- SEÇÃO NOVA (0162) — REGRESSÃO: SEM BALCÃO, O RAMO CLÁSSICO (0121) CONTINUA
-- ABRINDO `diagnostico:entidade` EXATAMENTE COMO ANTES.
-- =============================================================================
do $$
declare
  v_caso  uuid;
  v_r     jsonb;
  v_doc   uuid;
  v_ver   uuid;
  v_n     int;
  v_txt   text;
begin
  v_caso := (fn_upsert_caso('Caso 0162 — regressão sem balcão'))::uuid;

  -- Documento registrado com uma entidade normal (não-ambígua) — o gatilho da
  -- 0153 não tem nada a abrir aqui, porque `fn_upsert_entidade` resolveu sem
  -- empate.
  v_r := fn_registrar_documento(
    v_caso, 'Metalúrgica Regressão LTDA.', 'anual', '2025', 'BALANCO', 0.9, 'nome_arquivo',
    'supabase_storage', 'b/001.pdf', '001_Balanco.pdf', false, 'HASH-162-REG', 'ok');
  v_doc := (v_r->>'documento_id')::uuid;
  select id into v_ver from documento_versao where documento_id = v_doc order by n_versao desc limit 1;

  perform teste_assert_ent(
    not exists (select 1 from pendencia where caso_id = v_caso and tipo = 'entidade_incorreta'
                and severidade = 'bloqueante'),
    'PRÉ-CONDIÇÃO: sem balcão, nenhuma pendência bloqueante de entidade nasceu do registro');

  -- Diagnóstico diverge de verdade: nome que não bate com NENHUMA empresa do
  -- caso (nem a registrada, nem outra qualquer) — é o caminho clássico da
  -- 0121, que a 0162 não pode ter mudado.
  v_r := fn_registrar_diagnostico(
    v_doc, v_ver, 'Empresa Totalmente Diferente E Nao Cadastrada LTDA.', true, 'BALANCO', 'anual',
    '2025', 'ok', null, null, 'O documento não menciona a Metalúrgica em lugar nenhum.');
  perform teste_assert_ent((v_r->>'executado')::boolean, 'o diagnóstico executou', v_r::text);

  select count(*), max(descricao) into v_n, v_txt from pendencia
  where caso_id = v_caso and motivo = 'diagnostico:entidade:' || v_doc and estado <> 'resolvida';
  perform teste_assert_ent(v_n = 1,
    'SEM REGRESSÃO: divergência real, sem balcão envolvido, continua abrindo `diagnostico:entidade` '
    'como antes da 0162', format('abriu %s', v_n));
  perform teste_assert_ent(v_txt like '%Empresa Totalmente Diferente%' and v_txt like '%Metalúrgica Regressão%',
    'e a descrição continua no formato clássico da 0121 (sugerido × registrado)',
    left(coalesce(v_txt, ''), 300));

  raise notice 'entidade_ambigua (0162, regressão) OK — sem balcão envolvido, o ramo clássico da '
               '0121 continua abrindo diagnostico:entidade exatamente como antes';
end $$;

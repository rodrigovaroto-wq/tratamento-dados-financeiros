-- =============================================================================
-- 0182 — fatia 1.7a do plano F1: `controlador` + `entidade_controlador`, o
--        grupo por CONTROLE COMUM que `controladora_id` (0181) não alcança
--
-- O DEFEITO, MEDIDO em 18/09/2026 contra os contratos sociais reais do mandato "AMO teste 00"
-- (caso `1be52ab4-9692-4e17-b332-1dc05dcc8c70`), lendo `campo_extraido` dos documentos
-- `tipo_taxonomia = 'CONTRATO_SOCIAL'` (ver `.claude/memory/grupo-por-controle-comum-sem-holding.md`
-- e a seção 12.2/fatia 1.7 do roadmap): as 8 empresas do mandato NÃO têm holding. Nos 4
-- contratos legíveis, TODOS os sócios são pessoas FÍSICAS e nenhuma empresa é sócia de outra —
-- GENERAL BUSINESS CENTER (Karina Souto Damasio Tascino 1.677.578 + Rafael Teles 1.677.577 de
-- 3.355.155 quotas), GENERAL TABACO (Igor Souto Damasio, 10.000 de 10.000 quotas), GLOBAL STORE
-- (Rafael Teles, 1.000.000 de 1.000.000 quotas), OMNIBEAUTY MARCAS (Igor Souto Damasio 60% ·
-- Leandro Morales Lima 20% · Roney Thiago Costa 20%). As outras 4 entidades seguem sem estrutura
-- societária medida — 2 delas (OMNIBEAUTY DISTRIBUIDORA PR e RS) não têm contrato social nenhum,
-- e 2 contratos (`Certidão 5ª Alteração - AMOBELEZA.pdf`, `Certidão 4ª Alteração -
-- CORPORATE.pdf`) vieram com ZERO campos extraídos. Estrutura societária medida em **4 de 8**
-- entidades reais — o resto é ausência não fabricada (regra 1 do CLAUDE.md).
--
-- A `0181` modela participação como `entidade.controladora_id` — FK de EMPRESA para EMPRESA.
-- Nesta estrutura real, essa coluna fica CORRETAMENTE NULL nas 8 entidades, e o sistema não tem
-- onde registrar que elas formam um grupo: o vínculo real é CONTROLE COMUM pelas mesmas pessoas
-- físicas, e ele não passa por dentro de nenhuma das empresas. É a regra 7 do CLAUDE.md de novo —
-- NULL por "o grupo é horizontal" continua indistinguível de NULL por "ninguém cadastrou", e esta
-- migration não resolve essa ambiguidade (isso é `forma_de_controle`, fatia 1.7b, migration 0183,
-- **fora do escopo desta migration** — não antecipada aqui).
--
-- A `0181` continua válida e correta para mandatos COM holding; esta fatia a COMPLEMENTA, sem
-- tocar `entidade.controladora_id` nem `entidade.papel_no_grupo` (0179).
--
-- O QUE ESTA MIGRATION ENTREGA: (1) `controlador` — a pessoa (física, ou jurídica externa ao
-- perímetro) que detém participação, escopada por caso como `entidade`; (2)
-- `entidade_controlador` — o vínculo N:N com percentual, SEM temporalidade; (3) a guarda de soma
-- (nunca deixa a soma dos percentuais CONHECIDOS de uma entidade passar de 100 — nunca exige que
-- some 100, porque conhecimento parcial é o estado normal aqui: 4 de 8 entidades não têm
-- estrutura lida); (4) percentual NULL distinguível da ausência da linha; (5) dois caminhos de
-- escrita, humano-chamados, com evento_auditoria; (6) o consumidor mínimo
-- `fn_grupo_por_controle_comum`, que reconhece as entidades do caso como grupo por FECHO
-- TRANSITIVO de controle comum. NADA é inferido de `campo_extraido`, nome ou CNPJ — a ficha
-- mostra que os dados existem em `campo_extraido` para as 4 entidades medidas, e mesmo assim
-- inferir automaticamente seria ausência virando dado (regra 1). Os dois caminhos de escrita são
-- chamados por um humano/analista com os números do contrato na mão.
--
-- ENUM vs `check`, DECIDIDO E JUSTIFICADO (mesmo critério que a 0179 e a 0180 já usaram, em
-- direções opostas): `tipo_pessoa` de um controlador é FÍSICA ou JURÍDICA — vocabulário FECHADO
-- e universalmente conhecido (não é um rótulo de domínio deste projeto que possa crescer, como
-- `escopo` de `perimetro` na 0180, que é texto livre porque o vocabulário não estava medido).
-- É o mesmo raciocínio da 0179 para `papel_no_grupo` (enum, 5 rótulos fechados e conhecidos):
-- aqui o vocabulário é ainda mais estável — pessoa física ou jurídica é uma dicotomia do direito
-- civil brasileiro, não algo que uma sessão futura vá precisar estender. Por isso `tipo_pessoa`
-- é ENUM (`controlador_tipo_pessoa`), não `check (tipo_pessoa in (...))`.
--
-- SEM TEMPORALIDADE, DELIBERADAMENTE — documentado como LIMITAÇÃO, não esquecimento (mesmo
-- espírito da simplicidade deliberada da 0181, que também não modela sócios múltiplos ou
-- participação cruzada além da cadeia simples de controle). Alteração contratual ao longo do
-- tempo é real (um sócio pode vender sua quota em outubro), mas não há NADA medido hoje que
-- justifique `desde`/`ate` aqui — ao contrário da 0180, cujo `perimetro` tinha o próprio roadmap
-- nomeando a troca de escopo no meio do mandato como risco real. Se uma sessão futura precisar de
-- histórico de participação societária, é decisão de F4 com um caso real na mão, não desta
-- migration.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2 do CLAUDE.md) — EXECUTADA, não descrita, em
-- `Supabase/test/entidade_controlador.test.sql`:
--
-- (a) A GUARDA DE SOMA: com a criação do `trigger trg_entidade_controlador_soma_maxima`
--     comentada nesta migration (a função-guarda existe, mas nada a chama) e
--     `teste_assert_0182` trocado temporariamente para não abortar no primeiro assert (`raise
--     notice` em vez de `raise exception`) e contar todos — **3 dos 24 asserts do arquivo
--     reprovaram**: "a terceira participação (que passaria de 100%) é recusada", "e nada foi
--     gravado — a soma continua em 80, não 130" e "e o terceiro sócio nem aparece no vínculo" (o
--     bloco 3 do arquivo). Os outros 21 passam com ou sem a guarda — inclusive os dois primeiros
--     inserts do MESMO bloco 3 (sócio A com 45%, sócio B com 35%, somando 80 ≤ 100): eles nunca
--     dependeram da guarda para passar, porque nenhum deles ultrapassa 100 sozinho — só o
--     terceiro insert (que levaria a soma a 130) discrimina a regressão. Religada a criação do
--     trigger, os 24 asserts passam.
--
-- (b) O FECHO TRANSITIVO: com a definição de `par_direto`/`alcance` na CTE de
--     `fn_grupo_por_controle_comum` trocada temporariamente para um JOIN DE UM SALTO (sem `with
--     recursive`, sem propagar — cada entidade só enxerga quem compartilha controlador
--     DIRETAMENTE com ela) e `teste_assert_0182` contando todos — **MEDIDO 3 dos 24 asserts do
--     arquivo reprovaram, não 2 como uma primeira leitura do desenho sugeria**: além de "A e C
--     (que só compartilham controlador via B, nunca diretamente) caem no MESMO grupo" e "o grupo
--     de A/B/C tem exatamente 3 entidades, não 2" (as duas óbvias), TAMBÉM "A e B estão no mesmo
--     grupo" reprovou — um efeito colateral do representante mínimo (`grupo_id`) que a medição
--     revelou e que não estava previsto antes de rodar: sem a recursão, A só alcança {A, B} e seu
--     `grupo_id` é o menor entre os dois; B alcança {A, B, C} (ela vê tanto A quanto C
--     diretamente) e seu `grupo_id` é o menor entre os TRÊS — quando C ordena antes de A
--     (textualmente), o `grupo_id` de B vira o de C, DIFERENTE do de A, e a igualdade "A e B no
--     mesmo grupo" quebra mesmo sem o teste perguntar sobre C. Ou seja: a quebra da transitividade
--     vaza para asserts que pareciam de um salto só, porque o representante do grupo depende do
--     alcance INTEIRO, não só do vínculo direto. Os outros 21 passam com ou sem a recursão,
--     inclusive "B e C estão no mesmo grupo" (a única relação verdadeiramente de um salto que
--     sobreviveu, porque B enxerga A e C nos dois cenários, e a comparação é sempre com o mesmo
--     `grupo_id` de B). Religada a recursão (0182 como está), os 24 asserts passam.
--
-- (c) OS 21 QUE NÃO DISCRIMINAM CADA REGRESSÃO, nomeados aqui pela mesma honestidade que a
--     0181 usou com os 25 dela: os testes de `controlador_caso_documento_unico` (unicidade de
--     documento por caso), de `entidade_controlador_percentual_valido` (check de tabela por
--     UPDATE direto), de reatribuição de percentual (reatribuir é permitido), de percentual NULL
--     distinguível de linha ausente, e de controle cross-caso são invariantes GENUÍNOS,
--     independentes tanto da guarda de soma quanto da recursão — nenhum dos dois protocolos
--     acima os derruba, e não deveriam: eles protegem invariantes DIFERENTES.
--
-- **Pronto quando** (critério da fatia 1.7, roadmap): as 8 entidades do mandato real podem ser
-- reconhecidas como um grupo. Esta migration entrega o MODELO e o CONSUMIDOR — registrar os
-- controladores reais (Karina, Rafael, Igor, Leandro, Roney) e os vínculos das 4 entidades
-- medidas contra as 8 é decisão de uma sessão seguinte, contra a sonda (migration escrita ≠
-- aplicada). `forma_de_controle` (o que torna o NULL de `controladora_id` da 0181 distinguível
-- de "ninguém cadastrou") é a 0183 — fatia 1.7b, NÃO desta migration.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- (1) O ENUM E A TABELA `controlador`.
-- -----------------------------------------------------------------------------

create type controlador_tipo_pessoa as enum ('fisica', 'juridica');

comment on type controlador_tipo_pessoa is
  '0182: pessoa física ou jurídica que detém participação num controlador comum. Vocabulário '
  'FECHADO e universalmente conhecido (dicotomia do direito civil brasileiro) — não é um rótulo '
  'de domínio deste projeto que possa crescer, ao contrário de `perimetro.escopo` (0180, texto '
  'livre por vocabulário não medido). Mesmo critério da 0179 para `papel_no_grupo` (enum): '
  'vocabulário fechado e conhecido vira enum; vocabulário aberto e não medido fica texto livre.';

create table controlador (
  id          uuid primary key default gen_random_uuid(),
  caso_id     uuid not null references caso(id) on delete cascade,
  nome        text not null,
  documento   text,
  tipo_pessoa controlador_tipo_pessoa not null,
  criado_em   timestamptz not null default now()
);

comment on table controlador is
  '0182 (fatia 1.7a do plano F1): a pessoa (física, ou jurídica externa ao perímetro do caso) '
  'que detém participação em uma ou mais entidades do caso — escopada por `caso_id`, como '
  '`entidade`. Existe para registrar CONTROLE COMUM sem inventar uma holding que não existe '
  '(ver `.claude/memory/grupo-por-controle-comum-sem-holding.md`): o vínculo mora em '
  '`entidade_controlador`, e `fn_grupo_por_controle_comum` agrupa as entidades por FECHO '
  'TRANSITIVO de controladores compartilhados. Não confundir com `entidade` — um controlador '
  'PESSOA FÍSICA nunca vira `entidade` (essa tabela é só de pessoas jurídicas do mandato); um '
  'controlador PESSOA JURÍDICA aqui é externo ao perímetro (senão a hierarquia seria '
  '`entidade.controladora_id`, 0181, não isto). Os dois caminhos de escrita são '
  '`fn_controlador_registrar` e `fn_entidade_definir_controlador` — nunca inferência automática '
  'a partir de `campo_extraido`, nome ou CNPJ (regra 1 do CLAUDE.md).';

comment on column controlador.documento is
  '0182: CPF ou CNPJ do controlador, texto livre e OPCIONAL — não há função de canonicalização '
  'de CPF neste repositório (só `fn_cnpj_canonico`, 0169, que é de CNPJ), e exigir o documento '
  'transformaria "sabemos que é sócio, mas não temos o CPF no contrato" (o estado normal aqui) '
  'em bloqueio. NULL é um documento não informado, distinto de um documento informado errado.';

-- Unicidade de DOCUMENTO por caso (quando informado): a mesma pessoa não pode ser cadastrada
-- duas vezes como dois controladores diferentes no mesmo caso — isso duplicaria a contagem da
-- guarda de soma por entidade (item 3) sem que ninguém tivesse decidido isso. Não protege NOMES
-- repetidos (dois "Igor Souto Damasio" com documentos diferentes, ou sem documento, são
-- permitidos — nome sozinho não é identidade, mesma lição da 0169 para entidade/CNPJ) — só a
-- reafirmação do MESMO documento.
create unique index controlador_caso_documento_unico on controlador(caso_id, documento)
  where documento is not null;

comment on index controlador_caso_documento_unico is
  '0182: o mesmo documento não pode virar dois controladores diferentes no mesmo caso — '
  'duplicaria a contagem da guarda de soma sem decisão nenhuma. Documento NULL não colide com '
  'nada (vários controladores sem documento informado são permitidos).';

create index idx_controlador_caso on controlador(caso_id);

alter table controlador enable row level security;
drop policy if exists controlador_read on controlador;
create policy controlador_read on controlador
  for select to authenticated using (true);
grant select on controlador to authenticated;

-- -----------------------------------------------------------------------------
-- (2) O CAMINHO DE ESCRITA DE `controlador` — mesma doutrina da 0179/0180/0181: humano decide,
-- nunca inferência automática.
-- -----------------------------------------------------------------------------

create function public.fn_controlador_registrar(p_caso_id uuid, p_nome text, p_documento text,
                                                  p_tipo_pessoa controlador_tipo_pessoa, p_autor text)
RETURNS uuid
    LANGUAGE plpgsql
    AS $$
declare
  v_caso_existe boolean;
  v_documento   text := nullif(trim(coalesce(p_documento, '')), '');
  v_id          uuid;
begin
  if p_nome is null or length(trim(p_nome)) = 0 then
    raise exception 'p_nome não pode ser vazio — um controlador sem nome não é registrável';
  end if;

  select exists(select 1 from caso where id = p_caso_id) into v_caso_existe;
  if not v_caso_existe then
    raise exception 'caso % não encontrado', p_caso_id;
  end if;

  insert into controlador (caso_id, nome, documento, tipo_pessoa)
  values (p_caso_id, trim(p_nome), v_documento, p_tipo_pessoa)
  returning id into v_id;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
  values (p_autor, 'controlador_registrado', 'controlador:' || v_id,
          jsonb_build_object('caso_id', p_caso_id, 'nome', trim(p_nome),
                              'documento', v_documento, 'tipo_pessoa', p_tipo_pessoa));

  return v_id;
end;
$$;

comment on function public.fn_controlador_registrar(uuid, text, text, controlador_tipo_pessoa, text) IS
  '0182: o ÚNICO caminho de escrita de `controlador` — chamado por um humano/analista (portal '
  'ou SQL direto; o portal não é escopo desta fatia). Grava evento_auditoria (ator = p_autor, '
  'nunca ''sistema:...''). NADA é inferido de campo_extraido, nome ou CNPJ — a decisão de QUEM é '
  'controlador vem do contrato social na mão de quem chama.';

grant execute on function public.fn_controlador_registrar(uuid, text, text, controlador_tipo_pessoa, text) to authenticated;

-- -----------------------------------------------------------------------------
-- (3) A TABELA `entidade_controlador` — o vínculo N:N, SEM temporalidade (deliberado, ver
-- cabeçalho), com percentual em (0,100] e no MÁXIMO uma linha por (entidade, controlador) — não
-- há histórico de reatribuição aqui (isso mora em evento_auditoria, mesma doutrina da 0179/0181).
-- -----------------------------------------------------------------------------

create table entidade_controlador (
  id             uuid primary key default gen_random_uuid(),
  caso_id        uuid not null references caso(id) on delete cascade,
  entidade_id    uuid not null references entidade(id) on delete cascade,
  controlador_id uuid not null references controlador(id) on delete cascade,
  percentual     numeric(6,3),
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  constraint entidade_controlador_par_unico unique (entidade_id, controlador_id)
);

comment on table entidade_controlador is
  '0182 (fatia 1.7a do plano F1): quem controla o quê, por CONTROLE COMUM — o vínculo N:N entre '
  '`entidade` e `controlador` que `entidade.controladora_id` (0181, FK de empresa para empresa) '
  'não alcança quando não há holding (ver `.claude/memory/grupo-por-controle-comum-sem-holding.md`'
  ' e o cabeçalho desta migration). SEM `desde`/`ate` — DELIBERADO, é uma limitação documentada, '
  'não um esquecimento (ver cabeçalho): não há nada medido hoje que justifique temporalidade '
  'aqui, ao contrário do `perimetro` da 0180. NO MÁXIMO uma linha por (entidade_id, '
  'controlador_id) — reatribuir o percentual é permitido (fn_entidade_definir_controlador '
  'sobrescreve o ESTADO ATUAL), o histórico mora em evento_auditoria. O único caminho de escrita '
  'é `fn_entidade_definir_controlador`.';

comment on column entidade_controlador.percentual is
  '0182: o percentual que este controlador detém desta entidade, em (0, 100], ou NULL. A '
  'DISTINÇÃO da regra 7 do CLAUDE.md: percentual NULL com a LINHA PRESENTE significa "é sócio '
  'CONHECIDO, o percentual NÃO foi medido" (ex.: um contrato que nomeia o sócio sem discriminar '
  'a fração, ou um dos 4 casos deste mandato em que o contrato social ainda não foi lido). A '
  'AUSÊNCIA DA LINHA inteira significa "não se sabe se esta pessoa é sócia desta entidade" — '
  'nem chegou a ser perguntado. As duas ausências (percentual NULL vs. linha ausente) NÃO SÃO A '
  'MESMA COISA, e confundi-las apagaria a diferença entre "sabemos que é sócio, falta o número" '
  'e "não sabemos nada". Nunca inserir uma linha só para registrar incerteza quando não há '
  'vínculo de sociedade conhecido algum.';

alter table entidade_controlador add constraint entidade_controlador_percentual_valido
  check (percentual is null or (percentual > 0 and percentual <= 100));

comment on constraint entidade_controlador_percentual_valido on entidade_controlador is
  '0182: percentual tem de estar em (0, 100] quando informado — zero ou negativo não é '
  'participação, mais de 100% não existe. Protege INSERT/UPDATE direto, mesma doutrina do '
  '`entidade_percentual_valido` da 0181 e do `perimetro_intervalo_valido` da 0180.';

create index idx_entidade_controlador_caso on entidade_controlador(caso_id);
create index idx_entidade_controlador_entidade on entidade_controlador(entidade_id);
create index idx_entidade_controlador_controlador on entidade_controlador(controlador_id);

alter table entidade_controlador enable row level security;
drop policy if exists entidade_controlador_read on entidade_controlador;
create policy entidade_controlador_read on entidade_controlador
  for select to authenticated using (true);
grant select on entidade_controlador to authenticated;

-- -----------------------------------------------------------------------------
-- (4) A GUARDA DE SOMA — nunca deixa a soma dos percentuais CONHECIDOS (não-nulos) de uma
-- entidade passar de 100. NUNCA EXIGE QUE SOME 100: conhecimento parcial é o estado normal aqui
-- (4 das 8 entidades do mandato real não têm estrutura societária lida) — exigir soma exata
-- transformaria "ainda não medimos todos os sócios" em erro e empurraria quem estivesse
-- cadastrando a inventar o resto (a regra 1 do CLAUDE.md pelo avesso). É um TRIGGER, não um
-- `check` de linha única, porque a soma é uma propriedade de VÁRIAS linhas (todas as
-- `entidade_controlador` da mesma entidade) — nenhum `check` de tabela enxerga outras linhas.
--
-- Dispara depois de gravar (AFTER), lê a soma já incluindo a linha nova/atualizada, e SÓ quando
-- `NEW.percentual` não é nulo (uma linha com percentual NULL nunca pode, sozinha, levar a soma a
-- passar de 100 — soma-la é a mesma coisa que não somá-la). É a MEDIÇÃO NÃO-VAZIA (a) do
-- cabeçalho desta migration.
-- -----------------------------------------------------------------------------

create function public.fn_trg_entidade_controlador_soma_maxima() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
  v_soma  numeric;
  v_razao text;
begin
  select coalesce(sum(percentual), 0) into v_soma
    from entidade_controlador
   where entidade_id = NEW.entidade_id
     and percentual is not null;

  if v_soma > 100 then
    select razao_social into v_razao from entidade where id = NEW.entidade_id;
    raise exception 'a soma dos percentuais CONHECIDOS de "%" passaria de 100%% (chegaria a %) — '
                     'conhecimento parcial é normal aqui (nem toda entidade tem todos os sócios '
                     'medidos), mas a soma do que É CONHECIDO nunca pode superar o todo',
      coalesce(v_razao, NEW.entidade_id::text), v_soma;
  end if;

  return NEW;
end;
$$;

comment on function public.fn_trg_entidade_controlador_soma_maxima() IS
  '0182: a guarda de soma — nunca deixa a soma dos percentuais NÃO-NULOS de uma entidade passar '
  'de 100. NÃO exige que some 100 (regra 1 do CLAUDE.md pelo avesso — ver cabeçalho): '
  'conhecimento parcial (4 de 8 entidades do mandato real sem estrutura lida) é o estado normal, '
  'e exigir soma exata puniria isso. É a MEDIÇÃO NÃO-VAZIA (a) desta migration — sem o trigger '
  'abaixo chamando esta função, uma terceira participação que ultrapassasse 100% seria gravada '
  'em silêncio.';

create trigger trg_entidade_controlador_soma_maxima
  after insert or update of percentual on entidade_controlador
  for each row
  when (NEW.percentual is not null)
  execute function fn_trg_entidade_controlador_soma_maxima();

-- -----------------------------------------------------------------------------
-- (5) O CAMINHO DE ESCRITA DE `entidade_controlador` — mesma doutrina: humano decide, nunca
-- inferência automática. Upsert por (entidade_id, controlador_id): reatribuir o percentual é
-- permitido (é o ESTADO ATUAL, como fn_entidade_definir_participacao/fn_entidade_definir_papel_no_grupo
-- — o histórico mora em evento_auditoria, não numa coluna imutável).
-- -----------------------------------------------------------------------------

create function public.fn_entidade_definir_controlador(p_entidade_id uuid, p_controlador_id uuid,
                                                          p_percentual numeric, p_autor text)
RETURNS uuid
    LANGUAGE plpgsql
    AS $$
declare
  v_caso_entidade       uuid;
  v_caso_controlador    uuid;
  v_percentual_anterior numeric;
  v_id                  uuid;
begin
  select caso_id into v_caso_entidade from entidade where id = p_entidade_id;
  if v_caso_entidade is null then
    raise exception 'entidade % não encontrada', p_entidade_id;
  end if;

  select caso_id into v_caso_controlador from controlador where id = p_controlador_id;
  if v_caso_controlador is null then
    raise exception 'controlador % não encontrado', p_controlador_id;
  end if;

  if v_caso_controlador <> v_caso_entidade then
    raise exception 'controlador % não pertence ao mesmo caso que a entidade %',
      p_controlador_id, p_entidade_id;
  end if;

  select percentual into v_percentual_anterior
    from entidade_controlador
   where entidade_id = p_entidade_id and controlador_id = p_controlador_id;

  insert into entidade_controlador (caso_id, entidade_id, controlador_id, percentual)
  values (v_caso_entidade, p_entidade_id, p_controlador_id, p_percentual)
  on conflict (entidade_id, controlador_id)
  do update set percentual = excluded.percentual, atualizado_em = now()
  returning id into v_id;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
  values (p_autor, 'entidade_controlador_definido', 'entidade:' || p_entidade_id,
          jsonb_build_object('controlador_id', p_controlador_id,
                              'percentual_novo', p_percentual,
                              'percentual_anterior', v_percentual_anterior));

  return v_id;
end;
$$;

comment on function public.fn_entidade_definir_controlador(uuid, uuid, numeric, text) IS
  '0182: o ÚNICO caminho de escrita de `entidade_controlador` — chamado por um humano/analista '
  '(portal ou SQL direto; o portal não é escopo desta fatia). Valida que entidade e controlador '
  'existem e pertencem ao mesmo caso. Upsert por (entidade_id, controlador_id) — reatribuir o '
  'percentual é permitido, é o ESTADO ATUAL (histórico em evento_auditoria). A guarda de soma '
  '(fn_trg_entidade_controlador_soma_maxima) recusa a gravação se a soma dos percentuais '
  'conhecidos da entidade passasse de 100. Grava evento_auditoria (ator = p_autor, nunca '
  '''sistema:...''). NADA é inferido de campo_extraido, nome ou CNPJ.';

grant execute on function public.fn_entidade_definir_controlador(uuid, uuid, numeric, text) to authenticated;

-- -----------------------------------------------------------------------------
-- (6) O CONSUMIDOR MÍNIMO — `fn_grupo_por_controle_comum`, que é o que prova a fatia (regra 7 do
-- CLAUDE.md, mesma lição da 0179/0180/0181): agrupa as entidades do caso por CONTROLE COMUM, por
-- FECHO TRANSITIVO — se A e B compartilham um controlador, e B e C compartilham OUTRO
-- controlador (não necessariamente o mesmo), as três formam UM grupo. É a pergunta que o
-- critério de pronto do roadmap cobra: "as 8 entidades do mandato real podem ser reconhecidas
-- como um grupo".
--
-- `par_direto` é a CTE de UM salto (entidades que compartilham um controlador DIRETAMENTE),
-- marcada `MATERIALIZED` DE PROPÓSITO — não enfeite (ver 0152, que mediu a diferença): ela é
-- referenciada DUAS VEZES dentro da CTE recursiva `alcance` (uma vez implicitamente via join no
-- termo recursivo, que roda uma vez POR SALTO da recursão) — sem `MATERIALIZED`, o Postgres 12+
-- teria o direito de reavaliar o self-join de `entidade_controlador` a CADA iteração da
-- recursão em vez de calculá-lo uma vez só, e o agrupamento que existe para conter o custo do
-- self-join viraria recalculado por salto — exatamente o padrão que a 0152 mediu e nomeou no
-- cabeçalho dela.
--
-- `alcance` propaga o alcance de cada entidade pelos pares diretos, com `UNION` (não `UNION
-- ALL`) — a deduplicação é o que garante TERMINAÇÃO num grafo com CICLO (A-B-C-A): sem ela, a
-- recursão giraria para sempre revisitando os mesmos pares. O limite de 50 saltos (`salto < 50`)
-- é o MESMO headroom da guarda de ciclo da 0181 — generoso para qualquer cadeia real deste
-- projeto (mandatos têm, no máximo, poucas dezenas de entidades), protegendo contra dado sujo
-- que já tivesse um grafo maior do que qualquer mandato real produziria.
--
-- `grupo_id` é o `entidade_id` alcançável de MENOR ordenação textual (`uuid` não tem operador
-- `min` nativo no Postgres — `min(al.alcancavel::text)::uuid` é o contorno) a partir de cada
-- entidade — um representante ARBITRÁRIO mas ESTÁVEL do componente conexo, não uma entidade
-- "principal" de verdade — a mesma convenção que `nivel` na 0181 é posição na cadeia, não juízo
-- de valor. Entidade SEM controlador nenhum registrado não aparece na saída — ausência
-- na saída significa "nenhum vínculo de controle comum registrado para ela", não "ela está fora
-- de qualquer grupo real" (a mesma cautela da regra 7: `perimetro` vazio também não afirma nada
-- sobre o combinado real).
-- -----------------------------------------------------------------------------

create function public.fn_grupo_por_controle_comum(p_caso_id uuid)
RETURNS TABLE(entidade_id uuid, razao_social text, grupo_id uuid)
    LANGUAGE sql
    STABLE
    AS $$
  with recursive par_direto as materialized (
    select ec1.entidade_id as a, ec2.entidade_id as b
      from entidade_controlador ec1
      join entidade_controlador ec2
        on ec2.controlador_id = ec1.controlador_id
       and ec2.entidade_id <> ec1.entidade_id
     where ec1.caso_id = p_caso_id
  ),
  alcance(entidade_id, alcancavel, salto) as (
    select e.id, e.id, 0
      from entidade e
     where e.caso_id = p_caso_id
       and exists (
         select 1 from entidade_controlador ec
          where ec.entidade_id = e.id and ec.caso_id = p_caso_id)
    union
    select al.entidade_id, pd.b, al.salto + 1
      from alcance al
      join par_direto pd on pd.a = al.alcancavel
     where al.salto < 50
  )
  select al.entidade_id, e.razao_social, min(al.alcancavel::text)::uuid as grupo_id
    from alcance al
    join entidade e on e.id = al.entidade_id
   group by al.entidade_id, e.razao_social
   order by min(al.alcancavel::text), e.razao_social;
$$;

comment on function public.fn_grupo_por_controle_comum(uuid) IS
  '0182: agrupa as entidades do caso por CONTROLE COMUM, por FECHO TRANSITIVO — se A e B '
  'compartilham um controlador, e B e C compartilham outro, as três caem no mesmo grupo. '
  '`par_direto` (pares de um salto) é MATERIALIZED de propósito (evita reavaliação a cada '
  'iteração da recursão — mesma lição da 0152, ver comentário acima da função). `grupo_id` é o '
  'entidade_id alcançável de menor ordenação textual — representante arbitrário mas estável do '
  'componente conexo, não uma entidade "principal". Entidade sem controlador registrado não '
  'aparece na saída — ausência '
  'não afirma nada sobre grupo real algum (regra 7 do CLAUDE.md). Limite de 50 saltos, mesmo '
  'headroom da guarda de ciclo da 0181. É o consumidor mínimo que prova a fatia 1.7 do roadmap: '
  '"as 8 entidades do mandato real podem ser reconhecidas como um grupo".';

grant execute on function public.fn_grupo_por_controle_comum(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- O CATÁLOGO DA SONDA.
-- -----------------------------------------------------------------------------

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('controlador_tabela_existe', '0182', 'tabela', 'controlador',
   null, null,
   'A tabela nova da fatia 1.7a: a pessoa (física ou jurídica externa ao perímetro) que detém '
   'participação. Ausente (banco anterior à 0182), não há onde registrar QUEM controla as '
   'entidades quando não há holding — só `entidade.controladora_id` (0181), que fica NULL neste '
   'arranjo por estar CERTA.',
   'importante', 761)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('entidade_controlador_tabela_existe', '0182', 'tabela', 'entidade_controlador',
   null, null,
   'O vínculo N:N nova da fatia 1.7a entre entidade e controlador, com percentual. Ausente, '
   '`controlador` fica sem onde se ligar a entidade nenhuma — existe, mas não vincula nada.',
   'importante', 762)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('fn_controlador_registrar_existe', '0182', 'funcao', 'fn_controlador_registrar',
   null, null,
   'O único caminho de escrita de `controlador`. Sem ele, a tabela nova entrega o mesmo vazio '
   'que `papel_no_grupo` tinha antes da 0179 — existe, mas nada a preenche.',
   'importante', 763)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('fn_entidade_definir_controlador_existe', '0182', 'funcao', 'fn_entidade_definir_controlador',
   null, null,
   'O único caminho de escrita do vínculo `entidade_controlador`. Sem ele, não há como ligar uma '
   'entidade a um controlador com segurança contra a soma passando de 100.',
   'importante', 764)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('fn_trg_entidade_controlador_soma_maxima_existe', '0182', 'funcao',
   'fn_trg_entidade_controlador_soma_maxima',
   null, null,
   'A guarda de soma (nunca > 100, nunca exige = 100). Sem ela, uma terceira participação que '
   'ultrapassasse 100% seria gravada em silêncio — é a MEDIÇÃO NÃO-VAZIA (a) desta migration.',
   'importante', 765)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('fn_grupo_por_controle_comum_existe', '0182', 'funcao', 'fn_grupo_por_controle_comum',
   null, null,
   'O consumidor mínimo — agrupa entidades por controle comum, por fecho transitivo. Sem ele, '
   'nada prova que `entidade_controlador` responde à pergunta que a fatia 1.7 existe para '
   'responder: reconhecer as 8 entidades do mandato real como um grupo (regra 7 do CLAUDE.md).',
   'informativo', 766)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0182', revisado_em = current_date,
       observacao = 'A 0182 fecha a fatia 1.7a do plano F1: `controlador` (pessoa física, ou '
                    'jurídica externa ao perímetro, escopada por caso) e `entidade_controlador` '
                    '(vínculo N:N com percentual, SEM temporalidade — limitação deliberada, ver '
                    'cabeçalho) para registrar CONTROLE COMUM quando não há holding — o arranjo '
                    'medido nas 8 entidades do mandato AMO ('
                    '.claude/memory/grupo-por-controle-comum-sem-holding.md). A guarda de soma '
                    '(trigger, nunca > 100, nunca exige = 100) protege contra participação '
                    'inventada sem punir conhecimento parcial (4 de 8 entidades sem estrutura '
                    'lida). Dois caminhos de escrita explícitos, chamados por humano '
                    '(fn_controlador_registrar, fn_entidade_definir_controlador) — nunca '
                    'inferência automática. Consumidor mínimo fn_grupo_por_controle_comum agrupa '
                    'por FECHO TRANSITIVO (CTE recursiva, par_direto MATERIALIZED). NÃO toca '
                    'entidade.controladora_id nem entidade.papel_no_grupo — a 0181/0179 seguem '
                    'válidas para mandatos com holding, esta fatia as complementa. '
                    '`forma_de_controle` (0183, fatia 1.7b) NÃO é desta migration. Nenhum caso '
                    'real tem controlador ou vínculo registrado ainda — aplicar a migration e '
                    'registrar os controladores reais das 4 entidades medidas é decisão de uma '
                    'sessão seguinte, contra a sonda.';

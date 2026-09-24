-- =============================================================================
-- 0183 — fatia 1.7b do plano F1: `entidade.forma_de_controle`, o que torna o
--        `controladora_id` VAZIO distinguível de um NÃO PREENCHIDO
--
-- O DEFEITO: a `0181` deu `entidade.controladora_id` (FK de empresa para empresa). A `0182` deu
-- `controlador`/`entidade_controlador`, onde registrar controle comum por PESSOA física quando
-- não há holding (ver `.claude/memory/grupo-por-controle-comum-sem-holding.md`). NENHUMA das
-- duas torna o SILÊNCIO legível: hoje `controladora_id IS NULL` é indistinguível entre "o grupo
-- é horizontal, apuramos e não há controladora empresa" (o mundo da 0182 — as 8 entidades reais
-- do mandato AMO) e "ninguém cadastrou ainda" (o mundo de TODA entidade nova, por construção,
-- desde a 0001). É a regra 7 do CLAUDE.md na forma mais literal: estágio que não rodou (ninguém
-- decidiu) tem a mesma aparência de estágio que rodou e concluiu que não há controladora
-- (apuramos, é horizontal). O critério de pronto da fatia 1.7 (roadmap, seção 12.2) cobra
-- exatamente isto: "um `controladora_id` vazio passa a ser distinguível de um não preenchido".
--
-- DECISÃO DE MODELO JÁ TOMADA, e registrada aqui com o motivo (para que uma sessão futura não
-- leia a ausência como esquecimento — a própria regra 7 aplicada à decisão em si, não só ao
-- dado): o enum `entidade_forma_de_controle` tem TRÊS rótulos, e um QUARTO foi CONSIDERADO e
-- RECUSADO. O quarto seria algo como `sem_controlador_identificavel` — para "apuramos e NÃO HÁ
-- controlador nenhum, capital pulverizado" — e ele foi descartado porque **nada medido hoje o
-- justifica**: os 4 contratos sociais legíveis do mandato real (GENERAL BUSINESS CENTER,
-- GENERAL TABACO, GLOBAL STORE, OMNIBEAUTY MARCAS — a mesma medição da `.claude/memory/
-- grupo-por-controle-comum-sem-holding.md`) têm controlador identificado em TODOS os casos
-- (pessoas físicas nomeadas, com percentual ou não). As outras 4 entidades não têm contrato
-- nenhum lido — isso é `indefinido` (ninguém apurou, não "apurei e não há"), não um quarto
-- estado. Criar o rótulo agora seria estrutura sem medição (regra 1 do CLAUDE.md pelo avesso —
-- a 0181 e a 0182 já estabeleceram o precedente de simplicidade deliberada e documentada, ver os
-- cabeçalhos das duas). Acrescentá-lo depois, se um caso real medir capital pulverizado, é
-- `alter type entidade_forma_de_controle add value` — aditivo, barato, e não migra dado nenhum
-- que já exista, porque nenhuma entidade usaria esse rótulo hoje.
--
-- Os três rótulos:
--   - `indefinido`   — o DEFAULT de TODA entidade, inclusive as que já existem no banco (o
--                       backfill desta migration). A ausência honesta: ninguém decidiu ainda.
--   - `controlada_por_entidade` — há controladora EMPRESA; é o mundo da 0181.
--   - `controle_comum` — grupo horizontal sob controle comum de pessoa(s); é o mundo da 0182.
--
-- A GUARDA DE COERÊNCIA é o coração desta fatia: o estado DECLARADO e os DADOS têm de concordar,
-- e a incoerência é RECUSADA na escrita, nunca tolerada em silêncio (regra 1 outra vez — uma
-- linha que afirma `controle_comum` sem nenhum controlador registrado estaria afirmando um fato
-- que ninguém mediu).
--   - `controlada_por_entidade` EXIGE `controladora_id` NÃO nulo.
--   - `controle_comum` EXIGE `controladora_id` NULO (se há controladora empresa, não é
--     horizontal) E pelo menos UM vínculo em `entidade_controlador`.
--   - `indefinido` não exige nada — é a ausência, e ausência não se cobra (mesma doutrina da
--     guarda de soma da 0182: não puxar afirmação de onde não há medição).
--
-- `check` VS TRIGGER, DECIDIDO PELO MESMO CRITÉRIO TÉCNICO DA 0182 (ver o item (4) dela): a
-- parte que compara `forma_de_controle` contra `controladora_id` é do MESMO registro (a mesma
-- linha de `entidade`) — um `check` de linha única enxerga as duas colunas sem problema, e é
-- isso que `entidade_forma_de_controle_coerente` (item 2 abaixo) faz. A parte que exige "pelo
-- menos um vínculo em `entidade_controlador`" olha OUTRA TABELA — nenhum `check` de tabela
-- enxerga linhas de uma tabela diferente — por isso ela é um TRIGGER
-- (`fn_trg_entidade_forma_de_controle_tem_vinculo`, item 3), no mesmo padrão da guarda de soma
-- da 0182 (`fn_trg_entidade_controlador_soma_maxima`).
--
-- LIMITAÇÃO DELIBERADA, documentada (mesmo espírito da 0181/0182): o trigger do item 3 dispara
-- só quando `forma_de_controle` MUDA (INSERT ou UPDATE OF forma_de_controle) — ele prova, NA
-- DECLARAÇÃO, que existe pelo menos um vínculo. Ele NÃO é uma restrição PERMANENTE que reage a
-- DELETE em `entidade_controlador`: apagar o último vínculo de uma entidade já declarada
-- `controle_comum` não reverte a declaração automaticamente. Isso é o mesmo tipo de escolha que
-- a 0182 fez ao não modelar temporalidade em `entidade_controlador` — vigiar toda alteração de
-- OUTRA tabela para manter uma declaração desta tabela coerente para sempre é um invariante mais
-- caro (trigger em `entidade_controlador` também) do que o que há hoje medido para justificar;
-- se um caso real marcar isso como risco, é decisão de uma sessão futura com o caso na mão.
--
-- NADA É INFERIDO AUTOMATICAMENTE (regra 1, e a instrução mais explícita desta fatia): esta
-- migration NÃO deriva `forma_de_controle` da presença de `controladora_id` nem de linhas em
-- `entidade_controlador` — nem no caminho de escrita, nem no backfill. Derivar transformaria
-- "ninguém decidiu" em "o sistema decidiu por você", que é o próprio defeito que esta fatia
-- existe para matar: um `controladora_id` preenchido por acidente de outra migration não pode
-- virar `controlada_por_entidade` sem um humano confirmar, e um `entidade_controlador` com uma
-- linha solta não pode virar `controle_comum` sem alguém decidir que aquilo FECHA o grupo.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2 do CLAUDE.md) — EXECUTADA, não descrita, em
-- `Supabase/test/entidade_forma_de_controle.test.sql`:
--
-- TODOS OS NÚMEROS ABAIXO FORAM REMEDIDOS EM 23/09/2026 contra o arquivo COMO ESTÁ COMMITADO,
-- depois da mesclagem com a main (0185/0186 da F2). Histórico do denominador, porque ele mudou
-- três vezes e cada mudança teve motivo: a primeira versão dizia "22" com o arquivo tendo 20; a
-- revisão independente achou um BURACO e os 2 asserts que o fecham levaram a 22; o backfill
-- corrigido (protocolo (c)) acrescentou 2, e o denominador real hoje é **24**.
--
-- (a) A GUARDA DE COERÊNCIA (o `check` de linha única): com o `check`
--     `entidade_forma_de_controle_coerente` comentado (e junto com ele o `comment on constraint`
--     dele — ver a ARMADILHA abaixo) e `teste_assert_0183` trocado temporariamente para não
--     abortar no primeiro assert e contar todos — **4 dos 24 asserts reprovaram**: "declarar
--     `controlada_por_entidade` SEM `controladora_id` é recusado", "nada foi gravado — a forma
--     continua indefinido", e os DOIS asserts novos do arranjo com controladora_id E vínculo.
--
--     ESSES DOIS SÃO A CORREÇÃO DE UM BURACO REAL, não cobertura decorativa. Antes deles, a
--     cláusula `controle_comum ⇒ controladora_id IS NULL` podia ser APAGADA do check com a suíte
--     inteira continuando verde: o único assert que exercitava esse par usava uma entidade com
--     controladora_id e NENHUM vínculo, e ali quem recusa é o TRIGGER. O arranjo que faltava é
--     perfeitamente real — uma entidade com as DUAS coisas (holding registrada pela 0181 E
--     sócios pessoa física registrados pela 0182) — e sem a cláusula ela poderia ser declarada
--     `controle_comum`: o trigger vê o vínculo e libera, e o banco passaria a afirmar "grupo
--     horizontal, não há controladora empresa" numa linha que TEM controladora empresa
--     preenchida. Ausência virando dado (regra 1) pelo caminho mais silencioso que existe.
--
-- (b) A GUARDA DO VÍNCULO (o trigger): com a criação do
--     `trigger trg_entidade_forma_de_controle_tem_vinculo` comentada (a função-guarda continua
--     existindo, mas nada a chama) e `teste_assert_0183` contando todos — **4 dos 24 asserts
--     reprovaram**, e eles NÃO são quatro provas independentes: 2 são DIRETOS ("declarar
--     `controle_comum` sem NENHUM vínculo é recusado" e "nada foi gravado") e 2 são CASCATA
--     ("exatamente um evento_auditoria gravado para v_ent_c" e "reatribuir com a MESMA forma
--     grava um segundo evento"), que reprovam porque a operação que deveria ter sido recusada
--     PASSOU e sujou a contagem de eventos do resto do bloco — não porque o trigger os proteja.
--
--     AS DUAS GUARDAS SE SOBREPÕEM, e isso é medido, não suposto: um mesmo arranjo pode ser
--     recusado por qualquer uma das duas dependendo de ter ou não vínculo registrado. Quem for
--     mexer numa delas NÃO pode concluir da outra que está coberto — foi exatamente assim que a
--     cláusula do check ficou sem dono até a revisão.
--
-- (c) O BACKFILL QUE RESPEITA A TRIAGEM (item 7): com o `not exists` da triagem removido de
--     `fn_pendencia_forma_de_controle_backfill` — **e junto o requisito de corpo da sonda que o
--     acusa**, senão a suíte para antes do teste — **1 dos 24 asserts reprovou**: "o backfill NÃO
--     reabre convite para entidade que a triagem humana já julgou ruído". Sem desligar o requisito,
--     quem reprova PRIMEIRO é a sonda (`instalacao.test.sql`, `backfill_forma_de_controle_respeita_
--     triagem` ausente) — são duas guardas independentes para o mesmo defeito, uma no teste e uma
--     no instrumento que confere produção. O outro assert do bloco ("abre para a entidade que
--     ninguém julgou") NÃO discrimina esta regressão, e não deveria: ele guarda a oposta, o filtro
--     excluindo DEMAIS.
--
--     A ARMADILHA DESTE PROTOCOLO, medida na primeira tentativa e registrada para a próxima
--     sessão: comentar só o `alter table ... add constraint` deixa o `comment on constraint`
--     órfão, a migration morre em `constraint ... does not exist`, o `run.sh` para ANTES do teste
--     e a contagem dá **0 reprovações**. Zero ali não era teste vazio — era teste NÃO EXECUTADO,
--     e os dois têm exatamente a mesma aparência (regra 7). Confira que a migration APLICOU antes
--     de acreditar em qualquer zero.
--

-- (c) OS QUE NÃO DISCRIMINAM CADA REGRESSÃO, nomeados pela mesma honestidade que a 0181/0182
--     usaram: os asserts de `fn_entidade_definir_forma_de_controle` grava evento_auditoria, de
--     reatribuição (mudar de forma é permitido, é o ESTADO ATUAL), de resolução de pendência, do
--     backfill (toda entidade pré-existente nasce `indefinido`), de entidade inexistente e da
--     ASSIMETRIA central (indefinido com controladora_id NULL × controle_comum com
--     controladora_id NULL são estados DIFERENTES e distinguíveis por consulta) são invariantes
--     GENUÍNOS, independentes tanto do `check` quanto do trigger — nenhum dos dois protocolos os
--     derruba, e não deveriam: eles protegem coisas diferentes.
--
-- O CUSTO DO BACKFILL, MEDIDO EM PRODUÇÃO ANTES DE APLICAR (regra 5): 365 entidades no banco,
-- das quais 347 já foram julgadas ruído de caso de teste pela triagem da 0179. O backfill
-- (item 7) REAPROVEITA essa triagem e abre pendência só para as outras — o que em produção, em
-- 23/09/2026, eram 18 (13 registros de `entidade` do caso AMO — que tem 8 empresas reais; a diferença
-- não foi investigada nesta rodada — e 5 dos casos AMOBELEZA*). Ver o item 7 para
-- por que a primeira versão, que abria as 365, estava errada.
--
-- **Pronto quando** (critério da fatia 1.7, roadmap): "um `controladora_id` vazio passa a ser
-- distinguível de um não preenchido" — esta migration entrega exatamente isso: a consulta
-- `select forma_de_controle from entidade where id = ...` responde a pergunta que
-- `controladora_id is null` sozinho nunca respondeu. Ela FECHA a fatia 1.7 (a 0182 abriu a
-- fatia 1.7a; esta é a 1.7b). Declarar a forma de controle real das 8 entidades do mandato AMO é
-- decisão de uma sessão seguinte, contra a sonda (migration escrita ≠ aplicada).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- (1) O ENUM E A COLUNA.
--
-- SEM `begin;`/`commit;` neste arquivo, de propósito — mesma razão exata da 0179 (ver o
-- cabeçalho dela, item 1): o passo (5) abaixo acrescenta um rótulo a `pendencia_tipo` (enum já
-- existente) e o USA no mesmo arquivo, e o Postgres proíbe usar um rótulo de enum recém-criado
-- por `ALTER TYPE ... ADD VALUE` dentro da MESMA transação em que ele nasceu ("unsafe use of new
-- value of enum type"). Cada statement de topo aplica em autocommit, e o rótulo novo já está
-- committed quando as funções abaixo o referenciam.
-- -----------------------------------------------------------------------------

create type entidade_forma_de_controle as enum (
  'indefinido',
  'controlada_por_entidade',
  'controle_comum'
);

comment on type entidade_forma_de_controle is
  '0183 (fatia 1.7b do plano F1): o que torna `entidade.controladora_id` NULO distinguível de '
  '"ninguém preencheu ainda". TRÊS rótulos, e um QUARTO foi CONSIDERADO E RECUSADO por falta de '
  'medição — ver o cabeçalho da migration 0183 para o motivo completo. `indefinido` é o DEFAULT '
  'de toda entidade (a ausência honesta); `controlada_por_entidade` é o mundo da 0181 '
  '(controladora_id preenchido); `controle_comum` é o mundo da 0182 (grupo horizontal, '
  'controladora_id NULO e pelo menos um vínculo em entidade_controlador). Só '
  '`fn_entidade_definir_forma_de_controle` escreve aqui — nunca inferência automática (regra 1 '
  'do CLAUDE.md).';

alter table entidade
  add column forma_de_controle entidade_forma_de_controle not null default 'indefinido';

comment on column entidade.forma_de_controle is
  '0183: o estado DECLARADO de controle desta entidade — `indefinido` (ninguém decidiu ainda, '
  'estado inicial de TODA entidade, inclusive as pré-existentes a esta migration), '
  '`controlada_por_entidade` (há controladora empresa — exige controladora_id não nulo) ou '
  '`controle_comum` (grupo horizontal sob controle comum — exige controladora_id nulo E pelo '
  'menos um vínculo em entidade_controlador, guardados por entidade_forma_de_controle_coerente e '
  'trg_entidade_forma_de_controle_tem_vinculo). É o que torna controladora_id NULO distinguível '
  'de um não preenchido (regra 7 do CLAUDE.md — critério de pronto da fatia 1.7). NADA é '
  'inferido: só fn_entidade_definir_forma_de_controle escreve aqui.';

-- `add column ... default` preenche toda LINHA JÁ EXISTENTE com o mesmo default, no mesmo
-- passo (Postgres 11+: default de coluna nova não reescreve a tabela quando é constante, mas o
-- VALOR lido para linha antiga é o default, idêntico ao de uma linha nova) — é o BACKFILL
-- HONESTO desta migration: toda entidade que já existia, inclusive as 8 do mandato AMO real,
-- vira `indefinido`. NÃO tenta adivinhar `controle_comum` a partir dos dados: as 8 entidades
-- reais ainda não têm vínculo NENHUM em `entidade_controlador` (a 0182 nasceu vazia de
-- propósito — ver o cabeçalho dela), e adivinhar aqui seria a regra 1 violada. Nenhum passo
-- adicional de backfill é necessário para esta coluna.

-- -----------------------------------------------------------------------------
-- (2) A GUARDA DE COERÊNCIA (linha única) — `check`, porque as duas colunas que ela compara
-- (`forma_de_controle`, `controladora_id`) estão na MESMA linha de `entidade`. `indefinido` não
-- exige nada; `controlada_por_entidade` exige `controladora_id` não nulo; `controle_comum` exige
-- `controladora_id` nulo (controle comum e controladora empresa são mutuamente exclusivos — se
-- há controladora, não é horizontal). É a MEDIÇÃO NÃO-VAZIA (a) do cabeçalho desta migration.
-- -----------------------------------------------------------------------------

alter table entidade add constraint entidade_forma_de_controle_coerente
  check (
    forma_de_controle = 'indefinido'
    or (forma_de_controle = 'controlada_por_entidade' and controladora_id is not null)
    or (forma_de_controle = 'controle_comum' and controladora_id is null)
  );

comment on constraint entidade_forma_de_controle_coerente on entidade is
  '0183: recusa a incoerência entre forma_de_controle e controladora_id mesmo por INSERT/UPDATE '
  'direto, sem passar pela função — `controlada_por_entidade` sem controladora_id, ou '
  '`controle_comum` COM controladora_id, afirmariam um estado que os dados contradizem. '
  '`indefinido` não exige nada — é a ausência (regra 1 do CLAUDE.md). É a MEDIÇÃO NÃO-VAZIA (a) '
  'da migration 0183 — ver o cabeçalho dela.';

-- -----------------------------------------------------------------------------
-- (3) A GUARDA DO VÍNCULO — TRIGGER, porque ela olha OUTRA tabela (`entidade_controlador`), que
-- nenhum `check` de `entidade` enxerga. Dispara quando `forma_de_controle` é gravada (INSERT ou
-- UPDATE OF forma_de_controle) como `controle_comum`, e recusa se não houver NENHUMA linha em
-- `entidade_controlador` para esta entidade — declarar controle comum sem controlador nenhum
-- registrado afirmaria um fato que ninguém mediu (regra 1). É a MEDIÇÃO NÃO-VAZIA (b) do
-- cabeçalho, mesmo padrão de `fn_trg_entidade_controlador_soma_maxima` (0182).
--
-- LIMITAÇÃO DELIBERADA (ver o cabeçalho desta migration): esta guarda prova o vínculo NA
-- DECLARAÇÃO — ela não é uma restrição permanente que reage a DELETE em `entidade_controlador`.
-- -----------------------------------------------------------------------------

create function public.fn_trg_entidade_forma_de_controle_tem_vinculo() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
  v_tem_vinculo boolean;
begin
  select exists(select 1 from entidade_controlador where entidade_id = NEW.id) into v_tem_vinculo;

  if not v_tem_vinculo then
    raise exception 'entidade "%" não pode ser declarada controle_comum sem NENHUM vínculo '
                     'registrado em entidade_controlador — registre os controladores primeiro '
                     '(fn_controlador_registrar/fn_entidade_definir_controlador, 0182)',
      coalesce(NEW.razao_social, NEW.id::text);
  end if;

  return NEW;
end;
$$;

comment on function public.fn_trg_entidade_forma_de_controle_tem_vinculo() IS
  '0183: a guarda do vínculo — recusa declarar `controle_comum` sem NENHUMA linha em '
  '`entidade_controlador` para a entidade. É a MEDIÇÃO NÃO-VAZIA (b) desta migration — sem o '
  'trigger abaixo chamando esta função, `controle_comum` seria gravado em silêncio mesmo sem '
  'nenhum controlador registrado. LIMITAÇÃO DELIBERADA: prova o vínculo na declaração, não reage '
  'a DELETE posterior em entidade_controlador (ver cabeçalho da migration 0183).';

create trigger trg_entidade_forma_de_controle_tem_vinculo
  after insert or update of forma_de_controle on entidade
  for each row
  when (NEW.forma_de_controle = 'controle_comum')
  execute function fn_trg_entidade_forma_de_controle_tem_vinculo();

-- -----------------------------------------------------------------------------
-- (4) O CAMINHO DE ESCRITA — mesma doutrina da 0179/0180/0181/0182: humano decide, nunca
-- inferência automática. Reatribuir (chamar de novo com forma diferente) é permitido — é o
-- ESTADO ATUAL, o histórico mora em evento_auditoria.
-- -----------------------------------------------------------------------------

create function public.fn_entidade_definir_forma_de_controle(p_entidade_id uuid,
                                                                p_forma entidade_forma_de_controle,
                                                                p_autor text)
RETURNS uuid
    LANGUAGE plpgsql
    AS $$
declare
  v_forma_anterior entidade_forma_de_controle;
  v_caso_id        uuid;
begin
  select forma_de_controle, caso_id into v_forma_anterior, v_caso_id
    from entidade where id = p_entidade_id;

  if v_caso_id is null then
    raise exception 'entidade % não encontrada', p_entidade_id;
  end if;

  -- As guardas (entidade_forma_de_controle_coerente, trg_entidade_forma_de_controle_tem_vinculo)
  -- recusam este UPDATE se p_forma for incoerente com controladora_id ou entidade_controlador —
  -- esta função NÃO duplica a checagem, ela confia na constraint/trigger para recusar e propagar
  -- a exceção, exatamente como fn_entidade_definir_participacao (0181) confia em
  -- entidade_nao_controla_a_si_mesma para o ciclo de um salto.
  update entidade set forma_de_controle = p_forma where id = p_entidade_id;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
  values (p_autor, 'entidade_forma_de_controle_definida', 'entidade:' || p_entidade_id,
          jsonb_build_object('forma_nova', p_forma, 'forma_anterior', v_forma_anterior));

  -- Resolve a pendência complementar (item 5) quando a forma deixa de ser `indefinido` — mesmo
  -- desenho de fn_entidade_definir_papel_no_grupo (0179). Reatribuir de volta para `indefinido`
  -- (caso raro — desfazer uma decisão) NÃO reabre a pendência automaticamente: reabrir pendência
  -- por UPDATE é decisão de produto que nenhuma migration anterior tomou (0179/0180/0181/0182
  -- também não reabrem as delas), e não há nada medido hoje que peça isso.
  if p_forma <> 'indefinido' then
    update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = p_autor
     where entidade_id = p_entidade_id
       and tipo = 'forma_de_controle_indefinida'
       and motivo = 'forma_de_controle_indefinida:' || p_entidade_id
       and estado <> 'resolvida';
  end if;

  return p_entidade_id;
end;
$$;

comment on function public.fn_entidade_definir_forma_de_controle(uuid, entidade_forma_de_controle, text) IS
  '0183: o ÚNICO caminho de escrita de entidade.forma_de_controle — chamado por um '
  'humano/analista (portal ou SQL direto; o portal não é escopo desta fatia). NÃO deriva a forma '
  'de controladora_id nem de entidade_controlador — a decisão vem de quem chama. As guardas '
  '(entidade_forma_de_controle_coerente, trg_entidade_forma_de_controle_tem_vinculo) recusam a '
  'gravação se for incoerente. Grava evento_auditoria (ator = p_autor, nunca ''sistema:...''), e '
  'resolve fn_pendencia_forma_de_controle_indefinida se estiver aberta, quando p_forma <> '
  '''indefinido''. Reatribuir é permitido — é o estado ATUAL, o histórico mora em '
  'evento_auditoria.';

grant execute on function public.fn_entidade_definir_forma_de_controle(uuid, entidade_forma_de_controle, text) to authenticated;

-- -----------------------------------------------------------------------------
-- (5) A PENDÊNCIA — o convite à decisão humana, mesmo desenho de
-- `fn_pendencia_papel_no_grupo_indefinido` (0179): idempotente por MOTIVO (uma por entidade),
-- nunca decide a forma — só marca a ausência. Chamada de dentro de `fn_upsert_entidade` (item 6)
-- para TODA entidade nova, incondicional, e pelo backfill (item 7) para as que já existiam.
-- -----------------------------------------------------------------------------

alter type pendencia_tipo add value if not exists 'forma_de_controle_indefinida';

create function public.fn_pendencia_forma_de_controle_indefinida(p_caso_id uuid, p_entidade_id uuid, p_nome text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
declare
  v_motivo text := 'forma_de_controle_indefinida:' || p_entidade_id;
  v_pend   uuid;
begin
  select id into v_pend from pendencia
   where caso_id = p_caso_id and motivo = v_motivo and estado <> 'resolvida'
   limit 1;
  if v_pend is not null then return v_pend; end if;

  insert into pendencia
    (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, entidade_id, motivo)
  values (
    p_caso_id, 'diagnostico', 'forma_de_controle_indefinida', 'complementar', true,
    format('A entidade "%s" ainda não tem forma de controle declarada (controlada por outra '
           || 'entidade / controle comum) — ninguém decidiu ainda, e o sistema não infere isso '
           || 'sozinho (nem de controladora_id, nem de entidade_controlador — regra 1 do '
           || 'CLAUDE.md). O EFEITO, hoje: nenhum, porque nenhum consumidor lê forma_de_controle '
           || 'ainda. Chame fn_entidade_definir_forma_de_controle para esta entidade quando a '
           || 'estrutura societária for conhecida.',
           p_nome),
    p_entidade_id, v_motivo)
  returning id into v_pend;

  return v_pend;
end;
$$;

comment on function public.fn_pendencia_forma_de_controle_indefinida(p_caso_id uuid, p_entidade_id uuid, p_nome text) IS '0183: pendência complementar (não bloqueia nada) para entidade sem forma de controle declarada. Idempotente por entidade_id (motivo). Nunca decide a forma — só marca a ausência, regra 1 do CLAUDE.md.';

-- -----------------------------------------------------------------------------
-- fn_upsert_entidade — reemitida INTEIRA, verbatim do corpo vigente (0179), com só uma linha
-- nova antes do `return v_id` final (nunca por âncora de texto em corpo de função — mesmo
-- cuidado da 0179 sobre a 0178). A assinatura não muda, então `create or replace` basta.
--
-- INCONDICIONAL, e de propósito: toda entidade que nasce por este `insert` final nasce com
-- forma_de_controle 'indefinido' pelo DEFAULT da coluna (item 1) — a chamada abaixo só marca a
-- pendência complementar, no mesmo espírito de papel_no_grupo_indefinido (0179): é honesto uma
-- entidade estar, simultaneamente, "sem papel no grupo" E "sem forma de controle declarada" —
-- são sinais diferentes.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_upsert_entidade(p_caso_id uuid, p_nome text, p_cnpj text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
declare
  v_id         uuid;
  v_n          int;
  v_candidatos text;
  v_nomes      text[];
  v_cnpj       text := fn_cnpj_canonico(p_cnpj);
  v_nome_atual text;
  v_e_balcao   boolean;
  v_mesmo_nome_do_balcao boolean;
begin
  -- 0153: no empate, não escolhe. (E o requisito de sonda `entidade_ambigua_nao_decide`
  -- tem o literal "0153" como MARCADOR DE CORPO — tirar esta linha derruba a sonda
  -- sem mudar comportamento nenhum. Achado ao rodar a suíte desta fatia.)
  if p_nome is null or length(trim(p_nome)) = 0 then return null; end if;

  -- (0) 0169: CNPJ IGUAL É A MESMA EMPRESA, e ele não pergunta o nome. É esta
  -- regra que funde as variantes truncadas em QUALQUER ordem de chegada —
  -- a 0168 só conseguia quando a ordem ajudava.
  if v_cnpj is not null then
    -- `order by` sem efeito prático desde a 0169: o índice único
    -- `entidade_caso_cnpj_unico (caso_id, cnpj)` garante NO MÁXIMO uma linha.
    -- Fica como documentação da invariante, não como desempate de verdade.
    select e.id, e.razao_social into v_id, v_nome_atual
    from entidade e
    where e.caso_id = p_caso_id and fn_cnpj_canonico(e.cnpj) = v_cnpj
    order by length(e.razao_social) desc, e.razao_social
    limit 1;

    if v_id is not null then
      v_e_balcao := fn_entidade_e_balcao_ambiguo(p_caso_id, v_id);

      -- 0177 (ALTO): o nome que chega pode ser o PRÓPRIO nome do balcão —
      -- um SEGUNDO documento do MESMO balcão, chegando pela classificação,
      -- com o CNPJ que ele já aprendeu. A 0176 tratava QUALQUER chegada
      -- contra um balcão como colisão externa, mesmo quando é o balcão
      -- recebendo mais um documento seu: a pendência abria dizendo que o
      -- nome "chegou... sem ser, ela própria, um balcão ambíguo" e que "o
      -- sistema NÃO... atribuiu este documento/entidade a ele" — as DUAS
      -- afirmações falsas, porque o nome que chegou É o do balcão e o
      -- documento SIM termina atribuído a ele pelo ramo (1) de casamento
      -- exato por nome, alguns passos abaixo. MEDIDO nesta sessão: uma
      -- pendência de colisão nascia (0→1) mesmo quando o documento novo era
      -- só mais um do MESMO balcão.
      v_mesmo_nome_do_balcao := v_e_balcao
        and fn_entidade_canonica(v_nome_atual) is not distinct from fn_entidade_canonica(trim(p_nome));

      -- MEDIDO (0176): um documento novo de OUTRA empresa (mesmo CNPJ de
      -- rodapé de contador) virava absorvido pelo balcão sem nunca ganhar
      -- linha própria — entidades no caso ficavam em 3 em vez de virarem 4.
      -- Trata o CNPJ como se nunca tivesse chegado (`v_cnpj := null`) para o
      -- resto desta chamada: sem isso, o `insert` do fim desta função
      -- tentaria gravar este MESMO CNPJ numa entidade nova e violaria
      -- `entidade_caso_cnpj_unico` — e, pior, atribuiria à empresa nova um
      -- CNPJ que pode não ser dela.
      if v_e_balcao and not v_mesmo_nome_do_balcao then
        perform fn_pendencia_cnpj_colide_balcao(p_caso_id, v_id, v_cnpj, trim(p_nome), null);
        v_id := null;
        v_cnpj := null;
      else
        -- O EVENTO DE CASAMENTO fica na forma CANÔNICA: ele existe para registrar
        -- que o CNPJ respondeu um nome MATERIALMENTE diferente do gravado, e
        -- diferença só de sufixo/pontuação não é isso. Quando é o PRÓPRIO
        -- balcão (v_mesmo_nome_do_balcao), esta condição já é falsa por
        -- construção — nenhum evento de "casamento" nasce, porque não houve
        -- casamento: é o mesmo nome de sempre.
        if fn_entidade_canonica(v_nome_atual) is distinct from fn_entidade_canonica(trim(p_nome)) then
          insert into evento_auditoria (ator, acao, entidade_ref, depois)
          values ('sistema:entidade', 'entidade_cnpj_casou', 'entidade:' || v_id,
                  jsonb_build_object('caso_id', p_caso_id, 'nome_procurado', trim(p_nome),
                                     'nome_mantido_antes_do_renomeio', v_nome_atual,
                                     'cnpj', v_cnpj,
                                     'pode_renomear', fn_pode_renomear_por_cnpj(v_nome_atual, trim(p_nome)),
                                     'porque', 'o CNPJ é o mesmo — o nome não foi consultado'));
        end if;

        -- 0173: O RENOMEIO VIROU FUNÇÃO PRÓPRIA, e os DOIS caminhos a chamam.
        -- Antes ele morava aqui dentro, e só este caminho (a classificação) o
        -- executava — o diagnóstico, que é o único que roda para TODO documento,
        -- gravava o CNPJ e ia embora sem renomear. Medido: identidade fiscal em
        -- 100% do lote e renomeio em ~50%.
        perform fn_entidade_talvez_renomear(p_caso_id, v_id, trim(p_nome), v_cnpj);

        return v_id;
      end if;
    end if;
  end if;

  -- (1) exato pela forma canônica — não há o que desempatar.
  select c.entidade_id into v_id
  from fn_entidades_candidatas_cnpj(p_caso_id, p_nome, p_cnpj) c
  where c.exata
  order by c.razao_social
  limit 1;
  if v_id is not null then
    -- 0174: usa o RETORNO, não `perform`. Sem isto, quando `fn_entidade_aprender_cnpj`
    -- funde esta entidade numa OUTRA que já tinha o mesmo CNPJ (a corrida entre
    -- o ramo (0) acima e este ramo, ou a mesma situação chegando pela porta do
    -- diagnóstico — ver o cabeçalho da função), `v_id` ficaria apontando para
    -- uma linha DELETADA, e o `insert into documento` em `fn_registrar_documento`
    -- quebraria a FK `documento.entidade_id → entidade.id`.
    v_id := fn_entidade_aprender_cnpj(v_id, v_cnpj);
    return v_id;
  end if;

  -- (2)/(3) quantos APROXIMADOS existem?
  select count(*), string_agg(c.razao_social, ' × ' order by c.razao_social),
         array_agg(c.razao_social)
    into v_n, v_candidatos, v_nomes
  from fn_entidades_candidatas_cnpj(p_caso_id, p_nome, p_cnpj) c;

  -- APRENDER SÓ NO CASAMENTO EXATO, e este `return` SEM `aprender` é a
  -- correção mais importante que a revisão desta fatia trouxe. Este ramo é o
  -- casamento FROUXO (subsequência de prefixos) — é ele que faz "Metalúrgica"
  -- ser absorvido por "VERTENTES METALÚRGICA LTDA.". Deixá-lo GRAVAR o CNPJ
  -- transformaria um palpite de nome em identidade fiscal permanente:
  -- "Canastra" com o CNPJ do GRUPO CANASTRA (a holding, impressa no
  -- consolidado) seria absorvido pela subsidiária e escreveria nela o CNPJ da
  -- holding — e daí em diante TODO documento da holding cairia na subsidiária
  -- pelo ramo (0), sem olhar nome. A própria 0168 já diz que o nome que CHEGA é
  -- o que pode estar contaminado; o CNPJ do mesmo documento não pode ser
  -- promovido a identidade por um casamento que o nome só aproximou.
  if v_n = 1 then
    select c.entidade_id into v_id
    from fn_entidades_candidatas_cnpj(p_caso_id, p_nome, p_cnpj) c limit 1;
    return v_id;
  end if;

  -- (3b) 0168: dois ou mais candidatos que casam ENTRE SI não são ambiguidade.
  if v_n > 1 and fn_entidades_sao_um_grupo(v_nomes || trim(p_nome)) then
    select c.entidade_id into v_id
    from fn_entidades_candidatas_cnpj(p_caso_id, p_nome, p_cnpj) c
    order by length(c.razao_social) desc, c.razao_social
    limit 1;

    insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:entidade', 'entidade_alias_fundido', 'entidade:' || v_id,
            jsonb_build_object('caso_id', p_caso_id, 'nome_procurado', trim(p_nome),
                               'candidatos', v_candidatos, 'quantos', v_n,
                               'porque', 'os candidatos casam todos entre si — é um nome só, '
                                      || 'truncado de jeitos diferentes pela fonte'));
    -- Sem `aprender` pelo mesmo motivo do ramo acima, e aqui é PIOR: o nome que
    -- chega é justamente o truncado, o que pode trazer o endereço colado.
    return v_id;
  end if;

  insert into entidade (caso_id, razao_social, cnpj) values (p_caso_id, trim(p_nome), v_cnpj)
    returning id into v_id;

  -- NASCER COM CNPJ MERECE O MESMO RASTRO QUE APRENDER DEPOIS. É uma afirmação
  -- de identidade tirada de UM documento, que nunca mais é revisitada e que
  -- passa a mandar sobre todo nome — o mínimo honesto é ela aparecer no log.
  if v_cnpj is not null then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:entidade', 'entidade_cnpj_aprendido', 'entidade:' || v_id,
            jsonb_build_object('cnpj', v_cnpj, 'como', 'nasceu com ele'));
  end if;

  if v_n > 1 then
    -- A AMBIGUIDADE É REGISTRADA AQUI e virada em pendência por quem tem o
    -- documento na mão. Esta função não conhece documento.
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:entidade', 'entidade_ambigua', 'entidade:' || v_id,
            jsonb_build_object('caso_id', p_caso_id, 'nome_procurado', trim(p_nome),
                               'candidatos', v_candidatos, 'quantos', v_n,
                               -- O CNPJ VAI JUNTO, e a revisão achou ele faltando:
                               -- `fn_pendencia_entidade_ambigua` (0153) monta a descrição
                               -- a partir deste payload, e o analista lia "casa com mais de
                               -- uma empresa: A × B" sem o único número que decide — a
                               -- regra 1 pelo avesso (a nota existe e cala o dado).
                               'cnpj', v_cnpj));
  end if;

  -- 0178: NEM CNPJ NEM CANDIDATO NENHUM CASOU, e o nome tem cara de
  -- título/coluna/aba/arquivo — a CONJUNÇÃO que separa isso do balcão
  -- ambíguo real (que também chega sem CNPJ por este mesmo `insert`, mas com
  -- nome vindo do CONTEÚDO do documento, não de um título). Não recusa o
  -- `insert` (o documento não pode ficar sem entidade — perderia
  -- proveniência) e não funde com nada — só marca para revisão humana.
  -- MEDIDO (`Supabase/test/entidade_titulo_suspeito.test.sql`): os 4 nomes
  -- reais do AMO teste 00 (Empresas, Vencidos, Status Extratos, Controle
  -- Extratos Ofx) batem aqui; um nome real de empresa do mesmo mandato,
  -- AMOBELEZA COMERCIO DIGITAL E OFFLINE LTDA (com CNPJ), não passa por este
  -- `if` porque `v_cnpj` não é nulo — nem chega a ser avaliado contra o léxico.
  if v_cnpj is null and fn_entidade_nome_parece_titulo_ou_arquivo(trim(p_nome)) then
    perform fn_pendencia_entidade_nome_suspeito(p_caso_id, v_id, trim(p_nome));
  end if;

  -- 0179: TODA entidade nasce aqui com papel_no_grupo NULL por construção (a
  -- coluna não é passada no insert acima) — marca a ausência, incondicional,
  -- porque não existe sinal automático para decidir o papel (fatia 1.3;
  -- roadmap, seção 12.1: sem participacao/hierarquia modelada). Vale tanto
  -- para a entidade real quanto para a suspeita de título/arquivo logo acima
  -- e para o balcão ambíguo (0153/0162, 0175-0177) — são sinais diferentes, e
  -- é honesto os dois estarem abertos ao mesmo tempo.
  perform fn_pendencia_papel_no_grupo_indefinido(p_caso_id, v_id, trim(p_nome));

  -- 0183: TODA entidade nasce aqui com forma_de_controle 'indefinido' pelo DEFAULT da coluna
  -- (item 1 desta migration) — marca a ausência, incondicional, mesmo espírito da chamada acima
  -- (0179): é honesto uma entidade estar, ao mesmo tempo, sem papel no grupo E sem forma de
  -- controle declarada — são sinais diferentes.
  perform fn_pendencia_forma_de_controle_indefinida(p_caso_id, v_id, trim(p_nome));

  return v_id;
end;
$$;

COMMENT ON FUNCTION public.fn_upsert_entidade(p_caso_id uuid, p_nome text, p_cnpj text) IS 'Acha ou cria a entidade do caso (0030), sem ESCOLHER no empate (0153), com o nome truncado fundido no mais completo (0168), com o CNPJ como identidade (0169) e adotando a variante mais completa ao fundir por CNPJ (0171/0173 — a decisão mora em fn_entidade_talvez_renomear, chamada dos dois caminhos). 0174: o ramo (1) usa o RETORNO de fn_entidade_aprender_cnpj. 0176: o ramo (0) não devolve mais um balcão ambíguo (0162/0175) direto para OUTRA empresa — trata o CNPJ como ausente e registra a colisão (fn_pendencia_cnpj_colide_balcao). 0177: essa colisão só é registrada quando quem chegou NÃO é, ela própria, o mesmo balcão — um segundo documento do PRÓPRIO balcão (mesmo nome, mesmo CNPJ) não abre pendência falsa; segue pelo caminho normal. 0178: uma entidade NOVA (nenhum candidato casou), sem CNPJ, com nome que bate fn_entidade_nome_parece_titulo_ou_arquivo, ainda é criada (documento não perde dona) mas ganha pendência entidade_incorreta/entidade_nome_suspeito para revisão humana — nunca fundida nem apagada. 0179: toda entidade nova (real, suspeita ou balcão) ganha também a pendência papel_no_grupo_indefinido, incondicional — não há sinal automático para classificar o papel no grupo. 0183: toda entidade nova ganha também a pendência forma_de_controle_indefinida, incondicional — não há sinal automático para declarar a forma de controle.';

-- -----------------------------------------------------------------------------
-- (7) O BACKFILL — entidades que JÁ EXISTEM neste banco (o `add column ... default` do item 1
-- já deu a TODAS `forma_de_controle = 'indefinido'`; este passo é só a PENDÊNCIA). Idempotente
-- por motivo.
--
-- ELE NÃO ALCANÇA O BANCO INTEIRO, e a primeira versão alcançava. MEDIDO em produção em
-- 23/09/2026, antes de aplicar (somente leitura, pela API de gerenciamento): **365 entidades**
-- em 52 casos (`count(distinct caso_id) from entidade`, 23/09; o ESTADO.md registrou "70 casos"
-- para as mesmas 365 em 18/09, por outra consulta — não reconciliado, e o 365 é o que importa
-- aqui). Um `where forma_de_controle = 'indefinido'` logo depois do `add column default`
-- pega todas — e é EXATAMENTE o desenho do backfill da 0179, que abriu 365 pendências das quais
-- **347 tiveram de ser resolvidas em lote** como ruído de caso de teste morto
-- (`.claude/memory/aplicar-migration-em-producao-pela-api.md`, que já dizia: "medir quantas
-- linhas o where alcança em PRODUÇÃO antes de escrever, não depois de aplicar").
--
-- A primeira versão desta migration NÃO corrigiu isso: ela DOCUMENTOU o custo ("quem aplicar
-- vai precisar repetir a triagem"). Documentar um defeito conhecido em vez de consertá-lo é
-- tratar o resultado em vez da origem. A origem é o backfill ignorar uma decisão humana que JÁ
-- EXISTE sobre as MESMAS entidades: aquelas 347 foram julgadas ruído de caso de teste, com
-- `resolvida_por = 'sessao-claude:ruido-de-caso-de-teste'` na pendência de papel da 0179. Esse
-- marcador é o único registro legível por máquina de "esta entidade é ruído" que o banco tem
-- (não há flag de caso de teste em `caso`), e reaproveitá-lo é a diferença entre abrir 365
-- convites a decidir e abrir 18.
--
-- NUM BANCO NOVO (CI, local) não existe triagem nenhuma, então a exclusão não exclui nada e o
-- backfill alcança todas as entidades — que é o comportamento certo: ninguém julgou nenhuma delas.
--
-- `p_caso_id` escopa o backfill a um caso (NULL = o banco inteiro, que é o que a migration usa).
-- Ele existe para o TESTE poder exercitar a exclusão sem abrir pendência nas entidades de
-- fixture de todos os outros casos do banco de teste.
-- -----------------------------------------------------------------------------

create function public.fn_pendencia_forma_de_controle_backfill(p_caso_id uuid DEFAULT NULL)
RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
  r   record;
  v_n integer := 0;
begin
  for r in
    select e.id, e.caso_id, e.razao_social
      from entidade e
     where e.forma_de_controle = 'indefinido'
       and (p_caso_id is null or e.caso_id = p_caso_id)
       -- a triagem humana que já existe: entidade julgada ruído de caso de teste não recebe
       -- um segundo convite a decidir sobre ela
       and not exists (
         select 1 from pendencia p
          where p.caso_id = e.caso_id
            and p.motivo = 'papel_no_grupo_indefinido:' || e.id
            and p.estado = 'resolvida'
            and p.resolvida_por = 'sessao-claude:ruido-de-caso-de-teste')
  loop
    perform fn_pendencia_forma_de_controle_indefinida(r.caso_id, r.id, r.razao_social);
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;

comment on function public.fn_pendencia_forma_de_controle_backfill(uuid) IS
  '0183: abre a pendência forma_de_controle_indefinida para as entidades que já existiam quando a '
  'coluna nasceu, EXCETO as que a triagem humana da 0179 já julgou ruído de caso de teste '
  '(pendência de papel resolvida com resolvida_por = ''sessao-claude:ruido-de-caso-de-teste''). '
  'Medido em produção antes de aplicar: 365 entidades, 347 triadas — sem a exclusão o backfill '
  'repetiria o ruído da 0179. Devolve quantas entidades visitou. p_caso_id NULL = banco inteiro.';

select fn_pendencia_forma_de_controle_backfill();

-- -----------------------------------------------------------------------------
-- O CATÁLOGO DA SONDA.
-- -----------------------------------------------------------------------------

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('entidade_forma_de_controle_tipo_existe', '0183', 'coluna', 'entidade.forma_de_controle',
   null, null,
   'A coluna nova da fatia 1.7b: o que torna controladora_id NULO distinguível de um não '
   'preenchido. Ausente (banco anterior à 0183), o vazio de controladora_id continua ambíguo '
   'entre "o grupo é horizontal, apuramos" e "ninguém cadastrou" (regra 7 do CLAUDE.md).',
   'importante', 770)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

-- A GUARDA DE COERÊNCIA (`entidade_forma_de_controle_coerente`, um `check`) não ganha requisito
-- próprio no catálogo — mesmo precedente da 0181 (`entidade_nao_controla_a_si_mesma`,
-- `entidade_percentual_valido`) e da 0182 (`entidade_controlador_percentual_valido`): nenhuma
-- delas catalogou seus `check`s de linha única, porque `tipo = 'comportamento'` da sonda conta
-- LINHAS de uma TABELA (é o mecanismo do n8n, "a tabela que aquele nó grava tem linha" — ver o
-- comentário de `instalacao_requisito.tipo`), não a existência de uma constraint. O requisito
-- `entidade_forma_de_controle_tipo_existe` (coluna, acima) já prova que esta migration foi
-- aplicada — o `check` nasce ATOMICAMENTE com a coluna, no mesmo `alter table`, e não há como o
-- Postgres aplicar um sem o outro.

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('fn_trg_entidade_forma_de_controle_tem_vinculo_existe', '0183', 'funcao',
   'fn_trg_entidade_forma_de_controle_tem_vinculo',
   null, null,
   'A guarda do vínculo (trigger) — recusa `controle_comum` sem NENHUM vínculo em '
   'entidade_controlador. Ausente, controle_comum seria gravado em silêncio sem controlador '
   'nenhum registrado — é a MEDIÇÃO NÃO-VAZIA (b) desta migration.',
   'importante', 772)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('fn_entidade_definir_forma_de_controle_existe', '0183', 'funcao',
   'fn_entidade_definir_forma_de_controle',
   null, null,
   'O único caminho de escrita de entidade.forma_de_controle. Sem ele, a coluna nova continua '
   'com o mesmo vazio de antes, só com tipo mais forte.',
   'importante', 773)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('fn_pendencia_forma_de_controle_indefinida_existe', '0183', 'funcao',
   'fn_pendencia_forma_de_controle_indefinida',
   null, null,
   'A função que marca a ausência de forma de controle para revisão humana, sem decidir nada — '
   'regra 1 do CLAUDE.md. Ausente, a chamada nova em fn_upsert_entidade não teria como deixar '
   'rastro.',
   'importante', 774)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('upsert_entidade_marca_forma_de_controle_indefinida', '0183', 'corpo', 'fn_upsert_entidade',
   'fn_pendencia_forma_de_controle_indefinida(p_caso_id, v_id', null,
   'Prova a CHAMADA dentro de fn_upsert_entidade, não só a existência da função (mesmo cuidado '
   'da 0179 com upsert_entidade_marca_papel_indefinido): sem esta linha no corpo publicado, uma '
   'reemissão futura da função pode perder a marca mesmo com '
   'fn_pendencia_forma_de_controle_indefinida continuando presente e testada, e a sonda ficaria '
   'muda sobre isso.',
   'importante', 775)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('backfill_forma_de_controle_respeita_triagem', '0183', 'corpo',
   'fn_pendencia_forma_de_controle_backfill',
   'p.resolvida_por = ''sessao-claude:ruido-de-caso-de-teste''', null,
   'Prova a EXCLUSÃO dentro do backfill, não só a existência da função. O marcador é a COMPARAÇÃO '
   'inteira, não a string solta: a string sozinha sobreviveria numa reemissão que a guardasse num '
   'comentário e perdesse o filtro (sonda_marcador_e_codigo.test.sql recusou a primeira versão '
   'deste requisito exatamente por isso). Sem o filtro, o backfill volta a abrir uma pendência por '
   'entidade do banco inteiro. '
   'Medido em produção em 23/09/2026: 365 entidades, 347 já triadas como ruído — com a exclusão '
   'o backfill alcança 18, sem ela alcança 365.',
   'importante', 776)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

-- -----------------------------------------------------------------------------
-- (9) O MARCADOR DE COBERTURA NÃO PODE REGREDIR — e em produção ele REGREDIU, causado pela 0182.
--
-- O DEFEITO, medido em 23/09/2026: 39 migrations (0147 em diante) terminam com
-- `update instalacao_cobertura set ate_migration = 'NNNN'` INCONDICIONAL. O desenho presume
-- aplicação EM ORDEM, e duas sessões trabalhando em paralelo quebraram essa premissa: a F2 aplicou
-- 0186–0188 em produção em 22/09, e a 0182 foi aplicada DEPOIS, em 23/09 — e escreveu '0182' por
-- cima de '0188'. A sonda passou a responder "cobertura até a 0182" com a 0186–0188 no ar. Sem
-- erro nenhum: a linha foi atualizada com sucesso para um valor menor.
--
-- A ORIGEM NÃO ESTÁ NAS 39 MIGRATIONS, ESTÁ NA TABELA: ela aceita que o marcador diminua.
-- Corrigir as 39 seria tratar o sintoma e depender de toda migration futura lembrar. O gatilho
-- abaixo impede a regressão em UM lugar, para toda migration que vier — inclusive esta, cuja
-- própria linha `set ate_migration = '0183'` logo abaixo, aplicada depois da 0188, rebaixaria o
-- marcador do mesmo jeito.
--
-- E O REPARO DO QUE JÁ REGREDIU: `greatest` não recupera informação perdida — em produção o valor
-- atual já é '0182'. O marcador é recalculado a partir de `instalacao_requisito`, que é escrito
-- pelas próprias migrations e é a verdade do que está instalado (a 0188 catalogou os requisitos
-- dela; o maior `migration` do catálogo é o que de fato rodou por último em número). Num banco
-- novo, aplicado em ordem, o reparo é inócuo: o maior do catálogo é a própria 0183.
-- -----------------------------------------------------------------------------

create function public.fn_trg_instalacao_cobertura_nao_regride() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  -- `ate_migration` é texto de 4 dígitos zero-padded, então a ordem lexicográfica coincide com a
  -- numérica ('0183' < '0188'). Quando quem chega é MAIS ANTIGO que o que está gravado, a linha
  -- inteira fica como estava: só o marcador não bastaria, porque a `observacao` ao lado passaria a
  -- descrever outra migration e a linha diria "cobertura até a 0188" com o texto da 0183.
  if NEW.ate_migration < OLD.ate_migration then
    -- Sem aviso, o `UPDATE 1` desta linha pareceria ter funcionado — um rollback deliberado do
    -- marcador ficaria indistinguível de um que pegou (achado da revisão de 23/09/2026).
    raise notice 'instalacao_cobertura: ate_migration % ignorado — o marcador já está em % e não regride',
      NEW.ate_migration, OLD.ate_migration;
    NEW.ate_migration := greatest(OLD.ate_migration, NEW.ate_migration);
    NEW.observacao    := OLD.observacao;
    NEW.revisado_em   := OLD.revisado_em;
  end if;
  return NEW;
end;
$$;

comment on function public.fn_trg_instalacao_cobertura_nao_regride() IS
  '0183: o marcador de cobertura da sonda nunca regride. Motivo medido: a 0182, aplicada em '
  'produção DEPOIS da 0188 (sessões paralelas), escreveu ate_migration = ''0182'' por cima de '
  '''0188'' — 39 migrations terminam com esse update incondicional, e a tabela aceitava o valor '
  'menor sem erro. Corrigido na tabela, não nas migrations.';

create trigger trg_instalacao_cobertura_nao_regride
  before update of ate_migration on instalacao_cobertura
  for each row execute function fn_trg_instalacao_cobertura_nao_regride();

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('cobertura_nao_regride', '0183', 'corpo', 'fn_trg_instalacao_cobertura_nao_regride',
   'greatest(OLD.ate_migration, NEW.ate_migration)', null,
   'O marcador de cobertura da própria sonda não pode descer. Sem isto, uma migration aplicada '
   'fora de ordem (o que já aconteceu: a 0182 depois da 0188, em 23/09/2026) rebaixa ate_migration '
   'e a sonda passa a subnotificar o que está instalado — sem erro nenhum.',
   'importante', 777)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

-- -----------------------------------------------------------------------------
-- (10) A FUSÃO DE ENTIDADES APAGAVA O CONTROLE DECLARADO — achado CRÍTICO do /revisar de 24/09/2026.
--
-- O DEFEITO: `fn_fundir_entidade` (0153, a única definição) move documento, checklist, pendência e
-- reconciliação da entidade absorvida para a sobrevivente e depois faz `delete from entidade`. Ela
-- nasceu antes da 0182 e não conhece `entidade_controlador`, cuja FK é `on delete cascade`: o
-- vínculo que um humano declarou some junto com a linha, e `fn_grupo_por_controle_comum` passa a
-- devolver um grupo menor sem erro nenhum. REPRODUZIDO nesta sessão, antes da correção (banco de
-- teste, transação desfeita): A com um vínculo de 60%, B sem vínculo, `fn_fundir_entidade(c, A, B)`
-- → **1 vínculo antes, 0 depois**, e **2 pendências abertas** (forma e papel) com motivo apontando
-- para a entidade que não existe mais — definir a forma de B resolve só `...:<B>`, então a de A
-- fica aberta para sempre. A fusão roda sozinha: `fn_entidade_aprender_cnpj` (0174/0177) a chama
-- quando o CNPJ lido num documento já pertence a outra entidade do caso.
--
-- A CORREÇÃO, e o que ela deliberadamente NÃO decide:
--   - B (sobrevivente) SEM vínculo: os vínculos de A passam para B. É a mesma empresa — o CNPJ é a
--     identidade (0169) — e A cabia no teto de 100%, então B cabe.
--   - B JÁ COM vínculo: os de B ficam, os de A NÃO são somados. Duas declarações diferentes sobre a
--     mesma empresa é conflito, e escolher entre elas é juízo, não medição (regra 1). Os de A vão
--     inteiros para o `evento_auditoria` da fusão (`vinculos_descartados`), com controlador e
--     percentual — nada some sem rastro.
--   - A `forma_de_controle` de A NÃO é herdada: herdar seria inferir a forma de B (o que só
--     `fn_entidade_definir_forma_de_controle`, humano, faz). Ela vai para o evento, e a pendência
--     de forma de B — que é de B — continua sendo o convite a decidir.
--   - As pendências de forma e de papel de A são resolvidas (`resolvida_por = p_por`): a pergunta
--     era sobre uma entidade que deixou de existir. É o mesmo desenho que a 0153 já tinha para
--     `entidade_ambigua:<A>`. O papel (0179) tinha o mesmo defeito antes desta fatia; entra aqui
--     porque é a mesma linha.
--
-- O CORPO É O DA 0153 INTEIRO, mais os três blocos marcados `0183` (regra: nunca corrigir função
-- por replace de texto). Quem aplicar em produção: compare o corpo de produção com o da 0153 antes
-- (`.claude/memory/sessoes-paralelas-aplicam-fora-de-ordem.md`) — a diferença tem de ser só esta.
-- -----------------------------------------------------------------------------

create or replace function fn_fundir_entidade(
  p_caso_id uuid, p_de_id uuid, p_para_id uuid, p_por text default 'sistema:fusao'
)
returns jsonb
language plpgsql
as $$
declare
  v_de    text;
  v_para  text;
  v_docs  int;
  -- 0183
  v_forma_de         entidade_forma_de_controle;
  v_vinculos_de      jsonb;
  v_vinculos_movidos int := 0;
  v_descartados      jsonb := '[]'::jsonb;
begin
  if p_de_id = p_para_id then
    raise exception 'fundir uma entidade nela mesma não faz sentido (%)', p_de_id;
  end if;

  select razao_social into v_de   from entidade where id = p_de_id   and caso_id = p_caso_id;
  select razao_social into v_para from entidade where id = p_para_id and caso_id = p_caso_id;
  if v_de is null or v_para is null then
    raise exception 'entidade não encontrada neste mandato (de=%, para=%)', p_de_id, p_para_id;
  end if;

  update documento set entidade_id = p_para_id
   where caso_id = p_caso_id and entidade_id = p_de_id;
  get diagnostics v_docs = row_count;

  -- Tudo o que aponta para a entidade acompanha o documento. `checklist_item_status`
  -- e `pendencia` guardam entidade_id por conta própria, e deixá-los para trás
  -- faria o Portão 1 continuar cobrando de uma empresa que não existe mais.
  update checklist_item_status set entidade_id = p_para_id
   where caso_id = p_caso_id and entidade_id = p_de_id;
  update pendencia set entidade_id = p_para_id
   where caso_id = p_caso_id and entidade_id = p_de_id;
  update reconciliacao set entidade_id = p_para_id
   where caso_id = p_caso_id and entidade_id = p_de_id;

  -- 0183: o controle declarado de A. Sem isto, o `on delete cascade` de entidade_controlador o
  -- apagava junto com a linha (ver o item (10) da migration 0183).
  select forma_de_controle into v_forma_de from entidade where id = p_de_id;
  select coalesce(jsonb_agg(jsonb_build_object('controlador_id', ec.controlador_id,
                                               'controlador', k.nome,
                                               'percentual', ec.percentual)
                            order by k.nome), '[]'::jsonb)
    into v_vinculos_de
    from entidade_controlador ec join controlador k on k.id = ec.controlador_id
   where ec.entidade_id = p_de_id;

  if not exists (select 1 from entidade_controlador where entidade_id = p_para_id) then
    update entidade_controlador set entidade_id = p_para_id where entidade_id = p_de_id;
    get diagnostics v_vinculos_movidos = row_count;
  else
    v_descartados := v_vinculos_de;
  end if;

  -- A pendência de ambiguidade da entidade fundida está respondida.
  update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = p_por
   where caso_id = p_caso_id and motivo = 'entidade_ambigua:' || p_de_id and estado <> 'resolvida';

  -- 0183: e as de forma e de papel de A também — a pergunta era sobre uma entidade que deixa de
  -- existir; a de B é de B.
  update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = p_por
   where caso_id = p_caso_id
     and motivo in ('forma_de_controle_indefinida:' || p_de_id, 'papel_no_grupo_indefinido:' || p_de_id)
     and estado <> 'resolvida';

  delete from entidade where id = p_de_id and caso_id = p_caso_id;

  insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
  values (p_por, 'entidade_fundida', 'entidade:' || p_para_id,
          jsonb_build_object('entidade_id', p_de_id, 'razao_social', v_de,
                             -- 0183
                             'forma_de_controle', v_forma_de, 'vinculos', v_vinculos_de),
          jsonb_build_object('entidade_id', p_para_id, 'razao_social', v_para,
                             'documentos_movidos', v_docs,
                             -- 0183
                             'vinculos_movidos', v_vinculos_movidos,
                             'vinculos_descartados', v_descartados));

  return jsonb_build_object('fundida', v_de, 'em', v_para, 'documentos', v_docs,
                            'vinculos_movidos', v_vinculos_movidos,
                            'vinculos_descartados', jsonb_array_length(v_descartados));
end;
$$;

comment on function fn_fundir_entidade(uuid, uuid, uuid, text) is
  'Funde duas entidades que são a mesma empresa, levando junto documentos, checklist, pendências '
  'e reconciliações (0153). Nada some sem rastro: evento_auditoria guarda o nome que existia e '
  'quantos documentos mudaram de dono. 0183: leva também os vínculos de entidade_controlador '
  'quando a sobrevivente não tem nenhum (antes, o on delete cascade os apagava); se ela já tem, '
  'os da absorvida não são somados e vão para o evento como vinculos_descartados. Não herda '
  'forma_de_controle (registra no evento) e resolve as pendências de forma e de papel da absorvida.';

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('fusao_preserva_controle_declarado', '0183', 'corpo', 'fn_fundir_entidade',
   'update entidade_controlador set entidade_id = p_para_id', null,
   'A fusão de entidades (0153) apagava por cascata os vínculos de controle declarados na absorvida, '
   'e fn_grupo_por_controle_comum passava a devolver um grupo menor sem erro. Reproduzido em '
   '24/09/2026: 1 vínculo antes da fusão, 0 depois. Ausente este trecho, a 0183 não foi aplicada '
   'ou uma reemissão posterior de fn_fundir_entidade voltou ao corpo da 0153.',
   'importante', 778)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

-- O REPARO ESCREVE A PRÓPRIA OBSERVAÇÃO. Sem isso, em produção a linha terminaria em "cobertura até
-- 0188" com o texto da 0182 ao lado: o reparo só subia o marcador, e o update da 0183 logo abaixo,
-- sendo mais antigo que 0188, era preservado-fora pelo gatilho junto com a observação dele. SIMULADO
-- pela revisão de 23/09/2026 (tabela temporária com o gatilho real): resultado `0188 | A 0182 fecha…`.
-- Num banco aplicado em ordem este texto é substituído logo abaixo pelo da 0183, que é o certo lá.
update instalacao_cobertura
   set ate_migration = (select max(migration) from instalacao_requisito),
       revisado_em   = current_date,
       observacao    = 'Marcador RECALCULADO pela 0183 a partir do catálogo instalacao_requisito ('
                       || (select max(migration) from instalacao_requisito) || ' é a maior migration '
                       'com requisito instalado). Motivo: a 0182 foi aplicada em produção depois da '
                       '0188 (sessões paralelas) e rebaixou o marcador; a 0183 criou o gatilho '
                       'trg_instalacao_cobertura_nao_regride para que isso não se repita.';

update instalacao_cobertura
   set ate_migration = '0183', revisado_em = current_date,
       observacao = 'A 0183 FECHA a fatia 1.7 do plano F1: entidade.forma_de_controle '
                    '(indefinido/controlada_por_entidade/controle_comum), com um quarto rótulo '
                    '(capital pulverizado) CONSIDERADO e RECUSADO por falta de medição — ver o '
                    'cabeçalho da migration. A guarda de coerência (check, mesma linha) exige '
                    'controladora_id não-nulo para controlada_por_entidade e nulo para '
                    'controle_comum; o trigger exige pelo menos um vínculo em '
                    'entidade_controlador para controle_comum. NADA é inferido de '
                    'controladora_id nem de entidade_controlador — só '
                    'fn_entidade_definir_forma_de_controle (humano) escreve. Pendência '
                    'complementar forma_de_controle_indefinida cobre toda entidade nova '
                    '(fn_upsert_entidade) e o backfill das pré-existentes. É a peça que faltava '
                    'para "um controladora_id vazio passar a ser distinguível de um não '
                    'preenchido" (critério de pronto da fatia 1.7, roadmap). Declarar a forma '
                    'real das 8 entidades do mandato AMO é decisão de uma sessão seguinte, '
                    'contra a sonda.';

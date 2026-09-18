-- =============================================================================
-- 0178 — fatia 1.2 do plano F1: `fn_upsert_entidade` aceitava QUALQUER string
--        como razão social, e cabeçalho de planilha virava pessoa jurídica
--
-- MEDIDO EM PRODUÇÃO (mandato real "AMO teste 00", 18/09/2026 — ver seção 12.1
-- de `Arquitetura do Sistema/3 Estado e Execução/ARQUITETURA_ALVO_E_ROADMAP.md`):
-- das 13 entidades cadastradas neste caso, QUATRO não são entidades —
--
--   Empresas · Vencidos · Status Extratos · Controle Extratos Ofx
--
-- — todas com EXATAMENTE 1 documento e SEM CNPJ. As 8 entidades reais do
-- mesmo mandato têm CNPJ. `fn_upsert_entidade` (0030) não tinha guarda
-- nenhuma entre "nome próprio de empresa" e "título de coluna/aba/arquivo":
-- qualquer string não-vazia que chegasse como `p_nome`, sem casar com nenhuma
-- entidade já cadastrada, virava uma linha nova em `entidade`. O padrão não é
-- acidente isolado do AMO — a fatia 1.1 (`f42f3cf`, 18/09/2026) mediu 16 das
-- 71 pendências `entidade_incorreta` abertas no banco inteiro na causa
-- `nome_de_arquivo_ou_titulo_virou_entidade` (script
-- `Supabase/test/perimetro-inventario.mjs`, constante `PADRAO_TITULO_OU_ARQUIVO`).
--
-- A ARMADILHA, já identificada no roadmap: o critério NÃO PODE ser "sem
-- CNPJ" sozinho. Entidade real sem CNPJ conhecido existe legitimamente — é o
-- balcão ambíguo que as `0175`-`0177` inteiras existem para tratar (nasce sem
-- CNPJ por construção, 0153/0162, e pode ficar assim indefinidamente até um
-- documento trazer a identidade fiscal). O sinal certo é a CONJUNÇÃO: sem
-- CNPJ **e** o nome bate um léxico de título/arquivo **e** este é o PRIMEIRO
-- documento da entidade (poucos documentos = 1, medido). A terceira condição
-- não precisa de contagem explícita aqui: o ramo novo só roda no `insert`
-- final de `fn_upsert_entidade` — o ponto em que NENHUM candidato exato,
-- frouxo-único ou de grupo casou (as linhas acima já teriam retornado) — e
-- toda linha que nasce ali começa, por construção, com zero documentos
-- atribuídos. O balcão ambíguo passa pelo MESMO `insert`, mas o nome dele vem
-- do CONTEÚDO do documento (ex.: "Araucaria SPE"), não de um título de
-- coluna — o léxico abaixo não o alcança, e é isso que evita reabrir o
-- defeito que a 0176/0177 corrigiram (balcão real tratado como descartável).
--
-- O LÉXICO usa `fn_entidade_canonica` (2690, já existente — acento/caixa/
-- pontuação/sufixo societário fora) como referência de normalização e
-- `Supabase/test/perimetro-inventario.mjs`/`PADRAO_TITULO_OU_ARQUIVO` como
-- referência de palavra: os 16 nomes reais que causaram a pendência
-- `nome_de_arquivo_ou_titulo_virou_entidade` começam com "Comparativo",
-- "Relatorio", "Controle", "Status", "Meses" ou "Liquido", ou contêm um
-- intervalo de exercícios (`2025x2024x2023`) — todos capturados pelo mesmo
-- padrão já testado ali. DUAS palavras são NOVAS aqui, e só aqui: "Empresas"
-- e "Vencidos" não aparecem nas 16 pendências (que comparam nome DIAGNOSTICADO
-- × nome JÁ CADASTRADO — um par, não um nome isolado), mas são 2 das 4
-- entidades reais medidas acima, cadastradas como PRIMEIRO nome sem nunca
-- terem sido comparadas a nada (documento único, sem diagnóstico
-- discordante). "Status" e "Controle" já cobriam as outras duas ("Status
-- Extratos", "Controle Extratos Ofx") — só 2 palavras precisaram entrar.
--
-- A DECISÃO DE PRODUTO (do dono, já tomada, não repetida aqui a cada sessão):
-- as 4 entidades que JÁ EXISTEM em produção não são deletadas (apagar perde a
-- proveniência dos documentos ligados a elas) nem fundidas automaticamente
-- com nada — fundir errado é pior que deixar separado. Elas são MARCADAS para
-- revisão humana, reaproveitando o padrão de pendência já usado por
-- `fn_pendencia_cnpj_colide_balcao` (0177) e `fn_pendencia_entidade_ambigua`
-- (0153): tipo `entidade_incorreta` (já é a família certa — é o mesmo tipo
-- que as 71 pendências da fatia 1.1 usam), motivo `entidade_nome_suspeito:<id>`
-- para dedupe por entidade, sem bloquear pipeline nenhum (severidade
-- `importante`, `sobrepujavel`). A migration FAZ os dois lados: (a) a guarda
-- daqui pra frente, dentro de `fn_upsert_entidade`; (b) o backfill, um laço
-- que aplica a MESMA função às entidades que já existem em QUALQUER banco em
-- que esta migration rodar — incluindo as 4 reais do AMO, quando aplicada em
-- produção (migration escrita ≠ aplicada — isso é decisão de uma sessão
-- depois, não desta).
--
-- MEDIÇÃO NÃO-VAZIA (regra 2 do CLAUDE.md), em
-- `Supabase/test/entidade_titulo_suspeito.test.sql`: com a guarda DESLIGADA
-- (checável comentando a chamada em `fn_upsert_entidade`), os 4 nomes
-- conhecidos passam como entidade comum, sem pendência — 4 asserts
-- reprovaram medidos contra o estado da 0177 antes de escrever a correção
-- (ver o corpo do teste para o número exato por bloco). Com a guarda LIGADA:
-- os 4 nomes reais abrem pendência `entidade_incorreta`/`entidade_nome_suspeito`
-- e a entidade continua existindo (documento não perde dona); um nome real de
-- empresa do MESMO mandato, `AMOBELEZA COMERCIO DIGITAL E OFFLINE LTDA`
-- (COM CNPJ), passa livre, sem pendência; e o balcão ambíguo (cenário da
-- 0176, nome vindo do conteúdo, sem CNPJ) continua nascendo e convergindo
-- normalmente, sem a guarda nova interferir.
--
-- NÃO decide o caso `OMNIBEAUTY … GESTAO DE MARCAS LTDA` × `… GESTAO DE
-- NEGOCIOS LTDA` (registrado no roadmap, seção 12.1) — a diferença de nome
-- não bate o léxico de título/arquivo, e por isso a guarda nova não o toca;
-- continua exigindo o contrato social, como já estava decidido.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- fn_entidade_nome_parece_titulo_ou_arquivo — o léxico, isolado em função
-- própria para a sonda poder provar a EXISTÊNCIA dele separado da CHAMADA
-- dentro de fn_upsert_entidade (o mesmo cuidado da 0177 com o marcador de
-- balcao_ambiguo_aprende_cnpj: duas perguntas diferentes merecem dois
-- requisitos, não um só que confunde "a função existe" com "é chamada onde
-- devia").
-- -----------------------------------------------------------------------------

CREATE FUNCTION public.fn_entidade_nome_parece_titulo_ou_arquivo(p_nome text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $_$
  select fn_entidade_canonica(p_nome) ~
    '^(comparativo|relatorio|controle|status|meses|liquido|empresas|vencidos)\y|\d{4}x\d{4}';
$_$;

COMMENT ON FUNCTION public.fn_entidade_nome_parece_titulo_ou_arquivo(p_nome text) IS '0178: nome com cara de título de coluna/planilha/arquivo em vez de razão social. Mesma normalização de fn_entidade_canonica (2690); o léxico é referência direta de Supabase/test/perimetro-inventario.mjs (PADRAO_TITULO_OU_ARQUIVO), medido contra os 16 nomes reais da causa nome_de_arquivo_ou_titulo_virou_entidade (fatia 1.1), mais "empresas"/"vencidos" — as 2 palavras que faltavam para cobrir as 4 entidades reais medidas no AMO teste 00 (seção 12.1 do roadmap). Léxico, não estatística: combinar com CNPJ nulo é o chamador, nunca esta função sozinha — ver o cabeçalho da 0178 para a armadilha do balcão ambíguo.';

-- -----------------------------------------------------------------------------
-- fn_pendencia_entidade_nome_suspeito — mesmo desenho de
-- fn_pendencia_cnpj_colide_balcao (0177) e fn_pendencia_entidade_ambigua
-- (0153): idempotente por MOTIVO (uma pendência por entidade, não por
-- documento/chamada), tipo entidade_incorreta (a mesma família que as 71
-- pendências da fatia 1.1 já usam), NUNCA funde nem apaga — só marca.
-- -----------------------------------------------------------------------------

CREATE FUNCTION public.fn_pendencia_entidade_nome_suspeito(p_caso_id uuid, p_entidade_id uuid, p_nome text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
declare
  v_motivo text := 'entidade_nome_suspeito:' || p_entidade_id;
  v_pend   uuid;
begin
  select id into v_pend from pendencia
   where caso_id = p_caso_id and motivo = v_motivo and estado <> 'resolvida'
   limit 1;
  if v_pend is not null then return v_pend; end if;

  insert into pendencia
    (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, entidade_id, motivo)
  values (
    p_caso_id, 'diagnostico', 'entidade_incorreta', 'importante', true,
    format('O nome "%s" tem cara de título de coluna/aba/arquivo, não de razão social — sem '
           || 'CNPJ e sem nenhum outro nome do caso para casar (0178). NÃO foi fundida nem '
           || 'apagada — fundir errado é pior que deixar separada, e apagar perderia a '
           || 'proveniência dos documentos já ligados a ela. O EFEITO, enquanto a pendência '
           || 'estiver aberta: os documentos desta pseudo-entidade ficam contabilizados FORA '
           || 'do book de qualquer empresa real do mandato. Confira o documento: se o nome '
           || 'certo está no conteúdo, funda com fn_fundir_entidade; se é mesmo um artefato '
           || '(cabeçalho de planilha, aba de controle), resolva a pendência sem fundir.',
           p_nome),
    p_entidade_id, v_motivo)
  returning id into v_pend;

  return v_pend;
end;
$$;

COMMENT ON FUNCTION public.fn_pendencia_entidade_nome_suspeito(p_caso_id uuid, p_entidade_id uuid, p_nome text) IS '0178: pendência entidade_incorreta para entidade cujo nome bate fn_entidade_nome_parece_titulo_ou_arquivo, sem CNPJ e recém-criada. Idempotente por entidade_id (motivo). Nunca funde, nunca apaga — só marca para revisão humana.';

-- -----------------------------------------------------------------------------
-- fn_upsert_entidade — reemitida INTEIRA, verbatim do corpo vigente (0177),
-- com só o bloco novo antes do `return v_id` final (nunca por âncora de texto
-- em corpo de função — .claude/memory/nunca-corrigir-funcao-por-replace.md).
-- A assinatura não muda, então `create or replace` basta, sem DROP.
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

  return v_id;
end;
$$;

COMMENT ON FUNCTION public.fn_upsert_entidade(p_caso_id uuid, p_nome text, p_cnpj text) IS 'Acha ou cria a entidade do caso (0030), sem ESCOLHER no empate (0153), com o nome truncado fundido no mais completo (0168), com o CNPJ como identidade (0169) e adotando a variante mais completa ao fundir por CNPJ (0171/0173 — a decisão mora em fn_entidade_talvez_renomear, chamada dos dois caminhos). 0174: o ramo (1) usa o RETORNO de fn_entidade_aprender_cnpj. 0176: o ramo (0) não devolve mais um balcão ambíguo (0162/0175) direto para OUTRA empresa — trata o CNPJ como ausente e registra a colisão (fn_pendencia_cnpj_colide_balcao). 0177: essa colisão só é registrada quando quem chegou NÃO é, ela própria, o mesmo balcão — um segundo documento do PRÓPRIO balcão (mesmo nome, mesmo CNPJ) não abre pendência falsa; segue pelo caminho normal. 0178: uma entidade NOVA (nenhum candidato casou), sem CNPJ, com nome que bate fn_entidade_nome_parece_titulo_ou_arquivo, ainda é criada (documento não perde dona) mas ganha pendência entidade_incorreta/entidade_nome_suspeito para revisão humana — nunca fundida nem apagada.';

-- -----------------------------------------------------------------------------
-- O BACKFILL. Entidades que JÁ EXISTEM neste banco (inclusive as 4 reais do
-- AMO, quando esta migration for aplicada em produção — escrita ≠ aplicada,
-- isso é decisão de uma sessão depois) e batem o mesmo critério que a guarda
-- daqui pra frente usa: sem CNPJ, nome de título/arquivo, e SÓ 1 documento —
-- aqui SIM contado explicitamente, porque a entidade já existe e pode ter
-- acumulado documentos desde que nasceu (ao contrário do `insert` acima, que
-- é sempre o primeiro). Reaproveita a MESMA fn_pendencia_entidade_nome_suspeito
-- — dedupe por entidade_id, então rodar esta migration mais de uma vez (ou
-- num banco onde a guarda já tenha marcado alguma destas) é inofensivo.
-- -----------------------------------------------------------------------------

do $$
declare
  r record;
begin
  for r in
    select e.id, e.caso_id, e.razao_social
    from entidade e
    where e.cnpj is null
      and fn_entidade_nome_parece_titulo_ou_arquivo(e.razao_social)
      and (select count(*) from documento d where d.entidade_id = e.id) = 1
  loop
    perform fn_pendencia_entidade_nome_suspeito(r.caso_id, r.id, r.razao_social);
  end loop;
end;
$$;

-- -----------------------------------------------------------------------------
-- O CATÁLOGO DA SONDA.
-- -----------------------------------------------------------------------------

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('entidade_nome_titulo_ou_arquivo_existe', '0178', 'funcao', 'fn_entidade_nome_parece_titulo_ou_arquivo',
   null, null,
   'O léxico que separa "razão social" de "título de coluna/aba/arquivo" — sem ele, a guarda de '
   'fn_upsert_entidade não tem como recusar/marcar "Empresas", "Vencidos", "Status Extratos" e '
   '"Controle Extratos Ofx" (as 4 de 13 entidades do mandato AMO teste 00 medidas em 18/09/2026 '
   'sem CNPJ e com 1 documento cada, contra as 8 reais, todas com CNPJ — seção 12.1 do roadmap).',
   'importante', 740)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('upsert_entidade_marca_nome_suspeito', '0178', 'corpo', 'fn_upsert_entidade',
   'fn_entidade_nome_parece_titulo_ou_arquivo(trim(p_nome))', null,
   'Prova a CHAMADA dentro de fn_upsert_entidade, não só a existência do léxico (o mesmo cuidado '
   'da 0177 com balcao_ambiguo_aprende_cnpj): sem esta linha no corpo publicado, uma reemissão '
   'futura da função pode perder a guarda mesmo com fn_entidade_nome_parece_titulo_ou_arquivo '
   'continuando presente e testada, e a sonda ficaria muda sobre isso.',
   'importante', 741)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('pendencia_entidade_nome_suspeito_existe', '0178', 'funcao', 'fn_pendencia_entidade_nome_suspeito',
   null, null,
   'A função que marca a entidade suspeita para revisão humana sem fundir nem apagar — decisão do '
   'dono registrada no cabeçalho da 0178. Ausente, a guarda de fn_upsert_entidade não teria como '
   'deixar rastro da recusa.',
   'importante', 742)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0178', revisado_em = current_date,
       observacao = 'A 0178 fecha a fatia 1.2 do plano F1: guarda em fn_upsert_entidade para que '
                    'nome de título/coluna/aba/arquivo não vire pessoa jurídica sem marca nenhuma '
                    '— léxico em fn_entidade_nome_parece_titulo_ou_arquivo, pendência (nunca fusão '
                    'automática) em fn_pendencia_entidade_nome_suspeito, e backfill para as '
                    'entidades que já existiam antes desta migration.';

commit;

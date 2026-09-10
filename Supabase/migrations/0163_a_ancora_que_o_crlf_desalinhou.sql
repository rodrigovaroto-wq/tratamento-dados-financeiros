-- =============================================================================
-- Migration 0163 — A ÂNCORA QUE O CRLF DESALINHOU: as duas migrations mais
-- novas nunca chegaram a escrever nada em produção, e a causa é a mesma da
-- 0142/0143/0145/0160 tendo funcionado — só que sem a mesma proteção.
--
-- O DEFEITO, relatado pelo dono ao tentar aplicar `0160`, `0161`, `0162` no
-- Supabase de produção, nesta ordem:
--
--   0160 → ERRO "o bloco de comparação de entidade não foi encontrado UMA
--          vez" — mas ela JÁ ESTAVA APLICADA (reexecução; o portão da própria
--          0160 recusou reaplicar sobre um corpo que já a contém). CORRETO.
--   0161 → ERRO "o bloco do format() de periodo_incorreto não foi encontrado
--          UMA vez (achei 0)".
--   0162 → ERRO "o patch apagou o da 0161 — abortado" (consequência direta:
--          como a 0161 não entrou, o corpo vigente não tinha o que a 0162
--          confere no fim para provar que não regrediu a vizinha).
--
-- NADA FOI CORROMPIDO. As três migrations são `do $mig$ ... end $mig$` com
-- `begin`/`raise exception`, e as duas que falharam abortaram ANTES do
-- `execute` (a 0161) ou depois de um `execute` cujo próprio corpo já carrega
-- a proteção de auto-reversão por transação (a 0162, mas ela nunca chegou lá:
-- a âncora dela reaproveita o texto exato da 0160/0162 vigentes, que já
-- estava lá — o que faltou foi o da 0161). `fn_instalacao_conferir()` rodada
-- pelo dono em produção devolve **ZERO linhas** — nenhum requisito ausente,
-- porque nenhum dos quatro requisitos da 0161/0162 chegou a ser inserido no
-- catálogo (a inserção mora DEPOIS do patch, na mesma migration que abortou).
--
-- A CAUSA, medida por reprodução, não suposição:
--
--   Sonda que o dono rodou em produção sobre fn_registrar_diagnostico:
--     md5=9098461a71979e7df52a481c0794d822  bytes=13620
--     tem_0121=false  tem_0142=true  tem_0160=TRUE  tem_0161=false
--     tem_0162=false  ancora_casou=1
--
--   Impressão digital LOCAL, reconstruindo o banco do zero nesta árvore:
--     estado 0159 -> a15d3bb89a3da3c55b1a0edf049da8a0 |  8507
--     estado 0160 -> 8f11482023ed5bec4c57a3a64849520c | 13414
--     estado 0161 -> 78fe5c7dc71843b795c8cc8f642631e6 | 13465
--     estado 0162 -> 8db263c25bd6d7199145b1999e8cd320 | 17585
--
--   Produção tem 13.620 bytes contra 13.414 do estado 0160 local: **206
--   bytes a mais**, e a função tem ~206 linhas — a diferença de bytes bate
--   com o custo de um `\r` extra por linha. **A CAUSA É CRLF**: o corpo em
--   produção foi gravado com `\r\n` (o texto passou, em algum momento, por um
--   editor ou colagem com terminador de linha do Windows — `pg_get_
--   functiondef` devolve exatamente o que está gravado, e não normaliza).
--
--   REPRODUZIDO NESTA ÁRVORE: o banco de teste `tdf_0160` (que fica no
--   servidor Postgres desta sessão) teve o corpo de `fn_registrar_
--   diagnostico` reemitido com `\r\n` no lugar de `\n` (13.631 bytes — a
--   mesma ordem de grandeza da diferença de produção), e a `0161` rodada
--   sobre ele falhou com a MESMA mensagem, literal, que o dono viu em
--   produção: `"0161: o bloco do format() de periodo_incorreto não foi
--   encontrado UMA vez (achei 0)"`.
--
--   A explicação, no próprio texto das migrations: a `0142`, a `0143`, a
--   `0145` e a `0160` usam `regexp_matches`/`regexp_replace` com `\r?\n`
--   entre os fragmentos do padrão que cruzam linha — o `?` torna o `\r`
--   OPCIONAL, então a mesma âncora casa tanto em corpo LF quanto em corpo
--   CRLF. **A `0161` e a `0162` nunca tiveram `\r?\n` em padrão nenhum** —
--   não por descuido isolado desta sessão: a técnica de âncora com `\r?`
--   nasceu na `0142` (ver o cabeçalho dela — "produção guarda o corpo com
--   CRLF e o banco montado do zero guarda com LF"), mas a lição não virou
--   hábito automático, e a 0161/0162 a perderam. É exatamente o buraco que
--   o item (6) desta migration fecha para a PRÓXIMA (ver a seção final).
--
-- ---------------------------------------------------------------------------
-- A DECISÃO DE PROJETO PARA ESTA MIGRATION: parar de patchar `fn_registrar_
-- diagnostico` por âncora, e REEMITIR A FUNÇÃO INTEIRA com o corpo final (o
-- estado da `0162`, que é o mais novo do repositório).
--
-- Por que isto é seguro AQUI, quando a `.claude/memory/nunca-corrigir-funcao-
-- por-replace.md` e o cabeçalho da própria 0160/0161/0162 escolheram âncora
-- exatamente para NÃO reemitir de cópia velha: o risco que âncora evita é
-- regredir em silêncio um patch MAIS NOVO que só existe no corpo vigente do
-- banco (não no texto de nenhuma migration sozinha) — foi o que quase
-- aconteceu na primeira versão da 0160 (regrediu o patch da 0142) e o que a
-- 0161/0162 preveniram com o `if position(...) = 0 then raise exception`
-- no fim de cada uma. Aqui esse risco NÃO EXISTE: a `0162` É a migration mais
-- nova do repositório — não há patch mais novo que ela para regredir. E o
-- estado que produção tem hoje (`0160`, `tem_0161=false`, `tem_0162=false`,
-- sonda zero linhas) confirma que produção não tem NADA além do que o
-- repositório já registra: reemitir para o estado da 0162 não apaga trabalho
-- nenhum que só exista em produção, porque não há trabalho assim.
--
-- A FONTE FIEL é `pg_get_functiondef` do banco `tdf_0162` (que fica no
-- servidor desta sessão, montado a partir das migrations até a 0162) — texto
-- IDÊNTICO, char a char, ao que `Supabase/schema.sql` desta árvore já
-- publica para `fn_registrar_diagnostico` (conferido por diff antes de
-- escrever esta migration). **Copiado VERBATIM abaixo — sem âncora, sem
-- regexp, sem `position()` sobre o corpo antigo.**
--
-- O QUE ESTA MIGRATION FAZ, em ordem:
--
--   (1) Reemite `fn_registrar_diagnostico` INTEIRA (estado 0162).
--   (2) Garante `fn_entidade_e_balcao_ambiguo` (0162: `create or replace`,
--       não patch — já era instalação idempotente por natureza), com
--       `comment` e `grant execute ... to authenticated`.
--   (3) Reexecuta, IDEMPOTENTE, as partes NÃO-patch da 0161 e da 0162 que
--       produção nunca recebeu (porque os `do $mig$` delas abortaram antes
--       de chegar lá): os `comment on function`, os `grant`, os `insert into
--       instalacao_requisito` (com `on conflict... do update`, como sempre),
--       a view `instalacao_sonda_entidade_balcao_ambiguo` e o fixture
--       permanente do caso "Sonda 0162". Nesta árvore, onde a 0161/0162 JÁ
--       aplicaram, isto é NO-OP semântico — `create or replace`/`on
--       conflict do update`/`grant` não duplicam nem regridem nada.
--   (4) Guardas que conferem o RESULTADO da reemissão (não a entrada): os
--       quatro marcadores (0142/0160/0161/0162) e a assinatura, contra o
--       corpo NOVO. Normalizadas com `replace(v_src, chr(13), '')` antes de
--       comparar — não porque os marcadores em si precisem (são todos texto
--       de UMA linha só, e uma âncora de linha única casa igual em LF e em
--       CRLF: é exatamente por isso que a 0161/0162 nunca precisaram de
--       `\r?` nas checagens de "confere em vez de confiar" que JÁ tinham) —
--       mas para a guarda não repetir, por hábito, o mesmo raciocínio frágil
--       que causou o defeito desta migration: se uma reemissão futura
--       precisar de um marcador multi-linha aqui, a normalização já está
--       pronta e não depende de mais ninguém lembrar.
--
--   (5) NÃO mexe em pendência nenhuma já aberta — 0163 é instalação de
--       código, não correção de dado. Igual a toda migration desta família
--       (ver 0160/0161/0162): reemitir a função não reprocessa documento
--       nenhum; o efeito só aparece na PRÓXIMA vez que `fn_registrar_
--       diagnostico` rodar sobre cada documento.
--
-- PROVADO EM DOIS ESTADOS (ver a mensagem de entrega para os números
-- exatos): (a) contra o banco `tdf_0160` (corpo em CRLF, sem 0161 nem 0162)
-- — depois desta migration, `md5(replace(pg_get_functiondef(...), chr(13),
-- ''))` bate, igual, com o mesmo hash tirado de `tdf_0162`; (b) nesta
-- árvore, onde a 0161/0162 já aplicaram — a 0163 roda por último, é NO-OP
-- semântico, e `Supabase/schema.sql` regenerado continua idêntico ao
-- commitado (`git diff --exit-code`), que é o assert mais importante: se o
-- schema mudasse, a reemissão não seria fiel.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- TUDO ABAIXO É UMA TRANSAÇÃO SÓ (begin ... commit no fim do arquivo). Ao
-- contrário da 0160/0161/0162 — que concentravam o risco num `do $mig$` único
-- e deixavam comment/grant/insert como statements separados DEPOIS dele —
-- esta migration reemite função ANTES de conferir o resultado (item 4), e sem
-- transação explícita um `raise exception` na guarda deixaria as duas
-- `CREATE OR REPLACE FUNCTION` já efetivadas (autocommit do psql), que é
-- exatamente o "estado pela metade" que `.claude/memory/nunca-corrigir-
-- funcao-por-replace.md` registra como o pior resultado possível: pior que
-- reprovar limpo. Com `begin`/`commit`, uma reprovação da guarda desfaz TUDO
-- — as duas funções, os inserts, a view, o fixture — e o banco fica
-- exatamente como estava antes de rodar este arquivo. MEDIDO: aplicando uma
-- cópia desta migration com um marcador removido de propósito contra um
-- banco de teste, a guarda (item 4) reprova com a mensagem esperada.
-- -----------------------------------------------------------------------------
begin;

-- -----------------------------------------------------------------------------
-- (1) fn_registrar_diagnostico — REEMITIDA INTEIRA, ESTADO 0162, VERBATIM.
--
-- Fonte: `select pg_get_functiondef('fn_registrar_diagnostico'::regproc)` no
-- banco `tdf_0162` desta sessão — igual, char a char, ao que
-- `Supabase/schema.sql` já publica para esta função (conferido por diff).
-- Nenhuma linha abaixo foi redigitada.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_registrar_diagnostico(p_documento_id uuid, p_documento_versao_id uuid, p_entidade_nome text, p_tipo_confirma boolean, p_tipo_sugerido text, p_periodo_tipo text, p_periodo_referencia text, p_legibilidade legibilidade, p_nota_legibilidade text, p_resumo text, p_justificativa text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
  v_caso_id            uuid;
  v_entidade_id         uuid;
  v_tipo_atual          text;
  v_periodo_id          uuid;
  v_periodo_tipo_atual  text;
  v_periodo_ref_atual   text;
  v_entidade_atual_nome text;
  v_pendencia_id        uuid;
  v_entidade_criada     boolean := false;
  v_pendencia_grupo_id  uuid;
  v_outros_n            int;
  v_outros_nomes        text;
  v_exatas_ambiguidade_n    int;
  v_exata_ambiguidade_nome  text;
  v_pendencia_ambigua_resp_id uuid;
  v_ambigua_resp_desc       text;
begin
  select caso_id, entidade_id, tipo_taxonomia, periodo_id
    into v_caso_id, v_entidade_id, v_tipo_atual, v_periodo_id
  from documento where id = p_documento_id;

  if v_caso_id is null then
    return jsonb_build_object('executado', false, 'motivo', 'documento não encontrado');
  end if;

  if v_periodo_id is not null then
    select tipo, referencia into v_periodo_tipo_atual, v_periodo_ref_atual from periodo where id = v_periodo_id;
  end if;

  -- ----- Entidade: preenche a lacuna se ainda vazia; senão só confere -----
  if p_entidade_nome is not null and length(trim(p_entidade_nome)) > 0 then
    if v_entidade_id is null then
      -- 0121: `fn_upsert_entidade` (0030), e não mais igualdade exata de texto.
      -- Era ela quem criava a segunda linha da MESMA empresa: o classificador
      -- não resolvia a entidade pelo nome do arquivo (6 dos 38 documentos do
      -- book), o diagnóstico lia a razão social completa do conteúdo
      -- ("CANASTRA INDÚSTRIA DE EMBALAGENS LTDA."), não achava igualdade exata
      -- com a que já existia ("Canastra Industria") e INSERIA outra.
      v_entidade_id := fn_upsert_entidade(v_caso_id, p_entidade_nome);
      update documento set entidade_id = v_entidade_id where id = p_documento_id;
      v_entidade_criada := true;
    else
      select razao_social into v_entidade_atual_nome from entidade where id = v_entidade_id;

      select id into v_pendencia_id from pendencia
        where caso_id = v_caso_id and motivo = 'diagnostico:entidade:' || p_documento_id and estado <> 'resolvida'
        limit 1;
      select id into v_pendencia_grupo_id from pendencia
        where caso_id = v_caso_id and motivo = 'diagnostico:entidade_grupo:' || p_documento_id and estado <> 'resolvida'
        limit 1;

      -- 0162: O CASAMENTO CONTRA O BALCÃO AMBÍGUO NÃO CONFIRMA NADA — ele foi
      -- criado (0153) exatamente porque o nome dele já casava com MAIS DE UMA
      -- empresa do caso, então casa por construção com qualquer nome de
      -- conteúdo que aponte para as candidatas que o originaram. Medido no
      -- araucária (lote 7417, 03/09): o documento 009 ficou no balcão
      -- "Araucaria SPE" (pendência entidade_ambigua bloqueante contra
      -- BIOENERGIA × IMOBILIÁRIA), e o diagnóstico de conteúdo, lendo o
      -- PRÓPRIO documento, nomeou "ARAUCÁRIA IMOBILIÁRIA SPE LTDA." por
      -- extenso — que `fn_mesma_entidade` confirma contra o balcão (ele casa
      -- com as DUAS empresas do grupo, por definição), e o ramo abaixo (0121)
      -- tomava isso como CONFIRMAÇÃO, sem a pendência bloqueante da 0153 nunca
      -- ter sido tocada e sem a resposta deixar rastro em lugar nenhum.
      if fn_entidade_e_balcao_ambiguo(v_caso_id, v_entidade_id) then
        -- O conteúdo pode ter respondido à própria pergunta: se o nome
        -- diagnosticado casa EXATO com exatamente UMA empresa já cadastrada
        -- neste caso (excluído o próprio balcão), é essa a resposta. NÃO
        -- decide sozinho — não move o documento, não funde — só a NOMEIA,
        -- para o humano confirmar em segundos em vez de abrir o PDF.
        select count(*) into v_exatas_ambiguidade_n
        from fn_entidades_candidatas(v_caso_id, p_entidade_nome) c
        where c.exata and c.entidade_id <> v_entidade_id;

        if v_exatas_ambiguidade_n = 1 then
          select c.razao_social into v_exata_ambiguidade_nome
          from fn_entidades_candidatas(v_caso_id, p_entidade_nome) c
          where c.exata and c.entidade_id <> v_entidade_id
          limit 1;

          select id into v_pendencia_ambigua_resp_id from pendencia
            where caso_id = v_caso_id
              and motivo = 'diagnostico:entidade_ambigua_respondida:' || p_documento_id
              and estado <> 'resolvida'
            limit 1;

          v_ambigua_resp_desc := format(
            'O nome do arquivo casou com MAIS DE UMA empresa deste mandato e não identificou '
            || 'nenhuma — por isso o documento foi registrado numa entidade própria ("%s"). O '
            || 'CONTEÚDO deste documento nomeia "%s", que é uma das empresas JÁ CADASTRADAS '
            || 'neste mandato — e nomeia só ela. Confirme pela revisão (fn_revisar_documento) se '
            || 'o documento é mesmo dela; se as duas linhas forem a mesma empresa, funda com '
            || 'fn_fundir_entidade.%s',
            coalesce(v_entidade_atual_nome, '(nenhuma)'), v_exata_ambiguidade_nome,
            case when p_justificativa is not null and length(trim(p_justificativa)) > 0
                 then ' Justificativa do diagnóstico: ' || p_justificativa else '' end);

          if v_pendencia_ambigua_resp_id is null then
            insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, entidade_id, motivo)
              values (v_caso_id, 'diagnostico', 'entidade_incorreta', 'importante', true,
                v_ambigua_resp_desc, p_documento_id, v_entidade_id,
                'diagnostico:entidade_ambigua_respondida:' || p_documento_id);
          else
            update pendencia set descricao = v_ambigua_resp_desc where id = v_pendencia_ambigua_resp_id;
          end if;
        end if;
        -- Zero, duas ou mais exatas: o conteúdo NÃO respondeu — silêncio aqui
        -- é honesto (regra 1 do CLAUDE.md: não fabricar ausência como dado).
        -- E, em QUALQUER dos casos acima, o casamento contra o balcão NUNCA
        -- resolve `diagnostico:entidade`/`diagnostico:entidade_grupo` — não
        -- tocar `v_pendencia_id`/`v_pendencia_grupo_id` aqui é o que deixa
        -- isso explícito: só o ramo `else` abaixo (comparação contra uma
        -- entidade de VERDADE) resolve essas duas pendências.
      else
      -- 0121: divergência de ENTIDADE medida pela forma canônica, como o
      -- período já é desde a 0022. "Canastra Industria" e "CANASTRA INDÚSTRIA
      -- DE EMBALAGENS LTDA." são a mesma empresa, e `fn_mesma_entidade` já
      -- sabia disso.
      if fn_mesma_entidade(v_entidade_atual_nome, p_entidade_nome) then
        if v_pendencia_id is not null then
          update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:diagnostico'
            where id = v_pendencia_id;
        end if;
        if v_pendencia_grupo_id is not null then
          update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:diagnostico'
            where id = v_pendencia_grupo_id;
        end if;
      else
        -- 0160: o nome que não casou com o registrado pode casar com OUTRA(S)
        -- empresa(s) já cadastrada(s) NESTE caso — nesse caso a função não sabe
        -- afirmar que o registro está errado. Excluída a própria entidade do
        -- documento, para não contar "casou consigo mesma" como candidata a
        -- outra empresa. Reaproveita `fn_entidades_candidatas` da 0153 em vez de
        -- duplicar a busca — e, ao contrário da 0153 (que ali resolve escolhendo
        -- SEM decidir, criando entidade nova), aqui `order by ... limit 1`
        -- escolheria no empate quando há mais de um candidato, que é exatamente
        -- o que a 0153 existe para não fazer: conta TODOS os candidatos, para a
        -- mensagem nomear todos, não só o primeiro por ordem alfabética.
        select count(*), string_agg(c.razao_social, ' × ' order by c.razao_social)
          into v_outros_n, v_outros_nomes
        from fn_entidades_candidatas(v_caso_id, p_entidade_nome) c
        where c.entidade_id <> v_entidade_id;

        if v_outros_n >= 1 then
          -- NÃO É AFIRMAÇÃO DE HIERARQUIA: `entidade.papel_no_grupo` é o único
          -- campo que registraria holding × subsidiária, e esta função não o
          -- consulta — não há como saber, só a partir do nome, qual é a relação
          -- entre as duas empresas, ou se há relação alguma. O que dá para
          -- afirmar sem inventar é só isto: as duas (ou mais) já são empresas
          -- cadastradas neste mandato, e o sistema não sabe qual delas é a
          -- certa para este documento — não decide quem está certo, só para de
          -- chamar de "incorreto" um registro que pode estar certo. A pendência
          -- de erro clássica, se estava aberta de uma rodada anterior, fecha —
          -- a resposta mudou de categoria (mas isso só acontece na PRÓXIMA
          -- passada de `fn_registrar_diagnostico` sobre o documento, não ao
          -- aplicar esta migration — ver `Supabase/README.md`).
          if v_pendencia_id is not null then
            update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:diagnostico'
              where id = v_pendencia_id;
          end if;
          if v_pendencia_grupo_id is null then
            insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, entidade_id, motivo)
              values (v_caso_id, 'diagnostico', 'entidade_incorreta', 'importante', true,
                case when v_outros_n = 1 then
                  format('O documento está registrado em "%s", mas o diagnóstico de conteúdo aponta "%s" — nome '
                         || 'que também já é uma empresa CADASTRADA neste mandato ("%s"). As duas são empresas '
                         || 'cadastradas neste caso, e o sistema não sabe qual das duas é a certa para este '
                         || 'documento — não presume nenhuma. Confira pela revisão se ele pertence mesmo a "%s" '
                         || 'ou deveria estar em "%s", sem fundir: as duas continuam sendo empresas diferentes.',
                         coalesce(v_entidade_atual_nome, '(nenhuma)'), p_entidade_nome, v_outros_nomes,
                         coalesce(v_entidade_atual_nome, '(nenhuma)'), v_outros_nomes)
                else
                  format('O documento está registrado em "%s", mas o diagnóstico de conteúdo aponta "%s" — nome '
                         || 'que casa com MAIS DE UMA empresa já cadastrada neste mandato (%s). O sistema não '
                         || 'sabe qual delas é a certa para este documento — não presume nenhuma. Confira pela '
                         || 'revisão qual é a empresa certa, sem fundir: continuam sendo empresas diferentes.',
                         coalesce(v_entidade_atual_nome, '(nenhuma)'), p_entidade_nome, v_outros_nomes)
                end,
                p_documento_id, v_entidade_id, 'diagnostico:entidade_grupo:' || p_documento_id);
          end if;
        else
          -- DIVERGÊNCIA DE VERDADE: o nome diagnosticado não bate com NENHUMA
          -- empresa já cadastrada no caso — não há hierarquia a reconhecer, e a
          -- pendência clássica continua acusando exatamente como na 0121.
          if v_pendencia_grupo_id is not null then
            update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:diagnostico'
              where id = v_pendencia_grupo_id;
          end if;
          if v_pendencia_id is null then
            insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
              values (v_caso_id, 'diagnostico', 'entidade_incorreta', 'importante', true,
                format('Diagnóstico de conteúdo sugere entidade "%s", mas o documento está registrado com "%s".',
                       p_entidade_nome, coalesce(v_entidade_atual_nome, '(nenhuma)')),
                p_documento_id, 'diagnostico:entidade:' || p_documento_id);
          end if;
        end if;
      end if;
      end if;
    end if;
  end if;

  -- ----- Tipo: confere contra o que já está registrado -----
  select id into v_pendencia_id from pendencia
    where caso_id = v_caso_id and motivo = 'diagnostico:tipo:' || p_documento_id and estado <> 'resolvida'
    limit 1;
  -- 0142: exige divergência ACIONÁVEL. "Não confirmo" sozinho não basta —
  -- o modelo diz isso também quando reconhece o mesmo tipo com outro nome
  -- (doc 27 da v48: NOTAS_EXPL contra NOTAS_EXPL) ou quando não sabe o que o
  -- documento é ("?" contra "(nenhum)", doc 28). Nos dois casos a pendência
  -- pedia decisão sobre uma diferença que não existe.
  if (p_tipo_sugerido is not null and p_tipo_sugerido is distinct from v_tipo_atual)
     or (coalesce(p_tipo_confirma, true) = false
         and v_tipo_atual is not null
         and coalesce(p_tipo_sugerido, '') <> coalesce(v_tipo_atual, '')) then
    if v_pendencia_id is null then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
        values (v_caso_id, 'diagnostico', 'tipo_incorreto', 'importante', true,
          format('Diagnóstico de conteúdo sugere tipo "%s" (documento está registrado como "%s"). %s',
                 coalesce(p_tipo_sugerido, '?'), coalesce(v_tipo_atual, '(nenhum)'), coalesce(p_justificativa, '')),
          p_documento_id, 'diagnostico:tipo:' || p_documento_id);
    end if;
  elsif v_pendencia_id is not null then
    update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:diagnostico'
      where id = v_pendencia_id;
  end if;

  -- ----- Período: confere contra o registrado, por FORMA CANÔNICA (0020) -----
  -- Só diverge quando os períodos são canonicamente distintos — notações
  -- diferentes do MESMO período não geram mais pendência falsa.
  select id into v_pendencia_id from pendencia
    where caso_id = v_caso_id and motivo = 'diagnostico:periodo:' || p_documento_id and estado <> 'resolvida'
    limit 1;
  -- 0022: compara pelo CONJUNTO DE ANOS. "anual 2025" e "data-base 2025-12-31"
  -- são o MESMO exercício com granularidade diferente — não é divergência, é
  -- refinamento; acusar isso enchia a fila de revisão de pendência falsa.
  -- Divergência real (2024 × 2025) continua virando pendência.
  if p_periodo_referencia is not null
     and not fn_periodos_equivalentes(p_periodo_tipo, p_periodo_referencia,
                                      v_periodo_tipo_atual, v_periodo_ref_atual) then
    if v_pendencia_id is null then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
        values (v_caso_id, 'diagnostico', 'periodo_incorreto', 'importante', true,
          format('Diagnóstico de conteúdo sugere período "%s %s" (documento está registrado com "%s %s"). %s',
                 p_periodo_tipo, p_periodo_referencia, coalesce(v_periodo_tipo_atual, '?'), coalesce(v_periodo_ref_atual, '(nenhum)'),
                 coalesce(p_justificativa, '')),
          p_documento_id, 'diagnostico:periodo:' || p_documento_id);
    end if;
  elsif v_pendencia_id is not null then
    update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:diagnostico'
      where id = v_pendencia_id;
  end if;

  -- ----- Legibilidade real do arquivo -----
  update documento_versao set legibilidade = coalesce(p_legibilidade, legibilidade), nota_legibilidade = p_nota_legibilidade
    where id = p_documento_versao_id;

  select id into v_pendencia_id from pendencia
    where caso_id = v_caso_id and motivo = 'diagnostico:legibilidade:' || p_documento_id and estado <> 'resolvida'
    limit 1;
  if p_legibilidade = 'ilegivel' then
    if v_pendencia_id is null then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
        values (v_caso_id, 'diagnostico', 'arquivo_ilegivel', 'importante', true,
          coalesce(p_nota_legibilidade, 'Arquivo sinalizado como ilegível pelo diagnóstico de conteúdo.'),
          p_documento_id, 'diagnostico:legibilidade:' || p_documento_id);
    end if;
  elsif v_pendencia_id is not null then
    update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:diagnostico'
      where id = v_pendencia_id;
  end if;

  -- ----- Resumo (nunca apaga um resumo anterior com uma resposta vazia) -----
  update documento set resumo = coalesce(p_resumo, resumo) where id = p_documento_id;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:diagnostico', 'diagnostico_documento', 'documento:'||p_documento_id,
      jsonb_build_object(
        'entidade', p_entidade_nome, 'tipo_confirma', p_tipo_confirma, 'tipo_sugerido', p_tipo_sugerido,
        'periodo_tipo', p_periodo_tipo, 'periodo_referencia', p_periodo_referencia,
        'legibilidade', p_legibilidade, 'resumo', p_resumo, 'justificativa', p_justificativa));

  return jsonb_build_object('executado', true, 'documento_id', p_documento_id, 'entidade_id', v_entidade_id,
    'entidade_criada', v_entidade_criada);
end;
$function$;

comment on function fn_registrar_diagnostico(uuid, uuid, text, boolean, text, text, text, legibilidade, text, text, text) is
  'Registra o diagnóstico de conteúdo (E1/E2) e confere contra o que já está no banco. 0121: a '
  'entidade casa e diverge pela forma CANÔNICA. 0142: tipo só diverge com divergência ACIONÁVEL. '
  '0160: quando a entidade não casa, mas o nome diagnosticado é ELE MESMO outra (ou mais de uma) '
  'empresa já cadastrada no mesmo caso, a função não sabe se o registro está certo ou errado — não '
  'presume nenhuma das duas, nomeia as candidatas na pendência e deixa a revisão decidir, sem '
  'fundir nem mover o documento sozinha. 0161: a pendência de periodo_incorreto passa a citar a '
  'justificativa do diagnóstico, como o tipo_incorreto já fazia. 0162: quando a entidade REGISTRADA '
  'é o balcão de perguntas da 0153 (nome que casou com DUAS ou mais empresas e não decidiu), o '
  'casamento de fn_mesma_entidade contra ele NÃO confirma nada — o balcão casa com todo mundo por '
  'construção. Se o nome diagnosticado casa EXATO com exatamente UMA empresa já cadastrada '
  '(excluído o balcão), abre pendência nomeando a resposta, sem mover o documento nem fundir. 0163: '
  'reemitida INTEIRA (não mais por patch de âncora) depois de produção ter abortado a aplicação da '
  '0161/0162 por causa de um corpo gravado em CRLF — ver o cabeçalho da 0163.';

grant execute on function fn_registrar_diagnostico(uuid, uuid, text, boolean, text, text, text, legibilidade, text, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- (2) fn_entidade_e_balcao_ambiguo — GARANTIDA (0162: já era `create or
-- replace`, não patch — instalação idempotente por natureza; reexecutada
-- aqui para o banco que ainda não a tem).
-- -----------------------------------------------------------------------------
create or replace function fn_entidade_e_balcao_ambiguo(p_caso_id uuid, p_entidade_id uuid)
returns boolean
language sql
stable
as $$
  select exists (
    select 1 from pendencia
    where caso_id = p_caso_id
      and entidade_id = p_entidade_id
      and motivo = 'entidade_ambigua:' || p_entidade_id
      and estado <> 'resolvida'
  );
$$;

comment on function fn_entidade_e_balcao_ambiguo(uuid, uuid) is
  'Verdadeiro quando a entidade é o balcão de perguntas que a 0153 cria para um nome que casa com '
  'DUAS ou mais empresas do caso — reconhecido pela pendência `entidade_ambigua:<id>` ainda aberta. '
  '(0162) Existe porque o balcão casa com TODO MUNDO por construção (foi criado exatamente porque '
  'o nome dele casava com mais de uma empresa), e `fn_registrar_diagnostico` estava tratando esse '
  'casamento como confirmação.';

grant execute on function fn_entidade_e_balcao_ambiguo(uuid, uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- (4) GUARDAS — conferem o RESULTADO da reemissão, não a entrada. Ver o
-- cabeçalho para o porquê da normalização de CRLF (defesa em profundidade;
-- os marcadores abaixo são todos de UMA linha e por isso já seriam achados
-- em corpo LF ou CRLF sem normalizar — a normalização é o hábito que esta
-- migration devolve ao repositório, não uma necessidade estrita de cada
-- marcador isolado).
-- -----------------------------------------------------------------------------
do $verifica0163$
declare
  v_src  text;
  v_norm text;
begin
  select pg_get_functiondef(p.oid) into v_src
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'fn_registrar_diagnostico';

  if v_src is null then
    raise exception '0163: fn_registrar_diagnostico não existe depois da reemissão — algo abortou antes do CREATE OR REPLACE acima';
  end if;

  v_norm := replace(v_src, chr(13), '');

  if position('0142: exige divergência ACIONÁVEL' in v_norm) = 0 then
    raise exception '0163: a reemissão saiu sem o marcador da 0142 (tipo_incorreto exige divergência acionável) — abortado';
  end if;
  if position('0160: o nome que não casou' in v_norm) = 0 then
    raise exception '0163: a reemissão saiu sem o marcador da 0160 (hierarquia não é entidade_incorreta) — abortado';
  end if;
  if position('registrado com "%s %s"). %s' in v_norm) = 0 then
    raise exception '0163: a reemissão saiu sem o marcador da 0161 (periodo_incorreto cita a justificativa) — abortado';
  end if;
  if position('0162: O CASAMENTO CONTRA O BALCÃO AMBÍGUO' in v_norm) = 0 then
    raise exception '0163: a reemissão saiu sem o marcador da 0162 (o balcão ambíguo não confirma) — abortado';
  end if;

  -- A assinatura (onze parâmetros, mesmos nomes e tipos) não pode ter mudado
  -- — ela é uma linha só em pg_get_functiondef, então a comparação já é
  -- imune a CRLF por construção; ainda assim compara contra v_norm, para
  -- não depender de ninguém lembrar disso da próxima vez.
  if position('fn_registrar_diagnostico(p_documento_id uuid, p_documento_versao_id uuid, p_entidade_nome text, p_tipo_confirma boolean, p_tipo_sugerido text, p_periodo_tipo text, p_periodo_referencia text, p_legibilidade legibilidade, p_nota_legibilidade text, p_resumo text, p_justificativa text)' in v_norm) = 0 then
    raise exception '0163: a assinatura de fn_registrar_diagnostico mudou na reemissão — abortado';
  end if;

  if to_regproc('public.fn_entidade_e_balcao_ambiguo') is null then
    raise exception '0163: fn_entidade_e_balcao_ambiguo não existe depois do CREATE OR REPLACE acima — abortado';
  end if;
end $verifica0163$;

-- -----------------------------------------------------------------------------
-- (3) O CATÁLOGO DA SONDA — reinstala, IDEMPOTENTE, os quatro requisitos da
-- 0161/0162 que produção nunca recebeu (o `insert` delas morava DEPOIS do
-- patch que abortou). `migration` continua apontando para 0161/0162: é
-- quando cada invariante foi desenhado e medido — a 0163 só o INSTALA de
-- novo num catálogo que, em produção, nunca chegou a tê-lo.
-- -----------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('periodo_incorreto_cita_justificativa', '0161', 'corpo', 'fn_registrar_diagnostico',
   'registrado com "%s %s"). %s', null,
   'Medido no lote 7377 (02/09): as pendências `periodo_incorreto` (2 dos 4 achados que o '
   'explorador marcou como divergência real, sem resposta automática honesta) mostravam o período '
   'sugerido contra o registrado mas nunca a justificativa do diagnóstico — mesmo ela chegando '
   'pronta na MESMA chamada e o `tipo_incorreto` já mostrando a mesma informação desde sempre. '
   'Sem isto, o revisor decide sem a razão que o próprio diagnóstico escreveu.',
   'importante', 590),
  ('diagnostico_nao_confirma_pelo_balcao', '0162', 'corpo', 'fn_registrar_diagnostico',
   '0162: O CASAMENTO CONTRA O BALCÃO AMBÍGUO', null,
   'O balcão de perguntas da 0153 casa com TODO MUNDO por construção (foi criado porque o nome dele '
   'casava com mais de uma empresa) — e fn_registrar_diagnostico tratava esse casamento como '
   'confirmação. Medido nesta árvore, reproduzindo o padrão do lote 7417 (araucária, 03/09): o '
   'diagnóstico de conteúdo do documento 009 nomeia "ARAUCÁRIA IMOBILIÁRIA SPE LTDA." por extenso, '
   '`fn_mesma_entidade` confirma contra o balcão "Araucaria SPE" (ele casa com as DUAS empresas do '
   'grupo), e a resposta que o documento trazia desaparecia sem deixar rastro — a pendência '
   'bloqueante da 0153 continuava aberta, sem ninguém saber que o próprio documento já respondera.',
   'bloqueante', 610),
  ('entidade_balcao_ambiguo_predicado', '0162', 'funcao', 'fn_entidade_e_balcao_ambiguo', null, null,
   'Sem ela não há como `fn_registrar_diagnostico` distinguir "esta entidade é uma empresa de '
   'verdade" de "esta entidade é o balcão de perguntas da 0153" — e o casamento contra o balcão '
   'volta a ser lido como confirmação.',
   'importante', 611),
  ('entidade_balcao_ambiguo_regra_viva', '0162', 'seed', 'instalacao_sonda_entidade_balcao_ambiguo', null, 1,
   'A REGRA de quando uma entidade é balcão ambíguo pode existir como código morto: um requisito de '
   '"corpo" ou "função" prova só que o texto está no arquivo, não que o predicado decide certo. Esta '
   'linha executa a decisão contra um fixture fixo (aberta=balcão, resolvida=não-balcão, '
   'inexistente=não-balcão, caso errado=não-balcão); ausente aqui quer dizer que o predicado pode '
   'ter voltado a dizer sempre falso (ou sempre verdadeiro), e o casamento contra o balcão volta a '
   'ser tratado como confirmação em silêncio.',
   'bloqueante', 612)
on conflict (chave) do update
  set migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
      marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
      porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

-- -----------------------------------------------------------------------------
-- A view da sonda (0162) e o fixture permanente "Sonda 0162" — reinstalados
-- IDEMPOTENTE pela mesma razão do catálogo acima.
-- -----------------------------------------------------------------------------
insert into caso (id, nome, produto) values
  ('01620000-0000-0000-0000-000000000001'::uuid,
   'Sonda 0162 — balcão ambíguo (fixture da instalação, não é mandato real)',
   'reestruturacao')
on conflict (id) do nothing;

insert into entidade (id, caso_id, razao_social) values
  ('01620000-0000-0000-0000-000000000002'::uuid, '01620000-0000-0000-0000-000000000001'::uuid, 'Sonda 0162 — balcão (com pendência aberta)'),
  ('01620000-0000-0000-0000-000000000003'::uuid, '01620000-0000-0000-0000-000000000001'::uuid, 'Sonda 0162 — normal (sem pendência)'),
  ('01620000-0000-0000-0000-000000000004'::uuid, '01620000-0000-0000-0000-000000000001'::uuid, 'Sonda 0162 — ex-balcão (pendência resolvida)')
on conflict (id) do nothing;

insert into pendencia
  (id, caso_id, origem_estagio, tipo, severidade, estado, sobrepujavel, descricao, entidade_id, motivo) values
  ('01620000-0000-0000-0000-000000000005'::uuid, '01620000-0000-0000-0000-000000000001'::uuid,
   'classificacao', 'entidade_incorreta', 'bloqueante', 'aberta', false,
   'Fixture da sonda 0162 — não editar nem resolver: o `run.sh` depende dela continuar aberta.',
   '01620000-0000-0000-0000-000000000002'::uuid,
   'entidade_ambigua:01620000-0000-0000-0000-000000000002'),
  ('01620000-0000-0000-0000-000000000006'::uuid, '01620000-0000-0000-0000-000000000001'::uuid,
   'classificacao', 'entidade_incorreta', 'bloqueante', 'resolvida', false,
   'Fixture da sonda 0162 — já resolvida de propósito: prova que resolvida não conta como balcão.',
   '01620000-0000-0000-0000-000000000004'::uuid,
   'entidade_ambigua:01620000-0000-0000-0000-000000000004')
on conflict (id) do update set estado = excluded.estado;

create or replace view instalacao_sonda_entidade_balcao_ambiguo as
select 1 as ok
where
  -- o balcão de verdade: pendência entidade_ambigua ABERTA para esta entidade.
  fn_entidade_e_balcao_ambiguo('01620000-0000-0000-0000-000000000001'::uuid,
                                '01620000-0000-0000-0000-000000000002'::uuid) = true
  -- entidade normal, sem pendência nenhuma: nunca foi balcão.
  and fn_entidade_e_balcao_ambiguo('01620000-0000-0000-0000-000000000001'::uuid,
                                '01620000-0000-0000-0000-000000000003'::uuid) = false
  -- a MESMA pendência, mas RESOLVIDA: deixou de ser balcão — resolvida não conta.
  and fn_entidade_e_balcao_ambiguo('01620000-0000-0000-0000-000000000001'::uuid,
                                '01620000-0000-0000-0000-000000000004'::uuid) = false
  -- entidade que nem existe: sem pendência nenhuma, o predicado não quebra.
  and fn_entidade_e_balcao_ambiguo('01620000-0000-0000-0000-000000000001'::uuid,
                                '01620000-0000-0000-0000-000000000009'::uuid) = false
  -- caso errado: a MESMA entidade-balcão sob um caso que não é o dela — a
  -- pendência é POR CASO, não só por entidade.
  and fn_entidade_e_balcao_ambiguo('01620000-0000-0000-0000-000000000099'::uuid,
                                '01620000-0000-0000-0000-000000000002'::uuid) = false;

comment on view instalacao_sonda_entidade_balcao_ambiguo is
  '(0162) Autoteste de fn_entidade_e_balcao_ambiguo, EXECUTADO contra um fixture PERMANENTE e '
  'isolado (o caso "Sonda 0162", que não é mandato real): 1 linha só se a entidade com pendência '
  'entidade_ambigua ABERTA responde true, a entidade sem pendência e a com a MESMA pendência '
  'RESOLVIDA respondem false, e o predicado não quebra para entidade inexistente nem confunde caso. '
  'Um marcador textual de corpo/função não pega um "false and" que mate o predicado e deixe os '
  'comentários intactos (achado D da revisão da 0157) — esta view pega, porque o predicado É '
  'executado.';

grant select on instalacao_sonda_entidade_balcao_ambiguo to authenticated;

-- -----------------------------------------------------------------------------
-- A COBERTURA DECLARADA — até a 0163. NÃO há requisito NOVO específico desta
-- migration: ela não muda o que o sistema decide (não é invariante de
-- produto), só CONSERTA COMO o invariante da 0161/0162 chega ao banco de
-- produção — e esse invariante já está coberto pelos quatro requisitos
-- reinstalados acima. A garantia de que a reemissão foi fiel é a guarda (4),
-- que roda NA INSTALAÇÃO (raise exception se qualquer marcador faltar) — não
-- é um requisito persistente de fn_instalacao_conferir, porque não há nada
-- para ela conferir DEPOIS que não seja redundante com os quatro que já
-- conferem o corpo publicado.
-- -----------------------------------------------------------------------------
update instalacao_cobertura
   set ate_migration = '0163',
       revisado_em = date '2026-09-10',
       observacao = 'Revisão de 10/09/2026: a 0163 reemite fn_registrar_diagnostico INTEIRA (estado '
                    '0162) depois de produção ter abortado a aplicação da 0161 e da 0162 — causa '
                    'medida: o corpo em produção está gravado em CRLF (206 bytes/linhas a mais que o '
                    'estado 0160 local), e as âncoras multi-linha da 0161/0162 nunca tiveram `\r?\n` '
                    '(ao contrário da 0142/0143/0145/0160, que já tinham). Reproduzido nesta árvore: '
                    'o corpo do banco tdf_0160 convertido para CRLF reproduz a mensagem idêntica de '
                    'produção ao rodar a 0161. Sem âncora, sem regexp, sem position() sobre o corpo '
                    'antigo — cópia verbatim de pg_get_functiondef(tdf_0162), seguro aqui porque a '
                    '0162 é a migration mais nova do repositório (não há patch mais novo para '
                    'regredir). Reinstala, idempotente, os quatro requisitos da 0161/0162 que nunca '
                    'chegaram ao catálogo de produção (o insert delas morava depois do patch que '
                    'abortou), a view/fixture "Sonda 0162", e guarda o resultado da reemissão '
                    '(quatro marcadores + assinatura, normalizado contra CRLF) em vez de confiar. '
                    'Nenhum requisito NOVO de produto: o invariante já é o da 0161/0162, só o '
                    'caminho até o banco que muda. Nenhuma pendência já aberta foi tocada.'
 where id;

commit;

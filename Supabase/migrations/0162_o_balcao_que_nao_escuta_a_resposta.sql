-- =============================================================================
-- Migration 0162 — O BALCÃO DE PERGUNTAS RESPONDIA POR ELE MESMO, E A
-- RESPOSTA DO PRÓPRIO DOCUMENTO ERA JOGADA FORA.
--
-- A 0153 faz o certo na hora de ESCOLHER: quando um nome casa com DUAS
-- empresas do caso, `fn_upsert_entidade` não decide — cria uma entidade
-- PRÓPRIA com o nome bruto (um "balcão de perguntas", não uma empresa) e abre
-- pendência `entidade_incorreta` / `bloqueante` / `sobrepujavel = false`,
-- motivo `entidade_ambigua:<entidade_id>`, que TRAVA o Portão 2. O que
-- ninguém tinha visto: o PRÓPRIO documento pode responder essa pergunta
-- depois, quando o diagnóstico de conteúdo lê o texto e nomeia a empresa por
-- extenso — e a resposta era jogada fora sem deixar rastro em lugar nenhum.
--
-- MEDIDO NESTA ÁRVORE, no banco `tdf_test`, reproduzindo o arranjo da rodada
-- real `7417` (araucária, 03/09 — o documento `009`, classificado por NOME DE
-- ARQUIVO com 90% de confiança, travou o Portão 2 até o dono chamar
-- `fn_revisar_documento` à mão):
--
--   ENTIDADE REGISTRADA: Araucaria SPE
--   PENDÊNCIA APÓS REGISTRO: entidade_incorreta / bloqueante / sobrepujavel=f
--                            / aberta / motivo entidade_ambigua:<id>
--   PORTÃO 2: elegivel=false, bloqueantes_abertas=1
--
--   -- e então o diagnóstico de conteúdo do PRÓPRIO documento nomeia a
--   -- empresa por extenso:
--   fn_registrar_diagnostico(doc, ver, 'ARAUCÁRIA IMOBILIÁRIA SPE LTDA.', ...)
--   DIAGNÓSTICO: {"executado": true, "entidade_criada": false}
--   ENTIDADE DEPOIS DO DIAGNÓSTICO: Araucaria SPE       ← não mudou
--   PENDÊNCIA DEPOIS: entidade_incorreta / bloqueante / sobrepujavel=f /
--                     aberta                             ← intacta
--   PORTÃO 2 DEPOIS: elegivel=false                       ← continua fechado
--
-- A resposta não deixou rastro em lugar nenhum.
--
-- A CAUSA, medida em `Supabase/schema.sql`, `fn_registrar_diagnostico`, ramo
-- `else` de `if v_entidade_id is null`: o corpo vigente (0121) só sabe
-- responder "é a mesma empresa" (`fn_mesma_entidade` = true, resolve as
-- pendências de diagnóstico) ou "diverge" (0160 trata o caso em que o nome
-- diagnosticado é OUTRA empresa já cadastrada). Ele nunca perguntou se a
-- entidade JÁ REGISTRADA é, ela mesma, o balcão de perguntas da 0153 — e
--
--   fn_mesma_entidade('Araucaria SPE', 'ARAUCÁRIA BIOENERGIA SPE LTDA.')  → t
--   fn_mesma_entidade('Araucaria SPE', 'ARAUCÁRIA IMOBILIÁRIA SPE LTDA.') → t
--
-- O BALCÃO CASA COM TODO MUNDO POR CONSTRUÇÃO — foi criado exatamente porque
-- o nome dele casava com mais de uma empresa. Tratar esse casamento como
-- CONFIRMAÇÃO é o defeito: um sinal que continua respondendo depois de deixar
-- de significar o que promete, a família central deste projeto (ver
-- `.claude/memory/`). E, medido no mesmo banco, o nome que o CONTEÚDO do
-- documento traz resolve para EXATAMENTE UMA empresa já cadastrada, por
-- casamento EXATO — a mesma regra que o passo (1) de `fn_upsert_entidade`
-- (0153) já trata como decisiva ("não há o que desempatar"):
--
--   candidatas para 'Araucaria SPE'                   → Araucaria SPE (exata=t)
--                                                        ARAUCÁRIA BIOENERGIA SPE LTDA. (exata=f)
--                                                        ARAUCÁRIA IMOBILIÁRIA SPE LTDA. (exata=f)
--   candidatas para 'ARAUCÁRIA IMOBILIÁRIA SPE LTDA.' → ARAUCÁRIA IMOBILIÁRIA SPE LTDA. (exata=t)
--                                                        Araucaria SPE (exata=f)
--   EXATAS para o nome do conteúdo, excluído o balcão → 1
--
-- O QUE NÃO DÁ PARA PROVAR, escrito aqui em vez de fingido: não há o dado do
-- lote `7417` — não se sabe qual string exata o diagnóstico de conteúdo do
-- documento `009` devolveu. O arranjo do teste reproduz o PADRÃO medido em
-- produção (nome de arquivo ambíguo + conteúdo que nomeia a empresa por
-- extenso), com as duas razões sociais que a própria 0153 já cita como
-- medidas em produção — não os números exatos daquela chamada específica.
--
-- ---------------------------------------------------------------------------
-- O QUE ESTA MIGRATION FAZ
-- ---------------------------------------------------------------------------
--
-- (1) `fn_entidade_e_balcao_ambiguo(p_caso_id, p_entidade_id)` — predicado que
--     torna o balcão VISÍVEL: verdadeiro quando existe, para aquele caso,
--     pendência não resolvida com `motivo = 'entidade_ambigua:' ||
--     p_entidade_id` (a mesma que a 0153 abre). Pura o bastante para a sonda
--     EXERCITAR de verdade (item 4), em vez de procurar marcador de texto.
--
-- (2) `fn_registrar_diagnostico` para de aceitar o casamento contra o balcão
--     como confirmação. Antes de `if fn_mesma_entidade(...)`: se a entidade
--     registrada é um balcão ambíguo, o casamento não confirma nada — as
--     candidatas EXATAS do nome diagnosticado são recalculadas (reaproveitando
--     `fn_entidades_candidatas` da 0153, como a 0160 já fez), EXCLUÍDO o
--     próprio balcão. Com EXATAMENTE UMA, o documento respondeu à própria
--     pergunta: abre (ou atualiza) uma pendência POR DOCUMENTO
--     (`diagnostico:entidade_ambigua_respondida:<documento_id>`),
--     `entidade_incorreta` / `importante` / `sobrepujavel = true`, nomeando a
--     empresa e dizendo o que fazer. Com zero ou duas-ou-mais exatas, NÃO
--     abre nada — silêncio aqui é honesto (regra 1 do CLAUDE.md: ausência não
--     vira dado). E, em QUALQUER dos casos, o casamento contra o balcão NUNCA
--     resolve `diagnostico:entidade`/`diagnostico:entidade_grupo` — só o ramo
--     que compara contra uma entidade de VERDADE (o `else`, herdado sem
--     mudança nenhuma) resolve essas duas.
--
-- (3) A sonda: um requisito `corpo` (prova a fiação — quem chama quem), um
--     `funcao` para o predicado, e um `seed` que EXECUTA o predicado (item 4)
--     contra um fixture PERMANENTE e isolado (o "caso" `Sonda 0162`, que não
--     é mandato real e não aparece em nenhuma tela de produto).
--
-- ---------------------------------------------------------------------------
-- O QUE ESTA MIGRATION NÃO FAZ, E POR QUÊ
-- ---------------------------------------------------------------------------
--
-- **NÃO move o documento** para a empresa nomeada, e **NÃO chama
-- `fn_fundir_entidade`**. O dano de pôr o documento na empresa errada é
-- invisível — o balanço da empresa errada FECHA (cabeçalho da própria 0153).
-- A pergunta continua sendo do humano; o que muda é que ela chega
-- RESPONDIDA, em vez de mandar o revisor abrir o PDF.
--
-- **NÃO mexe em `severidade`, `sobrepujavel` nem no estado da pendência da
-- 0153**, e não a resolve. Afrouxar salvaguarda para destravar portão é
-- exatamente o que a 0127 existe para impedir — e o teste desta migration
-- prova isso com assert (a pendência bloqueante continua intacta e o Portão 2
-- continua fechado).
--
-- **NÃO aperta `fn_mesma_entidade`.** A frouxidão dela é deliberada (cabeçalho
-- da 0153): apertá-la trocaria "fundir empresas" por "partir a mesma empresa
-- em duas".
--
-- **NÃO afirma hierarquia, grupo, holding ou subsidiária.** Foi exatamente
-- isso que a revisão derrubou na primeira versão da 0160 — a função não sabe.
-- Diz só o que dá para medir: o conteúdo nomeia esta empresa, e ela é uma das
-- já cadastradas.
--
-- **NÃO reemite `fn_registrar_diagnostico` copiando texto de migration
-- antiga.** Ela foi patchada pela 0160 e pela 0161. Este arquivo aplica PATCH
-- POR ÂNCORA sobre o corpo VIGENTE (o que está em `Supabase/schema.sql`),
-- pela mesma razão da 0160/0161: reemitir de cópia velha regrediria os dois
-- patches em silêncio.
-- =============================================================================

-- =============================================================================
-- 1. O PREDICADO QUE TORNA O BALCÃO VISÍVEL
-- =============================================================================
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

-- =============================================================================
-- 2. `fn_registrar_diagnostico` — O CASAMENTO CONTRA O BALCÃO NÃO CONFIRMA NADA
-- =============================================================================
do $mig$
declare
  v_src text; v_novo text;
  v_pat constant text := $anchor162$      -- 0121: divergência de ENTIDADE medida pela forma canônica, como o
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
      end if;$anchor162$;
  v_rep constant text := $anchor162rep$      -- 0162: O CASAMENTO CONTRA O BALCÃO AMBÍGUO NÃO CONFIRMA NADA — ele foi
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
      end if;$anchor162rep$;
begin
  select pg_get_functiondef(p.oid) into v_src
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'fn_registrar_diagnostico';

  if v_src is null then
    raise exception '0162: fn_registrar_diagnostico não existe — migration fora de ordem';
  end if;

  if (length(v_src) - length(replace(v_src, v_pat, ''))) / greatest(length(v_pat), 1) <> 1 then
    raise exception '0162: o bloco de comparação de entidade (0121/0160 vigente) não foi encontrado UMA vez — este patch precisa ser relido por gente';
  end if;

  v_novo := replace(v_src, v_pat, v_rep);

  -- as quatro variáveis novas que o ramo do balcão usa.
  if (select count(*) from regexp_matches(v_novo, 'v_outros_nomes        text;')) <> 1 then
    raise exception '0162: âncora da declaração de variáveis não encontrada UMA vez';
  end if;
  v_novo := regexp_replace(v_novo,
    'v_outros_nomes        text;',
    E'v_outros_nomes        text;\n' ||
    E'  v_exatas_ambiguidade_n    int;\n' ||
    E'  v_exata_ambiguidade_nome  text;\n' ||
    E'  v_pendencia_ambigua_resp_id uuid;\n' ||
    E'  v_ambigua_resp_desc       text;');

  execute v_novo;

  -- Confere em vez de confiar.
  select pg_get_functiondef(p.oid) into v_src
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'fn_registrar_diagnostico';
  if position('0162: O CASAMENTO CONTRA O BALCÃO AMBÍGUO' in v_src) = 0 then
    raise exception '0162: a função foi recriada sem o ramo do balcão ambíguo — abortado';
  end if;
  if position('0142: exige divergência ACIONÁVEL' in v_src) = 0 then
    raise exception '0162: o patch apagou o da 0142 — abortado';
  end if;
  if position('0160: o nome que não casou' in v_src) = 0 then
    raise exception '0162: o patch apagou o da 0160 — abortado';
  end if;
  if position('registrado com "%s %s"). %s' in v_src) = 0 then
    raise exception '0162: o patch apagou o da 0161 — abortado';
  end if;
end $mig$;

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
  '(excluído o balcão), abre pendência nomeando a resposta, sem mover o documento nem fundir.';

grant execute on function fn_registrar_diagnostico(uuid, uuid, text, boolean, text, text, text, legibilidade, text, text, text) to authenticated;

-- =============================================================================
-- 3. A SONDA — FIXTURE PERMANENTE E ISOLADO PARA EXERCITAR O PREDICADO
-- =============================================================================
--
-- Um "caso" que NÃO é mandato real — nome com prefixo `Sonda 0162`, para não
-- se confundir com nada em produção — com IDs fixos, literais, para o
-- predicado ser exercitado de verdade (achado D da revisão da 0157: marcador
-- textual não pega um `false and` que mata o predicado e deixa os comentários
-- intactos; só quem EXECUTA o predicado pega). Três entidades: uma com
-- pendência `entidade_ambigua` ABERTA (é o balcão), uma sem pendência nenhuma
-- (entidade normal) e uma com a MESMA pendência já RESOLVIDA (prova que
-- resolvida não conta como balcão).
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

-- =============================================================================
-- 4. O CATÁLOGO DA SONDA
-- =============================================================================
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
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

update instalacao_cobertura
   set ate_migration = '0162',
       revisado_em = date '2026-09-09',
       observacao = 'Revisão de 09/09/2026: a 0162 corrige fn_registrar_diagnostico para não tratar '
                    'o casamento contra o BALCÃO AMBÍGUO da 0153 como confirmação de entidade — o '
                    'balcão casa com todo mundo por construção (foi criado porque o nome dele casava '
                    'com mais de uma empresa). Quando o nome diagnosticado casa EXATO com '
                    'exatamente UMA empresa já cadastrada no caso (excluído o balcão), abre '
                    'pendência POR DOCUMENTO nomeando a resposta, sem mover o documento nem fundir '
                    'entidades, e sem tocar a pendência bloqueante da 0153. Reproduzido o padrão do '
                    'lote 7417 (araucária, 03/09) com as duas razões sociais que a própria 0153 já '
                    'mede como reais. Três requisitos novos: a fiação (corpo), o predicado (função) '
                    'e a regra viva (seed, EXECUTADA contra fixture permanente e isolado — achado D '
                    'da revisão da 0157, sem o qual um `false and` no predicado passaria despercebido '
                    'pelos requisitos de corpo/função).'
 where id;

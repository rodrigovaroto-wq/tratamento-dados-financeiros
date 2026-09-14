-- =============================================================================
-- 0172 — O CNPJ pelo caminho que roda SEMPRE
--
-- A 0170 fez o CNPJ atravessar `fn_registrar_documento`, e a fatia do n8n o fez
-- ser lido na chamada de CLASSIFICAÇÃO. A revisão do diff achou o buraco: essa
-- chamada **só roda no ramo de fallback**, quando o nome do arquivo não resolve
-- tipo+período com confiança ≥ 0,70 (`Precisa Fallback?`). MEDIDO no book que o
-- repositório versiona: **19 de 38 documentos** do `book-canastra` passam por
-- ela — os outros 19 chegariam ao banco com `cnpj` NULO, e nenhum sintoma
-- apareceria: a identidade continuaria sendo o nome, exatamente como antes, na
-- metade do lote.
--
-- O CAMINHO QUE RODA SEMPRE é o do DIAGNÓSTICO. A chamada de extração é a única
-- leitura de conteúdo garantida para TODO documento — é ela que devolve
-- `diagnostico.entidade`, e é por ela que os nomes contaminados (o endereço
-- colado da OMNIBEAUTY) NASCEM. `fn_registrar_diagnostico` (0010, reemitida
-- pela 0163) já chama `fn_upsert_entidade` com esse nome — com DOIS argumentos,
-- deixando o CNPJ de fora.
--
-- ESTA MIGRATION acrescenta `p_cnpj text default null` e o repassa. Nada mais:
-- o corpo é reemitido INTEIRO, verbatim do `Supabase/schema.sql` vigente, com
-- DUAS mudanças e nenhuma outra (a assinatura e a linha da chamada). Nunca por
-- patch de âncora — `.claude/memory/nunca-corrigir-funcao-por-replace.md`, e o
-- incidente de CRLF que a 0163 teve de consertar exatamente nesta função.
--
-- POR QUE OS DOIS CAMINHOS, e não só este: a classificação chega ANTES (é ela
-- que cria a entidade no `fn_registrar_documento`), então o CNPJ que ela lê
-- evita a entidade nascer com o nome errado. O diagnóstico chega depois e cobre
-- os 100%. Os dois escrevem no mesmo lugar pela mesma função, e a regra de
-- aprendizado da 0169 (nunca sobrescreve CNPJ já gravado) faz a ordem não
-- importar.
--
-- A ARMADILHA DO OVERLOAD, pela terceira vez nesta série e pelo mesmo motivo:
-- com a de 11 argumentos viva ao lado da de 12, a chamada do n8n casa com
-- AMBAS e o Postgres recusa com "function is not unique" no meio de um lote.
-- Daí o `drop function` explícito com a assinatura antiga por extenso.
--
-- Idempotente: `drop ... if exists` + `create or replace`.
-- =============================================================================

begin;

drop function if exists fn_registrar_diagnostico(
  uuid, uuid, text, boolean, text, text, text, legibilidade, text, text, text
);

create or replace function fn_registrar_diagnostico(p_documento_id uuid, p_documento_versao_id uuid, p_entidade_nome text, p_tipo_confirma boolean, p_tipo_sugerido text, p_periodo_tipo text, p_periodo_referencia text, p_legibilidade public.legibilidade, p_nota_legibilidade text, p_resumo text, p_justificativa text, p_cnpj text DEFAULT NULL::text) RETURNS jsonb
language plpgsql
as $$
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
      v_entidade_id := fn_upsert_entidade(v_caso_id, p_entidade_nome, p_cnpj);
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
$$;
comment on function fn_registrar_diagnostico(uuid, uuid, text, boolean, text, text, text, legibilidade, text, text, text, text) is
  'Registra o diagnóstico de conteúdo (E1/E2) e confere contra o que já está no banco — ver o '
  'histórico de 0121/0142/0160/0161/0162/0163 no comentário da 0163. 0172: recebe o CNPJ lido do '
  'CONTEÚDO e o repassa a fn_upsert_entidade. É o caminho que roda para TODO documento: a '
  'classificação por conteúdo só roda no fallback (19 de 38 no book-canastra), então sem este fio '
  'metade do lote chegaria sem identidade fiscal e sem sintoma nenhum.';

-- -----------------------------------------------------------------------------
-- O CATÁLOGO DA SONDA — requisito de CORPO sobre a chamada com três argumentos.
--
-- O marcador é a CHAMADA, não o nome da função chamada: `fn_upsert_entidade`
-- está no corpo desde a 0121, então procurá-lo passaria num banco que nunca
-- aplicou esta migration.
-- -----------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('cnpj_no_diagnostico', '0172', 'corpo', 'fn_registrar_diagnostico',
   'p_entidade_nome, p_cnpj', null,
   'Sem esta migration o CNPJ só chega ao banco pelos documentos que passam pela classificação '
   'por conteúdo — o ramo de fallback, que roda quando o NOME DO ARQUIVO não resolve tipo+período '
   'com confiança suficiente. Medido no book-canastra versionado: 19 de 38 documentos. Os outros '
   '19 chegariam com cnpj NULO e nenhum sintoma: a identidade continuaria sendo o nome, na metade '
   'do lote, com todo o código de identidade instalado e metade dele nunca executado.',
   'bloqueante', 700)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0172', revisado_em = current_date,
       observacao = 'A 0172 reemite fn_registrar_diagnostico INTEIRA (11 → 12 args, com DROP da '
                    'de 11: overload vivo derruba lote real com "function is not unique"). '
                    'Requisito de corpo pela CHAMADA de três argumentos, não pelo nome da função '
                    'chamada — o nome está lá desde a 0121 e o requisito nasceria vazio.';

commit;

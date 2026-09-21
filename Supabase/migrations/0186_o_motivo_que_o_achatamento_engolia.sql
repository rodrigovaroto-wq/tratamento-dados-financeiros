-- =============================================================================
-- 0186 — O MOTIVO QUE O ACHATAMENTO ENGOLIA
--
-- O DEFEITO, medido contra produção (somente leitura, `ESTADO.md` 21/09/2026):
-- `fonte_a`/`fonte_b` vêm as DUAS nulas em 1.922 das 1.926 linhas de
-- `reconciliacao` com `precondicoes_ok = false`, e ~278 desses pares
-- caso×entidade são de casos onde a CONTRAPARTE NEM EXISTE. A fila de
-- pendências não distingue isso de "o documento veio e a linha não foi
-- localizada" — os dois casos chegam ao analista com o mesmo texto,
-- `precondicao_nao_satisfeita`, e remédios OPOSTOS: um se resolve cobrando o
-- cliente pelo checklist do Kit Básico, o outro se resolve olhando o
-- localizador ou a extração. Sem o motivo, cada pendência dessas exige uma
-- investigação forense — é o que trava a fase inteira, porque a fila deixa de
-- ser acionável.
--
-- A CAUSA, lida em `fn_registrar_reconciliacao` (0023, corpo vigente na
-- 0127): a função já sabe a diferença — quem chama passa `'documento_ausente'`
-- quando a contraparte não existe, e passa `'precondicao_nao_satisfeita'` (ou
-- um motivo mais fino, numa fatia futura) quando o documento está lá e algo
-- não foi localizado — e ACHATA os dois na hora de gravar:
--
--     v_res_log := case when p_resultado = 'documento_ausente'
--                       then 'precondicao_nao_satisfeita' else p_resultado end;
--
-- O motivo original não SOME — ele sobrevive em `evento_auditoria`, no
-- `depois->>'resultado'` do evento `reconciliacao_<tipo>` que a própria função
-- grava no fim, com `entidade_ref = 'reconciliacao:' || v_reconciliacao_id`.
-- Mas ninguém lê `evento_auditoria` para montar a fila — é trilha de
-- auditoria, não é onde uma tela de pendências vai procurar.
--
-- O QUE ESTA MIGRATION FAZ, e o que ela DELIBERADAMENTE não faz.
--
--   1. `reconciliacao.motivo_precondicao` — coluna nova, nullable. Guarda o
--      motivo VERDADEIRO quando a precondição falha; fica NULL quando a
--      checagem concluiu (`ok`/`divergente`/`zona_cinzenta`).
--   2. `fn_registrar_reconciliacao` reemitida inteira (nunca corrigida por
--      replace de texto — `.claude/memory/nunca-corrigir-funcao-por-replace.md`),
--      com UMA mudança de comportamento: grava `motivo_precondicao` a partir
--      do `p_resultado` ORIGINAL, antes do achatamento.
--   3. Backfill de `evento_auditoria` para as linhas já gravadas.
--   4. Catálogo da sonda.
--
-- **`resultado` NÃO MUDA DE VOCABULÁRIO — isto é inegociável.** Continua
-- gravando `precondicao_nao_satisfeita` exatamente como hoje, porque portal,
-- export, suítes e medidores já leem essa string. É `motivo_precondicao` que
-- passa a carregar a distinção; `resultado` continua respondendo só "concluiu
-- ou não".
--
-- E `v_divergente := p_resultado not in ('ok', 'documento_ausente')` — a linha
-- que decide se abre pendência — NÃO MUDA UMA VÍRGULA. `documento_ausente`
-- continua NÃO abrindo pendência (é cobrança do checklist do Kit Básico, não
-- da fila de revisão — regra herdada da 0023 e reafirmada na 0127). Qualquer
-- motivo novo que uma fatia futura vier a passar (ver o CONTRATO abaixo) cai,
-- por essa mesma linha, do lado de ABRE pendência — que é o comportamento
-- seguro por default: motivo desconhecido é tratado como achado acionável,
-- nunca como ausência silenciosa.
--
-- O CONTRATO — a lista de motivos que o achatamento reconhece hoje.
-- `v_res_log` deixa de testar só `= 'documento_ausente'` e passa a testar
-- `= any(v_motivos_precondicao)`, um array documentado aqui para a checagem
-- individual (`fn_reconciliar_*`) poder, numa fatia futura, passar um motivo
-- mais específico sem que nada a jusante quebre — `resultado` continua saindo
-- `precondicao_nao_satisfeita` para qualquer um deles:
--
--   'documento_ausente'      — a contraparte não foi entregue. NÃO abre
--                               pendência (checklist do Kit Básico cobra).
--   'precondicao_nao_satisfeita' — hoje é o único outro valor que as funções
--                               de checagem realmente emitem: documento
--                               presente, mas ela não especificou qual
--                               localizador/eixo falhou. É honesto gravar o
--                               próprio valor em `motivo_precondicao` — "a
--                               função não detalhou o motivo" é informação,
--                               não lacuna. ABRE pendência (documento
--                               presente é achado acionável).
--   'linha_nao_localizada'   — RESERVADO para a fatia seguinte: documento
--                               presente, rótulo não bateu com nenhum
--                               localizador. ABRE pendência (mesmo remédio de
--                               'precondicao_nao_satisfeita' hoje — só o rótulo
--                               na tela fica mais preciso).
--   'unidade_divergente'     — RESERVADO: as duas pontas têm valor, mas a
--                               escala não é conversível
--                               (`fn_motivo_escala_incomparavel`). ABRE
--                               pendência.
--   'sem_periodo_par'        — RESERVADO: nenhum dos anos/períodos do
--                               documento tem contraparte comparável. ABRE
--                               pendência.
--
-- Nenhuma função de checagem passa os três reservados ainda — isso é a fatia
-- seguinte, e ela fica barata porque esta aqui já abre o caminho: quando ela
-- passar `'linha_nao_localizada'`, por exemplo, `motivo_precondicao` já vai
-- gravar o valor certo sem tocar em `fn_registrar_reconciliacao` de novo. Até
-- lá, listá-los aqui sem uso é o CONTRATO ficando escrito antes do primeiro
-- consumidor — não é código morto, é o combinado.
--
-- O BACKFILL — alcance medido no banco de TESTE, não em produção.
--
-- Neste banco (`run.sh`, migrations aplicadas do zero, ANTES de qualquer
-- fixture carregada), `reconciliacao` está vazia no instante em que esta
-- migration roda — nenhuma migration anterior semeia essa tabela. O UPDATE
-- abaixo mede e afeta ZERO linhas aqui, e é isso mesmo: o teste que prova o
-- comportamento (`reconciliacao_motivo_precondicao.test.sql`) exercita a
-- COSTURA REAL (registrar documento → extrair → reconciliar), não este
-- backfill. **O alcance em PRODUÇÃO é desconhecido e não foi medido** — a
-- lição da 0179 (`.claude/memory/aplicar-migration-em-producao-pela-api.md`,
-- 365 pendências onde se previam 13) é que quem aplica mede o `where` ANTES,
-- contra o banco real, com uma consulta somente leitura equivalente a:
--
--     select count(*) from reconciliacao
--      where precondicoes_ok = false and motivo_precondicao is null;
--
-- e só então decide se o backfill é seguro de rodar como está ou precisa de
-- lote.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- (1) A COLUNA NOVA
-- -----------------------------------------------------------------------------

alter table reconciliacao
  add column if not exists motivo_precondicao text;

comment on column reconciliacao.motivo_precondicao is
  'O motivo VERDADEIRO quando resultado = precondicao_nao_satisfeita; NULL quando a checagem '
  'concluiu. Existe porque resultado achata estados com remédios OPOSTOS no mesmo texto '
  '(documento_ausente cobra o cliente pelo checklist; linha não localizada pede olhar o '
  'localizador ou a extração) — resultado não pode carregar essa distinção sem quebrar quem já '
  'lê essa coluna (portal, export, suítes, medidores). Ver o CONTRATO no cabeçalho da 0186 para '
  'a lista de valores reconhecidos.';

-- -----------------------------------------------------------------------------
-- (2) fn_registrar_reconciliacao — REEMITIDA INTEIRA (corpo da 0127), com a
-- única mudança de comportamento sendo a gravação de motivo_precondicao. Ver
-- o marcador `motivo_precondicao` no ponto exato da mudança.
-- -----------------------------------------------------------------------------
create or replace function fn_registrar_reconciliacao(
  p_caso_id       uuid,
  p_entidade_id   uuid,
  p_periodo_id    uuid,
  p_tipo          text,
  p_classe        text,
  p_documento_id  uuid,
  p_fonte_a       jsonb,
  p_fonte_b       jsonb,
  p_resultado     text,
  p_divergencia_abs numeric,
  p_divergencia_pct numeric,
  p_materialidade jsonb,
  p_descricao     text
)
returns jsonb
language plpgsql
as $$
declare
  v_reconciliacao_id uuid;
  v_pendencia_id     uuid;
  v_motivo           text := 'reconciliacao:' || p_tipo;
  -- 0186: O CONTRATO — todo motivo que o achatamento reconhece como "a
  -- checagem não concluiu". `resultado` sai `precondicao_nao_satisfeita` para
  -- QUALQUER um destes; o valor ORIGINAL vai para `motivo_precondicao` (ver
  -- abaixo). Só 'documento_ausente' e 'precondicao_nao_satisfeita' têm
  -- emissor hoje — os outros três são o contrato reservado para a fatia
  -- seguinte, documentado no cabeçalho desta migration.
  v_motivos_precondicao text[] := array[
    'documento_ausente', 'precondicao_nao_satisfeita',
    'linha_nao_localizada', 'unidade_divergente', 'sem_periodo_par'
  ];
  -- 'documento_ausente' é um resultado NOSSO, para decidir a pendência; no log
  -- ele é gravado como pré-condição não satisfeita (é o que ele é).
  v_res_log          text := case when p_resultado = any(v_motivos_precondicao)
                                  then 'precondicao_nao_satisfeita' else p_resultado end;
  -- motivo_precondicao: o valor ORIGINAL, antes do achatamento acima — NULL
  -- quando a checagem concluiu (v_res_log não é 'precondicao_nao_satisfeita').
  -- Quando p_resultado já chega como 'precondicao_nao_satisfeita' (a função de
  -- checagem não detalhou o motivo), grava esse mesmo valor: é honesto — "sem
  -- motivo específico" é informação, não lacuna.
  v_motivo_precondicao text := case when v_res_log = 'precondicao_nao_satisfeita'
                                     then p_resultado else null end;
  -- 0127: a decisão passa para o corpo, porque agora ela depende do DIAL da
  -- classe — e o dial não se lê no declare sem esconder a regra.
  --
  -- 0186: ESTA LINHA NÃO MUDA. `documento_ausente` continua sendo o ÚNICO
  -- motivo de precondição que NÃO abre pendência — é cobrança do checklist do
  -- Kit Básico, não achado de revisão (0023, reafirmado pela 0127). Qualquer
  -- motivo novo do array acima que não seja 'documento_ausente' cai do lado
  -- de ABRE pendência por esta mesma linha, sem precisar tocá-la: documento
  -- presente e algo não localizado é sempre achado acionável, mesmo quando o
  -- motivo específico ainda não existe (default seguro).
  v_divergente       boolean := p_resultado not in ('ok', 'documento_ausente');
  v_abre_pendencia   boolean;
  v_estagio_dial     text;
  v_influencia       boolean;
begin
  -- 0127: O DIAL DA CLASSE DECIDE SE O ACHADO CHEGA À FILA DE ALGUÉM.
  --
  -- `reconciliacao_classe_bc` declarava N0 — "roda, registra a saída, mas NÃO
  -- influencia decisão" (Arquitetura do Sistema/1 Visão e Doutrina/01) — e abria pendência: as checagens B passam 'B'
  -- para cá e esta função nunca olhou a classe. Pendência entra na fila do painel
  -- e é contada na avaliação do Portão 2; isso é influenciar. O comportamento era
  -- N1, que é o teto dela — não era inseguro, era MAL DECLARADO.
  --
  -- Note que o registro em `reconciliacao` acontece SEMPRE, inclusive em N0: "roda
  -- e registra" é a primeira metade da definição de sombra, e é ela que permite
  -- medir um estágio antes de confiar nele.
  v_estagio_dial := case when upper(coalesce(p_classe, 'A')) = 'A'
                         then 'reconciliacao_classe_a'
                         else 'reconciliacao_classe_bc' end;
  v_influencia := fn_dial_influencia(v_estagio_dial);
  v_abre_pendencia := v_divergente and v_influencia;

  insert into reconciliacao
    (caso_id, entidade_id, periodo_id, tipo, classe, fonte_a, fonte_b,
     precondicoes_ok, resultado, motivo_precondicao, divergencia_abs, divergencia_pct, materialidade)
  values (
    p_caso_id, p_entidade_id, p_periodo_id, p_tipo, p_classe, p_fonte_a, p_fonte_b,
    v_res_log <> 'precondicao_nao_satisfeita', v_res_log, v_motivo_precondicao,
    p_divergencia_abs, p_divergencia_pct, p_materialidade
  )
  returning id into v_reconciliacao_id;

  select id into v_pendencia_id from pendencia
  where caso_id = p_caso_id and motivo = v_motivo
    and coalesce(entidade_id, '00000000-0000-0000-0000-000000000000'::uuid)
      = coalesce(p_entidade_id, '00000000-0000-0000-0000-000000000000'::uuid)
    -- Período COMPATÍVEL, não igual: a mesma checagem chega por dois documentos
    -- com granularidade diferente (DRE "multi 24,25" × Faturamento "L24M") e sem
    -- isso o mesmo achado abriria duas pendências.
    and (periodo_id is not distinct from p_periodo_id
         or fn_periodos_compativeis(periodo_id, p_periodo_id))
    and estado <> 'resolvida'
  order by criada_em
  limit 1;

  if v_abre_pendencia then
    if v_pendencia_id is null then
      insert into pendencia
        (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao,
         documento_id, entidade_id, periodo_id, motivo)
      values (
        p_caso_id, 'reconciliacao',
        case when v_res_log = 'precondicao_nao_satisfeita' then 'precondicao_nao_satisfeita'
             else 'divergencia_reconciliacao' end::pendencia_tipo,
        'importante', true, p_descricao, p_documento_id, p_entidade_id, p_periodo_id, v_motivo
      )
      returning id into v_pendencia_id;
    else
      update pendencia set descricao = p_descricao where id = v_pendencia_id;
    end if;
  elsif v_divergente and not v_influencia then
    -- 0127: SOMBRA COM DIVERGÊNCIA PRESENTE — e este ramo existe para não mentir.
    --
    -- Sem ele, este caso cairia no `elsif` de baixo e a pendência aberta seria
    -- marcada "resolvida por sistema:reconciliacao". Mas o sintoma NÃO sumiu: o
    -- estágio foi silenciado. Resolver aqui escreveria na trilha que o problema
    -- acabou, quando o que acabou foi o direito daquele estágio de falar — e a
    -- trilha é append-only justamente para não permitir esse tipo de reescrita.
    --
    -- Então: registra em sombra, e deixa em paz a pendência que um humano já pode
    -- estar tratando.
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values ('sistema:reconciliacao', 'reconciliacao_em_sombra',
              'reconciliacao:' || v_reconciliacao_id,
              jsonb_build_object('estagio', v_estagio_dial, 'classe', p_classe,
                                 'tipo', p_tipo, 'resultado', p_resultado,
                                 'divergencia_abs', p_divergencia_abs,
                                 'pendencia_preexistente', v_pendencia_id,
                                 'porque', 'estagio em N0: registra e nao abre pendencia (Arquitetura do Sistema/1 Visão e Doutrina/01). '
                                           'Pendencia anterior, se existe, NAO foi resolvida: o '
                                           'sintoma nao sumiu, o estagio foi silenciado.'));

  elsif v_pendencia_id is not null then
    -- Sumiu o sintoma (reextração corrigiu, ou a pendência era falsa e a regra
    -- nova não a emite mais): fecha. Não escreve número nenhum em base viva.
    update pendencia set estado = 'resolvida', resolvida_em = now(),
           resolvida_por = 'sistema:reconciliacao'
    where id = v_pendencia_id;
    v_pendencia_id := null;
  end if;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:reconciliacao', 'reconciliacao_' || p_tipo,
            'reconciliacao:' || v_reconciliacao_id,
            jsonb_build_object('resultado', p_resultado, 'divergencia_abs', p_divergencia_abs));

  return jsonb_build_object(
    'reconciliacao_id', v_reconciliacao_id, 'tipo', p_tipo,
    'resultado', p_resultado, 'pendencia_id', v_pendencia_id
  );
end;
$$;
-- Sem `grant` aqui de propósito: fn_registrar_reconciliacao nunca foi exposta ao
-- portal — ela é chamada só por outras funções SQL, e o schema materializado
-- confirma que ela não tem grant. Acrescentar um mudaria o dump sem motivo.

-- -----------------------------------------------------------------------------
-- (3) BACKFILL — recupera de evento_auditoria o motivo das linhas já gravadas
-- com precondição falha. Ver a medição de alcance no cabeçalho: NESTE banco
-- (recém-migrado, sem fixture) o `where` não bate linha nenhuma — é o
-- resultado esperado, não um bug do UPDATE. Quem aplica em produção mede o
-- `where` antes, contra o banco real (consulta no cabeçalho).
-- -----------------------------------------------------------------------------
with alvo as (
  select r.id, ea.depois->>'resultado' as motivo_original
  from reconciliacao r
  join evento_auditoria ea
    on ea.entidade_ref = 'reconciliacao:' || r.id
   and ea.ator = 'sistema:reconciliacao'
   and ea.acao = 'reconciliacao_' || r.tipo
  where r.precondicoes_ok = false
    and r.motivo_precondicao is null
)
update reconciliacao r
   set motivo_precondicao = a.motivo_original
  from alvo a
 where r.id = a.id
   and a.motivo_original is not null;

-- -----------------------------------------------------------------------------
-- (4) O CATÁLOGO DA SONDA
-- -----------------------------------------------------------------------------

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values

  ('reconciliacao_motivo_precondicao_existe', '0186', 'coluna', 'reconciliacao.motivo_precondicao',
   null, null,
   'Sem a coluna, resultado = precondicao_nao_satisfeita continua achatando "contraparte não '
   'entregue" (não é achado, é cobrança do checklist) e "documento veio e a linha não foi '
   'localizada" (é achado, pede revisão) no mesmo texto — 1.922 das 1.926 linhas assim medidas '
   'em produção, remédios opostos indistinguíveis na fila.',
   'importante', 780),

  ('fn_registrar_reconciliacao_grava_motivo', '0186', 'corpo', 'fn_registrar_reconciliacao',
   'motivo_precondicao', null,
   'A coluna existe mas fn_registrar_reconciliacao é a homônima de ANTES da 0186: continua '
   'achatando o motivo original sem gravá-lo em canto nenhum acessível à fila — a distinção some '
   'de novo, silenciosamente, mesmo com a coluna presente no schema.',
   'bloqueante', 781)

on conflict (chave) do update
  set migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
      marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
      porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0186', revisado_em = current_date,
       observacao = 'A 0186 acrescenta reconciliacao.motivo_precondicao e reemite '
                    'fn_registrar_reconciliacao para gravá-la (corpo da 0127 + uma mudança de '
                    'comportamento). resultado NÃO muda de vocabulário — só motivo_precondicao '
                    'passa a existir. O requisito de corpo usa o marcador motivo_precondicao, '
                    'que aparece na lista de colunas do INSERT; um banco com a coluna mas com a '
                    'função de antes da 0186 falha esse requisito e não o de coluna, que é a '
                    'distinção que importa para quem lê o painel.';

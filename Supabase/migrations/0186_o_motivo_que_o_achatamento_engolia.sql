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
-- 0127): quem chama passa DOIS literais distintos — `'documento_ausente'` e
-- `'precondicao_nao_satisfeita'` — e a função ACHATA os dois num só na hora de
-- gravar. O que cada literal significa está no CONTRATO abaixo, e NÃO é o que
-- a intuição sugere: nenhum dos dois prova presença ou ausência de documento.
-- (Esta frase já esteve errada aqui, dizendo que `precondicao_nao_satisfeita`
-- significava "o documento está lá" — a revisão independente derrubou, e a
-- correção da correção derrubou também a simétrica sobre `documento_ausente`.)
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
--   'documento_ausente'      — o que ele GARANTE é só uma coisa: NÃO abre
--                               pendência. Ele NÃO prova que a contraparte
--                               deixou de ser entregue, e quem construir tela
--                               sobre isso vai mandar cobrar documento que o
--                               cliente já entregou. Medido: `fn_reconciliar_arvore`
--                               (0133:371) o emite com `p_documento_id` NÃO-NULO
--                               ("este documento não tem seção com filhos") e
--                               `fn_reconciliar_mutuos` (0123) o emite com a
--                               planilha de mútuos PRESENTE — 42 linhas de
--                               `secao_fecha` e 9 de `mutuos_planilha_vs_balanco`
--                               no banco de teste, com o documento lá.
--   'precondicao_nao_satisfeita' — CORRIGIDO após revisão independente, que
--                               achou este trecho descrevendo errado o que o
--                               próprio valor significa (regra 1, invertida:
--                               afirmar presença que não foi medida). Como
--                               MOTIVO (o que fica em `motivo_precondicao`,
--                               nunca em `resultado`), este valor significa
--                               só "o emissor não especificou o motivo" — NADA
--                               MAIS. É o que as funções de checagem de hoje
--                               passam direto quando não detalham qual
--                               localizador/eixo falhou; mas é TAMBÉM o que o
--                               legado (0009/0022 de fn_reconciliar_ativo_-
--                               passivo_pl, antes da reescrita da 0023) usava
--                               tanto para "nenhum Balanço classificado para
--                               esta entidade/período" (documento
--                               REALMENTE ausente) quanto para "documento
--                               presente, Ativo Total não localizado" — o
--                               MESMO literal para os dois. Por isso este
--                               valor NÃO AUTORIZA concluir que o documento
--                               estava presente — nem hoje, e principalmente
--                               não nas linhas que o BACKFILL grava a partir
--                               de `evento_auditoria` antigo, onde a origem é
--                               exatamente esse legado achatado na fonte. ABRE
--                               pendência por default (ver `v_abre_pendencia`
--                               abaixo) não porque o documento certamente
--                               estava lá, mas porque motivo não especificado
--                               é tratado como achado acionável até prova em
--                               contrário — a mesma regra que os três
--                               reservados abaixo herdam.
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
-- E O VOCABULÁRIO É UMA GUARDA DURA, NÃO UM COMENTÁRIO: `p_resultado` fora da
-- lista levanta exceção. Isso fecha o buraco que a revisão independente mediu
-- (um literal com UMA letra trocada fazia `precondicoes_ok` virar TRUE — a
-- coluna que é o denominador de toda a medição desta fase). Mas a guarda tem
-- um custo que quem aplicar precisa pesar ANTES: a reconciliação roda dentro
-- do fluxo de ingestão e não há `exception when others` em ponto nenhum desse
-- caminho, então um valor inesperado deixa de ser dado errado em silêncio e
-- passa a ABORTAR a transação do caso. O vocabulário foi levantado varrendo o
-- repositório e conferido contra o banco de teste (os valores realmente
-- emitidos no histórico são 6, todos dentro da lista) — mas produção é o único
-- lugar onde uma função criada fora do repositório apareceria. A consulta que
-- fecha isso é somente leitura, roda ANTES do apply, e está no
-- `Supabase/README.md`, item (c) do bloco desta migration. Valor fora da lista
-- lá = NÃO APLICAR.
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
-- 365 pendências onde se previam 13) é que quem aplica mede ANTES, contra o
-- banco real.
--
-- CORRIGIDO após revisão independente: a consulta que este cabeçalho mandava
-- rodar ANTES do apply usava `motivo_precondicao` — coluna que esta MESMA
-- migration cria. Rodada antes do `alter table`, ela dá
-- `ERROR: column "motivo_precondicao" does not exist`, e quem toma esse erro
-- aplica sem medir (o passo que a 0179 custou caro). As duas consultas abaixo
-- RODAM ANTES do apply, somente leitura:
--
--   -- (a) o total que esta migration mexe:
--   select count(*) from reconciliacao where precondicoes_ok = false;
--
--   -- (b) quantas o backfill alcançaria e quantas ficariam de fora, por tipo
--   -- (mesma junção do UPDATE abaixo, inclusive o de-para de
--   -- caixa_bp_vs_fluxo → caixa_bp_fluxo — ver o comentário na seção (3)):
--   select r.tipo,
--          count(*) as total,
--          count(ea.id) as alcancaria_o_backfill,
--          count(*) filter (where ea.id is null) as ficaria_null
--     from reconciliacao r
--     left join evento_auditoria ea
--       on ea.entidade_ref = 'reconciliacao:' || r.id
--      and ea.ator = 'sistema:reconciliacao'
--      and ea.acao = 'reconciliacao_' ||
--          case when r.tipo = 'caixa_bp_vs_fluxo' then 'caixa_bp_fluxo' else r.tipo end
--    where r.precondicoes_ok = false
--    group by r.tipo
--    order by 1;
--
-- E não há "rodar como está ou em lote" para escolher em tempo de apply: o
-- backfill é um único UPDATE dentro DESTE arquivo, aplicado inteiro por
-- `supabase db execute --file` — não existe um modo de aplicar só uma parte.
-- Se a consulta (b) mostrar um alcance grande demais para rodar de uma vez,
-- a única forma de "ir em lote" é editar o ARQUIVO da migration antes de
-- aplicar (por exemplo, acrescentando um `limit`/filtro ao UPDATE) — não uma
-- escolha que a migration ofereça em si.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- (1) A COLUNA NOVA
-- -----------------------------------------------------------------------------

alter table reconciliacao
  add column if not exists motivo_precondicao text;

comment on column reconciliacao.motivo_precondicao is
  'O motivo que o emissor passou ANTES do achatamento de resultado, quando a checagem NÃO '
  'concluiu; NULL quando concluiu (ok/divergente/divergencia/zona_cinzenta). NENHUM DOS DOIS '
  'MOTIVOS PROVA PRESENÇA OU AUSÊNCIA DE DOCUMENTO, e quem construir tela sobre esta coluna '
  'precisa saber disso. documento_ausente NÃO é confiável como "a contraparte não foi '
  'entregue": fn_reconciliar_arvore (0133) o emite com documento_id NÃO-NULO para "este '
  'documento não tem seção com filhos", e fn_reconciliar_mutuos (0123) o emite para "planilha '
  'de mútuos presente, mas nenhum balanço traz conta de mútuo com lado reconhecível" — nos dois '
  'o documento FOI entregue. Medido no banco de teste: 42 linhas de secao_fecha e 9 de '
  'mutuos_planilha_vs_balanco com este motivo e documento presente. O que documento_ausente '
  'garante é só o que o código faz com ele: NÃO abre pendência. precondicao_nao_satisfeita como MOTIVO significa '
  'apenas "o emissor não especificou o motivo" — NÃO AUTORIZA concluir que o documento estava '
  'presente: é o mesmo literal que o legado (0009/0022, antes da reescrita da 0023 de '
  'fn_reconciliar_ativo_passivo_pl) usava tanto para documento ausente quanto para documento '
  'presente com linha não localizada, e é esse literal que o backfill grava a partir de '
  'evento_auditoria para as linhas antigas. Ver o CONTRATO no cabeçalho da 0186 para a lista '
  'completa de valores reconhecidos.';

-- -----------------------------------------------------------------------------
-- (2) fn_registrar_reconciliacao — REEMITIDA INTEIRA (corpo da 0127), com
-- duas mudanças de comportamento: a gravação de motivo_precondicao, e a
-- validação de vocabulário do achado 1 (ver comentário logo após `begin`).
-- O marcador que a sonda usa (catálogo, seção 4) é `, v_motivo_precondicao,`
-- — a lista de VALUES do INSERT, não a lista de colunas nem os comentários,
-- porque é o único ponto cujo texto muda de verdade se alguém trocar a
-- gravação por `null` (CORRIGIDO após revisão: o marcador antigo, a palavra
-- `motivo_precondicao` solta, casa em comentários e na lista de colunas do
-- INSERT também — ficava verde mesmo com a escrita desligada).
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
  -- CORRIGIDO após revisão independente (achado mais grave: um p_resultado
  -- fora do vocabulário virava 'a checagem concluiu' — precondicoes_ok =
  -- TRUE, afirmação positiva e FALSA, medido passando 'linha_nao_localizado',
  -- uma letra fora do contrato). Todo valor que QUALQUER `fn_reconciliar_*`
  -- hoje realmente emite (grep em todas as migrations) mais os três
  -- reservados do CONTRATO acima — nada além disso é reconhecido.
  v_vocabulario_resultado text[] := array['ok', 'divergente', 'divergencia', 'zona_cinzenta']
                                       || v_motivos_precondicao;
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
  -- 0186 (achado 1 da revisão): p_resultado FORA do vocabulário conhecido
  -- REPROVA ALTO — não vira 'a checagem concluiu' por acidente de digitação.
  -- `raise` em vez de `check constraint` na coluna `resultado`: a tabela tem
  -- histórico com valores legados (ok, divergente, divergencia, zona_cinzenta,
  -- precondicao_nao_satisfeita) e um check retroativo recusaria linha antiga
  -- ou faria o `alter table` falhar — o raise protege só a ESCRITA daqui pra
  -- frente, sem tocar no que já está gravado.
  if not (p_resultado = any(v_vocabulario_resultado)) then
    raise exception 'fn_registrar_reconciliacao: p_resultado=% fora do vocabulario conhecido (%)',
      p_resultado, array_to_string(v_vocabulario_resultado, ', ');
  end if;

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
-- alcance ANTES, contra o banco real (as duas consultas no cabeçalho).
--
-- CORRIGIDO após revisão independente, duas coisas:
--
--   (a) tipo RENOMEADO sem de-para: linhas gravadas entre a 0009 e a 0023
--       têm `reconciliacao.tipo = 'caixa_bp_vs_fluxo'`, mas o evento saiu com
--       `acao = 'reconciliacao_caixa_bp_fluxo'` (sem o `_vs`) — a junção
--       original (`'reconciliacao_' || r.tipo`) nunca casava essas linhas, e
--       ficavam NULL sem erro nem aviso. A PROVA ESTÁ NO CÓDIGO-FONTE, que é
--       melhor que medição de produção porque qualquer sessão futura pode
--       reconferir sem acesso a banco nenhum: `0009_reconciliacao_e3.sql:355`
--       grava `tipo = 'caixa_bp_vs_fluxo'` enquanto `:396` grava
--       `acao = 'reconciliacao_caixa_bp_fluxo'` HARDCODED, sem o `_vs`; idem
--       `0022:786` contra `0022:827`. Varridos os quatro arquivos legados
--       (`0009`, `0015`, `0021`, `0022`), esse é o ÚNICO par tipo↔ação
--       divergente — todos os outros usam `'reconciliacao_' || p_tipo`. A 0023
--       renomeou o tipo para `caixa_bp_fluxo`; é renomeação, não checagem
--       distinta. O alcance está medido e registrado em `ESTADO.md`: 55 linhas
--       com o nome antigo em produção. O `case` abaixo mapeia o nome antigo
--       para o atual só para montar o `acao` da junção.
--
--   (b) sinal POSITIVO de execução: sem isto, "0 linhas preenchidas porque a
--       tabela estava vazia" e "0 linhas preenchidas porque os nomes não
--       batem" eram indistinguíveis — exatamente
--       `.claude/memory/estagio-desligado-parece-limpo.md`. O bloco abaixo
--       conta as duas coisas e avisa com `raise notice`.
-- -----------------------------------------------------------------------------
do $$
declare
  v_preenchidas  int;
  v_ficaram_null int;
begin
  with alvo as (
    select r.id, ea.depois->>'resultado' as motivo_original
    from reconciliacao r
    join evento_auditoria ea
      on ea.entidade_ref = 'reconciliacao:' || r.id
     and ea.ator = 'sistema:reconciliacao'
     and ea.acao = 'reconciliacao_' ||
         case when r.tipo = 'caixa_bp_vs_fluxo' then 'caixa_bp_fluxo' else r.tipo end
    where r.precondicoes_ok = false
      and r.motivo_precondicao is null
  )
  update reconciliacao r
     set motivo_precondicao = a.motivo_original
    from alvo a
   where r.id = a.id
     and a.motivo_original is not null;

  get diagnostics v_preenchidas = row_count;

  select count(*) into v_ficaram_null
    from reconciliacao
   where precondicoes_ok = false and motivo_precondicao is null;

  raise notice '0186 backfill motivo_precondicao: % linha(s) preenchida(s), % linha(s) com '
    'precondicoes_ok=false continuam com motivo_precondicao NULL (evento_auditoria sem match '
    'ou depois->>''resultado'' nulo)', v_preenchidas, v_ficaram_null;
end $$;

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
   ', v_motivo_precondicao,', null,
   'A coluna existe mas fn_registrar_reconciliacao é a homônima de ANTES da 0186: continua '
   'achatando o motivo original sem gravá-lo em canto nenhum acessível à fila — a distinção some '
   'de novo, silenciosamente, mesmo com a coluna presente no schema. Marcador CORRIGIDO após '
   'revisão independente: a palavra solta "motivo_precondicao" casa em pg_get_functiondef até '
   'com a escrita desligada (ela aparece 5x no corpo — 2 em comentários, 1 no nome da variável, '
   '1 na lista de colunas do INSERT — sem contar a VALUES) — '
   'medido trocando v_motivo_precondicao por null na VALUES e a sonda continuava "corpo com o '
   'marcador". ", v_motivo_precondicao," só existe no ponto exato da gravação (a lista de '
   'VALUES do INSERT); some se a variável deixar de ser o valor escrito.',
   'bloqueante', 781)

on conflict (chave) do update
  set migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
      marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
      porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0186', revisado_em = current_date,
       observacao = 'A 0186 acrescenta reconciliacao.motivo_precondicao e reemite '
                    'fn_registrar_reconciliacao para gravá-la (corpo da 0127 + a gravação de '
                    'motivo_precondicao + a validação de vocabulário do p_resultado, que '
                    'levanta exceção — não check constraint — para valor desconhecido). '
                    'resultado NÃO muda de vocabulário — só motivo_precondicao passa a existir. '
                    'O requisito de corpo usa o marcador ", v_motivo_precondicao," (a lista de '
                    'VALUES do INSERT, não a palavra solta — que casava até em comentário, com '
                    'a escrita desligada); um banco com a coluna mas com a função de antes da '
                    '0186 falha esse requisito e não o de coluna, que é a distinção que importa '
                    'para quem lê o painel.';

-- =============================================================================
-- 0188 — O MOTIVO QUE A CHECAGEM SABIA E NÃO DIZIA
--
-- O DEFEITO, medido contra produção (somente leitura, 21-22/09/2026, banco na
-- 0181 — ficha `.claude/conhecimento/fichas/f2-camada-reconciliacao-conclui-
-- pouco-e-ninguem-sabe-por-que.md`): a camada de reconciliação conclui entre
-- 8,3% e 67,8% por caso × entidade, e ninguém sabe por quê. A 0186 parou de
-- JOGAR FORA o motivo que a checagem passa (`reconciliacao.motivo_precondicao`)
-- — mas as quatro checagens que emitem a precondição genérica continuavam
-- passando o GENÉRICO, `precondicao_nao_satisfeita`, em TODO ramo, inclusive
-- nos ramos em que o próprio código já sabe qual é o motivo. A coluna existia
-- e dizia "não especificado" onde a resposta estava na variável ao lado.
--
-- E a fila herdava o mesmo silêncio por outra porta: das 52 pendências
-- `linha_exigida_ausente` DRE/despesa_financeira abertas em produção, 50 são
-- de DRE que publica só "Resultado financeiro líquido" — ausência REAL e
-- legítima, a pendência está certa, e o texto dela manda "conferir o rótulo
-- ou reenviar", que é o remédio de OUTRA doença. E 1 das 52 é FALSA: a
-- entidade tem "JUROS E COMISSÕES BANCÁRIAS" e o localizador exigia "juros"
-- E "encargos" no mesmo rótulo.
--
-- TRÊS PARTES, e a regra que separa a primeira das outras duas.
--
-- PARTE 1 — cada checagem passa o motivo ESPECÍFICO que ela sabe.
--
--   INVARIANTE DURO: esta parte NÃO muda QUAIS linhas de `reconciliacao`
--   nascem, com que `precondicoes_ok`/`resultado`, nem QUAIS pendências abrem
--   ou fecham. Só `motivo_precondicao` e o texto. Os três motivos do CONTRATO
--   da 0186 que ela passa a emitir ('linha_nao_localizada', 'unidade_divergente',
--   'sem_periodo_par') caem, pela linha `v_divergente` de
--   `fn_registrar_reconciliacao` (que NÃO muda), do mesmo lado de
--   'precondicao_nao_satisfeita': ABRE pendência. `documento_ausente` fica
--   EXATAMENTE onde está — inclusive onde ele significa "sem estrutura
--   verificável" (`fn_reconciliar_arvore`, 0133; `fn_reconciliar_mutuos`,
--   0123; `fn_reconciliar_intragrupo`, 0124). Trocá-lo por qualquer outro
--   motivo ABRIRIA pendência onde hoje não abre.
--
--   O BURACO QUE O INVARIANTE TINHA, e que só apareceu lendo os despachantes:
--   `fn_reconciliar_caso` e `fn_reconciliar_chaves_do_documento` (0152) tentam
--   cada checagem período a período e param em
--       exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
--   lendo o `resultado` que `fn_registrar_reconciliacao` DEVOLVE — e ela
--   devolvia o `p_resultado` ORIGINAL, não o achatado. Passar
--   'linha_nao_localizada' faria o laço PARAR no primeiro período em vez de
--   tentar o seguinte: menos linhas, e uma checagem que concluiria no segundo
--   período deixaria de concluir. Medido nas fixtures perturbadas (teste
--   desta migration, bloco 1): as 53 linhas de precondição vêm de laços que
--   atravessam 4 a 5 períodos. Por isso `fn_registrar_reconciliacao` é reemitida com UMA
--   mudança: o `resultado` que ela DEVOLVE sai achatado para os três motivos
--   novos (e a chave nova `motivo_precondicao` carrega o original). Ela
--   continua devolvendo `documento_ausente` cru — é isso que faz o laço parar
--   hoje quando falta a contraparte, e isso não muda. A alternativa (reemitir
--   os dois despachantes para conhecer os três motivos) espalharia o CONTRATO
--   por mais dois corpos; o achatamento já mora num lugar só, e é lá que fica.
--
--   A TABELA função → ramo → motivo antigo → novo (conferida lendo o corpo
--   vigente de cada uma, `pg_get_functiondef` no banco da 0187):
--
--   fn_reconciliar_ativo_passivo_pl (0165) · nenhum exercício com os dois lados
--       precondicao_nao_satisfeita → linha_nao_localizada, se em ALGUM
--       exercício o documento tinha a coluna do ano e da entidade e o total
--       não casou; sem_periodo_par, se em TODOS o documento não tinha coluna
--       do ano (fn_coluna_periodo_do_ano devolveu a sentinela E'\x01');
--       precondicao_nao_satisfeita (fica), se a coluna da ENTIDADE não foi
--       achada num documento de várias (o código sabe o que faltou, mas não é
--       nenhum dos três do contrato).
--   fn_reconciliar_caixa_bp_fluxo (0031) · escala não conversível
--       precondicao_nao_satisfeita → unidade_divergente.
--   fn_reconciliar_caixa_bp_fluxo (0031) · nenhum exercício com Caixa E Saldo
--       precondicao_nao_satisfeita → a mesma agregação acima, lado a lado.
--   fn_reconciliar_despfin_dre_vs_divida (0023) · escala não conversível
--       precondicao_nao_satisfeita → unidade_divergente.
--   fn_reconciliar_despfin_dre_vs_divida (0023) · nenhum exercício comparado
--       precondicao_nao_satisfeita → agregação; o Mapa sem linha de juros é
--       linha_nao_localizada (o mapa não é filtrado por ano, então não há
--       "sem período" do lado dele).
--   fn_reconciliar_receita_dre_vs_faturamento (0023) · escala não conversível
--       precondicao_nao_satisfeita → unidade_divergente.
--   fn_reconciliar_receita_dre_vs_faturamento (0023) · nenhum ano casado
--       precondicao_nao_satisfeita → agregação do lado da DRE. O lado do
--       FATURAMENTO sem mês do ano FICA GENÉRICO: fn_somar_faturamento_ano não
--       distingue "o relatório não tem este ano" de "o rótulo não carrega o
--       ano", e escolher um dos dois seria afirmar o que não foi medido. Período
--       sem ano (v_ano nulo) também fica genérico.
--   fn_reconciliar_mutuos (0123), fn_reconciliar_intragrupo (0124),
--   fn_reconciliar_arvore (0133) · NÃO SÃO REEMITIDAS: nenhum ramo delas passa
--       o genérico a fn_registrar_reconciliacao (só 'documento_ausente' e os
--       resultados que concluem). Nada a especificar.
--
--   A AGREGAÇÃO entre exercícios (fn_motivo_precondicao_agregado): se ALGUM
--   exercício teve documento com a coluna e a linha não casou, o motivo é
--   linha_nao_localizada — é o fato acionável. Senão, qualquer exercício sem
--   motivo sabido deixa o genérico. Só com TODOS sem período par o motivo é
--   sem_periodo_par.
--
--   E O TEXTO passa a dizer o motivo e o remédio na frente do que já dizia
--   (fn_motivo_precondicao_prefixo). O texto antigo fica INTEIRO depois do
--   prefixo: o portal quebra a descrição em frases e procura o marcador
--   "Rótulos que a extração TROUXE" (portal/src/lib/rotulos.ts), e três suítes
--   procuram trechos literais dele.
--
-- PARTE 2 — o recado da pendência de despesa financeira, como DADO.
--
--   No espírito da 0113 (exigência é linha, não corpo de função):
--   `taxonomia_linha_alternativa` — quando a exigência NÃO é satisfeita mas
--   uma alternativa casa, a pendência não diz "não localizada, confira o
--   rótulo": diz o que o documento traz no lugar e o que fazer. A alternativa
--   NUNCA satisfaz a exigência (a pendência continua aberta, porque a linha
--   exigida continua ausente) — ela só muda o que a pendência diz.
--
--   ONDE ELA É AVALIADA: dentro de `fn_exigencias_do_caso`, que ganha duas
--   colunas (`alternativa_rotulo`, `alternativa_recado`). Uma função
--   auxiliar teria de refazer a atribuição de entidade (capa × coluna, 0146;
--   o COMBINADO servido, 0157; fn_mesma_entidade por nome distinto, 0101) —
--   e duas atribuições divergiriam em silêncio, que é a razão pela qual a 0103
--   manteve UMA tokenização. Mudar o tipo de retorno exige `drop function`:
--   nenhuma view nem regra depende dela (conferido em pg_depend), e o grant a
--   authenticated é refeito abaixo.
--
--   SEED: DRE/despesa_financeira, contra a chave, inclui ['resultado',
--   'financeiro'], exclui ['antes']. Medido em produção (22/09/2026, sobre
--   TODOS os rótulos de DRE): casa "resultado financeiro liquido" em 71
--   entidades, e NÃO casa "resultado antes do resultado financeiro" nem
--   "resultado operacional antes do resultado financeiro".
--
--   `fn_recomputar_completude` (corpo da 0157) reemitida INTEIRA: a descrição
--   sai de `fn_descricao_linha_exigida` (byte a byte o texto de antes quando
--   não há alternativa), e no ramo em que a pendência JÁ EXISTE a descrição
--   também é atualizada — antes só a severidade era, e as 50 de produção
--   nunca mudariam de texto.
--
--   E AS 50 QUE JÁ ESTÃO ABERTAS: nenhum recompute em lote aqui. Um UPDATE
--   dirigido (seção 7) reescreve só a descrição das pendências `aberta`
--   DRE:despesa_financeira cuja entidade tem a alternativa, e conta em `raise
--   notice`. A pré-medição somente leitura está no Supabase/README.md.
--
-- PARTE 3 — o falso C, a primeira das DUAS exceções ao invariante da parte 1
-- (a outra é a parte 4, a tolerância).
--
--   Localizador ['juros','bancari'] exclui ['receita','aplicac'] na exigência
--   DRE/despesa_financeira (origem 'codigo': o seed espelha o código) E no
--   ponto equivalente de fn_reconciliar_despfin_dre_vs_divida — a duplicação
--   assumida pela 0113 ("os termos de 'codigo' são cópia literal dos arrays das
--   reconciliações vigentes"). Medido em produção sobre TODOS os rótulos de DRE
--   com juros/financeir/encargo: casa "juros e comissoes bancarias" (8 linhas,
--   4 entidades, todas negativas) e "despesas financeiras - juros e encargos
--   bancarios" (que o localizador 1 já pegava), e NÃO casa nenhum rótulo de
--   receita ("juros s/ aplicacao financeira", "juros de aplicacoes",
--   "descontos financeiros obtidos").
--
--   ISTO PODE MUDAR O RESULTADO da checagem despfin para essa entidade: onde
--   a DRE só tinha "JUROS E COMISSÕES BANCÁRIAS", a checagem deixava de
--   concluir e passa a comparar. Declarado aqui e testado à parte (bloco 3 do
--   teste), com o NEGATIVO obrigatório: DRE só com "JUROS DE APLICAÇÕES"
--   continua NÃO satisfazendo. Nas fixtures dos dois books nada muda (bloco 1
--   do teste compara contra o snapshot da 0187).
--
-- PARTE 4 — A TOLERÂNCIA DA DESPFIN NA BASE (achado da revisão independente,
-- 22/09/2026), a SEGUNDA exceção declarada ao invariante da parte 1.
--
--   Da 0023 até a 0188 escrita, fn_reconciliar_despfin_dre_vs_divida fazia
--       v_tol := greatest(p_tolerancia_abs * fator_da_DRE, abs(v_a) * pct)
--   com v_a e v_b JÁ na base (fn_valor_em_base). Numa DRE em 'milhar' o default
--   de R$ 50.000 virava R$ 50 MILHÕES. MEDIDO EM PRODUÇÃO (somente leitura,
--   22/09/2026): das 33 linhas despfin com resultado 'ok', 32 conferem de
--   verdade com greatest(R$ 50.000, 5%) e 1 é FALSA — R$ 12.400.000 de
--   diferença saindo "confere". Esta migration já reemite a função inteira,
--   então a correção vai no mesmo corpo: a tolerância absoluta fica na base.
--
--   ISTO MUDA RESULTADO: onde a divergência está entre greatest(R$ 50.000, 5%)
--   e R$ 50.000 × fator, 'ok' vira 'zona_cinzenta' (e abre pendência). Em
--   produção, pela medição acima, 1 linha — só na próxima rodada do caso. Nas
--   fixtures dos dois books nada muda: o retrato do bloco 1 e o md5 do bloco 2
--   do teste continuam os medidos na 0187 (nenhuma despfin das fixtures
--   concluía). Testado à parte (bloco 5 do teste): DRE em milhar 8.194 × mapa
--   5.308 (os números do book-distress 2025) sai zona_cinzenta; 5.308 × 5.309
--   (R$ 1.000 de arredondamento) continua ok.
--
--   O MESMO VÍCIO em outras duas checagens, REPORTADO e NÃO corrigido (não
--   foram medidas contra produção — corrigir sem medir é a 0179 de novo):
--     • fn_reconciliar_receita_dre_vs_faturamento (0023; reemitida aqui só
--       pelo motivo): `p_tolerancia_abs * fator(unidade da receita)` com o
--       mesmo default de 50.000 — em DRE 'milhar', R$ 50 milhões absolutos.
--     • fn_reconciliar_caixa_bp_fluxo (0031; idem): `100 * fator(unidade do
--       caixa)` — em 'milhar', R$ 100 mil; em 'milhão', R$ 100 milhões.
--   Nas duas o piso percentual (5% e 0,5%) domina quando o valor é grande, e
--   o absoluto só engole divergência quando o valor comparado é pequeno perto
--   do piso inflado. O alcance real só a consulta de produção diz.
--
-- O QUE ESTA MIGRATION NÃO FAZ.
--   • Não roda reconciliação nem recompute em caso nenhum. As linhas de
--     `reconciliacao` já gravadas continuam com o motivo genérico — o motivo
--     específico aparece na próxima rodada de cada caso.
--   • Não muda `resultado` nem `precondicoes_ok` fora das partes 3 e 4, nem
--     o vocabulário da 0186, nem a linha que decide pendência.
--   • Não é aplicada em produção por estar escrita. Quem responde é a sonda.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- (0) A 0188 EXIGE A 0186 APLICADA ANTES — e diz isso NA INSTALAÇÃO, não em
--     runtime.
-- -----------------------------------------------------------------------------
-- Achado da revisão independente (22/09/2026): esta migration reemite
-- fn_registrar_reconciliacao e quatro checagens em plpgsql, e o corpo de
-- plpgsql só resolve coluna quando RODA. Num banco sem a 0186, a 0188 instala
-- LIMPA — e toda fn_reconciliar_* morre depois em "column motivo_precondicao
-- does not exist" na primeira gravação. O n8n trata erro de Postgres com
-- continueRegularOutput (N8N/build-workflow.mjs, PG_RETRY): a ingestão segue,
-- e o caso fica com ZERO reconciliações, sem erro visível em canto nenhum. É
-- estágio desligado com cara de estágio limpo (regra 7).
--
-- Duas condições, porque cada uma sozinha deixa um buraco:
--   (a) a COLUNA reconciliacao.motivo_precondicao — sem ela o INSERT morre;
--   (b) o CORPO da 0186 em fn_registrar_reconciliacao (o mesmo marcador do
--       requisito `fn_registrar_reconciliacao_grava_motivo` da sonda) — a
--       coluna pode existir por um apply parcial com a função antiga, e aí a
--       0188 reemitiria por cima de um estado que a 0186 não validou (o
--       vocabulário e o backfill são dela).
-- O \r é tirado antes de procurar (`.claude/memory/ancora-de-texto-quebra-com-crlf.md`):
-- produção guarda corpo com CRLF. Reaplicar a 0188 passa — o corpo que ela
-- mesma emite contém o marcador.
--
-- Provado num banco descartável migrado até a 0181 + 0187 SEM a 0186: a 0188
-- aborta com a mensagem abaixo e nada dela fica (0 das funções novas); com este
-- bloco desligado, a MESMA 0188 instala com rc=0 sobre o mesmo banco (as 3
-- funções auxiliares criadas, as checagens reemitidas e mortas); com a 0186
-- aplicada, passa — e reaplicá-la também passa.
-- Os comandos estão no Supabase/README.md, no bloco da 0188.
do $$
declare
  v_tem_coluna boolean;
  v_tem_corpo  boolean;
begin
  select exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'reconciliacao'
                    and column_name = 'motivo_precondicao')
    into v_tem_coluna;
  select exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname = 'fn_registrar_reconciliacao'
                    and p.prokind = 'f'
                    and position(', v_motivo_precondicao,'
                                 in replace(pg_get_functiondef(p.oid), E'\r', '')) > 0)
    into v_tem_corpo;
  if not v_tem_coluna or not v_tem_corpo then
    raise exception '0188 exige a 0186 aplicada antes: %',
      concat_ws('; ',
        case when not v_tem_coluna then 'a coluna reconciliacao.motivo_precondicao não existe' end,
        case when not v_tem_corpo then 'fn_registrar_reconciliacao não é a da 0186 (não grava '
                                       'v_motivo_precondicao)' end)
      using hint = 'Aplique Supabase/migrations/0186_o_motivo_que_o_achatamento_engolia.sql e '
                   'rode esta de novo. Sem a 0186, as checagens reemitidas aqui instalam e '
                   'morrem na primeira reconciliação.';
  end if;
end $$;

-- -----------------------------------------------------------------------------
-- (1) OS TRÊS AUXILIARES DO MOTIVO — um lugar só para "qual motivo" e "que texto"
-- -----------------------------------------------------------------------------

-- O motivo de UM lado de UMA comparação que não achou a linha. A sentinela
-- E'\x01' é a de fn_coluna_entidade / fn_coluna_periodo_do_ano (0022/0023): o
-- documento DECLARA colunas desse eixo, e nenhuma é a pedida — com ela,
-- fn_valor_conceito_col não devolve nada por construção. Coluna NULA é o
-- documento sem aquele eixo, e aí a busca foi feita no documento inteiro.
create or replace function fn_motivo_do_lado(p_achou boolean, p_col_entidade text,
                                             p_col_periodo text)
returns text
language sql immutable
as $$
  select case
    when p_achou then null
    -- A entidade não tem coluna num documento de várias: o código sabe o que
    -- faltou, mas não é nenhum dos três do CONTRATO da 0186 — fica genérico.
    when p_col_entidade is not distinct from E'\x01' then 'precondicao_nao_satisfeita'
    when p_col_periodo  is not distinct from E'\x01' then 'sem_periodo_par'
    else 'linha_nao_localizada'
  end;
$$;

comment on function fn_motivo_do_lado(boolean, text, text) is
  '0188: motivo de um lado de uma comparação de reconciliação. NULL se achou; '
  'sem_periodo_par se o documento declara colunas de período e nenhuma é do ano (sentinela '
  'E''\x01''); precondicao_nao_satisfeita se a coluna da ENTIDADE não foi achada; senão '
  'linha_nao_localizada.';

-- A agregação entre lados e exercícios. Ver o cabeçalho: linha_nao_localizada
-- vence (é o fato acionável); qualquer genérico mantém o genérico; só TODOS
-- sem período par dão sem_periodo_par.
create or replace function fn_motivo_precondicao_agregado(p_motivos text[])
returns text
language sql immutable
as $$
  select case
    when cardinality(coalesce(array_remove(p_motivos, null), '{}')) = 0
      then 'precondicao_nao_satisfeita'
    when 'linha_nao_localizada' = any(array_remove(p_motivos, null))
      then 'linha_nao_localizada'
    when array_remove(p_motivos, null) <@ array['sem_periodo_par']
      then 'sem_periodo_par'
    else 'precondicao_nao_satisfeita'
  end;
$$;

comment on function fn_motivo_precondicao_agregado(text[]) is
  '0188: um motivo para a checagem a partir dos motivos por lado/exercício. '
  'linha_nao_localizada se algum; sem_periodo_par só se TODOS; senão precondicao_nao_satisfeita.';

-- O texto que vai NA FRENTE da descrição de sempre. Vazio para o genérico: onde
-- a checagem não sabe o motivo, ela não finge saber.
create or replace function fn_motivo_precondicao_prefixo(p_motivo text)
returns text
language sql immutable
as $$
  select case p_motivo
    when 'linha_nao_localizada' then
      'MOTIVO: linha não localizada — o documento está presente, mas a linha que esta '
      || 'conferência lê não casou com nenhum rótulo esperado. REMÉDIO: se a linha está no '
      || 'documento com outro nome, o defeito é o padrão de casamento; se não está, ou a '
      || 'extração não a trouxe (reextrair) ou o documento não a publica (pedir ao cliente). '
    when 'sem_periodo_par' then
      'MOTIVO: sem período par — o documento está presente, mas não traz coluna de nenhum '
      || 'exercício deste período. REMÉDIO: conferir o período atribuído ao documento, ou pedir '
      || 'ao cliente o documento do exercício que falta. '
    when 'unidade_divergente' then
      'MOTIVO: unidade divergente — os dois lados têm valor, mas as escalas não são '
      || 'conversíveis entre si. REMÉDIO: confirmar o cabeçalho de escala de cada documento. '
    else ''
  end;
$$;

comment on function fn_motivo_precondicao_prefixo(text) is
  '0188: MOTIVO e REMÉDIO de um motivo_precondicao, para ir na frente da descrição da '
  'pendência. Vazio para precondicao_nao_satisfeita (motivo não especificado) e documento_ausente.';

-- -----------------------------------------------------------------------------
-- (2) fn_registrar_reconciliacao — REEMITIDA INTEIRA (corpo da 0186), com UMA
-- mudança: o `resultado` DEVOLVIDO sai achatado para os três motivos novos. Ver
-- o cabeçalho, "O BURACO QUE O INVARIANTE TINHA". O marcador da sonda é
-- `'resultado', v_res_retorno`.
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
  -- abaixo). Desde a 0188 os cinco têm emissor.
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
  -- 0188: O QUE A FUNÇÃO DEVOLVE em `resultado`. Os despachantes (0152)
  -- decidem se tentam o PRÓXIMO período por
  -- `exit when v_res->>'resultado' <> 'precondicao_nao_satisfeita'`. Até a
  -- 0187 isso era o p_resultado cru, e só dois valores de precondição
  -- existiam: 'documento_ausente' (para o laço — falta a contraparte, outro
  -- período não a cria) e o genérico (segue o laço). Os três motivos da 0188
  -- são refinamentos do GENÉRICO, então devolvem o genérico: o laço continua
  -- exatamente como antes. 'documento_ausente' continua saindo cru.
  v_res_retorno      text := case when p_resultado in ('linha_nao_localizada',
                                                       'unidade_divergente',
                                                       'sem_periodo_par')
                                  then 'precondicao_nao_satisfeita' else p_resultado end;
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
    'resultado', v_res_retorno, 'motivo_precondicao', v_motivo_precondicao,
    'pendencia_id', v_pendencia_id
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- (3) fn_reconciliar_ativo_passivo_pl — REEMITIDA INTEIRA (corpo da 0165).
-- Mudanças: o motivo por exercício (v_motivos_ano), a sentinela da coluna
-- deixa de aparecer como "(qualquer)" no texto (era o OPOSTO do que ela
-- significa: "nenhuma coluna deste ano", não "qualquer coluna"), e o motivo
-- agregado + o prefixo no ramo de nenhum exercício. Nenhum outro ramo muda.
-- -----------------------------------------------------------------------------
create or replace function fn_reconciliar_ativo_passivo_pl(p_caso_id uuid, p_entidade_id uuid,
  p_periodo_id uuid, p_tolerancia_abs numeric default 100, p_tolerancia_pct numeric default 0.005)
returns jsonb
language plpgsql
as $$
declare
  v_doc_id     uuid;
  v_versao     uuid;
  v_col_ent    text;
  v_ano        int;
  v_col_per    text;
  v_ativo      campo_extraido;
  v_passivo_pl campo_extraido;
  v_passivo    campo_extraido;
  v_pl         campo_extraido;
  v_esq        numeric;
  v_dir        numeric;
  v_soma       record;
  v_soma_pl    record;
  v_div_abs    numeric;
  v_tol        numeric;
  v_pior_abs   numeric := null;
  v_pior_pct   numeric := null;
  v_resultado  text := 'ok';
  v_partes     text[] := '{}';
  v_n_anos     int := 0;
  v_fonte_a    jsonb;
  v_fonte_b    jsonb;
  v_desc       text;
  v_orig_esq   text;
  v_orig_dir   text;
  v_faltas     text[] := '{}';
  -- 0165: o "PASSIVO" bare veio do casamento ESTRUTURAL (e não de um rótulo que
  -- diz "Passivo Total")? É essa a única via ambígua — ver o comentário grande
  -- da migration.
  v_passivo_estrutural boolean := false;
  -- 0188: o motivo de cada exercício que ficou sem os dois lados.
  v_motivos_ano text[] := '{}';
  v_motivo_prec text;
begin
  v_doc_id := fn_documento_balanco(p_caso_id, p_entidade_id, p_periodo_id);

  if v_doc_id is null then
    return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
      'ativo_passivo_pl', 'A', null, null, null, 'documento_ausente', null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      'Nenhum Balanço Patrimonial, Combinado ou Balancete classificado para esta '
      || 'entidade/período — nada a reconciliar (a cobrança do documento é do checklist).');
  end if;

  v_versao  := fn_versao_atual(v_doc_id);
  v_col_ent := fn_coluna_entidade(v_versao, p_entidade_id);

  foreach v_ano in array fn_anos_alvo(p_periodo_id) loop
    v_col_per := case when v_ano is null then null
                      else fn_coluna_periodo_do_ano(v_versao, v_ano) end;
    v_orig_esq := null;
    v_orig_dir := null;
    v_esq := null;
    v_dir := null;
    v_passivo_estrutural := false;

    -- ---- lado esquerdo: ATIVO ------------------------------------------------
    -- (a) a linha que diz "total" no rótulo.
    select * into v_ativo from fn_valor_conceito_col(v_versao,
      array['ativo', 'total'], array['circulante', 'nao circulante'], v_col_ent, v_col_per);
    if v_ativo.id is not null then
      v_esq := v_ativo.valor_num;
      v_orig_esq := format('linha "%s"', v_ativo.chave);
    else
      -- (b) 0034: o rótulo ESTRUTURAL — "ATIVO", que é como a maioria dos
      -- balanços brasileiros imprime o total do grupo.
      select * into v_ativo from fn_valor_estrutural_col(v_versao,
        array['ativo'], v_col_ent, v_col_per);
      if v_ativo.id is not null then
        v_esq := v_ativo.valor_num;
        v_orig_esq := format('linha "%s" (total do grupo, sem a palavra "total")', v_ativo.chave);
      else
        -- (c) soma das contas da seção.
        select * into v_soma from fn_soma_secao(v_versao, array['ativo'], v_col_ent, v_col_per,
          array['passivo', 'patrimonio'], array['total do ativo']);
        v_esq := case when coalesce(v_soma.n_linhas, 0) > 0 then v_soma.soma end;
        v_orig_esq := case when v_esq is null then null
          else format('soma da seção ATIVO (%s linhas, sem linha de total impressa)', v_soma.n_linhas) end;
      end if;
    end if;

    -- ---- lado direito: PASSIVO + PL -----------------------------------------
    select * into v_passivo_pl from fn_valor_conceito_col(v_versao,
      array['passivo', 'patrimonio', 'total'], array['circulante'], v_col_ent, v_col_per);
    if v_passivo_pl.id is not null then
      v_dir := v_passivo_pl.valor_num;
      v_orig_dir := format('linha "%s"', v_passivo_pl.chave);
    else
      -- 0034: "PASSIVO E PATRIMÔNIO LÍQUIDO" — o rótulo do v35, que a busca com
      -- "total" não via.
      select * into v_passivo_pl from fn_valor_estrutural_col(v_versao,
        array['passivo', 'patrimonio'], v_col_ent, v_col_per);
      if v_passivo_pl.id is not null then
        v_dir := v_passivo_pl.valor_num;
        v_orig_dir := format('linha "%s" (total do grupo, sem a palavra "total")', v_passivo_pl.chave);
      else
        select * into v_passivo from fn_valor_conceito_col(v_versao,
          array['passivo', 'total'], array['patrimonio', 'circulante', 'nao circulante'],
          v_col_ent, v_col_per);
        select * into v_pl from fn_valor_conceito_col(v_versao,
          array['patrimonio', 'liquido', 'total'], array['circulante'], v_col_ent, v_col_per);
        if v_passivo.id is null then
          select * into v_passivo from fn_valor_estrutural_col(v_versao,
            array['passivo'], v_col_ent, v_col_per);
          v_passivo_estrutural := v_passivo.id is not null;
        end if;
        if v_pl.id is null then
          select * into v_pl from fn_valor_estrutural_col(v_versao,
            array['patrimonio'], v_col_ent, v_col_per);
        end if;
        -- 0165: "PASSIVO" BARE QUE JÁ BATE COM O ATIVO É O TOTAL DO GRUPO.
        -- Ver o cabeçalho desta migration para a medição. Só vale para o rótulo
        -- ESTRUTURAL: um rótulo que DIZ "Passivo Total" (e exclui patrimônio)
        -- está afirmando exigível, e nele a igualdade com o Ativo seria um
        -- balanço que não fecha — que é divergência de verdade, e continua
        -- sendo reportada pelo ramo de baixo.
        if v_passivo_estrutural and v_esq is not null
           and abs(v_passivo.valor_num - v_esq)
               <= greatest(p_tolerancia_abs, abs(v_esq) * p_tolerancia_pct) then
          v_dir := v_passivo.valor_num;
          v_orig_dir := format('linha "%s" (total do grupo, já inclui o Patrimônio Líquido)',
                               v_passivo.chave);
        elsif v_passivo.id is not null and v_pl.id is not null then
          v_dir := v_passivo.valor_num + v_pl.valor_num;
          v_orig_dir := format('linhas "%s" + "%s"', v_passivo.chave, v_pl.chave);
        else
          -- 0034: o fallback de soma, agora ALCANÇÁVEL. Era
          -- `fn_soma_secao(array['passivo','patrimonio'])`, que exige a seção
          -- conter os DOIS termos — e não existe seção "passivo patrimônio".
          -- As seções reais são "Passivo Circulante", "Passivo Não Circulante"
          -- e "Patrimônio Líquido", então são DUAS somas que se juntam.
          select * into v_soma from fn_soma_secao(v_versao, array['passivo'],
            v_col_ent, v_col_per, array['patrimonio'],
            array['total do passivo', 'passivo e patrimonio']);
          select * into v_soma_pl from fn_soma_secao(v_versao, array['patrimonio'],
            v_col_ent, v_col_per, '{}',
            array['total do passivo', 'passivo e patrimonio']);
          if coalesce(v_soma.n_linhas, 0) + coalesce(v_soma_pl.n_linhas, 0) > 0 then
            v_dir := coalesce(v_soma.soma, 0) + coalesce(v_soma_pl.soma, 0);
            v_orig_dir := format('soma das seções PASSIVO (%s linhas) + PL (%s linhas), sem linha de total impressa',
                                 coalesce(v_soma.n_linhas, 0), coalesce(v_soma_pl.n_linhas, 0));
          end if;
        end if;
      end if;
    end if;

    if v_esq is null or v_dir is null then
      -- 0188: os dois lados leem o MESMO documento com as MESMAS colunas, então
      -- o motivo do exercício é o de um lado só.
      v_motivos_ano := v_motivos_ano || fn_motivo_do_lado(false, v_col_ent, v_col_per);
      v_faltas := v_faltas || format('%s: falta %s%s',
        coalesce(v_ano::text, 'período do documento'),
        case
          when v_esq is null and v_dir is null then 'o Ativo Total E o Passivo+PL'
          when v_esq is null then 'o Ativo Total'
          else 'o Passivo+PL'
        end,
        case
          when v_col_per is null and v_col_ent is null then ''
          else format(' (coluna de entidade: %s; coluna de período: %s)',
                      -- 0188: a sentinela é "o documento tem colunas deste eixo
                      -- e NENHUMA é a pedida" — o texto dizia "(qualquer)",
                      -- que é o contrário.
                      case when v_col_ent = E'\x01' then '(nenhuma desta entidade)'
                           else coalesce(v_col_ent, '(qualquer)') end,
                      case when v_col_per = E'\x01' then '(nenhuma deste exercício)'
                           else coalesce(v_col_per, '(qualquer)') end)
        end);
      continue;
    end if;

    v_n_anos := v_n_anos + 1;
    v_div_abs := abs(v_esq - v_dir);
    v_tol := greatest(p_tolerancia_abs, abs(v_esq) * p_tolerancia_pct);
    if v_div_abs > v_tol then
      v_resultado := 'divergente';
      v_partes := v_partes || format('%s: Ativo %s [%s] vs Passivo+PL %s [%s] (diferença de %s)',
        coalesce(v_ano::text, 'período do documento'), v_esq, v_orig_esq, v_dir, v_orig_dir, v_div_abs);
      if v_pior_abs is null or v_div_abs > v_pior_abs then
        v_pior_abs := v_div_abs;
        v_pior_pct := case when v_esq <> 0 then v_div_abs / abs(v_esq) end;
      end if;
    else
      v_partes := v_partes || format('%s: confere (Ativo %s [%s] = Passivo+PL %s [%s])',
        coalesce(v_ano::text, 'período do documento'), v_esq, v_orig_esq, v_dir, v_orig_dir);
    end if;
    v_fonte_a := jsonb_build_object('chave', coalesce(v_ativo.chave, 'soma da seção ATIVO'),
      'valor', v_esq, 'ano', v_ano, 'origem', v_orig_esq, 'documento_versao_id', v_versao);
    v_fonte_b := jsonb_build_object('valor', v_dir, 'ano', v_ano, 'origem', v_orig_dir,
      'documento_versao_id', v_versao);
  end loop;

  if v_n_anos = 0 then
    v_motivo_prec := fn_motivo_precondicao_agregado(v_motivos_ano);
    return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
      'ativo_passivo_pl', 'A', v_doc_id, null, null, v_motivo_prec, null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      fn_motivo_precondicao_prefixo(v_motivo_prec)
      || 'O Balanço foi encontrado, mas nenhum exercício teve os DOIS lados. '
      || case when array_length(v_faltas, 1) is null then ''
              else array_to_string(v_faltas, '; ') || '. ' end
      || 'Rótulos que a extração TROUXE e que poderiam ser um total: '
      || fn_rotulos_candidatos(v_versao)
      || '. Se o rótulo certo está nessa lista, o defeito é o padrão de casamento; '
      || 'se não está, a extração não trouxe a linha e o caminho é reextrair.');
  end if;

  v_desc := format('Ativo Total vs Passivo+Patrimônio Líquido em %s ano(s): %s.',
                   v_n_anos, array_to_string(v_partes, '; '));
  if array_length(v_faltas, 1) is not null then
    v_desc := v_desc || format(' Exercícios NÃO checados: %s.', array_to_string(v_faltas, '; '));
  end if;

  return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
    'ativo_passivo_pl', 'A', v_doc_id, v_fonte_a, v_fonte_b, v_resultado,
    v_pior_abs, v_pior_pct,
    jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct,
                       'anos_checados', v_n_anos,
                       'anos_nao_checados', coalesce(array_length(v_faltas, 1), 0)),
    v_desc);
end;
$$;

-- -----------------------------------------------------------------------------
-- (4) fn_reconciliar_caixa_bp_fluxo — REEMITIDA INTEIRA (corpo da 0031).
-- Mudanças: a coluna de período de CADA lado fica guardada (o corpo antigo
-- reusava v_col_per e perdia a do Balanço), o motivo por exercício, o
-- 'unidade_divergente' no ramo de escala, e o motivo agregado + o texto por
-- exercício no ramo de nenhum exercício.
-- -----------------------------------------------------------------------------
create or replace function fn_reconciliar_caixa_bp_fluxo(p_caso_id uuid, p_entidade_id uuid,
  p_periodo_id uuid, p_tolerancia_abs numeric default 100, p_tolerancia_pct numeric default 0.005)
returns jsonb
language plpgsql
as $$
declare
  v_doc_bp    uuid;
  v_doc_fx    uuid;
  v_ver_bp    uuid;
  v_ver_fx    uuid;
  v_col_ent   text;
  v_ano       int;
  v_col_per   text;
  v_caixa     campo_extraido;
  v_saldo     campo_extraido;
  v_motivo    text;
  v_a         numeric;
  v_b         numeric;
  v_div_abs   numeric;
  v_tol       numeric;
  v_resultado text := 'ok';
  v_partes    text[] := '{}';
  v_n         int := 0;
  v_pior_abs  numeric;
  v_pior_pct  numeric;
  v_fonte_a   jsonb;
  v_fonte_b   jsonb;
  -- 0188
  v_col_bp      text;
  v_motivos_ano text[] := '{}';
  v_motivo_ano  text;
  v_faltas      text[] := '{}';
  v_motivo_prec text;
begin
  v_doc_bp := fn_documento_balanco(p_caso_id, p_entidade_id, p_periodo_id);
  v_doc_fx := fn_documento_por_tipo(p_caso_id, p_entidade_id, p_periodo_id, 'FLUXO_CAIXA');

  if v_doc_bp is null or v_doc_fx is null then
    -- Fato comum e legítimo: nem toda empresa do grupo entrega DFC. Quem cobra
    -- documento faltante é o checklist do Kit Básico, não a fila de revisão.
    return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
      'caixa_bp_fluxo', 'A', coalesce(v_doc_bp, v_doc_fx), null, null,
      'documento_ausente', null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      format('Sem par para reconciliar: %s não foi entregue para esta entidade/período.',
        case when v_doc_bp is null and v_doc_fx is null then 'Balanço e Fluxo de Caixa'
             when v_doc_bp is null then 'Balanço Patrimonial' else 'Fluxo de Caixa' end));
  end if;

  v_ver_bp  := fn_versao_atual(v_doc_bp);
  v_ver_fx  := fn_versao_atual(v_doc_fx);
  v_col_ent := fn_coluna_entidade(v_ver_bp, p_entidade_id);

  foreach v_ano in array fn_anos_alvo(p_periodo_id) loop
    v_col_per := case when v_ano is null then null
                      else fn_coluna_periodo_do_ano(v_ver_bp, v_ano) end;
    v_col_bp := v_col_per;

    -- Caixa no Balanço. "Disponível"/"Disponibilidades" é o rótulo mais comum em
    -- demonstração brasileira detalhada — a DFC do book chega a dizer, na nota,
    -- que o saldo final "confere com a rubrica Disponível do balanço".
    select * into v_caixa from fn_valor_conceito_col(v_ver_bp,
      array['caixa', 'equivalentes'], array['circulante', 'fluxo', 'inicio', 'inicial'],
      v_col_ent, v_col_per);
    if v_caixa.id is null then
      select * into v_caixa from fn_valor_conceito_col(v_ver_bp,
        array['disponibilidades'], array['circulante'], v_col_ent, v_col_per);
    end if;
    if v_caixa.id is null then
      select * into v_caixa from fn_valor_conceito_col(v_ver_bp,
        array['disponivel'], array['circulante'], v_col_ent, v_col_per);
    end if;
    if v_caixa.id is null then
      select * into v_caixa from fn_valor_conceito_col(v_ver_bp,
        array['caixa', 'bancos'], array['circulante'], v_col_ent, v_col_per);
    end if;
    -- 0031: as quatro tentativas acima olham SÓ `ce.chave`, e é isso que produzia a
    -- pendência "não foi possível localizar o Caixa/Disponível" no teste v31. Contra
    -- os rótulos reais do book:
    --
    --   Holding      "Caixa e Equivalentes de Caixa"  -> casa (1)
    --   Metalúrgica  "Disponibilidades"               -> casa (2)
    --   Componentes  "Numerário Disponível"           -> casa (3)
    --   SPE          "Caixa"                          -> NÃO casava: (1) exige
    --                                                   'equivalentes' e (4) exige 'bancos'
    --   VT Logística "Bancos Conta Movimento"         -> NÃO casava nenhuma
    --
    -- E o dado que faltava ESTAVA no documento: a `secao` da VT Logística diz
    -- "Disponível". A função nunca olhou `ce.secao`.
    if v_caixa.id is null then
      -- "Caixa" puro (SPE). Vem depois das combinações de dois termos, que são
      -- mais específicas — assim um documento que tem as duas coisas escolhe a
      -- linha certa em vez da mais genérica.
      select * into v_caixa from fn_valor_conceito_col(v_ver_bp,
        array['caixa'], array['circulante', 'fluxo', 'inicio', 'inicial', 'equivalente'],
        v_col_ent, v_col_per);
    end if;
    if v_caixa.id is null then
      -- Pela SEÇÃO do documento: é o que resolve "Bancos Conta Movimento".
      select * into v_caixa from fn_valor_conceito_secao(v_ver_bp,
        array['disponivel'], array['circulante'], v_col_ent, v_col_per);
    end if;
    if v_caixa.id is null then
      select * into v_caixa from fn_valor_conceito_secao(v_ver_bp,
        array['caixa'], array['circulante', 'fluxo'], v_col_ent, v_col_per);
    end if;

    -- Saldo final na DFC (a coluna de período da DFC é a dela, não a do BP).
    v_col_per := case when v_ano is null then null
                      else fn_coluna_periodo_do_ano(v_ver_fx, v_ano) end;
    select * into v_saldo from fn_valor_conceito_col(v_ver_fx,
      array['saldo', 'final'], array['inicial', 'inicio'], null, v_col_per);
    if v_saldo.id is null then
      select * into v_saldo from fn_valor_conceito_col(v_ver_fx,
        array['caixa', 'final'], array['inicial', 'inicio'], null, v_col_per);
    end if;
    if v_saldo.id is null then
      select * into v_saldo from fn_valor_conceito_col(v_ver_fx,
        array['caixa', 'fim'], array['inicial', 'inicio'], null, v_col_per);
    end if;

    if v_caixa.id is null or v_saldo.id is null then
      -- 0188: cada lado com o motivo dele (o Balanço com a coluna de entidade e
      -- a de período do Balanço; a DFC só com a de período dela).
      v_motivo_ano := fn_motivo_precondicao_agregado(array[
        fn_motivo_do_lado(v_caixa.id is not null, v_col_ent, v_col_bp),
        fn_motivo_do_lado(v_saldo.id is not null, null, v_col_per)]);
      v_motivos_ano := v_motivos_ano || v_motivo_ano;
      v_faltas := v_faltas || format('%s: %s',
        coalesce(v_ano::text, 'período do documento'),
        array_to_string(array_remove(array[
          case when v_caixa.id is null then
            case when v_col_bp = E'\x01' then 'o Balanço não tem coluna deste exercício'
                 when v_col_ent = E'\x01' then 'o Balanço não tem coluna desta entidade'
                 else 'o Caixa/Disponível do Balanço não foi localizado' end end,
          case when v_saldo.id is null then
            case when v_col_per = E'\x01' then 'o Fluxo de Caixa não tem coluna deste exercício'
                 else 'o Saldo final do Fluxo de Caixa não foi localizado' end end
        ], null), ' e '));
      continue;
    end if;

    v_motivo := fn_motivo_escala_incomparavel(v_caixa.unidade, v_saldo.unidade,
      'o Caixa do Balanço', 'o Saldo final do Fluxo de Caixa');
    if v_motivo is not null then
      return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
        'caixa_bp_fluxo', 'A', v_doc_bp, null, null, 'unidade_divergente', null, null,
        jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
        fn_motivo_precondicao_prefixo('unidade_divergente') || v_motivo);
    end if;

    v_a := fn_valor_em_base(v_caixa.valor_num, v_caixa.unidade);
    v_b := fn_valor_em_base(v_saldo.valor_num, v_saldo.unidade);
    v_n := v_n + 1;
    v_div_abs := abs(v_a - v_b);
    v_tol := greatest(p_tolerancia_abs * coalesce(fn_fator_escala(v_caixa.unidade), 1),
                      abs(v_a) * p_tolerancia_pct);
    if v_div_abs > v_tol then
      v_resultado := 'divergente';
      v_partes := v_partes || format('%s: Caixa no Balanço %s ("%s") vs Saldo final na DFC %s ("%s") — diferença de %s',
        coalesce(v_ano::text, 'período do documento'), v_caixa.valor_num, v_caixa.chave,
        v_saldo.valor_num, v_saldo.chave, v_div_abs);
      if v_pior_abs is null or v_div_abs > v_pior_abs then
        v_pior_abs := v_div_abs;
        v_pior_pct := case when v_a <> 0 then v_div_abs / abs(v_a) end;
      end if;
    else
      v_partes := v_partes || format('%s: confere (%s "%s" = %s "%s")',
        coalesce(v_ano::text, 'período do documento'), v_caixa.valor_num, v_caixa.chave,
        v_saldo.valor_num, v_saldo.chave);
    end if;
    v_fonte_a := jsonb_build_object('chave', v_caixa.chave, 'valor', v_caixa.valor_num,
      'unidade', v_caixa.unidade, 'documento_versao_id', v_ver_bp);
    v_fonte_b := jsonb_build_object('chave', v_saldo.chave, 'valor', v_saldo.valor_num,
      'unidade', v_saldo.unidade, 'documento_versao_id', v_ver_fx);
  end loop;

  if v_n = 0 then
    v_motivo_prec := fn_motivo_precondicao_agregado(v_motivos_ano);
    return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
      'caixa_bp_fluxo', 'A', v_doc_bp, null, null, v_motivo_prec, null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      fn_motivo_precondicao_prefixo(v_motivo_prec)
      || 'Balanço e Fluxo de Caixa presentes, mas não foi possível localizar o Caixa/Disponível do '
      || 'Balanço e/ou o Saldo final de caixa do Fluxo (rótulos extraídos não bateram). '
      || array_to_string(v_faltas, '; ') || '.');
  end if;

  return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
    'caixa_bp_fluxo', 'A', v_doc_bp, v_fonte_a, v_fonte_b, v_resultado, v_pior_abs, v_pior_pct,
    jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct,
                       'anos_checados', v_n),
    format('Caixa do Balanço vs Saldo final do Fluxo de Caixa em %s ano(s): %s.',
           v_n, array_to_string(v_partes, '; ')));
end;
$$;

-- -----------------------------------------------------------------------------
-- (5) A TABELA DAS ALTERNATIVAS (parte 2) — vem antes da despfin porque ela a lê.
-- -----------------------------------------------------------------------------
create table if not exists taxonomia_linha_alternativa (
  id            uuid primary key default gen_random_uuid(),
  exigencia_id  uuid not null references taxonomia_linha_exigida(id) on delete cascade,
  ordem         int  not null,
  -- Os mesmos alvos de taxonomia_linha_localizador, menos 'estrutural': a
  -- alternativa é "o documento traz ISTO no lugar", e isso se diz por termos.
  contra        text not null default 'chave' check (contra in ('chave', 'secao', 'coluna')),
  termos_inclui text[] not null check (cardinality(termos_inclui) > 0),
  termos_exclui text[] not null default '{}',
  -- O RECADO é o que a pendência passa a dizer: o que o documento traz, e o
  -- que fazer. Obrigatório e não vazio — alternativa sem recado seria uma
  -- linha que muda o casamento sem mudar o texto, que é o contrário do motivo
  -- de ela existir.
  recado        text not null check (length(btrim(recado)) > 0),
  unique (exigencia_id, ordem)
);

comment on table taxonomia_linha_alternativa is
  '0188: o que um documento pode trazer NO LUGAR de uma linha exigida, e o recado que a '
  'pendência linha_exigida_ausente passa a dar quando isso acontece. A alternativa NUNCA '
  'satisfaz a exigência (a linha exigida continua ausente e a pendência continua aberta) — ela '
  'só troca o "não localizada, confira o rótulo" pelo motivo real e o remédio. Casamento no '
  'formato de taxonomia_linha_localizador (substring do texto normalizado).';
comment on column taxonomia_linha_alternativa.recado is
  'O que a pendência diz quando a alternativa casa: o que o documento traz, o efeito, e o que '
  'pedir. Vai inteiro na descrição (fn_descricao_linha_exigida).';

alter table taxonomia_linha_alternativa enable row level security;
drop policy if exists taxonomia_linha_alternativa_read on taxonomia_linha_alternativa;
create policy taxonomia_linha_alternativa_read on taxonomia_linha_alternativa
  for select to authenticated using (true);
-- Escrita reservada (migration/service_role), como taxonomia_linha_exigida.

insert into taxonomia_linha_alternativa (exigencia_id, ordem, contra, termos_inclui, termos_exclui, recado)
select e.id, 1, 'chave', array['resultado', 'financeiro'], array['antes'],
  'A DRE traz o resultado financeiro LÍQUIDO (receitas menos despesas financeiras) em vez da '
  || 'despesa financeira BRUTA. A linha não está faltando por defeito de extração: o documento '
  || 'não a publica. Efeito: a conferência da despesa financeira contra os juros do mapa de '
  || 'dívida não roda, porque líquido não se compara com juros de contrato. Remédio: pedir ao '
  || 'cliente a abertura do resultado financeiro (despesas financeiras separadas das receitas '
  || 'financeiras).'
from taxonomia_linha_exigida e
where e.tipo_taxonomia = 'DRE' and e.conceito = 'despesa_financeira'
on conflict (exigencia_id, ordem) do nothing;

-- PARTE 3, lado do SEED: o localizador que espelha o código (seção 6).
insert into taxonomia_linha_localizador (exigencia_id, ordem, contra, termos_inclui, termos_exclui)
select e.id, 3, 'chave', array['juros', 'bancari'], array['receita', 'aplicac']
from taxonomia_linha_exigida e
where e.tipo_taxonomia = 'DRE' and e.conceito = 'despesa_financeira'
on conflict (exigencia_id, ordem) do nothing;

-- -----------------------------------------------------------------------------
-- (6) fn_reconciliar_despfin_dre_vs_divida — REEMITIDA INTEIRA (corpo da 0023,
-- com o comentário da 0145 que o dump preserva). Mudanças: o terceiro
-- localizador (parte 3) e a tolerância absoluta na base (parte 4) — as DUAS
-- mudanças de resultado desta migration —, o motivo por exercício,
-- 'unidade_divergente' no ramo de escala, e o recado da alternativa quando a
-- DRE traz o líquido no lugar da despesa.
-- -----------------------------------------------------------------------------
create or replace function fn_reconciliar_despfin_dre_vs_divida(p_caso_id uuid, p_entidade_id uuid,
  p_periodo_id uuid, p_tolerancia_abs numeric default 50000, p_tolerancia_pct numeric default 0.05)
returns jsonb
language plpgsql
as $_$
declare
  v_doc_dre uuid;
  v_doc_div uuid;
  v_ver_dre uuid;
  v_ver_div uuid;
  v_col_ent text;
  v_ano int;
  v_col_per text;
  v_despfin campo_extraido;
  v_juros   record;
  v_unid_div text;
  v_motivo text;
  v_a numeric; v_b numeric; v_div numeric; v_tol numeric;
  v_resultado text := 'ok';
  v_partes text[] := '{}';
  v_n int := 0;
  v_pior_abs numeric; v_pior_pct numeric;
  v_fonte_a jsonb; v_fonte_b jsonb;
  -- 0188
  v_motivos_ano text[] := '{}';
  v_faltas      text[] := '{}';
  v_motivo_prec text;
  v_alt         record;
  v_recado      text;
begin
  v_doc_dre := fn_documento_por_tipo(p_caso_id, p_entidade_id, p_periodo_id, 'DRE');
  v_doc_div := fn_documento_por_tipo(p_caso_id, p_entidade_id, p_periodo_id, 'MAPA_DIVIDA');

  if v_doc_dre is null or v_doc_div is null then
    return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
      'despfin_dre_vs_divida', 'B', coalesce(v_doc_dre, v_doc_div), null, null,
      'documento_ausente', null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      format('Sem par para reconciliar despesa financeira: %s não foi entregue para esta entidade/período.',
        case when v_doc_dre is null and v_doc_div is null then 'DRE e Mapa de Dívida'
             when v_doc_dre is null then 'DRE' else 'Mapa de Dívida' end));
  end if;

  v_ver_dre  := fn_versao_atual(v_doc_dre);
  v_ver_div  := fn_versao_atual(v_doc_div);
  v_col_ent  := fn_coluna_entidade(v_ver_dre, p_entidade_id);
  v_unid_div := fn_unidade_predominante(v_ver_div);

  foreach v_ano in array fn_anos_alvo(p_periodo_id) loop
    v_col_per := case when v_ano is null then null
                      else fn_coluna_periodo_do_ano(v_ver_dre, v_ano) end;

    select * into v_despfin from fn_valor_conceito_col(v_ver_dre,
      array['despesa', 'financeira'], array['receita'], v_col_ent, v_col_per);
    if v_despfin.id is null then
      select * into v_despfin from fn_valor_conceito_col(v_ver_dre,
        array['juros', 'encargos'], array['receita', 'pagos'], v_col_ent, v_col_per);
    end if;
    -- 0188 (parte 3): "JUROS E COMISSÕES BANCÁRIAS" — o rótulo de UMA entidade
    -- de produção cuja pendência de despesa financeira era falsa, porque o
    -- localizador de cima exige "juros" E "encargos". Medido sobre TODOS os
    -- rótulos de DRE com juros/financeir/encargo em produção (22/09/2026): casa
    -- "juros e comissoes bancarias" (8 linhas, 4 entidades, todas negativas) e
    -- NENHUM rótulo de receita — o exclui leva 'aplicac' porque "juros s/
    -- aplicação financeira" e "juros de aplicações" são receita. O MESMO par
    -- está em taxonomia_linha_localizador (DRE/despesa_financeira, ordem 3):
    -- duplicação assumida da 0113, para exigência e checagem não divergirem.
    if v_despfin.id is null then
      select * into v_despfin from fn_valor_conceito_col(v_ver_dre,
        array['juros', 'bancari'], array['receita', 'aplicac'], v_col_ent, v_col_per);
    end if;
    if v_despfin.id is null then
      v_motivos_ano := v_motivos_ano || fn_motivo_do_lado(false, v_col_ent, v_col_per);
      -- 0188 (parte 2, do lado da checagem): a DRE traz o LÍQUIDO no lugar? A
      -- alternativa é a mesma linha que a pendência de completude lê.
      if v_recado is null then
        select a.recado, ce.chave into v_alt
          from taxonomia_linha_alternativa a
          join taxonomia_linha_exigida e on e.id = a.exigencia_id
          cross join lateral fn_valor_conceito_col(v_ver_dre, a.termos_inclui, a.termos_exclui,
                                                   v_col_ent, v_col_per) ce
         where e.tipo_taxonomia = 'DRE' and e.conceito = 'despesa_financeira' and e.ativo
           and a.contra = 'chave' and ce.id is not null
         order by a.ordem
         limit 1;
        if v_alt.recado is not null then
          v_recado := format('A DRE traz "%s" no lugar. %s', v_alt.chave, v_alt.recado);
        end if;
      end if;
      v_faltas := v_faltas || format('%s: %s', coalesce(v_ano::text, 'período do documento'),
        case when v_col_per = E'\x01' then 'a DRE não tem coluna deste exercício'
             when v_col_ent = E'\x01' then 'a DRE não tem coluna desta entidade'
             else 'a Despesa Financeira da DRE não foi localizada' end);
      continue;
    end if;

    -- Juros do exercício no mapa: soma as linhas por contrato, excluindo o total.
    select coalesce(sum(ce.valor_num), 0)::numeric as soma, count(*)::int as n
      into v_juros
    from campo_extraido ce
    where ce.documento_versao_id = v_ver_div
      and ce.valor_num is not null
      -- 0145: o conceito pode morar na COLUNA. No mapa de dívida matricial a
      -- chave é o contrato ("Banco Meridional S.A. - Capital de giro (…)") e o
      -- cabeçalho é "Juros do exercício (R$)". Sem este segundo ramo a soma vinha
      -- vazia e a checagem devolvia precondicao_nao_satisfeita sobre um documento
      -- perfeitamente extraído — pendência da v48 no 02_DRE_Canastra_Industria.
      and (fn_normalizar_texto(ce.chave) like '%juros%'
           or fn_normalizar_texto(ce.chave) like '%encargos%'
           or fn_normalizar_texto(coalesce(ce.periodo_coluna, '')) like '%juros%'
           or fn_normalizar_texto(coalesce(ce.periodo_coluna, '')) like '%encargos%')
      and fn_normalizar_texto(ce.chave) not like 'total%'
      and fn_normalizar_texto(ce.chave) not like '%total %';
    if coalesce(v_juros.n, 0) = 0 then
      -- 0188: o mapa não é recortado por ano (a soma lê o documento inteiro),
      -- então do lado dele não há "sem período": é linha não localizada.
      v_motivos_ano := v_motivos_ano || 'linha_nao_localizada'::text;
      v_faltas := v_faltas || format('%s: o Mapa de Dívida não tem linha nem coluna de juros/encargos',
        coalesce(v_ano::text, 'período do documento'));
      continue;
    end if;

    v_motivo := fn_motivo_escala_incomparavel(v_despfin.unidade, v_unid_div,
      'a Despesa Financeira da DRE', 'o Mapa de Dívida');
    if v_motivo is not null then
      return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
        'despfin_dre_vs_divida', 'B', v_doc_dre, null, null,
        'unidade_divergente', null, null,
        jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
        fn_motivo_precondicao_prefixo('unidade_divergente') || v_motivo);
    end if;

    -- Comparação em VALOR ABSOLUTO: a DRE traz a despesa como negativa
    -- (dedução), o mapa traz os juros como positivos.
    v_a := abs(fn_valor_em_base(v_despfin.valor_num, v_despfin.unidade));
    v_b := abs(fn_valor_em_base(v_juros.soma, v_unid_div));
    v_n := v_n + 1;
    v_div := abs(v_a - v_b);
    -- 0188 (revisão, 22/09/2026): A TOLERÂNCIA ABSOLUTA ESTÁ NA BASE, como v_a
    -- e v_b. Da 0023 até aqui ela era `p_tolerancia_abs * fator_da_DRE`: numa
    -- DRE em 'milhar', os 50.000 do default viravam R$ 50 MILHÕES, e qualquer
    -- divergência abaixo disso saía "confere". MEDIDO EM PRODUÇÃO (22/09/2026,
    -- somente leitura): das 33 despfin com resultado 'ok', 32 conferem de
    -- verdade com greatest(R$ 50.000, 5%) e 1 é falsa — R$ 12.400.000 de
    -- diferença saindo "confere". fn_reconciliar_mutuos (0123) já fazia assim
    -- ("tolerância em MOEDA BASE ... senão a checagem é mais frouxa justamente
    -- onde os valores são maiores"). Esta é a SEGUNDA mudança de resultado
    -- desta migration (a primeira é a parte 3) — ver o cabeçalho. MEDIDO
    -- (regra 2): com o `× fator` de volta, 2 asserts reprovam — o bloco 5 de
    -- motivo_especifico.test.sql (8.194 × 5.308 em milhar sai "ok") e o
    -- requisito despfin_tolerancia_na_base de instalacao.test.sql.
    v_tol := greatest(p_tolerancia_abs, abs(v_a) * p_tolerancia_pct);
    if v_div > v_tol then
      v_resultado := 'zona_cinzenta';
      v_partes := v_partes || format('%s: Despesa Financeira %s "%s" vs soma de %s contratos %s "%s" — diferença de %s na base',
        v_ano, v_despfin.valor_num, coalesce(v_despfin.unidade, 'sem escala'),
        v_juros.n, v_juros.soma, coalesce(v_unid_div, 'sem escala'), v_div);
      if v_pior_abs is null or v_div > v_pior_abs then
        v_pior_abs := v_div;
        v_pior_pct := case when v_a <> 0 then v_div / abs(v_a) end;
      end if;
    else
      v_partes := v_partes || format('%s: confere (Despesa Financeira %s "%s" = juros de %s contratos %s "%s", convertidos à mesma base)',
        v_ano, v_despfin.valor_num, coalesce(v_despfin.unidade, 'sem escala'),
        v_juros.n, v_juros.soma, coalesce(v_unid_div, 'sem escala'));
    end if;
    v_fonte_a := jsonb_build_object('chave', v_despfin.chave, 'valor', v_despfin.valor_num,
      'unidade', v_despfin.unidade, 'ano', v_ano, 'documento_versao_id', v_ver_dre);
    v_fonte_b := jsonb_build_object('soma_juros', v_juros.soma, 'n_contratos', v_juros.n,
      'unidade', v_unid_div, 'documento_versao_id', v_ver_div);
  end loop;

  if v_n = 0 then
    v_motivo_prec := fn_motivo_precondicao_agregado(v_motivos_ano);
    return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
      'despfin_dre_vs_divida', 'B', v_doc_dre, null, null,
      v_motivo_prec, null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      fn_motivo_precondicao_prefixo(v_motivo_prec)
      || 'DRE e Mapa de Dívida presentes, mas não foi possível localizar a Despesa Financeira da DRE '
      || 'e/ou as linhas de juros do mapa (rótulos extraídos não bateram). '
      || array_to_string(v_faltas, '; ') || '.'
      || coalesce(' ' || v_recado, ''));
  end if;

  return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
    'despfin_dre_vs_divida', 'B', v_doc_dre, v_fonte_a, v_fonte_b, v_resultado,
    v_pior_abs, v_pior_pct,
    jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct,
                       'anos_checados', v_n),
    format('Despesa Financeira da DRE vs juros do Mapa de Dívida em %s ano(s): %s.',
           v_n, array_to_string(v_partes, '; ')));
end;
$_$;

-- -----------------------------------------------------------------------------
-- (7) fn_reconciliar_receita_dre_vs_faturamento — REEMITIDA INTEIRA (corpo da
-- 0023). Mudanças: o motivo por exercício do lado da DRE, 'unidade_divergente'
-- no ramo de escala, e o texto por exercício. O lado do FATURAMENTO sem mês do
-- ano e o período sem ano ficam GENÉRICOS (ver o cabeçalho).
-- -----------------------------------------------------------------------------
create or replace function fn_reconciliar_receita_dre_vs_faturamento(p_caso_id uuid,
  p_entidade_id uuid, p_periodo_id uuid, p_tolerancia_abs numeric default 50000,
  p_tolerancia_pct numeric default 0.05)
returns jsonb
language plpgsql
as $$
declare
  v_doc_dre  uuid;
  v_doc_fat  uuid;
  v_ver_dre  uuid;
  v_ver_fat  uuid;
  v_col_ent  text;
  v_ano      int;
  v_col_per  text;
  v_receita  campo_extraido;
  v_soma_sec record;
  v_val_rec  numeric;
  v_unid_rec text;
  v_chave_rec text;
  v_fat      record;
  v_unid_fat text;
  v_motivo   text;
  v_a numeric; v_b numeric; v_div numeric; v_tol numeric;
  v_resultado text := 'ok';
  v_partes text[] := '{}';
  v_n int := 0;
  v_pior_abs numeric; v_pior_pct numeric;
  v_fonte_a jsonb; v_fonte_b jsonb;
  -- 0188
  v_motivos_ano text[] := '{}';
  v_faltas      text[] := '{}';
  v_motivo_prec text;
begin
  v_doc_dre := fn_documento_por_tipo(p_caso_id, p_entidade_id, p_periodo_id, 'DRE');
  v_doc_fat := fn_documento_por_tipo(p_caso_id, p_entidade_id, p_periodo_id, 'FATURAMENTO_24M');

  if v_doc_dre is null or v_doc_fat is null then
    return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
      'receita_dre_vs_faturamento', 'B', coalesce(v_doc_dre, v_doc_fat), null, null,
      'documento_ausente', null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      format('Sem par para reconciliar receita: %s não foi entregue para esta entidade/período.',
        case when v_doc_dre is null and v_doc_fat is null then 'DRE e Faturamento (24m)'
             when v_doc_dre is null then 'DRE' else 'Faturamento (24m)' end));
  end if;

  v_ver_dre  := fn_versao_atual(v_doc_dre);
  v_ver_fat  := fn_versao_atual(v_doc_fat);
  v_col_ent  := fn_coluna_entidade(v_ver_dre, p_entidade_id);
  v_unid_fat := fn_unidade_predominante(v_ver_fat);

  foreach v_ano in array fn_anos_alvo(p_periodo_id) loop
    if v_ano is null then
      -- sem ano não há como recortar o mês. 0188: motivo GENÉRICO de propósito.
      v_motivos_ano := v_motivos_ano || 'precondicao_nao_satisfeita'::text;
      v_faltas := v_faltas || 'o período não tem ano, e sem ano não há como recortar os meses do faturamento'::text;
      continue;
    end if;
    v_col_per := fn_coluna_periodo_do_ano(v_ver_dre, v_ano);

    select * into v_receita from fn_valor_conceito_col(v_ver_dre,
      array['receita', 'bruta'], array['liquida', 'deducoes', 'deducao'], v_col_ent, v_col_per);
    if v_receita.id is not null then
      v_val_rec := v_receita.valor_num; v_unid_rec := v_receita.unidade;
      v_chave_rec := v_receita.chave;
    else
      -- "RECEITA OPERACIONAL BRUTA" costuma ser CABEÇALHO SEM VALOR: soma as
      -- contas da seção (Vendas de produtos, Prestação de serviços...).
      select * into v_soma_sec from fn_soma_secao(v_ver_dre,
        array['receita', 'bruta'], v_col_ent, v_col_per,
        array['deducoes', 'deducao'],
        array['liquida', 'lucro bruto', 'resultado', 'prejuizo']);
      if coalesce(v_soma_sec.n_linhas, 0) = 0 then
        v_motivos_ano := v_motivos_ano || fn_motivo_do_lado(false, v_col_ent, v_col_per);
        v_faltas := v_faltas || format('%s: %s', v_ano,
          case when v_col_per = E'\x01' then 'a DRE não tem coluna deste exercício'
               when v_col_ent = E'\x01' then 'a DRE não tem coluna desta entidade'
               else 'a Receita Bruta da DRE não foi localizada (nem como linha, nem como seção)' end);
        continue;
      end if;
      v_val_rec := v_soma_sec.soma; v_unid_rec := v_soma_sec.unidade;
      v_chave_rec := format('soma de %s contas da seção Receita Bruta', v_soma_sec.n_linhas);
    end if;

    select soma, n_linhas into v_fat
    from fn_somar_faturamento_ano(v_ver_fat, v_ano::text, right(v_ano::text, 2));
    if coalesce(v_fat.n_linhas, 0) = 0 then
      -- 0188: GENÉRICO de propósito — "o relatório não tem este ano" e "o
      -- rótulo do mês não carrega o ano" são indistinguíveis daqui.
      v_motivos_ano := v_motivos_ano || 'precondicao_nao_satisfeita'::text;
      v_faltas := v_faltas || format('%s: o Faturamento não traz linha mensal deste ano', v_ano);
      continue;
    end if;

    v_motivo := fn_motivo_escala_incomparavel(v_unid_rec, v_unid_fat,
      'a Receita Bruta da DRE', 'o Faturamento mensal');
    if v_motivo is not null then
      return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
        'receita_dre_vs_faturamento', 'B', v_doc_dre, null, null,
        'unidade_divergente', null, null,
        jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
        fn_motivo_precondicao_prefixo('unidade_divergente') || v_motivo);
    end if;

    v_a := fn_valor_em_base(v_val_rec, v_unid_rec);
    v_b := fn_valor_em_base(v_fat.soma, v_unid_fat);
    v_n := v_n + 1;
    v_div := abs(v_a - v_b);
    v_tol := greatest(p_tolerancia_abs * coalesce(fn_fator_escala(v_unid_rec), 1),
                      abs(v_a) * p_tolerancia_pct);
    if v_div > v_tol then
      v_resultado := 'zona_cinzenta';
      v_partes := v_partes || format('%s: Receita Bruta %s vs %s meses de faturamento %s — diferença de %s '
        || '(Classe B: faturamento e receita reconhecida podem divergir por competência/recorte)',
        v_ano, v_val_rec, v_fat.n_linhas, v_fat.soma, v_div);
      if v_pior_abs is null or v_div > v_pior_abs then
        v_pior_abs := v_div;
        v_pior_pct := case when v_a <> 0 then v_div / abs(v_a) end;
      end if;
    else
      v_partes := v_partes || format('%s: confere (Receita Bruta %s = soma de %s meses %s)',
        v_ano, v_val_rec, v_fat.n_linhas, v_fat.soma);
    end if;
    v_fonte_a := jsonb_build_object('chave', v_chave_rec, 'valor', v_val_rec,
      'unidade', v_unid_rec, 'ano', v_ano, 'documento_versao_id', v_ver_dre);
    v_fonte_b := jsonb_build_object('soma_faturamento', v_fat.soma, 'n_meses', v_fat.n_linhas,
      'ano', v_ano, 'unidade', v_unid_fat, 'documento_versao_id', v_ver_fat);
  end loop;

  if v_n = 0 then
    v_motivo_prec := fn_motivo_precondicao_agregado(v_motivos_ano);
    return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
      'receita_dre_vs_faturamento', 'B', v_doc_dre, null, null,
      v_motivo_prec, null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      fn_motivo_precondicao_prefixo(v_motivo_prec)
      || 'DRE e Faturamento presentes, mas não foi possível casar Receita Bruta e meses do mesmo ano '
      || '(rótulos extraídos não bateram, ou o faturamento não traz o mês por linha). '
      || array_to_string(v_faltas, '; ') || '.');
  end if;

  return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
    'receita_dre_vs_faturamento', 'B', v_doc_dre, v_fonte_a, v_fonte_b, v_resultado,
    v_pior_abs, v_pior_pct,
    jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct,
                       'anos_checados', v_n),
    format('Receita Bruta da DRE vs faturamento mensal em %s ano(s): %s.',
           v_n, array_to_string(v_partes, '; ')));
end;
$$;

-- -----------------------------------------------------------------------------
-- (8) fn_exigencias_do_caso — REEMITIDA INTEIRA (corpo da 0157), com duas
-- colunas novas no FIM do retorno: alternativa_rotulo e alternativa_recado. Só
-- vêm preenchidas quando a exigência NÃO está satisfeita. Mudar o tipo de
-- retorno exige drop; o grant e o comentário são refeitos logo abaixo.
-- -----------------------------------------------------------------------------
drop function if exists fn_exigencias_do_caso(uuid);

create function fn_exigencias_do_caso(p_caso_id uuid)
returns table(exigencia_id uuid, tipo_taxonomia text, conceito text, rotulo text, origem text,
              depende_de text[], severidade text, sobrepujavel boolean, descricao text,
              entidade text, entidade_id uuid, satisfeita boolean,
              alternativa_rotulo text, alternativa_recado text)
language sql stable
as $$
  -- UMA CHAMADA POR TIPO, E NÃO POR DOCUMENTO — e o `materialized` é a metade
  -- que faz a diferença existir. A forma herdada da 0113 rodava
  -- `fn_linhas_do_tipo` uma vez por DOCUMENTO (662 ms de 914 num caso de 400
  -- documentos), e separar em duas CTEs simples não mudou nada, porque o
  -- Postgres achata CTE e empurra o filtro de volta para baixo do agrupamento.
  -- É a palavra `materialized` que impede isso; sem ela este comentário estaria
  -- descrevendo uma otimização que não acontece.
  with tipos_do_caso as materialized (
    select distinct d.tipo_taxonomia from documento d where d.caso_id = p_caso_id
    union
    -- Revisão da 0157 (achado C): quando NENHUM documento está rotulado
    -- COMBINADO mas algum SERVE como COMBINADO por estrutura
    -- (fn_documento_serve_como), o tipo precisa entrar aqui do mesmo jeito —
    -- senão as exigências de linha do COMBINADO nunca aparecem no resultado
    -- desta função: nem satisfeitas, nem ausentes, silêncio puro.
    select 'COMBINADO'
     where exists (
       select 1 from documento d
       where d.caso_id = p_caso_id and fn_documento_serve_como(d.id, 'COMBINADO')
     )
  ),
  -- Revisão da 0157 (achado C): "tem conteúdo" pergunta pelo tipo SERVIDO
  -- (fn_documento_serve_como), com fn_linhas_do_tipo mantida como a resposta
  -- para todo tipo que não seja COMBINADO — é a única exceção que
  -- fn_documento_serve_como conhece, então nenhum outro tipo muda de
  -- comportamento aqui. Para COMBINADO, soma-se um segundo caminho: qualquer
  -- documento que SIRVA como COMBINADO e tenha rendido alguma linha.
  tipos_com_conteudo as (
    select t.tipo_taxonomia from tipos_do_caso t
    where fn_linhas_do_tipo(p_caso_id, t.tipo_taxonomia) > 0
       or (
         t.tipo_taxonomia = 'COMBINADO'
         and exists (
           select 1
           from documento d
           join documento_versao dv on dv.documento_id = d.id and dv.id = fn_versao_com_extracao(d.id)
           join campo_extraido ce on ce.documento_versao_id = dv.id
           where d.caso_id = p_caso_id
             and fn_documento_serve_como(d.id, 'COMBINADO')
         )
       )
  ),
  -- A VERSÃO VIGENTE DE CADA DOCUMENTO, resolvida UMA vez (lição de custo da
  -- 0101), e — 0146 — QUANTAS COLUNAS DE ENTIDADE o documento declara.
  --
  -- É esse número que decide se a capa do documento pode responder pela linha
  -- que não tem coluna. Uma coluna (ou nenhuma): o documento é de uma empresa e
  -- a capa é a única fonte. Mais de uma: o documento já disse de quem é cada
  -- número, e a capa não responde por ninguém.
  docs as (
    select d.id, d.tipo_taxonomia, ent.razao_social as ent_doc,
           v.versao,
           (select count(distinct ce.entidade_coluna) from campo_extraido ce
             where ce.documento_versao_id = v.versao and ce.valor_num is not null) > 1
             as multi_entidade,
           -- Revisão da 0157 (achado C): este documento SERVE como COMBINADO —
           -- pelo rótulo ou pela estrutura (fn_documento_serve_como, que já
           -- filtra fonte permitida e exige conteúdo — achados B e A).
           -- Calculado uma vez por documento, não por linha extraída.
           fn_documento_serve_como(d.id, 'COMBINADO') as serve_combinado
    from documento d
    left join entidade ent on ent.id = d.entidade_id
    cross join lateral (select fn_versao_com_extracao(d.id) as versao) v
    where d.caso_id = p_caso_id
  ),
  campos as (
    select dc.tipo_taxonomia,
           ce.chave, ce.secao, ce.secao_canonica,
           -- 0145: o outro eixo da matriz.
           ce.periodo_coluna as coluna,
           -- 0146: a capa só responde pela linha sem coluna quando o documento é
           -- de UMA empresa. Num documento de várias, a linha sem coluna fica sem
           -- entidade — ela vale para o caso, não para a capa.
           case when dc.multi_entidade then ce.entidade_coluna
                else coalesce(ce.entidade_coluna, dc.ent_doc) end as ent_txt
    from docs dc
    join campo_extraido ce on ce.documento_versao_id = dc.versao
    where ce.valor_num is not null

    union all

    -- Revisão da 0157 (achado C): um documento rotulado diferente (ex.:
    -- BALANCO) que SERVE como COMBINADO por estrutura entra AQUI TAMBÉM, sob
    -- o tipo COMBINADO — ADITIVO, não substitui: ele continua contando para
    -- o seu próprio tipo rotulado no ramo acima. Sem este ramo, as linhas
    -- dele nunca casam contra `taxonomia_linha_exigida` de COMBINADO, e as
    -- 3 exigências (ativo_total, caixa_e_equivalentes, passivo_mais_pl) ficam
    -- mudas em vez de avaliadas — medido lado a lado contra o mesmo dado
    -- rotulado COMBINADO, que abre a pendência normalmente.
    select 'COMBINADO' as tipo_taxonomia,
           ce.chave, ce.secao, ce.secao_canonica,
           ce.periodo_coluna as coluna,
           case when dc.multi_entidade then ce.entidade_coluna
                else coalesce(ce.entidade_coluna, dc.ent_doc) end as ent_txt
    from docs dc
    join campo_extraido ce on ce.documento_versao_id = dc.versao
    where ce.valor_num is not null
      and dc.tipo_taxonomia <> 'COMBINADO'
      and dc.serve_combinado
  ),
  -- O NOME vira ENTIDADE REGISTRADA uma vez por nome DISTINTO (lição da 0101:
  -- fn_mesma_entidade custa; pagar por ocorrência seria pagar 770 vezes por
  -- ~10 respostas). Nome que não casa com registro nenhum fica NULL.
  nomes_resolvidos as (
    select n.ent_txt,
           (select e.id from entidade e
             where e.caso_id = p_caso_id
               and fn_mesma_entidade(n.ent_txt, e.razao_social)
             order by e.razao_social, e.id limit 1) as entidade_id
    from (select distinct c.ent_txt from campos c where c.ent_txt is not null) n
  ),
  campos_ent as (
    select c.*, nr.entidade_id
    from campos c
    left join nomes_resolvidos nr on nr.ent_txt = c.ent_txt
  ),
  -- O CASAMENTO exigência × rótulo é avaliado uma vez por LINHA DISTINTA
  -- (mesma lição): fn_normalizar_texto por (rótulo × termo) é o custo.
  linhas_distintas as (
    select distinct c.tipo_taxonomia, c.chave, c.secao, c.secao_canonica, c.coluna
    from campos c
  ),
  casadas as (
    select e.id as exigencia_id, ld.tipo_taxonomia, ld.chave, ld.secao,
           ld.secao_canonica, ld.coluna
    from taxonomia_linha_exigida e
    join linhas_distintas ld on ld.tipo_taxonomia = e.tipo_taxonomia
    where e.ativo
      and case e.checagem
        when 'secao_presente' then ld.secao_canonica = e.secao_canonica
        when 'serie_mensal'   then fn_mes_do_rotulo(ld.chave) is not null
        else exists (
          select 1 from taxonomia_linha_localizador l
          -- O ALVO do casamento, escolhido pelo modo (0145).
          cross join lateral (select fn_normalizar_texto(
            case l.contra
              when 'secao'  then coalesce(ld.secao, '')
              when 'coluna' then coalesce(ld.coluna, '')
              else ld.chave
            end) as alvo) a
          where l.exigencia_id = e.id
            and case
              when l.contra = 'estrutural' then fn_rotulo_estrutural(ld.chave, l.termos_inclui)
              else
                not exists (
                  select 1 from unnest(l.termos_inclui) t
                  where a.alvo not like '%' || fn_normalizar_texto(t) || '%')
                and not exists (
                  select 1 from unnest(l.termos_exclui) t
                  where a.alvo like '%' || fn_normalizar_texto(t) || '%')
            end)
      end
  ),
  -- Quais (exigência, entidade) estão SATISFEITAS: a linha casada volta às
  -- ocorrências para saber DE QUEM ela é.
  satisfazedores as (
    select distinct ca.exigencia_id, c.entidade_id
    from casadas ca
    join campos_ent c
      on c.tipo_taxonomia = ca.tipo_taxonomia
     and c.chave = ca.chave
     and c.secao is not distinct from ca.secao
     and c.secao_canonica is not distinct from ca.secao_canonica
     and c.coluna is not distinct from ca.coluna
  ),
  -- 0188: AS ALTERNATIVAS — o que o documento traz NO LUGAR da linha exigida.
  -- Mesmo casamento (substring do texto normalizado, alvo pelo modo) e a MESMA
  -- volta às ocorrências para saber de quem é: uma atribuição de entidade só,
  -- a desta função (ver o cabeçalho da 0188). Só as exigências que TÊM
  -- alternativa entram no join, então o custo fica restrito a elas.
  alternativas_casadas as (
    select a.exigencia_id, a.ordem, a.recado, ld.tipo_taxonomia, ld.chave, ld.secao,
           ld.secao_canonica, ld.coluna
    from taxonomia_linha_alternativa a
    join taxonomia_linha_exigida e on e.id = a.exigencia_id and e.ativo
    join linhas_distintas ld on ld.tipo_taxonomia = e.tipo_taxonomia
    cross join lateral (select fn_normalizar_texto(
      case a.contra
        when 'secao'  then coalesce(ld.secao, '')
        when 'coluna' then coalesce(ld.coluna, '')
        else ld.chave
      end) as alvo) x
    where not exists (
            select 1 from unnest(a.termos_inclui) t
            where x.alvo not like '%' || fn_normalizar_texto(t) || '%')
      and not exists (
            select 1 from unnest(a.termos_exclui) t
            where x.alvo like '%' || fn_normalizar_texto(t) || '%')
  ),
  alternativas_por_entidade as (
    select distinct ac.exigencia_id, c.entidade_id, ac.ordem, ac.chave, ac.recado
    from alternativas_casadas ac
    join campos_ent c
      on c.tipo_taxonomia = ac.tipo_taxonomia
     and c.chave = ac.chave
     and c.secao is not distinct from ac.secao
     and c.secao_canonica is not distinct from ac.secao_canonica
     and c.coluna is not distinct from ac.coluna
  ),
  -- O EIXO: entidades registradas que TROUXERAM linha do tipo. Quem tem
  -- documento mas nenhuma linha atribuível não entra — cobrar conteúdo de quem
  -- não tem conteúdo é assunto da 0036/0112, não daqui. E, desde a 0146, "linha
  -- atribuível" quer dizer atribuída PELO DOCUMENTO quando ele sabe atribuir.
  eixo as (
    select distinct c.tipo_taxonomia, c.entidade_id
    from campos_ent c
    where c.entidade_id is not null
  )
  select e.id, e.tipo_taxonomia, e.conceito, e.rotulo, e.origem, e.depende_de,
         e.severidade, e.sobrepujavel, e.descricao,
         ent.razao_social, ax.entidade_id,
         s.satisfeita,
         alt.chave, alt.recado
  from taxonomia_linha_exigida e
  join tipos_com_conteudo t on t.tipo_taxonomia = e.tipo_taxonomia
  join taxonomia_tipo_documento tx on tx.codigo = e.tipo_taxonomia
  cross join lateral (
    -- Escopo entidade COM eixo: uma linha por entidade. Senão: a linha única
    -- com entidade NULL (escopo caso, ou fallback nº 2 do cabeçalho da 0119).
    select x.entidade_id
    from eixo x
    where x.tipo_taxonomia = e.tipo_taxonomia
      and coalesce(e.escopo_entidade, tx.granularidade::text in ('entidade', 'entidade_periodo'))
    union all
    select null::uuid
    where not (coalesce(e.escopo_entidade, tx.granularidade::text in ('entidade', 'entidade_periodo'))
               and exists (select 1 from eixo x2 where x2.tipo_taxonomia = e.tipo_taxonomia))
  ) ax
  cross join lateral (
    select case when ax.entidade_id is null
                then exists (select 1 from satisfazedores s where s.exigencia_id = e.id)
                else exists (select 1 from satisfazedores s
                              where s.exigencia_id = e.id and s.entidade_id = ax.entidade_id)
           end as satisfeita
  ) s
  -- 0188: a alternativa só é procurada para o que NÃO está satisfeito — ela
  -- nunca satisfaz, só muda o que a pendência diz.
  left join lateral (
    select ap.chave, ap.recado
    from alternativas_por_entidade ap
    where not s.satisfeita
      and ap.exigencia_id = e.id
      and (ax.entidade_id is null or ap.entidade_id = ax.entidade_id)
    order by ap.ordem, ap.chave
    limit 1
  ) alt on true
  left join entidade ent on ent.id = ax.entidade_id
  where e.ativo;
$$;

comment on function fn_exigencias_do_caso(uuid) is
  'Exigências de linha aplicáveis ao caso (tipos presentes COM conteúdo), com satisfeita s/n. '
  'Casa contra a versão VIGENTE (0102), pela chave, pela seção, pela COLUNA (0145) ou pelo '
  'rótulo estrutural. Num documento que declara VÁRIAS colunas de entidade, a linha sem coluna '
  'não é atribuída à capa (0146). Desde a revisão da 0157 (achado C), um documento que SERVE '
  'como COMBINADO por estrutura (rotulado BALANCO/DRE/FLUXO_CAIXA, fn_documento_serve_como) tem '
  'suas linhas avaliadas TAMBÉM sob COMBINADO, além do seu próprio tipo rotulado — sem isso as 3 '
  'exigências do item (ativo_total, caixa_e_equivalentes, passivo_mais_pl) ficavam mudas assim '
  'que o passo 1 de fn_recomputar_completude parou de exigir o rótulo exato. 0188: quando a '
  'exigência NÃO está satisfeita e uma linha de taxonomia_linha_alternativa casa para a mesma '
  'entidade, alternativa_rotulo diz qual linha o documento traz no lugar e alternativa_recado o '
  'que a pendência deve dizer (a alternativa nunca satisfaz). Alimenta o passo 2b de '
  'fn_recomputar_completude e a tela do caso.';

grant all on function fn_exigencias_do_caso(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- (9) O TEXTO DA PENDÊNCIA DE LINHA EXIGIDA — um lugar só, lido pelo recompute
-- e pelo UPDATE dirigido da seção 11. Sem alternativa, é BYTE A BYTE o texto
-- que fn_recomputar_completude (0119/0157) montava inline.
-- -----------------------------------------------------------------------------
create or replace function fn_descricao_linha_exigida(p_tipo text, p_entidade text, p_rotulo text,
  p_depende_de text[], p_origem text, p_alternativa_rotulo text, p_alternativa_recado text)
returns text
language sql stable
as $$
  select case
    when p_alternativa_recado is not null and p_entidade is not null then
      format('Nos documentos de %s da entidade "%s", a linha exigida "%s" não existe como tal: o '
             'documento traz "%s" no lugar. %s Sem a linha exigida, PARA ESTA ENTIDADE: %s.%s',
             p_tipo, p_entidade, p_rotulo, p_alternativa_rotulo, p_alternativa_recado,
             array_to_string(p_depende_de, '; '),
             case when p_origem = 'proposta'
                  then ' (Exigência PROPOSTA na análise — nenhuma checagem automática a lê hoje.)'
                  else '' end)
    when p_alternativa_recado is not null then
      format('O tipo %s chegou e rendeu linhas, mas a linha exigida "%s" não existe como tal: o '
             'documento traz "%s" no lugar. %s Sem a linha exigida: %s.%s',
             p_tipo, p_rotulo, p_alternativa_rotulo, p_alternativa_recado,
             array_to_string(p_depende_de, '; '),
             case when p_origem = 'proposta'
                  then ' (Exigência PROPOSTA na análise — nenhuma checagem automática a lê hoje.)'
                  else '' end)
    when p_entidade is not null then
      format('Nos documentos de %s da entidade "%s", a linha exigida "%s" não foi '
             'localizada na versão vigente. Sem ela, PARA ESTA ENTIDADE: %s.%s Conferir '
             'se o documento dela traz a linha com outro rótulo (e corrigir na revisão) '
             'ou reenviar o arquivo completo.',
             p_tipo, p_entidade, p_rotulo,
             array_to_string(p_depende_de, '; '),
             case when p_origem = 'proposta'
                  then ' (Exigência PROPOSTA na análise — nenhuma checagem automática a lê hoje.)'
                  else '' end)
    else
      format('O tipo %s chegou e rendeu linhas, mas a linha exigida "%s" não foi '
             'localizada na versão vigente de nenhum documento do tipo. Sem ela: %s.%s '
             'Conferir se o documento traz a linha com outro rótulo (e corrigir na '
             'revisão) ou reenviar o arquivo completo.',
             p_tipo, p_rotulo,
             array_to_string(p_depende_de, '; '),
             case when p_origem = 'proposta'
                  then ' (Exigência PROPOSTA na análise — nenhuma checagem automática a lê hoje.)'
                  else '' end)
  end;
$$;

comment on function fn_descricao_linha_exigida(text, text, text, text[], text, text, text) is
  '0188: a descrição da pendência linha_exigida_ausente. Sem alternativa, o texto de sempre '
  '(0119/0157: "não foi localizada … conferir o rótulo ou reenviar"); com alternativa, o que o '
  'documento traz no lugar e o recado de taxonomia_linha_alternativa.';

-- -----------------------------------------------------------------------------
-- (10) fn_recomputar_completude — REEMITIDA INTEIRA (corpo da 0157). Mudanças,
-- só no passo (2b): a descrição sai de fn_descricao_linha_exigida (com o
-- recado da alternativa), e no ramo em que a pendência JÁ EXISTE a descrição é
-- atualizada junto com a severidade — sem isso as 50 de produção nunca mudam.
-- -----------------------------------------------------------------------------
create or replace function fn_recomputar_completude(p_caso_id uuid)
returns jsonb
language plpgsql
as $$
declare
  v_faltantes text[];
  v_sem_conteudo text[];
  v_cod text;
  v_nao_sobre boolean;
  v_status_atual caso_status;
  v_novo_status caso_status;
  v_pend_id uuid;
  -- 0113/0119: passo (2b)
  v_ex record;
  v_motivo text;
  v_motivos_ausentes text[] := '{}';
  v_linhas_ausentes jsonb := '[]'::jsonb;
  -- 0188
  v_desc text;
begin
  -- ----- (1) obrigatório sem NENHUM documento QUE SIRVA (0006/0157) ----------
  -- 0157: "sem documento" deixava de contar um documento que ESTÁ no caso só
  -- porque o classificador o rotulou diferente do que ele estruturalmente é —
  -- medido no lote 7377, dois COMBINADOs (8 empresas na planilha) chamados de
  -- BALANCO travavam o item COMBINADO como ausente e bloqueante. Agora a
  -- pergunta é fn_documento_serve_como(documento, tipo): a regra do rótulo,
  -- mais — só para COMBINADO — a decisão de fn_combinado_estrutural_apto
  -- (revisão da 0157, achados A e B: fonte permitida e conteúdo exigido).
  select array_agg(t.codigo order by t.codigo) into v_faltantes
  from taxonomia_tipo_documento t
  where t.obrigatoriedade = 'obrigatorio'
    and not exists (
      select 1 from documento d
      where d.caso_id = p_caso_id and fn_documento_serve_como(d.id, t.codigo)
    );
  v_faltantes := coalesce(v_faltantes, array[]::text[]);

  update pendencia p set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:n8n'
  where p.caso_id = p_caso_id and p.tipo = 'item_faltante' and p.estado <> 'resolvida'
    and not (p.descricao = any (select 'Item obrigatório do Kit Básico ausente: '||x from unnest(v_faltantes) x));

  foreach v_cod in array v_faltantes loop
    select nao_sobrepujavel into v_nao_sobre from taxonomia_tipo_documento where codigo = v_cod;
    if not exists (
      select 1 from pendencia p
      where p.caso_id = p_caso_id and p.tipo = 'item_faltante'
        and p.estado <> 'resolvida'
        and p.descricao = 'Item obrigatório do Kit Básico ausente: '||v_cod
    ) then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao)
        values (p_caso_id, 'completude', 'item_faltante', 'bloqueante',
                not coalesce(v_nao_sobre,false),
                'Item obrigatório do Kit Básico ausente: '||v_cod);
    end if;
  end loop;

  -- ----- (2) obrigatório PRESENTE mas sem uma linha aproveitável (0036) ------
  select array_agg(t.codigo order by t.codigo) into v_sem_conteudo
  from taxonomia_tipo_documento t
  where t.obrigatoriedade = 'obrigatorio'
    and exists (
      select 1 from documento d
      where d.caso_id = p_caso_id and d.tipo_taxonomia = t.codigo
    )
    and fn_linhas_do_tipo(p_caso_id, t.codigo) = 0;
  v_sem_conteudo := coalesce(v_sem_conteudo, array[]::text[]);

  update pendencia p set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:extracao'
  where p.caso_id = p_caso_id and p.tipo = 'item_sem_conteudo' and p.estado <> 'resolvida'
    and not (p.motivo = any (select 'completude:sem_conteudo:'||x from unnest(v_sem_conteudo) x));

  foreach v_cod in array v_sem_conteudo loop
    if not exists (
      select 1 from pendencia p
      where p.caso_id = p_caso_id and p.tipo = 'item_sem_conteudo'
        and p.estado <> 'resolvida' and p.motivo = 'completude:sem_conteudo:'||v_cod
    ) then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, motivo)
        values (p_caso_id, 'completude', 'item_sem_conteudo', 'bloqueante', false,
                format('Item obrigatório "%s" foi RECEBIDO, mas nenhuma linha foi extraída de nenhuma '
                       'versão dele: o documento existe e o book sai VAZIO nesta parte. Causas comuns: '
                       'formato que o pipeline ainda não converte (.xlsx/.docx), arquivo ilegível, ou '
                       'chamada de extração que falhou. Conferir o arquivo e reenviar — completude não '
                       'é validade (Arquitetura do Sistema/3 Estado e Execução/07), e um obrigatório sem conteúdo não passa o Portão 2.',
                       v_cod),
                'completude:sem_conteudo:'||v_cod);
    end if;
  end loop;

  -- ----- (2b) 0113/0119: tipo COM conteúdo, mas sem uma LINHA exigida --------
  -- 0119: a cobrança desce ao nível da ENTIDADE quando o escopo pede. O motivo
  -- ganha o sufixo canônico da entidade (chave estável mesmo que a grafia da
  -- razão social varie entre extrações), `entidade_id` vai na pendência, e a
  -- descrição nomeia a empresa. Pendência de formato velho (sem sufixo) sai da
  -- lista corrente e é resolvida no fim do bloco — é a transição, e a trilha
  -- guarda as duas gerações.
  for v_ex in
    select * from fn_exigencias_do_caso(p_caso_id) x where not x.satisfeita
  loop
    v_motivo := 'completude:linha_exigida:' || v_ex.tipo_taxonomia || ':' || v_ex.conceito
                || case when v_ex.entidade is not null
                        then ':' || fn_entidade_canonica(v_ex.entidade)
                        else '' end;
    v_motivos_ausentes := v_motivos_ausentes || v_motivo;
    v_linhas_ausentes := v_linhas_ausentes || jsonb_build_object(
      'tipo', v_ex.tipo_taxonomia, 'conceito', v_ex.conceito,
      'rotulo', v_ex.rotulo, 'origem', v_ex.origem,
      'entidade', v_ex.entidade,
      -- 0188: o que o documento traz no lugar, quando traz.
      'alternativa', v_ex.alternativa_rotulo);

    -- 0188: o texto sai de UM lugar, com o recado da alternativa quando ela
    -- casou (taxonomia_linha_alternativa). Sem alternativa, é o texto de sempre.
    v_desc := fn_descricao_linha_exigida(v_ex.tipo_taxonomia, v_ex.entidade, v_ex.rotulo,
                                         v_ex.depende_de, v_ex.origem,
                                         v_ex.alternativa_rotulo, v_ex.alternativa_recado);

    select id into v_pend_id from pendencia p
    where p.caso_id = p_caso_id and p.tipo = 'linha_exigida_ausente'
      and p.estado <> 'resolvida'
      and p.motivo = v_motivo
    limit 1;

    if v_pend_id is null then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel,
                             descricao, entidade_id, motivo)
        values (p_caso_id, 'completude', 'linha_exigida_ausente',
                coalesce(v_ex.severidade, 'importante')::pendencia_severidade,
                coalesce(v_ex.sobrepujavel, true),
                v_desc,
                v_ex.entidade_id,
                v_motivo);
    else
      -- 0188: a DESCRIÇÃO também é atualizada. Até a 0187 só a política era, e
      -- a pendência aberta antes de uma alternativa existir ficava para sempre
      -- com o texto da doença errada.
      update pendencia set
        severidade   = coalesce(v_ex.severidade, 'importante')::pendencia_severidade,
        sobrepujavel = coalesce(v_ex.sobrepujavel, true),
        descricao    = case when descricao is distinct from v_desc then v_desc else descricao end
      where id = v_pend_id;
    end if;
  end loop;

  -- A linha apareceu, a exigência foi desativada, ou o formato do motivo mudou
  -- (a transição 0113 → 0119): resolve sozinha, como as da 0036.
  update pendencia p set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:extracao'
  where p.caso_id = p_caso_id and p.tipo = 'linha_exigida_ausente' and p.estado <> 'resolvida'
    and not (p.motivo = any (v_motivos_ausentes));

  -- ----- (3) o checklist reflete os três estados (0036) ----------------------
  update checklist_item_status c
    set status = case
                   when fn_linhas_do_tipo(p_caso_id, c.tipo_taxonomia) = 0 then 'recebido_nao_valido'
                   else 'presente'
                 end,
        atualizado_em = now()
  where c.caso_id = p_caso_id
    and c.documento_id is not null
    and c.status in ('presente', 'recebido_nao_valido');

  -- ----- (4) status do caso: Portão 1 continua sendo CHEGADA (0036) ----------
  select status into v_status_atual from caso where id = p_caso_id;
  if array_length(v_faltantes,1) is null then
    v_novo_status := 'completude_ok';
  else
    v_novo_status := 'em_triagem';
  end if;

  if v_status_atual in ('intake','em_triagem','completude_ok') and v_novo_status <> v_status_atual then
    update caso set status = v_novo_status where id = p_caso_id;
    insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
      values ('sistema:n8n', 'transicao_status', 'caso:'||p_caso_id,
              jsonb_build_object('status', v_status_atual),
              jsonb_build_object('status', v_novo_status));
  end if;

  return jsonb_build_object(
    'portao1_ok', array_length(v_faltantes,1) is null,
    'faltantes', to_jsonb(v_faltantes),
    'sem_conteudo', to_jsonb(v_sem_conteudo),
    -- 0119: cada ausência agora pode nomear a entidade. `pronto_para_revisao`
    -- segue intocado — endurecê-lo é decisão de produto do dono, não efeito
    -- colateral (0113).
    'linhas_exigidas_ausentes', v_linhas_ausentes,
    'pronto_para_revisao',
      array_length(v_faltantes,1) is null and array_length(v_sem_conteudo,1) is null,
    'status', v_novo_status
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- (11) O UPDATE DIRIGIDO — só o TEXTO das pendências `aberta` da exigência
-- pedida cuja entidade tem a alternativa. NÃO é recompute: não abre, não
-- resolve, não mexe em severidade, não toca em aceita_com_ressalva. Lê
-- fn_exigencias_do_caso (a mesma fonte do recompute, para o texto ser idêntico
-- ao que o próximo recompute escreveria) só nos casos que TÊM uma pendência
-- dessas aberta.
--
-- É FUNÇÃO, e não um bloco anônimo, pela mesma razão da
-- fn_resolver_linha_exigida_superada (0187): o que ela faz tem de ser
-- exercitado por teste (bloco 4 de motivo_especifico.test.sql) — um `do $$`
-- dentro da migration roda uma vez, num banco vazio, e reescreve ZERO linhas
-- por construção. O alcance em produção é medido ANTES com a consulta do
-- Supabase/README.md. Sem grant: ação de migration/service_role.
-- -----------------------------------------------------------------------------
create or replace function fn_reescrever_recado_linha_exigida(p_tipo text, p_conceito text)
returns jsonb
language plpgsql
as $$
declare
  v_caso    uuid;
  v_ex      record;
  v_motivo  text;
  v_n       int;
  v_total   int := 0;
  v_casos   int := 0;
  v_abertas int;
  v_prefixo text := 'completude:linha_exigida:' || p_tipo || ':' || p_conceito;
begin
  -- `like` com o conceito escapado: '_' é curinga, e despesa_financeira o tem.
  select count(*) into v_abertas
    from pendencia
   where tipo = 'linha_exigida_ausente' and estado = 'aberta'
     and (motivo = v_prefixo
          or motivo like replace(v_prefixo, '_', '\_') || ':%');

  for v_caso in
    select distinct caso_id from pendencia
     where tipo = 'linha_exigida_ausente' and estado = 'aberta'
       and (motivo = v_prefixo
            or motivo like replace(v_prefixo, '_', '\_') || ':%')
  loop
    v_casos := v_casos + 1;
    for v_ex in
      select * from fn_exigencias_do_caso(v_caso) x
       where x.tipo_taxonomia = p_tipo and x.conceito = p_conceito
         and not x.satisfeita and x.alternativa_recado is not null
    loop
      -- O MESMO motivo que fn_recomputar_completude monta (0119).
      v_motivo := 'completude:linha_exigida:' || v_ex.tipo_taxonomia || ':' || v_ex.conceito
                  || case when v_ex.entidade is not null
                          then ':' || fn_entidade_canonica(v_ex.entidade) else '' end;
      update pendencia
         set descricao = fn_descricao_linha_exigida(v_ex.tipo_taxonomia, v_ex.entidade,
                           v_ex.rotulo, v_ex.depende_de, v_ex.origem,
                           v_ex.alternativa_rotulo, v_ex.alternativa_recado)
       where caso_id = v_caso and tipo = 'linha_exigida_ausente' and estado = 'aberta'
         and motivo = v_motivo
         and descricao is distinct from fn_descricao_linha_exigida(v_ex.tipo_taxonomia,
                           v_ex.entidade, v_ex.rotulo, v_ex.depende_de, v_ex.origem,
                           v_ex.alternativa_rotulo, v_ex.alternativa_recado);
      get diagnostics v_n = row_count;
      v_total := v_total + v_n;
    end loop;
  end loop;

  return jsonb_build_object('abertas', v_abertas, 'casos_olhados', v_casos,
                            'reescritas', v_total);
end;
$$;

comment on function fn_reescrever_recado_linha_exigida(text, text) is
  '0188: reescreve SÓ a descrição das pendências linha_exigida_ausente ABERTAS da exigência '
  '(tipo, conceito) cuja entidade tem alternativa em taxonomia_linha_alternativa — o texto que o '
  'próximo recompute escreveria. Não abre, não resolve, não toca em aceita_com_ressalva. Ação de '
  'migration/service_role — sem grant para o portal.';

do $$
declare
  v_r jsonb;
begin
  v_r := fn_reescrever_recado_linha_exigida('DRE', 'despesa_financeira');
  raise notice '0188 texto das pendências DRE/despesa_financeira: % de % aberta(s), em % caso(s) '
    'olhado(s), passaram a dizer o que a DRE traz no lugar; as outras continuam com o texto de '
    'antes (sem alternativa que case, ou exigência já satisfeita — o próximo recompute resolve '
    'estas)', v_r->>'reescritas', v_r->>'abertas', v_r->>'casos_olhados';
end $$;

-- -----------------------------------------------------------------------------
-- (12) O CATÁLOGO DA SONDA
-- -----------------------------------------------------------------------------
create or replace view instalacao_sonda_exigencias_0188 as
  select e.tipo_taxonomia, e.conceito, 'alternativa_resultado_liquido'::text as mudanca
    from taxonomia_linha_alternativa a
    join taxonomia_linha_exigida e on e.id = a.exigencia_id
   where e.tipo_taxonomia = 'DRE' and e.conceito = 'despesa_financeira' and e.ativo
     and a.termos_inclui = array['resultado', 'financeiro']::text[]
  union all
  select e.tipo_taxonomia, e.conceito, 'localizador_juros_bancarios'
    from taxonomia_linha_localizador l
    join taxonomia_linha_exigida e on e.id = l.exigencia_id
   where e.tipo_taxonomia = 'DRE' and e.conceito = 'despesa_financeira' and e.ativo
     and l.contra = 'chave' and l.termos_inclui = array['juros', 'bancari']::text[];

comment on view instalacao_sonda_exigencias_0188 is
  'Sonda da 0188: a alternativa "resultado financeiro" de DRE/despesa_financeira e o localizador '
  '["juros","bancari"] da mesma exigência. Duas linhas.';

grant select on instalacao_sonda_exigencias_0188 to authenticated;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values

  ('registrar_devolve_resultado_achatado', '0188', 'corpo', 'fn_registrar_reconciliacao',
   '''resultado'', v_res_retorno', null,
   'Com as checagens da 0188 e a fn_registrar_reconciliacao da 0186, o resultado DEVOLVIDO sai '
   'cru (linha_nao_localizada…) e os despachantes (0152) param o laço de períodos no primeiro: '
   'menos linhas em reconciliacao, e checagem que concluiria no período seguinte deixa de '
   'concluir. É o requisito que segura o invariante da parte 1.',
   'bloqueante', 800),

  ('motivo_especifico_ativo_passivo_pl', '0188', 'corpo', 'fn_reconciliar_ativo_passivo_pl',
   'fn_motivo_precondicao_agregado(v_motivos_ano)', null,
   'Sem o corpo da 0188, a precondição do Ativo × Passivo+PL continua gravando "motivo não '
   'especificado" onde o código sabe se foi linha não localizada ou exercício sem coluna.',
   'importante', 801),

  ('motivo_especifico_caixa_bp_fluxo', '0188', 'corpo', 'fn_reconciliar_caixa_bp_fluxo',
   'fn_motivo_precondicao_agregado(v_motivos_ano)', null,
   'Sem o corpo da 0188, Caixa × DFC grava o genérico — inclusive quando a escala não é '
   'conversível (unidade_divergente).',
   'importante', 802),

  ('motivo_especifico_despfin', '0188', 'corpo', 'fn_reconciliar_despfin_dre_vs_divida',
   'fn_motivo_precondicao_agregado(v_motivos_ano)', null,
   'Sem o corpo da 0188, Despesa financeira × Mapa de dívida grava o genérico, e o texto não diz '
   'que a DRE traz o resultado LÍQUIDO no lugar da despesa bruta.',
   'importante', 803),

  ('despfin_juros_bancarios', '0188', 'corpo', 'fn_reconciliar_despfin_dre_vs_divida',
   'array[''juros'', ''bancari''], array[''receita'', ''aplicac''], v_col_ent, v_col_per)', null,
   'Sem o localizador, a DRE que publica "JUROS E COMISSÕES BANCÁRIAS" não concilia com o mapa '
   'de dívida — e o seed da exigência, que tem o mesmo localizador, diria o contrário da '
   'checagem (1 pendência falsa medida em produção, 22/09/2026).',
   'importante', 804),

  ('despfin_tolerancia_na_base', '0188', 'corpo', 'fn_reconciliar_despfin_dre_vs_divida',
   'v_tol := greatest(p_tolerancia_abs, abs(v_a) * p_tolerancia_pct)', null,
   'Sem este corpo, a tolerância absoluta da despesa financeira é multiplicada pela escala da '
   'DRE: em milhar, R$ 50 MILHÕES. Medido em produção (22/09/2026): 1 das 33 despfin "ok" era '
   'falsa, R$ 12.400.000 de diferença saindo "confere".',
   'importante', 815),

  ('motivo_especifico_receita', '0188', 'corpo', 'fn_reconciliar_receita_dre_vs_faturamento',
   'fn_motivo_precondicao_agregado(v_motivos_ano)', null,
   'Sem o corpo da 0188, Receita × Faturamento grava o genérico onde o lado da DRE sabe o motivo.',
   'importante', 805),

  ('motivo_precondicao_agregado_existe', '0188', 'funcao', 'fn_motivo_precondicao_agregado', null, null,
   'Os quatro corpos da 0188 chamam esta função; sem ela a reconciliação de cada caso ABORTA na '
   'primeira precondição (a chamada falha em tempo de execução, não de instalação).',
   'bloqueante', 806),

  ('motivo_do_lado_existe', '0188', 'funcao', 'fn_motivo_do_lado', null, null,
   'Idem: chamada pelos corpos da 0188 no ramo de linha não achada.',
   'bloqueante', 807),

  ('motivo_precondicao_prefixo_existe', '0188', 'funcao', 'fn_motivo_precondicao_prefixo', null, null,
   'Idem: chamada pelos corpos da 0188 para montar MOTIVO/REMÉDIO na descrição.',
   'bloqueante', 808),

  ('taxonomia_linha_alternativa_existe', '0188', 'tabela', 'taxonomia_linha_alternativa', null, null,
   'Sem a tabela, a pendência de DRE que publica só o resultado financeiro LÍQUIDO continua '
   'dizendo "linha não localizada, confira o rótulo" — 50 de 52 abertas em produção (22/09/2026).',
   'importante', 809),

  ('exigencias_devolvem_alternativa', '0188', 'corpo', 'fn_exigencias_do_caso',
   'alternativas_por_entidade', null,
   'Com a tabela mas sem este corpo, a alternativa nunca é avaliada: o texto não muda.',
   'importante', 810),

  ('completude_descreve_pela_alternativa', '0188', 'corpo', 'fn_recomputar_completude',
   'fn_descricao_linha_exigida(v_ex.tipo_taxonomia', null,
   'Sem este corpo, a pendência nova não usa o recado da alternativa.',
   'importante', 811),

  ('completude_atualiza_descricao', '0188', 'corpo', 'fn_recomputar_completude',
   'descricao is distinct from v_desc', null,
   'Sem este ramo, a pendência que JÁ estava aberta só tem a severidade atualizada — as 50 de '
   'produção nunca mudariam de texto, por mais recomputes que rodassem.',
   'importante', 812),

  ('descricao_linha_exigida_existe', '0188', 'funcao', 'fn_descricao_linha_exigida', null, null,
   'fn_recomputar_completude da 0188 chama esta função; sem ela o recompute ABORTA.',
   'bloqueante', 813),

  ('seed_alternativa_e_juros_bancarios', '0188', 'seed', 'instalacao_sonda_exigencias_0188', null, 2,
   'A alternativa "resultado financeiro" e o localizador ["juros","bancari"] de '
   'DRE/despesa_financeira. Uma linha só = uma das duas faltou.',
   'importante', 814)

on conflict (chave) do update
  set migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
      marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
      porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0188', revisado_em = current_date,
       observacao = 'A 0188 faz as quatro checagens que emitiam a precondição genérica passarem o '
                    'motivo específico quando o código o sabe (linha_nao_localizada, '
                    'unidade_divergente, sem_periodo_par), reemite fn_registrar_reconciliacao só '
                    'para DEVOLVER o resultado achatado (o laço de períodos dos despachantes lê '
                    'esse valor), cria taxonomia_linha_alternativa com o recado do resultado '
                    'financeiro LÍQUIDO, reemite fn_exigencias_do_caso (colunas novas) e '
                    'fn_recomputar_completude (texto + atualização da descrição), e acrescenta o '
                    'localizador ["juros","bancari"] na exigência e na checagem de despesa '
                    'financeira. mutuos/intragrupo/arvore não emitem o genérico e não foram '
                    'reemitidas.';

commit;

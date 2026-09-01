-- =============================================================================
-- 0133 — A SEÇÃO TEM DE FECHAR: o documento passa a conferir a si mesmo
--
-- O DEFEITO, e ele foi ABERTO por uma correção nossa.
--
-- `fn_reconciliar_ativo_passivo_pl` (0009, refeita até a 0034) confere Ativo =
-- Passivo + PL. Ela prefere o TOTAL IMPRESSO e só soma a seção quando o total
-- não existe:
--
--     select * into v_ativo from fn_valor_conceito_col(... 'ativo','total' ...);
--     if v_ativo.id is null then
--       -- Sem linha "TOTAL DO ATIVO": soma as contas da seção ATIVO.
--
-- Até a `0116` isso era conservador: o prompt não trazia os totais impressos,
-- `v_ativo` vinha nulo quase sempre, a checagem SOMAVA as contas — e uma conta
-- perdida quebrava a soma e abria pendência. A `0116` mandou o total impresso
-- chegar como LINHA (e estava certa: sem ele o export não tem contra o que
-- conferir). O efeito colateral é que agora os dois lados da checagem são totais
-- impressos, **e total impresso contra total impresso fecha por construção**: o
-- balanço do cliente bate consigo mesmo. A checagem ficou verde e CEGA para a
-- coisa que ela pegava antes.
--
-- Concretamente, hoje: apagar metade das contas do Ativo Circulante não abre
-- pendência nenhuma. "TOTAL DO ATIVO" continua batendo com "TOTAL DO PASSIVO +
-- PL", `lote_integro` fica verde, e a Modelagem recebe uma seção com buraco. É a
-- família mais cara deste projeto — não parece erro, parece um documento em
-- ordem — e é a mesma forma da `0028` (corte silencioso de leitura) e do
-- fatiamento desligado da sessão 52: o dado some e o placar não muda.
--
-- O QUE TORNA A CORREÇÃO BARATA: A ÁRVORE JÁ ESTÁ NO BANCO.
--
-- `campo_extraido.secao` guarda o PAI IMEDIATO da linha, não o grupo de topo.
-- No book:
--
--     chave                                    secao
--     ATIVO                            95.780  ATIVO          ← auto-referência
--     Ativo Circulante                 45.440  ATIVO
--     Disponível                          500  Ativo Circulante
--     Caixa e bancos conta movimento      380  Disponível
--     Aplicações financeiras de liquidez   120  Disponível
--
-- Então "os filhos de P" é uma pergunta EXATA — as linhas cuja `secao` é a
-- `chave` de P —, não um casamento por semelhança de rótulo. E a identidade que
-- todo demonstrativo obedece é: **pai = soma dos filhos diretos**. Não é
-- heurística nem tolerância de negócio: é a aritmética que o próprio documento
-- imprimiu, e a extração teve de satisfazê-la SEM SABER que seria conferida.
--
-- O QUE ELA PEGA, e nenhuma checagem de hoje pega:
--   • linha PERDIDA          — some um filho, o pai deixa de bater
--   • valor ERRADO           — dígito trocado quebra o pai
--   • linha DUPLICADA        — soma passa do pai
--   • SINAL invertido        — "(-) Provisão" lida positiva quebra o pai
-- e localiza o defeito NA SEÇÃO, que é o que a Modelagem precisa: quem lê
-- "Estoques não fecha por 2.350" reextrai um bloco, não o documento inteiro.
--
-- AS QUATRO GUARDAS CONTRA FALSO POSITIVO, e por que cada uma existe. Uma
-- pendência que abre sem defeito custa mesa e não compra qualidade nenhuma —
-- é regressão pura na razão entre autonomia e trabalho humano, que é o que este
-- sistema existe para melhorar. Então:
--
--   1. RÓTULO DUPLICADO NÃO É CONFERIDO AQUI — nem no PAI, nem nas PARCELAS.
--      Se o pai aparece duas vezes na coluna ele é ambíguo; se uma parcela
--      aparece duas vezes a soma passa do pai. Nos dois casos esta checagem
--      acusaria — e nos dois o defeito já tem dono:
--      `reconciliacao:duplicidade_de_rotulo` (0105). Duas pendências para um
--      defeito é DOIS toques humanos onde cabe um, e a razão entre autonomia e
--      trabalho humano piora sem que a qualidade suba um ponto. Aqui vira
--      pré-condição não satisfeita, apontando a checagem que manda. Não há perda
--      de detecção: a 0105 pega o mesmo caso, e pega melhor.
--
--   2. UNIDADE MISTA NÃO SE SOMA. Filho em 'unidade' sob pai em 'milhar' daria
--      divergência de 1000×. Não se compara: pré-condição não satisfeita.
--      E note a ordem — o filho de unidade divergente NÃO é descartado da soma,
--      porque descartar em silêncio produziria uma soma errada com cara de certa.
--
--   3. LINHA DERIVADA NÃO É PARCELA. `fn_papel_linha` já sabe que "Margem
--      bruta", "Prazo médio" e "Índice de liquidez" são indicador e não dinheiro
--      (a 0103/0116 fecharam essa lista). Somá-los ao lado de contas misturaria
--      percentual com reais.
--
--   4. A TOLERÂNCIA É DE ARREDONDAMENTO, E SÓ. As outras checagens usam 0,5% —
--      porque comparam DOCUMENTOS diferentes, que arredondam de forma diferente.
--      Aqui os dois lados saem da MESMA coluna do MESMO documento, e a única
--      diferença legítima é o arredondamento de cada parcela: com n filhos, a
--      deriva máxima é ~0,5·(n+1) na unidade do documento. Usar 0,5% aqui seria
--      desastroso: 0,5% de um Ativo de 95.780 é 479 — deixaria passar uma conta
--      inteira de meio milhão, que é EXATAMENTE o defeito que esta migration
--      existe para achar.
--
-- O QUE ELA DELIBERADAMENTE NÃO FAZ, e fica anotado:
--
--   • NÃO DISTINGUE "a extração errou" de "o documento do cliente não fecha".
--     Os dois quebram a mesma identidade e a diferença exige olhar o PDF. A
--     descrição da pendência nomeia as duas hipóteses em vez de escolher uma —
--     escolher errado mandaria o analista reextrair um documento que está certo,
--     ou pedir ao cliente um documento que nós lemos mal. Quando a rodada real
--     disser qual das duas domina, dá para separar por confiança da extração.
--
--   • SÓ VALE ONDE A ÁRVORE É COMPLETA POR CONSTRUÇÃO — demonstrativo, não
--     anexo. Uma nota explicativa que detalha PARTE de um saldo não fecha, e
--     está certa em não fechar. Os tipos gateados estão em `fn_reconciliar_arvore`.
--     Rodar sobre anexo produziria pendência em documento correto, que é a
--     guarda 1 de novo, por outro caminho.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- fn_conferir_arvore — a medição. Uma linha por (pai × coluna).
--
-- POR QUE POR COLUNA. O mesmo balanço traz 2024 e 2025 lado a lado, e um grupo
-- pode ter empresas em colunas. Somar filhos de 2025 contra o pai de 2024 daria
-- divergência em todo documento comparativo — que são quase todos.
-- `coalesce(norm(coluna), '')` mantém o documento de coluna única num grupo só.
-- -----------------------------------------------------------------------------
create or replace function fn_conferir_arvore(p_documento_versao_id uuid)
returns table (
  entidade_coluna text,
  periodo_coluna  text,
  pai             text,
  pai_valor       numeric,
  soma_filhos     numeric,
  n_filhos        int,
  n_reafirmacoes  int,
  unidade         text,
  divergencia_abs numeric,
  tolerancia      numeric,
  resultado       text,
  achado          text,
  porque          text,
  filhos          text[]
)
language sql
stable
as $$
  with linha as (
    select ce.chave,
           fn_normalizar_texto(ce.chave) as chave_norm,
           fn_normalizar_texto(ce.secao) as secao_norm,
           ce.valor_num,
           ce.unidade,
           ce.entidade_coluna,
           ce.periodo_coluna,
           coalesce(fn_normalizar_texto(ce.entidade_coluna), '') as ck_ent,
           coalesce(fn_normalizar_texto(ce.periodo_coluna),  '') as ck_per,
           fn_papel_linha(ce.chave, d.tipo_taxonomia, ce.unidade) as papel
      from campo_extraido ce
      join documento_versao dv on dv.id = ce.documento_versao_id
      join documento d         on d.id  = dv.documento_id
     where ce.documento_versao_id = p_documento_versao_id
       and ce.valor_num is not null
  ),
  eh_pai as (
    select distinct f.secao_norm as pai_norm, f.ck_ent, f.ck_per
      from linha f
     where f.secao_norm is not null
       and f.chave_norm is distinct from f.secao_norm
  ),
  pai as (
    select l.chave_norm as pai_norm, l.ck_ent, l.ck_per,
           min(l.chave)           as pai_chave,
           min(l.valor_num)       as pai_valor,
           min(l.unidade)         as pai_unidade,
           min(l.entidade_coluna) as ent_col,
           min(l.periodo_coluna)  as per_col,
           count(*)::int          as n_pai
      from linha l
      join eh_pai e
        on e.pai_norm = l.chave_norm
       and e.ck_ent   = l.ck_ent
       and e.ck_per   = l.ck_per
     group by l.chave_norm, l.ck_ent, l.ck_per
  ),
  -- O CLASSIFICADOR DE FILHO. Esta é a parte que a primeira versão errou, e o
  -- fixture disse na cara: a soma dava EXATAMENTE 2x o pai em 31 seções.
  --
  -- Depois da 0116 o total impresso chega como LINHA, e ele fica na MESMA seção
  -- que as parcelas — "TOTAL DO ATIVO" é irmão de "Ativo Circulante", não pai
  -- dele. Somá-lo às parcelas conta a seção duas vezes. Ele não é parcela: é a
  -- REAFIRMAÇÃO do pai, e o próprio documento a imprime para ser conferida.
  --
  -- A regra é por VALOR, não por rótulo, e isso foi medido: "TOTAL DO PASSIVO E
  -- DO PATRIMÔNIO LÍQUIDO" contra a seção "PASSIVO E PATRIMÔNIO LÍQUIDO" não
  -- casa por texto (sobra o "do" do meio), e casar por semelhança traria de
  -- volta a adivinhação que `secao` existe para evitar.
  --
  -- E a reafirmação que NÃO bate não é descartada — vira achado PRÓPRIO. Se
  -- "TOTAL DO ATIVO" foi lido 95.000 com "ATIVO" em 95.780, o defeito não é
  -- "a seção não fecha": é "o documento declara o mesmo total duas vezes e as
  -- duas leituras discordam". Tratá-la como parcela produziria uma divergência
  -- de ~95.000 e um diagnóstico errado sobre um defeito verdadeiro.
  filho as (
    select p.pai_norm, p.ck_ent, p.ck_per, p.pai_valor, p.pai_unidade,
           f.chave, f.valor_num, f.unidade,
           f.chave_norm,
           case
             when f.papel = 'derivado'  then 'derivado'
             when f.papel = 'subtotal' and f.valor_num = p.pai_valor
               then 'reafirmacao'
             when f.papel = 'subtotal'
                  and fn_normalizar_texto(f.chave) ~ '^(total|soma)\y'
                  and f.valor_num is distinct from p.pai_valor
               then 'reafirmacao_divergente'
             else 'parcela'
           end as tipo
      from pai p
      join linha f
        on f.secao_norm = p.pai_norm
       and f.ck_ent     = p.ck_ent
       and f.ck_per     = p.ck_per
       and f.chave_norm is distinct from f.secao_norm
  ),
  agregado as (
    select p.ent_col, p.per_col, p.pai_chave, p.pai_valor, p.pai_unidade, p.n_pai,
           coalesce(sum(c.valor_num) filter (where c.tipo = 'parcela'), 0) as soma,
           count(*) filter (where c.tipo = 'parcela')::int                 as n,
           count(*) filter (where c.tipo = 'reafirmacao')::int             as n_reaf,
           count(*) filter (where c.tipo = 'reafirmacao_divergente')::int  as n_reaf_div,
           array_agg(c.chave order by c.chave)
             filter (where c.tipo = 'parcela')                             as chaves,
           min(c.chave) filter (where c.tipo = 'reafirmacao_divergente')   as reaf_div_chave,
           min(c.valor_num) filter (where c.tipo = 'reafirmacao_divergente') as reaf_div_valor,
           count(*) filter (
             where c.tipo = 'parcela'
               and c.unidade is not null and p.pai_unidade is not null
               and fn_normalizar_texto(c.unidade) <> fn_normalizar_texto(p.pai_unidade)
           )::int                                                          as n_unid_dif,
           (count(*) filter (where c.tipo = 'parcela')
            - count(distinct c.chave_norm) filter (where c.tipo = 'parcela'))::int
                                                                           as n_parcela_dup
      from pai p
      join filho c
        on c.pai_norm = p.pai_norm
       and c.ck_ent   = p.ck_ent
       and c.ck_per   = p.ck_per
     group by p.ent_col, p.per_col, p.pai_chave, p.pai_valor, p.pai_unidade, p.n_pai
  ),
  medido as (
    select a.*,
           abs(a.pai_valor - a.soma)                    as div_abs,
           greatest(1, ceil(0.5 * (a.n + 1)))::numeric  as tol
      from agregado a
  )
  select m.ent_col, m.per_col, m.pai_chave, m.pai_valor, m.soma, m.n, m.n_reaf, m.pai_unidade,
         m.div_abs, m.tol,
         case
           when m.n_pai > 1          then 'precondicao_nao_satisfeita'
           when m.n_parcela_dup > 0  then 'precondicao_nao_satisfeita'
           when m.n_unid_dif > 0     then 'precondicao_nao_satisfeita'
           when m.n_reaf_div > 0   then 'divergente'
           when m.n = 0            then 'precondicao_nao_satisfeita'
           when m.div_abs > m.tol  then 'divergente'
           else 'ok'
         end,
         case
           when m.n_pai > 1         then 'rotulo_duplicado'
           when m.n_parcela_dup > 0 then 'rotulo_duplicado'
           when m.n_unid_dif > 0    then 'unidade_mista'
           when m.n_reaf_div > 0 then 'total_declarado_diverge'
           when m.n = 0          then 'sem_parcela'
           when m.div_abs > m.tol then 'secao_nao_fecha'
           else 'ok'
         end,
         case
           when m.n_pai > 1 then
             format('O rótulo "%s" aparece %s vezes nesta coluna: o pai é ambíguo e a soma não '
                    'decide nada. Quem cobra isso é reconciliacao:duplicidade_de_rotulo (0105) — '
                    'duas pendências para um defeito seriam dois toques humanos onde cabe um.',
                    m.pai_chave, m.n_pai)
           when m.n_parcela_dup > 0 then
             format('%s parcela(s) de "%s" aparecem com o rótulo repetido nesta coluna. A soma '
                    'passaria do pai e esta checagem acusaria — mas o defeito já tem dono, '
                    'reconciliacao:duplicidade_de_rotulo (0105), e duas pendências para um defeito '
                    'seriam dois toques humanos onde cabe um.',
                    m.n_parcela_dup, m.pai_chave)
           when m.n_unid_dif > 0 then
             format('%s de %s parcelas de "%s" estão em unidade diferente da do pai (%s). Somar '
                    'unidades diferentes erraria por ordem de grandeza, e descartar a parcela '
                    'divergente produziria uma soma errada com cara de certa.',
                    m.n_unid_dif, m.n, m.pai_chave, coalesce(m.pai_unidade, 'não declarada'))
           when m.n_reaf_div > 0 then
             format('O documento declara o total de "%s" DUAS vezes e as duas leituras discordam: '
                    'a seção diz %s e "%s" diz %s. Uma das duas foi lida errado — não é a soma das '
                    'parcelas que está em questão aqui.',
                    m.pai_chave, m.pai_valor, m.reaf_div_chave, m.reaf_div_valor)
           when m.n = 0 then
             format('"%s" nomeia uma seção, mas nenhum filho dela é parcela somável nesta coluna '
                    '(só reafirmação do próprio total, derivados, ou linhas sem número).',
                    m.pai_chave)
           when m.div_abs > m.tol then
             format('"%s" informa %s e a soma das %s parcelas dá %s — diferença de %s (tolerância '
                    'de arredondamento: %s). Ou a extração perdeu/errou uma linha desta seção, ou '
                    'o documento não fecha consigo mesmo; as duas exigem olhar o PDF.',
                    m.pai_chave, m.pai_valor, m.n, m.soma, m.div_abs, m.tol)
           else
             format('"%s" = soma das %s parcelas (%s)%s.', m.pai_chave, m.n, m.soma,
                    case when m.n_reaf > 0
                         then format(', e o total reafirmado pelo documento (%s vez) confere',
                                     m.n_reaf)
                         else '' end)
         end,
         m.chaves
    from medido m;
$$;

comment on function fn_conferir_arvore(uuid) is
  'Confere, por (pai × coluna), se o valor da linha-pai é igual à soma dos filhos diretos — a '
  'identidade que todo demonstrativo obedece e que a extração teve de satisfazer sem saber que '
  'seria conferida. `campo_extraido.secao` é o pai IMEDIATO, então "os filhos de P" é pergunta '
  'exata e não casamento por semelhança. Pega linha perdida, valor errado, linha duplicada e sinal '
  'invertido, e localiza o defeito na seção. Tolerância é de ARREDONDAMENTO (~0,5·(n+1)), não '
  'percentual: 0,5% de um Ativo grande deixaria passar a conta inteira que a checagem existe para '
  'achar.';

grant execute on function fn_conferir_arvore(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_reconciliar_arvore — o registro, no idioma das outras checagens.
--
-- CLASSE A porque é aritmética sobre valores já extraídos, como `ativo_passivo_pl`
-- e `caixa_bp_fluxo`: não há julgamento, há identidade. Quem decide se o achado
-- abre pendência é o dial da classe (0127), não esta função.
--
-- UMA PENDÊNCIA POR DOCUMENTO, não uma por seção. Um documento cuja escala saiu
-- errada quebra TODAS as seções de uma vez, e trinta pendências para um defeito
-- é o oposto do que este sistema deve fazer com o tempo de quem lê a fila. A
-- descrição lista as piores, com número, para a ação ser possível sem abrir
-- trinta itens.
-- -----------------------------------------------------------------------------
create or replace function fn_reconciliar_arvore(p_documento_id uuid)
returns jsonb
language plpgsql
as $$
declare
  v_caso_id     uuid;
  v_entidade_id uuid;
  v_periodo_id  uuid;
  v_tipo        text;
  v_versao      uuid;
  v_n_ok        int := 0;
  v_n_div       int := 0;
  v_n_prec      int := 0;
  v_pior_abs    numeric;
  v_pior_pct    numeric;
  v_pior_pai    text;
  v_partes      text[] := '{}';
  v_resultado   text;
  v_desc        text;
begin
  select caso_id, entidade_id, periodo_id, tipo_taxonomia
    into v_caso_id, v_entidade_id, v_periodo_id, v_tipo
  from documento where id = p_documento_id;

  if v_caso_id is null then
    return jsonb_build_object('executado', false, 'motivo', 'documento não encontrado');
  end if;

  v_versao := fn_versao_atual(p_documento_id);
  if v_versao is null then
    return jsonb_build_object('executado', false, 'motivo', 'documento sem versão');
  end if;

  select count(*) filter (where resultado = 'ok'),
         count(*) filter (where resultado = 'divergente'),
         count(*) filter (where resultado = 'precondicao_nao_satisfeita')
    into v_n_ok, v_n_div, v_n_prec
  from fn_conferir_arvore(v_versao);

  -- Nenhum pai com filho: documento de lista (aging, razão, mapa de dívida) ou
  -- extração sem hierarquia. Não é achado — é ausência de árvore para conferir.
  if v_n_ok + v_n_div + v_n_prec = 0 then
    return fn_registrar_reconciliacao(v_caso_id, v_entidade_id, v_periodo_id,
      'secao_fecha', 'A', p_documento_id, null, null, 'documento_ausente', null, null,
      jsonb_build_object('tolerancia', 'arredondamento ~0,5*(n+1)'),
      'Este documento não tem seção com filhos — não há árvore a conferir. É o esperado em '
      || 'documento de lista (razão, aging, mapa de dívida), não um achado.');
  end if;

  select a.divergencia_abs,
         case when a.pai_valor <> 0 then a.divergencia_abs / abs(a.pai_valor) end,
         a.pai
    into v_pior_abs, v_pior_pct, v_pior_pai
  from fn_conferir_arvore(v_versao) a
  where a.resultado = 'divergente'
  order by a.divergencia_abs desc
  limit 1;

  select array_agg(
           format('%s%s: informa %s, filhos somam %s (dif. %s)',
                  a.pai,
                  case when coalesce(a.periodo_coluna, '') <> ''
                       then ' [' || a.periodo_coluna || ']' else '' end,
                  a.pai_valor, a.soma_filhos, a.divergencia_abs)
           order by a.divergencia_abs desc)
    into v_partes
  from (select * from fn_conferir_arvore(v_versao)
         where resultado = 'divergente'
         order by divergencia_abs desc limit 5) a;

  v_resultado := case when v_n_div > 0 then 'divergente' else 'ok' end;

  if v_n_div > 0 then
    v_desc := format(
      '%s seção(ões) não fecham com as próprias linhas neste documento (%s conferem). %s. '
      || 'Ou a extração perdeu/errou linha nessas seções, ou o documento não fecha consigo '
      || 'mesmo — as duas exigem olhar o PDF, e a diferença decide entre reextrair e perguntar '
      || 'ao cliente.',
      v_n_div, v_n_ok, array_to_string(v_partes, '; '));
    if v_n_div > 5 then
      v_desc := v_desc || format(' (mostrando as 5 maiores de %s; muitas seções quebrando de uma '
                                 'vez costuma ser escala ou coluna, não linha perdida.)', v_n_div);
    end if;
  else
    v_desc := format('As %s seções deste documento fecham com as próprias linhas. %s ficaram sem '
                     'conferir por pré-condição (rótulo duplicado ou unidade mista).',
                     v_n_ok, v_n_prec);
  end if;

  return fn_registrar_reconciliacao(v_caso_id, v_entidade_id, v_periodo_id,
    'secao_fecha', 'A', p_documento_id,
    jsonb_build_object('secoes_conferidas', v_n_ok + v_n_div, 'pior_secao', v_pior_pai),
    jsonb_build_object('divergentes', v_n_div, 'sem_conferir', v_n_prec),
    v_resultado, v_pior_abs, v_pior_pct,
    jsonb_build_object('tolerancia', 'arredondamento ~0,5*(n+1) na unidade do documento'),
    v_desc);
end;
$$;

comment on function fn_reconciliar_arvore(uuid) is
  'Registra, como reconciliação Classe A, se as seções do documento fecham com as próprias linhas. '
  'UMA pendência por documento (não uma por seção): erro de escala quebra todas as seções de uma '
  'vez, e trinta pendências para um defeito é o oposto do que fazer com o tempo de quem lê a fila.';

grant execute on function fn_reconciliar_arvore(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_reconciliar_por_documento — a checagem entra na rodada.
--
-- OS TIPOS GATEADOS são os demonstrativos, onde a árvore é completa por
-- construção. Anexo e nota explicativa detalham PARTE de um saldo e não fecham —
-- e estão certos em não fechar; cobrá-los abriria pendência em documento
-- correto. RAZAO, AGING_* e MAPA_DIVIDA são listas sem hierarquia e caem no
-- 'documento_ausente' da própria função, mas nem chegam lá.
--
-- O resto do corpo é o da 0023, inalterado.
-- -----------------------------------------------------------------------------
create or replace function fn_reconciliar_por_documento(p_documento_id uuid)
returns jsonb language plpgsql as $$
declare
  v_caso_id     uuid;
  v_entidade_id uuid;
  v_periodo_id  uuid;
  v_tipo        text;
  v_checagens   jsonb := '[]'::jsonb;
  v_periodos    uuid[];
  v_per         uuid;
  v_res         jsonb;

begin
  select caso_id, entidade_id, periodo_id, tipo_taxonomia
    into v_caso_id, v_entidade_id, v_periodo_id, v_tipo
  from documento where id = p_documento_id;

  if v_caso_id is null then
    return jsonb_build_object('executado', false, 'motivo', 'documento não encontrado');
  end if;

  -- 0133: a conferência INTRA-documento vem PRIMEIRO. Se as seções do próprio
  -- documento não fecham, as comparações entre documentos abaixo estão sendo
  -- feitas sobre números que já não se sustentam — e é melhor que a fila diga
  -- isso antes de dizer que o Ativo bate com o Passivo (que, com totais
  -- impressos dos dois lados, bate mesmo quando faltam contas no meio).
  --
  -- Sem loop de período: a árvore é INTRA-documento, então o período do
  -- documento é o único que existe aqui — não há documento par a procurar.
  if v_tipo in ('BALANCO', 'BALANCETE', 'COMBINADO') then
    v_checagens := v_checagens || jsonb_build_array(fn_reconciliar_arvore(p_documento_id));
  end if;

  select array_agg(p.id order by (p.id = v_periodo_id) desc, p.referencia)
    into v_periodos
  from periodo p
  where p.caso_id = v_caso_id
    and (p.id = v_periodo_id or fn_periodos_compativeis(p.id, v_periodo_id));
  if v_periodos is null or cardinality(v_periodos) = 0 then
    v_periodos := array[v_periodo_id];
  end if;

  -- Classe A (0009)
  if v_tipo in ('BALANCO', 'BALANCETE', 'COMBINADO') then
    foreach v_per in array v_periodos loop
      v_res := fn_reconciliar_ativo_passivo_pl(v_caso_id, v_entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res);
  end if;
  if v_tipo in ('BALANCO', 'BALANCETE', 'COMBINADO', 'FLUXO_CAIXA') then
    foreach v_per in array v_periodos loop
      v_res := fn_reconciliar_caixa_bp_fluxo(v_caso_id, v_entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res);
  end if;

  -- Classe B (0015/0021)
  if v_tipo in ('DRE', 'FATURAMENTO_24M') then
    foreach v_per in array v_periodos loop
      v_res := fn_reconciliar_receita_dre_vs_faturamento(v_caso_id, v_entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res);
  end if;
  if v_tipo in ('DRE', 'MAPA_DIVIDA') then
    foreach v_per in array v_periodos loop
      v_res := fn_reconciliar_despfin_dre_vs_divida(v_caso_id, v_entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res);
  end if;

  -- Mútuos (0117/0123). Pelos dois lados: quem chega por último fecha o par.
  if v_tipo in ('MUTUOS', 'BALANCO', 'COMBINADO', 'DF_AUDITADA') then
    foreach v_per in array v_periodos loop
      v_res := fn_reconciliar_mutuos(v_caso_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res);
  end if;

  -- Intragrupo FORA mútuo (0124). Disparada por balanço individual, que é a
  -- única peça de que ela precisa — não há documento par a esperar. `COMBINADO`
  -- não dispara e não é lido: as linhas intragrupo dele são eliminações.
  if v_tipo in ('BALANCO', 'BALANCETE', 'DF_AUDITADA') then
    foreach v_per in array v_periodos loop
      v_res := fn_reconciliar_intragrupo(v_caso_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res);
  end if;

  -- Duplicidade de rótulo (0105). Sem loop de período: é por caso/entidade.
  if v_tipo in ('BALANCO', 'BALANCETE', 'COMBINADO') then
    v_checagens := v_checagens || jsonb_build_array(
      fn_reconciliar_duplicidade(v_caso_id, v_entidade_id));
  end if;

  return jsonb_build_object('executado', true, 'documento_id', p_documento_id, 'checagens', v_checagens);
end;
$$;

comment on function fn_reconciliar_por_documento(uuid) is
  'Roda as reconciliações que o tipo do documento autoriza. Desde a 0133 começa pela conferência '
  'INTRA-documento (fn_reconciliar_arvore): com totais impressos dos dois lados, Ativo = Passivo+PL '
  'fecha mesmo quando faltam contas no meio, então a árvore tem de falar primeiro.';

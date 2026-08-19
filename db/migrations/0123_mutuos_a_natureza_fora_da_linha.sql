-- 0123 — A CHECAGEM DE MÚTUOS PARA DE DEPENDER DE UM ENFEITE DO FIXTURE.
--
-- O QUE ACHOU ISTO. A fixture de extração do `book-canastra` (o book DIFÍCIL,
-- que existia desde o PR #112 e nunca havia sido exercitado pela ingestão).
-- Carregada e reconciliada, ela abriu ZERO pendência — e o book planta UMA de
-- propósito: a planilha de mútuos traz R$ 240 mil a MENOS que o balanço, para o
-- sistema ter o que mostrar a um humano. A `0117` existe exatamente para isso, e
-- passou por cima em silêncio.
--
-- ------------------------------------------------------------------ DEFEITO 1
-- A CHECAGEM PROCURAVA A PALAVRA "MÚTUO" NO RÓTULO DE CADA LINHA DA PLANILHA.
--
--     and fn_normalizar_texto(ce.chave) like '%mutuo%'
--
-- Uma planilha de mútuos de verdade não repete a palavra em cada linha: ela diz
-- a natureza UMA vez, no título e no nome das colunas. O quadro do Canastra é
--
--     RELAÇÃO DE MÚTUOS ENTRE PARTES RELACIONADAS
--     Mutuante | Mutuária | Saldo devedor
--     CANASTRA PARTICIPAÇÕES S.A. | CANASTRA INDÚSTRIA ... | 11.160
--
-- e nenhuma das três linhas contém "mútuo". O filtro zerava o lado B, o laço
-- caía no `continue`, `v_n` terminava em 0 e a função devolvia
-- `documento_ausente` — o único resultado que NÃO abre pendência. Ou seja: a
-- divergência plantada não era "não encontrada", era declarada inexistente.
--
-- POR QUE PASSOU DESAPERCEBIDO POR SEIS SESSÕES. O `fixture_book_vertentes.sql`
-- escreve o rótulo como `"A → B — Mútuo"`, colando a NATUREZA dentro do nome da
-- linha. Isso não vem do PDF de Vertentes — é um enfeite do gerador do fixture.
-- A checagem estava, portanto, aprovada por um dado que só existia no teste. É a
-- mesma família do defeito da `0102`: teste que confirma o código porque os dois
-- foram escritos com a mesma suposição errada.
--
-- O CONSERTO NÃO É REMOVER O FILTRO. Ele faz trabalho real: a planilha de
-- intragrupo lista mais coisa que mútuo (conta corrente rotativa, aluguel entre
-- coligadas, rateio de despesa), e o balanço registra cada natureza num lugar
-- diferente — comparar a planilha INTEIRA contra as contas de mútuo do balanço
-- acusaria como divergência aquilo que é só natureza diferente. O conserto é
-- olhar a natureza onde ela realmente está, em três degraus de evidência **com
-- precedência estrita — o degrau mais específico que existir é o único usado**:
--
--   1. ALGUMA LINHA diz no próprio rótulo ("... — Mútuo")  → usa só as linhas
--      cujo RÓTULO diz. O documento está diferenciando natureza linha a linha, e
--      é ele a autoridade sobre a linha dele.
--   2. nenhuma linha diz, mas a SEÇÃO diz ("RELAÇÃO DE MÚTUOS ENTRE PARTES
--      RELACIONADAS")                                     → usa as linhas dessa
--      seção. Os rótulos estão calados sobre natureza, então a seção é a única
--      coisa que fala.
--   3. NADA diz, em linha nem em seção                    → o documento inteiro é
--      a relação de mútuos, e a taxonomia já afirmou isso ao classificá-lo como
--      `MUTUOS`. Todas as linhas de valor entram.
--
-- A PRECEDÊNCIA NÃO É ZELO: SEM ELA A CORREÇÃO REPETE O DEFEITO QUE CONSERTA, e
-- isso foi medido. A primeira versão desta migration olhava rótulo OU seção de
-- uma vez, sem ordem, e a suíte de Vertentes reprovou na hora: o fixture de
-- Vertentes põe `secao = "MÚTUOS E CONTAS INTRAGRUPO"` — um agrupador que nomeia
-- DUAS naturezas —, e com a seção valendo por si a conta corrente (1.400) e o
-- aluguel entre coligadas (640) passaram a entrar na soma da planilha. A
-- divergência saltou de R$ 180 mil para R$ 2.220 mil. É textualmente o que o
-- comentário da `0117` já avisava, cometido de novo por outro caminho.
--
-- Com a precedência, o caso de Vertentes cai no degrau 1 (as linhas dizem "—
-- Mútuo", "— Conta corrente", "— Aluguéis a receber") e a separação volta a
-- valer; o do Canastra cai no degrau 2, que é o que ele precisa.
--
-- O degrau 3 é seguro por eliminação, não por otimismo: se nem o rótulo nem a
-- seção de UMA linha sequer nomeiam a natureza, não existe no documento nada com
-- que separar mútuo de conta corrente — e a única informação disponível é o tipo
-- do documento.
--
-- O QUE NENHUM DEGRAU RESOLVE, e fica dito: seção que nomeia VÁRIAS naturezas com
-- rótulos calados ("MÚTUOS E CONTAS INTRAGRUPO" sem "— Mútuo" nas linhas). Aí
-- nada no documento separa as naturezas, e o degrau 2 inclui tudo. Não há régua
-- possível sobre um documento que não diz — o que existe é a pendência, que
-- mostra o número ao humano em vez de escondê-lo.
--
-- ------------------------------------------------------------------ DEFEITO 2
-- UMA GUARDA DOCUMENTADA QUE NÃO EXISTIA. O comentário da `0117` dizia:
--
--     -- Isso só é honesto porque o bloco abaixo interrompe a checagem quando o
--     -- balanço tem os DOIS lados: aí a linha sem lado caberia nos dois, e
--     -- escolher um é chute.
--
-- Não há bloco abaixo. `v_lados_bp` é ATRIBUÍDA e nunca LIDA — a guarda nunca foi
-- escrita, e o comentário afirmava uma proteção inexistente. Achado ao ler a
-- função para consertar o defeito 1.
--
-- E A GUARDA PROMETIDA, COMO ESCRITA, ESTÁ ERRADA — medido, não deduzido.
-- "Interromper quando há os dois lados" silenciaria a checagem exatamente no
-- caso em que a evidência é MAIS forte. Um mútuo intragrupo aparece duas vezes
-- dentro do mandato — a receber no balanço de quem emprestou, a pagar no de quem
-- tomou — e no Canastra os dois lados dão 16.300 cada: eles se confirmam
-- mutuamente, e é a planilha (16.060) que discorda. Interromper aí seria calar
-- sobre a única divergência do book.
--
-- A regra que entra é a que o número sustenta:
--
--   • dois lados que CONCORDAM entre si  → o saldo do balanço está estabelecido
--     por dupla evidência. Compara-se a planilha UMA vez contra ele (antes eram
--     duas comparações com o mesmo resultado, repetindo o mesmo fato na tela).
--   • dois lados que DISCORDAM entre si  → isso é o achado, e é dos balanços,
--     não da planilha: a mesma dívida vista das duas pontas não fecha dentro do
--     próprio mandato. Reporta-se ISSO, e a planilha não é comparada naquele
--     ano — atribuir uma linha sem lado a um dos dois seria o chute que o
--     comentário original temia, e com razão.
--   • um lado só                          → como antes.
--
-- ------------------------------------------------------------------ DEFEITO 3
-- E FOI ESSA GUARDA QUE ACHOU O TERCEIRO: **MÚTUO COM SÓCIO NÃO TEM ESPELHO.**
--
-- Ligada a guarda, o Canastra passou a acusar 14.000 de diferença ENTRE OS DOIS
-- LADOS (a receber 16.300, a pagar 30.300) — e a diferença tem nome: "Empréstimo
-- de sócios (mútuo com quotistas)", 14.000 no não circulante da SPE. É mútuo, e
-- está corretamente na conta de partes relacionadas, mas a contraparte é o QUOTISTA
-- e não outra empresa do grupo. A outra ponta dele mora fora do mandato.
--
-- A propriedade do espelho, portanto, vale para mútuo INTRAGRUPO, não para "mútuo".
-- E a planilha conferida é intragrupo por definição — o título do quadro diz
-- "ENTRE PARTES RELACIONADAS" e cada linha é um par de empresas do grupo. Somar o
-- empréstimo dos sócios no lado do balanço é comparar duas populações diferentes:
-- daria 14.240 de "divergência da planilha" onde há 240 de divergência e 14.000 de
-- um mútuo que aquela planilha nunca teve por que listar.
--
-- Por isso entra `fn_mutuo_com_socio`, e ela é LEXICAL de propósito: `fn_lado_do_mutuo`
-- já decide "a pagar × a receber" pelo mesmo tipo de leitura, e não há sinal
-- ESTRUTURAL disponível — o empréstimo dos sócios mora na mesma subseção ("Partes
-- Relacionadas") que o mútuo intragrupo, no mesmo grupo do balanço, com a mesma
-- seção canônica. Quem separa os dois é a palavra que o documento usa para a
-- contraparte, que é também o que um analista lê.
--
-- O QUE ISSO DEIXA DE FORA, escrito para não se perder: mútuo com sócio passa a não
-- ser conferido por ninguém. O par dele não é a planilha intragrupo — é o contrato
-- de mútuo com o quotista, que o Kit Básico coleta como `CONTRATO_DIVIDA`/`CONTRATOS_IC`
-- e que ninguém cruza hoje. Antes desta migration ele também não era conferido; a
-- diferença é que agora está dito.
--
-- ------------------------------------------------------------------ MEDIDO
-- Canastra (após): os dois lados fecham em 16.300 e a planilha abre UMA pendência
-- com os R$ 240.000 do book — nada mais. Vertentes (após): continua UMA pendência,
-- com os mesmos R$ 180.000, e ela deixa de dizer duas vezes a mesma coisa.

-- ---------------------------------------------------------------------------
-- "ESTE TEXTO NOMEIA A NATUREZA MÚTUO?" — UM argumento, de propósito.
--
-- Aplicada ao RÓTULO responde pelo degrau 1; aplicada à SEÇÃO, pelo degrau 2. São
-- perguntas diferentes e têm precedência diferente, então a função não pode
-- recebê-los juntos e responder "algum dos dois" — foi essa versão de dois
-- argumentos que fez a primeira tentativa desta migration somar conta corrente
-- junto com mútuo em Vertentes.
-- ---------------------------------------------------------------------------
create or replace function fn_texto_nomeia_mutuo(p_texto text)
returns boolean language sql immutable as $$
  select fn_normalizar_texto(coalesce(p_texto, '')) like '%mutuo%';
$$;

comment on function fn_texto_nomeia_mutuo(text) is
  '0123: a natureza "mútuo" nomeada NESTE texto. Usada no rótulo (degrau 1) e na seção (degrau 2), com precedência do rótulo — nunca nos dois de uma vez.';

grant execute on function fn_texto_nomeia_mutuo(text) to authenticated;


-- ---------------------------------------------------------------------------
-- MÚTUO COM SÓCIO / QUOTISTA / ACIONISTA — a contraparte está FORA do grupo, e a
-- outra ponta do lançamento não existe dentro do mandato. Fica fora da conferência
-- de espelho e da comparação contra a planilha intragrupo, que é de outra
-- população.
--
-- A lista é curta e fechada porque é o vocabulário do documento contábil
-- brasileiro para essa contraparte; não há intenção de cobrir apelido criativo.
-- O pior caso de ela não reconhecer é o comportamento anterior a esta migration:
-- a linha entra na soma e a diferença aparece atribuída à planilha.
-- ---------------------------------------------------------------------------
create or replace function fn_mutuo_com_socio(p_chave text, p_secao text default null)
returns boolean language sql immutable as $$
  select fn_normalizar_texto(coalesce(p_chave, '') || ' ' || coalesce(p_secao, ''))
         ~ '(socio|quotista|cotista|acionista)';
$$;

comment on function fn_mutuo_com_socio(text, text) is
  '0123: mútuo cuja contraparte é o SÓCIO, não outra empresa do grupo — não tem espelho no mandato e não se confere contra a planilha intragrupo.';

grant execute on function fn_mutuo_com_socio(text, text) to authenticated;


create or replace function fn_reconciliar_mutuos(
  p_caso_id        uuid,
  p_periodo_id     uuid,
  p_tolerancia_abs numeric default 50000,
  p_tolerancia_pct numeric default 0.005
) returns jsonb language plpgsql as $$
declare
  v_doc_mut uuid;
  v_ver_mut uuid;
  v_ano int;
  v_col_mut text;
  v_unid_mut text;
  v_bp   record;
  v_pl   record;
  v_a numeric; v_b numeric; v_div numeric; v_tol numeric;
  v_resultado text := 'ok';
  v_partes text[] := '{}';
  v_n int := 0;
  v_pior_abs numeric; v_pior_pct numeric;
  v_fonte_a jsonb; v_fonte_b jsonb;
  v_tem_balanco boolean;
  -- 0123: os dois degraus específicos, respondidos sobre o DOCUMENTO. Algum
  -- rótulo nomeia (degrau 1)? Alguma seção nomeia (degrau 2)? Nenhum dos dois é
  -- o degrau 3.
  v_pl_rotulo boolean;
  v_pl_secao  boolean;
  -- 0123: os lados do balanço, colhidos ANTES de comparar — é o que permite
  -- perguntar se eles concordam entre si, que a versão anterior não fazia.
  v_lados record;
  v_lado_alvo text;
  v_rotulo_lado text;
begin
  -- A PLANILHA É DO GRUPO E O SALDO É DE CADA EMPRESA — por isso esta checagem
  -- é por CASO, e não por (caso, entidade) como as outras.
  --
  -- Foi a primeira versão desta função que ensinou isso, errando: ela procurava
  -- o balanço DA MESMA entidade dona da planilha. No book Vertentes a planilha é
  -- do "GRUPO VERTENTES" e a única demonstração dessa entidade é a COMBINADA —
  -- que, por definição, ELIMINA o intragrupo e não tem uma linha de mútuo
  -- sequer. A checagem "não achava o par" e abria pendência de pré-condição num
  -- caso que está perfeitamente em ordem. O par certo é o outro: a planilha
  -- lista "A → B", e o saldo mora no balanço de A (a receber) ou de B (a pagar).
  v_doc_mut := fn_documento_por_tipo(p_caso_id, null, p_periodo_id, 'MUTUOS');
  if v_doc_mut is null then
    v_doc_mut := fn_documento_por_tipo(p_caso_id, null, null, 'MUTUOS');
  end if;

  select exists (
    select 1 from documento d
    where d.caso_id = p_caso_id
      and d.tipo_taxonomia in ('BALANCO', 'BALANCETE', 'COMBINADO', 'DF_AUDITADA')
  ) into v_tem_balanco;

  if v_doc_mut is null or not v_tem_balanco then
    return fn_registrar_reconciliacao(p_caso_id, null, p_periodo_id,
      'mutuos_planilha_vs_balanco', 'B', v_doc_mut, null, null,
      'documento_ausente', null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      format('Sem par para reconciliar mútuos: %s não foi entregue neste mandato.',
        case when v_doc_mut is null and not v_tem_balanco then 'a planilha de mútuos e nenhum balanço'
             when v_doc_mut is null then 'a planilha de mútuos' else 'nenhum balanço' end));
  end if;

  v_ver_mut  := fn_versao_atual(v_doc_mut);
  v_unid_mut := fn_unidade_predominante(v_ver_mut);

  -- OS DEGRAUS SÃO RESOLVIDOS UMA VEZ, PARA O DOCUMENTO TODO — e é essencial que
  -- seja assim, não linha a linha. A pergunta do degrau é "este documento
  -- diferencia natureza no rótulo?"; respondê-la por linha faria a linha calada de
  -- um documento que diferencia entrar junto (que é justamente o erro), e a de um
  -- que não diferencia ficar de fora (que é o outro erro).
  select bool_or(fn_texto_nomeia_mutuo(ce.chave)),
         bool_or(fn_texto_nomeia_mutuo(ce.secao))
    into v_pl_rotulo, v_pl_secao
  from campo_extraido ce
  where ce.documento_versao_id = v_ver_mut
    and ce.valor_num is not null
    and fn_papel_linha(ce.chave) <> 'subtotal';
  v_pl_rotulo := coalesce(v_pl_rotulo, false);
  v_pl_secao  := coalesce(v_pl_secao, false);

  foreach v_ano in array fn_anos_alvo(p_periodo_id) loop
    v_col_mut := case when v_ano is null then null
                      else fn_coluna_periodo_do_ano(v_ver_mut, v_ano) end;

    -- ---- LADO A: o saldo de mútuos, somado sobre TODOS os balanços do caso --
    -- Soma, e não `fn_valor_conceito_col`: o saldo aparece numa conta por
    -- empresa, e pegar UMA compararia parte do saldo com a planilha inteira.
    -- A escala entra linha a linha (`fn_valor_em_base`), então um caso com um
    -- balanço em milhar e outro em unidade continua somando certo.
    --
    -- 0123: o resultado é AGREGADO em uma linha só (um objeto por lado), em vez
    -- de percorrido lado a lado. É essa mudança de forma que torna possível
    -- perguntar "os dois lados concordam?" antes de comparar qualquer coisa.
    with balancos as (
      -- UM DOCUMENTO POR ENTIDADE, e isto é correção de defeito medido, não
      -- zelo: o book Vertentes entrega para a mesma controlada um BALANÇO e
      -- um BALANCETE do mesmo exercício, com o mesmo saldo de mútuo (3.974).
      -- Somando os dois, o lado passivo saía 15.427 contra 11.453 do ativo e
      -- a checagem acusava 2.394 de divergência — uma divergência que ela
      -- mesma tinha criado. Balanço e balancete são a MESMA realidade dita
      -- duas vezes; a ordem abaixo escolhe a peça mais definitiva.
      select distinct on (d.entidade_id) d.id, d.entidade_id
      from documento d
      where d.caso_id = p_caso_id
        and d.tipo_taxonomia in ('BALANCO', 'BALANCETE', 'COMBINADO', 'DF_AUDITADA')
      order by d.entidade_id,
               array_position(array['BALANCO','COMBINADO','DF_AUDITADA','BALANCETE'],
                              d.tipo_taxonomia),
               d.criado_em desc
    ), linhas as (
      select d.id as doc_id,
             fn_lado_do_mutuo(ce.chave, ce.secao_canonica) as lado,
             fn_valor_em_base(ce.valor_num, ce.unidade) as valor_base,
             ce.chave,
             ce.unidade
      from balancos d
      join lateral (select fn_versao_atual(d.id) as ver) v on true
      join campo_extraido ce on ce.documento_versao_id = v.ver
      where ce.valor_num is not null
        -- O LADO DO BALANÇO CONTINUA LENDO O RÓTULO, e isto é deliberado: o
        -- defeito medido é do lado da PLANILHA, e nos balanços do Canastra e de
        -- Vertentes a conta diz "Mútuos a pagar" / "Mútuos a receber" no próprio
        -- rótulo. Alargar aqui para a seção seria consertar um caso que não
        -- existe — e traria a mesma over-inclusão: a subseção de balanço é
        -- "Partes Relacionadas", que agrupa mútuo, conta corrente e aluguel.
        and fn_texto_nomeia_mutuo(ce.chave)
        -- 0123: mútuo com SÓCIO sai — a outra ponta dele não está no mandato,
        -- então ele não espelha e não é da população da planilha intragrupo.
        and not fn_mutuo_com_socio(ce.chave, ce.secao)
        and fn_papel_linha(ce.chave) <> 'subtotal'
        and (fn_coluna_periodo_do_ano(v.ver, v_ano) is null
             or fn_normalizar_texto(ce.periodo_coluna)
                = fn_normalizar_texto(fn_coluna_periodo_do_ano(v.ver, v_ano)))
        and fn_lado_do_mutuo(ce.chave, ce.secao_canonica) is not null
    ), por_lado as (
      select lado, abs(sum(valor_base)) as soma_base
      from linhas group by lado
    )
    select
      (select count(*)::int from por_lado) as n_lados,
      (select soma_base from por_lado where lado = 'ativo')   as soma_ativo,
      (select soma_base from por_lado where lado = 'passivo') as soma_passivo,
      -- CONTAGENS SOBRE AS LINHAS, não sobre os lados agregados: com os dois
      -- lados somados num número, `max(n_docs)` por lado dizia "2 documentos"
      -- num par que vem de 3. O que a mensagem promete é quantas peças
      -- sustentam o número, e isso só se conta antes de agrupar.
      count(*)::int as n_linhas,
      count(distinct doc_id)::int as n_docs,
      min(chave) as exemplo,
      bool_or(unidade is null) as tem_sem_escala
    into v_lados
    from linhas;

    if coalesce(v_lados.n_lados, 0) = 0 then
      continue;
    end if;

    -- Escala ausente de um dos lados é o mesmo critério conservador da 0009:
    -- não há o que converter, e afirmar "confere" seria pior que calar.
    if coalesce(v_lados.tem_sem_escala, false) <> (v_unid_mut is null) then
      continue;
    end if;

    -- OS DOIS LADOS SE ESPELHAM: CONFERI-LOS ENTRE SI VEM PRIMEIRO.
    if v_lados.n_lados = 2 then
      v_div := abs(v_lados.soma_ativo - v_lados.soma_passivo);
      v_tol := greatest(p_tolerancia_abs, v_lados.soma_ativo * p_tolerancia_pct);
      if v_div > v_tol then
        -- O achado é dos BALANÇOS, e a planilha não é comparada neste ano:
        -- atribuir a um dos lados uma linha de planilha que não declara lado
        -- seria escolher por sorteio qual metade da contradição é a verdade.
        v_n := v_n + 1;
        v_resultado := 'zona_cinzenta';
        v_partes := v_partes || format(
          '%s: os DOIS LADOS do mesmo mútuo não fecham DENTRO do mandato — a receber soma %s e '
          || 'a pagar soma %s, diferença de %s (em reais). A planilha não foi comparada neste '
          || 'exercício: sem saber qual lado é o correto, atribuir a linha da planilha a um deles '
          || 'seria chute.',
          v_ano, round(v_lados.soma_ativo), round(v_lados.soma_passivo), round(v_div));
        if v_pior_abs is null or v_div > v_pior_abs then
          v_pior_abs := v_div;
          v_pior_pct := case when v_lados.soma_ativo <> 0
                             then v_div / v_lados.soma_ativo end;
        end if;
        continue;
      end if;
      -- Concordam: o saldo do balanço está estabelecido por dupla evidência.
      -- UMA comparação, contra o número que as duas pontas confirmam.
      v_lado_alvo := null;
      v_a := v_lados.soma_ativo;
      v_rotulo_lado := 'os dois lados';
    else
      v_lado_alvo := case when v_lados.soma_ativo is not null then 'ativo' else 'passivo' end;
      v_a := coalesce(v_lados.soma_ativo, v_lados.soma_passivo);
      v_rotulo_lado := v_lado_alvo;
    end if;

    -- ---- LADO B: a planilha ----------------------------------------------
    select coalesce(sum(fn_valor_em_base(ce.valor_num, ce.unidade)), 0) as soma_base,
           coalesce(sum(ce.valor_num), 0) as soma_bruta,
           count(*)::int as n
      into v_pl
    from campo_extraido ce
    where ce.documento_versao_id = v_ver_mut
      and ce.valor_num is not null
      and fn_papel_linha(ce.chave) <> 'subtotal'
      -- MÚTUO CONTRA MÚTUO — nos degraus 1 e 2. A planilha de intragrupo lista
      -- mais coisa do que mútuo (conta corrente rotativa, aluguel entre
      -- coligadas, rateio de despesa), e o balanço registra cada uma num lugar
      -- diferente ("Outros créditos", "Contas a pagar"). Comparar a planilha
      -- INTEIRA contra as contas de mútuo do balanço acusa como divergência
      -- aquilo que é só natureza diferente: no book Vertentes isso somava a
      -- conta corrente de 1.400 de um lado só e inventava 1.400 de diferença.
      --
      -- OS TRÊS DEGRAUS, NA ORDEM. O `case` é o que impede o degrau 2 de valer
      -- quando o degrau 1 existe — sem isso, seção larga ("MÚTUOS E CONTAS
      -- INTRAGRUPO") passa a incluir a conta corrente que o rótulo já tinha
      -- separado, que é o defeito de novo.
      --
      -- Fica anotado o que ISTO deixa de fora: a conferência das linhas
      -- intragrupo que NÃO são mútuo continua sem checagem. É trabalho próprio
      -- — exige casar cada linha com a conta certa de cada balanço.
      and (case
             when v_pl_rotulo then fn_texto_nomeia_mutuo(ce.chave)
             when v_pl_secao  then fn_texto_nomeia_mutuo(ce.secao)
             else true
           end)
      -- A MESMA RÉGUA DOS DOIS LADOS. Se o balanço exclui o mútuo com sócio e a
      -- planilha não, a diferença que sobra é da régua e não do dado — é o defeito
      -- que esta migration está consertando, cometido de novo em espelho.
      and not fn_mutuo_com_socio(ce.chave, ce.secao)
      -- Quando o balanço tem um lado só, a linha da planilha que DECLARA lado
      -- tem de ser do mesmo; a que não declara entra (ela é as duas pontas).
      -- Com os dois lados concordando, `v_lado_alvo` é nulo e não há o que
      -- filtrar: compara-se a planilha inteira contra o saldo estabelecido.
      and (v_lado_alvo is null
           or coalesce(fn_lado_do_mutuo(ce.chave, ce.secao_canonica), v_lado_alvo) = v_lado_alvo)
      and (v_col_mut is null
           or fn_normalizar_texto(ce.periodo_coluna) = fn_normalizar_texto(v_col_mut));
    if coalesce(v_pl.n, 0) = 0 then continue; end if;

    v_b := abs(coalesce(v_pl.soma_base, 0));
    v_a := abs(coalesce(v_a, 0));
    v_n := v_n + 1;
    v_div := abs(v_a - v_b);
    -- Tolerância em MOEDA BASE (reais), não na escala do documento: o mesmo
    -- número tem de significar a mesma coisa num balanço em milhar e noutro
    -- em unidade, senão a checagem é mais frouxa justamente onde os valores
    -- são maiores.
    v_tol := greatest(p_tolerancia_abs, v_a * p_tolerancia_pct);

    if v_div > v_tol then
      v_resultado := 'zona_cinzenta';
      v_partes := v_partes || format(
        '%s (%s): balanço soma %s em %s linha(s) de %s documento(s) e a planilha soma %s em %s '
        || 'linha(s) — diferença de %s (em reais, já convertidas as escalas)',
        v_ano, v_rotulo_lado, round(v_a), v_lados.n_linhas, v_lados.n_docs, round(v_b),
        v_pl.n, round(v_div));
      if v_pior_abs is null or v_div > v_pior_abs then
        v_pior_abs := v_div;
        v_pior_pct := case when v_a <> 0 then v_div / v_a end;
      end if;
    else
      v_partes := v_partes || format('%s (%s): confere (balanço %s = planilha %s, em reais)',
        v_ano, v_rotulo_lado, round(v_a), round(v_b));
    end if;

    v_fonte_a := jsonb_build_object('lado', v_rotulo_lado, 'soma_base', v_a,
      'n_linhas', v_lados.n_linhas, 'n_documentos', v_lados.n_docs,
      'exemplo', v_lados.exemplo, 'ano', v_ano);
    v_fonte_b := jsonb_build_object('lado', v_rotulo_lado, 'soma_base', v_b,
      'soma_bruta', v_pl.soma_bruta, 'n_linhas', v_pl.n, 'unidade', v_unid_mut,
      'documento_versao_id', v_ver_mut,
      'natureza_no_rotulo', v_pl_rotulo, 'natureza_na_secao', v_pl_secao);
  end loop;

  if v_n = 0 then
    -- SEM PENDÊNCIA, e é decisão de projeto: `documento_ausente` é o único
    -- resultado que `fn_registrar_reconciliacao` não transforma em pendência.
    -- Não achar linha de mútuo NO BALANÇO é o caso comum e correto — a
    -- demonstração combinada elimina o intragrupo, e o balanço individual pode
    -- agregar o saldo em "outras partes relacionadas". Abrir pendência aqui
    -- encheria a fila de todo mandato com um aviso que não pede ação nenhuma,
    -- e uma fila assim é uma fila que ninguém lê.
    return fn_registrar_reconciliacao(p_caso_id, null, p_periodo_id,
      'mutuos_planilha_vs_balanco', 'B', v_doc_mut, null, null,
      'documento_ausente', null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      'Planilha de mútuos presente, mas nenhum balanço do mandato traz conta de mútuo com lado '
      || 'reconhecível (combinado elimina intragrupo; individual às vezes agrega em "partes '
      || 'relacionadas"). Sem par, não há o que conferir.');
  end if;

  return fn_registrar_reconciliacao(p_caso_id, null, p_periodo_id,
    'mutuos_planilha_vs_balanco', 'B', v_doc_mut, v_fonte_a, v_fonte_b, v_resultado,
    v_pior_abs, v_pior_pct,
    jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct,
                       'comparacoes', v_n,
                       'natureza_no_rotulo', v_pl_rotulo,
                       'natureza_na_secao', v_pl_secao),
    format('Mútuos: a planilha intragrupo contra o saldo dos balanços em %s comparação(ões) — %s.',
           v_n, array_to_string(v_partes, '; ')));
end;
$$;

comment on function fn_reconciliar_mutuos(uuid, uuid, numeric, numeric) is
  '0123: a natureza "mútuo" é lida na linha OU na seção, e um documento MUTUOS que não a nomeia em lugar nenhum conta inteiro. Confere os dois lados entre si antes de comparar a planilha; lados que discordam são o achado, e aí a planilha não é atribuída a um deles. Mútuo com sócio fica fora: não tem espelho no mandato.';

grant execute on function fn_reconciliar_mutuos(uuid, uuid, numeric, numeric) to authenticated;

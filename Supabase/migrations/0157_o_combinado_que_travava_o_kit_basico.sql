-- =============================================================================
-- Migration 0157 — O COMBINADO QUE TRAVAVA O KIT BÁSICO
--
-- O DEFEITO ORIGINAL, medido na rodada real de 02/09 (lote 7377, mandato
-- "teste Canastra", 38 documentos). A rodada abriu esta pendência:
--
--   bloqueante, item_faltante, completude, (sem arquivo),
--   "Item obrigatório do Kit Básico ausente: COMBINADO", sobrepujavel=false
--
-- E O COMBINADO ESTÁ NO CASO. Dois documentos, medidos na mesma rodada:
--
--   arquivo                                        tipo     confianca  classificado_por  entidades_na_planilha
--   13_Balanco_COMBINADO_Grupo_Canastra_2025.pdf   BALANCO    1.00      openai_conteudo         8
--   14_Balanco_COMBINADO_Grupo_Canastra_2024.pdf   BALANCO    1.00      openai_conteudo         8
--
-- Os dois abriram, na MESMA rodada, pendência `tipo_incorreto` do diagnóstico
-- dizendo literalmente "Diagnóstico de conteúdo sugere tipo COMBINADO
-- (documento está registrado como BALANCO)" — o próprio sistema já sabia.
--
-- A CAUSA é o passo (1) de `fn_recomputar_completude` (0006/0113/0119): o item
-- obrigatório só é considerado presente quando existe
-- `documento.tipo_taxonomia = t.codigo`. Como a IA chamou o combinado de
-- BALANCO — e a 0155 já documenta, com cinco documentos do araucária, que ela
-- chama a MESMA peça de BALANCO ou de COMBINADO conforme o dia —, o checklist
-- declara ausente um documento que está lá, e TRAVA o mandato numa pendência
-- `sobrepujavel = false`. Não sobrepujável: não existe botão no portal que
-- destrave isso. O mandato fica parado até alguém entrar no banco.
--
-- ---------------------------------------------------------------------------
-- A REVISÃO — quatro achados, ANTES de esta migration ser aplicada em
-- lugar nenhum. Nada abaixo é incidente de produção: é o que a revisão mediu
-- contra a primeira versão deste arquivo, num banco descartável, antes do
-- commit. Os quatro estão citados por letra porque foi assim que a revisão os
-- numerou.
-- ---------------------------------------------------------------------------
--
-- ACHADO A — documento SEM NENHUM NÚMERO satisfazia o item. A primeira versão
-- usava `fn_documento_de_varias_empresas` (0155) tal e qual, que conta
-- `distinct entidade_coluna` SEM exigir `valor_num is not null`. Medido: um
-- BALANCO com duas linhas de `valor_texto: "n/d"`, `valor_num` nulo, e duas
-- empresas nas colunas, tirava COMBINADO de `v_faltantes` — e o passo (2)
-- (`v_sem_conteudo`) continua perguntando `d.tipo_taxonomia = t.codigo`, então
-- COMBINADO também não entrava ali: nenhuma pendência de espécie alguma. É a
-- sub-extração que a 0154 mediu (razões de 40% a 78% no araucária) sobre um
-- combinado ESCANEADO — os cabeçalhos de empresa saem da extração, os números
-- não. Sem a correção, o caso passava o Portão 1 com `pronto_para_revisao =
-- true` e a parte combinada do book saía VAZIA: a regra 1 do CLAUDE.md
-- ("nunca apresentar ausência como dado") sendo violada pela correção que
-- existia para outra coisa.
--
-- A exigência de CONTEÚDO mora em `fn_documento_serve_como` — não em
-- `fn_documento_de_varias_empresas`, que a 0155 usa para AUTORIDADE, onde
-- cabeçalho sem número ainda pode legitimamente rebaixar um documento (a
-- pergunta lá é "isso é derivado?", não "isso tem o que preciso"). Por isso
-- este arquivo não toca na 0155: introduz um cálculo próprio, com o filtro
-- `valor_num is not null` que a checklist precisa e a autoridade não.
--
-- ACHADO B — a exceção era restrita pelo tipo ALVO (só valia para o item
-- COMBINADO) e NUNCA pelo tipo FONTE: o `not exists` do passo (1) varre TODO
-- documento do caso, e qualquer um com colunas de várias empresas satisfazia
-- COMBINADO — medido com um MUTUOS de duas empresas nas colunas, sozinho.
-- O arranjo realista não é um mútuo: é a DF_AUDITADA consolidada de um grupo,
-- e quem chama isso de "a soma das empresas" é o próprio cabeçalho da 0155.
--
-- DECISÃO (escrita aqui, isolada em `fn_combinado_estrutural_apto`, para
-- poder mudar num lugar só e com o número ao lado): o que pode se apresentar
-- em forma combinada é DEMONSTRAÇÃO CONTÁBIL PRIMÁRIA — DRE, BALANCO,
-- FLUXO_CAIXA, os três primários do próprio Kit Básico (0002). Documento
-- AUXILIAR (MUTUOS, AGING_*, RAZAO, BALANCETE, MAPA_DIVIDA…) não é
-- demonstração, é apoio a uma, e não entra.
--
-- `DF_AUDITADA` FICA DE FORA, E ISSO É UMA PERGUNTA ABERTA PARA O DONO, NÃO
-- UMA CERTEZA. Ela é demonstração financeira de verdade — a 0151 já a trata
-- ao lado de BALANCO na escala de `autoridade` (60 contra 50) — e uma
-- DF_AUDITADA consolidada de grupo é candidata natural a satisfazer o item
-- COMBINADO. Mas deixá-la entrar aqui sem decisão do dono trocaria "o
-- classificador errou o rótulo" (o caso medido no lote 7377, uma peça que
-- CHEGOU e foi mal rotulada) por "o mandato nunca mandou o combinado e a
-- auditada consolidada passa a bastar" — silenciosamente, em todo mandato já
-- aberto. `taxonomia_tipo_documento` não tem hoje uma coluna que diga "é
-- demonstração primária" (só `categoria`, que agrupa BALANCO e DF_AUDITADA e
-- BALANCETE e RAZAO e NOTAS_EXPL todos sob "Contábil/Demonstrações" — grosso
-- demais para esta decisão). Uma lista literal, pequena, comentada, é mais
-- honesta que fingir que existe um sinal estrutural aqui.
--
-- ACHADO C — as 3 exigências de LINHA do item COMBINADO (`ativo_total`,
-- `caixa_e_equivalentes`, `passivo_mais_pl`, seed da 0113) deixavam de ser
-- avaliadas quando o documento que serve como COMBINADO está rotulado
-- diferente, e NINGUÉM via isso: `fn_exigencias_do_caso` monta
-- `tipos_do_caso` de `distinct d.tipo_taxonomia`, e monta `campos` a partir do
-- rótulo cru — então 'COMBINADO' nunca entrava em nenhuma das duas quando o
-- único documento que serve como tal está rotulado BALANCO. Medido lado a
-- lado, no mesmo dado: rotulado COMBINADO abre
-- `completude:linha_exigida:COMBINADO:caixa_e_equivalentes`; pela via
-- estrutural, ANTES desta correção, zero pendências de linha — nenhuma das
-- três. Antes desta migration isso era inconsequente (o caso estava travado
-- no passo 1); com o passo 1 corrigido, o caso avança, e a ausência das três
-- checagens ficava indistinguível de "checadas e presentes" — o mesmo defeito
-- de forma que a regra 1 do CLAUDE.md existe para impedir, só que um nível
-- abaixo (a LINHA, não o item).
--
-- A CORREÇÃO: `fn_exigencias_do_caso` passa a enxergar o tipo SERVIDO
-- (`fn_documento_serve_como`), não só o rotulado — em três pontos: (i)
-- `tipos_do_caso` ganha COMBINADO quando algum documento o serve por
-- estrutura; (ii) `tipos_com_conteudo` pergunta pelo tipo servido, mantendo
-- `fn_linhas_do_tipo` intocada para todo tipo que não seja COMBINADO (é a
-- única exceção que `fn_documento_serve_como` conhece, então nenhum outro
-- tipo muda de comportamento); (iii) `campos` ganha um `union all` aditivo —
-- o documento estrutural continua contando para o seu próprio tipo rotulado
-- E passa a contar também para COMBINADO. É mais lata de vermes do que
-- parecia no primeiro rascunho (a função foi reemitida inteira, não só o
-- passo 1), mas o silêncio não era opção.
--
-- ACHADO D — a sonda dizia PRESENTE com a exceção MORTA. O requisito `corpo`
-- da primeira versão casava `position('0157' in prosrc) > 0`, e o marcador
-- morava num BLOCO DE COMENTÁRIO; o requisito `funcao` conferia só a
-- existência do nome. Medido: prefixando o predicado com `false and` (a
-- exceção nunca mais entra, os comentários intactos), `fn_instalacao_conferir`
-- devolveu os dois como `presente = true`. Isso não é um acaso do exemplo: é
-- estrutural — QUALQUER `false and (X)` preserva `X` como substring, então
-- NENHUM marcador textual sobrevive a esse ataque, por melhor escolhido que
-- seja. Só uma checagem que EXECUTA o predicado pega isso.
--
-- A CORREÇÃO isola a decisão (achados A+B) numa função PURA — sem tocar
-- tabela — `fn_combinado_estrutural_apto(tipo_fonte, empresas_com_valor)`.
-- Sendo pura, ela pode ser exercitada por literais, sem fixture de documento:
-- é a view `instalacao_sonda_combinado_estrutural`, registrada como
-- `tipo = 'seed'` com `criterio_seed`, que `Supabase/test/instalacao.test.sql`
-- já confere não-vazia contra TODO seed do catálogo (achado do bloco "E os
-- seeds também"). Um `false and` dentro da função derruba a view para zero
-- linhas — `presente = false` — porque desta vez o predicado É executado, não
-- apenas procurado como texto. Os requisitos de `corpo`/`funcao` continuam
-- existindo (provam que a FIAÇÃO — quem chama quem — está no lugar), mas
-- deixam de ser a única linha de defesa.
-- ---------------------------------------------------------------------------
--
-- O QUE NÃO MUDOU, DELIBERADAMENTE: `fn_documento_de_varias_empresas` (0155)
-- não é tocada — continua sendo o critério de AUTORIDADE, sem exigência de
-- conteúdo, porque ali a pergunta é outra. Não há coluna nova no catálogo
-- (`taxonomia_tipo_documento`): a lista de fontes permitidas é código, de
-- propósito, pela mesma razão da 0155 — uma coluna sugeriria um mecanismo
-- geral que não existe.
--
-- A PENDÊNCIA BLOQUEANTE JÁ ABERTA CONTINUA SE RESOLVENDO SOZINHA. O `update
-- pendencia ... estado = 'resolvida'` que já existe no passo (1) desde a 0006
-- resolve toda `item_faltante` cuja descrição não bate com a lista CORRENTE
-- de faltantes (`v_faltantes`). Quando COMBINADO passa a ser servido pelo
-- documento estrutural qualificado (achados A+B), ele sai de `v_faltantes` no
-- próximo recomputo, e a pendência do lote 7377 casa na cláusula `not (...)`
-- e é resolvida — sem código novo.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- fn_combinado_estrutural_apto — a DECISÃO isolada (achados A e B da revisão),
-- em função PURA (sem tocar tabela) para poder ser medida sem fixture de
-- documento. Ver o cabeçalho para o raciocínio completo por trás de cada
-- metade do `and`.
-- -----------------------------------------------------------------------------
create or replace function fn_combinado_estrutural_apto(p_tipo_fonte text, p_empresas_com_valor integer)
returns boolean
language sql
immutable
as $$
  select
    -- Achado B: só demonstração contábil PRIMÁRIA pode se apresentar em forma
    -- combinada. DF_AUDITADA fica de fora de propósito — pergunta aberta do
    -- dono, ver o cabeçalho da 0157.
    p_tipo_fonte = any (array['DRE', 'BALANCO', 'FLUXO_CAIXA'])
    -- Achado A: cabeçalho de várias empresas sem NENHUM número não é
    -- combinado — é a sub-extração que a 0154 já mediu (40%-78% no
    -- araucária). ">1", não ">0", pela mesma razão da 0155: duas colunas
    -- iguais (comparativo de anos da mesma empresa) não é grupo.
    and coalesce(p_empresas_com_valor, 0) > 1;
$$;

comment on function fn_combinado_estrutural_apto(text, integer) is
  '(Revisão da 0157, achados A e B) Este par — tipo do documento-FONTE, quantas empresas têm VALOR '
  'extraído nas colunas (não só cabeçalho) — o torna apto a servir como o item COMBINADO do Kit '
  'Básico? Fonte precisa ser demonstração contábil PRIMÁRIA (DRE/BALANCO/FLUXO_CAIXA — DF_AUDITADA '
  'fica fora, decisão aberta do dono) E precisa haver mais de uma empresa com número de verdade. '
  'Função pura de propósito: a sonda de instalação a exercita por literais, sem fixture de '
  'documento (instalacao_sonda_combinado_estrutural) — um marcador textual não sobrevive a um '
  '"false and" que mate o predicado e deixe os comentários intactos; uma função executada, sim.';

grant execute on function fn_combinado_estrutural_apto(text, integer) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_documento_serve_como — a ÚNICA porta pela qual um documento pode
-- satisfazer um item do Kit Básico sob rótulo diferente do seu.
--
-- HOJE só existe uma exceção: COMBINADO aceita substituto estrutural, e a
-- decisão de QUEM qualifica mora inteira em fn_combinado_estrutural_apto
-- (achados A e B). Nasce assim de propósito e não como lista/tabela, para não
-- sugerir que o mecanismo generaliza — o dia em que existir um segundo caso
-- real e medido, ele entra aqui, ao lado deste, com o número que o justifica.
-- -----------------------------------------------------------------------------
create or replace function fn_documento_serve_como(p_documento_id uuid, p_tipo_taxonomia text)
returns boolean
language sql
stable
as $$
  select exists (
    select 1 from documento d
    where d.id = p_documento_id
      and (
        d.tipo_taxonomia = p_tipo_taxonomia
        -- Revisão da 0157: aqui só se calcula o DADO que a decisão pede —
        -- quantas empresas distintas têm valor_num extraído (não só
        -- cabeçalho) na versão vigente. A decisão em si (fonte permitida +
        -- limiar) mora em fn_combinado_estrutural_apto.
        or (
          p_tipo_taxonomia = 'COMBINADO'
          and fn_combinado_estrutural_apto(
                d.tipo_taxonomia,
                (select count(distinct ce.entidade_coluna)::int
                   from campo_extraido ce
                  where ce.documento_versao_id = fn_versao_com_extracao(d.id)
                    and ce.valor_num is not null
                    and ce.entidade_coluna is not null)
              )
        )
      )
  );
$$;

comment on function fn_documento_serve_como(uuid, text) is
  'Este documento satisfaz o item <tipo_taxonomia> do Kit Básico, mesmo que rotulado diferente? '
  'Regra do rótulo (tipo_taxonomia = codigo) OU, só para o código COMBINADO, a decisão de '
  'fn_combinado_estrutural_apto (revisão da 0157, achados A e B): fonte é demonstração contábil '
  'primária (DRE/BALANCO/FLUXO_CAIXA) E mais de uma empresa tem VALOR extraído nas colunas — não só '
  'cabeçalho. Não é fn_documento_de_varias_empresas (0155): aquela serve AUTORIDADE e não exige '
  'conteúdo; esta serve o checklist e exige. Medido no lote 7377 (mandato "teste Canastra"): dois '
  'documentos com 8 empresas na planilha, confiança 1,0, classificados de BALANCO, travavam o item '
  'COMBINADO como ausente e não-sobrepujável. A exceção NÃO generaliza para outros tipos-ALVO — de '
  'propósito, para o Kit Básico continuar exigindo o balanço individual mesmo com um combinado no '
  'caso.';

grant execute on function fn_documento_serve_como(uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_recomputar_completude — corpo da 0119 com o passo (1) reaberto para
-- estrutura (0157). Reemitida INTEIRA (padrão do repositório). Passos (2),
-- (2b), (3) e (4): intactos, byte a byte. Mudou SÓ o (1): "existe documento do
-- tipo" vira "existe documento que SERVE como o tipo" — fn_documento_serve_como.
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
      'entidade', v_ex.entidade);

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
                case when v_ex.entidade is not null then
                  format('Nos documentos de %s da entidade "%s", a linha exigida "%s" não foi '
                         'localizada na versão vigente. Sem ela, PARA ESTA ENTIDADE: %s.%s Conferir '
                         'se o documento dela traz a linha com outro rótulo (e corrigir na revisão) '
                         'ou reenviar o arquivo completo.',
                         v_ex.tipo_taxonomia, v_ex.entidade, v_ex.rotulo,
                         array_to_string(v_ex.depende_de, '; '),
                         case when v_ex.origem = 'proposta'
                              then ' (Exigência PROPOSTA na análise — nenhuma checagem automática a lê hoje.)'
                              else '' end)
                else
                  format('O tipo %s chegou e rendeu linhas, mas a linha exigida "%s" não foi '
                         'localizada na versão vigente de nenhum documento do tipo. Sem ela: %s.%s '
                         'Conferir se o documento traz a linha com outro rótulo (e corrigir na '
                         'revisão) ou reenviar o arquivo completo.',
                         v_ex.tipo_taxonomia, v_ex.rotulo,
                         array_to_string(v_ex.depende_de, '; '),
                         case when v_ex.origem = 'proposta'
                              then ' (Exigência PROPOSTA na análise — nenhuma checagem automática a lê hoje.)'
                              else '' end)
                end,
                v_ex.entidade_id,
                v_motivo);
    else
      update pendencia set
        severidade   = coalesce(v_ex.severidade, 'importante')::pendencia_severidade,
        sobrepujavel = coalesce(v_ex.sobrepujavel, true)
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

comment on function fn_recomputar_completude(uuid) is
  'Portão 1 (chegada) + 0036 (recebido sem conteúdo) + 0113/0119 (passo 2b: linha exigida ausente, '
  'cobrada POR ENTIDADE quando o escopo pede) + 0157 (passo 1: "sem documento do tipo" vira "sem '
  'documento que SIRVA como o tipo" — fn_documento_serve_como aceita, só para COMBINADO, um '
  'documento estruturalmente combinado e com conteúdo (fn_combinado_estrutural_apto, achados A e B '
  'da revisão) classificado como BALANCO/DRE/FLUXO_CAIXA). Política por linha é do dono; default = '
  'importante/sobrepujável. `portao1_ok` segue "chegou tudo"; `pronto_para_revisao` segue "chegou '
  'tudo E tem conteúdo".';

-- -----------------------------------------------------------------------------
-- fn_exigencias_do_caso — reemitida (corpo da 0146) para o achado C da
-- revisão: o tipo COMBINADO servido por estrutura (rotulado BALANCO/DRE/
-- FLUXO_CAIXA, fn_documento_serve_como) precisa ter suas 3 exigências de
-- linha (0113) AVALIADAS, não silenciadas. Três pontos mudam, cada um
-- comentado no lugar; o resto — `nomes_resolvidos`, `campos_ent`,
-- `linhas_distintas`, `casadas`, `satisfazedores`, `eixo`, o select final —
-- intacto, byte a byte.
-- -----------------------------------------------------------------------------
create or replace function fn_exigencias_do_caso(p_caso_id uuid)
returns table (
  exigencia_id   uuid,
  tipo_taxonomia text,
  conceito       text,
  rotulo         text,
  origem         text,
  depende_de     text[],
  severidade     text,
  sobrepujavel   boolean,
  descricao      text,
  entidade       text,
  entidade_id    uuid,
  satisfeita     boolean
)
language sql
stable
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
         case when ax.entidade_id is null
              then exists (select 1 from satisfazedores s where s.exigencia_id = e.id)
              else exists (select 1 from satisfazedores s
                            where s.exigencia_id = e.id and s.entidade_id = ax.entidade_id)
         end as satisfeita
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
  left join entidade ent on ent.id = ax.entidade_id
  where e.ativo;
$$;

comment on function fn_exigencias_do_caso(uuid) is
  'Exigências de linha aplicáveis ao caso (tipos presentes COM conteúdo), com satisfeita s/n. '
  'Casa contra a versão VIGENTE (0102), pela chave, pela seção, pela COLUNA (0145) ou pelo rótulo '
  'estrutural. Num documento que declara VÁRIAS colunas de entidade, a linha sem coluna não é '
  'atribuída à capa (0146). Desde a revisão da 0157 (achado C), um documento que SERVE como '
  'COMBINADO por estrutura (rotulado BALANCO/DRE/FLUXO_CAIXA, fn_documento_serve_como) tem suas '
  'linhas avaliadas TAMBÉM sob COMBINADO, além do seu próprio tipo rotulado — sem isso as 3 '
  'exigências do item (ativo_total, caixa_e_equivalentes, passivo_mais_pl) ficavam mudas assim que '
  'o passo 1 de fn_recomputar_completude parou de exigir o rótulo exato. Alimenta o passo 2b de '
  'fn_recomputar_completude e a tela do caso.';

grant execute on function fn_exigencias_do_caso(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- A SONDA DE INSTALAÇÃO — revisão do achado D: marcador textual ('corpo'/
-- 'funcao') não sobrevive a um `false and` que mate o predicado e deixe os
-- comentários intactos, porque a substring buscada continua lá. A view abaixo
-- EXECUTA fn_combinado_estrutural_apto com literais — sem fixture de
-- documento, porque a função é pura — e só devolve a linha (criterio_seed=1)
-- quando as três propriedades (positivo, achado A, achado B) valem ao mesmo
-- tempo. `Supabase/test/instalacao.test.sql` já confere TODO requisito
-- tipo='seed' não-vazio contra o banco cheio (bloco "E os seeds também"), o
-- que torna esta view parte do portão do CI, não só do painel de produção.
-- -----------------------------------------------------------------------------
create or replace view instalacao_sonda_combinado_estrutural as
select 1 as ok
where
  -- positivo: fonte permitida (BALANCO), 2+ empresas com valor de verdade.
  fn_combinado_estrutural_apto('BALANCO', 2) = true
  and fn_combinado_estrutural_apto('DRE', 3) = true
  and fn_combinado_estrutural_apto('FLUXO_CAIXA', 3) = true
  -- achado A: cabeçalho sem número nenhum, ou uma empresa só, não serve.
  and fn_combinado_estrutural_apto('BALANCO', 0) = false
  and fn_combinado_estrutural_apto('BALANCO', 1) = false
  -- achado B: fonte fora da lista (auxiliar, ou DF_AUDITADA de propósito)
  -- não serve mesmo com conteúdo de sobra.
  and fn_combinado_estrutural_apto('MUTUOS', 5) = false
  and fn_combinado_estrutural_apto('DF_AUDITADA', 5) = false;

comment on view instalacao_sonda_combinado_estrutural is
  '(0157, achado D da revisão) Autoteste da decisão de fn_combinado_estrutural_apto, EXECUTADA por '
  'literais (função pura, sem fixture de documento): 1 linha só se o positivo, o achado A '
  '(conteúdo exigido) e o achado B (fonte permitida) valem TODOS ao mesmo tempo. Um marcador '
  'textual de corpo/função não pega um "false and" que mate o predicado e deixe os comentários '
  'intactos — esta view pega, porque o predicado É executado.';

grant select on instalacao_sonda_combinado_estrutural to authenticated;

-- -----------------------------------------------------------------------------
-- A SONDA — o catálogo
-- -----------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('kit_basico_aceita_combinado_estrutural', '0157', 'corpo', 'fn_recomputar_completude',
   'fn_documento_serve_como(d.id, t.codigo)', null,
   'O item obrigatório COMBINADO do Kit Básico é declarado ausente mesmo com o documento no caso, '
   'porque o classificador o rotulou de BALANCO — medido no lote 7377 (mandato "teste Canastra"): '
   'dois documentos COMBINADO, confiança 1,0, ficam presos atrás de uma pendência bloqueante e '
   'NÃO-sobrepujável que nenhum botão do portal destrava, e o mandato para. Este requisito prova só '
   'a FIAÇÃO (o passo 1 chama fn_documento_serve_como); a decisão em si é o requisito '
   'combinado_estrutural_regra_viva.',
   'bloqueante', 600),
  ('documento_serve_como', '0157', 'funcao', 'fn_documento_serve_como', null, null,
   'Sem ela o passo (1) de fn_recomputar_completude volta a perguntar só ao rótulo do documento, '
   'e o combinado estrutural (0155) fica escondido atrás do BALANCO que o classificador escolheu '
   'entre dois rótulos igualmente defensáveis.',
   'importante', 605),
  ('combinado_estrutural_regra_viva', '0157', 'seed', 'instalacao_sonda_combinado_estrutural', null, 1,
   'A REGRA de quem pode servir como COMBINADO estrutural (fonte permitida + conteúdo exigido) '
   'pode existir como código morto: um requisito de "corpo" ou "função" prova só que o texto está '
   'no arquivo, não que o predicado decide certo. Esta linha executa a decisão contra três casos '
   'fixos; ausente aqui quer dizer que um documento sem número, ou de fonte errada (mútuo, aging, '
   'DF_AUDITADA), pode voltar a satisfazer o item COMBINADO em silêncio — o book sai vazio ou o '
   'grupo empresta autoridade a um auxiliar, e nenhuma pendência avisa.',
   'bloqueante', 606),
  ('exigencias_enxergam_tipo_servido', '0157', 'corpo', 'fn_exigencias_do_caso',
   'dc.serve_combinado', null,
   'As 3 exigências de linha do COMBINADO (ativo_total, caixa_e_equivalentes, passivo_mais_pl) '
   'ficam mudas — nem satisfeitas nem ausentes — quando o único documento que serve como COMBINADO '
   'está rotulado BALANCO/DRE/FLUXO_CAIXA: a função monta tipos e linhas pelo rótulo cru, e '
   '''COMBINADO'' nunca aparece. Sem isso, o Kit Básico dá o item por completo sem nunca ter '
   'conferido se o ativo total, o caixa e o passivo+PL do combinado realmente vieram.',
   'importante', 607)
on conflict (chave) do update
  set migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
      marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
      porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0157',
       revisado_em = date '2026-09-03',
       observacao = 'Revisão de 03/09/2026 (antes do primeiro commit da 0157): a migration original '
                    '(02/09) tinha quatro defeitos próprios, medidos num banco descartável antes de '
                    'aplicar em lugar nenhum. (A) o predicado estrutural não exigia conteúdo — um '
                    'documento com cabeçalho de várias empresas e ZERO valor_num satisfazia o item, '
                    'e nenhum passo acusava nada (book vazio calado). (B) a exceção não filtrava o '
                    'tipo-FONTE — qualquer documento do caso (um MUTUOS, por exemplo) com colunas de '
                    'várias empresas satisfazia COMBINADO; agora só demonstração contábil primária '
                    '(DRE/BALANCO/FLUXO_CAIXA) qualifica, com DF_AUDITADA fora de propósito e a '
                    'pergunta escrita para o dono. (C) fn_exigencias_do_caso ignorava o tipo servido '
                    'e as 3 exigências de linha do COMBINADO ficavam mudas assim que o passo 1 parou '
                    'de exigir o rótulo exato — corrigido enxergando fn_documento_serve_como em três '
                    'pontos da função. (D) a sonda usava marcador textual que sobrevive a um "false '
                    'and"; agora a decisão central (fn_combinado_estrutural_apto) é isolada em '
                    'função pura e exercitada de verdade por uma view-seed '
                    '(instalacao_sonda_combinado_estrutural), conferida não-vazia pelo '
                    'instalacao.test.sql. Quatro requisitos novos/revisados.'
 where id;

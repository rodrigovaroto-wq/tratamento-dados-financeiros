-- =============================================================================
-- Migration 0102 — A Modelagem lê a versão VIGENTE de cada documento
--
-- O QUE ESTA MIGRATION FECHA, e por que ela vem logo depois da 0101. A 0101 tirou
-- `fn_conferir_modelagem` de 9,3 s para ~600 ms num caso do tamanho do v35, e com
-- isso a tela parou de anunciar "este caso ainda não tem linha extraída" por
-- causa de consulta cancelada. Ela resolveu o CUSTO POR OCORRÊNCIA e não tocou no
-- NÚMERO DE OCORRÊNCIAS — e o número de ocorrências deste sistema cresce sozinho.
--
-- A 0026 estabeleceu que reenviar ou reextrair um documento cria uma
-- `documento_versao` nova (`n_versao + 1`) sob o mesmo `documento`, "sem perder a
-- anterior". Guardar a anterior é certo: é a trilha. **Mas a leitura da Modelagem
-- nunca soube disso.** `fn_linhas_para_modelagem` percorre
--
--     campo_extraido → documento_versao → documento (caso_id = ?)
--
-- sem uma única menção a `n_versao`. Ou seja: as ocorrências de TODAS as versões
-- entram no mesmo agrupamento. Medido nesta sessão, contra o caso real:
--
--     Estoques, antes da reextração:   7 ocorrências, valor 24.610
--     depois de UMA reextração:        8 ocorrências, valor 777.777
--
-- A ocorrência velha não foi substituída, foi SOMADA à contagem — e o
-- `valor_ultimo` (maior módulo, 0042) passou a poder vir da versão que o analista
-- acabou de corrigir e substituir. São dois estragos de naturezas diferentes:
--
--   • CORREÇÃO: a tela mostra, e o Excel exporta, valor de versão SUPERADA. Isto
--     não dá erro nem parece errado — parece um número. É a mesma família da
--     dupla contagem, o defeito mais caro deste projeto.
--   • CUSTO: cada rodada de reextração acrescenta um jogo inteiro de ocorrências
--     ao caso. O caso do v35 tem 760; três reextrações fazem 2.280, e o custo das
--     funções da tela é linear nas ocorrências. **O `statement_timeout` que a
--     0101 acabou de destravar volta sozinho, sem ninguém mexer em uma linha de
--     código** — e volta com a mesma cara de "este caso está vazio".
--
-- E O RESTO DO REPOSITÓRIO JÁ FAZIA CERTO. As quatro `fn_reconciliar_*` resolvem
-- a versão com `fn_versao_atual` antes de ler campo. Quem não resolvia era
-- justamente o caminho da Modelagem, do checklist e do export. Esta migration põe
-- os cinco leitores por caso na mesma regra, de UMA definição só.
--
-- O QUE ESTA MIGRATION NÃO MUDA: com um caso de uma versão por documento — que é
-- o estado de toda fixture deste repositório e do caso do v35 antes de qualquer
-- reextração — nenhum resultado muda, campo a campo. É por isso que as suítes
-- existentes valem sem uma linha alterada.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- fn_versao_com_extracao — a versão VIGENTE de um documento, para quem lê CONTEÚDO.
--
-- POR QUE NÃO REUSAR `fn_versao_atual`, e por que isto não é duas definições da
-- mesma coisa. `fn_versao_atual` (0009) devolve `max(n_versao)` — "a versão mais
-- recente que existe". É a resposta certa para quem ACABOU de registrar um
-- documento e vai escrever a extração nele: é o caso de uso das
-- `fn_reconciliar_*`, e mudá-la mexeria no caminho de escrita da reconciliação.
--
-- Quem LÊ conteúdo precisa de outra pergunta: "qual é a versão mais recente que
-- TEM extração". A diferença não é teórica, é uma janela que o sistema abre em
-- toda rodada: `fn_registrar_documento` cria a `documento_versao` e
-- `fn_registrar_campos_extraidos` a preenche DEPOIS, em outra chamada. Entre as
-- duas, a versão mais recente está vazia.
--
-- **Com `max(n_versao)` puro, nessa janela a tela de Modelagem ficaria em branco**
-- — exibindo "este caso ainda não tem linha extraída com valor" num caso cheio,
-- que é LITERALMENTE o sintoma que a 0101 e esta migration existem para matar.
-- Trocar um jeito de mentir por outro não é correção. Daí a função separada, com
-- a diferença nomeada aqui em vez de descoberta em produção.
--
-- Versão registrada e ainda não extraída, portanto, não esconde a anterior: a
-- tela segue mostrando o último conteúdo que existe, e passa a mostrar o novo no
-- instante em que a extração grava a primeira linha.
-- -----------------------------------------------------------------------------
create or replace function fn_versao_com_extracao(p_documento_id uuid)
returns uuid
language sql
stable
as $$
  -- marca-0102
  select dv.id
  from documento_versao dv
  where dv.documento_id = p_documento_id
    and exists (select 1 from campo_extraido ce where ce.documento_versao_id = dv.id)
  order by dv.n_versao desc
  limit 1;
$$;

comment on function fn_versao_com_extracao(uuid) is
  'A documento_versao VIGENTE para quem lê conteúdo: a de maior n_versao que TEM campo_extraido. '
  'Difere de fn_versao_atual (max(n_versao)) de propósito: entre fn_registrar_documento e '
  'fn_registrar_campos_extraidos a versão mais recente está vazia, e max(n_versao) puro deixaria a '
  'tela de Modelagem em branco nessa janela — o mesmo sintoma que a 0101 corrigiu.';

grant execute on function fn_versao_com_extracao(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_linhas_para_modelagem — corpo da 0101, com o filtro de versão.
--
-- Única mudança: `and dv.id = fn_versao_com_extracao(d.id)` na CTE `bruto`. O
-- filtro fica no ÚNICO lugar onde as ocorrências do caso são lidas, então tudo
-- que desce daí (papel, valor com sinal, unidade, documentos, sobreposição)
-- herda o escopo sem repetir a regra.
--
-- Custo: a função é avaliada uma vez por `documento` do caso (14 no v35), não por
-- ocorrência — e cada avaliação é um índice em (documento_id, n_versao). Medido
-- contra a fixture real: sem efeito no tempo, que continua na casa dos 600 ms.
-- -----------------------------------------------------------------------------
create or replace function fn_linhas_para_modelagem(p_caso_id uuid)
returns table (
  secao_canonica text,
  chave          text,
  rotulo_norm    text,
  entidade       text,
  valor_ultimo   numeric,
  n_ocorrencias  bigint,
  papel          text,
  unidade        text,
  moeda          text,
  documentos     text[],
  sobreposicao_suspeita boolean
)
language sql
stable
as $$
  -- marca-0102
  with bruto as (
    select
      ce.secao_canonica,
      ce.chave,
      fn_normalizar_texto(ce.chave) as rotulo_norm,
      coalesce(ce.entidade_coluna, e.razao_social) as entidade,
      ce.valor_num,
      ce.unidade,
      ce.moeda,
      d.tipo_taxonomia
    from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
    left join entidade e on e.id = d.entidade_id
    where d.caso_id = p_caso_id
      and ce.valor_num is not null
      -- 0102: só a versão VIGENTE de cada documento. Sem isto, cada reextração
      -- soma um jogo inteiro de ocorrências ao caso — inflando n_ocorrencias,
      -- deixando valor_ultimo vir de versão superada, e devolvendo o caso ao
      -- statement_timeout que a 0101 tinha acabado de destravar.
      and dv.id = fn_versao_com_extracao(d.id)
  ),
  -- O PAPEL É PROPRIEDADE DO RÓTULO, NÃO DA OCORRÊNCIA (0101).
  --
  -- `fn_papel_linha` depende só de (chave, tipo do documento, unidade) e custa
  -- ~1,6 ms por chamada. Avaliá-la por ocorrência era pagar 760 vezes por uma
  -- resposta que tem ~250 valores distintos. Aqui ela roda uma vez por combinação
  -- distinta e o resultado volta por join — é a mesma resposta, porque a função é
  -- `immutable`.
  papel_do_rotulo as (
    select distinct chave, tipo_taxonomia, unidade,
           fn_papel_linha(chave, tipo_taxonomia, unidade) as papel
    from (select distinct chave, tipo_taxonomia, unidade from bruto) d
  ),
  ocorrencia as (
    select b.*, p.papel
    from bruto b
    join papel_do_rotulo p
      on p.chave = b.chave
     and p.tipo_taxonomia is not distinct from b.tipo_taxonomia
     and p.unidade is not distinct from b.unidade
  ),
  base as (
    select
      o.secao_canonica,
      (array_agg(o.chave order by length(o.chave)))[1] as chave,
      o.rotulo_norm,
      max(o.entidade) as entidade,
      -- valor da ocorrência de MAIOR MÓDULO, COM O SINAL (0042).
      (array_agg(o.valor_num order by abs(o.valor_num) desc nulls last))[1] as valor_ultimo,
      count(*) as n_ocorrencias,
      max(o.unidade) as unidade,
      max(o.moeda) as moeda,
      array_agg(distinct o.tipo_taxonomia) as documentos,
      -- papel da ocorrência de MAIOR PRIORIDADE (fn_papel_prioridade): no empate
      -- entre documentos, o lado seguro é não projetar.
      (array_agg(o.papel order by fn_papel_prioridade(o.papel)))[1] as papel
    from ocorrencia o
    group by o.secao_canonica, o.rotulo_norm
  ),
  -- SOBREPOSIÇÃO SUSPEITA, por join (0101). Mesma regra da 0042: outra linha da
  -- MESMA seção, MESMO valor, e um rótulo descrevendo o outro de forma mais
  -- grossa (`Provisões` × `Provisão para passivo a descoberto de controlada`).
  -- A função não escolhe por ninguém: MARCA, e quem decide é o analista.
  sobrepostas as (
    select distinct b.secao_canonica, b.rotulo_norm
    from base b
    join base o
      on coalesce(o.secao_canonica, '') = coalesce(b.secao_canonica, '')
     and o.valor_ultimo = b.valor_ultimo
     and o.rotulo_norm <> b.rotulo_norm
    where b.papel = 'conta' and o.papel = 'conta'
      and (fn_rotulo_contido(o.chave, b.chave) or fn_rotulo_contido(b.chave, o.chave))
  )
  select b.secao_canonica, b.chave, b.rotulo_norm, b.entidade, b.valor_ultimo,
         b.n_ocorrencias, b.papel, b.unidade, b.moeda, b.documentos,
         (s.rotulo_norm is not null) as sobreposicao_suspeita
  from base b
  left join sobrepostas s
    on s.rotulo_norm = b.rotulo_norm
   and coalesce(s.secao_canonica, '') = coalesce(b.secao_canonica, '')
  order by b.secao_canonica nulls last, b.rotulo_norm;
$$;

comment on function fn_linhas_para_modelagem(uuid) is
  'Linhas lógicas do caso para a tela de Modelagem, com PAPEL (conta/subtotal/derivado/'
  'serie_mensal), valor COM SINAL, unidade/moeda, documentos de origem e marca de sobreposição. '
  'Existe como função porque campo_extraido não tem caso_id — o escopo por caso mora aqui. '
  '0101: papel calculado uma vez por rótulo e sobreposição por join, para caber no '
  'statement_timeout. 0102: só a versão VIGENTE de cada documento (reextração deixava a versão '
  'superada somando ocorrência e podendo ditar o valor_ultimo).';

grant execute on function fn_linhas_para_modelagem(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_papel_do_rotulo_no_caso — a GUARDA precisa ver o mesmo que a tela.
--
-- Esta é a função que a 0100 alinhou com `fn_linhas_para_modelagem` depois de o
-- "aplicar em lote" cair inteiro em produção: a tela oferecia a linha como conta
-- e a guarda a recusava, porque as duas calculavam o papel com escopos
-- diferentes. Se o filtro de versão entrasse só na tela, a divergência VOLTARIA
-- pela outra ponta — uma ocorrência de versão superada, com papel mais
-- restritivo, faria a guarda recusar a linha que a tela acabou de oferecer.
--
-- Os dois lados andam juntos ou o defeito da 0100 renasce. É o mesmo motivo pelo
-- qual a 0100 declarou que as duas funções têm de agrupar igual.
--
-- DECLARADO: HOJE ESTE FILTRO NÃO MUDA NENHUM RESULTADO, E NÃO ESTÁ COBERTO POR
-- TESTE. Medido nesta sessão, e o motivo é preciso: `fn_papel_linha(chave, tipo,
-- unidade)` declara `p_unidade` na assinatura e **nunca a usa no corpo** — o papel
-- é função de (chave, tipo do documento) e nada mais. Como uma versão superada
-- pertence ao MESMO `documento`, ela tem o mesmo `tipo_taxonomia`; e como as duas
-- funções selecionam por `rotulo_norm`, a `chave` só pode diferir em acento,
-- caixa ou pontuação, que `fn_normalizar_texto` remove. Logo o papel calculado
-- sobre a versão superada é necessariamente IGUAL ao da vigente, e o ramo é
-- inalcançável pela porta da versão.
--
-- Tentei escrever o teste e ele passou com o filtro REMOVIDO — que, pela regra do
-- CLAUDE.md ("teste que não pode falhar não prova nada"), é motivo para declarar
-- em vez de fingir cobertura. O filtro fica de propósito, pelo mesmo critério que
-- a 0100 usou: a divergência entre estas duas funções já derrubou o "aplicar em
-- lote" em produção uma vez, e ela volta no instante em que alguém mexer num lado
-- só — inclusive no dia em que `p_unidade` deixar de ser um parâmetro decorativo.
-- Alinhar as duas custa uma linha; descobrir a divergência custou uma rodada.
-- -----------------------------------------------------------------------------
create or replace function fn_papel_do_rotulo_no_caso(
  p_caso_id uuid,
  p_rotulo_norm text,
  p_secao_canonica text
)
returns text
language sql
stable
as $$
  -- marca-0102
  with ocorrencias as (
    select ce.secao_canonica,
           fn_papel_linha(ce.chave, d.tipo_taxonomia, ce.unidade) as papel
    from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
    where d.caso_id = p_caso_id
      and ce.valor_num is not null
      and fn_normalizar_texto(ce.chave) = p_rotulo_norm
      and dv.id = fn_versao_com_extracao(d.id)
  ),
  da_secao as (
    select papel from ocorrencias
    where coalesce(secao_canonica, '') = coalesce(p_secao_canonica, '')
  )
  select coalesce(
    -- 1) o papel dentro da seção pedida — o mesmo que fn_linhas_para_modelagem
    --    mostra, porque o agrupamento é o mesmo.
    (select (array_agg(papel order by fn_papel_prioridade(papel)))[1] from da_secao),
    -- 2) e só se o rótulo não existir naquela seção, o do caso inteiro.
    (select (array_agg(papel order by fn_papel_prioridade(papel)))[1] from ocorrencias)
  );
$$;

comment on function fn_papel_do_rotulo_no_caso(uuid, text, text) is
  'Papel do rótulo DENTRO DA SEÇÃO (0100), com queda para o caso inteiro só quando o rótulo não '
  'existe na seção. Tem de concordar com fn_linhas_para_modelagem — discordância entre as duas é '
  'o defeito que derrubava o "aplicar em lote". 0102: mesmo filtro de versão vigente que a tela.';

grant execute on function fn_papel_do_rotulo_no_caso(uuid, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_sazonalidade_do_caso — a curva não pode somar dois faturamentos do mesmo mês.
--
-- Aqui o estrago da versão superada é pior do que uma contagem inflada. A curva é
-- normalizada (cada mês dividido pelo total do ano), e o documento de
-- faturamento reextraído faria o MESMO mês entrar duas vezes. Se as duas versões
-- concordarem em todos os meses, a curva até sai igual por acidente aritmético;
-- se discordarem em UM mês — que é o motivo de alguém reextrair —, aquele mês
-- ganha peso e todos os outros perdem. E a curva reparte o valor anual das linhas
-- com sazonalidade vinculada: o erro vaza para o Excel entregue, sem nada acusar.
-- -----------------------------------------------------------------------------
create or replace function fn_sazonalidade_do_caso(p_caso_id uuid)
returns table (mes int, fracao numeric, n_observacoes bigint)
language sql
stable
as $$
  -- marca-0102
  with mensal as (
    select fn_mes_do_rotulo(ce.chave) as mes, abs(ce.valor_num) as valor
    from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
    where d.caso_id = p_caso_id
      and d.tipo_taxonomia = 'FATURAMENTO_24M'
      and ce.valor_num is not null
      -- A linha de TOTAL não é um mês. Continua sendo o `fn_mes_do_rotulo` que a
      -- exclui (nenhuma palavra de mês em "TOTAL DO EXERCÍCIO"); este filtro é
      -- REDUNDANTE de propósito, para um rótulo como "Total jan-dez", e está
      -- anotado como redundante para ninguém escrever um teste acreditando estar
      -- provando ele — foi o que aconteceu na primeira versão do teste da 0040.
      and fn_normalizar_texto(ce.chave) not like 'total%'
      -- 0042: e a linha DERIVADA também não é um mês. "Média mensal" não casa
      -- palavra de mês, mas "Ticket médio por pedido 2024" tampouco deveria
      -- entrar numa curva de faturamento se algum dia casar.
      and fn_papel_linha(ce.chave, d.tipo_taxonomia, ce.unidade) <> 'derivado'
      and dv.id = fn_versao_com_extracao(d.id)
  ),
  somado as (
    select mes, sum(valor) as valor, count(*) as n
    from mensal where mes is not null
    group by mes
  ),
  total as (select sum(valor) as t from somado)
  select s.mes,
         case when t.t is null or t.t = 0 then null else s.valor / t.t end as fracao,
         s.n as n_observacoes
  from somado s cross join total t
  -- Só devolve curva COMPLETA: 12 meses ou nada. Curva parcial distribuiria o
  -- ano inteiro nos meses que existem, inflando cada um — pior que não ter curva.
  where (select count(*) from somado) = 12
  order by s.mes;
$$;

comment on function fn_sazonalidade_do_caso(uuid) is
  'Curva de sazonalidade DERIVADA do faturamento mensal do caso (0040), 12 meses ou nada. '
  '0102: só a versão vigente do documento de faturamento — versão superada faria o mesmo mês '
  'entrar duas vezes e deslocaria a curva que reparte o valor anual no Excel.';

grant execute on function fn_sazonalidade_do_caso(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_valores_por_ano — é ela que escreve os números do Excel.
--
-- `fn_linhas_para_modelagem` alimenta a TELA; esta alimenta o ARQUIVO ENTREGUE
-- (`portal/src/lib/export.ts`, abas do modelo institucional). O valor de cada
-- linha por exercício sai daqui, também por maior módulo com sinal — então uma
-- ocorrência de versão superada com módulo maior GANHA da versão corrigida, e o
-- número errado sai no entregável. Das cinco funções desta migration, é a de
-- consequência mais direta para o cliente.
-- -----------------------------------------------------------------------------
create or replace function fn_valores_por_ano(p_caso_id uuid, p_entidade text default null)
returns table (rotulo_norm text, secao_canonica text, ano int, valor numeric, n_ocorrencias bigint)
language sql
stable
as $$
  -- marca-0102
  with ocorrencias as (
    select
      fn_normalizar_texto(ce.chave) as rotulo_norm,
      ce.secao_canonica,
      fn_ano_da_coluna(ce.periodo_coluna, p.referencia) as ano,
      ce.valor_num as valor
    from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
    left join periodo p on p.id = d.periodo_id
    left join entidade e on e.id = d.entidade_id
    where d.caso_id = p_caso_id
      and ce.valor_num is not null
      and (p_entidade is null
           or fn_mesma_entidade(coalesce(ce.entidade_coluna, e.razao_social, ''), p_entidade))
      and dv.id = fn_versao_com_extracao(d.id)
  )
  select o.rotulo_norm, o.secao_canonica, o.ano,
         -- Maior módulo COM SINAL, igual à 0042. Duas grafias da mesma conta no
         -- mesmo exercício não somam: representam o mesmo saldo.
         (array_agg(o.valor order by abs(o.valor) desc))[1] as valor,
         count(*) as n_ocorrencias
  from ocorrencias o
  where o.ano is not null
  group by o.rotulo_norm, o.secao_canonica, o.ano
  order by o.rotulo_norm, o.ano;
$$;

comment on function fn_valores_por_ano(uuid, text) is
  'O valor de cada linha lógica por exercício — é a fonte dos números do .xlsx entregue. O filtro '
  'de entidade não é opcional (0044). 0102: só a versão vigente de cada documento, senão uma '
  'ocorrência superada de módulo maior vence a corrigida e sai no entregável.';

grant execute on function fn_valores_por_ano(uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_linhas_do_tipo — o checklist conta linha, e contava linha repetida.
--
-- Usada pela completude (0036: "chegou vazio não cumpre item"). Sem filtro de
-- versão, um documento reextraído fazia o item parecer MAIS cumprido do que
-- está — a contagem dobra sem que uma linha nova de conteúdo tenha entrado.
-- Completude inflada é a que faz o Portão 2 liberar o que não deveria.
-- -----------------------------------------------------------------------------
create or replace function fn_linhas_do_tipo(p_caso_id uuid, p_codigo text)
returns bigint
language sql
stable
as $$
  -- marca-0102
  select count(ce.id)
  from documento d
  join documento_versao dv on dv.documento_id = d.id
  join campo_extraido ce on ce.documento_versao_id = dv.id
  where d.caso_id = p_caso_id
    and d.tipo_taxonomia = p_codigo
    and dv.id = fn_versao_com_extracao(d.id);
$$;

comment on function fn_linhas_do_tipo(uuid, text) is
  'Quantas linhas extraídas o caso tem de um tipo de documento (insumo da completude, 0036). '
  '0102: só a versão vigente — reextração dobrava a contagem e inflava a completude.';

grant execute on function fn_linhas_do_tipo(uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_diagnostico_modelagem — o instrumento que faltava para NÃO adivinhar.
--
-- POR QUE ISTO É PARTE DA CORREÇÃO, e não um extra. O motivo pelo qual esta
-- rodada existiu é que ninguém conseguia responder, olhando a tela, à pergunta
-- "a correção está no banco?". A tela em produção mostrava o mesmo sintoma antes
-- e depois do merge do PR, porque **merge não é apply**: o código entra no
-- GitHub, e a migration só passa a existir quando o dono a executa no Supabase.
-- Sem um jeito de checar, "já apliquei" e "ainda não apliquei" têm exatamente a
-- mesma aparência na tela — e foi nessa ambiguidade que a rodada inteira se
-- perdeu.
--
-- Esta função responde em UMA chamada, do SQL Editor do Supabase:
--
--     select jsonb_pretty(fn_diagnostico_modelagem('<caso_id>'));
--
--   • `correcoes_instaladas` — se as funções em pé no banco são as da 0101/0102,
--     detectado pela marca no corpo. É a resposta direta a "apliquei ou não";
--   • `ocorrencias_superadas` — quantas ocorrências vinham de versão superada,
--     isto é, o tamanho do estrago que a 0102 acabou de tirar do caminho;
--   • `linhas` / `linhas_projetaveis` — o que a tela deve mostrar, para comparar
--     com o que ela está mostrando.
--
-- Não mede tempo de propósito: cronômetro dentro de função `stable` seria número
-- sem teto de referência, e o teto que importa (`statement_timeout`) é o próprio
-- Postgres que aplica. Quem prova o tempo é `db/test/modelagem_v35.test.sql`.
-- -----------------------------------------------------------------------------
create or replace function fn_diagnostico_modelagem(p_caso_id uuid)
returns jsonb
language sql
stable
as $$
  -- marca-0102
  with instalada as (
    select jsonb_object_agg(p.proname, pg_get_functiondef(p.oid) like '%marca-0102%') as j
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('fn_versao_com_extracao', 'fn_linhas_para_modelagem',
                        'fn_papel_do_rotulo_no_caso', 'fn_sazonalidade_do_caso',
                        'fn_valores_por_ano', 'fn_linhas_do_tipo')
  ),
  ocorrencia as (
    select dv.id = fn_versao_com_extracao(d.id) as vigente
    from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
    where d.caso_id = p_caso_id and ce.valor_num is not null
  ),
  linha as (select papel from fn_linhas_para_modelagem(p_caso_id))
  select jsonb_build_object(
    'caso_id', p_caso_id,
    'correcoes_instaladas', (select j from instalada),
    'conferir_modelagem_e_0101',
      (select pg_get_functiondef(p.oid) like '%with linhas as%'
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'fn_conferir_modelagem' limit 1),
    'documentos', (select count(*) from documento where caso_id = p_caso_id),
    'documentos_com_versao_superada', (
      select count(*) from documento d
      where d.caso_id = p_caso_id
        and (select count(*) from documento_versao dv
             where dv.documento_id = d.id
               and exists (select 1 from campo_extraido ce where ce.documento_versao_id = dv.id)) > 1),
    'ocorrencias_total', (select count(*) from ocorrencia),
    'ocorrencias_vigentes', (select count(*) from ocorrencia where vigente),
    'ocorrencias_superadas', (select count(*) from ocorrencia where not vigente),
    'linhas', (select count(*) from linha),
    'linhas_projetaveis', (select count(*) from linha where papel = 'conta'),
    'linhas_por_papel', (select jsonb_object_agg(papel, n)
                         from (select papel, count(*) n from linha group by papel) x)
  );
$$;

comment on function fn_diagnostico_modelagem(uuid) is
  'Diagnóstico da tela de Modelagem de um caso, para rodar no SQL Editor: se as correções da '
  '0101/0102 estão INSTALADAS no banco (merge não é apply), quantas ocorrências vinham de versão '
  'superada, e quantas linhas a tela deve mostrar. Existe porque "já apliquei" e "ainda não '
  'apliquei" tinham a mesma aparência na tela.';

grant execute on function fn_diagnostico_modelagem(uuid) to authenticated;

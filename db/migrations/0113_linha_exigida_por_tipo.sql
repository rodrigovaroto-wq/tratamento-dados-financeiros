-- =============================================================================
-- Migration 0113 — A LINHA EXIGIDA por tipo de documento vira DADO, e o
-- Portão 1 passa a cobrá-la pelo nome
--
-- (Nasceu como "0108" na entrega aprovada; 0108–0110 entraram na main antes
-- desta, e número não se reaproveita — db/README.md, faixas de numeração.)
--
-- O PROBLEMA. Quando uma linha de que uma checagem depende NÃO EXISTE no
-- documento — o balanço veio sem a linha de caixa, a DRE sem receita bruta —
-- a reconciliação sai como `precondicao_nao_satisfeita`. A pendência até
-- existe (0009 grava uma), mas ela é MOLE: severidade `importante`,
-- sobrepujável, então não trava o Portão 2; o despachante
-- (`fn_reconciliar_por_documento`, 0022/0105) tenta a checagem período a
-- período e publica só o ÚLTIMO resultado; e só as ~10 linhas que alguma das
-- cinco checagens por acaso cruza têm dono. Uma linha exigida que nenhuma
-- reconciliação toca não é verificada NUNCA. O efeito real: o documento
-- "passou", o book sai sem a linha, e ninguém viu — o caso segue como se
-- tivesse conferido.
--
-- A ENTREGA que isto materializa (aprovada pelo dono) define, para cada um dos
-- oito tipos do Kit Básico, quais linhas financeiras precisam existir para o
-- documento ser UTILIZÁVEL. Hoje essa exigência mora em dois lugares ruins:
-- hardcoded nos arrays inclui/exclui dentro dos corpos das funções de
-- reconciliação (0009/0023/0031/0034), e em lugar nenhum para os tipos que
-- nenhuma checagem lê (MUTUOS, FAT_INTRAGRUPO, CONTRATO_SOCIAL).
--
-- A INVERSÃO é a mesma da 0038 (premissas): a exigência deixa de ser corpo de
-- função e vira LINHA numa tabela, filha da taxonomia. Acrescentar "o mapa de
-- dívida precisa da taxa por contrato" passa a ser um INSERT, não uma função
-- nova.
--
-- DUAS TABELAS, e por que são duas:
--   • `taxonomia_linha_exigida`      O QUE precisa existir (uma exigência por
--                                    conceito: "Ativo Total", "Caixa e equiv.")
--   • `taxonomia_linha_localizador`  COMO se procura — porque o código real
--     procura em CASCATA: o caixa do BP tem SETE tentativas (0031, quatro por
--     rótulo, uma alargada, duas por seção), o Ativo Total tem três (0034:
--     rótulo com "total", total estrutural sem a palavra "total", soma da
--     seção). Uma exigência satisfaz-se quando QUALQUER localizador casa.
--     Achatar isso numa linha só teria reintroduzido o defeito da 0034: acusar
--     ausência de "TOTAL DO ATIVO" num balanço cujo rótulo é "ATIVO".
--
-- O FORMATO do localizador é o de `fn_valor_conceito` (0009): termos_inclui /
-- termos_exclui, casados por substring do rótulo normalizado. De propósito —
-- é A definição de "como se localiza uma linha" neste banco, e um segundo
-- localizador divergiria em silêncio (mesma razão pela qual a 0103 manteve UMA
-- tokenização). `contra` diz onde casar: 'chave' (o normal), 'secao' (espelha
-- fn_valor_conceito_secao, 0031) ou 'estrutural' (espelha fn_rotulo_estrutural,
-- 0034 — igualdade de tokens, não substring).
--
-- ORIGEM: 'codigo' | 'proposta'. Quem revisar precisa distinguir, SEM abrir o
-- documento da entrega, o que é fato verificado no código de hoje (os termos
-- de 'codigo' são cópia literal dos arrays das reconciliações vigentes) do que
-- é proposta da análise (nenhuma checagem lê hoje). Nada com origem 'proposta'
-- muda comportamento de checagem existente.
--
-- DEPENDE_DE: fato levantado, não política — QUAL reconciliação ou indicador
-- deixa de funcionar sem a linha. É o insumo para o dono decidir severidade
-- linha a linha depois, com base em algo.
--
-- POLÍTICA (severidade / sobrepujavel): NULL até o dono decidir. Enquanto
-- NULL, o Portão 1 usa o MESMO peso que a ausência já tem hoje via
-- `precondicao_nao_satisfeita` — 'importante', sobrepujável. Esta migration
-- torna a ausência VISÍVEL e NOMEADA; não endurece portão nenhum sozinha.
-- `pronto_para_revisao` também não muda: incluir linha exigida nele é decisão
-- de produto, não efeito colateral.
--
-- ONDE O PORTÃO 1 LÊ: `fn_recomputar_completude` (reemitida, corpo da 0036)
-- ganha o passo (2b), entre "chegou vazio" (0036) e o checklist: para cada
-- tipo PRESENTE e COM linhas, cada exigência ativa não satisfeita vira
-- pendência `linha_exigida_ausente` que NOMEIA a linha (doutrina da 0033) e
-- publica o depende_de. Como a 0036 já ligou
-- `fn_registrar_campos_extraidos → fn_recomputar_completude`, isto roda
-- sozinho depois de CADA extração — a ausência é declarada ANTES de degradar
-- uma reconciliação em silêncio. Quando uma versão nova traz a linha, a
-- pendência resolve sozinha ('sistema:extracao'), como as da 0036.
--
-- GRANULARIDADE v1, dita às claras: a exigência é do TIPO no caso — satisfeita
-- se QUALQUER documento do tipo (versão vigente, 0102) tem a linha. Dois
-- balanços no caso, um com caixa e um sem: não acusa. Refinar por
-- entidade/documento é evolução com dado na mão, não chute agora.
--
-- DUPLICAÇÃO ASSUMIDA: o seed de origem 'codigo' COPIA termos que continuam
-- vivos no corpo das reconciliações (0023/0031/0034) — dois lugares para a
-- mesma verdade, exatamente o que a 0103 desfez para a tokenização. Fica assim
-- MESMO, por escopo: a convergência (as reconciliações passarem a LER os
-- termos daqui) mexe em cinco funções auditadas em produção e é evolução fora
-- desta migration. Até lá, quem mudar termo de reconciliação atualiza o seed
-- junto — o aviso está repetido na seção do seed.
-- =============================================================================

alter type pendencia_tipo add value if not exists 'linha_exigida_ausente';

-- -----------------------------------------------------------------------------
-- O QUE precisa existir. Uma linha por (tipo, conceito).
-- -----------------------------------------------------------------------------
create table if not exists taxonomia_linha_exigida (
  id             uuid primary key default gen_random_uuid(),
  tipo_taxonomia text not null references taxonomia_tipo_documento(codigo),
  conceito       text not null,
  rotulo         text not null,
  checagem       text not null check (checagem in ('linha_por_termos', 'secao_presente', 'serie_mensal')),
  secao_canonica text,
  origem         text not null check (origem in ('codigo', 'proposta')),
  depende_de     text[] not null default '{}',
  descricao      text not null,
  severidade     text check (severidade in ('bloqueante', 'importante')),
  sobrepujavel   boolean,
  ativo          boolean not null default true,   -- deprecar em vez de apagar (padrão da taxonomia)
  versao         int not null default 1,
  unique (tipo_taxonomia, conceito),
  check (checagem <> 'secao_presente' or secao_canonica is not null)
);

comment on table taxonomia_linha_exigida is
  'Linhas/seções que um tipo de documento PRECISA ter para ser utilizável (entrega aprovada, '
  'sessão de 13/08/2026). Filha da taxonomia: a taxonomia diz QUAIS tipos são obrigatórios; esta '
  'diz O QUE cada tipo precisa conter. Lida pelo Portão 1 (fn_recomputar_completude, passo 2b).';
comment on column taxonomia_linha_exigida.checagem is
  'linha_por_termos = existe linha casando algum localizador; secao_presente = existe linha com a '
  'secao_canonica; serie_mensal = existe linha cujo rótulo tem mês (fn_mes_do_rotulo, 0042).';
comment on column taxonomia_linha_exigida.origem is
  '''codigo'' = a exigência JÁ está hardcoded numa reconciliação vigente (termos copiados '
  'literalmente de 0009/0023/0031/0034); ''proposta'' = saiu da análise do estagiário e NENHUMA '
  'checagem a lê hoje. Distinção para o revisor ver a diferença sem abrir o documento da entrega.';
comment on column taxonomia_linha_exigida.depende_de is
  'FATO, não política: qual reconciliação/indicador deixa de funcionar sem esta linha. Insumo para '
  'o dono definir severidade linha a linha.';
comment on column taxonomia_linha_exigida.severidade is
  'DECISÃO DO DONO, por linha. NULL = ainda não decidida; o Portão 1 usa então ''importante'' — o '
  'mesmo peso que a ausência já tem hoje via precondicao_nao_satisfeita. A migration não endurece '
  'nada sozinha.';
comment on column taxonomia_linha_exigida.sobrepujavel is
  'DECISÃO DO DONO, por linha. NULL = ainda não decidida; o Portão 1 usa então TRUE (sobrepujável, '
  'como a precondicao_nao_satisfeita de hoje).';

alter table taxonomia_linha_exigida enable row level security;
create policy taxonomia_linha_exigida_read on taxonomia_linha_exigida
  for select to authenticated using (true);
-- Escrita reservada (seed/admin via service_role), como taxonomia_tipo_documento:
-- definir exigência e política é ação de banco, não de tela.

-- -----------------------------------------------------------------------------
-- COMO se procura. Cascata de tentativas por exigência, na ordem do código.
-- -----------------------------------------------------------------------------
create table if not exists taxonomia_linha_localizador (
  id            uuid primary key default gen_random_uuid(),
  exigencia_id  uuid not null references taxonomia_linha_exigida(id) on delete cascade,
  ordem         int not null,
  contra        text not null default 'chave' check (contra in ('chave', 'secao', 'estrutural')),
  termos_inclui text[] not null,
  termos_exclui text[] not null default '{}',
  unique (exigencia_id, ordem)
);

comment on table taxonomia_linha_localizador is
  'Tentativas de localização de uma exigência, em cascata (a ordem espelha o código: o caixa do BP '
  'tem 7 tentativas na 0031). Formato de fn_valor_conceito (0009): inclui/exclui por substring do '
  'texto normalizado. A exigência satisfaz-se quando QUALQUER localizador casa.';
comment on column taxonomia_linha_localizador.contra is
  '''chave'' = casa contra ce.chave (fn_valor_conceito); ''secao'' = contra ce.secao '
  '(fn_valor_conceito_secao, 0031); ''estrutural'' = fn_rotulo_estrutural(ce.chave, termos_inclui) '
  '(0034 — igualdade de tokens estruturais; termos_exclui não se aplica).';

alter table taxonomia_linha_localizador enable row level security;
create policy taxonomia_linha_localizador_read on taxonomia_linha_localizador
  for select to authenticated using (true);

-- -----------------------------------------------------------------------------
-- fn_exigencias_do_caso — cada exigência aplicável ao caso, com satisfeita s/n.
--
-- Aplicável = o tipo tem documento no caso E alguma linha extraída
-- (fn_linhas_do_tipo > 0). De propósito: tipo AUSENTE já é `item_faltante`
-- (0006) e tipo presente com ZERO linhas já é `item_sem_conteudo` (0036) —
-- cobrar linha exigida por cima seria a dupla cobrança que a 0023 desfez e a
-- 0105 evitou de novo. O casamento lê a versão VIGENTE de cada documento
-- (fn_versao_com_extracao, 0102): ocorrência de versão superada não conta.
--
-- Separada da completude porque é ela que a TELA vai listar (o painel do caso
-- quer mostrar exigido × encontrado, não só a pendência), e porque assim o
-- teste confere o CRITÉRIO sem passar pela máquina de pendência — mesmo padrão
-- de fn_pares_duplicados_do_caso (0105).
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
  satisfeita     boolean
)
language sql
stable
as $$
  with tipos_com_conteudo as (
    select distinct d.tipo_taxonomia
    from documento d
    where d.caso_id = p_caso_id
      and fn_linhas_do_tipo(p_caso_id, d.tipo_taxonomia) > 0
  ),
  campos as (
    select d.tipo_taxonomia, ce.chave, ce.secao, ce.secao_canonica
    from documento d
    join campo_extraido ce on ce.documento_versao_id = fn_versao_com_extracao(d.id)
    where d.caso_id = p_caso_id
      and ce.valor_num is not null
  )
  select e.id, e.tipo_taxonomia, e.conceito, e.rotulo, e.origem, e.depende_de,
         e.severidade, e.sobrepujavel, e.descricao,
         case e.checagem
           when 'secao_presente' then exists (
             select 1 from campos c
             where c.tipo_taxonomia = e.tipo_taxonomia
               and c.secao_canonica = e.secao_canonica)
           when 'serie_mensal' then exists (
             select 1 from campos c
             where c.tipo_taxonomia = e.tipo_taxonomia
               and fn_mes_do_rotulo(c.chave) is not null)
           else exists (
             select 1
             from taxonomia_linha_localizador l, campos c
             where l.exigencia_id = e.id
               and c.tipo_taxonomia = e.tipo_taxonomia
               and case
                 when l.contra = 'estrutural' then fn_rotulo_estrutural(c.chave, l.termos_inclui)
                 else
                   not exists (
                     select 1 from unnest(l.termos_inclui) t
                     where fn_normalizar_texto(case when l.contra = 'secao'
                                               then coalesce(c.secao, '') else c.chave end)
                       not like '%' || fn_normalizar_texto(t) || '%')
                   and not exists (
                     select 1 from unnest(l.termos_exclui) t
                     where fn_normalizar_texto(case when l.contra = 'secao'
                                               then coalesce(c.secao, '') else c.chave end)
                       like '%' || fn_normalizar_texto(t) || '%')
               end)
         end as satisfeita
  from taxonomia_linha_exigida e
  join tipos_com_conteudo t on t.tipo_taxonomia = e.tipo_taxonomia
  where e.ativo;
$$;

comment on function fn_exigencias_do_caso(uuid) is
  'Exigências de linha aplicáveis ao caso (tipos presentes COM conteúdo), com satisfeita s/n. '
  'Casa contra a versão VIGENTE (0102), no formato de fn_valor_conceito (0009). Alimenta o passo '
  '2b de fn_recomputar_completude e a tela do caso.';

grant execute on function fn_exigencias_do_caso(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_recomputar_completude — corpo da 0036 com UM passo novo, o (2b).
-- Reemitida inteira (padrão do repositório): a definição vigente fica legível
-- num arquivo só. Passos (1), (2), (3) e (4) são os da 0036, intactos.
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
  -- 0113: passo (2b)
  v_ex record;
  v_motivos_ausentes text[] := '{}';
  v_linhas_ausentes jsonb := '[]'::jsonb;
begin
  -- ----- (1) obrigatório sem NENHUM documento: igual à 0006 ------------------
  select array_agg(t.codigo order by t.codigo) into v_faltantes
  from taxonomia_tipo_documento t
  where t.obrigatoriedade = 'obrigatorio'
    and not exists (
      select 1 from documento d
      where d.caso_id = p_caso_id and d.tipo_taxonomia = t.codigo
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
                       'é validade (docs/07), e um obrigatório sem conteúdo não passa o Portão 2.',
                       v_cod),
                'completude:sem_conteudo:'||v_cod);
    end if;
  end loop;

  -- ----- (2b) 0113: tipo presente COM conteúdo, mas sem uma LINHA exigida ----
  -- É o buraco entre a 0036 e as reconciliações: o documento chegou e rendeu
  -- linhas, só que NÃO as linhas de que o resto do sistema depende. Até aqui,
  -- isso só aparecia como `precondicao_nao_satisfeita` — mole, sobrepujável e
  -- publicada por período — e SÓ para as linhas que alguma das cinco checagens
  -- cruza. Agora a ausência é declarada na completude, NOMEANDO a linha (0033)
  -- e o que deixa de funcionar sem ela (depende_de).
  --
  -- Política por linha é do dono: severidade/sobrepujavel NULL caem em
  -- 'importante'/true — o peso que a ausência já tem hoje. Pendência existente
  -- é ATUALIZADA (descrição e política), como a 0009 faz, para uma decisão
  -- nova do dono valer sem esperar a pendência reabrir.
  for v_ex in
    select * from fn_exigencias_do_caso(p_caso_id) x where not x.satisfeita
  loop
    v_motivos_ausentes := v_motivos_ausentes
      || ('completude:linha_exigida:' || v_ex.tipo_taxonomia || ':' || v_ex.conceito);
    v_linhas_ausentes := v_linhas_ausentes || jsonb_build_object(
      'tipo', v_ex.tipo_taxonomia, 'conceito', v_ex.conceito,
      'rotulo', v_ex.rotulo, 'origem', v_ex.origem);

    select id into v_pend_id from pendencia p
    where p.caso_id = p_caso_id and p.tipo = 'linha_exigida_ausente'
      and p.estado <> 'resolvida'
      and p.motivo = 'completude:linha_exigida:' || v_ex.tipo_taxonomia || ':' || v_ex.conceito
    limit 1;

    if v_pend_id is null then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, motivo)
        values (p_caso_id, 'completude', 'linha_exigida_ausente',
                coalesce(v_ex.severidade, 'importante')::pendencia_severidade,
                coalesce(v_ex.sobrepujavel, true),
                format('O tipo %s chegou e rendeu linhas, mas a linha exigida "%s" não foi localizada '
                       'na versão vigente de nenhum documento do tipo. Sem ela: %s.%s Conferir se o '
                       'documento traz a linha com outro rótulo (e corrigir na revisão) ou reenviar o '
                       'arquivo completo.',
                       v_ex.tipo_taxonomia, v_ex.rotulo,
                       array_to_string(v_ex.depende_de, '; '),
                       case when v_ex.origem = 'proposta'
                            then ' (Exigência PROPOSTA na análise — nenhuma checagem automática a lê hoje.)'
                            else '' end),
                'completude:linha_exigida:' || v_ex.tipo_taxonomia || ':' || v_ex.conceito);
    else
      update pendencia set
        severidade   = coalesce(v_ex.severidade, 'importante')::pendencia_severidade,
        sobrepujavel = coalesce(v_ex.sobrepujavel, true)
      where id = v_pend_id;
    end if;
  end loop;

  -- A linha apareceu (versão nova, revisão que corrigiu o rótulo) — resolve
  -- sozinha, como as da 0036. Vale também para exigência desativada pelo dono.
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
    -- 0113: as linhas exigidas que faltam saem no payload (nó do n8n e portal
    -- mostram sem refazer a consulta). `pronto_para_revisao` NÃO muda:
    -- endurecê-lo com linha exigida é decisão de produto do dono, não efeito
    -- colateral desta migration.
    'linhas_exigidas_ausentes', v_linhas_ausentes,
    'pronto_para_revisao',
      array_length(v_faltantes,1) is null and array_length(v_sem_conteudo,1) is null,
    'status', v_novo_status
  );
end;
$$;

comment on function fn_recomputar_completude(uuid) is
  'Portão 1 (chegada) + 0036 (recebido sem conteúdo) + 0113 (passo 2b: tipo com conteúdo mas sem '
  'uma LINHA exigida — pendência linha_exigida_ausente nomeando a linha e o depende_de; severidade '
  'por linha é do dono, default importante/sobrepujável). `portao1_ok` segue significando "chegou '
  'tudo"; `pronto_para_revisao` segue chegou tudo E tem conteúdo.';

-- =============================================================================
-- SEED — a entrega, linha a linha.
--
-- origem='codigo': termos copiados LITERALMENTE das reconciliações vigentes
-- (a reemissão mais recente de cada uma: 0034 para Ativo×Passivo+PL, 0031 para
-- o caixa, 0023 para receita e despesa financeira). Se um dia a reconciliação
-- mudar de termos, este seed é o segundo lugar a atualizar — e o teste de
-- linha exigida é o que vai acusar a divergência de comportamento.
--
-- origem='proposta': MUTUOS, FAT_INTRAGRUPO e CONTRATO_SOCIAL — nenhuma
-- checagem lê esses tipos hoje; as linhas saíram da análise da entrega e estão
-- aqui para o dono validar (e então promover, ajustar ou desativar).
--
-- `on conflict do nothing`: idempotente, padrão do seed 0002/0024.
-- =============================================================================

-- ---- BALANCO e COMBINADO: as mesmas três exigências, porque o despachante
-- ---- (0022/0105) roda as MESMAS checagens de balanço nos dois tipos. --------
insert into taxonomia_linha_exigida
  (tipo_taxonomia, conceito, rotulo, checagem, origem, depende_de, descricao)
select t.tipo, x.conceito, x.rotulo, 'linha_por_termos', 'codigo', x.depende, x.descricao
from (values ('BALANCO'), ('COMBINADO')) t(tipo)
cross join (values
  ('ativo_total', 'Ativo Total',
   array['reconciliacao:ativo_passivo_pl (0009/0034)']::text[],
   'Lado esquerdo de Ativo = Passivo + PL. Sem esta linha (nem total estrutural, nem seção ATIVO '
   'somável), a checagem sai precondicao_nao_satisfeita.'),
  ('passivo_mais_pl', 'Passivo + Patrimônio Líquido (total)',
   array['reconciliacao:ativo_passivo_pl (0009/0034)']::text[],
   'Lado direito de Ativo = Passivo + PL. Quando a linha combinada falta, o código exige Passivo '
   'total E PL total JUNTOS (0034); aqui qualquer localizador satisfaz — a exigência acusa a '
   'ausência total, o par fino continua com a reconciliação.'),
  ('caixa_e_equivalentes', 'Caixa e equivalentes (BP)',
   array['reconciliacao:caixa_bp_fluxo (0009/0031)']::text[],
   'Lado do balanço em Caixa BP = saldo final do Fluxo. Cascata de 7 tentativas da 0031 — rótulo, '
   'rótulo alargado e seção.')
) x(conceito, rotulo, depende, descricao)
on conflict (tipo_taxonomia, conceito) do nothing;

insert into taxonomia_linha_localizador (exigencia_id, ordem, contra, termos_inclui, termos_exclui)
select e.id, x.ordem, x.contra, x.inclui, x.exclui
from taxonomia_linha_exigida e
cross join (values
  (1, 'chave',      array['ativo','total']::text[], array['circulante','nao circulante']::text[]),
  (2, 'estrutural', array['ativo']::text[],         '{}'::text[]),
  (3, 'secao',      array['ativo']::text[],         array['passivo','patrimonio']::text[])
) x(ordem, contra, inclui, exclui)
where e.tipo_taxonomia in ('BALANCO','COMBINADO') and e.conceito = 'ativo_total'
on conflict (exigencia_id, ordem) do nothing;

insert into taxonomia_linha_localizador (exigencia_id, ordem, contra, termos_inclui, termos_exclui)
select e.id, x.ordem, x.contra, x.inclui, x.exclui
from taxonomia_linha_exigida e
cross join (values
  (1, 'chave',      array['passivo','patrimonio','total']::text[], array['circulante']::text[]),
  (2, 'estrutural', array['passivo','patrimonio']::text[],         '{}'::text[]),
  (3, 'chave',      array['passivo','total']::text[],              array['patrimonio','circulante','nao circulante']::text[]),
  (4, 'chave',      array['patrimonio','liquido','total']::text[], array['circulante']::text[])
) x(ordem, contra, inclui, exclui)
where e.tipo_taxonomia in ('BALANCO','COMBINADO') and e.conceito = 'passivo_mais_pl'
on conflict (exigencia_id, ordem) do nothing;

insert into taxonomia_linha_localizador (exigencia_id, ordem, contra, termos_inclui, termos_exclui)
select e.id, x.ordem, x.contra, x.inclui, x.exclui
from taxonomia_linha_exigida e
cross join (values
  (1, 'chave', array['caixa','equivalentes']::text[], array['circulante','fluxo','inicio','inicial']::text[]),
  (2, 'chave', array['disponibilidades']::text[],     array['circulante']::text[]),
  (3, 'chave', array['disponivel']::text[],           array['circulante']::text[]),
  (4, 'chave', array['caixa','bancos']::text[],       array['circulante']::text[]),
  (5, 'chave', array['caixa']::text[],                array['circulante','fluxo','inicio','inicial','equivalente']::text[]),
  (6, 'secao', array['disponivel']::text[],           array['circulante']::text[]),
  (7, 'secao', array['caixa']::text[],                array['circulante','fluxo']::text[])
) x(ordem, contra, inclui, exclui)
where e.tipo_taxonomia in ('BALANCO','COMBINADO') and e.conceito = 'caixa_e_equivalentes'
on conflict (exigencia_id, ordem) do nothing;

-- ---- FLUXO_CAIXA ------------------------------------------------------------
insert into taxonomia_linha_exigida
  (tipo_taxonomia, conceito, rotulo, checagem, origem, depende_de, descricao)
values
  ('FLUXO_CAIXA', 'saldo_final_de_caixa', 'Saldo final de caixa (DFC)', 'linha_por_termos', 'codigo',
   array['reconciliacao:caixa_bp_fluxo (0009/0031)'],
   'Lado do fluxo em Caixa BP = saldo final do Fluxo. Cascata da 0031: saldo final, caixa final, '
   'caixa no fim do período.')
on conflict (tipo_taxonomia, conceito) do nothing;

insert into taxonomia_linha_localizador (exigencia_id, ordem, contra, termos_inclui, termos_exclui)
select e.id, x.ordem, 'chave', x.inclui, x.exclui
from taxonomia_linha_exigida e
cross join (values
  (1, array['saldo','final']::text[], array['inicial','inicio']::text[]),
  (2, array['caixa','final']::text[], array['inicial','inicio']::text[]),
  (3, array['caixa','fim']::text[],   array['inicial','inicio']::text[])
) x(ordem, inclui, exclui)
where e.tipo_taxonomia = 'FLUXO_CAIXA' and e.conceito = 'saldo_final_de_caixa'
on conflict (exigencia_id, ordem) do nothing;

-- ---- DRE --------------------------------------------------------------------
insert into taxonomia_linha_exigida
  (tipo_taxonomia, conceito, rotulo, checagem, origem, depende_de, descricao)
values
  ('DRE', 'receita_bruta', 'Receita Bruta', 'linha_por_termos', 'codigo',
   array['reconciliacao:receita_dre_vs_faturamento (0015/0023)'],
   'Lado da DRE em Receita Bruta × soma dos meses de faturamento. O código também aceita a linha '
   'como cabeçalho sem valor somando a seção (0023) — daí o localizador por seção.'),
  ('DRE', 'despesa_financeira', 'Despesa Financeira', 'linha_por_termos', 'codigo',
   array['reconciliacao:despfin_dre_vs_divida (0015/0023)'],
   'Lado da DRE em Despesa Financeira × juros do mapa de dívida. Fallback do código: juros e '
   'encargos (0023).')
on conflict (tipo_taxonomia, conceito) do nothing;

insert into taxonomia_linha_localizador (exigencia_id, ordem, contra, termos_inclui, termos_exclui)
select e.id, x.ordem, x.contra, x.inclui, x.exclui
from taxonomia_linha_exigida e
cross join (values
  (1, 'chave', array['receita','bruta']::text[], array['liquida','deducoes','deducao']::text[]),
  (2, 'secao', array['receita','bruta']::text[], array['deducoes','deducao']::text[])
) x(ordem, contra, inclui, exclui)
where e.tipo_taxonomia = 'DRE' and e.conceito = 'receita_bruta'
on conflict (exigencia_id, ordem) do nothing;

insert into taxonomia_linha_localizador (exigencia_id, ordem, contra, termos_inclui, termos_exclui)
select e.id, x.ordem, 'chave', x.inclui, x.exclui
from taxonomia_linha_exigida e
cross join (values
  (1, array['despesa','financeira']::text[], array['receita']::text[]),
  (2, array['juros','encargos']::text[],     array['receita','pagos']::text[])
) x(ordem, inclui, exclui)
where e.tipo_taxonomia = 'DRE' and e.conceito = 'despesa_financeira'
on conflict (exigencia_id, ordem) do nothing;

-- ---- FATURAMENTO_24M --------------------------------------------------------
-- Não é termo: é ESTRUTURA. A reconciliação de receita exige linhas com MÊS
-- (fn_mes_do_rotulo — "o faturamento não traz o mês por linha" é precondição
-- não satisfeita na 0023), e a sazonalidade do caso (0040) e o papel
-- serie_mensal (0042) dependem da mesma estrutura. Por isso origem 'codigo',
-- ainda que não estivesse na lista de sete da entrega: é fato do código.
insert into taxonomia_linha_exigida
  (tipo_taxonomia, conceito, rotulo, checagem, origem, depende_de, descricao)
values
  ('FATURAMENTO_24M', 'serie_mensal_de_faturamento', 'Série mensal de faturamento',
   'serie_mensal', 'codigo',
   array['reconciliacao:receita_dre_vs_faturamento (0023)',
         'modelagem:sazonalidade_do_caso (0040)',
         'modelagem:papel serie_mensal (0042)'],
   'Pelo menos uma linha com mês reconhecível no rótulo (fn_mes_do_rotulo). Sem isso, a '
   'reconciliação de receita não casa nenhum ano e a curva de sazonalidade fica sem insumo.')
on conflict (tipo_taxonomia, conceito) do nothing;

-- ---- MAPA_DIVIDA (fora do Kit Básico; entra porque a exigência está no
-- ---- código — é o outro lado da checagem de despesa financeira) -------------
insert into taxonomia_linha_exigida
  (tipo_taxonomia, conceito, rotulo, checagem, origem, depende_de, descricao)
values
  ('MAPA_DIVIDA', 'juros_por_contrato', 'Juros/encargos por contrato', 'linha_por_termos', 'codigo',
   array['reconciliacao:despfin_dre_vs_divida (0023)'],
   'Lado do mapa em Despesa Financeira × juros: o código soma linhas com "juros" ou "encargos" '
   'excluindo totais (0023).')
on conflict (tipo_taxonomia, conceito) do nothing;

insert into taxonomia_linha_localizador (exigencia_id, ordem, contra, termos_inclui, termos_exclui)
select e.id, x.ordem, 'chave', x.inclui, x.exclui
from taxonomia_linha_exigida e
cross join (values
  (1, array['juros']::text[],    array['total']::text[]),
  (2, array['encargos']::text[], array['total']::text[])
) x(ordem, inclui, exclui)
where e.tipo_taxonomia = 'MAPA_DIVIDA' and e.conceito = 'juros_por_contrato'
on conflict (exigencia_id, ordem) do nothing;

-- ---- PROPOSTAS (nenhuma checagem lê esses três tipos hoje) ------------------
-- REDUÇÃO DECLARADA: a entrega aprovada especifica MAIS do que esta tabela
-- consegue exprimir. A forma daqui é "existe linha com valor casando termos";
-- a entrega pede ESTRUTURA (par de contrapartes em MUTUOS, par de entidades
-- por exercício em FAT_INTRAGRUPO) e CAMPOS não numéricos (CONTRATO_SOCIAL).
-- O que está abaixo é o SUBCONJUNTO que cabe na forma — e cada descricao diz
-- o que ficou de fora, para a redução não passar por cobertura.
insert into taxonomia_linha_exigida
  (tipo_taxonomia, conceito, rotulo, checagem, origem, depende_de, descricao)
values
  ('MUTUOS', 'saldo_de_mutuo', 'Saldo de mútuo por contraparte', 'linha_por_termos', 'proposta',
   array['(proposta) espelhamento mutuo a receber x a pagar entre entidades do grupo — '
         'nenhuma checagem lê MUTUOS hoje'],
   'REDUÇÃO da entrega: ela especifica, por operação, mutuante, mutuária, saldo devedor e SENTIDO; '
   'esta tabela só consegue exigir "existe linha de mútuo com valor" — o par de contrapartes fica '
   'de fora. Sem nem essa linha, a posição intragrupo do book sai vazia e um futuro espelhamento '
   '(crédito de A = débito de B) não tem o que cruzar.'),
  ('FAT_INTRAGRUPO', 'faturamento_entre_partes', 'Faturamento entre partes relacionadas',
   'linha_por_termos', 'proposta',
   array['(proposta) cruzamento FAT_INTRAGRUPO x FATURAMENTO_24M / eliminacao intragrupo no '
         'combinado — nenhuma checagem lê FAT_INTRAGRUPO hoje'],
   'REDUÇÃO da entrega: ela especifica, por par de entidades e por exercício, vendedora, compradora '
   'e valor; aqui só "existe linha de faturamento com valor". Sem nem essa linha, a eliminação '
   'intragrupo e a leitura de dependência entre entidades ficam sem insumo.'),
  ('CONTRATO_SOCIAL', 'capital_social', 'Capital social', 'linha_por_termos', 'proposta',
   array['(proposta) conferencia capital social do contrato x linha de capital social do BP '
         '(patrimonio_liquido) — nenhuma checagem lê CONTRATO_SOCIAL hoje'],
   'REDUÇÃO da entrega: ela especifica cinco CAMPOS (razão social, CNPJ, data do registro, '
   'composição societária com percentuais, cláusula de administração) e diz que o documento não '
   'tem linha numérica. Capital social é o ÚNICO desses que cabe na forma linha-com-valor desta '
   'tabela; os outros quatro pedem estrutura de campos, não de linhas. É também o único número do '
   'contrato que cruza com as demonstrações.')
on conflict (tipo_taxonomia, conceito) do nothing;

insert into taxonomia_linha_localizador (exigencia_id, ordem, contra, termos_inclui, termos_exclui)
select e.id, 1, 'chave', x.inclui, x.exclui
from taxonomia_linha_exigida e
join (values
  ('MUTUOS',          'saldo_de_mutuo',           array['mutuo']::text[],           array['total']::text[]),
  ('FAT_INTRAGRUPO',  'faturamento_entre_partes', array['faturamento']::text[],     array['total']::text[]),
  ('CONTRATO_SOCIAL', 'capital_social',           array['capital','social']::text[], '{}'::text[])
) x(tipo, conceito, inclui, exclui)
  on x.tipo = e.tipo_taxonomia and x.conceito = e.conceito
on conflict (exigencia_id, ordem) do nothing;

-- -----------------------------------------------------------------------------
-- VERIFICAÇÃO EMBUTIDA (padrão 0105). Sem tocar em pendência — o valor novo de
-- `pendencia_tipo` não pode ser usado na MESMA transação em que foi criado, e
-- `supabase db execute` pode rodar o arquivo numa transação só. O comportamento
-- do Portão 1 é coberto em db/test/linha_exigida.test.sql.
-- -----------------------------------------------------------------------------
do $$
declare
  v_n int;
  v_caso uuid := gen_random_uuid();
begin
  select count(*) into v_n from taxonomia_linha_exigida where origem = 'codigo' and ativo;
  if v_n <> 11 then
    raise exception '0113: seed de origem ''codigo'' devia ter 11 exigências (3 BALANCO + 3 COMBINADO + 1 FLUXO + 2 DRE + 1 FAT24M + 1 MAPA), achou %', v_n;
  end if;

  select count(*) into v_n from taxonomia_linha_exigida where origem = 'proposta' and ativo;
  if v_n <> 3 then
    raise exception '0113: seed de origem ''proposta'' devia ter 3 exigências (MUTUOS, FAT_INTRAGRUPO, CONTRATO_SOCIAL), achou %', v_n;
  end if;

  select count(*) into v_n from taxonomia_linha_exigida e
  where e.checagem = 'linha_por_termos'
    and not exists (select 1 from taxonomia_linha_localizador l where l.exigencia_id = e.id);
  if v_n <> 0 then
    raise exception '0113: % exigência(s) por termos SEM localizador — exigência que não se procura não se satisfaz nunca', v_n;
  end if;

  -- Política é do dono: a migration não pode ter definido nenhuma.
  select count(*) into v_n from taxonomia_linha_exigida
  where severidade is not null or sobrepujavel is not null;
  if v_n <> 0 then
    raise exception '0113: % exigência(s) com política definida no seed — severidade/sobrepujavel são decisão do dono, nascem NULL', v_n;
  end if;

  -- Caso sem documento: nenhuma exigência é cobrada (ausência de tipo é
  -- item_faltante da 0006, não linha exigida).
  insert into caso (id, nome, produto) values (v_caso, 'VERIF 0113', 'reestruturacao');
  select count(*) into v_n from fn_exigencias_do_caso(v_caso);
  if v_n <> 0 then
    raise exception '0113: caso sem documento devolveu % exigência(s) — a cobrança é só para tipo presente COM conteúdo', v_n;
  end if;
  delete from caso where id = v_caso;

  raise notice '0113 OK — 11 exigências de código + 3 propostas, todas com localizador, política toda NULL (do dono), caso vazio não cobra nada';
end $$;

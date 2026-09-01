-- =============================================================================
-- Migration 0120 — O banco de perguntas ao cliente vira DADO, e o sistema
-- passa a SUGERIR a pergunta pronta
--
-- (Nasceu para ser "0117" — é o nome da branch. Entre o desenho e a escrita a
-- main ocupou 0117/0118, e a 0119 é o PR #135 renumerado — a linha exigida por
-- entidade, que já está no main. Número não se reaproveita; esta é a 0120.)
--
-- O QUE O DONO APONTOU na revisão da 0113, literal: "de sugestão de pergunta
-- não há nada aqui". O capítulo 10 do onboarding define 36 perguntas a fazer
-- ao cliente DEPOIS que a extração roda, cada uma com quatro campos
-- obrigatórios — pergunta, motivo, risco, impacto — mais dois da análise do
-- estagiário: prioridade (1 crítica … 4 contextual) e gatilho (a condição
-- sobre o dado extraído que faz a pergunta aparecer). Nada disso era sistema:
-- quando o analista clica "Contatar o Cliente" (0109 — o botão só rotula), o
-- que perguntar sai da cabeça dele, não do banco.
--
-- A INVERSÃO é a mesma da 0038 e da 0113: a pergunta vira LINHA numa tabela.
-- E o encaixe com a 0113 é a razão de o desenho ser pequeno: a pendência
-- `linha_exigida_ausente` e a pergunta ao cliente são DUAS FACES DA MESMA
-- AVALIAÇÃO — a pendência é o lado interno (trava, fila), a pergunta é o lado
-- externo (o texto pronto, com motivo/risco/impacto, para o analista enviar).
-- As duas derivam da MESMA função (`fn_exigencias_do_caso`), então nunca
-- divergem.
--
-- ESCOPO v1, DECLARADO: das 36 perguntas da entrega, **11 cabem** nas três
-- espécies de gatilho desta migration e são seedadas aqui — A1–A7 por
-- `exigencia_ausente` (ancoradas em conceitos do catálogo da 0113) e
-- 5.1/5.3/6.3/7.1 por `sempre`. As outras **25 ficam FORA**, cada uma pedindo
-- uma espécie que não existe — meia-cobertura declarada é melhor que gatilho
-- forçado (a doutrina da guarda seed×código):
--   1. CONCEITO INEXISTENTE no catálogo (6): 3.2, 4.3, 6.1, 6.2, 8.1, 8.2 —
--      linha_presente sobre contas a receber, provisões, empréstimos LP,
--      contingências, tributos a recolher, parcelamentos. Criar esses
--      conceitos abriria pendência de ausência em todo balanço que não os tem:
--      mudança de política disfarçada de seed. Decisão de desenho do dono.
--   2. RESULTADO DE RECONCILIAÇÃO (3): 2.1, 2.2, 2.3 — o dado existe (tabela
--      `reconciliacao`), a espécie de gatilho não.
--   3. COMPARAÇÃO NUMÉRICA ENTRE CONCEITOS (3): 3.1, 3.3, 4.1.
--   4. LIMIAR SOBRE PROPORÇÃO (2): 7.3, 8.3 — o limiar é decisão do dono.
--   5. COMPARAÇÃO ENTRE PERÍODOS (2): 4.2, 7.2.
--   6. QUALIDADE DA EXTRAÇÃO (4): A9, A10, A11, A12 — o insumo existe
--      (pendências de guarda 0013/0016, cobertura), a espécie não.
--   7. AVULSAS (5): A8 (pede exigência `secao_presente`, e nenhuma foi
--      seedada), 1.1 (composta), 1.2 (substituída pela A11), 1.3 (contagem de
--      entidades), 5.2 (comparação de datas).
--
-- AS TRÊS ESPÉCIES de gatilho:
--   • `exigencia_ausente` — dispara quando `fn_exigencias_do_caso` diz que o
--     conceito ancorado (FK no catálogo da 0113) NÃO está satisfeito. Uma
--     pergunta sobre BALANCO não dispara em caso sem balanço: a função só
--     lista tipos presentes COM conteúdo — "cadê o documento" é assunto do
--     item_faltante (0006), não daqui.
--   • `linha_presente` — o oposto: dispara quando o conceito ESTÁ satisfeito
--     (perguntas sobre o que a linha revela). Nenhuma das 11 usa; a espécie
--     existe e é testada porque é o upgrade natural da 5.1 (o conceito
--     MUTUOS:saldo_de_mutuo já existe) — um UPDATE de uma linha, do dono.
--   • `sempre` — pergunta contextual, sem âncora. "Sempre" = todo caso COM ao
--     menos uma linha extraída na versão vigente: a entrega define as
--     perguntas como "para depois que a extração roda", e sugerir questionário
--     em caso vazio é ruído.
--
-- MARCADORES nos templates, e como resolvem:
--   • {data_base} e {ano} → a referência de período MAIS RECENTE dos
--     documentos do tipo ancorado (ou do caso inteiro, nas `sempre`). É
--     apresentação: o analista edita antes de enviar; se não houver período,
--     sai "(período não informado)" — visível, nunca em branco.
--   • {saldo_mutuos} → SOMA das linhas que casam o conceito
--     MUTUOS:saldo_de_mutuo (localizadores do catálogo), com a unidade quando
--     ela é única; escalas mistas viram "(valores em escalas mistas —
--     conferir)" em vez de uma soma mentirosa; sem linha, "(não localizado)".
--   • marcador DESCONHECIDO fica visível no texto, de propósito — pergunta
--     nova com marcador novo pede evolução da função, e o jeito de descobrir
--     isso é ver o marcador na tela, não um espaço em branco.
--
-- O QUE NADA AQUI FAZ: enviar. Não existe canal automático (o botão verde da
-- 0109 só rotula) e esta migration não cria um — o sistema SUGERE, o humano
-- decide e envia por fora (Arquitetura do Sistema/1 Visão e Doutrina/01). `caso_pergunta` grava só a AÇÃO HUMANA
-- (enviada/descartada), com o texto renderizado NO MOMENTO do envio congelado
-- na linha — o que foi perguntado é fato histórico e não muda se a extração
-- mudar. `prioridade` não carrega comportamento nenhum (corte, envio, teto
-- seriam política); a função ordena por ela na saída, e só.
--
-- LIMITAÇÕES ASSUMIDAS:
--   • GRANULARIDADE POR ENTIDADE — o reemit previsto, já feito. A versão
--     original desta migration era por CASO e anotava aqui que, quando a linha
--     exigida por entidade (PR #135) mergeasse, as sugestões passariam a nomear
--     a empresa. Ela mergeou como `0119` antes desta entrar, então o reemit
--     está feito: a sugestão é uma por (pergunta × entidade que não satisfaz),
--     com o nome da empresa no texto. Deixar por caso teria produzido, num
--     grupo de oito balanços, uma pergunta que não diz de qual empresa fala —
--     e essa pergunta é ENVIADA ao cliente.
--   • TERCEIRA CÓPIA da expressão de casamento de localizador (0113 e a
--     versão do PR #135 têm as outras duas, inline). A extração para um helper
--     único é a evolução da 0103 — e se faz quando as duas estiverem na main,
--     não daqui de dentro de um PR aberto alheio.
--   • A 5.1 NASCE COM O MOTIVO DEFASADO, de propósito: o texto da entrega diz
--     que "MUTUOS … não são cruzados … por nenhuma reconciliação", e a
--     0117_reconciliar_mutuos (mergeada depois da entrega) criou exatamente
--     esse cruzamento para mútuos (FAT_INTRAGRUPO segue sem). O texto é da
--     entrega e não se parafraseia por conta própria; o ajuste é do autor.
--     Ver a nota no seed.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- O catálogo. Os quatro campos do capítulo 10 + os dois da análise + fonte.
-- -----------------------------------------------------------------------------
create table if not exists pergunta_catalogo (
  codigo                 text primary key,
  titulo                 text not null,
  pergunta               text not null,               -- template, com marcadores
  motivo                 text not null,
  risco                  text not null,
  impacto                text not null,
  prioridade             int  not null check (prioridade between 1 and 4),
  gatilho_especie        text not null check (gatilho_especie in ('exigencia_ausente', 'linha_presente', 'sempre')),
  gatilho_tipo_taxonomia text,
  gatilho_conceito       text,
  gatilho_descricao      text not null,               -- o gatilho como a ENTREGA o escreveu
  fonte                  text not null,
  ativo                  boolean not null default true,
  versao                 int not null default 1,
  -- espécie ancorada exige âncora; 'sempre' exige não ter.
  check ((gatilho_especie = 'sempre') = (gatilho_tipo_taxonomia is null and gatilho_conceito is null)),
  foreign key (gatilho_tipo_taxonomia, gatilho_conceito)
    references taxonomia_linha_exigida (tipo_taxonomia, conceito)
);

comment on table pergunta_catalogo is
  'Banco de perguntas ao cliente (onboarding cap. 10 + análise aprovada, sessão de 13/08/2026). '
  'Texto VERBATIM da entrega. gatilho_especie é o que o motor avalia; gatilho_descricao é a '
  'condição como a entrega a descreveu — insumo das espécies futuras (ver cabeçalho da 0120).';
comment on column pergunta_catalogo.prioridade is
  '1 crítica … 4 contextual — dado da entrega. NENHUM comportamento é atrelado a ela (corte, '
  'envio automático, teto seriam política do dono); a função de sugestão apenas ordena por ela.';
comment on column pergunta_catalogo.gatilho_descricao is
  'O gatilho nas palavras da ENTREGA, inclusive quando pede espécie que ainda não existe. Fato, '
  'não configuração: é daqui que as espécies futuras (reconciliação, comparação, limiar…) saem.';

alter table pergunta_catalogo enable row level security;
-- `drop policy if exists` ANTES do create, que é o padrão da casa (0009, 0107,
-- 0108, 0115) — e não é zelo: o Postgres não tem `create policy if not exists`,
-- então sem esta linha REAPLICAR a migration morre em "policy already exists".
-- E reaplicar não é hipótese: o `Supabase/README.md` é uma lista de comandos que o
-- dono COPIA E RODA, e todo o resto deste arquivo já foi escrito para
-- sobreviver a isso (`create table if not exists`, `on conflict do nothing`).
drop policy if exists pergunta_catalogo_read on pergunta_catalogo;
create policy pergunta_catalogo_read on pergunta_catalogo
  for select to authenticated using (true);
-- Escrita reservada (seed/admin via service_role), como a taxonomia: catálogo
-- de pergunta é vocabulário do sistema, não formulário de tela.

-- -----------------------------------------------------------------------------
-- A AÇÃO humana sobre uma sugestão. Append-only por desenho: enviar de novo é
-- outra linha, nunca update — o que foi perguntado ao cliente não se reescreve.
-- -----------------------------------------------------------------------------
create table if not exists caso_pergunta (
  id              uuid primary key default gen_random_uuid(),
  caso_id         uuid not null references caso(id) on delete cascade,
  pergunta_codigo text not null references pergunta_catalogo(codigo),
  -- DE QUAL EMPRESA é a pergunta. Nasceu na v1 como reserva ("v1 grava null");
  -- desde que a sugestão passou a ser por entidade (a 0119 já está no main),
  -- ela é o que distingue "perguntei sobre a Alfa" de "perguntei sobre a Beta"
  -- — e é por ela que `ja_enviada` sabe qual das duas ainda falta.
  entidade_id     uuid references entidade(id),
  acao            text not null check (acao in ('enviada', 'descartada')),
  texto_enviado   text,
  autor           text not null,
  criado_em       timestamptz not null default now(),
  -- enviar sem o texto enviado deixaria a trilha dizendo QUE se perguntou sem
  -- dizer O QUE — e o template pode mudar depois.
  check (acao <> 'enviada' or (texto_enviado is not null and length(trim(texto_enviado)) > 0))
);

comment on table caso_pergunta is
  'Ação HUMANA sobre uma pergunta sugerida: enviada (com o texto renderizado congelado) ou '
  'descartada. O sistema sugere, o humano decide (Arquitetura do Sistema/1 Visão e Doutrina/01); nenhum envio é automático — o canal '
  'continua sendo o analista (o botão da 0109 só rotula a pendência).';

alter table caso_pergunta enable row level security;
drop policy if exists caso_pergunta_authenticated_all on caso_pergunta;
drop policy if exists caso_pergunta_read on caso_pergunta;
drop policy if exists caso_pergunta_insert on caso_pergunta;

-- APPEND-ONLY DE VERDADE, e não só no comentário.
--
-- A primeira versão declarava "append-only por desenho" e publicava
-- `for all to authenticated` — o que deixa qualquer usuário autenticado dar
-- UPDATE e DELETE. Medido: `set role authenticated; delete from caso_pergunta`
-- apagou a linha. O texto do que foi perguntado a um cliente é fato histórico;
-- uma tabela que promete guardá-lo e aceita `delete` promete o que não cumpre.
--
-- O par certo já existe do lado, no `evento_auditoria` (0003): uma política de
-- INSERT e uma de SELECT, e nenhuma de UPDATE ou DELETE. Sem política para um
-- comando, o RLS nega aquele comando — é assim que "append-only" deixa de ser
-- adjetivo e vira regra do banco.
create policy caso_pergunta_read on caso_pergunta
  for select to authenticated using (true);
create policy caso_pergunta_insert on caso_pergunta
  for insert to authenticated with check (true);

-- O ÍNDICE que o `ja_enviada` pede: `fn_sugerir_perguntas` faz um `exists` por
-- pergunta sugerida, sempre pelo mesmo par. Barato agora, e o tipo de coisa
-- que ninguém volta para acrescentar depois (0025/0028).
create index if not exists idx_caso_pergunta_caso_codigo
  on caso_pergunta (caso_id, pergunta_codigo);

-- -----------------------------------------------------------------------------
-- fn_sugerir_perguntas — a lista, computada NA LEITURA (padrão de
-- fn_linhas_para_modelagem: nada gravado ao sugerir; tabela de sugestão
-- envelhece e mente, função não). `ja_enviada` é informação, não filtro: a
-- pergunta continua listada — quem decide se repete é o humano.
-- -----------------------------------------------------------------------------
create or replace function fn_sugerir_perguntas(p_caso_id uuid)
returns table (
  codigo     text,
  titulo     text,
  prioridade int,
  entidade   text,
  entidade_id uuid,
  pergunta   text,
  motivo     text,
  risco      text,
  impacto    text,
  gatilho    text,
  fonte      text,
  ja_enviada boolean
)
language sql
stable
as $$
  with tem_conteudo as (
    select exists (
      select 1
      from documento d
      join campo_extraido ce on ce.documento_versao_id = fn_versao_com_extracao(d.id)
      where d.caso_id = p_caso_id and ce.valor_num is not null
    ) as ok
  ),
  -- Quais códigos disparam. DISTINCT de propósito: sob a assinatura por
  -- entidade (futura 0119), fn_exigencias_do_caso devolve uma linha por
  -- entidade e a pergunta dispararia N vezes — na v1 a sugestão é por caso.
  -- QUAIS CÓDIGOS DISPARAM, E PARA QUEM.
  --
  -- A versão original devolvia só o código, com `distinct`, porque
  -- `fn_exigencias_do_caso` ainda era por CASO. Desde a 0119 ela é por
  -- ENTIDADE, e a pendência `linha_exigida_ausente` nomeia a empresa. A
  -- pergunta é o lado externo da MESMA avaliação — o texto que vai ao cliente —,
  -- e num grupo de oito balanços "no balanço de 31/12/2025 não localizamos uma
  -- linha de Ativo Total" não diz de QUAL empresa se está falando. Quem recebe
  -- não tem como responder, e quem enviou não tem como saber que faltou.
  --
  -- Então o disparo carrega a entidade quando ela existe, e a sugestão passa a
  -- ser uma por (pergunta × entidade que não satisfaz) — espelhando exatamente
  -- as pendências. Em mandato de uma empresa só, `entidade` vem nula e nada
  -- muda: nomear a única empresa do caso seria ruído.
  disparos as (
    select pc.codigo, null::text as entidade, null::uuid as entidade_id
    from pergunta_catalogo pc
    where pc.ativo and pc.gatilho_especie = 'sempre'
      and (select ok from tem_conteudo)
    union
    select distinct pc.codigo, x.entidade, x.entidade_id
    from pergunta_catalogo pc
    join fn_exigencias_do_caso(p_caso_id) x
      on x.tipo_taxonomia = pc.gatilho_tipo_taxonomia
     and x.conceito = pc.gatilho_conceito
    where pc.ativo
      and ((pc.gatilho_especie = 'exigencia_ausente' and not x.satisfeita)
        or (pc.gatilho_especie = 'linha_presente' and x.satisfeita))
  ),
  -- {saldo_mutuos}: soma das linhas que casam MUTUOS:saldo_de_mutuo na versão
  -- vigente. Escala única acompanha; escalas mistas NÃO são somadas às cegas.
  -- (Terceira cópia da expressão de casamento — ver LIMITAÇÕES no cabeçalho.)
  saldo_mutuos as (
    select case
      when count(*) = 0 then null
      when count(distinct coalesce(c.unidade, '')) > 1 then '(valores em escalas mistas — conferir)'
      else trim(sum(c.valor_num)::text || ' ' || coalesce(max(nullif(c.unidade, '')), ''))
    end as txt
    from (
      select ce.valor_num, ce.unidade
      from documento d
      join campo_extraido ce on ce.documento_versao_id = fn_versao_com_extracao(d.id)
      where d.caso_id = p_caso_id
        and d.tipo_taxonomia = 'MUTUOS'
        and ce.valor_num is not null
        and exists (
          select 1
          from taxonomia_linha_exigida e
          join taxonomia_linha_localizador l on l.exigencia_id = e.id
          where e.tipo_taxonomia = 'MUTUOS' and e.conceito = 'saldo_de_mutuo' and e.ativo
            and case
              when l.contra = 'estrutural' then fn_rotulo_estrutural(ce.chave, l.termos_inclui)
              else
                not exists (
                  select 1 from unnest(l.termos_inclui) t
                  where fn_normalizar_texto(case when l.contra = 'secao'
                                            then coalesce(ce.secao, '') else ce.chave end)
                    not like '%' || fn_normalizar_texto(t) || '%')
                and not exists (
                  select 1 from unnest(l.termos_exclui) t
                  where fn_normalizar_texto(case when l.contra = 'secao'
                                            then coalesce(ce.secao, '') else ce.chave end)
                    like '%' || fn_normalizar_texto(t) || '%')
            end)
    ) c
  )
  -- `entidade_id` SAI JUNTO, e não é enfeite: é o que quem registra a ação
  -- humana precisa devolver em `fn_registrar_pergunta_acao`. Sem ele na saída,
  -- o chamador teria de reencontrar a empresa pelo nome — e errar isso não dá
  -- erro nenhum: a pergunta simplesmente nunca aparece como enviada.
  select pc.codigo, pc.titulo, pc.prioridade, di.entidade, di.entidade_id,
         -- A ENTIDADE ENTRA COMO PREFIXO, e não reescrevendo o texto da
         -- entrega. O corpo da pergunta é verbatim do capítulo 10 e continua
         -- sendo; o que se acrescenta é a única coisa que ele não podia saber —
         -- de qual empresa do grupo se fala. Nula (mandato de uma empresa,
         -- pergunta `sempre`), o prefixo não existe.
         case when di.entidade is not null then 'Sobre a ' || di.entidade || ': ' else '' end ||
         replace(replace(replace(pc.pergunta,
           '{data_base}',    coalesce(per.referencia, '(período não informado)')),
           '{ano}',          coalesce(per.referencia, '(período não informado)')),
           '{saldo_mutuos}', coalesce(sm.txt, '(não localizado)')) as pergunta,
         pc.motivo, pc.risco, pc.impacto,
         case when pc.gatilho_especie = 'sempre' then 'sempre'
              else pc.gatilho_especie || ':' || pc.gatilho_tipo_taxonomia || ':' || pc.gatilho_conceito
         end as gatilho,
         pc.fonte,
         -- `ja_enviada` POR ENTIDADE quando há entidade: enviar a pergunta
         -- sobre a Alfa não responde a mesma pergunta sobre a Beta, e marcar as
         -- duas como enviadas esconderia a que falta. `caso_pergunta.entidade_id`
         -- já existia para isso, reservado desde a v1.
         exists (
           select 1 from caso_pergunta cp
           where cp.caso_id = p_caso_id and cp.pergunta_codigo = pc.codigo and cp.acao = 'enviada'
             and cp.entidade_id is not distinct from di.entidade_id
         ) as ja_enviada
  from pergunta_catalogo pc
  join disparos di on di.codigo = pc.codigo
  cross join saldo_mutuos sm
  -- O PERÍODO MAIS RECENTE É POR ANO, NÃO POR ORDEM ALFABÉTICA.
  --
  -- Era `max(p2.referencia)` — máximo de TEXTO sobre rótulos que não são
  -- comparáveis como texto. Num caso com os períodos "2025" e "L24M", o `max`
  -- devolve **L24M**, e a pergunta saía assim, para o cliente:
  --
  --   "No balanço de L24M não localizamos uma linha de Ativo Total."
  --
  -- L24M é rótulo de janela móvel (últimos 24 meses), não data de balanço — e
  -- nem era o mais recente. Isto não é detalhe de formatação: é o texto que sai
  -- do sistema e chega ao cliente, e a única coisa que a pergunta tem de acertar
  -- sozinha é a qual exercício ela se refere.
  --
  -- `fn_anos_texto` (0030) já sabe ler o ano de qualquer uma das notações do
  -- projeto ("2025", "12M25", "25,24", "1T25"). Ordena-se pelo MAIOR ano que o
  -- rótulo denota; rótulo sem ano nenhum (o "L24M" da vida) vai para o fim em
  -- vez de para a frente, e só é escolhido se for o único que existe.
  left join lateral (
    select p2.referencia
    from documento d2
    join periodo p2 on p2.id = d2.periodo_id
    where d2.caso_id = p_caso_id
      and (pc.gatilho_tipo_taxonomia is null or d2.tipo_taxonomia = pc.gatilho_tipo_taxonomia)
    order by coalesce((select max(a) from unnest(fn_anos_texto(p2.referencia)) a), -1) desc,
             p2.referencia desc
    limit 1
  ) per on true
  order by pc.prioridade, pc.codigo, di.entidade nulls first;
$$;

comment on function fn_sugerir_perguntas(uuid) is
  'Perguntas ao cliente SUGERIDAS para o caso (0120): exigencia_ausente/linha_presente avaliadas '
  'sobre fn_exigencias_do_caso (a mesma fonte da pendência linha_exigida_ausente — as duas faces '
  'nunca divergem); sempre = caso com conteúdo. Marcadores {data_base}/{ano}/{saldo_mutuos} '
  'preenchidos; desconhecidos ficam visíveis. Nada é gravado ao sugerir; ja_enviada informa, não '
  'filtra. Uma sugestão por (pergunta × entidade que não satisfaz) desde que fn_exigencias_do_caso '
  'passou a ser por entidade (0119) — o texto nomeia a empresa, como a pendência já faz.';

grant execute on function fn_sugerir_perguntas(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_registrar_pergunta_acao — a ação humana. Recusas RETORNADAS em jsonb
-- (padrão 0106/0111): exceção desfaria o rastro em evento_auditoria.
-- -----------------------------------------------------------------------------
create or replace function fn_registrar_pergunta_acao(
  p_caso_id     uuid,
  p_codigo      text,
  p_acao        text,
  p_texto       text,
  p_autor       text,
  p_entidade_id uuid default null
)
returns jsonb
language plpgsql
as $$
declare
  v_id uuid;
begin
  if p_acao not in ('enviada', 'descartada') then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('Ação "%s" não existe: as ações são enviada e descartada.', p_acao));
  end if;
  if not exists (select 1 from pergunta_catalogo pc where pc.codigo = p_codigo and pc.ativo) then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('A pergunta "%s" não existe no catálogo (ou está inativa).', p_codigo));
  end if;
  if p_acao = 'enviada' and (p_texto is null or length(trim(p_texto)) = 0) then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'Enviar exige o TEXTO enviado: o template pode mudar depois, e a trilha '
        || 'precisa dizer O QUE foi perguntado ao cliente, não só que se perguntou.');
  end if;

  insert into caso_pergunta (caso_id, pergunta_codigo, entidade_id, acao, texto_enviado, autor)
    values (p_caso_id, p_codigo, p_entidade_id, p_acao,
            case when p_acao = 'enviada' then p_texto end, p_autor)
    returning id into v_id;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values (p_autor, 'pergunta_' || p_acao, 'caso:' || p_caso_id,
            jsonb_build_object('pergunta_codigo', p_codigo, 'caso_pergunta_id', v_id,
                               'entidade_id', p_entidade_id));

  return jsonb_build_object('caso_pergunta_id', v_id, 'pergunta_codigo', p_codigo, 'acao', p_acao);
end;
$$;

comment on function fn_registrar_pergunta_acao(uuid, text, text, text, text, uuid) is
  'Registra a ação HUMANA sobre uma pergunta sugerida (0120). Enviada exige o texto renderizado '
  '(congelado na linha). Recusa em jsonb, nunca exceção — o rastro fica. Append-only: reenviar é '
  'linha nova.';

grant execute on function fn_registrar_pergunta_acao(uuid, text, text, text, text, uuid) to authenticated;

-- =============================================================================
-- SEED — as 11 da entrega, texto VERBATIM (títulos, perguntas, motivo, risco,
-- impacto, gatilho como escrito, fonte). `on conflict do nothing`: idempotente.
-- =============================================================================
insert into pergunta_catalogo
  (codigo, titulo, prioridade, gatilho_especie, gatilho_tipo_taxonomia, gatilho_conceito,
   pergunta, motivo, risco, impacto, gatilho_descricao, fonte)
values
  ('A1', 'Linha de Ativo Total não localizada', 1, 'exigencia_ausente', 'BALANCO', 'ativo_total',
   $q$No balanço de {data_base} não localizamos uma linha de Ativo Total. Podem confirmar o total do ativo do período e, se possível, reenviar o documento com a linha de total visível?$q$,
   $q$A reconciliação A.1 procura um rótulo que contenha 'ativo' e 'total'. Sem ele, e sem seções suficientes para somar, a checagem sai como precondição não satisfeita — não como divergência.$q$,
   $q$Contábil: a equação contábil básica do caso nunca é verificada, e nada na tela diz isso.$q$,
   $q$Sem a A.1, o balanço entra na análise sem nenhuma prova de consistência interna.$q$,
   $q$fn_reconciliar_ativo_passivo_pl retorna precondição não satisfeita por ausência do lado esquerdo.$q$,
   $q$Migrations 0009 e 0033.$q$),

  ('A2', 'Linha de Passivo + PL não localizada', 1, 'exigencia_ausente', 'BALANCO', 'passivo_mais_pl',
   $q$No balanço de {data_base} não localizamos nem a linha combinada de Total do Passivo e do Patrimônio Líquido, nem as linhas separadas de Passivo Total e Patrimônio Líquido Total. Podem confirmar esses totais?$q$,
   $q$A A.1 tenta primeiro a linha combinada e, se ausente, soma as duas separadas. Faltando as três, resta somar as contas da seção — e aí uma seção não classificada some da soma.$q$,
   $q$Contábil: quando a soma vem do fallback por seção, a 'divergência' pode não ser do documento e sim buraco da extração.$q$,
   $q$Muda a interpretação do resultado da A.1: divergência real ou lacuna de extração são investigações diferentes.$q$,
   $q$fn_reconciliar_ativo_passivo_pl sem lado direito por linha de total; caiu no fallback de soma por seção.$q$,
   $q$Migrations 0009, 0023 e 0033.$q$),

  ('A3', 'Caixa e equivalentes não localizado no balanço', 2, 'exigencia_ausente', 'BALANCO', 'caixa_e_equivalentes',
   $q$No balanço de {data_base} não localizamos linha de caixa e equivalentes nem de disponibilidades. O saldo de caixa está agrupado em outra conta?$q$,
   $q$A A.2 procura 'caixa' e 'equivalentes' e, na falta, 'disponibilidades'. Sem uma das duas, não há o que comparar com o fluxo.$q$,
   $q$Financeiro: o saldo de caixa é o número mais sensível da capacidade de pagamento e fica sem contraprova.$q$,
   $q$Sem a A.2, caixa declarado e caixa demonstrado nunca são confrontados.$q$,
   $q$fn_reconciliar_caixa_bp_fluxo sem linha de caixa no BALANCO.$q$,
   $q$Migration 0009.$q$),

  ('A4', 'Saldo final de caixa não localizado no fluxo', 2, 'exigencia_ausente', 'FLUXO_CAIXA', 'saldo_final_de_caixa',
   $q$No fluxo de caixa de {ano} não localizamos a linha de saldo final. Podem confirmar o saldo de caixa ao fim do período?$q$,
   $q$A A.2 procura 'saldo' e 'final', excluindo 'inicial', com alternativa 'caixa' e 'final'.$q$,
   $q$Financeiro: mesma consequência da A3, pela outra ponta.$q$,
   $q$Sem os dois lados, a única checagem que confronta dois documentos sobre caixa não roda.$q$,
   $q$fn_reconciliar_caixa_bp_fluxo sem linha de saldo final no FLUXO_CAIXA.$q$,
   $q$Migrations 0009 e 0031.$q$),

  ('A5', 'Receita bruta não localizada na DRE', 1, 'exigencia_ausente', 'DRE', 'receita_bruta',
   $q$Na DRE de {ano} não localizamos a linha de receita operacional bruta. A receita informada é líquida de deduções?$q$,
   $q$A B.1 procura 'receita' e 'bruta', excluindo 'liquida' e 'deducoes'. Se a DRE só traz receita líquida, a comparação com o faturamento mensal compara bases diferentes.$q$,
   $q$Financeiro e contábil: divergência estrutural lida como erro, ou erro real escondido por base diferente.$q$,
   $q$Define se a B.1 pode rodar e sobre qual base a projeção de receita será construída.$q$,
   $q$fn_reconciliar_receita_dre_vs_faturamento sem linha de receita bruta.$q$,
   $q$Migrations 0015 e 0021.$q$),

  ('A6', 'Despesas financeiras não localizadas na DRE', 1, 'exigencia_ausente', 'DRE', 'despesa_financeira',
   $q$Na DRE de {ano} não localizamos a linha de despesas financeiras. Elas estão agrupadas no resultado financeiro líquido, junto com receitas financeiras?$q$,
   $q$A B.2 procura 'despesas' e 'financeiras', excluindo 'receitas'. Resultado financeiro líquido não serve: compensa juros pagos com receita de aplicação.$q$,
   $q$Financeiro: o custo real da dívida fica desconhecido, e é ele que se compara ao mapa de dívida para achar dívida omitida.$q$,
   $q$Sem a B.2, dívida fora do mapa não é detectada por nenhum mecanismo automático.$q$,
   $q$fn_reconciliar_despesa_financeira sem linha de despesa financeira, ou seção resultado_financeiro vazia.$q$,
   $q$Migrations 0015 e 0021.$q$),

  ('A7', 'Juros não localizados no mapa de dívida', 2, 'exigencia_ausente', 'MAPA_DIVIDA', 'juros_por_contrato',
   $q$No mapa de dívida não localizamos linhas de juros por contrato. Podem informar os juros incorridos em {ano}, por contrato?$q$,
   $q$A B.2 soma as linhas cujo rótulo contém 'juros', excluindo totais. Sem elas, sobra só o lado da DRE.$q$,
   $q$Financeiro: sem os dois lados, dívida omitida do mapa continua invisível.$q$,
   $q$Define se a única checagem capaz de revelar dívida não listada consegue rodar.$q$,
   $q$fn_somar_conceito sobre MAPA_DIVIDA retorna zero linhas de juros.$q$,
   $q$Migration 0015.$q$),

  -- NOTA DE DEFASAGEM (17/08, registrada na 0120 e não corrigida aqui de
  -- propósito): o MOTIVO da 5.1 é texto verbatim da entrega e afirma que
  -- mútuos não são cruzados por nenhuma reconciliação. A 0117_reconciliar_
  -- mutuos, mergeada DEPOIS da entrega, criou o cruzamento balanço × planilha
  -- para mútuos (FAT_INTRAGRUPO segue sem nenhum). A pergunta em si continua
  -- válida — a checagem nova não verifica PERÍMETRO. Ajustar o texto é do
  -- autor da entrega; quando a espécie "resultado de reconciliação" existir,
  -- o gatilho natural desta pergunta é a checagem de mútuos da 0117.
  ('5.1', 'Perímetro dos mútuos', 2, 'sempre', null, null,
   $q$A relação de mútuos informa {saldo_mutuos} em operações entre empresas do grupo. Confirmam que todas as entidades envolvidas nessas operações estão dentro do perímetro das demonstrações combinadas enviadas?$q$,
   $q$O sistema não tem como verificar a eliminação intragrupo — MUTUOS e FAT_INTRAGRUPO são obrigatórios mas não são cruzados com o COMBINADO por nenhuma reconciliação.$q$,
   $q$Societário e contábil: uma entidade fora do perímetro deixa a operação sem contrapartida, e o passivo ou a receita fica contado uma vez a mais.$q$,
   $q$Muda o tamanho declarado do grupo — receita e dívida consolidadas — que é a base de toda negociação.$q$,
   $q$Linhas cujo rótulo contém 'mutuo' com entidade_coluna fora da lista de entidades presentes no COMBINADO, ou mútuos a receber e a pagar que não se anulam.$q$,
   $q$Elaboração própria a partir dos achados das fichas MUTUOS, FAT_INTRAGRUPO e COMBINADO.$q$),

  ('5.3', 'Partes relacionadas fora do grupo', 2, 'sempre', null, null,
   $q$Existem transações relevantes com empresas dos sócios ou de familiares que não fazem parte do perímetro combinado — aluguéis, prestação de serviços, compra e venda de insumos? Em caso positivo, qual o volume anual e o critério de preço.$q$,
   $q$Parte relacionada fora do perímetro não é eliminada e não é sinalizada por nenhuma checagem do sistema.$q$,
   $q$Societário: custo ou receita fora de mercado distorce a margem e pode transferir resultado para fora do grupo em negociação.$q$,
   $q$Ajusta o EBITDA normalizado apresentado aos credores.$q$,
   $q$Existem linhas com rótulo de partes relacionadas, ou despesas de aluguel e serviços cuja contraparte não está no perímetro combinado. Gatilho incerto: o rótulo raramente identifica a contraparte como relacionada — pode precisar de campo próprio na extração.$q$,
   $q$Onboarding cap. 10.2, família societário.$q$),

  ('6.3', 'Avais e garantias prestadas', 1, 'sempre', null, null,
   $q$Quais garantias foram prestadas pelas empresas do grupo ou pelos sócios — avais, fianças, alienação fiduciária, cessão de recebíveis? Podem indicar o contrato garantido, o garantidor e o valor.$q$,
   $q$Aval cruzado entre empresas do grupo transforma dívida de uma entidade em risco de todas, e não aparece no balanço da garantidora.$q$,
   $q$Jurídico e financeiro: passivo contingente invisível que se materializa exatamente no cenário de inadimplência que se está tratando.$q$,
   $q$Redefine quais entidades precisam entrar no acordo e o desenho jurídico da reestruturação.$q$,
   $q$Mais de uma entidade em campo_extraido.entidade_coluna e linhas de dívida bancária no grupo. Contexto: a garantia em si não aparece em linha.$q$,
   $q$Onboarding cap. 10.2, família jurídico; taxonomia AVAIS_FIANCAS.$q$),

  ('7.1', 'Concentração de clientes', 3, 'sempre', null, null,
   $q$Qual a participação dos cinco maiores clientes no faturamento de {ano}? Algum contrato relevante tem vencimento ou renegociação prevista nos próximos 12 meses?$q$,
   $q$A série de faturamento mostra o total, nunca a concentração. Um grupo com receita estável e um cliente responsável por 60% dela tem risco completamente diferente.$q$,
   $q$Operacional: dependência de contrato único, que torna qualquer projeção de receita frágil.$q$,
   $q$Define o grau de confiança na projeção de receita apresentada aos credores e a necessidade de cenário de estresse.$q$,
   $q$Existem linhas de receita e nenhuma abertura por cliente no material recebido. Contexto: concentração não é derivável das linhas.$q$,
   $q$Onboarding cap. 10.2, família operacional.$q$)
on conflict (codigo) do nothing;

-- -----------------------------------------------------------------------------
-- VERIFICAÇÃO EMBUTIDA (padrão 0105).
-- -----------------------------------------------------------------------------
do $$
declare
  v_n int;
  v_caso uuid := gen_random_uuid();
begin
  -- A VERIFICAÇÃO PROVA COISAS SOBRE ESTA MIGRATION, NÃO SOBRE O BANCO DE
  -- AMANHÃ — e a diferença é o que separa um portão de um alçapão.
  --
  -- A forma original contava `where ativo` e exigia exatamente 11. Duas ações
  -- perfeitamente legítimas do dono derrubavam a reaplicação: desativar uma
  -- pergunta (a coluna `ativo` existe para isso) ou acrescentar uma décima
  -- segunda. É o mesmo alçapão que a 0119 teve de corrigir na mesma posição do
  -- arquivo, e a regra que sai das duas vezes é esta: a verificação embutida
  -- confere o que o ARQUIVO fez, e o que o dono fez depois é informação.
  --
  -- Então a conta é sobre as 11 do seed, pelo código, e não sobre o total da
  -- tabela; e `ativo` sai da conta, porque desativar é decisão dele.
  select count(*) into v_n from pergunta_catalogo
   where codigo in ('A1','A2','A3','A4','A5','A6','A7','5.1','5.3','6.3','7.1');
  if v_n <> 11 then
    raise exception '0120: o seed devia ter inserido as 11 perguntas nomeadas, achou %', v_n;
  end if;
  select count(*) into v_n from pergunta_catalogo
   where gatilho_especie = 'exigencia_ausente'
     and codigo in ('A1','A2','A3','A4','A5','A6','A7');
  if v_n <> 7 then
    raise exception '0120: as A1–A7 deviam ser exigencia_ausente, achou %', v_n;
  end if;
  select count(*) into v_n from pergunta_catalogo
   where gatilho_especie = 'sempre' and codigo in ('5.1','5.3','6.3','7.1');
  if v_n <> 4 then
    raise exception '0120: 5.1/5.3/6.3/7.1 deviam ser sempre, achou %', v_n;
  end if;
  -- Nenhuma das 11 usa `linha_presente`: a espécie existe para o upgrade do
  -- dono (um UPDATE), não para o seed. Se ELE ligar depois, isto é notícia, não
  -- erro — por isso NOTICE, e a conta é sobre as 11, não sobre a tabela.
  select count(*) into v_n from pergunta_catalogo
   where gatilho_especie = 'linha_presente'
     and codigo in ('A1','A2','A3','A4','A5','A6','A7','5.1','5.3','6.3','7.1');
  if v_n <> 0 then
    raise notice '0120: % das 11 perguntas do seed estão como linha_presente — upgrade do dono, preservado', v_n;
  end if;
  select count(*) into v_n from pergunta_catalogo
   where codigo not in ('A1','A2','A3','A4','A5','A6','A7','5.1','5.3','6.3','7.1');
  if v_n <> 0 then
    raise notice '0120: % pergunta(s) além das 11 do seed no catálogo — acréscimo do dono, preservado', v_n;
  end if;

  -- Caso VAZIO não recebe pergunta nenhuma — nem as 'sempre': a entrega define
  -- as perguntas para DEPOIS que a extração roda.
  insert into caso (id, nome, produto) values (v_caso, 'VERIF 0120', 'reestruturacao');
  select count(*) into v_n from fn_sugerir_perguntas(v_caso);
  if v_n <> 0 then
    raise exception '0120: caso sem linha extraída recebeu % sugestão(ões) — questionário em caso vazio é ruído', v_n;
  end if;
  delete from caso where id = v_caso;

  raise notice '0120 OK — 11 perguntas (7 ausente + 4 sempre), FKs no catálogo da 0113, caso vazio sem sugestão';
end $$;

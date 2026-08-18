-- =============================================================================
-- Migration 0120 — O banco de perguntas ao cliente vira DADO, e o sistema
-- passa a SUGERIR a pergunta pronta
--
-- (Nasceu para ser "0117" — é o nome da branch. Entre o desenho e a escrita a
-- main ocupou 0117/0118, e 0119 está reservada ao renumero do PR #135, a linha
-- exigida por entidade. Número não se reaproveita; esta é a 0120.)
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
-- decide e envia por fora (docs/01). `caso_pergunta` grava só a AÇÃO HUMANA
-- (enviada/descartada), com o texto renderizado NO MOMENTO do envio congelado
-- na linha — o que foi perguntado é fato histórico e não muda se a extração
-- mudar. `prioridade` não carrega comportamento nenhum (corte, envio, teto
-- seriam política); a função ordena por ela na saída, e só.
--
-- LIMITAÇÕES ASSUMIDAS:
--   • GRANULARIDADE POR CASO. `fn_sugerir_perguntas` referencia só as colunas
--     que `fn_exigencias_do_caso` tem HOJE na main (0113). Quando a linha
--     exigida POR ENTIDADE (PR #135, futura 0119) mergear, as sugestões de
--     `exigencia_ausente` podem nomear a entidade — é um reemit desta função,
--     não um redesenho; o DISTINCT no corpo já a mantém correta sob as duas
--     assinaturas.
--   • TERCEIRA CÓPIA da expressão de casamento de localizador (0113 e a
--     versão do PR #135 têm as outras duas, inline). A extração para um helper
--     único é a evolução da 0103 — e se faz quando as duas estiverem na main,
--     não daqui de dentro de um PR aberto alheio.
--   • O MOTIVO DA 5.1 FOI AJUSTADO PELO AUTOR em 18/08: o texto original da
--     entrega (13/08) dizia que mútuos não eram cruzados por nenhuma
--     reconciliação, e a 0117_reconciliar_mutuos (mergeada depois) criou o
--     cruzamento balanço × planilha. O motivo vigente registra o que a
--     checagem nova NÃO faz — verificar perímetro — que é o que sustenta a
--     pergunta. Texto de terceiro não se parafraseia por conta própria; o
--     ajuste veio do autor. Ver a nota no seed.
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
  entidade_id     uuid references entidade(id),      -- v1 grava null; reservado à granularidade por entidade
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
  'descartada. O sistema sugere, o humano decide (docs/01); nenhum envio é automático — o canal '
  'continua sendo o analista (o botão da 0109 só rotula a pendência).';

alter table caso_pergunta enable row level security;
create policy caso_pergunta_authenticated_all on caso_pergunta
  for all to authenticated using (true) with check (true);

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
  disparos as (
    select pc.codigo
    from pergunta_catalogo pc
    where pc.ativo and pc.gatilho_especie = 'sempre'
      and (select ok from tem_conteudo)
    union
    select distinct pc.codigo
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
  select pc.codigo, pc.titulo, pc.prioridade,
         replace(replace(replace(pc.pergunta,
           '{data_base}',    coalesce(per.referencia, '(período não informado)')),
           '{ano}',          coalesce(per.referencia, '(período não informado)')),
           '{saldo_mutuos}', coalesce(sm.txt, '(não localizado)')) as pergunta,
         pc.motivo, pc.risco, pc.impacto,
         case when pc.gatilho_especie = 'sempre' then 'sempre'
              else pc.gatilho_especie || ':' || pc.gatilho_tipo_taxonomia || ':' || pc.gatilho_conceito
         end as gatilho,
         pc.fonte,
         exists (
           select 1 from caso_pergunta cp
           where cp.caso_id = p_caso_id and cp.pergunta_codigo = pc.codigo and cp.acao = 'enviada'
         ) as ja_enviada
  from pergunta_catalogo pc
  join disparos di on di.codigo = pc.codigo
  cross join saldo_mutuos sm
  left join lateral (
    select max(p2.referencia) as referencia
    from documento d2
    join periodo p2 on p2.id = d2.periodo_id
    where d2.caso_id = p_caso_id
      and (pc.gatilho_tipo_taxonomia is null or d2.tipo_taxonomia = pc.gatilho_tipo_taxonomia)
  ) per on true
  order by pc.prioridade, pc.codigo;
$$;

comment on function fn_sugerir_perguntas(uuid) is
  'Perguntas ao cliente SUGERIDAS para o caso (0120): exigencia_ausente/linha_presente avaliadas '
  'sobre fn_exigencias_do_caso (a mesma fonte da pendência linha_exigida_ausente — as duas faces '
  'nunca divergem); sempre = caso com conteúdo. Marcadores {data_base}/{ano}/{saldo_mutuos} '
  'preenchidos; desconhecidos ficam visíveis. Nada é gravado ao sugerir; ja_enviada informa, não '
  'filtra.';

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

  -- NOTA DE DEFASAGEM E AJUSTE. O motivo original da entrega (13/08) dizia
  -- que mútuos não eram cruzados por nenhuma reconciliação — verdade na data,
  -- defasada quando a 0117_reconciliar_mutuos (mergeada depois) criou o
  -- cruzamento balanço × planilha. O AUTOR DA ENTREGA ajustou o motivo em
  -- 18/08 para o texto abaixo: a pergunta continua válida porque a checagem
  -- nova não verifica PERÍMETRO — contraparte fora das combinadas fecha o
  -- cruzamento e ainda assim deixa a eliminação sem conferência. Quando a
  -- espécie "resultado de reconciliação" existir, o gatilho natural desta
  -- pergunta é a checagem de mútuos da 0117.
  ('5.1', 'Perímetro dos mútuos', 2, 'sempre', null, null,
   $q$A relação de mútuos informa {saldo_mutuos} em operações entre empresas do grupo. Confirmam que todas as entidades envolvidas nessas operações estão dentro do perímetro das demonstrações combinadas enviadas?$q$,
   $q$A 0117 passou a cruzar o saldo de mútuos entre o balanço e a planilha, mas não verifica PERÍMETRO: se a contraparte de uma operação está fora das demonstrações combinadas, o cruzamento fecha e a eliminação continua sem conferência. FAT_INTRAGRUPO segue sem nenhuma checagem.$q$,
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
  select count(*) into v_n from pergunta_catalogo where ativo;
  if v_n <> 11 then
    raise exception '0120: o seed devia ter 11 perguntas (7 exigencia_ausente + 4 sempre), achou %', v_n;
  end if;
  select count(*) into v_n from pergunta_catalogo where gatilho_especie = 'exigencia_ausente';
  if v_n <> 7 then
    raise exception '0120: deviam ser 7 perguntas por exigencia_ausente (A1–A7), achou %', v_n;
  end if;
  select count(*) into v_n from pergunta_catalogo where gatilho_especie = 'sempre';
  if v_n <> 4 then
    raise exception '0120: deviam ser 4 perguntas por sempre (5.1, 5.3, 6.3, 7.1), achou %', v_n;
  end if;
  select count(*) into v_n from pergunta_catalogo where gatilho_especie = 'linha_presente';
  if v_n <> 0 then
    raise exception '0120: nenhuma das 11 usa linha_presente — a espécie existe para o upgrade do dono, não para o seed (achou %)', v_n;
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

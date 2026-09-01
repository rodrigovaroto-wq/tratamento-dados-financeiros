-- =============================================================================
-- 0148 — O FATO QUE O DOCUMENTO DIZ EM TEXTO
--
-- A LACUNA, medida na v48 e registrada no ANEXO A.2 da análise: dos 38
-- documentos, quatro não produzem linha nenhuma — e os quatro estão CERTOS,
-- porque não têm tabela. Só que DOIS deles carregam os fatos mais importantes
-- do mandato:
--
--   • `33_Notas_Explicativas` diz, em texto corrido: "o índice apurado em
--     31/12/2025 não atingiu o mínimo contratado… os saldos originalmente
--     classificados no passivo não circulante foram integralmente
--     reclassificados para o passivo circulante". É A EXPLICAÇÃO de por que o
--     Passivo Circulante saltou para 112.372 — o motivo real de a empresa
--     parecer ilíquida;
--   • `34_Relatorio_do_Auditor` traz OPINIÃO COM RESSALVA e INCERTEZA RELEVANTE
--     SOBRE CONTINUIDADE OPERACIONAL.
--
-- Ressalva de auditor e quebra de covenant são o que um comitê de crédito
-- precisa ver PRIMEIRO. Hoje eles não chegam ao portal de forma nenhuma — nem
-- como linha, nem como alerta. Os documentos entram, são classificados, e ficam
-- mudos. Não é defeito de extração: é lacuna de ESCOPO, e o sistema inteiro está
-- construído para ler tabela.
--
-- A DECISÃO DE PRODUTO, dita antes do schema porque ela é a parte discutível:
--
--   (1) FATO MATERIAL NÃO É PENDÊNCIA. Pendência, neste produto, significa "há
--       algo a corrigir, e alguém precisa agir". Um covenant rompido não é um
--       defeito do dado — é o dado. Pôr os dois na mesma fila obrigaria o
--       analista a "resolver" um fato do mundo, e faria a fila de trabalho
--       deixar de significar trabalho. Então é canal próprio.
--
--   (2) O FATO CARREGA O TRECHO LITERAL, E ISSO É NOT NULL. Um resumo escrito
--       pelo modelo é uma AFIRMAÇÃO; a frase copiada do documento é EVIDÊNCIA.
--       Este repositório passou sessões inteiras corrigindo número que se
--       apresentava como conferido sem ter sido, e um alerta de "continuidade
--       operacional" que ninguém consegue rastrear até a página seria a versão
--       mais cara desse defeito — porque é o alerta que vai ao comitê. Sem
--       trecho, não há fato: `fn_registrar_fatos` DESCARTA a entrada.
--
--   (3) O TIPO É CATÁLOGO, NÃO ENUM NO CORPO DA FUNÇÃO. É a lição do limiar 0.95
--       escrito dentro de `fn_registrar_campos_extraidos` (0041) e da
--       `estagio.startsWith("extracao")` da tela de autonomia (0126): lista de
--       nomes dentro de função obriga a reescrever a função para acrescentar um
--       item. O catálogo também é onde mora a SEVERIDADE e o rótulo humano, para
--       a tela não ter um `switch` paralelo que envelhece sozinho.
--
-- O QUE ESTA MIGRATION NÃO FAZ, dito para não prometer: ela não lê documento
-- nenhum. O que enche `documento_fato` é a extração — o modelo já lê o PDF
-- inteiro, e passa a ter para onde mandar o que leu em prosa. Nenhuma chamada
-- nova, nenhum custo novo de leitura.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- O CATÁLOGO DE TIPOS.
--
-- A lista nasce dos DOIS documentos reais da v48 e do que um comitê de crédito
-- lê primeiro. Ela é curta de propósito: tipo que ninguém sabe o que fazer com
-- vira ruído, e ruído numa lista curta de alertas é pior que ausência.
-- -----------------------------------------------------------------------------
create table if not exists fato_tipo_catalogo (
  tipo        text primary key,
  rotulo      text not null,
  severidade  text not null check (severidade in ('critico', 'relevante', 'informativo')),
  porque      text not null,
  ordem       int  not null default 100
);

comment on table fato_tipo_catalogo is
  'Os tipos de fato material que a extração pode declarar, com a severidade e o rótulo humano. '
  'É catálogo e não enum no corpo da função porque acrescentar um tipo não pode exigir reescrever '
  'a função — e porque a TELA precisa do rótulo sem manter um switch paralelo.';

comment on column fato_tipo_catalogo.porque is
  'Por que este fato importa para quem decide. É o texto que a tela mostra abaixo do trecho, e é o '
  'que separa um alerta acionável de uma etiqueta.';

alter table fato_tipo_catalogo enable row level security;
drop policy if exists fato_tipo_catalogo_read on fato_tipo_catalogo;
create policy fato_tipo_catalogo_read on fato_tipo_catalogo
  for select to authenticated using (true);
grant select on fato_tipo_catalogo to authenticated;

insert into fato_tipo_catalogo (tipo, rotulo, severidade, porque, ordem) values
  ('continuidade_operacional', 'Incerteza sobre continuidade operacional', 'critico',
   'O auditor declarou dúvida relevante sobre a capacidade de a empresa continuar operando. É o '
   'fato de maior peso que um parecer pode trazer, e muda a leitura de todos os números do caso.',
   10),
  ('ressalva_auditoria', 'Opinião com ressalva do auditor', 'critico',
   'O auditor NÃO deu opinião limpa: há item das demonstrações que ele não conseguiu confirmar ou '
   'com o qual discorda. Os números conferem entre si e mesmo assim carregam uma exceção declarada.',
   20),
  ('covenant_rompido', 'Covenant financeiro rompido', 'critico',
   'Um índice contratado não foi atingido. Costuma disparar vencimento antecipado — e é o que '
   'explica dívida de longo prazo aparecendo no curto, com a empresa parecendo ilíquida sem que '
   'nada tenha vencido de fato.',
   30),
  ('reclassificacao_divida', 'Dívida reclassificada para o curto prazo', 'relevante',
   'Saldos que estavam no passivo NÃO circulante foram movidos para o circulante. Sem este fato, o '
   'salto do passivo circulante parece deterioração operacional quando é consequência contratual.',
   40),
  ('litigio_relevante', 'Litígio ou contingência relevante', 'relevante',
   'Processo com valor material declarado. Entra na leitura de risco e pode não ter provisão '
   'correspondente no balanço.',
   50),
  ('garantia_dada', 'Garantia ou ônus sobre ativos', 'relevante',
   'Ativos dados em garantia não estão livres para negociação nem para nova captação — o valor '
   'está no balanço e a disponibilidade dele, não.',
   60),
  ('evento_subsequente', 'Evento subsequente ao encerramento', 'relevante',
   'Aconteceu depois da data do balanço e altera a leitura dele. Os números do exercício não o '
   'contêm, e quem lê só a planilha não fica sabendo.',
   70),
  ('parte_relacionada', 'Transação relevante com parte relacionada', 'informativo',
   'Operação com controlada, controladora ou sócio, declarada em nota. Cruza com o mapa de mútuos '
   'e com o faturamento intragrupo.',
   80),
  ('mudanca_criterio_contabil', 'Mudança de critério contábil', 'informativo',
   'O critério mudou entre exercícios, então a série histórica não é comparável linha a linha sem '
   'ajuste — e a projeção sai do histórico.',
   90)
on conflict (tipo) do update
  set rotulo = excluded.rotulo,
      severidade = excluded.severidade,
      porque = excluded.porque,
      ordem = excluded.ordem;

-- -----------------------------------------------------------------------------
-- documento_fato — um fato por linha, sempre com a evidência junto.
-- -----------------------------------------------------------------------------
create table if not exists documento_fato (
  id                    uuid primary key default gen_random_uuid(),
  documento_versao_id   uuid not null references documento_versao(id) on delete cascade,
  tipo                  text not null references fato_tipo_catalogo(tipo),
  -- O TRECHO LITERAL. NOT NULL, e é a decisão (2) do cabeçalho: sem a frase do
  -- documento não há como conferir o alerta, e alerta que não se confere é
  -- exatamente o que este produto existe para não produzir.
  trecho                text not null check (length(btrim(trecho)) >= 20),
  pagina                int,
  -- O que o modelo entendeu do trecho, em uma frase. É COMPLEMENTO da evidência,
  -- nunca substituto: a tela mostra os dois, e o trecho vem primeiro.
  leitura               text,
  confianca             numeric,
  criado_em             timestamptz not null default now()
);

comment on table documento_fato is
  'Fato material declarado por um documento EM TEXTO — covenant rompido, ressalva de auditoria, '
  'continuidade operacional. Não é pendência: pendência significa "há algo a corrigir", e um '
  'covenant rompido não é defeito do dado, é o dado. Nasceu da v48, onde as Notas Explicativas e o '
  'Parecer do Auditor entravam, eram classificados e ficavam mudos.';

comment on column documento_fato.trecho is
  'A frase COPIADA do documento. NOT NULL e com tamanho mínimo: um resumo escrito pelo modelo é '
  'afirmação, a frase do documento é evidência — e este alerta é o que vai ao comitê.';

create index if not exists documento_fato_versao_idx on documento_fato(documento_versao_id);

alter table documento_fato enable row level security;
drop policy if exists documento_fato_read on documento_fato;
create policy documento_fato_read on documento_fato
  for select to authenticated using (true);
grant select on documento_fato to authenticated;

-- -----------------------------------------------------------------------------
-- fn_registrar_fatos — chamada pelo mesmo nó que registra o diagnóstico.
--
-- IDEMPOTENTE POR VERSÃO, como os outros registradores desta casa: a reextração
-- de uma versão substitui os fatos dela, em vez de acumular duplicatas a cada
-- reprocessamento. O escopo do apagamento é a VERSÃO, nunca o documento — versão
-- anterior é trilha.
--
-- E ELA DESCARTA, EM SILÊNCIO CONTADO, o que não tem evidência. "Silêncio
-- contado" é a diferença que importa: o retorno diz quantos entraram E quantos
-- foram recusados, então um modelo que passe a declarar fatos sem trecho aparece
-- como número, e não como ausência.
-- -----------------------------------------------------------------------------
create or replace function fn_registrar_fatos(
  p_documento_versao_id uuid,
  p_fatos               jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_gravados  int := 0;
  v_sem_prova int := 0;
  v_tipo_ruim int := 0;
begin
  if p_documento_versao_id is null then
    return jsonb_build_object('erro', 'documento_versao_id nulo');
  end if;

  -- Sem chave `fatos` na resposta (workflow antigo, ou resposta que falhou) NÃO
  -- é o mesmo que "este documento não tem fato nenhum". Apagar os fatos de uma
  -- versão porque a chave veio ausente destruiria trilha por causa de um
  -- workflow desatualizado — o mesmo modo de falha do `Gravar Campos` que
  -- desligou a reconciliação por onze dias.
  if p_fatos is null or jsonb_typeof(p_fatos) <> 'array' then
    return jsonb_build_object('gravados', 0, 'sem_prova', 0, 'tipo_desconhecido', 0,
                              'nota', 'sem lista de fatos na resposta — nada foi tocado');
  end if;

  delete from documento_fato where documento_versao_id = p_documento_versao_id;

  insert into documento_fato (documento_versao_id, tipo, trecho, pagina, leitura, confianca)
  select p_documento_versao_id,
         f->>'tipo',
         btrim(f->>'trecho'),
         case when jsonb_typeof(f->'pagina') = 'number' then (f->>'pagina')::int end,
         nullif(btrim(coalesce(f->>'leitura', '')), ''),
         case when jsonb_typeof(f->'confianca') = 'number' then (f->>'confianca')::numeric end
    from jsonb_array_elements(p_fatos) f
   where length(btrim(coalesce(f->>'trecho', ''))) >= 20
     and exists (select 1 from fato_tipo_catalogo c where c.tipo = f->>'tipo');
  get diagnostics v_gravados = row_count;

  select count(*)::int into v_sem_prova
    from jsonb_array_elements(p_fatos) f
   where length(btrim(coalesce(f->>'trecho', ''))) < 20;

  select count(*)::int into v_tipo_ruim
    from jsonb_array_elements(p_fatos) f
   where length(btrim(coalesce(f->>'trecho', ''))) >= 20
     and not exists (select 1 from fato_tipo_catalogo c where c.tipo = f->>'tipo');

  return jsonb_build_object('gravados', v_gravados,
                            'sem_prova', v_sem_prova,
                            'tipo_desconhecido', v_tipo_ruim);
end;
$$;

comment on function fn_registrar_fatos(uuid, jsonb) is
  'Grava os fatos materiais de uma versão de documento, substituindo os anteriores dela. Recusa '
  'entrada sem trecho literal (evidência é obrigatória) e tipo fora do catálogo, e CONTA as '
  'recusas no retorno — recusa silenciosa vira ausência, e ausência parece "não há fato".';

grant execute on function fn_registrar_fatos(uuid, jsonb) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_fatos_do_caso — o que a tela do mandato lê.
--
-- Só a versão CORRENTE de cada documento: versão anterior é trilha, e um alerta
-- de covenant que já foi substituído por uma releitura não pode continuar
-- aparecendo ao lado do novo.
-- -----------------------------------------------------------------------------
create or replace function fn_fatos_do_caso(p_caso_id uuid)
returns table (
  fato_id             uuid,
  documento_id        uuid,
  documento_versao_id uuid,
  nome_documento      text,
  tipo_taxonomia      text,
  tipo                text,
  rotulo              text,
  severidade          text,
  porque              text,
  trecho              text,
  pagina              int,
  leitura             text,
  confianca           numeric
)
language sql
stable
as $$
  with corrente as (
    select distinct on (dv.documento_id) dv.id, dv.documento_id, dv.arquivo_ref, dv.nome_original
      from documento_versao dv
      join documento d on d.id = dv.documento_id
     where d.caso_id = p_caso_id
     order by dv.documento_id, dv.n_versao desc
  )
  select f.id, c.documento_id, f.documento_versao_id,
         coalesce(c.nome_original, c.arquivo_ref),
         d.tipo_taxonomia,
         f.tipo, cat.rotulo, cat.severidade, cat.porque,
         f.trecho, f.pagina, f.leitura, f.confianca
    from documento_fato f
    join corrente c            on c.id = f.documento_versao_id
    join documento d           on d.id = c.documento_id
    join fato_tipo_catalogo cat on cat.tipo = f.tipo
   order by cat.ordem, cat.rotulo, f.criado_em;
$$;

comment on function fn_fatos_do_caso(uuid) is
  'Os fatos materiais do mandato, da versão CORRENTE de cada documento, ordenados por gravidade. '
  'Versão anterior é trilha e não aparece: um alerta já substituído por releitura ao lado do novo '
  'seria duas verdades sobre a mesma frase.';

grant execute on function fn_fatos_do_caso(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- O CATÁLOGO DE INSTALAÇÃO — obrigatório desde a 0147, e é a primeira vez que o
-- portão cobra. Sem estas linhas o `Supabase/test/run.sh` reprova nomeando a 0148.
-- -----------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('fato_material', '0148', 'tabela', 'documento_fato', null, null,
   'O bloco "O que os documentos dizem" some da tela do mandato, e os fatos que um comitê lê '
   'PRIMEIRO — ressalva de auditoria, continuidade operacional, covenant rompido — voltam a não '
   'chegar de forma nenhuma. As Notas Explicativas e o Parecer entram, são classificados e ficam '
   'mudos, exatamente como na v48.',
   'importante', 390),
  ('fato_tipos_semeados', '0148', 'seed', 'fato_tipo_catalogo', 9, null,
   'O catálogo de tipos está vazio: a extração declara o fato e `fn_registrar_fatos` recusa TODOS '
   'por "tipo desconhecido". A tela abre vazia e parece que o documento não disse nada.',
   'importante', 400),
  ('fatos_do_caso', '0148', 'funcao', 'fn_fatos_do_caso', null, null,
   'A tela do mandato não consegue ler os fatos: a tabela tem as linhas e não há função que as '
   'entregue com rótulo e gravidade.',
   'importante', 410)
on conflict (chave) do update
  set migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
      marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
      porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0148',
       revisado_em   = current_date,
       observacao    = 'Revisão de 25/08/2026: a 0148 acrescenta três requisitos (a tabela de '
                       'fatos, o seed dos nove tipos e a função que a tela lê). O seed tem '
                       'critério 9 de propósito — catálogo semeado pela metade recusaria fato de '
                       'tipo válido e a tela ficaria vazia parecendo documento mudo.'
 where id;

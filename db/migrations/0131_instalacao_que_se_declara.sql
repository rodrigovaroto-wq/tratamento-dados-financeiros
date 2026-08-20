-- =============================================================================
-- 0131 — A INSTALAÇÃO PASSA A SE DECLARAR
--
-- O DEFEITO QUE ESTA MIGRATION FECHA, e ele não é de código: é de LUGAR. O
-- `ESTADO.md` carrega, espalhados por 1.400 linhas, recados assim:
--
--   > **Para o dono:** a `0114` precisa ser aplicada no Supabase. Sem ela, a
--   > coluna não existe e a lista trata todo mandato como ativo.
--   > **PARA OS TRÊS INDICADORES NOVOS ACENDEREM:** aplicar a `0115` e
--   > **reimportar o `n8n/workflow.e1-ingestao.json`**.
--
-- Cada um desses recados está correto e nenhum deles é EXECUTADO por nada. Quem
-- abre o portal não lê o `ESTADO.md`; quem lê o `ESTADO.md` não está com o portal
-- aberto. O sintoma no meio é o pior possível para um sistema que promete
-- honestidade sobre os próprios números: **a tela não quebra.** Ela mostra um
-- traço, ou zero, ou uma lista que trata todo mandato como ativo — e parece
-- funcionando. Um número ausente que se apresenta como número é a mesma família
-- do corte silencioso de leitura que originou a paginação (0028) e do teto do
-- PostgREST que entregava parte da extração como se fosse toda ela.
--
-- É, portanto, a mesma forma de defeito que a 0126 e a 0127 corrigiram um nível
-- acima: DOUTRINA SEM EXECUÇÃO. A regra de ouro existia em prosa e não recusava
-- nada; o dial existia como dado e ninguém o lia. Aqui o requisito de instalação
-- existe em prosa e ninguém o confere.
--
-- O QUE ESTA MIGRATION NÃO PROMETE, dito antes de qualquer uso. A sonda abaixo
-- responde "o objeto existe no catálogo", e isso NÃO é "a migration foi aplicada
-- corretamente". Uma migration parcialmente aplicada — a tabela criada, o seed
-- não — passa na sonda de tabela e falha na de seed, e é por isso que os
-- requisitos de SEED são declarados separadamente dos de estrutura em vez de
-- confiados a um só. O que a sonda garante é o contrapositivo, que é a parte
-- útil: **objeto ausente é migration ausente, sem dúvida nenhuma.**
--
-- E ELA NÃO CONFERE A CORREÇÃO DO CORPO DE UMA FUNÇÃO. `create or replace
-- function` sobre um corpo velho deixa a assinatura idêntica; a sonda não
-- distingue. Para isso existe a suíte, que roda o comportamento. A sonda é para o
-- que a suíte NÃO pode ver: o estado do banco de PRODUÇÃO, onde nenhum teste
-- roda.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- instalacao_requisito — o catálogo do que precisa existir FORA DO GIT.
--
-- POR QUE TABELA E NÃO UMA LISTA DENTRO DE UMA FUNÇÃO. É a lição do limiar 0.95
-- escrito no corpo de `fn_registrar_campos_extraidos` (corrigida pela 0041) e da
-- `estagio.startsWith("extracao")` na tela de autonomia (corrigida pela 0126):
-- lista de nomes dentro de função obriga a reescrever a função para acrescentar
-- um item, e quem acrescenta o item costuma ser justamente quem não vai lembrar
-- de reescrever a função. Requisito é DADO.
--
-- `porque` é NOT NULL de propósito, e é o campo mais importante da tabela. Um
-- painel que diz "0115 ausente" não serve para ninguém que não tenha o
-- `ESTADO.md` na outra aba. "Os indicadores de custo do painel mostram um traço"
-- é acionável por quem está olhando a tela.
-- -----------------------------------------------------------------------------
create table if not exists instalacao_requisito (
  chave        text primary key,
  migration    text not null,
  tipo         text not null check (tipo in ('tabela','coluna','funcao','seed','comportamento')),
  -- Para 'tabela' e 'funcao': o nome. Para 'coluna': `tabela.coluna`. Para
  -- 'seed': `tabela` (e `criterio_seed` diz o quanto se espera). Para
  -- 'comportamento': `tabela` cuja existência de LINHA é a prova.
  objeto       text not null,
  criterio_seed int,
  porque       text not null,
  severidade   text not null default 'importante'
                 check (severidade in ('bloqueante','importante','informativo')),
  ordem        int  not null default 100
);

comment on table instalacao_requisito is
  'O que precisa existir no banco de PRODUÇÃO para o portal não mentir — um requisito por linha, '
  'com o sintoma visível escrito. Existe porque estes requisitos moravam em prosa no ESTADO.md, '
  'onde nada os executa: quem abre o portal não lê o ESTADO.md, e a tela sem a migration não '
  'quebra, mostra um traço.';

comment on column instalacao_requisito.porque is
  'O SINTOMA VISÍVEL da ausência, não a descrição da migration. É o que torna o painel acionável '
  'para quem está com a tela aberta e não com o repositório.';

comment on column instalacao_requisito.tipo is
  'comportamento é o único que não sonda o catálogo: alguns requisitos não são de banco (reimportar '
  'o workflow do n8n) e só se provam pelo EFEITO — a tabela que aquele nó grava tem linha.';

alter table instalacao_requisito enable row level security;
drop policy if exists instalacao_requisito_read on instalacao_requisito;
create policy instalacao_requisito_read on instalacao_requisito
  for select to authenticated using (true);
-- Sem política de insert/update/delete para `authenticated`: o catálogo é
-- versionado em migration, não editado pela tela. Quem acrescenta requisito
-- escreve migration — que é exatamente o momento em que ele sabe o que
-- acrescentar.

grant select on instalacao_requisito to authenticated;

-- -----------------------------------------------------------------------------
-- fn_instalacao_conferir — a sonda.
--
-- Uma passada, um `left join lateral` por tipo. Não recebe parâmetro: a pergunta
-- "esta instalação está completa?" não tem variante.
--
-- POR QUE `to_regclass` E `to_regproc` E NÃO CONSULTA A `pg_class` NA MÃO. As
-- duas resolvem o nome pelo `search_path` corrente e devolvem NULL em vez de
-- erro quando o objeto não existe — que é precisamente o que uma sonda precisa.
-- Consultar `pg_class` por `relname` sem qualificar o schema encontraria um
-- homônimo em outro schema e responderia "presente" para o objeto errado.
-- -----------------------------------------------------------------------------
create or replace function fn_instalacao_conferir()
returns table (
  chave       text,
  migration   text,
  tipo        text,
  objeto      text,
  presente    boolean,
  detalhe     text,
  porque      text,
  severidade  text
)
language plpgsql
stable
as $$
declare
  r         instalacao_requisito;
  v_ok      boolean;
  v_det     text;
  v_n       bigint;
begin
  for r in select * from instalacao_requisito order by ordem, chave loop
    v_ok  := false;
    v_det := null;

    if r.tipo = 'tabela' then
      v_ok := to_regclass('public.' || r.objeto) is not null;

    elsif r.tipo = 'funcao' then
      -- `to_regproc` falha quando a função tem sobrecargas ambíguas; o nome sem
      -- argumentos resolve pelo único candidato, e sobrecarga é sinal de que o
      -- requisito devia declarar a assinatura. Nenhum dos requisitos abaixo tem.
      begin
        v_ok := to_regproc('public.' || r.objeto) is not null;
      exception when others then
        -- Ambiguidade significa que EXISTE mais de uma — logo, existe.
        v_ok := true;
        v_det := 'mais de uma assinatura com este nome';
      end;

    elsif r.tipo = 'coluna' then
      v_ok := exists (
        select 1 from information_schema.columns c
         where c.table_schema = 'public'
           and c.table_name   = split_part(r.objeto, '.', 1)
           and c.column_name  = split_part(r.objeto, '.', 2));

    elsif r.tipo in ('seed', 'comportamento') then
      -- A tabela pode não existir ainda: contar nela levantaria erro e derrubaria
      -- a sonda inteira, transformando "um requisito faltando" em "o painel não
      -- abre". A sonda de instalação é o último lugar do sistema que pode falhar
      -- por causa do que ela existe para medir.
      if to_regclass('public.' || r.objeto) is null then
        v_ok  := false;
        v_det := 'a tabela nem existe';
      else
        execute format('select count(*) from public.%I', r.objeto) into v_n;
        v_ok  := v_n >= coalesce(r.criterio_seed, 1);
        v_det := format('%s linha(s)', v_n);
      end if;
    end if;

    return query select r.chave, r.migration, r.tipo, r.objeto, v_ok, v_det,
                        r.porque, r.severidade;
  end loop;
end;
$$;

comment on function fn_instalacao_conferir() is
  'Sonda cada requisito de instalacao_requisito contra o catálogo do banco em que ela roda. '
  'Responde "o objeto existe", que NÃO é "a migration foi aplicada corretamente" — o corpo de uma '
  'função trocada por create or replace passa igual. O que ela garante é o contrapositivo, que é a '
  'parte útil: objeto ausente é migration ausente.';

grant execute on function fn_instalacao_conferir() to authenticated;

-- -----------------------------------------------------------------------------
-- fn_instalacao_resumo — a resposta de uma linha, para o painel decidir a cor.
-- -----------------------------------------------------------------------------
create or replace function fn_instalacao_resumo()
returns jsonb
language sql
stable
as $$
  with c as (select * from fn_instalacao_conferir())
  select jsonb_build_object(
    'total',        (select count(*) from c),
    'presentes',    (select count(*) from c where presente),
    'ausentes',     (select count(*) from c where not presente),
    'bloqueantes_ausentes',
                    (select count(*) from c where not presente and severidade = 'bloqueante'),
    'completa',     (select not exists (select 1 from c where not presente)),
    'faltando',     coalesce((select jsonb_agg(jsonb_build_object(
                       'chave', chave, 'migration', migration, 'porque', porque,
                       'severidade', severidade) order by severidade, chave)
                     from c where not presente), '[]'::jsonb));
$$;

comment on function fn_instalacao_resumo() is
  'O veredito de uma linha sobre a instalação, para o painel. "completa" só é true quando NENHUM '
  'requisito falta — inclusive os informativos, porque um requisito que não vale a pena conferir '
  'não devia estar no catálogo.';

grant execute on function fn_instalacao_resumo() to authenticated;

-- =============================================================================
-- O CATÁLOGO — cada linha era um recado em prosa no ESTADO.md.
--
-- A ORDEM É A DA DOR, não a numérica: o que quebra a tela mais visível vem
-- primeiro. E `porque` descreve o SINTOMA, porque é ele que quem está olhando a
-- tela consegue reconhecer.
-- =============================================================================

insert into instalacao_requisito (chave, migration, tipo, objeto, criterio_seed, porque, severidade, ordem) values

  -- ---- o que o sistema não roda sem ----------------------------------------
  ('taxonomia_semeada', '0002', 'seed', 'taxonomia_tipo_documento', 8,
   'Sem a taxonomia, o Portão 1 não sabe o que exigir: todo mandato aparece completo, porque a '
   'lista do que devia ter chegado está vazia. É a falha mais silenciosa de todas — o sistema '
   'aprova por não saber cobrar.',
   'bloqueante', 10),

  ('dial_semeado', '0002', 'seed', 'estagio_autonomia', 8,
   'Sem os oito estágios, o painel de autonomia abre vazio e — pior — fn_dial_influencia devolve o '
   'default de "influencia" para estágio sem linha. A tela some e o comportamento não.',
   'bloqueante', 20),

  -- ---- as telas que mostram traço em vez de número -------------------------
  ('custo_do_lote', '0115', 'tabela', 'lote_execucao', null,
   'Os indicadores de custo e de cobertura do painel mostram um traço com a causa escrita. Nenhum '
   'número de gasto de API aparece, e o oitavo indicador (cobertura da extração) não existe.',
   'importante', 30),

  ('custo_gravado_pelo_n8n', '0115', 'comportamento', 'lote_execucao', 1,
   'A tabela existe e está VAZIA: é o sintoma de que o workflow do n8n não foi reimportado depois '
   'da mudança. O nó "Gravar Uso do Lote" não está no canvas em execução — e o n8n executa o JSON '
   'importado, não o do repositório. Merge não reimporta.',
   'importante', 40),

  ('mandato_fechado', '0114', 'coluna', 'caso.fechado_em', null,
   'A lista de mandatos trata todo mandato como ativo, e o botão de fechar falha ao ser clicado. '
   'A tela não quebra antes do clique.',
   'importante', 50),

  -- ---- o banco de perguntas ------------------------------------------------
  ('banco_de_perguntas', '0120', 'tabela', 'caso_pergunta', null,
   'A aba de perguntas ao cliente abre vazia. As pendências continuam nomeando o que falta, mas '
   'ninguém recebe a pergunta redigida — o trabalho de escrever volta para a mesa.',
   'importante', 60),

  ('perguntas_semeadas', '0120', 'seed', 'pergunta_catalogo', 1,
   'A tabela existe e o catálogo está vazio: nenhuma pergunta é sugerida, para nenhum mandato, '
   'em nenhuma situação. Igual a não ter a migration, com a diferença de parecer instalado.',
   'importante', 70),

  -- ---- a governança de autonomia ------------------------------------------
  ('golden_set', '0126', 'tabela', 'golden_rodada', null,
   'O painel de autonomia perde o bloco de golden set e a regra de ouro deixa de ser executada: '
   'fn_mudar_dial não existe na versão que RECUSA subida sem medição. O dial voltaria a subir por '
   'digitação.',
   'bloqueante', 80),

  ('dial_obedecido', '0127', 'funcao', 'fn_dial_permite_auto', null,
   'O limiar de auto-aceite volta a viver no corpo do código em vez do dial: mudar o nível na tela '
   'não muda o comportamento do sistema. O painel de autonomia passa a descrever uma configuração '
   'que ninguém lê.',
   'bloqueante', 90),

  ('classificacao_contabil', '0128', 'tabela', 'classe_contabil_catalogo', null,
   'A coluna "Classe contábil" da tela do documento fica vazia em toda linha, e nenhuma sugestão '
   'de natureza (recorrente, ajuste de EBITDA) é gravada — o oitavo estágio deixa de existir.',
   'importante', 100),

  ('rubricas_semeadas', '0128', 'seed', 'rubrica_classe', 1,
   'O catálogo de regras está vazio: a classificação roda e sugere "revisar_manual" para tudo. '
   'Funciona, e não serve para nada.',
   'importante', 110),

  -- ---- a saída do gate de captura -----------------------------------------
  ('transcricao_humana', '0129', 'coluna', 'campo_extraido.origem_valor', null,
   'O bloco de transcrição assistida some da tela do documento ilegível, e o gate de captura volta '
   'a ser o dead-end que a doutrina proíbe: arquivo que não se lê, pendência que não fecha, e '
   'nenhum caminho a não ser o cliente reenviar um arquivo que às vezes não existe.',
   'importante', 120),

  ('golden_rotulavel', '0130', 'funcao', 'fn_golden_abrir_rodada', null,
   'A tela de rotulagem cega não grava: o golden set existe como tabela e não há caminho de '
   'escrita. Sem isso a concordância nunca é medida, e nenhum estágio interpretativo pode subir '
   'de nível — por regra, não por defeito.',
   'informativo', 130)

on conflict (chave) do update
  set migration = excluded.migration,
      tipo      = excluded.tipo,
      objeto    = excluded.objeto,
      criterio_seed = excluded.criterio_seed,
      porque    = excluded.porque,
      severidade = excluded.severidade,
      ordem     = excluded.ordem;

-- `do update` e não `do nothing`: este catálogo é a única coisa nesta casa em que
-- reaplicar DEVE corrigir o texto. `porque` é a mensagem que uma pessoa vai ler
-- num painel para decidir o que fazer, e uma migration posterior que melhore essa
-- frase precisa que a melhora chegue. Não há trilha a preservar aqui — o
-- requisito não é evidência de nada, é documentação executável.

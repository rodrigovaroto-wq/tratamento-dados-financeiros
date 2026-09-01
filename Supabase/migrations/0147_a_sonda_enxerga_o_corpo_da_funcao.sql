-- =============================================================================
-- 0147 — A SONDA PASSA A ENXERGAR O CORPO DA FUNÇÃO, E O CATÁLOGO PASSA A DIZER
--        ATÉ ONDE FOI REVISADO
--
-- O DEFEITO, e ele é do tipo que este repositório já nomeou: o catálogo de
-- instalação tinha 13 marcadores e o mais novo apontava para a `0130`. As
-- migrations estão na `0146`. Dezesseis migrations sem cobertura nenhuma — e não
-- por descuido: ninguém foi avisado, porque nada acusa um catálogo que fica para
-- trás. É a MESMA forma do cabeçalho do `HANDOFF.md` que passou 17 PRs congelado
-- e do `ESTADO.md` que só parou de envelhecer quando o `run.sh` passou a
-- reprovar. Documento que não é executado envelhece; a correção não é escrever
-- de novo, é pôr alguém para conferir.
--
-- E HÁ UMA SEGUNDA CEGUEIRA, que a própria 0131 declarou de si mesma e deixou
-- aberta:
--
--   > E ELA NÃO CONFERE A CORREÇÃO DO CORPO DE UMA FUNÇÃO. `create or replace
--   > function` sobre um corpo velho deixa a assinatura idêntica; a sonda não
--   > distingue.
--
-- Isso não é um detalhe deste catálogo: é a maior parte dele. Das dezesseis
-- migrations sem cobertura, apenas SETE criam objeto novo. As outras NOVE só
-- republicam o corpo de uma função que já existia — a `0142` (tipo_incorreto
-- exige divergência), a `0143` (hierarquia achatada), a `0144` (duplicidade
-- entre documentos), a `0145` (o conceito na coluna), a `0146` (a entidade
-- fantasma). Todas elas mudam O QUE O SISTEMA ACUSA. Um banco de produção sem
-- elas abre pendência falsa e parece perfeitamente instalado, porque cada função
-- que elas corrigem EXISTE.
--
-- Era, portanto, a fatia mais cara possível de ficar de fora: a sonda enxergava
-- justamente as migrations cuja ausência quebraria uma tela — e era cega
-- justamente para as que mentem calado.
--
-- O QUE ESTA MIGRATION FAZ, em três partes:
--
--   (1) o tipo `corpo`: o requisito passa a poder exigir que um TRECHO apareça
--       no corpo publicado da função. `pg_get_functiondef` devolve o fonte
--       vigente, comentários inclusive, e as migrations de patch desta casa já
--       deixam a própria assinatura lá dentro (`-- 0142:`, `-- 0143:`);
--   (2) os 20 requisitos das migrations `0131` a `0146`;
--   (3) `instalacao_cobertura`: uma linha dizendo até QUE MIGRATION o catálogo
--       foi revisado — e o `Supabase/test/run.sh` reprova quando ela fica para trás da
--       migration mais nova. É o mesmo portão do `ESTADO.md`, pela mesma razão.
--
-- O QUE O TIPO `corpo` NÃO PROMETE, dito antes do primeiro uso. Ele responde "o
-- corpo publicado contém este trecho", que é mais forte que "a função existe" e
-- mais fraco que "a função está correta". Um trecho pode sobreviver a uma
-- correção que o deixe inócuo. O que ele garante continua sendo o
-- contrapositivo, que é a parte útil: **trecho ausente é migration ausente,
-- sem dúvida nenhuma** — e é esse lado que o painel precisa.
--
-- E ELE PODE FICAR FRÁGIL, o que é uma escolha e não um descuido: se uma
-- migration futura reescrever `fn_registrar_diagnostico` sem o comentário
-- `-- 0142`, o requisito passa a acusar ausência num banco completo. Isso NÃO
-- fica escondido: o `instalacao.test.sql` roda a sonda contra o banco montado do
-- zero e reprova qualquer requisito ausente, então o alarme falso aparece no CI —
-- na mesma passada em que a reescrita foi feita, e não meses depois na tela do
-- dono. Fragilidade que o CI acusa é fragilidade barata; a alternativa era não
-- conferir nada.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- (1) O TIPO `corpo`
-- -----------------------------------------------------------------------------

alter table instalacao_requisito
  add column if not exists marcador text;

comment on column instalacao_requisito.marcador is
  'Para tipo=''corpo'': o TRECHO que precisa aparecer em pg_get_functiondef(objeto). É a única '
  'forma de a sonda distinguir uma função corrigida de uma função homônima com o corpo velho — '
  'e essa distinção é a maior parte do catálogo, porque a maioria das migrations recentes só '
  'republica corpo.';

alter table instalacao_requisito
  drop constraint if exists instalacao_requisito_tipo_check;

alter table instalacao_requisito
  add constraint instalacao_requisito_tipo_check
  check (tipo in ('tabela', 'coluna', 'funcao', 'seed', 'comportamento', 'corpo'));

-- Requisito de corpo SEM marcador passaria em qualquer banco, para sempre, sem
-- nunca acusar nada — o pior estado possível para uma sonda. A restrição fecha
-- isso na escrita, que é onde dá para consertar.
alter table instalacao_requisito
  drop constraint if exists instalacao_requisito_marcador_check;

alter table instalacao_requisito
  add constraint instalacao_requisito_marcador_check
  check (tipo <> 'corpo' or (marcador is not null and length(marcador) >= 4));

-- -----------------------------------------------------------------------------
-- fn_instalacao_conferir — reemitida com o ramo `corpo`.
--
-- REEMISSÃO A PARTIR DO CORPO DA 0132, e não do da 0131: é a 0132 que tem a
-- contagem limitada ao critério (o custo do painel deixando de crescer junto com
-- `lote_execucao`) e o `pg_attribute` no lugar do `information_schema`. Reemitir
-- da 0131 desfaria as duas em silêncio — o defeito que a 0116 causou na checagem
-- de balanço e que só apareceu cinco sessões depois.
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
  v_alvo    regclass;
  v_crit    int;
  v_proc    regproc;
  v_src     text;
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

    elsif r.tipo = 'corpo' then
      -- 0147: o corpo PUBLICADO tem de conter o marcador.
      --
      -- Como todo ramo desta função, ele não pode derrubar a sonda: função
      -- ausente, nome ambíguo e marcador ausente são três respostas diferentes,
      -- e as três são `presente = false` com o detalhe dizendo QUAL — porque
      -- "aplique a migration" e "há duas assinaturas com este nome" pedem ações
      -- diferentes de quem está lendo a tela.
      begin
        v_proc := to_regproc('public.' || r.objeto);
      exception when others then
        v_proc := null;
        v_det  := 'mais de uma assinatura com este nome — o requisito precisa declarar os argumentos';
      end;

      if v_proc is null then
        v_ok  := false;
        v_det := coalesce(v_det, 'a função nem existe');
      else
        v_src := pg_get_functiondef(v_proc::oid);
        v_ok  := v_src is not null and position(r.marcador in v_src) > 0;
        v_det := case when v_ok then 'corpo com o marcador'
                      else 'a função existe, mas o corpo é ANTERIOR a esta migration' end;
      end if;

    elsif r.tipo = 'coluna' then
      -- 0132: `pg_attribute` em vez de `information_schema.columns` — mesma
      -- resposta, 14× mais barato (3,4 ms → 0,25 ms medidos). A view do
      -- information_schema junta várias tabelas de catálogo e filtra por
      -- privilégio linha a linha; aqui a pergunta é "existe esta coluna", e
      -- `attrelid` já vem resolvido por `to_regclass`.
      --
      -- `to_regclass` devolvendo NULL não é erro: significa que a TABELA não
      -- existe, e aí a coluna também não — `attrelid = null` não casa com nada e
      -- o `exists` dá false, que é a resposta certa. É a mesma proteção do ramo
      -- de seed abaixo, obtida de graça pela forma da consulta.
      v_ok := exists (
        select 1 from pg_attribute a
         where a.attrelid  = to_regclass('public.' || split_part(r.objeto, '.', 1))
           and a.attname   = split_part(r.objeto, '.', 2)
           and a.attnum    > 0
           and not a.attisdropped);

    elsif r.tipo in ('seed', 'comportamento') then
      -- A tabela pode não existir ainda: contar nela levantaria erro e derrubaria
      -- a sonda inteira, transformando "um requisito faltando" em "o painel não
      -- abre". A sonda de instalação é o último lugar do sistema que pode falhar
      -- por causa do que ela existe para medir.
      v_alvo := to_regclass('public.' || r.objeto);
      if v_alvo is null then
        v_ok  := false;
        v_det := 'a tabela nem existe';
      else
        -- 0132: CONTAGEM LIMITADA AO CRITÉRIO. Ver o cabeçalho: a pergunta é
        -- ">= criterio", e varrer a tabela inteira para respondê-la faz o custo
        -- do painel crescer junto com `lote_execucao`, que cresce para sempre.
        v_crit := greatest(coalesce(r.criterio_seed, 1), 1);
        execute format('select count(*) from (select 1 from public.%I limit %s) x',
                       r.objeto, v_crit)
           into v_n;
        v_ok := v_n >= v_crit;
        -- No caso PRESENTE o total exato não é conhecido (nem usado pela tela).
        -- No caso AUSENTE ele é exato por construção — a varredura parou antes do
        -- limite, logo passou por tudo — e é nele que o número informa algo:
        -- "3 linha(s)" com critério 8 diz que o seed rodou pela metade.
        v_det := case when v_ok then format('%s linha(s) ou mais', v_crit)
                      else format('%s linha(s)', v_n) end;
      end if;
    end if;

    return query select r.chave, r.migration, r.tipo, r.objeto, v_ok, v_det,
                        r.porque, r.severidade;
  end loop;
end;
$$;

comment on function fn_instalacao_conferir() is
  'Confere cada requisito de instalacao_requisito contra o catálogo do banco. Sobrevive ao objeto '
  'ausente (to_regclass/to_regproc devolvem NULL em vez de erro): a sonda não pode falhar por causa '
  'do que ela existe para medir. Desde a 0147 confere também o CORPO da função (tipo=corpo), que é '
  'o único jeito de distinguir uma correção aplicada de uma função homônima com o corpo velho.';

grant execute on function fn_instalacao_conferir() to authenticated;

-- -----------------------------------------------------------------------------
-- (3) A COBERTURA DECLARADA — para o catálogo não voltar a envelhecer calado.
--
-- POR QUE UMA LINHA DE DADO E NÃO UM COMENTÁRIO. Comentário não é conferível.
-- O `Supabase/test/run.sh` lê esta linha do banco que ele acabou de montar e a compara
-- com a migration mais nova do diretório; divergiu, reprova. Quem escreve a
-- migration `0148` é obrigado a decidir uma das duas coisas — "acrescento um
-- requisito" ou "revisei e não há o que acrescentar" — e as duas passam por
-- aqui. Nenhuma delas é "não pensei nisso", que é o que aconteceu 16 vezes.
--
-- `observacao` é NOT NULL de propósito, pela mesma razão do `porque`: um
-- `ate_migration = '0152'` sozinho não conta se as `0148`–`0152` não tinham o
-- que declarar ou se alguém só empurrou o número para o portão calar.
-- -----------------------------------------------------------------------------
create table if not exists instalacao_cobertura (
  id             boolean primary key default true check (id),  -- uma linha só
  ate_migration  text not null,
  revisado_em    date not null default current_date,
  observacao     text not null
);

comment on table instalacao_cobertura is
  'Até que migration o catálogo instalacao_requisito foi revisado. Uma linha só. O Supabase/test/run.sh '
  'reprova quando ela fica para trás da migration mais nova — é o mesmo portão do ESTADO.md, e '
  'existe porque o catálogo passou 16 migrations parado na 0130 sem que nada acusasse.';

alter table instalacao_cobertura enable row level security;
drop policy if exists instalacao_cobertura_read on instalacao_cobertura;
create policy instalacao_cobertura_read on instalacao_cobertura
  for select to authenticated using (true);
grant select on instalacao_cobertura to authenticated;

insert into instalacao_cobertura (id, ate_migration, observacao) values
  (true, '0147',
   'Revisão de 25/08/2026: as 0131 a 0146 entraram no catálogo. Das 16, sete criam objeto novo e '
   'entram por nome; nove só republicam corpo de função e entram pelo tipo corpo, novo nesta '
   'migration. A 0133 e a 0137 aparecem duas vezes de propósito — o objeto novo E o corpo — porque '
   'são as duas coisas que podem faltar separadamente.')
on conflict (id) do update
  set ate_migration = excluded.ate_migration,
      revisado_em   = current_date,
      observacao    = excluded.observacao;

-- -----------------------------------------------------------------------------
-- (2) OS REQUISITOS DAS 0131 A 0146
--
-- A ORDEM CONTINUA SENDO A DA DOR: `ordem` 200+ para não se misturar com os 13
-- originais, mas dentro da faixa o que MENTE vem antes do que quebra. Um painel
-- que abre vazio é reconhecível; uma pendência falsa não é, e foi por isso que a
-- v48 gastou uma sessão inteira provando que 20 das 27 eram falsas.
--
-- E `porque` continua sendo o SINTOMA, não a descrição da migration: quem lê
-- está com a tela aberta, não com o repositório.
-- -----------------------------------------------------------------------------

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values

  -- ---- as que fazem o sistema ACUSAR O QUE NÃO EXISTE -----------------------
  -- Estas cinco são a fatia cara: sem elas nenhuma tela quebra, nenhum número
  -- some, e o analista recebe pendência para conferir o que já está certo. Foi
  -- exatamente o estado medido na v48 — 27 pendências, 20 falsas.

  ('tipo_incorreto_com_divergencia', '0142', 'corpo', 'fn_registrar_diagnostico', '-- 0142', null,
   'O documento abre pendência de "tipo incorreto" sem que haja divergência nenhuma: o modelo '
   'reconheceu o MESMO tipo com outro nome, ou disse que não sabe, e a pendência pede decisão '
   'sobre uma diferença que não existe. Nada na tela indica que a pendência é falsa.',
   'importante', 200),

  ('hierarquia_achatada_nao_acusa', '0143', 'corpo', 'fn_conferir_arvore', '-- 0143', null,
   'A conferência de árvore acusa "divergente" em toda seção cuja soma dá EXATAMENTE o dobro do '
   'pai — que é o sintoma de hierarquia achatada na extração, não de número errado. Foram 12 das '
   '20 pendências falsas da v48, todas apontando para contas corretas.',
   'importante', 210),

  ('duplicidade_entre_documentos', '0144', 'corpo', 'fn_reconciliar_duplicidade',
   'DOCUMENTOS DIFERENTES (0144)', null,
   'A checagem de duplicidade de rótulo acusa pares que estão no MESMO documento — onde repetir o '
   'rótulo é a forma normal de um demonstrativo, não um erro. Na v48 os 33 pares acusados eram '
   '33 de 33 dentro do mesmo documento.',
   'importante', 220),

  ('conceito_na_coluna', '0145', 'corpo', 'fn_exigencias_do_caso', '-- 0145', null,
   'Em documento MATRICIAL (mapa de dívida, aging) o conceito mora no CABEÇALHO DA COLUNA e a '
   'linha é a entidade concreta. Sem isto o localizador só olha a linha, a exigência fica '
   '"ausente" com o dado ali do lado, e a reconciliação que depende dela não roda — inclusive a '
   'de despesa financeira do DRE contra os juros do mapa de dívida.',
   'importante', 230),

  ('entidade_que_o_documento_nao_declarou', '0146', 'corpo', 'fn_exigencias_do_caso', '-- 0146', null,
   'Num documento que fala de VÁRIAS empresas, a linha sem coluna é atribuída à empresa da capa — '
   'e nasce uma entidade fantasma cobrando um balanço que ninguém prometeu. Três pendências da '
   'v48 vieram daí, todas contra uma empresa que o documento nunca declarou.',
   'importante', 240),

  -- ---- as que fazem o sistema NÃO ACUSAR o que devia ------------------------

  ('secao_tem_de_fechar', '0133', 'funcao', 'fn_conferir_arvore', null, null,
   'A conferência de que cada seção FECHA com seus componentes não existe: seção com buraco não '
   'abre pendência nenhuma, e o balanço passa por completo porque ninguém somou. É a cegueira que '
   'a 0116 abriu e que ficou cinco sessões sem ser vista.',
   'bloqueante', 250),

  ('reconciliar_arvore', '0133', 'funcao', 'fn_reconciliar_arvore', null, null,
   'A árvore do balanço não é reconciliada por documento: o resultado da conferência existe como '
   'função e não vira achado gravado, então nada chega à tela de pendências.',
   'bloqueante', 260),

  ('coluna_de_dimensao', '0140', 'funcao', 'fn_coluna_de_dimensao', null, null,
   'A guarda de "padrão suspeito" trata coluna de DIMENSÃO (exercício, quantidade, natureza, %) '
   'como se fosse coluna de valor, e acusa o ANO repetido como se fosse número repetido. Foi o '
   'falso positivo da v47.',
   'importante', 270),

  ('limiar_de_auto_aceite_exclui', '0141', 'corpo', 'fn_registrar_campos_extraidos', '-- 0141', null,
   'O limiar de auto-aceite não exclui linha nenhuma e a trilha não diz isso: o sistema declara '
   'ter filtrado por confiança quando nunca filtrou. Número que se apresenta como filtrado sem '
   'ter sido é a família do corte silencioso de leitura.',
   'importante', 280),

  -- ---- o dial e o veredito -------------------------------------------------

  ('veredito_de_producao', '0136', 'funcao', 'fn_veredito_producao', null, null,
   'O painel de autonomia perde o veredito de produção: o dial passa a decidir só com o golden '
   'set, e o piso declaradamente enviesado que a 0136 introduziu deixa de contar.',
   'importante', 290),

  ('veredito_nao_estoura_vazio', '0138', 'corpo', 'fn_veredito_producao',
   'com os dois lados)''::text', null,
   'O painel de autonomia MORRE com "malformed array literal" em vez de abrir — e morre '
   'exatamente no estado de instalação nova, onde ainda não há veredito nenhum para medir. É a '
   'tela que ia dizer o que fazer sendo a tela que não abre.',
   'bloqueante', 300),

  ('dial_sobe_sozinho', '0137', 'funcao', 'fn_dial_auto_promover', null, null,
   'O dial nunca sobe sozinho ao atingir o critério: a promoção automática não existe e todo '
   'avanço volta a depender de alguém lembrar de mudar o nível na tela.',
   'importante', 310),

  ('gatilho_da_promocao', '0137', 'funcao', 'fn_trg_auto_promover_dial', null, null,
   'A função de promoção existe e NADA a chama: o dial continua parado, e a tela mostra um '
   'critério atingido que não produz efeito nenhum. Pior que não ter, porque parece ligado.',
   'importante', 320),

  ('reafirmar_nao_apaga_medicao', '0139', 'corpo', 'fn_mudar_dial', 'v_mede', null,
   'Reafirmar o nível atual APAGA a medição que sustentava aquele nível: o estágio continua no '
   'mesmo lugar e perde a base que o justificava, então a próxima subida é recusada por falta de '
   'medição que existia. O clique mais inofensivo da tela é o que destrói evidência.',
   'importante', 330),

  -- ---- a operação e a modelagem --------------------------------------------

  ('operacao_visivel', '0135', 'funcao', 'fn_operacao_resumo', null, null,
   'Não há como ver a operação: quantas execuções houve, quanto custaram, quais falharam. O '
   'sistema roda e ninguém consegue responder se ele rodou.',
   'importante', 340),

  ('operacao_lotes', '0135', 'funcao', 'fn_operacao_lotes', null, null,
   'A lista de lotes executados não existe — o resumo da operação abre sem o detalhe que explica '
   'o número, e não há caminho da anomalia até a execução que a causou.',
   'importante', 350),

  ('sazonalidade_no_pronto', '0134', 'corpo', 'fn_conferir_modelagem', '-- 0134', null,
   'A modelagem é dada como "pronta" com a sazonalidade em branco: o modelo projeta o ano inteiro '
   'espalhado igualmente pelos meses e o arquivo entregue parece calibrado. Premissa vazia que '
   'não trava o pronto é premissa que ninguém preenche.',
   'importante', 360),

  -- ---- a própria sonda ------------------------------------------------------

  ('sonda_nao_cresce_com_o_dado', '0132', 'corpo', 'fn_instalacao_conferir', 'ou mais', null,
   'A sonda conta a tabela INTEIRA para responder ">= N", e uma delas (lote_execucao) ganha uma '
   'linha por execução e nunca para de crescer. A tela mais usada da casa fica linearmente mais '
   'lenta pelo resto da vida do produto, sem nunca quebrar — lentidão difusa que ninguém sabe a '
   'quem atribuir.',
   'informativo', 370),

  ('cobertura_declarada', '0147', 'tabela', 'instalacao_cobertura', null, null,
   'O catálogo deixa de dizer até onde foi revisado, e volta a poder envelhecer em silêncio — que '
   'é como ele passou 16 migrations parado na 0130 enquanto o banco chegava na 0146.',
   'informativo', 380)

on conflict (chave) do update
  set migration = excluded.migration,
      tipo      = excluded.tipo,
      objeto    = excluded.objeto,
      marcador  = excluded.marcador,
      criterio_seed = excluded.criterio_seed,
      porque    = excluded.porque,
      severidade = excluded.severidade,
      ordem     = excluded.ordem;

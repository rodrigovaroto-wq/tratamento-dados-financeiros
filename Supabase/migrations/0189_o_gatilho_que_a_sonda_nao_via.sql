-- =============================================================================
-- 0189 — O GATILHO QUE A SONDA NÃO VIA
--
-- O DEFEITO. `fn_instalacao_conferir()` (0131, corpo vigente na 0147) confere
-- seis tipos de requisito — tabela, coluna, funcao, corpo, seed, comportamento
-- — e NENHUM deles é "o gatilho está instalado e ligado". Onde o catálogo
-- precisava afirmar isso, ele fez o que dava: catalogou a FUNÇÃO do gatilho
-- como tipo `funcao`. O exemplo já está lá, escrito por quem sentiu o problema
-- sem ainda ter o tipo para resolvê-lo — `gatilho_da_promocao` (0137, objeto
-- `fn_trg_auto_promover_dial`), cujo `porque` diz, literalmente: "A função de
-- promoção existe e NADA a chama: o dial continua parado (...) Pior que não
-- ter, porque parece ligado."
--
-- Essa frase é a prova de que o tipo `funcao` estrutural não serve para
-- gatilho: a FUNÇÃO sobrevive a `drop trigger` e a
-- `alter table ... disable trigger`. Um incidente em produção que rode
-- qualquer um dos dois — um DBA depurando um deadlock, uma migration manual
-- malfeita, uma restauração parcial de backup — desliga a guarda e a sonda
-- continua vendo "presente", porque o que ela mediu nunca foi o vínculo.
-- MEDIDO: derrubar as seis guardas hoje instaladas (`drop trigger` /
-- `disable trigger` / `enable replica trigger`) não muda a contagem de
-- ausentes que `fn_instalacao_conferir()` devolve — o número da medição real
-- está no religamento, abaixo, e no cabeçalho de
-- `Supabase/test/sonda_ve_gatilho.test.sql`.
--
-- O QUE ESTA MIGRATION FAZ, em quatro partes:
--
--   (1) o tipo `gatilho`: `instalacao_requisito_tipo_check` passa a aceitar
--       `'gatilho'`, com `objeto = 'tabela.nome_do_gatilho'`;
--   (2) `fn_instalacao_conferir()` reemitida com o ramo novo — presença ==
--       o gatilho EXISTE na tabela E está habilitado para disparar em sessão
--       normal (ver a decisão sobre `tgenabled` no corpo do ramo);
--   (3) os seis gatilhos não-internos que existem hoje em `main`, catalogados
--       um por um, com o SINTOMA de cada guarda desligada;
--   (4) `instalacao_cobertura` avançada para `0189`.
--
-- O QUE O TIPO `gatilho` NÃO PROMETE, dito antes do primeiro uso — a mesma
-- disciplina da 0131 e da 0147 para os tipos anteriores. Ele responde "o
-- gatilho existe nesta tabela com este nome e está habilitado", e isso NÃO é
-- "ele chama a função certa" nem "ele dispara nos eventos certos"
-- (INSERT/UPDATE/DELETE, BEFORE/AFTER). Um `drop trigger` seguido de um
-- `create trigger` homônimo apontando para outra função passaria. Para essa
-- distinção, como para o corpo de uma função, existe a suíte de
-- comportamento — o item (g) de `sonda_ve_gatilho.test.sql` prova só UM elo
-- da cadeia (rodada congelada recusa update com o gatilho presente, aceita
-- sem ele), que é o que o painel de produção precisa saber, não uma prova de
-- que o gatilho é semanticamente idêntico ao pretendido.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- (1) O TIPO `gatilho`
-- -----------------------------------------------------------------------------

alter table instalacao_requisito
  drop constraint if exists instalacao_requisito_tipo_check;

alter table instalacao_requisito
  add constraint instalacao_requisito_tipo_check
  check (tipo in ('tabela', 'coluna', 'funcao', 'seed', 'comportamento', 'corpo', 'gatilho'));

comment on column instalacao_requisito.tipo is
  'tabela/funcao: o nome. coluna: tabela.coluna. corpo: o nome da função, com marcador de CÓDIGO '
  '(pg_get_functiondef tem de conter o trecho). seed: tabela (criterio_seed diz o quanto se '
  'espera). comportamento: tabela cuja existência de LINHA é a prova — não sonda catálogo, só '
  'efeito. gatilho (0189): tabela.nome_do_gatilho — presente exige o gatilho existir E estar '
  'habilitado para disparar em sessão normal (tgenabled em ''O'' ou ''A''; ver o ramo da sonda '
  'para o porquê de ''R'' não contar). A função do gatilho NÃO serve como prova: ela sobrevive a '
  '`drop trigger` e a `alter table ... disable trigger`, que é exatamente o defeito que este tipo '
  'fecha (ver gatilho_da_promocao, tipo funcao, cujo próprio `porque` descreve o problema).';

-- -----------------------------------------------------------------------------
-- fn_instalacao_conferir — reemitida com o ramo `gatilho`.
--
-- REEMISSÃO A PARTIR DO CORPO DA 0147, que já contém o da 0132 (a contagem
-- limitada ao critério, o texto 'ou mais') — confirmado por
-- `grep -l "function fn_instalacao_conferir" Supabase/migrations/*.sql`, que dá
-- só 0131/0132/0147. Reemitir de uma base mais velha desfaria as duas em
-- silêncio, o mesmo risco que a 0147 já registrou sobre reemitir da 0131.
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
  r            instalacao_requisito;
  v_ok         boolean;
  v_det        text;
  v_n          bigint;
  v_alvo       regclass;
  v_crit       int;
  v_proc       regproc;
  v_src        text;
  v_tg_enabled "char";
  v_tg_fn      text;
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

    elsif r.tipo = 'gatilho' then
      -- 0189: gatilho é catalogado POR SI, não pela função que ele chama.
      --
      -- POR QUE ISTO NÃO CABE NO TIPO `funcao`. A função de um gatilho
      -- SOBREVIVE a `drop trigger` e a `alter table ... disable trigger` — o
      -- exemplo já estava no catálogo antes deste tipo existir, em
      -- `gatilho_da_promocao` (0137): a função `fn_trg_auto_promover_dial`
      -- existe e nada garante que algo a chame. `objeto` aqui é
      -- `tabela.nome_do_gatilho`; a tabela é resolvida primeiro, como em todo
      -- ramo desta função — tabela ausente nunca pode virar exceção que
      -- derruba a sonda inteira.
      v_alvo := to_regclass('public.' || split_part(r.objeto, '.', 1));
      if v_alvo is null then
        v_ok  := false;
        v_det := 'a tabela nem existe';
      else
        select tgenabled, tgfoid::regproc::text
          into v_tg_enabled, v_tg_fn
          from pg_trigger
         where tgrelid = v_alvo
           and tgname  = split_part(r.objeto, '.', 2)
           and not tgisinternal;

        if v_tg_enabled is null then
          v_ok  := false;
          v_det := 'o gatilho não existe na tabela (a função dele pode existir — ela sobrevive ao drop trigger)';
        elsif v_tg_enabled = 'D' then
          v_ok  := false;
          v_det := 'o gatilho existe mas está DESABILITADO (disable trigger) — a guarda não roda';
        elsif v_tg_enabled = 'R' then
          -- 'R' = ENABLE REPLICA TRIGGER. Decisão deliberada, e mais estrita
          -- que `<> 'D'`: um gatilho em modo réplica NÃO dispara com
          -- `session_replication_role = origin`, que é o padrão de toda sessão
          -- normal (é o que o pooler do Supabase usa). Do ponto de vista de
          -- quem depende da guarda rodando na sessão normal, um gatilho em
          -- modo réplica está tão desligado quanto um desabilitado — só que
          -- calado, porque `tgenabled <> 'D'` deixaria passar.
          v_ok  := false;
          v_det := 'o gatilho existe mas só dispara em modo réplica — na sessão normal a guarda não roda';
        elsif v_tg_enabled in ('O', 'A') then
          -- 'O' = ENABLE (origin, o padrão) · 'A' = ENABLE ALWAYS (dispara em
          -- origin e em réplica). As duas rodam em sessão normal — é só isso
          -- que este ramo promete. Ele NÃO confere se o gatilho chama a
          -- função certa nem em quais eventos (INSERT/UPDATE/DELETE) — só que
          -- existe e dispara. `v_tg_fn` entra no detalhe por informação, sem
          -- afetar `v_ok`.
          v_ok  := true;
          v_det := format('gatilho habilitado (chama %s)', coalesce(v_tg_fn, '?'));
        else
          -- Não deveria acontecer — `tgenabled` só tem estes quatro valores —
          -- mas a sonda nunca assume "presente" por omissão de um `case`.
          v_ok  := false;
          v_det := format('estado de gatilho desconhecido: %s', v_tg_enabled);
        end if;
      end if;

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
  'do que ela existe para medir. Desde a 0147 confere também o CORPO da função (tipo=corpo). Desde '
  'a 0189 confere também GATILHO (tipo=gatilho): existência na tabela E tgenabled em (''O'',''A'') '
  '— a função do gatilho sobrevive a drop trigger/disable trigger e por isso NUNCA prova, sozinha, '
  'que a guarda está ligada.';

grant execute on function fn_instalacao_conferir() to authenticated;

-- -----------------------------------------------------------------------------
-- (3) OS SEIS GATILHOS NÃO-INTERNOS DE `main`, catalogados um por um.
--
-- Levantados agora por `select tgrelid::regclass, tgname from pg_trigger where
-- not tgisinternal` contra um banco montado do zero pelas migrations até a
-- 0186 (a mais nova antes desta). São exatamente seis; nenhum outro existe em
-- `main` hoje.
--
-- OS DOIS GATILHOS DA F1.7 (`entidade_controlador.trg_entidade_controlador_
-- soma_maxima`, `entidade.trg_entidade_forma_de_controle_tem_vinculo`) NÃO
-- ENTRAM AQUI: eles vivem no PR #238, ainda não mergeado em `main`, e
-- catalogá-los agora faria `instalacao.test.sql` reprovar neste banco (que
-- não os tem). QUEM MERGEAR/RENUMERAR A F1.7 deve acrescentá-los com
-- `tipo = 'gatilho'`, mesmo padrão deste bloco — `objeto` é
-- `entidade_controlador.trg_entidade_controlador_soma_maxima` e
-- `entidade.trg_entidade_forma_de_controle_tem_vinculo`.
--
-- SEVERIDADE: as quatro guardas do golden set (rodada/documento/rótulo/campo
-- congelados) e o gatilho de entidade ambígua ficam 'importante', não
-- 'bloqueante' — nenhuma delas impede o sistema de rodar; o que elas impedem,
-- se desligadas, é que uma pendência abra ou que um dado protegido mude sem
-- ser notado. É a mesma família de dano dos outros requisitos 'importante' do
-- catálogo (0142–0146): número errado silencioso, não painel fora do ar.
-- `gatilho_da_promocao_dispara` segue a MESMA severidade do requisito
-- `gatilho_da_promocao` que ele complementa (0137, 'importante').
-- -----------------------------------------------------------------------------

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, porque, severidade, ordem) values

  ('gatilho_guarda_rodada_congelada', '0126', 'gatilho',
   'golden_rodada.trg_golden_rodada_imutavel', null,
   'Uma rodada golden CONGELADA aceita descongelar, mudar de nome ou de taxonomia — o número que '
   'o dial de autonomia mede deixa de ser reprodutível, porque o conjunto que o sustenta pode ter '
   'mudado depois da medição sem deixar rastro.',
   'importante', 790),

  ('gatilho_guarda_documento_congelada', '0126', 'gatilho',
   'golden_documento.trg_golden_documento_congelada', null,
   'Uma rodada golden CONGELADA aceita documento novo dentro dela — o conjunto que sustentou uma '
   'medição do dial deixa de ser o mesmo conjunto quando alguém for reproduzi-la.',
   'importante', 791),

  ('gatilho_guarda_rotulo_congelada', '0126', 'gatilho',
   'golden_rotulo.trg_golden_rotulo_congelada', null,
   'Uma rodada golden CONGELADA aceita rótulo novo — o gabarito contra o qual o sistema é medido '
   'muda depois de a rodada já ter produzido um veredito, e o veredito anterior fica '
   'silenciosamente desatualizado.',
   'importante', 792),

  ('gatilho_guarda_campo_congelada', '0126', 'gatilho',
   'golden_campo.trg_golden_campo_congelada', null,
   'Uma rodada golden CONGELADA aceita campo novo — mesmo defeito do rótulo: o gabarito de uma '
   'medição já fechada muda por baixo, e ninguém que olhar o resultado antigo vai saber.',
   'importante', 793),

  ('gatilho_da_promocao_dispara', '0137', 'gatilho',
   'decisao.trg_auto_promover_dial', null,
   'A promoção automática do dial existe como função e nada garante que ela seja CHAMADA: um '
   '`drop trigger` ou `disable trigger` nesta guarda faz o painel mostrar um critério atingido que '
   'não produz efeito nenhum — pior que não ter promoção automática, porque parece ligada. (Este '
   'requisito complementa `gatilho_da_promocao`, tipo funcao/0137, que confere só a função — os '
   'dois juntos é que fecham o caso: função existe E está de fato amarrada ao gatilho.)',
   'importante', 794),

  ('gatilho_entidade_ambigua_dispara', '0153', 'gatilho',
   'documento.trg_entidade_ambigua', null,
   'A pendência de entidade ambígua depende deste gatilho para abrir — sem ele, um documento que '
   'chega com entidade ambígua não gera pendência nenhuma, e a ambiguidade fica resolvida em '
   'silêncio pelo primeiro palpite, sem que ninguém decida.',
   'importante', 795),

  -- ---- o requisito CORPO que prova que esta própria reemissão está no ar ----
  --
  -- 0189, regra 2 do CLAUDE.md aplicada à própria sonda: um banco com a 0189
  -- aplicada pela metade (a constraint aceita 'gatilho', mas a função ainda é
  -- a de antes, de outra branch ou de um apply parcial) tem de acusar isso,
  -- não silenciar. `Supabase/test/sonda_marcador_e_codigo.test.sql` exige que
  -- todo marcador NOVO de tipo `corpo` seja código, não comentário nem prosa
  -- — `v_tg_enabled in ('O', 'A')` é o trecho de código deste ramo, não um
  -- número de migration.
  ('sonda_ve_gatilho', '0189', 'corpo', 'fn_instalacao_conferir',
   'v_tg_enabled in (''O'', ''A'')',
   'A sonda de instalação não vê gatilho desligado: `drop trigger`/`disable trigger` numa guarda '
   'do golden set ou da promoção do dial passa despercebido, porque o único requisito que existia '
   'para essas guardas era sobre a FUNÇÃO — que sobrevive aos dois.',
   'importante', 796)

on conflict (chave) do update
  set migration = excluded.migration,
      tipo      = excluded.tipo,
      objeto    = excluded.objeto,
      marcador  = excluded.marcador,
      porque    = excluded.porque,
      severidade = excluded.severidade,
      ordem     = excluded.ordem;

-- -----------------------------------------------------------------------------
-- (4) A COBERTURA DECLARADA
-- -----------------------------------------------------------------------------
update instalacao_cobertura
   set ate_migration = '0189', revisado_em = current_date,
       observacao = 'A 0189 acrescenta o tipo gatilho (instalacao_requisito_tipo_check + o ramo '
         'novo de fn_instalacao_conferir) e cataloga os seis gatilhos não-internos de main: as '
         'quatro guardas de imutabilidade do golden set (0126), o gatilho de auto-promoção do dial '
         '(0137, complementa gatilho_da_promocao que já existia como tipo funcao) e o gatilho de '
         'entidade ambígua (0153). A função do gatilho sobrevive a drop trigger/disable trigger, '
         'então nenhum desses seis tinha prova real de estar LIGADO antes desta migration — só de '
         'a função existir. Os dois gatilhos da F1.7 (PR #238, não mergeado) ficam de fora até o '
         'merge; quem mergear os acrescenta com o mesmo tipo gatilho.'
 where id = true;

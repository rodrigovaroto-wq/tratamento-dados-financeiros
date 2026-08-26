-- =============================================================================
-- 0149 — O FATO MATERIAL ENDURECIDO: sete defeitos achados na auditoria da 0148
--
-- A 0148 entregou o canal e passou em 16 asserts. Depois dela, o canal foi
-- auditado de forma ADVERSARIAL — procurando quebrá-lo em vez de confirmá-lo —
-- e sete defeitos apareceram. Cinco deles são silenciosos, que é a família que
-- este produto existe para não ter. Estão listados aqui na ordem da gravidade,
-- cada um com o que a medição mostrou.
--
-- ---------------------------------------------------------------------------
-- (1) O RLS RECUSAVA A GRAVAÇÃO. MEDIDO: `set local role authenticated` +
--     `fn_registrar_fatos(...)` devolve
--     `new row violates row-level security policy for table "documento_fato"`
--     [42501]. A 0148 deu à tabela apenas política de SELECT, enquanto
--     `campo_extraido` — que o MESMO pipeline escreve — tem `authenticated_all`
--     com `with check`. E a 0148 ainda deu `grant execute` da função ao papel
--     `authenticated`: uma permissão que a política não honra. Funcionava só
--     porque o n8n conecta como dono da tabela, que ignora RLS — ou seja, o
--     canal dependia de um detalhe da credencial, não de uma decisão.
--
-- (2) UMA PÁGINA ABSURDA DERRUBAVA O DIAGNÓSTICO INTEIRO. MEDIDO: `pagina` =
--     99999999999 levanta `value out of range for type integer` [22003]. E o
--     estrago não para no fato: `fn_registrar_fatos` roda na MESMA query que
--     `fn_registrar_diagnostico` (foi decisão da 0148, para não acrescentar nó),
--     então a exceção aborta a query e o DIAGNÓSTICO do documento não é gravado.
--     Um número de página alucinado pelo modelo custaria o estágio inteiro.
--
-- (3) VERSÃO INEXISTENTE FAZIA O MESMO. MEDIDO: violação de chave estrangeira
--     [23503], mesma consequência da (2).
--
-- (4) O REENVIO DE ARQUIVO FAZIA OS FATOS SUMIREM. MEDIDO: com a v1 carregando
--     um covenant e a v2 recém-criada e ainda não processada,
--     `fn_fatos_do_caso` devolve ZERO. A 0148 escolhia a versão por
--     `n_versao desc`, sem perguntar se ela foi processada. O alerta mais
--     importante do mandato desaparecia da tela durante um reenvio, sem nada
--     acusar.
--
--     E A CORREÇÃO ÓBVIA ERA A ERRADA, o que vale registrar: o resto do sistema
--     escolhe versão com `fn_versao_com_extracao`, que exige linha em
--     `campo_extraido`. Os documentos 33 e 34 extraem ZERO linha por natureza —
--     são texto corrido — então usá-la esconderia os fatos exatamente dos
--     documentos que os têm. Foi medido antes de virar código.
--
--     A regra certa precisa distinguir "versão ainda não processada" de "versão
--     processada e sem fatos" — a primeira deve cair para a versão anterior, a
--     segunda não, porque um fato revogado por releitura não pode voltar. Isso
--     não se infere: se declara. Daí `documento_versao.fatos_avaliados_em`.
--
-- (5) A ORDEM DA LISTA ERA INDETERMINADA. MEDIDO: três fatos gravados no mesmo
--     `insert` compartilham UM único `criado_em` (now() é estável na
--     transação), e o `order by cat.ordem, cat.rotulo, f.criado_em` não desempata
--     — a mesma lista podia sair em ordens diferentes entre duas leituras. Numa
--     tela em que a ordem SIGNIFICA gravidade, isso corrói a confiança sem
--     nunca dar erro.
--
-- (6) `confianca` NUNCA ERA PREENCHIDA. MEDIDO: zero linhas com valor. O schema
--     da IA não pede o campo e o parse não o mapeia. A coluna SAI, e a decisão
--     é deliberada: a evidência deste canal é o TRECHO LITERAL, e uma confiança
--     auto-declarada pelo modelo num alerta que vai ao comitê é exatamente o
--     número sem lastro que esta casa passa o tempo removendo. Melhor não ter o
--     campo do que ter um campo que promete medição e entrega opinião.
--
-- (7) O SÉTIMO NÃO É DE BANCO e está corrigido em `n8n/lib/cobertura.mjs`: em
--     documento fatiado, `Juntar Blocos` mantinha só o diagnóstico do bloco 1, e
--     os fatos declarados nos blocos 2..N eram descartados em silêncio. Fica
--     citado aqui porque é o mesmo canal e a mesma auditoria.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- (1) A POLÍTICA — a mesma de `campo_extraido`, pela mesma razão.
-- -----------------------------------------------------------------------------
drop policy if exists documento_fato_read on documento_fato;
drop policy if exists documento_fato_authenticated_all on documento_fato;

create policy documento_fato_authenticated_all on documento_fato
  to authenticated using (true) with check (true);

grant select, insert, update, delete on documento_fato to authenticated;

comment on table documento_fato is
  'Fato material declarado por um documento EM TEXTO — covenant rompido, ressalva de auditoria, '
  'continuidade operacional. Não é pendência: pendência significa "há algo a corrigir", e um '
  'covenant rompido não é defeito do dado, é o dado. Nasceu da v48, onde as Notas Explicativas e o '
  'Parecer do Auditor entravam, eram classificados e ficavam mudos. A política de escrita é a mesma '
  'de campo_extraido (0149): a 0148 só dava SELECT, e a gravação funcionava por acidente da '
  'credencial em vez de por decisão.';

-- -----------------------------------------------------------------------------
-- (6) A COLUNA QUE NUNCA RECEBEU NADA
--
-- Segura de remover agora e nunca mais: a tabela nasceu na 0148, e em produção
-- ela tem zero linha. Adiar isso seria carregar a promessa vazia para dentro do
-- primeiro dado real.
-- -----------------------------------------------------------------------------
alter table documento_fato drop column if exists confianca;

-- -----------------------------------------------------------------------------
-- (4) O MARCADOR DE "ESTA VERSÃO JÁ FOI LIDA À PROCURA DE FATOS"
--
-- POR QUE UMA COLUNA E NÃO UMA INFERÊNCIA. Sem ela só há duas perguntas
-- possíveis — "esta versão tem fatos?" e "esta versão tem linhas?" — e nenhuma
-- das duas distingue os dois estados que importam:
--
--   • versão nova, ainda não processada  → os fatos da versão ANTERIOR valem;
--   • versão processada, nenhum fato     → não há fatos, e a anterior NÃO volta.
--
-- Inferir daria a resposta certa no primeiro caso e errada no segundo — um
-- covenant revogado por releitura reaparecendo na tela. É o mesmo motivo pelo
-- qual `null` não é `[]` em `fn_registrar_fatos`.
-- -----------------------------------------------------------------------------
alter table documento_versao
  add column if not exists fatos_avaliados_em timestamptz;

comment on column documento_versao.fatos_avaliados_em is
  'Quando esta versão foi lida à procura de fatos materiais (0149). NULL = ainda não foi — e nesse '
  'caso os fatos da versão anterior continuam valendo na tela. Preenchida mesmo quando a leitura '
  'não achou nada: é o que distingue "sem fatos" de "não processada".';

-- -----------------------------------------------------------------------------
-- fn_registrar_fatos — reemitida com (1), (2), (3) e (4).
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
  v_pag_ruim  int := 0;
  v_erro      text := null;
  v_estado    text := null;
begin
  if p_documento_versao_id is null then
    return jsonb_build_object('erro', 'documento_versao_id nulo');
  end if;

  -- Sem chave `fatos` na resposta (workflow antigo, ou resposta que falhou) NÃO
  -- é o mesmo que "este documento não tem fato nenhum". Apagar os fatos de uma
  -- versão porque a chave veio ausente destruiria trilha por causa de um
  -- workflow desatualizado — o mesmo modo de falha do `Gravar Campos` que
  -- desligou a reconciliação por onze dias. E NÃO marca como avaliada: não foi.
  if p_fatos is null or jsonb_typeof(p_fatos) <> 'array' then
    return jsonb_build_object('gravados', 0, 'sem_prova', 0, 'tipo_desconhecido', 0,
                              'nota', 'sem lista de fatos na resposta — nada foi tocado');
  end if;

  -- 0149 (2)(3): O BLOCO PROTEGIDO.
  --
  -- Esta função roda na MESMA query que `fn_registrar_diagnostico`. Qualquer
  -- exceção aqui aborta a query e o documento perde o DIAGNÓSTICO — um número
  -- de página alucinado custando o estágio inteiro. O `exception` transforma
  -- isso em recusa DECLARADA no retorno, e o retorno é uma coluna da query, que
  -- aparece na execução do n8n.
  --
  -- Declarada, e não engolida: a diferença é o campo `erro` abaixo. Recusa que
  -- não se conta vira ausência, e ausência parece "este documento não disse
  -- nada" — o estado exato que este canal existe para acabar.
  --
  -- O bloco cobre o DELETE junto com o INSERT de propósito: se o insert falhar,
  -- o savepoint desfaz o delete também, e a versão fica com os fatos que já
  -- tinha em vez de ficar sem nenhum.
  begin
    delete from documento_fato where documento_versao_id = p_documento_versao_id;

    insert into documento_fato (documento_versao_id, tipo, trecho, pagina, leitura)
    select p_documento_versao_id,
           f->>'tipo',
           btrim(f->>'trecho'),
           -- 0149 (2): página fora do plausível vira NULL em vez de estourar.
           -- O teste é feito em `numeric`, que aguenta o absurdo; só depois
           -- vira `int`. Página zero ou negativa também não existe.
           case when jsonb_typeof(f->'pagina') = 'number'
                 and (f->>'pagina')::numeric between 1 and 100000
                then (f->>'pagina')::int end,
           nullif(btrim(coalesce(f->>'leitura', '')), '')
      from jsonb_array_elements(p_fatos) f
     where length(btrim(coalesce(f->>'trecho', ''))) >= 20
       and exists (select 1 from fato_tipo_catalogo c where c.tipo = f->>'tipo');
    get diagnostics v_gravados = row_count;
  exception when others then
    v_erro   := sqlerrm;
    v_estado := sqlstate;
    v_gravados := 0;
  end;

  select count(*)::int into v_sem_prova
    from jsonb_array_elements(p_fatos) f
   where length(btrim(coalesce(f->>'trecho', ''))) < 20;

  select count(*)::int into v_tipo_ruim
    from jsonb_array_elements(p_fatos) f
   where length(btrim(coalesce(f->>'trecho', ''))) >= 20
     and not exists (select 1 from fato_tipo_catalogo c where c.tipo = f->>'tipo');

  -- A página descartada é CONTADA à parte: o fato entra (o trecho é a
  -- evidência, não a página), mas quem confere merece saber que o número não
  -- era utilizável em vez de achar que o documento não tinha página.
  select count(*)::int into v_pag_ruim
    from jsonb_array_elements(p_fatos) f
   where jsonb_typeof(f->'pagina') = 'number'
     and (f->>'pagina')::numeric not between 1 and 100000;

  -- 0149 (4): a versão foi LIDA. Vale mesmo com zero fatos gravados — é
  -- exatamente esse caso que a coluna existe para registrar. Não vale quando
  -- houve erro: aí a leitura não chegou ao fim.
  if v_erro is null then
    update documento_versao set fatos_avaliados_em = now()
     where id = p_documento_versao_id;
  end if;

  return jsonb_build_object('gravados', v_gravados,
                            'sem_prova', v_sem_prova,
                            'tipo_desconhecido', v_tipo_ruim,
                            'pagina_descartada', v_pag_ruim,
                            'erro', v_erro,
                            'sqlstate', v_estado);
end;
$$;

comment on function fn_registrar_fatos(uuid, jsonb) is
  'Grava os fatos materiais de uma versão, substituindo os anteriores dela, e marca a versão como '
  'avaliada. Recusa entrada sem trecho literal e tipo fora do catálogo, e CONTA cada recusa no '
  'retorno. Desde a 0149 NÃO levanta exceção: ela roda na mesma query do diagnóstico, e uma página '
  'absurda derrubava o registro do diagnóstico junto — o erro passa a voltar declarado no retorno.';

grant execute on function fn_registrar_fatos(uuid, jsonb) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_fatos_do_caso — reemitida com (4), (5) e (6).
-- -----------------------------------------------------------------------------
-- O `drop` É OBRIGATÓRIO, e não é higiene: a coluna `confianca` sai do retorno,
-- e `create or replace` NÃO muda o tipo de retorno de uma função existente
-- ("cannot change return type of existing function"). Sem ele a migration morre
-- no meio — e foi assim que ela morreu na primeira tentativa, deixando a tabela
-- já alterada e a função velha no lugar. O `drop` leva o `grant` junto, por isso
-- ele é reemitido logo abaixo.
drop function if exists fn_fatos_do_caso(uuid);

create function fn_fatos_do_caso(p_caso_id uuid)
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
  leitura             text
)
language sql
stable
as $$
  -- 0149 (4): a versão que VALE é a mais nova que foi AVALIADA — não a mais
  -- nova, e não a que tem linha extraída.
  --
  -- Não a mais nova: um reenvio ainda não processado apagava da tela os fatos
  -- da versão anterior (medido: zero fatos com um covenant gravado).
  -- Não `fn_versao_com_extracao`: ela exige linha em `campo_extraido`, e os
  -- documentos que mais têm fatos — notas explicativas, parecer de auditoria —
  -- extraem ZERO linha por natureza.
  with corrente as (
    select distinct on (dv.documento_id)
           dv.id, dv.documento_id, dv.arquivo_ref, dv.nome_original
      from documento_versao dv
      join documento d on d.id = dv.documento_id
     where d.caso_id = p_caso_id
       and dv.fatos_avaliados_em is not null
     order by dv.documento_id, dv.n_versao desc
  )
  select f.id, c.documento_id, f.documento_versao_id,
         coalesce(c.nome_original, c.arquivo_ref),
         d.tipo_taxonomia,
         f.tipo, cat.rotulo, cat.severidade, cat.porque,
         f.trecho, f.pagina, f.leitura
    from documento_fato f
    join corrente c            on c.id = f.documento_versao_id
    join documento d           on d.id = c.documento_id
    join fato_tipo_catalogo cat on cat.tipo = f.tipo
   -- 0149 (5): `f.id` desempata. Fatos gravados no mesmo insert compartilham um
   -- único `criado_em`, e sem o desempate a MESMA lista podia sair em ordens
   -- diferentes entre duas leituras — numa tela em que a ordem significa
   -- gravidade.
   order by cat.ordem, cat.rotulo, f.criado_em, f.id;
$$;

comment on function fn_fatos_do_caso(uuid) is
  'Os fatos materiais do mandato, da versão mais nova que foi AVALIADA (0149), ordenados por '
  'gravidade com desempate estável. Versão não avaliada não apaga o que a anterior achou — era o '
  'que fazia os alertas sumirem durante um reenvio de arquivo.';

grant execute on function fn_fatos_do_caso(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- O CATÁLOGO DE INSTALAÇÃO — o portão da 0147 cobrando pela segunda vez.
-- -----------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('fato_versao_avaliada', '0149', 'coluna', 'documento_versao.fatos_avaliados_em', null, null,
   'Os fatos materiais SOMEM da tela do mandato assim que alguém reenvia um arquivo: sem a coluna, '
   'a tela escolhe a versão mais nova sem perguntar se ela chegou a ser lida, e o covenant que a '
   'versão anterior achou desaparece sem nada acusar.',
   'importante', 420),
  ('fato_grava_sem_derrubar', '0149', 'corpo', 'fn_registrar_fatos', '-- 0149 (2)', null,
   'Uma página absurda vinda do modelo (99999999999) derruba a gravação — e como ela roda na mesma '
   'query do diagnóstico, o documento perde o DIAGNÓSTICO inteiro junto. O sintoma é um documento '
   'sem entidade, sem tipo confirmado e sem resumo, sem explicação nenhuma na tela.',
   'bloqueante', 430),
  ('fato_escrita_permitida', '0149', 'corpo', 'fn_fatos_do_caso', '0149 (4)', null,
   'A tela volta a escolher a versão errada e a ordem da lista volta a ser indeterminada — numa '
   'tela em que a ordem significa gravidade.',
   'importante', 440)
on conflict (chave) do update
  set migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
      marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
      porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0149',
       revisado_em   = current_date,
       observacao    = 'Revisão de 26/08/2026: a 0149 endurece o canal de fato material depois de '
                       'uma auditoria adversarial da 0148 — sete defeitos, cinco silenciosos. Três '
                       'requisitos novos: a coluna que distingue versão não avaliada de versão sem '
                       'fatos, e o corpo das duas funções reemitidas.'
 where id;

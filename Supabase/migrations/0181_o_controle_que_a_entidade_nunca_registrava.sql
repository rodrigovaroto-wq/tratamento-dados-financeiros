-- =============================================================================
-- 0181 — fatia 1.5 do plano F1: `entidade.controladora_id` + `percentual_participacao`,
--        a FK preparada que a F4 vai consumir
--
-- O DEFEITO, medido em 18/09/2026 contra o schema (seção 12.1 de
-- `Arquitetura do Sistema/3 Estado e Execução/ARQUITETURA_ALVO_E_ROADMAP.md`: "participacao
-- (coluna) — não existe"): não há, em NENHUMA entidade deste banco, o registro de QUEM a
-- controla. `papel_no_grupo` (0179) diz o que a entidade É (holding/operacional/veículo/
-- coligada/fora do perímetro); `perimetro` (0180) diz o que ENTRA no combinado, por escopo e
-- por data. Nenhuma das duas registra a HIERARQUIA entre entidades — "a Holding controla a SPE
-- em 60%" não tem onde morar. Sem isso, consolidação (somar as controladas) e intercompany
-- (eliminar saldo entre controladora e controlada) não têm de onde ler quem é filha de quem —
-- é exatamente o que o roadmap nomeia: "é a fatia que destrava consolidação e intercompany".
--
-- A DECISÃO DE PRODUTO JÁ TOMADA (mesmo raciocínio da 0179/0180 — não repetida a cada sessão):
-- **este modelo é deliberadamente simples, e a simplicidade é uma LIMITAÇÃO documentada, não um
-- esquecimento.** `controladora_id` é uma FK self-referencing simples: cada entidade tem NO
-- MÁXIMO uma controladora DIRETA registrada aqui. Isto NÃO é um grafo completo de participação
-- societária — não modela sócios minoritários múltiplos, participação cruzada, nem percentuais
-- que somem menos de 100% entre vários sócios. É a CADEIA DE CONTROLE que a F4 vai percorrer
-- subindo por `controladora_id` (holding → subholding → SPE), nada mais. Se uma sessão futura
-- precisar de mais que isso (sócios múltiplos, participação cruzada), é decisão de F4 com um
-- caso real na mão — não desta migration, que não tem hoje nenhum contrato social lido pelo
-- pipeline para justificar um modelo mais rico (regra 1 do CLAUDE.md: estrutura sem medição).
--
-- O RISCO REAL DE UM SELF-FK: CICLO. "A controla B controla A" quebraria qualquer código futuro
-- que suba a cadeia (`while controladora_id is not null`) num loop infinito — e é exatamente o
-- tipo de consumidor que a F4 vai escrever. Por isso o caminho de escrita
-- (`fn_entidade_definir_participacao`) nunca grava sem primeiro perguntar a
-- `fn_entidade_criaria_ciclo_participacao` (item 2 abaixo) se o ciclo se fecharia. O limite de
-- 50 saltos nela (e no consumidor de leitura, item 4) existe para o caso em que dado sujo já
-- tenha um ciclo por outra via (ex.: um `update` direto que ignorasse a função) — 50 é
-- headroom generoso para qualquer cadeia real de holding (mandatos deste projeto têm, no
-- máximo, poucas dezenas de entidades), e evita loop infinito em vez de confiar que nunca vai
-- acontecer.
--
-- MESMA DOUTRINA DA 0179/0180: nenhuma FK é preenchida automaticamente. Não há contrato social
-- lido pelo pipeline hoje — inferir hierarquia de participação a partir de nome, CNPJ ou
-- qualquer outro sinal seria ausência virando dado (regra 1). `controladora_id` é NULL por
-- padrão em toda entidade nova, e só `fn_entidade_definir_participacao` (chamada por um
-- humano/analista) escreve aqui.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2), em `Supabase/test/entidade_participacao.test.sql`: MEDIDA de
-- fato (não estimada) — com a chamada a `fn_entidade_criaria_ciclo_participacao` comentada
-- dentro de `fn_entidade_definir_participacao` (a função grava direto, sem perguntar) e
-- `teste_assert_0181` trocado temporariamente para não abortar no primeiro assert (`raise
-- notice` em vez de `raise exception`) e contar todos — **4 dos 29 asserts do arquivo
-- reprovaram**: os 2 do bloco de ciclo de 2 níveis ("a tentativa de ciclo de 2 níveis levanta
-- exceção" e "nada foi gravado — A continua sem controladora") e os 2 do bloco de ciclo de 3
-- níveis ("a tentativa de ciclo de 3 níveis levanta exceção" e "nada foi gravado — A continua
-- sem controladora, o topo da cadeia real") — sem a guarda, `fn_entidade_definir_participacao`
-- GRAVA o ciclo em vez de recusar (a chamada arriscada não levanta exceção, então a controladora
-- da entidade A é sobrescrita de verdade). Os outros 25 passam com ou sem a correção — inclusive
-- os dois asserts que checam se B/C na cadeia real permaneceram intocados: com a guarda
-- desligada, só o UPDATE de A muda, então B e C continuam corretos por não terem sido tocados,
-- não porque a guarda os protegeu (não discriminam esta regressão). Religada a guarda, os 29
-- asserts passam.
--
-- **Pronto** (a fatia não lista "pronto quando" no roadmap — mesma leveza deliberada da 1.4):
-- as colunas existem, com os dois `check`s óbvios (auto-referência, percentual em (0,100]), a
-- guarda de ciclo é testável isoladamente, o caminho de escrita
-- (`fn_entidade_definir_participacao`) é explícito e chamado por humano, e o consumidor mínimo
-- (`fn_entidade_cadeia_controladora`) prova que a FK serve para algo além de existir. Aplicar em
-- produção e registrar a hierarquia real dos casos é decisão de uma sessão seguinte, contra a
-- sonda (migration escrita ≠ aplicada).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- (1) AS COLUNAS E OS CHECKS ÓBVIOS.
-- -----------------------------------------------------------------------------

alter table entidade add column controladora_id uuid references entidade(id);
alter table entidade add column percentual_participacao numeric(6,3);

comment on column entidade.controladora_id is
  '0181 (fatia 1.5 do plano F1): a controladora DIRETA desta entidade — no máximo UMA, aqui. '
  'NÃO é um grafo completo de participação societária: sócios minoritários múltiplos e '
  'participação cruzada NÃO cabem neste modelo simples, e isso é deliberado (ver cabeçalho da '
  '0181) — é a cadeia de controle que a F4 (consolidação/intercompany) vai percorrer subindo por '
  'esta coluna. NULL por padrão em toda entidade nova (fn_upsert_entidade nunca o passa no '
  'insert) — não há contrato social lido pelo pipeline hoje para inferir isto automaticamente '
  '(regra 1 do CLAUDE.md). Só `fn_entidade_definir_participacao` escreve aqui, e só depois de '
  'perguntar a `fn_entidade_criaria_ciclo_participacao` se o ciclo se fecharia.';

comment on column entidade.percentual_participacao is
  '0181: o percentual que `controladora_id` detém desta entidade, em (0, 100]. NULL sempre que '
  '`controladora_id` for NULL (percentual sem controladora não significa nada — '
  '`fn_entidade_definir_participacao` recusa a combinação inversa). `numeric(6,3)`: até '
  '999,999% de headroom não faz sentido para um percentual real, mas a precisão cobre 100,000 '
  'com folga de formatação sem exigir um tipo mais estreito — ajustar depois é uma migration '
  'aditiva se algum dado real pedir mais casas.';

alter table entidade add constraint entidade_nao_controla_a_si_mesma
  check (controladora_id is null or controladora_id <> id);

comment on constraint entidade_nao_controla_a_si_mesma on entidade is
  '0181: recusa `controladora_id = id` mesmo por INSERT/UPDATE direto, sem passar pela função — '
  'é o ciclo de UM salto (o caso trivial que `fn_entidade_criaria_ciclo_participacao` também '
  'pega, mas o `check` protege o caminho que não chama a função nenhuma).';

alter table entidade add constraint entidade_percentual_valido
  check (percentual_participacao is null or
         (percentual_participacao > 0 and percentual_participacao <= 100));

comment on constraint entidade_percentual_valido on entidade is
  '0181: percentual de participação tem de estar em (0, 100] — zero ou negativo não é '
  'participação, e mais de 100% não existe. Protege INSERT/UPDATE direto, mesma doutrina do '
  '`perimetro_intervalo_valido` da 0180.';

-- -----------------------------------------------------------------------------
-- (2) A GUARDA DE CICLO — separada e testável, chamada por (3) ANTES de gravar.
--
-- Percorre `controladora_id` a partir de `p_nova_controladora_id` subindo a cadeia; se
-- `p_entidade_id` aparecer nela, gravar `p_entidade_id.controladora_id = p_nova_controladora_id`
-- fecharia o ciclo (p_entidade_id → ... → p_nova_controladora_id → p_entidade_id). Limite de 50
-- saltos: headroom generoso para qualquer cadeia real deste projeto, e evita loop infinito se
-- algum dado sujo já tiver ciclo por outra via (ex.: um update direto que ignorasse esta
-- função) — a mesma decisão de profundidade é reaproveitada em (4), o consumidor de leitura.
-- -----------------------------------------------------------------------------

create function public.fn_entidade_criaria_ciclo_participacao(p_entidade_id uuid,
                                                                p_nova_controladora_id uuid)
RETURNS boolean
    LANGUAGE plpgsql
    STABLE
    AS $$
declare
  v_atual  uuid := p_nova_controladora_id;
  v_saltos int  := 0;
begin
  while v_atual is not null and v_saltos < 50 loop
    if v_atual = p_entidade_id then
      return true;
    end if;
    select controladora_id into v_atual from entidade where id = v_atual;
    v_saltos := v_saltos + 1;
  end loop;
  return false;
end;
$$;

comment on function public.fn_entidade_criaria_ciclo_participacao(uuid, uuid) IS
  '0181: sobe a cadeia de `controladora_id` a partir de `p_nova_controladora_id` e devolve true '
  'se `p_entidade_id` aparecer nela — nesse caso, torná-la controladora de `p_entidade_id` '
  'fecharia um ciclo. Limite de 50 saltos (mesmo limite do consumidor de leitura, item 4) evita '
  'loop infinito com dado sujo. Chamada por `fn_entidade_definir_participacao` ANTES de gravar '
  '— é a MEDIÇÃO NÃO-VAZIA desta migration (ver cabeçalho).';

grant execute on function public.fn_entidade_criaria_ciclo_participacao(uuid, uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- (3) O CAMINHO DE ESCRITA — mesma doutrina da 0179/0180: humano decide, nunca inferência
-- automática. `p_controladora_id` NULL remove a controladora (ex.: a holding do topo) — e
-- exige `p_percentual` também NULL, porque percentual sem controladora não significa nada.
-- Reatribuir é permitido — é o ESTADO ATUAL (como `fn_entidade_definir_papel_no_grupo`, 0179);
-- o histórico mora em evento_auditoria, não numa coluna imutável.
-- -----------------------------------------------------------------------------

create function public.fn_entidade_definir_participacao(p_entidade_id uuid, p_controladora_id uuid,
                                                          p_percentual numeric, p_autor text)
RETURNS uuid
    LANGUAGE plpgsql
    AS $$
declare
  v_caso_entidade         uuid;
  v_caso_controladora     uuid;
  v_controladora_anterior uuid;
  v_percentual_anterior   numeric;
begin
  if p_controladora_id is null and p_percentual is not null then
    raise exception 'percentual (%) sem controladora não significa nada — informe p_percentual '
                     'null junto com p_controladora_id null', p_percentual;
  end if;

  select caso_id, controladora_id, percentual_participacao
    into v_caso_entidade, v_controladora_anterior, v_percentual_anterior
    from entidade where id = p_entidade_id;

  if v_caso_entidade is null then
    raise exception 'entidade % não encontrada', p_entidade_id;
  end if;

  if p_controladora_id is not null then
    select caso_id into v_caso_controladora from entidade where id = p_controladora_id;
    if v_caso_controladora is null then
      raise exception 'controladora % não encontrada', p_controladora_id;
    end if;
    if v_caso_controladora <> v_caso_entidade then
      raise exception 'controladora % não pertence ao mesmo caso que a entidade %',
        p_controladora_id, p_entidade_id;
    end if;

    -- A MEDIÇÃO NÃO-VAZIA desta migration (ver cabeçalho): sem esta chamada, um ciclo de 2 ou
    -- 3 níveis seria GRAVADO em vez de recusado, e um consumidor futuro que suba a cadeia
    -- (fn_entidade_cadeia_controladora ou qualquer código que a F4 escrever) entraria em loop
    -- até o limite de profundidade, escondendo o defeito em vez de o recusar na escrita.
    if fn_entidade_criaria_ciclo_participacao(p_entidade_id, p_controladora_id) then
      raise exception 'definir % como controladora de % criaria um CICLO de participação — % já '
                       'é controlada (direta ou indiretamente) por %',
        p_controladora_id, p_entidade_id, p_controladora_id, p_entidade_id;
    end if;
  end if;

  update entidade
     set controladora_id = p_controladora_id,
         percentual_participacao = p_percentual
   where id = p_entidade_id;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
  values (p_autor, 'entidade_participacao_definida', 'entidade:' || p_entidade_id,
          jsonb_build_object(
            'controladora_id_novo', p_controladora_id, 'controladora_id_anterior', v_controladora_anterior,
            'percentual_novo', p_percentual, 'percentual_anterior', v_percentual_anterior));

  return p_entidade_id;
end;
$$;

comment on function public.fn_entidade_definir_participacao(uuid, uuid, numeric, text) IS
  '0181: o ÚNICO caminho de escrita de `entidade.controladora_id`/`percentual_participacao` — '
  'chamado por um humano/analista (portal ou SQL direto; o portal não é escopo desta fatia). '
  'p_controladora_id NULL remove a controladora e EXIGE p_percentual NULL. Valida que as duas '
  'entidades existem e pertencem ao mesmo caso, e recusa (raise exception) se '
  'fn_entidade_criaria_ciclo_participacao disser que fecharia um ciclo. Grava evento_auditoria '
  '(ator = p_autor, nunca ''sistema:...''). Reatribuir é permitido — é o estado ATUAL, o '
  'histórico mora em evento_auditoria.';

grant execute on function public.fn_entidade_definir_participacao(uuid, uuid, numeric, text) to authenticated;

-- -----------------------------------------------------------------------------
-- (4) O CONSUMIDOR MÍNIMO — a leitura que prova que a FK serve para algo além de existir
-- (regra 7 do CLAUDE.md, mesma lição da 0179/0180). Sobe a cadeia de controle a partir de uma
-- entidade, nível a nível, parando no topo (controladora_id NULL) ou no mesmo limite de
-- profundidade da guarda de ciclo (item 2) — não é o consumidor REAL de consolidação (isso é
-- F4), só a prova de que a cadeia responde à pergunta que ela existe para responder.
-- -----------------------------------------------------------------------------

create function public.fn_entidade_cadeia_controladora(p_entidade_id uuid)
RETURNS TABLE(entidade_id uuid, razao_social text, nivel int)
    LANGUAGE sql
    STABLE
    AS $$
  with recursive cadeia(entidade_id, nivel) as (
    select e0.controladora_id, 1
      from entidade e0
     where e0.id = p_entidade_id
       and e0.controladora_id is not null
    union all
    select e1.controladora_id, c.nivel + 1
      from cadeia c
      join entidade e1 on e1.id = c.entidade_id
     where e1.controladora_id is not null
       and c.nivel < 50
  )
  select c.entidade_id, e2.razao_social, c.nivel
    from cadeia c
    join entidade e2 on e2.id = c.entidade_id
   order by c.nivel;
$$;

comment on function public.fn_entidade_cadeia_controladora(uuid) IS
  '0181: sobe a cadeia de controle a partir de uma entidade (nível 1 = controladora direta, '
  'nível 2 = a controladora da controladora, …), parando no topo (controladora_id NULL) ou no '
  'limite de 50 níveis (mesmo limite de fn_entidade_criaria_ciclo_participacao). Consumidor '
  'mínimo — prova que a FK serve para algo além de existir (regra 7 do CLAUDE.md). O consumidor '
  'REAL (consolidação/intercompany) é F4, fora do escopo desta fatia — ver roadmap, fatia 1.5.';

grant execute on function public.fn_entidade_cadeia_controladora(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- O CATÁLOGO DA SONDA.
-- -----------------------------------------------------------------------------

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('entidade_controladora_id_existe', '0181', 'coluna', 'entidade.controladora_id',
   null, null,
   'A coluna nova da fatia 1.5: a FK self-referencing que registra a controladora DIRETA de '
   'cada entidade. Ausente (banco anterior à 0181), não há onde a hierarquia de controle morar '
   '— consolidação e intercompany (F4) não têm de onde ler quem é filha de quem.',
   'importante', 757)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('fn_entidade_criaria_ciclo_participacao_existe', '0181', 'funcao',
   'fn_entidade_criaria_ciclo_participacao',
   null, null,
   'A guarda contra ciclo de participação (A controla B controla A). Sem ela, o caminho de '
   'escrita gravaria um ciclo em vez de recusá-lo, e qualquer código futuro que suba a cadeia '
   'entraria em loop.',
   'importante', 758)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('fn_entidade_definir_participacao_existe', '0181', 'funcao', 'fn_entidade_definir_participacao',
   null, null,
   'O único caminho de escrita de controladora_id/percentual_participacao. Sem ele, as colunas '
   'novas entregam o mesmo vazio de papel_no_grupo antes da 0179 — existem, mas nada as '
   'preenche com segurança contra ciclo.',
   'importante', 759)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('fn_entidade_cadeia_controladora_existe', '0181', 'funcao', 'fn_entidade_cadeia_controladora',
   null, null,
   'O consumidor mínimo da hierarquia de controle — sobe a cadeia a partir de uma entidade. Sem '
   'ele, nada prova que a FK responde a pergunta nenhuma além de existir (regra 7 do CLAUDE.md).',
   'informativo', 760)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0181', revisado_em = current_date,
       observacao = 'A 0181 fecha a fatia 1.5 do plano F1: `entidade.controladora_id` '
                    '(FK self-referencing, no máximo uma controladora DIRETA por entidade — não '
                    'um grafo completo de participação) e `entidade.percentual_participacao`, '
                    'com os checks de auto-referência e de percentual em (0,100], a guarda '
                    'contra ciclo (fn_entidade_criaria_ciclo_participacao, chamada antes de '
                    'gravar) e caminho de escrita explícito (fn_entidade_definir_participacao, '
                    'chamado por humano — nunca inferência automática) e consumidor mínimo de '
                    'leitura (fn_entidade_cadeia_controladora). É a FK preparada que a F4 '
                    '(consolidação/intercompany) vai consumir — nenhum caso real tem hierarquia '
                    'de controle registrada ainda. Aplicar a migration e registrar a hierarquia '
                    'dos casos reais é decisão de uma sessão seguinte, contra a sonda.';

-- =============================================================================
-- 0180 — fatia 1.4 do plano F1: `perimetro(caso, entidade, escopo, desde, ate)`
--
-- O DEFEITO, medido em 18/09/2026 contra o schema (seção 12.2 de
-- `Arquitetura do Sistema/3 Estado e Execução/ARQUITETURA_ALVO_E_ROADMAP.md`, fatia 1.4): não
-- existe, em NENHUMA tabela deste banco, o registro de QUEM entra no COMBINADO de um caso.
-- `autoridade_combinado` (0155) e `rotulo_contraditorio` (0159) sabem ler um documento
-- COMBINADO e contar quantas empresas as colunas dele têm — mas isso é o que o DOCUMENTO diz
-- sobre si mesmo, não uma decisão do sistema sobre o que DEVERIA compor o combinado. Sem esta
-- tabela, "o Grupo Vertentes tem 5 empresas no combinado" é um fato que só existe dentro de um
-- PDF — nunca gravado, nunca consultável, nunca datado.
--
-- E A PARTE QUE O ROADMAP JÁ NOMEIA COMO O RISCO REAL: **perímetro muda no meio do mandato.**
-- Uma SPE que entra em operação em julho, uma coligada vendida em outubro — sem `desde`/`ate`,
-- qualquer tabela de perímetro que alguém criasse "para resolver rápido" (ex.: uma flag booleana
-- em `entidade`) contaria a foto de HOJE como se fosse a foto de todo o histórico, e o exercício
-- anterior do combinado ficaria mentindo sobre quem estava dentro dele na época. É exatamente o
-- defeito que a regra 1 do CLAUDE.md nomeia: ausência de data virando afirmação atemporal.
--
-- A DECISÃO DE PRODUTO JÁ TOMADA (mesmo raciocínio da 0179 para papel_no_grupo — não repetida a
-- cada sessão): **esta migration NÃO deriva escopo de `entidade.papel_no_grupo`.**
-- `papel_no_grupo = 'fora_do_perimetro'` (0179) parece um sinal tentador — mas ligar as duas
-- fatias é decisão de F4 (consolidação), não desta migration isolada, aditiva e de risco baixo.
-- Papel no grupo é uma CLASSIFICAÇÃO da entidade (o que ela É); perímetro é uma decisão de
-- ESCOPO por (caso, escopo, intervalo de tempo) — a mesma entidade pode entrar e saltar de
-- combinados diferentes ao longo do mandato, e uma coluna em `entidade` não teria como
-- expressar isso. Inferir uma da outra aqui seria estrutura sem medição (regra 1 do CLAUDE.md):
-- não há hoje nenhum consumidor que precise dessa ponte, e construí-la sem um caso real que a
-- exija é decidir no escuro. Fica registrado para a sessão seguinte NÃO reabrir esta pergunta
-- sem contexto novo — quando a F4 (consolidação) precisar decidir o que soma no combinado, ela
-- decide então, com as DUAS tabelas na mão e um caso real para testar contra.
--
-- POR QUE `escopo` É `text` LIVRE, NÃO ENUM (mesmo raciocínio da 0179 para papel_no_grupo): não
-- há vocabulário fechado medido ainda para "o nome do COMBINADO a que este período pertence" —
-- um mandato pode ter um COMBINADO só, ou vários (ex.: "Grupo Vertentes" e "Grupo Vertentes
-- ex-Logística"). Inventar um enum aqui seria estrutura sem medição.
--
-- O CONSUMIDOR MÍNIMO: `fn_perimetro_vigente`, a leitura que prova que a tabela serve para algo
-- além de existir (mesma lição da 0179, regra 7 do CLAUDE.md — tabela sem caminho de LEITURA
-- nenhum tem a mesma aparência vazia de uma tabela sem caminho de ESCRITA). Ela não é consumida
-- por pipeline nenhum ainda — o consumidor REAL (o combinado calculado respeitando o perímetro)
-- fica para quando a F1.6/F4 precisar dele, exatamente como a seção 12.3 do roadmap nomeia o que
-- esta fase NÃO faz (identidade de conta e consolidação são F4). Aqui ela só prova, com teste,
-- que a data importa: perguntar "quem estava no combinado em 30/06" e "quem está hoje" tem
-- respostas DIFERENTES depois de uma troca de escopo.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2), em `Supabase/test/perimetro.test.sql`: com o `update` que fecha o
-- intervalo aberto anterior (dentro de `fn_perimetro_definir_escopo`) comentado — rodado contra
-- o arquivo de teste com `teste_assert_0180` trocado para não abortar no primeiro assert e
-- contar todos — **4 dos 17 asserts do arquivo reprovaram** (medido de fato; ver o cabeçalho do
-- arquivo de teste para o detalhe por bloco, inclusive por que os outros 13 passam com ou sem a
-- correção). Religado o fechamento, os 17 asserts passam.
--
-- **Pronto** (a fatia não lista "pronto quando" no roadmap — deliberadamente mais leve que a
-- 1.3): a tabela existe, com os dois índices que impedem dois "vigente" simultâneos por
-- (caso, entidade, escopo) e a checagem óbvia de intervalo, e o caminho de escrita
-- (`fn_perimetro_definir_escopo`) é explícito e chamado por humano — nunca inferência
-- automática. Aplicar em produção e usar a função para os casos reais é decisão de uma sessão
-- seguinte, contra a sonda (migration escrita ≠ aplicada).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- (1) A TABELA.
-- -----------------------------------------------------------------------------

create table perimetro (
  id          uuid primary key default gen_random_uuid(),
  caso_id     uuid not null references caso(id) on delete cascade,
  entidade_id uuid not null references entidade(id) on delete cascade,
  escopo      text not null,
  desde       date not null,
  ate         date,
  criado_em   timestamptz not null default now()
);

comment on table perimetro is
  '0180 (fatia 1.4 do plano F1): quem entra no COMBINADO de um caso, por escopo e por intervalo '
  'de tempo. `escopo` é texto livre (o nome do combinado — não há vocabulário fechado medido '
  'ainda, mesmo raciocínio de `periodo.tipo`). `ate` NULL = ainda vigente. NÃO é derivada de '
  '`entidade.papel_no_grupo` (0179) — ligar as duas é decisão de F4 (consolidação), fora do '
  'escopo desta migration. O único caminho de escrita é `fn_perimetro_definir_escopo`.';

comment on column perimetro.escopo is
  '0180: o nome do COMBINADO a que este período de perímetro pertence (texto livre, como '
  '`periodo.tipo`) — inventar um enum aqui seria estrutura sem medição (regra 1 do CLAUDE.md).';

comment on column perimetro.ate is
  '0180: NULL = ainda vigente. Trocar o escopo de uma entidade (fn_perimetro_definir_escopo) '
  'FECHA este campo no intervalo anterior — nunca sobrescreve silenciosamente — porque um '
  'perímetro sem data mente sobre o exercício anterior (roadmap, fatia 1.4).';

create index idx_perimetro_caso on perimetro(caso_id);
create index idx_perimetro_entidade on perimetro(entidade_id);

-- No máximo UM intervalo aberto por (caso, entidade, escopo) — impede dois "vigente"
-- simultâneos para a mesma combinação, mesma técnica de `perimetro_atual_unico` desta fatia.
create unique index perimetro_atual_unico on perimetro(caso_id, entidade_id, escopo) where ate is null;

-- `ate`, quando presente, não pode ser anterior a `desde` — dado óbvio que uma migration não
-- deveria deixar o banco aceitar ao contrário. `fn_perimetro_definir_escopo` conta com este
-- `check` para recusar uma troca de escopo cuja `p_desde` seja anterior (ou igual) ao `desde` do
-- intervalo aberto que ela mesma está fechando — ver comentário da função abaixo.
alter table perimetro add constraint perimetro_intervalo_valido check (ate is null or ate >= desde);

alter table perimetro enable row level security;
drop policy if exists perimetro_read on perimetro;
create policy perimetro_read on perimetro
  for select to authenticated using (true);
grant select on perimetro to authenticated;

-- -----------------------------------------------------------------------------
-- (2) O CAMINHO DE ESCRITA — mesma doutrina da 0179: não inferir automaticamente, humano decide.
--
-- Fecha o intervalo aberto anterior do MESMO (caso, entidade, escopo), se existir — a mudança de
-- perímetro no meio do mandato é exatamente o caso que o roadmap cita: o intervalo anterior tem
-- de ganhar um FIM, não ser sobrescrito silenciosamente (regra 1 do CLAUDE.md pelo avesso).
-- Insere o novo intervalo aberto, e grava evento_auditoria.
--
-- SE `p_desde` for anterior (ou igual) ao `desde` do intervalo que está sendo fechado, o `update`
-- deste passo tentaria gravar `ate < desde` nessa MESMA linha, e `perimetro_intervalo_valido`
-- (acima) recusa a transação inteira com uma mensagem do Postgres — decisão deliberada de deixar
-- o `check` fazer esse trabalho em vez de duplicar a validação em PL/pgSQL: a regra já existe na
-- tabela para proteger contra INSERT direto (regra do desenho desta fatia), então reaproveitá-la
-- aqui evita ter a mesma invariante escrita em dois lugares que podem divergir.
-- -----------------------------------------------------------------------------

create function public.fn_perimetro_definir_escopo(p_caso_id uuid, p_entidade_id uuid,
                                                     p_escopo text, p_desde date, p_autor text)
RETURNS uuid
    LANGUAGE plpgsql
    AS $$
declare
  v_caso_da_entidade uuid;
  v_novo_id          uuid;
begin
  if p_desde is null then
    raise exception 'p_desde não pode ser nulo — todo intervalo de perímetro tem início';
  end if;

  select caso_id into v_caso_da_entidade from entidade where id = p_entidade_id;
  if v_caso_da_entidade is null then
    raise exception 'entidade % não encontrada', p_entidade_id;
  end if;
  if v_caso_da_entidade <> p_caso_id then
    raise exception 'entidade % não pertence ao caso %', p_entidade_id, p_caso_id;
  end if;

  -- A MUDANÇA de perímetro no meio do mandato: o intervalo anterior GANHA UM FIM, não é
  -- sobrescrito. Sem esta linha, uma segunda chamada para o mesmo (caso, entidade, escopo)
  -- violaria `perimetro_atual_unico` (dois "vigente" ao mesmo tempo) em vez de fechar o
  -- primeiro — é esta a MEDIÇÃO NÃO-VAZIA do cabeçalho desta migration.
  update perimetro
     set ate = p_desde - 1
   where caso_id = p_caso_id and entidade_id = p_entidade_id and escopo = p_escopo
     and ate is null;

  insert into perimetro (caso_id, entidade_id, escopo, desde, ate)
  values (p_caso_id, p_entidade_id, p_escopo, p_desde, null)
  returning id into v_novo_id;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
  values (p_autor, 'perimetro_escopo_definido', 'entidade:' || p_entidade_id,
          jsonb_build_object('caso_id', p_caso_id, 'escopo', p_escopo, 'desde', p_desde));

  return v_novo_id;
end;
$$;

comment on function public.fn_perimetro_definir_escopo(uuid, uuid, text, date, text) IS
  '0180: o ÚNICO caminho de escrita de `perimetro` — chamado por um humano/analista (portal ou '
  'SQL direto; o portal não é escopo desta fatia). Fecha o intervalo aberto anterior do mesmo '
  '(caso, entidade, escopo) com `ate = p_desde - 1` em vez de sobrescrever — é a mudança de '
  'perímetro no meio do mandato que o roadmap cita (fatia 1.4). Grava evento_auditoria (ator = '
  'p_autor, nunca ''sistema:...''). NÃO deriva nada de entidade.papel_no_grupo (0179) — ligar as '
  'duas fatias é decisão de F4, fora do escopo desta migration.';

grant execute on function public.fn_perimetro_definir_escopo(uuid, uuid, text, date, text) to authenticated;

-- -----------------------------------------------------------------------------
-- (3) O CONSUMIDOR MÍNIMO — a leitura que prova que a tabela serve para algo além de existir
-- (regra 7 do CLAUDE.md, mesma lição que a 0179 acabou de aprender para papel_no_grupo). Quem
-- estava no escopo NUMA DATA (padrão: hoje) — não é o consumidor real do combinado (esse é F4/
-- F1.6, ver seção 12.3 do roadmap: "não cria conta_canonica", identidade e consolidação não são
-- desta fase), só a prova de que `desde`/`ate` respondem a pergunta que a tabela existe para
-- responder.
-- -----------------------------------------------------------------------------

create function public.fn_perimetro_vigente(p_caso_id uuid, p_escopo text, p_data date DEFAULT CURRENT_DATE)
RETURNS SETOF entidade
    LANGUAGE sql
    STABLE
    AS $$
  select e.*
    from perimetro p
    join entidade e on e.id = p.entidade_id
   where p.caso_id = p_caso_id
     and p.escopo = p_escopo
     and p.desde <= p_data
     and (p.ate is null or p.ate >= p_data)
   order by e.razao_social;
$$;

comment on function public.fn_perimetro_vigente(uuid, text, date) IS
  '0180: quem está no escopo de um COMBINADO numa data (padrão: hoje). Consumidor mínimo de '
  '`perimetro` — prova que desde/ate respondem "quem estava dentro em 30/06" diferente de "quem '
  'está dentro hoje" depois de uma troca de escopo. O consumidor REAL (o combinado calculado '
  'respeitando o perímetro) é F1.6/F4, fora do escopo desta fatia — ver seção 12.3 do roadmap.';

grant execute on function public.fn_perimetro_vigente(uuid, text, date) to authenticated;

-- -----------------------------------------------------------------------------
-- O CATÁLOGO DA SONDA.
-- -----------------------------------------------------------------------------

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('perimetro_tabela_existe', '0180', 'tabela', 'perimetro',
   null, null,
   'A tabela nova da fatia 1.4: quem entra no COMBINADO de um caso, por escopo e por intervalo '
   'de tempo. Ausente (banco anterior à 0180), não há registro nenhum de perímetro — só o que um '
   'documento COMBINADO diz sobre si mesmo (autoridade_combinado, 0155).',
   'importante', 754)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('fn_perimetro_definir_escopo_existe', '0180', 'funcao', 'fn_perimetro_definir_escopo',
   null, null,
   'O único caminho de escrita de `perimetro`. Sem ele, a tabela nova entrega o mesmo vazio de '
   'papel_no_grupo antes da 0179 — existe, mas nada a preenche.',
   'importante', 755)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('fn_perimetro_vigente_existe', '0180', 'funcao', 'fn_perimetro_vigente',
   null, null,
   'O consumidor mínimo de `perimetro` — quem está no escopo numa data. Sem ele, nada prova que '
   'desde/ate respondem a pergunta que a tabela existe para responder (regra 7 do CLAUDE.md).',
   'informativo', 756)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0180', revisado_em = current_date,
       observacao = 'A 0180 fecha a fatia 1.4 do plano F1: tabela `perimetro` nova (quem entra '
                    'no COMBINADO, por escopo e por intervalo desde/ate) com caminho de escrita '
                    'explícito (fn_perimetro_definir_escopo, chamado por humano — a troca de '
                    'escopo no meio do mandato FECHA o intervalo anterior, nunca sobrescreve) e '
                    'consumidor mínimo de leitura (fn_perimetro_vigente). NÃO deriva escopo de '
                    'entidade.papel_no_grupo (0179) — ligar as duas fatias é decisão de F4, fora '
                    'do escopo desta migration (ver cabeçalho). Nenhum caso real tem perímetro '
                    'definido ainda — aplicar a migration e chamar a função para os casos reais '
                    'é decisão de uma sessão seguinte, contra a sonda.';

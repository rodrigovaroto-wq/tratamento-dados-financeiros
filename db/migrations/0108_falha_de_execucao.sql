-- =============================================================================
-- Migration 0108 — Quando o pipeline falha, a TELA fica sabendo
--
-- O QUE ACONTECEU, e é o pior tipo de defeito que este sistema pode ter. O dono
-- subiu 35 documentos do book-canastra. O n8n recusou o lote no nó `Orcamento do
-- Lote` (estimativa acima do teto) e lançou a exceção — corretamente, nada foi
-- gasto. E o portal continuou dizendo:
--
--     "Estamos organizando tudo com cuidado — isso costuma levar alguns minutos.
--      Você pode aguardar aqui ou voltar mais tarde; assim que estiver pronto,
--      avisamos."
--
-- Para sempre. Não havia "assim que estiver pronto": o processamento tinha
-- morrido dois minutos antes, e a única pessoa que sabia disso era quem abrisse
-- a aba de execuções do n8n.
--
-- ISTO É PIOR QUE UM ERRO NA TELA. Erro na tela é informação; tela de espera
-- sobre um processo morto é uma MENTIRA que o sistema conta com cara de calma. E
-- ela custa o dobro: além de não resolver, consome a paciência de quem espera e
-- depois a confiança de quem descobre.
--
-- POR QUE O PORTAL NÃO TINHA COMO SABER: a rota `/api/intake/status` deduz o
-- progresso de dois sinais POSITIVOS — documento criado e evento de extração. A
-- falha não produz nenhum dos dois; ela produz ausência. E ausência é
-- exatamente o que "ainda está processando" também produz. Os dois estados
-- tinham a mesma aparência do lado de fora, que é a assinatura de defeito que
-- este projeto persegue desde a sessão 16.
--
-- A SOLUÇÃO É DAR AO ERRO UM LUGAR PARA MORAR. Tabela própria, não só
-- `evento_auditoria`: a trilha é append-only e serve à auditoria, enquanto isto
-- aqui é estado operacional que a tela LÊ a cada 3 segundos e que alguém precisa
-- poder marcar como visto. Misturar os dois faria a trilha crescer com
-- informação de tela e a tela depender de varredura da trilha.
-- =============================================================================

create table if not exists execucao_falha (
  id           uuid primary key default gen_random_uuid(),
  caso_id      uuid references caso(id) on delete cascade,
  -- Nome do CASO como o formulário mandou. Existe porque a falha pode acontecer
  -- ANTES de o caso existir (nome inválido, banco fora do ar no upsert), e uma
  -- falha órfã que ninguém consegue ligar ao mandato é uma falha invisível.
  caso_nome    text,
  etapa        text not null,
  mensagem     text not null,
  detalhe      jsonb,
  criado_em    timestamptz not null default now(),
  visto_em     timestamptz,
  visto_por    text
);
create index if not exists idx_execucao_falha_caso on execucao_falha(caso_id, criado_em desc);
create index if not exists idx_execucao_falha_nome on execucao_falha(lower(caso_nome), criado_em desc);

comment on table execucao_falha is
  'Falha do pipeline (n8n) que a TELA precisa mostrar. Existe porque o portal deduzia progresso de '
  'sinais positivos, e falha produz ausência — indistinguível de "ainda processando". Tabela '
  'própria e não evento_auditoria: isto é estado operacional que se marca como visto, não trilha.';

alter table execucao_falha enable row level security;

drop policy if exists execucao_falha_authenticated_all on execucao_falha;
create policy execucao_falha_authenticated_all on execucao_falha
  for all to authenticated using (true) with check (true);

-- -----------------------------------------------------------------------------
-- fn_registrar_falha_execucao — chamada pelo n8n no caminho de erro.
--
-- Recebe o NOME do caso além do id porque o id pode não existir ainda. Grava
-- também na trilha: a tela mostra o estado, a auditoria guarda o histórico, e
-- nenhuma das duas depende da outra.
-- -----------------------------------------------------------------------------
create or replace function fn_registrar_falha_execucao(
  p_caso_id   uuid,
  p_caso_nome text,
  p_etapa     text,
  p_mensagem  text,
  p_detalhe   jsonb default null
)
returns jsonb
language plpgsql
as $$
declare
  v_id uuid;
begin
  insert into execucao_falha (caso_id, caso_nome, etapa, mensagem, detalhe)
    values (p_caso_id, nullif(trim(coalesce(p_caso_nome, '')), ''),
            coalesce(nullif(trim(p_etapa), ''), 'desconhecida'),
            coalesce(nullif(trim(p_mensagem), ''), 'Falha sem mensagem.'),
            p_detalhe)
    returning id into v_id;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:n8n', 'falha_execucao',
            coalesce('caso:' || p_caso_id::text, 'caso_nome:' || coalesce(p_caso_nome, '?')),
            jsonb_build_object('etapa', p_etapa, 'mensagem', p_mensagem, 'detalhe', p_detalhe));

  return jsonb_build_object('falha_id', v_id, 'registrada', true);
end;
$$;

comment on function fn_registrar_falha_execucao(uuid, text, text, text, jsonb) is
  'Registra falha do pipeline para a TELA mostrar (e para a trilha guardar). Aceita caso_id nulo: '
  'a falha pode acontecer antes de o caso existir, e falha órfã é falha invisível.';

grant execute on function fn_registrar_falha_execucao(uuid, text, text, text, jsonb) to authenticated;
grant execute on function fn_registrar_falha_execucao(uuid, text, text, text, jsonb) to service_role;

-- -----------------------------------------------------------------------------
-- fn_falhas_abertas — o que a tela pergunta a cada polling.
--
-- Por NOME do caso porque é o que o formulário de upload conhece antes de o
-- caso existir. Só as não vistas, e só as recentes: falha de semana passada não
-- é notícia sobre o upload de agora.
-- -----------------------------------------------------------------------------
create or replace function fn_falhas_abertas(p_caso_nome text, p_desde timestamptz)
returns table (
  id        uuid,
  etapa     text,
  mensagem  text,
  criado_em timestamptz
)
language sql
stable
as $$
  select f.id, f.etapa, f.mensagem, f.criado_em
  from execucao_falha f
  where f.visto_em is null
    and f.criado_em >= p_desde
    and (lower(f.caso_nome) = lower(trim(p_caso_nome))
         or f.caso_id in (select c.id from caso c where lower(c.nome) = lower(trim(p_caso_nome))))
  order by f.criado_em desc;
$$;

grant execute on function fn_falhas_abertas(text, timestamptz) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_marcar_falha_vista — o "entendi" da tela.
-- -----------------------------------------------------------------------------
create or replace function fn_marcar_falha_vista(p_falha_id uuid, p_autor text)
returns jsonb
language plpgsql
as $$
begin
  update execucao_falha set visto_em = now(), visto_por = p_autor
   where id = p_falha_id and visto_em is null;
  return jsonb_build_object('ok', found);
end;
$$;

grant execute on function fn_marcar_falha_vista(uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_excluir_caso — apagar o mandato inteiro, com a contagem do que se perdeu.
--
-- Pedido do dono (11/08/2026): um botão de excluir dentro de cada mandato, com
-- confirmação dizendo que TODOS os dados serão perdidos.
--
-- POR QUE ISTO É UMA FUNÇÃO E NÃO UM `delete` DA TELA. A tela apagaria a linha
-- de `caso` e confiaria no `on delete cascade` — que existe e funciona. O que a
-- tela NÃO faria é (a) contar o que foi apagado, e (b) deixar rastro de que
-- existiu. Um mandato que some sem deixar nem o nome na trilha é indistinguível
-- de um mandato que nunca foi criado, e essa é a diferença entre "apagamos" e
-- "não sabemos".
--
-- A trilha fica FORA do cascade de propósito: `evento_auditoria` não referencia
-- `caso` por chave estrangeira, então o registro da exclusão sobrevive ao
-- próprio caso. É o único jeito de a exclusão ser auditável.
-- -----------------------------------------------------------------------------
create or replace function fn_excluir_caso(p_caso_id uuid, p_autor text)
returns jsonb
language plpgsql
as $$
declare
  v_nome  text;
  v_docs  int;
  v_campos int;
  v_pend  int;
begin
  select nome into v_nome from caso where id = p_caso_id;
  if v_nome is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'Este mandato não existe mais — talvez alguém já o tenha excluído.');
  end if;

  select count(*) into v_docs from documento where caso_id = p_caso_id;
  select count(*) into v_campos from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
   where d.caso_id = p_caso_id;
  select count(*) into v_pend from pendencia where caso_id = p_caso_id;

  -- A trilha ANTES do delete: se o delete falhar, sobra um registro de tentativa,
  -- que é informação; se registrássemos depois, uma falha no meio deixaria o
  -- caso apagado e nenhum rastro.
  insert into evento_auditoria (ator, acao, entidade_ref, antes)
    values (p_autor, 'caso_excluido', 'caso:'||p_caso_id,
            jsonb_build_object('nome', v_nome, 'documentos', v_docs,
                               'campos_extraidos', v_campos, 'pendencias', v_pend));

  delete from caso where id = p_caso_id;

  return jsonb_build_object('excluido', true, 'nome', v_nome,
                            'documentos', v_docs, 'campos_extraidos', v_campos,
                            'pendencias', v_pend);
end;
$$;

comment on function fn_excluir_caso(uuid, text) is
  'Exclui o mandato e tudo que depende dele (cascade da 0001), devolvendo a contagem do que se '
  'perdeu. Grava a exclusão em evento_auditoria ANTES do delete — a trilha não tem FK para caso, '
  'então o rastro sobrevive ao caso.';

grant execute on function fn_excluir_caso(uuid, text) to authenticated;

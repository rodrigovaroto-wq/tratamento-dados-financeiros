-- =============================================================================
-- Migration 0037 — O Portão 2 existe (era só um valor de enum)
--
-- O que estava faltando, e não estava em nenhuma lista de itens abertos: a regra
-- do Portão 2 está ESPECIFICADA E APROVADA em `f0/04` desde a F0 ("Teto de
-- ressalvas confirmado em 3", lista fechada de não-sobrepujáveis, três condições
-- determinísticas) e `docs/03` a põe dentro do MVP — mas nada disso é código.
--
-- O que existia de fato antes desta migration:
--   • `caso_status` tem os valores 'aprovado' e 'pronto_para_base' — e NENHUMA
--     função transiciona um caso para eles;
--   • `pendencia.sobrepujavel` é GRAVADO desde a 0001 e nunca LIDO por ninguém
--     (grep: só escrita). O flag que existe para dizer "nenhuma ressalva libera
--     isto" não tinha quem o consultasse;
--   • `status_aceite = 'com_ressalva'` existe por linha, mas não há teto, não há
--     expiração conferida, e não há a checagem por caso;
--   • `fn_aceitar_extracao` é o Portão 2 POR DOCUMENTO (o comentário da 0011 diz
--     isso). O portão POR CASO — o que decide se o mandato pode ser aprovado —
--     não existia.
--
-- Consequência prática: a única coisa que impedia um caso de ser tratado como
-- aprovado era ninguém ter escrito a transição. Não havia recusa possível porque
-- não havia aprovação possível — e "não implementado" tem a mesma aparência de
-- "sem pendência bloqueante" para quem olha o dashboard.
--
-- Esta migration implementa a regra COMO ELA ESTÁ ESCRITA em `f0/04`, sem
-- inventar política: o teto é 3 porque o dono confirmou 3; a lista fechada é a
-- de lá; as três condições são as de lá, na mesma ordem.
--
-- ---------------------------------------------------------------------------
-- UMA DECISÃO DE IMPLEMENTAÇÃO QUE VALE REGISTRAR: ressalva EXPIRADA
-- ---------------------------------------------------------------------------
-- `f0/04` diz: "Ao expirar, a pendência REABRE automaticamente e o caso pode
-- voltar a bloqueado." Reabrir sozinha exigiria um job agendado — e job que
-- ninguém observa é a próxima falha silenciosa. Aqui a expiração é avaliada NO
-- MOMENTO DA LEITURA: uma pendência `aceita_com_ressalva` com `expira_em` no
-- passado conta como BLOQUEANTE de novo, sem precisar que nada tenha rodado. O
-- efeito é o que a spec pede, e não depende de cron nenhum estar vivo.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- O teto, num lugar só. Função em vez de constante espalhada: quando o dono
-- mudar de 3 para outro número, muda aqui e vale para o banco inteiro.
-- -----------------------------------------------------------------------------
create or replace function fn_teto_ressalvas()
returns int
language sql
immutable
as $$ select 3; $$;

comment on function fn_teto_ressalvas() is
  'Teto de pendências aceitas com ressalva ATIVAS por caso. 3 é o valor que o dono confirmou em '
  'f0/04 ("Teto de ressalvas confirmado em 3") — não é palpite deste código.';

grant execute on function fn_teto_ressalvas() to authenticated;

-- -----------------------------------------------------------------------------
-- fn_avaliar_portao2 — a regra de `f0/04`, determinística e sem efeito colateral.
--
-- Só LÊ. Serve para o portal mostrar o estado, para o teste conferir a regra, e
-- para `fn_aprovar_caso` decidir. Separar avaliação de ação é o que permite
-- mostrar "por que não pode" sem tentar aprovar.
-- -----------------------------------------------------------------------------
create or replace function fn_avaliar_portao2(p_caso_id uuid)
returns jsonb
language plpgsql
stable
as $$
declare
  v_bloqueantes      int;
  v_nao_sobrepujavel int;
  v_ressalvas        int;
  v_ressalvas_venc   int;
  v_teto             int := fn_teto_ressalvas();
  v_motivos          text[] := array[]::text[];
  v_status           caso_status;
begin
  select status into v_status from caso where id = p_caso_id;
  if v_status is null then
    raise exception 'caso % não encontrado', p_caso_id;
  end if;

  -- Condição 1: nenhuma BLOQUEANTE em aberto. "Em aberto" inclui as que estão
  -- em tratamento (correção interna / reenviada ao cliente) — é o que `f0/04`
  -- escreve, e faz sentido: pendência sendo tratada é pendência não resolvida.
  select count(*) into v_bloqueantes
  from pendencia
  where caso_id = p_caso_id and severidade = 'bloqueante'
    and estado in ('aberta', 'em_correcao_interna', 'reenviada_ao_cliente');

  -- Condição 3: nenhuma NÃO-SOBREPUJÁVEL viva. Note que os estados aqui são
  -- OUTROS — e essa diferença é o ponto todo desta condição.
  --
  -- A primeira versão usava a mesma lista da condição 1 ('aberta',
  -- 'em_correcao_interna', 'reenviada_ao_cliente') e o teste reprovou: mover uma
  -- não-sobrepujável para `aceita_com_ressalva` a tirava da contagem e o portão
  -- LIBERAVA. Isto é exatamente a porta dos fundos que a lista fechada de f0/04
  -- existe para fechar ("nenhuma ressalva libera") — e ela estava aberta na minha
  -- própria implementação, por um copiar-e-colar de três valores de enum.
  --
  -- Então: qualquer estado que não seja TERMINAL conta. `aceita_com_ressalva`
  -- numa não-sobrepujável é estado ILEGÍTIMO, não um caminho de saída — o que se
  -- faz com ela é resolver ou rejeitar, não ressalvar.
  select count(*) into v_nao_sobrepujavel
  from pendencia
  where caso_id = p_caso_id and sobrepujavel = false
    and estado not in ('resolvida', 'rejeitada');

  -- Condição 2: ressalvas ATIVAS dentro do teto. Ativa = aceita_com_ressalva e
  -- ainda não expirada.
  select count(*) into v_ressalvas
  from pendencia
  where caso_id = p_caso_id and estado = 'aceita_com_ressalva'
    and (expira_em is null or expira_em > now());

  -- Ressalva EXPIRADA volta a bloquear (ver o cabeçalho: a spec manda reabrir;
  -- aqui a leitura já a trata como reaberta, sem depender de job).
  select count(*) into v_ressalvas_venc
  from pendencia
  where caso_id = p_caso_id and estado = 'aceita_com_ressalva'
    and expira_em is not null and expira_em <= now();

  if v_bloqueantes > 0 then
    v_motivos := array_append(v_motivos,
      format('%s pendência(s) BLOQUEANTE(s) em aberto', v_bloqueantes));
  end if;
  if v_nao_sobrepujavel > 0 then
    v_motivos := array_append(v_motivos,
      format('%s pendência(s) NÃO-SOBREPUJÁVEL(is) viva(s): nenhuma ressalva libera (lista '
             'fechada de f0/04) — tem de ser resolvida ou rejeitada', v_nao_sobrepujavel));
  end if;
  if v_ressalvas > v_teto then
    v_motivos := array_append(v_motivos,
      format('%s ressalvas ativas — acima do teto de %s por caso', v_ressalvas, v_teto));
  end if;
  if v_ressalvas_venc > 0 then
    v_motivos := array_append(v_motivos,
      format('%s ressalva(s) EXPIRADA(s): voltam a valer como pendência (f0/04)',
             v_ressalvas_venc));
  end if;

  return jsonb_build_object(
    'caso_id', p_caso_id,
    'status_atual', v_status,
    'elegivel', array_length(v_motivos, 1) is null,
    'motivos', to_jsonb(v_motivos),
    'bloqueantes_abertas', v_bloqueantes,
    'nao_sobrepujaveis_abertas', v_nao_sobrepujavel,
    'ressalvas_ativas', v_ressalvas,
    'ressalvas_expiradas', v_ressalvas_venc,
    'teto_ressalvas', v_teto
  );
end;
$$;

comment on function fn_avaliar_portao2(uuid) is
  'Regra do Portão 2 de f0/04, determinística e sem efeito colateral: elegível se e somente se '
  'nenhuma bloqueante em aberto, nenhuma não-sobrepujável em aberto, e ressalvas ativas <= teto. '
  'Ressalva expirada conta como pendência de novo (avaliada na leitura, sem depender de job).';

grant execute on function fn_avaliar_portao2(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_aprovar_caso — a ação, que RECUSA quando a regra não permite.
--
-- Recusa RETORNADA, não `raise exception`, pelo mesmo motivo da 0036: exceção em
-- plpgsql desfaz o registro da própria tentativa, e a tentativa de aprovar um
-- caso bloqueado é justamente o que uma trilha de auditoria precisa guardar.
-- `recusado: true` sai no payload para nenhum chamador confundir com sucesso.
-- -----------------------------------------------------------------------------
create or replace function fn_aprovar_caso(
  p_caso_id uuid,
  p_autor   text,
  p_motivo  text default null
)
returns jsonb
language plpgsql
as $$
declare
  v_aval   jsonb;
  v_status caso_status;
begin
  v_aval := fn_avaliar_portao2(p_caso_id);
  select status into v_status from caso where id = p_caso_id;

  if not (v_aval->>'elegivel')::boolean then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values (p_autor, 'aprovacao_recusada', 'caso:'||p_caso_id,
              jsonb_build_object('avaliacao', v_aval, 'motivo_informado', p_motivo));
    return v_aval || jsonb_build_object(
      'recusado', true,
      'motivo_recusa',
        'Este caso NÃO é elegível ao Portão 2: '
        || array_to_string(array(select jsonb_array_elements_text(v_aval->'motivos')), '; ')
        || '. A regra é determinística (f0/04) e não tem exceção por autor — resolva as '
        || 'pendências ou registre ressalva onde ela é permitida.');
  end if;

  -- Idempotente: aprovar um caso já aprovado não gera decisão nova.
  if v_status in ('aprovado', 'pronto_para_base') then
    return v_aval || jsonb_build_object('ja_aprovado', true);
  end if;

  update caso set status = 'aprovado' where id = p_caso_id;

  insert into decisao (caso_id, tipo, autor, motivo, payload)
    values (p_caso_id, 'aprovacao', p_autor,
            coalesce(p_motivo, 'Portão 2: caso aprovado'),
            jsonb_build_object('portao', 2, 'avaliacao', v_aval, 'status_anterior', v_status));

  insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
    values (p_autor, 'transicao_status', 'caso:'||p_caso_id,
            jsonb_build_object('status', v_status),
            jsonb_build_object('status', 'aprovado', 'avaliacao', v_aval));

  return v_aval || jsonb_build_object('elegivel', true, 'status_atual', 'aprovado', 'aprovado', true);
end;
$$;

comment on function fn_aprovar_caso(uuid, text, text) is
  'Portão 2 por CASO. Recusa (payload com recusado=true) quando fn_avaliar_portao2 diz que não; '
  'aprova, registra decisao+evento e transiciona para `aprovado` quando diz que sim. Sem exceção '
  'para nenhum autor: a regra de f0/04 é determinística.';

grant execute on function fn_aprovar_caso(uuid, text, text) to authenticated;

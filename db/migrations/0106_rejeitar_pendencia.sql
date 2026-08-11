-- =============================================================================
-- Migration 0106 — O Portão 2 ganha o segundo lado: REJEITAR pendência
--
-- O QUE FALTAVA, e o tamanho real do buraco. A `0037` implementou o Portão 2 por
-- caso: `fn_avaliar_portao2` diz por que um caso não pode ser aprovado, e
-- `fn_aprovar_caso` aprova quando pode. Só que a única ação que o portal oferecia
-- era APROVAR — e aprovar é justamente o que a regra proíbe enquanto houver
-- pendência bloqueante viva. Na prática: o caso trava, a tela explica o motivo, e
-- não há UM botão que mude o motivo.
--
-- `f0/04` define a máquina de estado da pendência com TRÊS saídas:
--
--     aberta → { em_correção_interna | reenviada_ao_cliente }
--            → { aceita_com_ressalva | rejeitada | resolvida }
--
-- e delas só uma existia em código de verdade: `resolvida`, escrita por
-- `sistema:*` quando a condição que abriu a pendência deixa de valer. As outras
-- duas — as HUMANAS — nunca tiveram função nem tela:
--
--   • `rejeitada`            = "a pendência não procede" (falso positivo do motor);
--   • `aceita_com_ressalva`  = "procede, e eu aceito o risco" (conta contra o teto de 3).
--
-- Esta migration entrega a PRIMEIRA. A segunda fica de fora por uma razão que
-- não é preguiça: `f0/04` exige papel **sênior** para ressalvar, e papel de
-- usuário não existe neste schema (a RLS da `0003` é "todo autenticado pode
-- tudo"). Implementar ressalva sem o papel seria publicar o controle sem o
-- controlador — e o teto de 3 já é lido e cobrado pela `0037`, então a ausência
-- aparece como ressalva que ninguém consegue criar, não como regra frouxa.
--
-- ---------------------------------------------------------------------------
-- REJEITAR É A ALAVANCA MAIS FORTE DO SISTEMA. POR ISSO ELA É CONTADA.
-- ---------------------------------------------------------------------------
-- Olhe a `0037` de novo: `fn_avaliar_portao2` conta bloqueante em
-- ('aberta','em_correcao_interna','reenviada_ao_cliente') e não-sobrepujável em
-- "qualquer estado que não seja terminal". `rejeitada` é terminal nas duas. Ou
-- seja: rejeitar libera o portão SEMPRE, inclusive para a lista fechada que
-- "nenhuma ressalva libera", e SEM TETO — enquanto a ressalva, que é o caminho
-- honesto para "eu sei do risco e assumo", para em 3.
--
-- Isso não é defeito da `0037`: é o que `f0/04` manda ("tem de ser resolvida ou
-- rejeitada"). Uma pendência que não procede não pode prender o caso para
-- sempre, e a alternativa a um botão auditado é alguém editando a tabela por
-- fora — que é a mesma liberação, sem rastro. Mas uma alavanca sem teto que só
-- deixa rastro em tabela que ninguém abre é, na prática, a porta dos fundos que
-- este projeto inteiro existe para fechar.
--
-- Três guardas, então, e cada uma tem assert que reprova religada:
--
--   1. MOTIVO OBRIGATÓRIO E SUBSTANTIVO (>= 15 caracteres, depois do trim). Na
--      aprovação o motivo é opcional — aqui não é. "ok", "-", "n/a" são
--      exatamente o que se digita quando se quer só tirar o vermelho da tela.
--   2. ESTADO TERMINAL NÃO SE REJEITA. `resolvida` → `rejeitada` seria reescrever
--      história: a pendência foi de fato tratada, e chamá-la de falso positivo
--      depois muda o passado. Rejeitar duas vezes é no-op DECLARADO, não segunda
--      decisão.
--   3. A REJEIÇÃO FICA VISÍVEL NO PRÓPRIO PORTÃO. `fn_avaliar_portao2` passa a
--      publicar `rejeitadas` e `rejeitadas_nao_sobrepujaveis`, então a avaliação
--      que a tela mostra — e que vai gravada dentro da `decisao` de aprovação —
--      diz quantas pendências foram declaradas improcedentes. Um caso aprovado
--      com 4 rejeições PARA DE TER A MESMA APARÊNCIA de um caso limpo, que era o
--      estado anterior e o motivo de esta migration mexer na função de leitura.
--
-- O que NÃO se faz aqui: apagar a pendência. A linha continua na tabela, com
-- estado `rejeitada`, o motivo escrito e o autor. `delete` seria a versão
-- silenciosa da mesma ação — e é assim que se perde a contagem do item 3.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- O piso do motivo, num lugar só (mesmo padrão de `fn_teto_ressalvas`): o portal
-- espelha este número em `portal/src/lib/pendencia.ts` para poder desabilitar o
-- botão antes do round-trip, e o assert (0114) compara os dois.
-- -----------------------------------------------------------------------------
create or replace function fn_min_motivo_rejeicao()
returns int
language sql
immutable
as $$ select 15; $$;

comment on function fn_min_motivo_rejeicao() is
  'Mínimo de caracteres do motivo de uma rejeição de pendência. Não é estética: rejeitar libera o '
  'Portão 2 sem teto, e motivo de duas letras é o que se escreve para tirar o vermelho da tela.';

grant execute on function fn_min_motivo_rejeicao() to authenticated;

-- -----------------------------------------------------------------------------
-- fn_avaliar_portao2 — REPUBLICADA (a regra da 0037, inalterada) para publicar
-- também o que foi REJEITADO.
--
-- As três condições continuam idênticas, caractere por caractere. O que muda é
-- só o que sai no payload: sem estes dois contadores, "caso limpo" e "caso
-- destravado a golpe de rejeição" são indistinguíveis na tela e dentro da
-- `decisao` de aprovação — e a segunda é a que precisa de leitura humana.
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
  v_rejeitadas       int;
  v_rejeitadas_ns    int;
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
  -- OUTROS — e essa diferença é o ponto todo desta condição (ver 0037: mover uma
  -- não-sobrepujável para `aceita_com_ressalva` NÃO pode liberar o portão).
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

  -- Ressalva EXPIRADA volta a bloquear (0037: a spec manda reabrir; a leitura já
  -- a trata como reaberta, sem depender de job).
  select count(*) into v_ressalvas_venc
  from pendencia
  where caso_id = p_caso_id and estado = 'aceita_com_ressalva'
    and expira_em is not null and expira_em <= now();

  -- NOVO (0106): o que foi declarado improcedente. Não entra em nenhuma das três
  -- condições — rejeitada é terminal, e é assim que `f0/04` a define. Entra no
  -- payload porque é a única informação que distingue um caso que nunca teve
  -- pendência de um que teve e as rejeitou.
  select count(*) filter (where true),
         count(*) filter (where sobrepujavel = false)
    into v_rejeitadas, v_rejeitadas_ns
  from pendencia
  where caso_id = p_caso_id and estado = 'rejeitada';

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
    'rejeitadas', v_rejeitadas,
    'rejeitadas_nao_sobrepujaveis', v_rejeitadas_ns,
    'teto_ressalvas', v_teto
  );
end;
$$;

comment on function fn_avaliar_portao2(uuid) is
  'Regra do Portão 2 de f0/04, determinística e sem efeito colateral: elegível se e somente se '
  'nenhuma bloqueante em aberto, nenhuma não-sobrepujável em aberto, e ressalvas ativas <= teto. '
  'Ressalva expirada conta como pendência de novo (avaliada na leitura, sem depender de job). '
  'Publica também quantas pendências foram REJEITADAS (0106) — não muda a regra, mas é o que '
  'distingue um caso limpo de um caso destravado por rejeição.';

grant execute on function fn_avaliar_portao2(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_rejeitar_pendencia — a ação humana que faltava.
--
-- RECUSA RETORNADA, não `raise exception`, pelo mesmo motivo da 0036/0037:
-- exceção em plpgsql desfaz o registro da própria tentativa, e "alguém tentou
-- rejeitar sem escrever motivo" é justamente o que a trilha precisa guardar.
-- `raise` fica só para o que é erro de programação (id que não existe).
-- -----------------------------------------------------------------------------
create or replace function fn_rejeitar_pendencia(
  p_pendencia_id uuid,
  p_autor        text,
  p_motivo       text
)
returns jsonb
language plpgsql
as $$
declare
  v_p       pendencia%rowtype;
  v_motivo  text := trim(coalesce(p_motivo, ''));
  v_min     int  := fn_min_motivo_rejeicao();
begin
  select * into v_p from pendencia where id = p_pendencia_id;
  if v_p.id is null then
    raise exception 'pendência % não encontrada', p_pendencia_id;
  end if;

  -- GUARDA 1 — motivo obrigatório e substantivo.
  --
  -- A trilha registra a TENTATIVA. Sem isto, a diferença entre "ninguém tentou"
  -- e "alguém tentou rejeitar sem justificar" some, e é a segunda que interessa
  -- a quem audita: ela indica pressão para destravar o caso.
  if length(v_motivo) < v_min then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values (p_autor, 'rejeicao_recusada', 'pendencia:'||p_pendencia_id,
              jsonb_build_object('caso_id', v_p.caso_id, 'motivo_informado', p_motivo,
                                 'minimo_exigido', v_min));
    return jsonb_build_object(
      'recusado', true,
      'pendencia_id', p_pendencia_id,
      'motivo_recusa',
        format('Rejeitar uma pendência exige motivo escrito com pelo menos %s caracteres. '
               'Rejeitar é declarar que a pendência NÃO PROCEDE — é a única ação que libera o '
               'Portão 2 sem teto, inclusive para a lista fechada de f0/04. Quem ler o caso '
               'daqui a seis meses precisa saber por quê.', v_min));
  end if;

  -- GUARDA 2 — estado terminal não se rejeita.
  --
  -- `rejeitada` de novo é no-op declarado (dois cliques não viram duas decisões).
  -- `resolvida` → `rejeitada` é recusado: a pendência foi tratada de fato, e
  -- rotulá-la de falso positivo depois reescreve o que aconteceu.
  if v_p.estado = 'rejeitada' then
    return jsonb_build_object(
      'ja_rejeitada', true,
      'pendencia_id', p_pendencia_id,
      'avaliacao', fn_avaliar_portao2(v_p.caso_id));
  end if;

  if v_p.estado = 'resolvida' then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values (p_autor, 'rejeicao_recusada', 'pendencia:'||p_pendencia_id,
              jsonb_build_object('caso_id', v_p.caso_id, 'estado', v_p.estado,
                                 'motivo_informado', v_motivo));
    return jsonb_build_object(
      'recusado', true,
      'pendencia_id', p_pendencia_id,
      'motivo_recusa',
        'Esta pendência já está RESOLVIDA: o problema que a abriu deixou de valer. '
        'Rejeitar agora diria que ela nunca procedeu, o que reescreve o que aconteceu.');
  end if;

  -- A AÇÃO. A linha NÃO é apagada: fica com estado `rejeitada`, o motivo escrito
  -- e o autor. `delete` seria a mesma liberação sem contagem — e é a contagem que
  -- `fn_avaliar_portao2` publica.
  update pendencia
     set estado        = 'rejeitada',
         motivo        = v_motivo,
         resolvida_em  = now(),
         resolvida_por = p_autor
   where id = p_pendencia_id;

  -- `decisao` tipo `override`: rejeitar é sobrepor o motor de pendências, que é
  -- o que `override` quer dizer em `f0/05`. Não é `ressalva` — ressalva admite o
  -- problema e assume o risco; rejeição afirma que problema não há.
  insert into decisao (caso_id, tipo, autor, motivo, payload)
    values (v_p.caso_id, 'override', p_autor, v_motivo,
            jsonb_build_object(
              'acao', 'rejeitar_pendencia',
              'pendencia_id', p_pendencia_id,
              'tipo', v_p.tipo,
              'severidade', v_p.severidade,
              'sobrepujavel', v_p.sobrepujavel,
              'estado_anterior', v_p.estado,
              'descricao', v_p.descricao));

  insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
    values (p_autor, 'pendencia_rejeitada', 'pendencia:'||p_pendencia_id,
            jsonb_build_object('estado', v_p.estado, 'caso_id', v_p.caso_id),
            jsonb_build_object('estado', 'rejeitada', 'motivo', v_motivo,
                               'severidade', v_p.severidade,
                               'sobrepujavel', v_p.sobrepujavel));

  -- Devolve a avaliação NOVA do portão junto: quem chamou quer saber se isto
  -- destravou o caso, e uma ida ao banco responde as duas coisas.
  return jsonb_build_object(
    'rejeitada', true,
    'pendencia_id', p_pendencia_id,
    'caso_id', v_p.caso_id,
    'severidade', v_p.severidade,
    'sobrepujavel', v_p.sobrepujavel,
    'avaliacao', fn_avaliar_portao2(v_p.caso_id));
end;
$$;

comment on function fn_rejeitar_pendencia(uuid, text, text) is
  'Declara uma pendência IMPROCEDENTE (f0/04: estado `rejeitada`). Exige motivo com no mínimo '
  'fn_min_motivo_rejeicao() caracteres, não aceita estado terminal, não apaga a linha, e grava '
  'decisao(override) + evento_auditoria. Libera o Portão 2 inclusive para não-sobrepujável — por '
  'isso a contagem sai em fn_avaliar_portao2.';

grant execute on function fn_rejeitar_pendencia(uuid, text, text) to authenticated;

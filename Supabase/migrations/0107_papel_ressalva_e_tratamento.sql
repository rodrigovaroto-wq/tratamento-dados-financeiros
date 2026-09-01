-- =============================================================================
-- Migration 0107 — A máquina de estado da pendência fica INTEIRA (Arquitetura do Sistema/2 Especificação/f0/04)
--
-- `Arquitetura do Sistema/2 Especificação/f0/04` define seis estados desde a F0, e até aqui o código escrevia três:
--
--     aberta            ✅ o motor abre
--     resolvida         ✅ `sistema:*` fecha quando a condição some
--     rejeitada         ✅ a 0106 (esta rodada)
--     em_correcao_interna    ❌ nenhum caminho
--     reenviada_ao_cliente   ❌ nenhum caminho
--     aceita_com_ressalva    ❌ nenhum caminho
--
-- Os três que faltavam não são detalhe. `reenviada_ao_cliente` representa a AÇÃO
-- MAIS COMUM do processo real — "pedi o documento de novo" —, e o sistema não
-- sabia registrá-la: quem pedisse por e-mail não tinha onde dizer isso, e a
-- pendência seguia idêntica a uma que ninguém tocou. `aceita_com_ressalva` é
-- pior: o card do Portão 2 fala de um teto de 3 ressalvas desde a 0037, e
-- NINGUÉM CONSEGUE CRIAR UMA. O controle estava publicado sem existir.
--
-- ---------------------------------------------------------------------------
-- POR QUE A RESSALVA EXIGIA UMA DECISÃO ANTES, E QUAL FOI
-- ---------------------------------------------------------------------------
-- `Arquitetura do Sistema/2 Especificação/f0/04`: "Exige papel SÊNIOR + motivo obrigatório + data de expiração." O
-- papel não existia neste schema — a RLS da 0003 é "todo autenticado pode tudo"
-- —, e era por isso que a ressalva não podia ser implementada como especificada.
-- Implementá-la sem o papel seria publicar o controle sem o controlador.
--
-- Então o papel entra aqui, no menor tamanho que resolve: uma tabela de e-mail →
-- papel, sem hierarquia, sem grupos, sem convite. Quem não está na tabela é
-- `analista` — o default é o MENOR privilégio, e a consequência prática é que num
-- banco recém-migrado NINGUÉM ressalva até o dono se cadastrar. Isso é o
-- comportamento certo: um controle que nasce aberto nunca é fechado depois.
--
-- E O QUE ISSO MUDA NA REJEIÇÃO DA 0106: rejeitar uma pendência comum continua
-- podendo ser feito por qualquer autenticado (com motivo e trilha, como está).
-- Rejeitar uma NÃO-SOBREPUJÁVEL — a lista fechada de Arquitetura do Sistema/2 Especificação/f0/04, a alavanca mais forte
-- do sistema — passa a exigir sênior. É um aperto deliberado sobre o que a 0106
-- entregou, e ele existe porque "qualquer um pode passar por cima do controle
-- mais duro" não é uma frase que se queira verdadeira.
--
-- ---------------------------------------------------------------------------
-- O QUE A RESSALVA RECUSA, E POR QUÊ CADA UMA
-- ---------------------------------------------------------------------------
--   • pendência NÃO-SOBREPUJÁVEL — a lista fechada diz que nenhuma ressalva
--     libera, e a 0037 já a mantém bloqueando mesmo ressalvada. Aceitar a
--     ressalva "com sucesso" e o portão continuar fechado seria o pior dos dois
--     mundos: o humano acha que resolveu e o caso segue travado sem explicação;
--   • SEM data de expiração — ressalva permanente é liberação com outro nome;
--   • expiração NO PASSADO — nasceria vencida, e a 0037 a contaria como
--     bloqueio no mesmo instante;
--   • acima do TETO — a quarta ressalva não "quase passa": ela bloqueia o
--     portão. Recusar na hora, dizendo quantas já existem, é melhor que gravar
--     uma decisão que trava o caso e descobrir isso na tela de aprovação.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- O papel, no menor tamanho que resolve.
-- -----------------------------------------------------------------------------
create table if not exists usuario_papel (
  email      text primary key,
  papel      text not null check (papel in ('analista', 'senior')),
  criado_em  timestamptz not null default now(),
  criado_por text
);

comment on table usuario_papel is
  'Papel por e-mail (Arquitetura do Sistema/2 Especificação/f0/04: ressalva exige sênior). Quem não está aqui é `analista` — o default é '
  'o menor privilégio, então num banco novo ninguém ressalva até o dono se cadastrar. Sem '
  'hierarquia e sem grupos de propósito: dois papéis é o que a spec pede.';

alter table usuario_papel enable row level security;

-- Leitura para todo autenticado (a tela precisa saber se mostra o botão);
-- ESCRITA não tem policy: cadastrar sênior é ação de banco, feita pelo dono.
-- Uma tela que promove o próprio usuário a sênior não é um controle.
drop policy if exists usuario_papel_leitura on usuario_papel;
create policy usuario_papel_leitura on usuario_papel
  for select to authenticated using (true);

create or replace function fn_papel(p_email text)
returns text
language sql
stable
as $$
  select coalesce((select papel from usuario_papel where lower(email) = lower(trim(p_email))), 'analista');
$$;

comment on function fn_papel(text) is
  'Papel do e-mail, `analista` quando não cadastrado. Default de menor privilégio: controle que '
  'nasce aberto nunca é fechado depois.';

grant execute on function fn_papel(text) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_ressalvar_pendencia — o caminho que `Arquitetura do Sistema/2 Especificação/f0/04` especificou na F0 e que nunca
-- existiu em código.
-- -----------------------------------------------------------------------------
create or replace function fn_ressalvar_pendencia(
  p_pendencia_id uuid,
  p_autor        text,
  p_motivo       text,
  p_expira_em    timestamptz
)
returns jsonb
language plpgsql
as $$
declare
  v_p      pendencia%rowtype;
  v_motivo text := trim(coalesce(p_motivo, ''));
  v_min    int  := fn_min_motivo_rejeicao();
  v_teto   int  := fn_teto_ressalvas();
  v_ativas int;
  v_recusa text;
begin
  select * into v_p from pendencia where id = p_pendencia_id;
  if v_p.id is null then
    raise exception 'pendência % não encontrada', p_pendencia_id;
  end if;

  select count(*) into v_ativas
  from pendencia
  where caso_id = v_p.caso_id and estado = 'aceita_com_ressalva'
    and id <> p_pendencia_id
    and (expira_em is null or expira_em > now());

  -- As recusas, na ordem em que importam a quem está lendo a tela.
  if fn_papel(p_autor) <> 'senior' then
    v_recusa := 'Aceitar com ressalva exige papel SÊNIOR (Arquitetura do Sistema/2 Especificação/f0/04). O seu está como analista — '
      || 'um sênior precisa registrar o seu e-mail em `usuario_papel`, e isso é feito no banco, '
      || 'não pela tela: um controle que o próprio usuário se concede não é controle.';
  elsif v_p.estado in ('resolvida', 'rejeitada') then
    v_recusa := 'Esta pendência já está encerrada — não há risco em aberto para ressalvar.';
  elsif v_p.sobrepujavel = false then
    v_recusa := 'Esta pendência é da lista fechada de Arquitetura do Sistema/2 Especificação/f0/04: NENHUMA ressalva a libera. Aceitar '
      || 'com ressalva aqui deixaria o caso travado do mesmo jeito, com o registro dizendo o '
      || 'contrário. O caminho é resolver o problema ou declarar a pendência improcedente.';
  elsif length(v_motivo) < v_min then
    v_recusa := format('Ressalva exige motivo escrito com pelo menos %s caracteres: ela é a '
      || 'aceitação CONSCIENTE de um risco conhecido, e quem assumiu o risco precisa dizer qual.',
      v_min);
  elsif p_expira_em is null then
    v_recusa := 'Ressalva exige DATA DE EXPIRAÇÃO (Arquitetura do Sistema/2 Especificação/f0/04). Ressalva permanente é liberação com '
      || 'outro nome — no vencimento a pendência volta a valer sozinha.';
  elsif p_expira_em <= now() then
    v_recusa := 'A data de expiração está no passado: a ressalva nasceria vencida e o Portão 2 a '
      || 'contaria como pendência no mesmo instante.';
  elsif v_ativas >= v_teto then
    v_recusa := format('Este caso já tem %s ressalvas ativas, que é o teto (Arquitetura do Sistema/2 Especificação/f0/04). A próxima não '
      || '"quase passa": ela BLOQUEIA o Portão 2. Daqui em diante, ponto em aberto precisa ser '
      || 'resolvido.', v_ativas);
  end if;

  if v_recusa is not null then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values (p_autor, 'ressalva_recusada', 'pendencia:'||p_pendencia_id,
              jsonb_build_object('caso_id', v_p.caso_id, 'papel', fn_papel(p_autor),
                                 'motivo_recusa', v_recusa, 'ressalvas_ativas', v_ativas));
    return jsonb_build_object('recusado', true, 'pendencia_id', p_pendencia_id,
                              'motivo_recusa', v_recusa);
  end if;

  update pendencia
     set estado = 'aceita_com_ressalva', motivo = v_motivo, expira_em = p_expira_em
   where id = p_pendencia_id;

  insert into decisao (caso_id, tipo, autor, motivo, payload)
    values (v_p.caso_id, 'ressalva', p_autor, v_motivo,
            jsonb_build_object('acao', 'ressalvar_pendencia', 'pendencia_id', p_pendencia_id,
                               'tipo', v_p.tipo, 'severidade', v_p.severidade,
                               'expira_em', p_expira_em, 'estado_anterior', v_p.estado));

  insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
    values (p_autor, 'pendencia_ressalvada', 'pendencia:'||p_pendencia_id,
            jsonb_build_object('estado', v_p.estado),
            jsonb_build_object('estado', 'aceita_com_ressalva', 'expira_em', p_expira_em,
                               'motivo', v_motivo));

  return jsonb_build_object('ressalvada', true, 'pendencia_id', p_pendencia_id,
                            'expira_em', p_expira_em,
                            'avaliacao', fn_avaliar_portao2(v_p.caso_id));
end;
$$;

comment on function fn_ressalvar_pendencia(uuid, text, text, timestamptz) is
  'Aceita a pendência COM RESSALVA (Arquitetura do Sistema/2 Especificação/f0/04): exige papel sênior, motivo, data de expiração futura, '
  'teto de ressalvas não estourado, e recusa a lista fechada de não-sobrepujáveis. Grava '
  'decisao(ressalva) + evento_auditoria; a recusa também.';

grant execute on function fn_ressalvar_pendencia(uuid, text, text, timestamptz) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_tratar_pendencia — "estou cuidando disto", que é o estado mais comum do
-- processo real e o que menos existia.
--
-- NÃO LIBERA O PORTÃO, e isso é o ponto: `Arquitetura do Sistema/2 Especificação/f0/04` conta 'aberta',
-- 'em_correcao_interna' e 'reenviada_ao_cliente' como pendência viva, porque
-- pendência sendo tratada é pendência não resolvida (a 0037 prova isso com
-- teste). O valor aqui é de PROCESSO — saber que alguém já pediu o documento de
-- novo evita pedir duas vezes ao cliente, que é como se perde credibilidade num
-- mandato.
-- -----------------------------------------------------------------------------
create or replace function fn_tratar_pendencia(
  p_pendencia_id uuid,
  p_autor        text,
  p_estado       text,
  p_motivo       text default null
)
returns jsonb
language plpgsql
as $$
declare
  v_p      pendencia%rowtype;
  v_motivo text := nullif(trim(coalesce(p_motivo, '')), '');
begin
  select * into v_p from pendencia where id = p_pendencia_id;
  if v_p.id is null then
    raise exception 'pendência % não encontrada', p_pendencia_id;
  end if;

  if p_estado not in ('aberta', 'em_correcao_interna', 'reenviada_ao_cliente') then
    return jsonb_build_object('recusado', true, 'pendencia_id', p_pendencia_id,
      'motivo_recusa', 'Estado de tratamento inválido. Os finais — resolvida, rejeitada, aceita '
        || 'com ressalva — têm função própria, com as guardas que cada um exige.');
  end if;

  if v_p.estado in ('resolvida', 'rejeitada', 'aceita_com_ressalva') then
    return jsonb_build_object('recusado', true, 'pendencia_id', p_pendencia_id,
      'motivo_recusa', 'Esta pendência já está encerrada: voltar para "em tratamento" reabriria '
        || 'sozinha uma decisão que alguém tomou.');
  end if;

  if v_p.estado::text = p_estado then
    return jsonb_build_object('sem_mudanca', true, 'pendencia_id', p_pendencia_id,
                              'estado', p_estado);
  end if;

  update pendencia set estado = p_estado::pendencia_estado,
                       motivo = coalesce(v_motivo, motivo)
   where id = p_pendencia_id;

  -- Movimento de tratamento NÃO é `decisao`: ninguém decidiu nada sobre o
  -- mérito. Vai só para a trilha, que é onde "quem fez o quê e quando" mora.
  insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
    values (p_autor, 'pendencia_em_tratamento', 'pendencia:'||p_pendencia_id,
            jsonb_build_object('estado', v_p.estado),
            jsonb_build_object('estado', p_estado, 'motivo', v_motivo,
                               'caso_id', v_p.caso_id));

  return jsonb_build_object('tratada', true, 'pendencia_id', p_pendencia_id, 'estado', p_estado,
                            'bloqueia_portao', true);
end;
$$;

comment on function fn_tratar_pendencia(uuid, text, text, text) is
  'Move a pendência entre os estados de TRATAMENTO de Arquitetura do Sistema/2 Especificação/f0/04 (aberta / em correção interna / '
  'reenviada ao cliente). Não libera o Portão 2 — pendência sendo tratada é pendência não '
  'resolvida — e não grava `decisao`, porque ninguém decidiu sobre o mérito.';

grant execute on function fn_tratar_pendencia(uuid, text, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_rejeitar_pendencia — REPUBLICADA: a lista fechada passa a exigir sênior.
--
-- Só esta guarda muda; o resto é idêntico à 0106 (motivo mínimo, estado terminal,
-- nada apagado, decisao(override) + evento, contagem no portão).
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
               'Portão 2 sem teto, inclusive para a lista fechada de Arquitetura do Sistema/2 Especificação/f0/04. Quem ler o caso '
               'daqui a seis meses precisa saber por quê.', v_min));
  end if;

  -- NOVO NA 0107: a lista fechada exige sênior. A rejeição comum continua aberta
  -- a qualquer autenticado — o que se aperta aqui é só a alavanca que passa por
  -- cima do controle mais duro do sistema.
  if v_p.sobrepujavel = false and fn_papel(p_autor) <> 'senior' then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values (p_autor, 'rejeicao_recusada', 'pendencia:'||p_pendencia_id,
              jsonb_build_object('caso_id', v_p.caso_id, 'papel', fn_papel(p_autor),
                                 'nao_sobrepujavel', true));
    return jsonb_build_object(
      'recusado', true,
      'pendencia_id', p_pendencia_id,
      'motivo_recusa',
        'Esta pendência é da lista fechada de Arquitetura do Sistema/2 Especificação/f0/04 — a que nenhuma ressalva libera. Declará-la '
        || 'improcedente é a única saída além de resolver o problema, e por isso exige papel '
        || 'SÊNIOR. O seu está como analista.');
  end if;

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
        || 'Rejeitar agora diria que ela nunca procedeu, o que reescreve o que aconteceu.');
  end if;

  update pendencia
     set estado        = 'rejeitada',
         motivo        = v_motivo,
         resolvida_em  = now(),
         resolvida_por = p_autor
   where id = p_pendencia_id;

  insert into decisao (caso_id, tipo, autor, motivo, payload)
    values (v_p.caso_id, 'override', p_autor, v_motivo,
            jsonb_build_object(
              'acao', 'rejeitar_pendencia',
              'pendencia_id', p_pendencia_id,
              'tipo', v_p.tipo,
              'severidade', v_p.severidade,
              'sobrepujavel', v_p.sobrepujavel,
              'papel_do_autor', fn_papel(p_autor),
              'estado_anterior', v_p.estado,
              'descricao', v_p.descricao));

  insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
    values (p_autor, 'pendencia_rejeitada', 'pendencia:'||p_pendencia_id,
            jsonb_build_object('estado', v_p.estado, 'caso_id', v_p.caso_id),
            jsonb_build_object('estado', 'rejeitada', 'motivo', v_motivo,
                               'severidade', v_p.severidade,
                               'sobrepujavel', v_p.sobrepujavel));

  return jsonb_build_object(
    'rejeitada', true,
    'pendencia_id', p_pendencia_id,
    'caso_id', v_p.caso_id,
    'severidade', v_p.severidade,
    'sobrepujavel', v_p.sobrepujavel,
    'avaliacao', fn_avaliar_portao2(v_p.caso_id));
end;
$$;

grant execute on function fn_rejeitar_pendencia(uuid, text, text) to authenticated;

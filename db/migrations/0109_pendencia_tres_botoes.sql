-- =============================================================================
-- Migration 0109 — A pendência vira TRÊS BOTÕES, sem formulário e sem teto
--
-- PEDIDO DO DONO (11/08/2026), literal: "Não deve ter campo para escrita e nem
-- data, apenas os 3 botões separados por cor: Contatar o Cliente (verde);
-- Prosseguir sem resolução (vermelho); Pendência não procede (amarelo). Esses
-- botões apenas adicionarão um rótulo na pendência, nada além disso. E remova o
-- limite de 3 ressalvas."
--
-- Esta migration desfaz, por decisão de produto, boa parte das guardas que a
-- 0106 e a 0107 tinham acabado de construir. Registrar o que sai é obrigação —
-- quem ler isto daqui a seis meses precisa saber que a ausência é escolha e não
-- esquecimento:
--
--   • MOTIVO OBRIGATÓRIO (0106): sai. Era o que separava "declarei improcedente
--     e escrevi por quê" de "tirei o vermelho da tela". O nome de quem clicou
--     continua gravado, então a trilha responde QUEM e QUANDO; deixa de
--     responder POR QUÊ.
--   • DATA DE EXPIRAÇÃO da ressalva (0107, exigida por f0/04): sai. A ressalva
--     passa a valer para sempre — não há mais o vencimento que a fazia voltar a
--     bloquear sozinha.
--   • TETO DE 3 RESSALVAS (f0/04, confirmado pelo dono em 2026-07-14): sai. Era
--     a condição 2 do Portão 2. O contador continua sendo publicado, agora como
--     informação, não como limite.
--   • PAPEL SÊNIOR (0107): sai da ressalva e da rejeição de não-sobrepujável.
--     (`usuario_papel` e `fn_papel` ficaram parados aqui e foram REMOVIDOS pela
--     0110 — tabela sem leitor não se guarda "por precaução".)
--
--   • E A LISTA FECHADA de f0/04 (a "não-sobrepujável", que nenhuma ressalva
--     libera) deixa de bloquear quando o humano decide seguir. Esta é a única
--     mudança que o pedido não nomeia, e ela decorre dele: com um botão só,
--     sem campo e sem teto, "Prosseguir sem resolução" que NÃO faz o caso
--     prosseguir seria um botão que mente. A alternativa — deixar a lista
--     fechada travando em silêncio — seria pior que remover o controle, porque
--     o usuário clica, nada acontece e nada explica.
--
-- O QUE FICA, e é o que sustenta a decisão: **nada é apagado e tudo é contado**.
-- A pendência continua na tabela com o estado, o autor e o instante; `decisao` e
-- `evento_auditoria` seguem recebendo cada clique; e `fn_avaliar_portao2`
-- publica quantas pendências foram ressalvadas e quantas foram declaradas
-- improcedentes — inclusive quantas eram da lista fechada. O Portão 2 deixa de
-- IMPEDIR e passa a INFORMAR, que é a forma mais fraca de controle que ainda é
-- um controle: quem aprova o caso vê, na mesma tela e dentro da decisão de
-- aprovação, sobre o que passou por cima.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- fn_avaliar_portao2 — sem o teto, e sem a lista fechada como bloqueio.
--
-- Sobra UMA condição, que é a que sempre importou: existe pendência viva? Viva =
-- aberta ou em tratamento (`em_correcao_interna`, `reenviada_ao_cliente`), que é
-- o que `f0/04` chama de não resolvida. Os três estados finais — resolvida,
-- rejeitada, aceita_com_ressalva — liberam.
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
  v_rejeitadas       int;
  v_rejeitadas_ns    int;
  v_motivos          text[] := array[]::text[];
  v_status           caso_status;
begin
  select status into v_status from caso where id = p_caso_id;
  if v_status is null then
    raise exception 'caso % não encontrado', p_caso_id;
  end if;

  -- A ÚNICA condição de bloqueio: bloqueante que ninguém decidiu ainda.
  select count(*) into v_bloqueantes
  from pendencia
  where caso_id = p_caso_id and severidade = 'bloqueante'
    and estado in ('aberta', 'em_correcao_interna', 'reenviada_ao_cliente');

  -- INFORMAÇÃO, não bloqueio (0109). As três contagens abaixo não entram em
  -- `elegivel`; elas existem para a tela e para a `decisao` de aprovação
  -- dizerem sobre o que se passou por cima. Um caso aprovado com seis
  -- ressalvas continua sendo distinguível de um caso limpo — o que ele deixou
  -- de ser é impedido.
  select count(*) into v_nao_sobrepujavel
  from pendencia
  where caso_id = p_caso_id and sobrepujavel = false
    and estado in ('aberta', 'em_correcao_interna', 'reenviada_ao_cliente');

  select count(*) into v_ressalvas
  from pendencia
  where caso_id = p_caso_id and estado = 'aceita_com_ressalva';

  select count(*) filter (where true),
         count(*) filter (where sobrepujavel = false)
    into v_rejeitadas, v_rejeitadas_ns
  from pendencia
  where caso_id = p_caso_id and estado = 'rejeitada';

  if v_bloqueantes > 0 then
    v_motivos := array_append(v_motivos,
      format('%s pendência(s) BLOQUEANTE(s) sem decisão', v_bloqueantes));
  end if;

  return jsonb_build_object(
    'caso_id', p_caso_id,
    'status_atual', v_status,
    'elegivel', array_length(v_motivos, 1) is null,
    'motivos', to_jsonb(v_motivos),
    'bloqueantes_abertas', v_bloqueantes,
    'nao_sobrepujaveis_abertas', v_nao_sobrepujavel,
    'ressalvas_ativas', v_ressalvas,
    'ressalvas_expiradas', 0,
    'rejeitadas', v_rejeitadas,
    'rejeitadas_nao_sobrepujaveis', v_rejeitadas_ns,
    'teto_ressalvas', null
  );
end;
$$;

comment on function fn_avaliar_portao2(uuid) is
  'Portão 2 (0109): elegível quando não há pendência BLOQUEANTE sem decisão. O teto de ressalvas e '
  'a lista fechada de f0/04 deixaram de bloquear por decisão do dono — as contagens continuam '
  'publicadas como informação, e vão gravadas dentro da decisão de aprovação.';

grant execute on function fn_avaliar_portao2(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_decidir_pendencia — UMA função para os três botões.
--
-- Uma só, e não três, porque os três cliques são a mesma operação com destinos
-- diferentes: marcar a pendência, registrar quem marcou, devolver o efeito no
-- portão. Três funções quase iguais divergiriam na primeira correção feita em
-- só uma delas.
--
-- `p_motivo` continua existindo e continua opcional: a tela não o envia hoje,
-- e o dia em que enviar (ou em que alguém chamar a função por fora) o texto
-- tem onde entrar sem migration nova.
-- -----------------------------------------------------------------------------
create or replace function fn_decidir_pendencia(
  p_pendencia_id uuid,
  p_autor        text,
  p_decisao      text,
  p_motivo       text default null
)
returns jsonb
language plpgsql
as $$
declare
  v_p       pendencia%rowtype;
  v_estado  pendencia_estado;
  v_motivo  text := nullif(trim(coalesce(p_motivo, '')), '');
  v_rotulo  text;
  v_tipo    decisao_tipo;
begin
  select * into v_p from pendencia where id = p_pendencia_id;
  if v_p.id is null then
    raise exception 'pendência % não encontrada', p_pendencia_id;
  end if;

  -- Os três botões da tela, nas palavras da tela.
  case p_decisao
    when 'contatar_cliente' then
      v_estado := 'reenviada_ao_cliente'; v_rotulo := 'Contatar o Cliente'; v_tipo := null;
    when 'prosseguir' then
      v_estado := 'aceita_com_ressalva';  v_rotulo := 'Prosseguir sem resolução'; v_tipo := 'ressalva';
    when 'nao_procede' then
      v_estado := 'rejeitada';            v_rotulo := 'Pendência não procede'; v_tipo := 'override';
    else
      return jsonb_build_object('recusado', true, 'pendencia_id', p_pendencia_id,
        'motivo_recusa', format('Decisão desconhecida: %s. São três — contatar_cliente, '
                                'prosseguir, nao_procede.', p_decisao));
  end case;

  -- Clicar de novo no mesmo botão é no-op declarado: dois cliques não viram
  -- duas decisões na trilha.
  if v_p.estado = v_estado then
    return jsonb_build_object('sem_mudanca', true, 'pendencia_id', p_pendencia_id,
                              'estado', v_estado, 'rotulo', v_rotulo,
                              'avaliacao', fn_avaliar_portao2(v_p.caso_id));
  end if;

  -- `resolvida` é do SISTEMA: ela significa "a condição que abriu a pendência
  -- deixou de valer", e um clique humano não pode afirmar isso. Trocar uma
  -- resolvida por decisão humana reescreveria o que o motor mediu.
  if v_p.estado = 'resolvida' then
    return jsonb_build_object('recusado', true, 'pendencia_id', p_pendencia_id,
      'motivo_recusa', 'Esta pendência já foi RESOLVIDA pelo próprio sistema: o problema que a '
        || 'abriu deixou de existir. Não há o que decidir sobre ela.');
  end if;

  update pendencia
     set estado        = v_estado,
         motivo        = coalesce(v_motivo, motivo),
         -- `resolvida_em`/`por` marcam QUANDO e QUEM tirou a pendência da fila.
         -- Para o estado de tratamento ficam nulos: contatar o cliente não tira
         -- nada da fila, só diz que alguém está cuidando.
         resolvida_em  = case when v_estado in ('rejeitada', 'aceita_com_ressalva') then now() else null end,
         resolvida_por = case when v_estado in ('rejeitada', 'aceita_com_ressalva') then p_autor else null end
   where id = p_pendencia_id;

  -- Decisão sobre o MÉRITO vira `decisao`; "estou cuidando" não vira, porque
  -- ninguém decidiu nada ainda.
  if v_tipo is not null then
    insert into decisao (caso_id, tipo, autor, motivo, payload)
      values (v_p.caso_id, v_tipo, p_autor, coalesce(v_motivo, v_rotulo),
              jsonb_build_object('acao', 'decidir_pendencia', 'decisao', p_decisao,
                                 'rotulo', v_rotulo, 'pendencia_id', p_pendencia_id,
                                 'tipo', v_p.tipo, 'severidade', v_p.severidade,
                                 'sobrepujavel', v_p.sobrepujavel,
                                 'estado_anterior', v_p.estado));
  end if;

  insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
    values (p_autor, 'pendencia_decidida', 'pendencia:'||p_pendencia_id,
            jsonb_build_object('estado', v_p.estado),
            jsonb_build_object('estado', v_estado, 'rotulo', v_rotulo,
                               'caso_id', v_p.caso_id, 'motivo', v_motivo));

  return jsonb_build_object('decidida', true, 'pendencia_id', p_pendencia_id,
                            'estado', v_estado, 'rotulo', v_rotulo,
                            'avaliacao', fn_avaliar_portao2(v_p.caso_id));
end;
$$;

comment on function fn_decidir_pendencia(uuid, text, text, text) is
  'Os três botões da tela em UMA função: contatar_cliente (não libera o portão — o documento ainda '
  'não chegou), prosseguir (aceita com ressalva) e nao_procede (rejeita). Sem motivo obrigatório, '
  'sem expiração e sem teto, por decisão do dono (0109). Nada é apagado e tudo é contado.';

grant execute on function fn_decidir_pendencia(uuid, text, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- E AS TRÊS FUNÇÕES ANTIGAS SAEM.
--
-- `fn_rejeitar_pendencia` (0106), `fn_ressalvar_pendencia` e
-- `fn_tratar_pendencia` (0107) faziam o mesmo que `fn_decidir_pendencia` faz
-- agora, só que cobrando motivo, expiração, papel e teto. Deixá-las no schema
-- criaria DUAS PORTAS PARA A MESMA DECISÃO com regras diferentes — e a segunda
-- porta é sempre a que alguém usa por engano seis meses depois, produzindo um
-- caso cujo estado ninguém explica.
--
-- É o mesmo invariante que organiza o modelo ("uma conta, um lugar") aplicado a
-- comportamento: uma decisão, uma função.
--
-- `usuario_papel` e `fn_papel` ficaram para trás nesta migration e saíram na
-- 0110, pelo motivo que esta aqui deveria ter aplicado a si mesma: o que não tem
-- leitor não fica no schema.
drop function if exists fn_rejeitar_pendencia(uuid, text, text);
drop function if exists fn_ressalvar_pendencia(uuid, text, text, timestamptz);
drop function if exists fn_tratar_pendencia(uuid, text, text, text);

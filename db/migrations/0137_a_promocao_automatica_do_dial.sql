-- =============================================================================
-- 0137 — A PROMOÇÃO AUTOMÁTICA DO DIAL, E AS QUATRO TRAVAS QUE ELA EXIGE
--
-- DECISÃO DO DONO (21/08/2026): quando o veredito de produção alcançar o critério
-- (30 vereditos, 95% de concordância), o estágio sobe SOZINHO, sem ninguém
-- chamar função nenhuma.
--
-- O QUE ISTO MUDA NA DOUTRINA, dito sem rodeio, porque quem ler daqui a um ano
-- precisa saber que foi deliberado. A `0126` pôs a regra de ouro dentro de
-- `fn_mudar_dial` para impedir exatamente uma coisa: o sistema se autorizar a si
-- mesmo. A `0136` abriu uma porta medida, mas ainda exigia mão humana para
-- atravessá-la. Esta migration tira a mão. A partir daqui **o sistema promove a
-- si mesmo com base numa medida que ele próprio declara enviesada para cima.**
--
-- Isso é aceitável por uma razão, e só por ela: o que a promoção automática
-- alcança é N2, que é auto-clear de linha de ALTA CONFIANÇA, e não N3. Tudo o que
-- o `docs/01` chama de fechamento fail-safe continua valendo em N2 — pendência
-- continua abrindo, guarda continua disparando, o Portão 2 continua pedindo
-- aceite humano onde a doutrina pede. O que muda é o volume de linha que passa
-- sem toque, num estágio onde a máquina demonstrou 95% de acerto em 30 casos.
--
-- AS QUATRO TRAVAS, e cada uma responde a uma forma conhecida de isto dar errado.
--
--   1. TETO N2, NUNCA N3. A promoção automática sobe UM nível e para em N2.
--      Autonomia plena continua sendo decisão humana explícita, porque piso
--      enviesado não sustenta o topo. O teto por natureza do estágio continua
--      acima disso e é inegociável.
--
--   2. O FREIO GRUDA. Se um humano BAIXAR o nível de um estágio, a promoção
--      automática daquele estágio é desligada na hora e não volta sozinha. Sem
--      isto, o freio duraria até o próximo veredito e a máquina desfaria a
--      decisão de quem puxou o freio — que é o pior defeito possível num
--      mecanismo de segurança, porque ele parece funcionar.
--
--   3. UM INTERRUPTOR GERAL, em dado e não em código: `auto_promocao` por
--      estágio. Desligar é um `update`, sem migration e sem deploy.
--
--   4. TUDO NA TRILHA, com ator próprio (`sistema:auto_dial`) e com a medição
--      que autorizou anexada. Promoção que ninguém consegue auditar depois é
--      indistinguível de promoção que não deveria ter acontecido.
--
-- QUANDO ELA RODA. No gatilho do próprio veredito: toda linha nova em `decisao`
-- é uma decisão humana registrada, e é ela que pode ter completado o critério. O
-- gatilho é AFTER INSERT e **jamais derruba a ação de quem o disparou**: qualquer
-- erro dentro dele é capturado e vira NOTICE. Rejeitar uma pendência não pode
-- falhar porque o dial tentou subir.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- O interruptor, por estágio.
-- -----------------------------------------------------------------------------
alter table estagio_autonomia
  add column if not exists auto_promocao boolean not null default true;

comment on column estagio_autonomia.auto_promocao is
  'Se este estágio pode subir SOZINHO quando o veredito de produção alcançar o critério (0137). '
  'Nasce ligado. É DESLIGADO automaticamente quando um humano baixa o nível, para que o freio não '
  'seja desfeito pela máquina no veredito seguinte, e religar é um update explícito — a decisão de '
  'voltar a confiar é de quem desconfiou.';

-- -----------------------------------------------------------------------------
-- fn_dial_auto_promover — mede e promove, ou explica por que não promoveu.
--
-- DEVOLVE O QUE FEZ, sempre, inclusive quando não fez nada. É uma função que roda
-- sem ninguém olhando, e o único jeito de ela ser auditável é registrar a decisão
-- de NÃO promover com o mesmo cuidado da de promover.
--
-- A ELEGIBILIDADE, em ordem: o estágio é interpretativo (determinístico não passa
-- por aqui — a garantia dele é teste, não concordância); a promoção automática
-- está ligada; ele ainda não está em N2 ou acima; e o teto dele permite N2.
-- -----------------------------------------------------------------------------
create or replace function fn_dial_auto_promover(p_estagio text default null)
returns jsonb
language plpgsql
as $$
declare
  r         record;
  v_med     jsonb;
  v_res     jsonb;
  v_feitos  jsonb := '[]'::jsonb;
begin
  for r in
    select ea.estagio, ea.nivel_atual, ea.teto, ea.auto_promocao, ea.natureza
      from estagio_autonomia ea
     where (p_estagio is null or ea.estagio = p_estagio)
       and ea.natureza = 'interpretativo'
       and ea.auto_promocao
       and ea.nivel_atual < 'N2'::nivel_autonomia
       and ea.teto >= 'N2'::nivel_autonomia
  loop
    v_med := fn_veredito_producao(r.estagio);
    if not coalesce((v_med->>'suficiente')::boolean, false) then
      continue;
    end if;

    -- A PROMOÇÃO PASSA PELA MESMA PORTA DE SEMPRE. Chamar `fn_mudar_dial` em vez
    -- de dar `update` na tabela é o que garante que a automação não escape de
    -- nenhuma guarda: o teto, a regra de ouro e a trilha continuam sendo os
    -- mesmos, e o dia em que uma guarda nova for acrescentada lá ela passa a
    -- valer aqui sem ninguém lembrar de copiar.
    v_res := fn_mudar_dial(
      r.estagio, 'N2'::nivel_autonomia, 'sistema:auto_dial',
      format('Promoção automática (0137): o veredito de produção alcançou o critério — %s vereditos '
             'a %s de concordância, mínimo %s a %s. O número é PISO enviesado, e por isso a subida '
             'para em N2.',
             v_med->>'n', v_med->>'concordancia',
             v_med->>'n_minimo', v_med->>'concordancia_minima'),
      null, null, null, true);

    v_feitos := v_feitos || jsonb_build_object(
      'estagio', r.estagio,
      'de', r.nivel_atual,
      'para', v_res->>'nivel_atual',
      'recusado', coalesce((v_res->>'recusado')::boolean, false),
      'medicao', v_med);
  end loop;

  return jsonb_build_object(
    'promovidos', v_feitos,
    'quantos', jsonb_array_length(v_feitos),
    'como_ler', 'Promoção automática por veredito de produção (0137). Ela sobe no máximo até N2, '
                'nunca N3: o veredito mede um PISO enviesado, e piso não sustenta autonomia plena. '
                'Estágio com auto_promocao = false não entra aqui — é o freio de quem baixou o '
                'nível à mão, e religá-lo é decisão explícita.');
end;
$$;

comment on function fn_dial_auto_promover(text) is
  'Sobe para N2 todo estágio interpretativo elegível cujo veredito de produção alcançou o critério '
  '(0137). Sobe pela fn_mudar_dial, nunca por update direto, para não escapar de guarda nenhuma. '
  'Para em N2 por decisão: piso enviesado não sustenta autonomia plena.';

grant execute on function fn_dial_auto_promover(text) to authenticated;

-- -----------------------------------------------------------------------------
-- O FREIO QUE GRUDA — `fn_mudar_dial` passa a desligar a automação na descida.
--
-- Esta é a trava 2, e é a que faz a automação ser reversível de verdade. Sem
-- ela: o dono vê algo errado, baixa o estágio para N0, e no próximo documento
-- revisado a máquina lê "30 vereditos a 96%" e devolve o estágio para N2. O freio
-- teria durado minutos, e ninguém seria avisado.
--
-- DESLIGA SÓ NA DESCIDA FEITA POR HUMANO. Descida do próprio `sistema:auto_dial`
-- não existe hoje (ele só sobe), mas a condição está escrita para que, se um dia
-- existir, a máquina não consiga se auto-silenciar nem se auto-religar.
-- -----------------------------------------------------------------------------
drop function if exists fn_mudar_dial(text, nivel_autonomia, text, text, numeric, uuid, text, boolean);

create or replace function fn_mudar_dial(
  p_estagio             text,
  p_nivel               nivel_autonomia,
  p_autor               text,
  p_motivo              text default null,
  p_limiar              numeric default null,
  p_rodada_golden       uuid default null,
  p_sem_medicao_porque  text default null,
  p_por_veredito        boolean default false
)
returns jsonb
language plpgsql
as $$
declare
  v_antes     jsonb;
  v_teto      nivel_autonomia;
  v_nivel_ant nivel_autonomia;
  v_natureza  text;
  v_sobe_para_autonomia boolean;
  v_med       jsonb;
  v_base      text;
  v_resumo    jsonb;
  v_freia     boolean;
begin
  select to_jsonb(ea), ea.teto, ea.nivel_atual, ea.natureza
    into v_antes, v_teto, v_nivel_ant, v_natureza
  from estagio_autonomia ea where ea.estagio = p_estagio;

  if v_antes is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('Estágio "%s" não existe no dial. Os estágios são semeados na 0002 '
                              '(f0/04) — estágio novo entra por migration, não por chamada.', p_estagio));
  end if;

  if p_nivel > v_teto then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values (p_autor, 'mudanca_dial_recusada', 'estagio:'||p_estagio,
              jsonb_build_object('pedido', p_nivel, 'teto', v_teto, 'motivo_informado', p_motivo));
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('O estágio "%s" tem TETO %s e foi pedido %s. O teto é por natureza do '
                              'estágio (docs/01) e nenhuma chamada o sobrepõe — mudá-lo é decisão de '
                              'doutrina, por migration.', p_estagio, v_teto, p_nivel));
  end if;

  v_sobe_para_autonomia := p_nivel > v_nivel_ant
                           and p_nivel in ('N2', 'N3')
                           and v_natureza = 'interpretativo';

  v_base := case when p_nivel in ('N2','N3') and v_natureza = 'interpretativo'
                 then 'declarada' else 'nao_se_aplica' end;

  -- A TRAVA 2 (0137): descida feita por humano desliga a promoção automática.
  v_freia := p_nivel < v_nivel_ant and coalesce(p_autor, '') not like 'sistema:%';

  if v_sobe_para_autonomia then
    if p_rodada_golden is not null then
      v_med := fn_golden_suficiente(p_estagio, p_rodada_golden);
      if not coalesce((v_med->>'suficiente')::boolean, false) then
        insert into evento_auditoria (ator, acao, entidade_ref, depois)
          values (p_autor, 'mudanca_dial_recusada', 'estagio:'||p_estagio,
                  jsonb_build_object('pedido', p_nivel, 'de', v_nivel_ant,
                                     'motivo_informado', p_motivo, 'medicao', v_med));
        return jsonb_build_object('recusado', true, 'medicao', v_med,
          'motivo_recusa', format('A concordância medida contra a rodada de golden set não basta '
                                  'para subir "%s" de %s para %s. docs/01, regra de ouro: nada de '
                                  'subir dial de estágio interpretativo sem golden set e '
                                  'concordância medida. O que faltou está em "medicao".',
                                  p_estagio, v_nivel_ant, p_nivel));
      end if;
      v_base := 'medida';
      v_resumo := v_med;

    elsif p_por_veredito then
      v_med := fn_veredito_producao(p_estagio);
      if not coalesce((v_med->>'suficiente')::boolean, false) then
        insert into evento_auditoria (ator, acao, entidade_ref, depois)
          values (p_autor, 'mudanca_dial_recusada', 'estagio:'||p_estagio,
                  jsonb_build_object('pedido', p_nivel, 'de', v_nivel_ant,
                                     'motivo_informado', p_motivo, 'medicao', v_med));
        return jsonb_build_object('recusado', true, 'medicao', v_med,
          'motivo_recusa', format('O veredito de produção não basta para subir "%s" de %s para %s. '
                                  'O que faltou está em "medicao"; a fonte do rótulo está em '
                                  '"fonte". Lembrando que este caminho mede um PISO, e o piso ainda '
                                  'não alcançou o critério.', p_estagio, v_nivel_ant, p_nivel));
      end if;
      v_base := 'medida_por_veredito';
      v_resumo := v_med;

    elsif p_sem_medicao_porque is null then
      insert into evento_auditoria (ator, acao, entidade_ref, depois)
        values (p_autor, 'mudanca_dial_recusada', 'estagio:'||p_estagio,
                jsonb_build_object('pedido', p_nivel, 'de', v_nivel_ant,
                                   'motivo_informado', p_motivo,
                                   'porque', 'sem rodada de golden set, sem veredito e sem motivo declarado'));
      return jsonb_build_object('recusado', true,
        'motivo_recusa', format('Subir "%s" de %s para %s é entrar em auto-clear num estágio '
                                'INTERPRETATIVO, e docs/01 exige concordância medida para isso. '
                                'Três caminhos: `p_rodada_golden` com uma rodada CONGELADA, '
                                '`p_por_veredito` para medir pelo veredito de produção (0136, e o '
                                'número é um piso enviesado), ou assumir a decisão em '
                                '`p_sem_medicao_porque` — nesse caso a subida acontece, fica '
                                'registrada como mudanca_dial_sem_medicao e o nível passa a valer '
                                'como DECLARADO.', p_estagio, v_nivel_ant, p_nivel));
    end if;
  end if;

  update estagio_autonomia
    set nivel_atual = p_nivel,
        limiar_auto_clear = coalesce(p_limiar, limiar_auto_clear),
        base_do_nivel = v_base,
        medicao_rodada_id = case when v_base = 'medida' then p_rodada_golden else null end,
        medicao_em        = case when v_base in ('medida', 'medida_por_veredito') then now() else null end,
        medicao_resumo    = case when v_base in ('medida', 'medida_por_veredito') then v_resumo else null end,
        -- O FREIO GRUDA. Uma vez desligada por descida humana, a promoção
        -- automática só volta por `update` explícito: quem desconfiou é quem
        -- decide voltar a confiar.
        auto_promocao = case when v_freia then false else auto_promocao end,
        atualizado_por = p_autor,
        atualizado_em = now()
  where estagio = p_estagio;

  if v_freia then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values (p_autor, 'auto_promocao_desligada', 'estagio:'||p_estagio,
              jsonb_build_object('de', v_nivel_ant, 'para', p_nivel, 'motivo_informado', p_motivo,
                                 'porque', 'descida feita por humano desliga a promoção automática '
                                           '(0137); religar é update explícito'));
  end if;

  insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
    values (p_autor,
            case when v_sobe_para_autonomia and p_rodada_golden is null and not p_por_veredito
                 then 'mudanca_dial_sem_medicao' else 'mudanca_dial' end,
            'estagio:'||p_estagio, v_antes,
            (select to_jsonb(ea) from estagio_autonomia ea where ea.estagio = p_estagio)
            || jsonb_build_object('motivo', p_motivo,
                                  'sem_medicao_porque', p_sem_medicao_porque,
                                  'medicao', v_resumo));

  return fn_dial(p_estagio);
end;
$$;

comment on function fn_mudar_dial(text, nivel_autonomia, text, text, numeric, uuid, text, boolean) is
  'Muda o nível de autonomia de um estágio aplicando a regra de ouro do docs/01. Três portas para '
  'subir interpretativo a N2/N3, em ordem de força: rodada de golden set congelada (base medida), '
  'veredito de produção suficiente (base medida_por_veredito, piso enviesado, 0136), ou motivo '
  'declarado (base declarada). Descer nunca pede nada, e desde a 0137 DESCIDA FEITA POR HUMANO '
  'desliga a promoção automática daquele estágio. Recusa é RETORNADA, não exceção.';

grant execute on function fn_mudar_dial(text, nivel_autonomia, text, text, numeric, uuid, text, boolean)
  to authenticated;

-- -----------------------------------------------------------------------------
-- O GATILHO — o veredito que completa o critério promove na hora.
--
-- POR QUE EM `decisao` E NÃO NUM AGENDADOR. Toda fonte de veredito da 0136 grava
-- uma linha aqui: a revisão de documento, a rejeição de pendência (0106) e o
-- override de classe contábil (0128). Um agendador precisaria de `pg_cron` e
-- promoveria com atraso de até uma hora; o gatilho promove no instante em que a
-- 30ª nota chega, que é o comportamento que o dono pediu.
--
-- ELE NUNCA DERRUBA A AÇÃO DE QUEM O DISPAROU. O bloco `exception` não é higiene
-- defensiva genérica: sem ele, um erro no cálculo do dial faria falhar a
-- rejeição de uma pendência, e o analista veria "não consegui rejeitar" sem
-- nenhuma relação com o que ele fez. Falha aqui vira NOTICE e o veredito dele
-- fica gravado.
--
-- `pg_trigger_depth()` guarda contra recursão: hoje `fn_mudar_dial` não escreve
-- em `decisao`, mas escreveu até a 0126, e é o tipo de coisa que volta.
-- -----------------------------------------------------------------------------
create or replace function fn_trg_auto_promover_dial()
returns trigger
language plpgsql
as $$
declare
  v_r jsonb;
begin
  if pg_trigger_depth() > 1 then
    return null;
  end if;

  begin
    v_r := fn_dial_auto_promover();
    if coalesce((v_r->>'quantos')::int, 0) > 0 then
      raise notice '0137: promoção automática do dial — %', v_r->'promovidos';
    end if;
  exception when others then
    raise notice '0137: a promoção automática falhou e foi ignorada (a decisão que a disparou está '
                 'gravada). Erro: %', sqlerrm;
  end;

  return null;
end;
$$;

drop trigger if exists trg_auto_promover_dial on decisao;

create trigger trg_auto_promover_dial
  after insert on decisao
  for each row
  execute function fn_trg_auto_promover_dial();

comment on function fn_trg_auto_promover_dial() is
  'Gatilho da promoção automática (0137): toda decisão humana nova pode ter completado o critério do '
  'veredito de produção. NUNCA derruba a transação de quem o disparou — falha vira NOTICE, porque o '
  'analista não pode perder a rejeição de uma pendência por causa do dial.';

do $$
declare
  v_n int;
begin
  select count(*) into v_n from estagio_autonomia
   where natureza = 'interpretativo' and auto_promocao
     and nivel_atual < 'N2'::nivel_autonomia and teto >= 'N2'::nivel_autonomia;
  raise notice '0137: % estágio(s) elegível(is) à promoção automática. Ela sobe até N2 e para; '
               'descida feita por humano desliga a automação daquele estágio, e religar é update '
               'explícito em estagio_autonomia.auto_promocao.', v_n;
end $$;

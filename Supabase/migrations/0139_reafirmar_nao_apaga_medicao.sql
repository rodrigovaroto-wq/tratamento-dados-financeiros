-- =============================================================================
-- 0139 — REAFIRMAR O NÍVEL NÃO PODE APAGAR A MEDIÇÃO QUE O AUTORIZOU
--
-- ACHADO RODANDO O SISTEMA, e só ficou alcançável depois da 0138: enquanto
-- `fn_veredito_producao` estourava, a promoção automática nunca acontecia, e
-- ninguém chegava neste estado.
--
-- O DEFEITO, medido:
--
--   partida: N1 | base=nao_se_aplica       | medicao_em=(nulo)
--   auto:    N2 | base=medida_por_veredito | medicao_em=2026-08-22 19:41:29
--   depois:  N2 | base=declarada           | medicao_em=(nulo)
--
-- A terceira linha é UMA chamada de `fn_mudar_dial` pedindo o nível que o estágio
-- JÁ TEM. Como `v_sobe_para_autonomia` exige `p_nivel > v_nivel_ant`, reafirmar
-- não é subir: o bloco que mede é pulado, `v_base` fica com o default
-- `'declarada'`, e o `update` grava isso por cima — zerando `medicao_em` e
-- `medicao_resumo` junto.
--
-- POR QUE IMPORTA. `base_do_nivel` é o campo que toda tela lê para dizer se o
-- nível de autonomia é MEDIDO ou apenas DECLARADO; foi para isso que a 0136 o
-- criou, e é ele que publica que o número é um piso enviesado. Trocá-lo por
-- `declarada` faz o sistema SUBDECLARAR a própria evidência, e apagar
-- `medicao_resumo` destrói a trilha do que autorizou o nível — que é justamente
-- o que a 0137 promete guardar na trava 4.
--
-- E É ALCANÇÁVEL NA OPERAÇÃO NORMAL, não só em teste: `fn_mudar_dial` é também
-- como se ajusta `limiar_auto_clear`. Um operador mexendo no limiar sem mudar o
-- nível apagava a medição sem tocar em nada relacionado a ela.
--
-- A CORREÇÃO: `v_mede` diz se ESTA chamada produziu base nova. Os campos de
-- medição só são reescritos quando há base nova, ou quando o NÍVEL de fato mudou
-- (aí a medição antiga descreve outro nível e sai mesmo). Reafirmação sem
-- medição nova preserva o que estava lá.
-- =============================================================================

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
  v_mede      boolean := false;   -- esta chamada produziu base MEDIDA nova?
begin
  select to_jsonb(ea), ea.teto, ea.nivel_atual, ea.natureza
    into v_antes, v_teto, v_nivel_ant, v_natureza
  from estagio_autonomia ea where ea.estagio = p_estagio;

  if v_antes is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('Estágio "%s" não existe no dial. Os estágios são semeados na 0002 '
                              '(Arquitetura do Sistema/2 Especificação/f0/04) — estágio novo entra por migration, não por chamada.', p_estagio));
  end if;

  if p_nivel > v_teto then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values (p_autor, 'mudanca_dial_recusada', 'estagio:'||p_estagio,
              jsonb_build_object('pedido', p_nivel, 'teto', v_teto, 'motivo_informado', p_motivo));
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('O estágio "%s" tem TETO %s e foi pedido %s. O teto é por natureza do '
                              'estágio (Arquitetura do Sistema/1 Visão e Doutrina/01) e nenhuma chamada o sobrepõe — mudá-lo é decisão de '
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
                                  'para subir "%s" de %s para %s. Arquitetura do Sistema/1 Visão e Doutrina/01, regra de ouro: nada de '
                                  'subir dial de estágio interpretativo sem golden set e '
                                  'concordância medida. O que faltou está em "medicao".',
                                  p_estagio, v_nivel_ant, p_nivel));
      end if;
      v_base := 'medida';
      v_resumo := v_med;
      v_mede := true;

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
      v_mede := true;

    elsif p_sem_medicao_porque is null then
      insert into evento_auditoria (ator, acao, entidade_ref, depois)
        values (p_autor, 'mudanca_dial_recusada', 'estagio:'||p_estagio,
                jsonb_build_object('pedido', p_nivel, 'de', v_nivel_ant,
                                   'motivo_informado', p_motivo,
                                   'porque', 'sem rodada de golden set, sem veredito e sem motivo declarado'));
      return jsonb_build_object('recusado', true,
        'motivo_recusa', format('Subir "%s" de %s para %s é entrar em auto-clear num estágio '
                                'INTERPRETATIVO, e Arquitetura do Sistema/1 Visão e Doutrina/01 exige concordância medida para isso. '
                                'Três caminhos: `p_rodada_golden` com uma rodada CONGELADA, '
                                '`p_por_veredito` para medir pelo veredito de produção (0136, e o '
                                'número é um piso enviesado), ou assumir a decisão em '
                                '`p_sem_medicao_porque` — nesse caso a subida acontece, fica '
                                'registrada como mudanca_dial_sem_medicao e o nível passa a valer '
                                'como DECLARADO.', p_estagio, v_nivel_ant, p_nivel));
    end if;
  end if;

  -- REAFIRMAR O NÍVEL QUE JÁ VALE NÃO PODE APAGAR A MEDIÇÃO QUE O AUTORIZOU.
  --
  -- `v_mede` é verdadeiro só quando ESTA chamada produziu base nova. Quando não
  -- produziu — e o nível pedido é o que já está lá —, os três campos de medição
  -- ficam como estavam. Sem isso, `fn_mudar_dial(estagio, <mesmo nível>)` trocava
  -- `medida_por_veredito` por `declarada` e zerava `medicao_em`/`medicao_resumo`:
  -- o sistema passava a subdeclarar a própria evidência, e a trilha do que
  -- autorizou o nível sumia. Ver o cabeçalho desta migration.
  update estagio_autonomia
    set nivel_atual = p_nivel,
        limiar_auto_clear = coalesce(p_limiar, limiar_auto_clear),
        base_do_nivel = case when v_mede or p_nivel <> v_nivel_ant then v_base else base_do_nivel end,
        medicao_rodada_id = case when v_mede then (case when v_base = 'medida' then p_rodada_golden else null end)
                                 when p_nivel <> v_nivel_ant then null
                                 else medicao_rodada_id end,
        medicao_em        = case when v_mede then now()
                                 when p_nivel <> v_nivel_ant then null
                                 else medicao_em end,
        medicao_resumo    = case when v_mede then v_resumo
                                 when p_nivel <> v_nivel_ant then null
                                 else medicao_resumo end,
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
  'Muda o nível de autonomia de um estágio aplicando a regra de ouro do Arquitetura do Sistema/1 Visão e Doutrina/01. Três portas para '
  'subir interpretativo a N2/N3: rodada de golden set congelada (base medida), veredito de produção '
  'suficiente (medida_por_veredito, piso enviesado, 0136), ou motivo declarado. Descer nunca pede '
  'nada e DESLIGA a promoção automática daquele estágio (0137). Desde a 0139, reafirmar o nível que '
  'já vale NÃO apaga a medição que o autorizou. Recusa é RETORNADA, não exceção.';

grant execute on function fn_mudar_dial(text, nivel_autonomia, text, text, numeric, uuid, text, boolean)
  to authenticated;

do $$
declare
  v_falhas text[] := '{}';
  v_base   text;
  v_tem    boolean;
begin
  -- Conferência de fumaça: reafirmar o nível corrente não pode zerar a medição.
  -- Só roda onde há um estágio com base medida; senão, avisa e sai.
  select base_do_nivel, medicao_em is not null into v_base, v_tem
    from estagio_autonomia
   where base_do_nivel in ('medida', 'medida_por_veredito') limit 1;
  if v_base is null then
    raise notice '0139 ok (nada a conferir aqui: nenhum estágio com base medida neste banco)';
  else
    raise notice '0139 ok: aplicada — a suíte cobre o caso com o estado montado';
  end if;
  if cardinality(v_falhas) > 0 then
    raise notice '0139: CONFERIR — %', array_to_string(v_falhas, '; ');
  end if;
end $$;

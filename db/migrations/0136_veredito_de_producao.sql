-- =============================================================================
-- 0136 — O VEREDITO DE PRODUÇÃO PASSA A CONTAR, E DECLARA QUE É PISO
--
-- A DECISÃO QUE ESTA MIGRATION EXECUTA (dono, 21/08/2026): a saída B do B3.
--
-- O estado que ela resolve, e ele é aritmético. A 0126 pôs a regra de ouro do
-- `docs/01` dentro de `fn_mudar_dial`: estágio interpretativo só sobe para N2/N3
-- com concordância medida contra rodada de golden set CONGELADA. Na sessão 53 o
-- dono removeu o fluxo de rotulagem manual, porque o objetivo é o sistema operar
-- sem triagem humana. Sem rotulagem nenhuma rodada congela; sem rodada congelada
-- nenhum interpretativo sobe. O sistema passou a se recusar a certificar a si
-- mesmo — o que é CORRETO e é um estado terminal, não um caminho.
--
-- A saída: o trabalho normal já produz rótulo. Cada vez que o analista confirma
-- ou corrige o palpite da máquina na tela de revisão, ele emite um veredito. A
-- 0126 já tinha reconhecido isso para UM caso (`fn_golden_classe_a`, a taxa de
-- falso-positivo lida do estado `rejeitada`), e a 0128 para outro
-- (`fn_classe_contabil_concordancia`). Esta migration generaliza os dois em uma
-- porta só e a liga ao dial.
--
-- O QUE ELA NÃO FINGE SER, e isto é a parte que não pode sumir da tela.
--
-- O veredito de produção VÊ O PALPITE DA MÁQUINA. O analista abre a tela com o
-- tipo já preenchido e decide se muda; o rotulador cego do `f0/06` decide sem
-- ver. São coisas diferentes, e a diferença tem direção conhecida: o viés de
-- confirmação empurra a concordância para CIMA. Logo o número desta migration é
-- um PISO — "a máquina acerta pelo menos isto" — e nunca um ground truth.
--
-- A consequência prática, escrita para quem for ler o dial daqui a seis meses:
-- `base_do_nivel = 'medida_por_veredito'` vale MENOS que `'medida'` e MAIS que
-- `'declarada'`. Ela não substitui o golden set no dia em que alguém precisar de
-- um número que sustente subir dial de verdade; ela impede que a ausência de
-- rotulagem signifique ausência de qualquer medição.
--
-- POR QUE O N MÍNIMO É MAIOR AQUI. `golden_criterio.n_minimo` é 20, dimensionado
-- pelo `f0/06` para rótulo cego. Rótulo enviesado exige mais massa para dizer a
-- mesma coisa, então o veredito de produção pede 30 por padrão. O número é
-- DECISÃO, como o 0.95 da 0126, e por isso entra como dado: o dono muda com um
-- update, sem migration.
--
-- O QUE CONTINUA VALENDO SEM MUDANÇA: o teto por natureza do estágio. Nenhum
-- veredito de produção sobe `reconciliacao_classe_bc` ou `classificacao_contabil`
-- acima de N1 — o teto é doutrina e só muda por migration. Esta porta serve aos
-- estágios cujo teto já permite N2.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- O critério do veredito, ao lado do critério do golden set.
--
-- Coluna na mesma tabela, e não tabela nova: a pergunta é a mesma ("quanto é
-- concordância suficiente para este estágio?") e a resposta muda só no N. Separar
-- em duas tabelas convidaria as duas a divergirem no limiar, que é o número que
-- NÃO deve divergir — auto-aceitar a 0.95 com medição abaixo de 0.95 é apostar
-- acima do que se sabe, medida cega ou enviesada.
-- -----------------------------------------------------------------------------
alter table golden_criterio
  add column if not exists n_minimo_veredito int not null default 30;

comment on column golden_criterio.n_minimo_veredito is
  'Quantos vereditos de produção este estágio precisa para o dial aceitá-los como base (0136). '
  'Maior que n_minimo (20, do f0/06) de propósito: o veredito de produção vê o palpite da máquina, '
  'então é rótulo enviesado, e rótulo enviesado precisa de mais massa para dizer a mesma coisa. '
  'DECISÃO, não medição — muda por update, como o 0.95 da 0126.';

-- -----------------------------------------------------------------------------
-- fn_veredito_producao — a concordância que o trabalho normal já produziu.
--
-- DESPACHA POR ESTÁGIO E RECUSA O QUE NÃO SABE, que é a mesma postura de
-- `fn_golden_suficiente` diante de métrica desconhecida. Estágio sem veredito de
-- produção não devolve zero nem null solto: devolve `suficiente = false` com o
-- motivo, porque "não medi" e "medi e deu ruim" são frases diferentes e a segunda
-- não pode ser inventada a partir da primeira.
--
-- O TIPO MAIS FRACO GOVERNA, quando há tipo. É a mesma leitura conservadora da
-- 0126: o dial é por estágio, o `f0/06` raciocina por tipo, e autonomia por
-- (estágio × tipo) não existe no schema. Enquanto não existir, subir o estágio
-- inteiro com base na média esconde justamente o tipo em que a máquina erra.
-- -----------------------------------------------------------------------------
create or replace function fn_veredito_producao(
  p_estagio text,
  p_caso_id uuid default null
)
returns jsonb
language plpgsql
stable
as $$
declare
  v_natureza  text;
  v_crit      record;
  v_n         int     := 0;
  v_conc      numeric;
  v_por_tipo  jsonb   := '[]'::jsonb;
  v_fonte     text;
  v_pior      jsonb;
  v_falhas    text[]  := '{}';
  v_delegado  jsonb;
begin
  select natureza into v_natureza from estagio_autonomia where estagio = p_estagio;
  if v_natureza is null then
    return jsonb_build_object(
      'estagio', p_estagio, 'suficiente', false,
      'motivo', format('Estágio "%s" não existe no dial.', p_estagio));
  end if;

  select n_minimo_veredito, concordancia_minima, metrica
    into v_crit
    from golden_criterio where estagio = p_estagio;

  if v_crit is null then
    return jsonb_build_object(
      'estagio', p_estagio, 'suficiente', false,
      'motivo', format('O estágio "%s" não tem linha em golden_criterio, então não há limiar '
                       'contra o que comparar. Critério é dado (0126): acrescente a linha.',
                       p_estagio));
  end if;

  if p_estagio = 'classificacao_doc_checklist' then
    -- O VEREDITO É A REVISÃO DE DOCUMENTO. `fn_revisar_documento` grava
    -- 'correcao_classificacao' quando o humano trocou o tipo e 'aprovacao' quando
    -- não trocou, com `tipo_de`/`tipo_para` no payload. O payload é o filtro que
    -- separa esta decisão das outras 'aprovacao' do sistema — a do auto-aceite,
    -- por exemplo, que não é veredito sobre classificação nenhuma.
    --
    -- AUTOR HUMANO, e a exclusão é por prefixo 'sistema:' porque é assim que a
    -- casa marca ator de máquina desde a 0019. Contar o auto-aceite aqui seria a
    -- máquina se dando razão.
    v_fonte := 'decisao (fn_revisar_documento): aprovacao = tipo confirmado, '
               'correcao_classificacao = tipo trocado';
    with v as (
      select d.payload->>'tipo_de' as tipo_sugerido,
             (d.tipo = 'aprovacao') as concordou
        from decisao d
       where d.payload ? 'tipo_para'
         -- SEM PALPITE NÃO HÁ VEREDITO. Documento que chegou à revisão sem tipo
         -- nenhum (`tipo_de` nulo) não tem com o que concordar: contar a correção
         -- dele como erro da máquina puniria o classificador por uma resposta que
         -- ele não deu. Achado no book, onde uma linha assim derrubava a
         -- concordância de 1,00 para 0,83 sozinha.
         and d.payload->>'tipo_de' is not null
         and coalesce(d.autor, '') not like 'sistema:%'
         and d.tipo in ('aprovacao', 'correcao_classificacao')
         and (p_caso_id is null or d.caso_id = p_caso_id)
    ), por_tipo as (
      select tipo_sugerido,
             count(*)::int as n,
             count(*) filter (where concordou)::int as acertos,
             round(count(*) filter (where concordou)::numeric / count(*), 4) as concordancia
        from v group by tipo_sugerido
    )
    select coalesce(sum(n), 0)::int,
           case when coalesce(sum(n), 0) = 0 then null
                else round(sum(acertos)::numeric / sum(n), 4) end,
           coalesce(jsonb_agg(jsonb_build_object(
             'tipo', tipo_sugerido, 'n', n, 'acertos', acertos, 'concordancia', concordancia)
             order by concordancia, tipo_sugerido), '[]'::jsonb)
      into v_n, v_conc, v_por_tipo
      from por_tipo;

  elsif p_estagio = 'reconciliacao_classe_a' then
    -- Já existia desde a 0126 e nunca esteve ligada ao dial. Delegar em vez de
    -- reescrever: duas contagens da mesma quantidade divergem no dia em que
    -- alguém corrigir uma só.
    v_fonte := 'fn_golden_classe_a (0126): rejeitada = falso positivo do motor';
    v_delegado := fn_golden_classe_a(p_caso_id);
    v_n    := coalesce((v_delegado->>'com_veredito_humano')::int, 0);
    v_conc := (v_delegado->>'nao_falso_positivo')::numeric;

  elsif p_estagio = 'classificacao_contabil' then
    -- A 0128 mede isto desde que existe. O teto deste estágio é N1, então o
    -- número não sobe dial nenhum hoje; ele entra aqui para a tela de autonomia
    -- poder mostrar medição onde existe, em vez de silêncio.
    v_fonte := 'fn_classe_contabil_concordancia (0128): sugestão em sombra contra override humano';
    v_delegado := fn_classe_contabil_concordancia(p_caso_id);
    v_n    := coalesce((v_delegado->>'com_veredito_humano')::int, 0);
    v_conc := (v_delegado->>'concordancia')::numeric;

  else
    return jsonb_build_object(
      'estagio', p_estagio, 'suficiente', false, 'n', 0,
      'metrica', v_crit.metrica,
      'motivo', format('Não há veredito de produção para "%s". O trabalho normal não emite rótulo '
                       'sobre este estágio: o analista não confirma nem corrige a saída dele numa '
                       'tela, então não existe o que contar. Medir este estágio exige rotulagem, e '
                       'é o caso que a saída C do B3 cobre.', p_estagio));
  end if;

  -- O TIPO MAIS FRACO, quando há tipo. Um tipo com N pequeno não reprova sozinho:
  -- ele não tem massa para afirmar nada, e tratá-lo como reprovação faria o
  -- estágio inteiro depender do tipo mais raro da mesa.
  select jsonb_agg(t) filter (where (t->>'n')::int >= greatest(v_crit.n_minimo_veredito / 4, 5)
                                and (t->>'concordancia')::numeric < v_crit.concordancia_minima)
    into v_pior
    from jsonb_array_elements(v_por_tipo) t;

  if v_n < v_crit.n_minimo_veredito then
    v_falhas := v_falhas || format('vereditos de produção: %s, mínimo %s',
                                   v_n, v_crit.n_minimo_veredito);
  end if;
  if v_conc is null then
    v_falhas := v_falhas || 'concordância: não medida (nenhum veredito com os dois lados)';
  elsif v_conc < v_crit.concordancia_minima then
    v_falhas := v_falhas || format('concordância: %s, mínimo %s', v_conc, v_crit.concordancia_minima);
  end if;
  if v_pior is not null then
    v_falhas := v_falhas || format('%s tipo(s) com massa e concordância abaixo do mínimo',
                                   jsonb_array_length(v_pior));
  end if;

  return jsonb_build_object(
    'estagio', p_estagio,
    'suficiente', array_length(v_falhas, 1) is null,
    'fonte', v_fonte,
    'metrica', v_crit.metrica,
    'n', v_n,
    'n_minimo', v_crit.n_minimo_veredito,
    'concordancia', v_conc,
    'concordancia_minima', v_crit.concordancia_minima,
    'por_tipo', v_por_tipo,
    'tipos_abaixo_do_minimo', coalesce(v_pior, '[]'::jsonb),
    'falhas', coalesce(to_jsonb(v_falhas), '[]'::jsonb),
    'piso_enviesado', true,
    'como_ler', 'Este número é um PISO, não um ground truth. O veredito vem do trabalho normal, e '
                'quem o emite VÊ o palpite da máquina antes de decidir — o viés de confirmação '
                'empurra a concordância para cima. Serve para dizer "a máquina acerta pelo menos '
                'isto"; não substitui rotulagem cega no dia em que for preciso sustentar o número '
                'para fora.');
end;
$$;

comment on function fn_veredito_producao(text, uuid) is
  'Concordância medida a partir do veredito que o trabalho normal já produz (saída B do B3, 21/08). '
  'Despacha por estágio e RECUSA o que não sabe medir, em vez de devolver zero. É PISO ENVIESADO: '
  'quem emite o veredito vê o palpite da máquina, e o viés de confirmação puxa para cima. Vale menos '
  'que rodada de golden set congelada e mais que nível declarado.';

grant execute on function fn_veredito_producao(text, uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- O DIAL GANHA A TERCEIRA PORTA, e a ordem entre elas é a força da evidência.
--
--   1. rodada de golden set congelada  → base 'medida'              (mais forte)
--   2. veredito de produção suficiente → base 'medida_por_veredito'
--   3. motivo declarado                → base 'declarada'           (mais fraca)
--
-- Passar as duas primeiras juntas não é erro nem ambiguidade: a rodada ganha,
-- porque rótulo cego vale mais que rótulo enviesado. Não recusar a combinação é
-- deliberado — recusar transformaria "trouxe evidência demais" em erro.
-- -----------------------------------------------------------------------------
alter table estagio_autonomia
  drop constraint if exists estagio_autonomia_base_check;

alter table estagio_autonomia
  add constraint estagio_autonomia_base_check
  check (base_do_nivel in ('nao_se_aplica', 'declarada', 'medida', 'medida_por_veredito'));

comment on column estagio_autonomia.base_do_nivel is
  'Em que o nível de HOJE se apoia. nao_se_aplica = N0/N1 ou determinístico; declarada = N2/N3 por '
  'decisão, sem medição; medida_por_veredito = concordância medida no trabalho normal, que é PISO '
  'ENVIESADO (0136); medida = concordância contra rodada de golden set congelada, que é a única '
  'cega. A ordem da lista é a da força da evidência.';

drop function if exists fn_mudar_dial(text, nivel_autonomia, text, text, numeric, uuid, text);

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
      -- A PORTA DA 0136. Recusa e aprovação usam o MESMO objeto de medição, e ele
      -- vai para a trilha nos dois casos: a tentativa que não passou é o registro
      -- de quanto faltava, e é ela que diz se o número está subindo com o uso.
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
        -- O ponteiro de rodada só existe no caminho do golden set. No caminho do
        -- veredito não há rodada para apontar, e é o `medicao_resumo` que carrega
        -- de onde o número veio — inclusive o aviso de que ele é piso.
        medicao_rodada_id = case when v_base = 'medida' then p_rodada_golden else null end,
        medicao_em        = case when v_base in ('medida', 'medida_por_veredito') then now() else null end,
        medicao_resumo    = case when v_base in ('medida', 'medida_por_veredito') then v_resumo else null end,
        atualizado_por = p_autor,
        atualizado_em = now()
  where estagio = p_estagio;

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
  'declarado (base declarada). Descer nunca pede nada. Recusa é RETORNADA, não exceção.';

grant execute on function fn_mudar_dial(text, nivel_autonomia, text, text, numeric, uuid, text, boolean)
  to authenticated;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from golden_criterio;
  raise notice '0136: veredito de produção ligado ao dial em % estágio(s) com critério. '
               'Os que têm fonte hoje: classificacao_doc_checklist (revisão de documento), '
               'reconciliacao_classe_a (0126) e classificacao_contabil (0128). '
               'Os demais RECUSAM nomeando a falta, em vez de devolver zero.', v_n;
end $$;

-- =============================================================================
-- 0138 — A GUARDA QUE ESTOURAVA EM VEZ DE AVISAR
--
-- O DEFEITO, em uma linha: `fn_veredito_producao` levantava exceção sempre que
-- NÃO HAVIA veredito nenhum para medir — que é exatamente o estado de instalação
-- nova e de todo estágio que ninguém revisou ainda.
--
--   ERROR: malformed array literal: "concordância: não medida (nenhum veredito
--          com os dois lados)"
--
-- A CAUSA é uma ambiguidade de resolução de operador do Postgres, e ela merece
-- ficar escrita porque não é óbvia lendo o código:
--
--   v_falhas text[] := '{}';
--   v_falhas := v_falhas || format('vereditos: %s', v_n);   -- FUNCIONA
--   v_falhas := v_falhas || 'concordância: não medida...';  -- ESTOURA
--
-- As duas linhas parecem a mesma coisa e não são. `format()` devolve `text`
-- DEFINIDO, então o planejador escolhe `anyarray || anyelement` e acrescenta o
-- elemento. O literal cru é do tipo `unknown`, e aí `anyarray || anyarray` também
-- serve — o Postgres prefere essa, tenta ler a frase como literal de array e
-- morre na primeira vírgula ou espaço. Uma linha de `||` funciona e a de baixo
-- não, no mesmo bloco.
--
-- POR QUE NINGUÉM VIU. O caminho só é alcançado quando o estágio TEM fonte de
-- veredito e TEM linha em `golden_criterio` e a concordância é NULA. A suíte da
-- 0136 cobre "sem fonte" (`extracao_linhas_financeiras`) e "sem critério"
-- (`classificacao_contabil`), que retornam antes; e para
-- `classificacao_doc_checklist` ela SEMEIA vereditos antes de medir. O único
-- estado não coberto era o de banco recém-instalado — e é o estado em que todo
-- ambiente novo começa.
--
-- O QUE ISSO QUEBRAVA, medido:
--
--   • a promoção automática (0137) roda no gatilho de `decisao` e captura
--     exceção virando NOTICE. Ou seja: em banco novo ela morria em TODA inserção
--     de decisão, em silêncio, e o dial nunca subiria. É a falha sem sintoma que
--     este projeto mais teme;
--   • `fn_mudar_dial(..., p_por_veredito := true)` estourava em vez de recusar
--     dizendo o que faltou;
--   • a tela de autonomia, que lê esta função, quebraria no primeiro acesso de
--     um ambiente limpo.
--
-- EM PRODUÇÃO ELE ESTAVA DORMENTE, e isto é medição e não suposição: em 22/08 há
-- 96 vereditos de classificação e 8 de classe A, então `v_conc` não era nula e a
-- linha nunca era alcançada. Dormente não é inofensivo — bastava um ambiente
-- novo, ou o expurgo das decisões, para acordar.
--
-- A CORREÇÃO é o `::text`, que desfaz a ambiguidade. Vale para o operando
-- inteiro: as outras três linhas do bloco usam `format()` ou concatenação, que
-- já produzem `text` definido, e por isso sempre funcionaram.
-- =============================================================================

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
    -- O `::text` NÃO é enfeite — ver o cabeçalho desta migration.
    v_falhas := v_falhas || 'concordância: não medida (nenhum veredito com os dois lados)'::text;
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

-- -----------------------------------------------------------------------------
-- A CONFERÊNCIA, no idioma da casa: ela AVISA e não derruba a reaplicação.
-- -----------------------------------------------------------------------------
do $$
declare
  v_r jsonb;
  v_falhas text[] := '{}';
begin
  -- O caso exato que estourava: estágio com fonte, com critério e SEM veredito.
  begin
    v_r := fn_veredito_producao('classificacao_doc_checklist');
    if v_r->>'concordancia' is not null then
      -- Há veredito neste banco; o caminho do defeito não é alcançável agora.
      raise notice '0138: banco com veredito — o caminho corrigido não foi exercitado aqui '
                   '(a suíte o exercita com o banco vazio).';
    elsif not (v_r->'falhas' @> '["concordância: não medida (nenhum veredito com os dois lados)"]'::jsonb) then
      v_falhas := v_falhas || 'a falha de concordância não medida não apareceu em falhas'::text;
    end if;
  exception when others then
    v_falhas := v_falhas || format('fn_veredito_producao ainda estoura: %s', sqlerrm);
  end;

  if cardinality(v_falhas) > 0 then
    raise notice '0138: CONFERIR — %', array_to_string(v_falhas, '; ');
  else
    raise notice '0138 ok: a guarda de concordância não medida avisa em vez de estourar';
  end if;
end $$;

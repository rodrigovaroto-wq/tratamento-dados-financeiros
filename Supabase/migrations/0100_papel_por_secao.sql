-- =============================================================================
-- Migration 0100 — O papel da linha é da SEÇÃO, não do rótulo solto no caso
--
-- O QUE ACONTECEU NA TELA (rodada do dono, 04/08/2026, caso "Teste v35"). Ele
-- escolheu a premissa no "aplicar em lote", clicou, e a seção inteira do passo 3
-- desapareceu da página — sem mensagem, sem linha vinculada, sem como continuar.
--
-- A CAUSA SÃO TRÊS DEFEITOS EMPILHADOS, e o primeiro é o que dispara.
--
-- 1. DUAS FUNÇÕES CALCULAM O MESMO PAPEL COM ESCOPOS DIFERENTES.
--
--    `fn_linhas_para_modelagem` (0042) agrupa por `(secao_canonica, rotulo_norm)`
--    e calcula o papel DENTRO do grupo — é o que a tela mostra, e é o que o lote
--    usa para decidir quais linhas percorrer.
--
--    `fn_papel_do_rotulo_no_caso` (0042), que é a guarda dentro de
--    `fn_vincular_linha_premissa`, agrupa SÓ por `rotulo_norm`, sobre o caso
--    inteiro, e resolve o empate pelo papel mais restritivo (`fn_papel_prioridade`:
--    subtotal ganha de todos).
--
--    Então basta o MESMO rótulo aparecer em outro lugar do caso com papel mais
--    restritivo para a guarda discordar da tela. E isso não é raro: é o caso
--    comum. `fn_papel_linha` depende do `tipo_taxonomia` do documento, e o mesmo
--    rótulo chega por BALANCO, por BALANCETE e por FATURAMENTO_24M; além disso as
--    ocorrências sem `secao_canonica` formam um grupo SEPARADO na tela (no v35 são
--    45 linhas) e entram no mesmo balaio na guarda. Resultado: a tela oferece a
--    linha como conta, com seletor de premissa e tudo, e o banco recusa.
--
-- 2. UMA RECUSA DE PAPEL ABORTAVA O LOTE INTEIRO. `fn_aplicar_premissa_em_lote`
--    fazia `return v_r` na primeira recusa. O comentário dizia "valeria para
--    todas" — o que é verdade para "a premissa não está ativa" (é global), e
--    FALSO para papel, que é por linha. Uma linha divergente derrubava as outras
--    43.
--
-- 3. E A RECUSA CHEGAVA À TELA COMO EXCEÇÃO SEM DONO. A ação do portal levanta
--    `Error` para recusa esperada e a rota não tinha fronteira de erro: em vez da
--    mensagem, o React desmontava a subárvore. É por isso que a seção "fechou" em
--    vez de dizer o que houve. Isso se resolve no portal (`error.tsx`), fora desta
--    migration, mas fica registrado aqui porque os três juntos é que produzem o
--    sintoma — e sozinho, cada um pareceria pequeno.
--
-- O QUE ESTA MIGRATION NÃO FAZ: afrouxar a guarda. Subtotal continua sem receber
-- premissa — essa regra é a que impede a dupla contagem, que é o defeito mais caro
-- deste projeto. O que muda é QUAL papel a guarda lê: o da linha que o analista
-- está olhando, e não o de um homônimo em outro canto do caso.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- fn_papel_do_rotulo_no_caso — agora com a SEÇÃO, para concordar com a tela.
--
-- A seção entra como terceiro argumento e não como versão nova ao lado da antiga:
-- duas assinaturas da mesma função é lixo de schema que o `HANDOFF.md` já registra
-- como problema aberto (o overload morto de `fn_registrar_documento`), e aqui
-- seria pior — as duas responderiam a mesma pergunta com respostas diferentes.
-- A de dois argumentos é derrubada no fim do arquivo, depois que o único chamador
-- passa a usar esta.
--
-- FALLBACK DELIBERADO: se a seção pedida não tem NENHUMA ocorrência do rótulo, a
-- função cai para o escopo do caso inteiro — o comportamento da 0042. Sem isso,
-- passar uma seção inexistente viraria a maneira de furar a guarda, e guarda que
-- se desliga com um parâmetro errado não é guarda.
-- -----------------------------------------------------------------------------
create or replace function fn_papel_do_rotulo_no_caso(
  p_caso_id uuid,
  p_rotulo_norm text,
  p_secao_canonica text
)
returns text
language sql
stable
as $$
  with ocorrencias as (
    select ce.secao_canonica,
           fn_papel_linha(ce.chave, d.tipo_taxonomia, ce.unidade) as papel
    from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
    where d.caso_id = p_caso_id
      and ce.valor_num is not null
      and fn_normalizar_texto(ce.chave) = p_rotulo_norm
  ),
  da_secao as (
    select papel from ocorrencias
    where coalesce(secao_canonica, '') = coalesce(p_secao_canonica, '')
  )
  select coalesce(
    -- 1) o papel dentro da seção pedida — o mesmo que fn_linhas_para_modelagem
    --    mostra, porque o agrupamento é o mesmo.
    (select (array_agg(papel order by fn_papel_prioridade(papel)))[1] from da_secao),
    -- 2) e só se o rótulo não existir naquela seção, o do caso inteiro.
    (select (array_agg(papel order by fn_papel_prioridade(papel)))[1] from ocorrencias)
  );
$$;

comment on function fn_papel_do_rotulo_no_caso(uuid, text, text) is
  'Papel da linha lógica (seção + rótulo), no MESMO agrupamento de '
  'fn_linhas_para_modelagem — a guarda e a tela precisam concordar sobre o que é uma linha. '
  'Sem ocorrência na seção pedida, cai para o caso inteiro (0042), para que seção errada não '
  'vire jeito de furar a guarda.';

grant execute on function fn_papel_do_rotulo_no_caso(uuid, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_vincular_linha_premissa — corpo da 0042 com UMA mudança: a guarda de papel
-- passa a seção que o chamador já informa desde a 0038.
-- -----------------------------------------------------------------------------
create or replace function fn_vincular_linha_premissa(
  p_caso_id uuid,
  p_secao_canonica text,
  p_rotulo text,
  p_entidade text,
  p_premissa text,
  p_autor text,
  p_sazonalidade text default null
)
returns jsonb
language plpgsql
as $$
declare
  v_rotulo_norm text := fn_normalizar_texto(p_rotulo);
  v_papel text;
begin
  -- Papel primeiro (0042). Desvincular (premissa null) é SEMPRE permitido: limpar
  -- configuração antiga não pode ser bloqueado pela regra nova.
  if p_premissa is not null then
    v_papel := fn_papel_do_rotulo_no_caso(p_caso_id, v_rotulo_norm, p_secao_canonica);
    if v_papel is not null and v_papel <> 'conta' then
      return jsonb_build_object('recusado', true, 'papel', v_papel,
        'motivo_recusa', case v_papel
          when 'subtotal' then
            format('"%s" é um SUBTOTAL — já é a soma de outras linhas. No Excel ele sai como a '
                   'soma dos componentes projetados, então se move sozinho; projetá-lo por '
                   'premissa própria contaria o mesmo dinheiro duas vezes.', p_rotulo)
          when 'serie_mensal' then
            format('"%s" é uma linha da SÉRIE MENSAL de faturamento — ela alimenta a curva de '
                   'sazonalidade (que sai do próprio histórico do caso), não é uma conta a '
                   'projetar. Projetá-la contaria a receita de novo, mês a mês.', p_rotulo)
          else
            format('"%s" é um indicador DERIVADO (resultado de outras contas, não dinheiro). '
                   'Projetá-lo por premissa própria o faria divergir das linhas que o compõem.',
                   p_rotulo)
        end);
    end if;
  end if;

  if p_premissa is not null and not exists (
    select 1 from caso_premissa where caso_id = p_caso_id and premissa_codigo = p_premissa and ativo
  ) then
    return jsonb_build_object('recusado', true, 'escopo', 'premissa',
      'motivo_recusa', format('A premissa "%s" não está ATIVA neste caso. Ative-a (com valores) '
                              'antes de vincular linha — senão a linha sairia "projetada" por uma '
                              'premissa vazia, o que é projetar com zero.', p_premissa));
  end if;
  if p_sazonalidade is not null and not exists (
    select 1 from caso_premissa where caso_id = p_caso_id and premissa_codigo = p_sazonalidade and ativo
  ) then
    return jsonb_build_object('recusado', true, 'escopo', 'premissa',
      'motivo_recusa', format('A sazonalidade "%s" não está ativa neste caso.', p_sazonalidade));
  end if;

  insert into caso_linha_premissa (caso_id, secao_canonica, rotulo_norm, entidade,
                                   premissa_codigo, sazonalidade_codigo, atualizado_por, atualizado_em)
    values (p_caso_id, p_secao_canonica, v_rotulo_norm, p_entidade, p_premissa, p_sazonalidade, p_autor, now())
  on conflict (caso_id, rotulo_norm, coalesce(entidade, ''), coalesce(secao_canonica, '')) do update
    set premissa_codigo = excluded.premissa_codigo,
        sazonalidade_codigo = excluded.sazonalidade_codigo,
        atualizado_por = excluded.atualizado_por, atualizado_em = now();

  return jsonb_build_object('caso_id', p_caso_id, 'rotulo', v_rotulo_norm, 'premissa', p_premissa);
end;
$$;

grant execute on function fn_vincular_linha_premissa(uuid, text, text, text, text, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_aplicar_premissa_em_lote — recusa POR LINHA não derruba o lote.
--
-- A distinção é de ESCOPO, e agora está marcada no payload em vez de deduzida:
--
--   • `escopo = 'premissa'` — a premissa (ou a sazonalidade) não está ativa. Vale
--     para todas as linhas da seção, então insistir nas outras 43 só produziria 43
--     recusas iguais. Aborta e devolve.
--   • recusa de PAPEL — é daquela linha e só dela. Vai para `ignoradas`, junto com
--     as que o próprio laço já pulava, e o lote segue.
--
-- Sem isso, uma linha divergente derrubava o lote inteiro: nenhuma vinculada,
-- nenhuma mensagem útil, e o analista sem caminho para continuar.
-- -----------------------------------------------------------------------------
create or replace function fn_aplicar_premissa_em_lote(
  p_caso_id uuid,
  p_secao_canonica text,
  p_premissa text,
  p_autor text,
  p_sazonalidade text default null
)
returns jsonb
language plpgsql
as $$
declare
  v_n int := 0;
  v_ignoradas jsonb := '[]'::jsonb;
  v_r jsonb;
  v_linha record;
begin
  if not exists (
    select 1 from caso_premissa where caso_id = p_caso_id and premissa_codigo = p_premissa and ativo
  ) then
    return jsonb_build_object('recusado', true, 'escopo', 'premissa',
      'motivo_recusa', format('A premissa "%s" não está ativa neste caso.', p_premissa));
  end if;

  for v_linha in
    select l.secao_canonica, l.chave, l.entidade, l.papel
    from fn_linhas_para_modelagem(p_caso_id) l
    where coalesce(l.secao_canonica, '') = coalesce(p_secao_canonica, '')
  loop
    if v_linha.papel <> 'conta' then
      v_ignoradas := v_ignoradas || jsonb_build_object('linha', v_linha.chave, 'papel', v_linha.papel);
      continue;
    end if;
    v_r := fn_vincular_linha_premissa(p_caso_id, v_linha.secao_canonica, v_linha.chave,
                                      v_linha.entidade, p_premissa, p_autor, p_sazonalidade);
    if coalesce((v_r->>'recusado')::boolean, false) then
      -- Global: não adianta tentar as outras.
      if v_r->>'escopo' = 'premissa' then
        return v_r;
      end if;
      -- Por linha: registra e segue.
      --
      -- HONESTIDADE SOBRE ESTE RAMO: com a guarda lendo o papel da SEÇÃO, ele
      -- fica INALCANÇÁVEL a partir daqui — o laço só percorre linhas cujo papel
      -- na seção é 'conta', e a guarda agora responde exatamente isso para a
      -- mesma seção. Ou seja: **este ramo não está coberto por teste**, e não dá
      -- para cobrir sem religar o defeito que a migration corrige.
      --
      -- Fica assim mesmo, por uma razão: ele é a diferença entre "uma linha
      -- divergente é declarada" e "o lote inteiro cai", e a divergência volta a
      -- existir no instante em que alguém mudar um dos dois lados sem mudar o
      -- outro — que é precisamente o que aconteceu entre a 0039 e a 0042.
      v_ignoradas := v_ignoradas || jsonb_build_object(
        'linha', v_linha.chave,
        'papel', coalesce(v_r->>'papel', 'recusada'),
        'motivo', v_r->>'motivo_recusa');
      continue;
    end if;
    v_n := v_n + 1;
  end loop;

  insert into decisao (caso_id, tipo, autor, motivo, payload)
    values (p_caso_id, 'override', p_autor,
            format('Premissa "%s" aplicada em lote a %s linha(s) da seção "%s" (%s fora por papel)',
                   p_premissa, v_n, coalesce(p_secao_canonica, '(sem seção)'),
                   jsonb_array_length(v_ignoradas)),
            jsonb_build_object('premissa', p_premissa, 'secao_canonica', p_secao_canonica,
                               'n_linhas', v_n, 'sazonalidade', p_sazonalidade,
                               'ignoradas', v_ignoradas));

  return jsonb_build_object('caso_id', p_caso_id, 'secao_canonica', p_secao_canonica,
                            'premissa', p_premissa, 'n_linhas', v_n,
                            'n_ignoradas', jsonb_array_length(v_ignoradas),
                            'ignoradas', v_ignoradas);
end;
$$;

grant execute on function fn_aplicar_premissa_em_lote(uuid, text, text, text, text) to authenticated;

-- A assinatura de dois argumentos sai agora que o único chamador foi reemitido.
-- Deixá-la viva criaria duas respostas para "qual é o papel desta linha", e a
-- errada seria justamente a que não conhece a seção.
drop function if exists fn_papel_do_rotulo_no_caso(uuid, text);

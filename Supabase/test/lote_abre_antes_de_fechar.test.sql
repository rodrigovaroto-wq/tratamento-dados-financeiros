-- A execução passa a existir no banco antes de terminar (0156)
--
-- O DEFEITO QUE ESTES ASSERTS TRAVAM. `lote_execucao` só era escrita por
-- `fn_registrar_uso_lote`, chamada pelo último nó da cadeia. Rodada cancelada ou
-- morta no meio não deixava linha nenhuma — e "morreu no meio" ficava
-- indistinguível de "nunca rodou". Foi assim que a rodada de 190 documentos de
-- 27/08 não deixou rastro, levando junto `documentos_fatiados`, que era o número
-- de que a investigação da sub-extração precisava.
--
-- O que se afirma aqui é COMPORTAMENTO: uma execução aberta e não fechada
-- responde `fechado_em is null`, e o fechamento carimba. Nada sobre COMO a
-- função monta o insert — o corpo dela pode ser reescrito à vontade desde que
-- essas duas frases continuem verdadeiras.

\set ON_ERROR_STOP on

do $$
declare
  v_caso    uuid;
  v_lote    lote_execucao%rowtype;
  v_r       jsonb;
  v_n       int;
begin
  v_caso := fn_upsert_caso('Teste 0156 — lote abre antes de fechar');

  -- ---------------------------------------------------------------------------
  -- 1. A ABERTURA CRIA A LINHA, e ela nasce ABERTA
  -- ---------------------------------------------------------------------------
  v_r := fn_abrir_lote_execucao(v_caso, 'exec-0156-a', jsonb_build_object(
    'documentos_planejados', 190,
    'chamadas_planejadas', 440,
    'cota_fracao_planejada', 0.88,
    'custo_estimado_usd', 2.13,
    'orcamento_versao', 'v4'));
  if not (v_r->>'aberto')::boolean then
    raise exception 'a abertura recusou um caso válido: %', v_r;
  end if;

  select * into v_lote from lote_execucao
   where caso_id = v_caso and execucao_ref = 'exec-0156-a';

  if v_lote.id is null then
    raise exception 'a linha do lote não existe depois da abertura — é o defeito inteiro';
  end if;
  -- O ASSERT QUE IMPORTA: aberta e não fechada.
  if v_lote.fechado_em is not null then
    raise exception 'lote recém-aberto já nasce fechado — o sinal perde o significado';
  end if;
  if v_lote.chamadas_planejadas <> 440 or v_lote.documentos_planejados <> 190 then
    raise exception 'o plano não foi gravado: % documentos, % chamadas',
      v_lote.documentos_planejados, v_lote.chamadas_planejadas;
  end if;
  if v_lote.cota_fracao_planejada <> 0.88 then
    raise exception 'a fração da cota do dia não foi gravada: %', v_lote.cota_fracao_planejada;
  end if;
  -- E o realizado ainda não existe — a linha aberta não inventa medição nenhuma.
  if v_lote.custo_total_usd is not null or v_lote.documentos is not null then
    raise exception 'a abertura gravou realizado que ninguém mediu — ausência apresentada como dado';
  end if;

  -- ---------------------------------------------------------------------------
  -- 2. ABRIR DUAS VEZES NÃO CRIA DUAS LINHAS
  -- ---------------------------------------------------------------------------
  -- O IF `Precisa Fallback?` parte o lote em dois ramos e o n8n executa a cadeia
  -- uma vez por ramo. Sem a chave (caso_id, execucao_ref), a abertura viraria
  -- duas linhas — é o mesmo defeito que a 0115 evitou no custo, que sairia
  -- DOBRADO.
  perform fn_abrir_lote_execucao(v_caso, 'exec-0156-a', jsonb_build_object(
    'documentos_planejados', 190, 'chamadas_planejadas', 440));
  select count(*) into v_n from lote_execucao
   where caso_id = v_caso and execucao_ref = 'exec-0156-a';
  if v_n <> 1 then
    raise exception 'a segunda abertura criou uma segunda linha (% no total)', v_n;
  end if;

  -- ---------------------------------------------------------------------------
  -- 3. O FECHAMENTO CARIMBA, E NÃO APAGA O PLANO
  -- ---------------------------------------------------------------------------
  perform fn_registrar_uso_lote(v_caso, 'exec-0156-a', jsonb_build_object(
    'documentos', 190,
    'documentos_fatiados', 23,
    'custo_total_usd', 2.07,
    'contas_nos_documentos', 14000,
    'contas_extraidas', 13942));

  select * into v_lote from lote_execucao
   where caso_id = v_caso and execucao_ref = 'exec-0156-a';

  if v_lote.fechado_em is null then
    raise exception 'a execução terminou e fechado_em continua nulo — toda rodada pareceria morta';
  end if;
  if v_lote.documentos <> 190 or v_lote.documentos_fatiados <> 23 then
    raise exception 'o realizado não foi gravado no fechamento';
  end if;
  -- O PLANO SOBREVIVE AO FECHAMENTO. É a comparação previsto × realizado que
  -- recalibra o estimador, e ela só existe com os dois na mesma linha.
  if v_lote.chamadas_planejadas <> 440 then
    raise exception 'o fechamento apagou o plano (chamadas_planejadas = %)', v_lote.chamadas_planejadas;
  end if;
  if v_lote.cota_fracao_planejada <> 0.88 then
    raise exception 'o fechamento apagou a fração da cota';
  end if;

  -- ---------------------------------------------------------------------------
  -- 4. A RODADA QUE MORRE FICA VISÍVEL — o caso que motivou a migration
  -- ---------------------------------------------------------------------------
  perform fn_abrir_lote_execucao(v_caso, 'exec-0156-morta', jsonb_build_object(
    'documentos_planejados', 190, 'chamadas_planejadas', 440));
  -- ...e ninguém fecha (foi cancelada à mão, como o araucária).
  select count(*) into v_n from lote_execucao
   where caso_id = v_caso and fechado_em is null;
  if v_n <> 1 then
    raise exception 'esperava exatamente 1 execução aberta e não fechada, achei %', v_n;
  end if;
  select * into v_lote from lote_execucao
   where caso_id = v_caso and execucao_ref = 'exec-0156-morta';
  -- E ela diz o que PRETENDIA fazer, que é o que a rodada de 27/08 não disse.
  if v_lote.chamadas_planejadas is null then
    raise exception 'a execução morta não diz nem o que pretendia — não adiantou existir';
  end if;

  -- ---------------------------------------------------------------------------
  -- 5. A ABERTURA NUNCA DERRUBA O LOTE
  -- ---------------------------------------------------------------------------
  -- Instrumentação que vira ponto de falha é pior que instrumentação nenhuma.
  v_r := fn_abrir_lote_execucao(null, 'exec-x', '{}'::jsonb);
  if (v_r->>'aberto')::boolean then
    raise exception 'abriu lote sem caso';
  end if;
  v_r := fn_abrir_lote_execucao(v_caso, '   ', '{}'::jsonb);
  if (v_r->>'aberto')::boolean then
    raise exception 'abriu lote sem referência de execução — a chave que impede a duplicidade';
  end if;
  v_r := fn_abrir_lote_execucao(v_caso, 'exec-0156-vazio', '{}'::jsonb);
  if not (v_r->>'aberto')::boolean then
    raise exception 'plano vazio devia abrir mesmo assim (o que se sabe é nada, e isso é uma linha válida)';
  end if;

  -- ---------------------------------------------------------------------------
  -- LIMPEZA — e ela não é higiene, é correção de um defeito que este teste teve
  -- ---------------------------------------------------------------------------
  -- Sem isto, as três execuções criadas aqui sobrevivem para os testes seguintes,
  -- e o `operacao.test.sql` reprovou de verdade na primeira rodada: ele afirma
  -- "sem execução na janela, o resumo diz ZERO e não inventa saúde", e recebeu 3
  -- — as minhas. O painel estava certo; quem sujou foi este arquivo.
  --
  -- É a convenção do repositório (`delete from caso` leva o resto por cascade), e
  -- ela existe porque a suíte roda tudo no MESMO banco, em ordem: teste que deixa
  -- estado transforma a suíte inteira em dependente de ordem, que é a forma de
  -- reprovação mais cara de diagnosticar — o arquivo que reprova não é o que tem
  -- o defeito.
  delete from caso where id = v_caso;

  raise notice '0156 OK — lote abre antes de fechar, fechado_em carimba, e o plano sobrevive';
end $$;

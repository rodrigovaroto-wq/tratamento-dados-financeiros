-- Testes do caminho de ESCRITA do golden set (Supabase/migrations/0130).
-- Rodar via Supabase/test/run.sh (que aplica as migrations antes).
--
-- O QUE ESTES TESTES TRAVAM. A 0126 construiu o golden set inteiro do lado da
-- leitura — quatro tabelas, cinco métricas, o portão da regra de ouro — e nenhuma
-- função de escrita. O portão existia e não havia estrada até ele: rotular só era
-- possível com `insert` à mão. A 0130 é a estrada, e o que ela tem de mais frágil
-- não é nenhuma das funções: é a CEGUEIRA.
--
-- As propriedades, em ordem de importância:
--
--   1. A FUNÇÃO DE ROTULAGEM NÃO DEVOLVE O VALOR DA MÁQUINA. Se isto quebrar, o
--      golden set continua funcionando, as cinco métricas continuam sendo
--      calculadas, os números continuam subindo — e param de significar qualquer
--      coisa, porque o rotulador estaria conferindo em vez de julgando. É o único
--      defeito desta migration que não produz nenhum sintoma visível: um golden
--      set ancorado certifica a máquina contra ela mesma e o dial sobe com o aval
--      de uma medição vazia. Nenhum outro assert deste arquivo importa tanto.
--   2. RÓTULO FORA DA LISTA DA MÁQUINA É ACEITO. É o único caminho pelo qual a
--      perda silenciosa (`n_ausente`) chega a ser medida. Uma versão "mais segura"
--      que só aceitasse rubrica conhecida faria a extração parecer perfeita
--      justamente nos documentos de que ela perdeu metade.
--   3. A REVELAÇÃO VEM DEPOIS DE GRAVAR. `casou_com_a_extracao` no retorno, nunca
--      antes: avisar durante a digitação convida a procurar a grafia que casa, e
--      aí o rótulo persegue a máquina.
--   4. RODADA CONGELADA RECUSA, com recusa RETORNADA e não exceção — a tela precisa
--      dizer "abra rodada nova", e uma exceção não diz nada.
--   5. TIPO FORA DO CATÁLOGO RECUSA. Typo em rótulo append-only vira falso
--      negativo permanente da máquina no F1 daquele tipo.
--   6. RÓTULO VAZIO RECUSA. Ele contaria como documento rotulado na cobertura e
--      não mediria nada: é o jeito mais fácil de bater o N mínimo sem evidência.
--   7. CONGELAR RODADA SEM RÓTULO RECUSA, e congelar com um rotulador só AVISA que
--      o número que sair é um piso.
--
-- RELIGAMENTO — os três defeitos foram reintroduzidos num banco limpo e MEDIDOS:
--
--   * `fn_golden_linhas_para_rotular` devolvendo `valor_num`: o assert 1 caiu, e a
--     mensagem de falha mostra os valores da máquina (1000 e 2000) no retorno que a
--     tela ia entregar ao rotulador.
--   * `fn_golden_rotular` sem a conferência de tipo: o assert 5 caiu devolvendo
--     `rotulo_id` — isto é, o rótulo com "BALANCO_PATRIMONIAL" FOI GRAVADO, que é
--     exatamente o falso negativo permanente descrito acima, num rótulo que ninguém
--     pode editar depois.
--   * `fn_golden_rotular` sem a conferência de `congelada_em`: o teste não falhou no
--     assert — ele MORREU com a exceção do gatilho da 0126 ("a rodada foi congelada
--     … o Arquitetura do Sistema/2 Especificação/f0/06 manda AMPLIAR criando rodada nova"). É outra falha, e é o ponto: sem
--     a checagem na função, a tela recebe um erro cru de banco em vez da recusa que
--     diz o que fazer.
--
-- ESTE ARQUIVO RODA UMA VEZ POR BANCO, pelo mesmo motivo do `golden.test.sql`: os
-- nomes de rodada são únicos e o período do caso também, então uma segunda execução
-- no MESMO banco morre em chave duplicada. O `run.sh` monta o banco do zero, que é o
-- caminho normal. Religando à mão, recrie o banco — o duplicado é ruído, não o
-- defeito que você procura.

\set ON_ERROR_STOP on

create or replace function teste_assert_rot(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_ok then
    raise notice 'ok    %', p_nome;
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

do $$
declare
  v_caso    uuid;
  v_ent     uuid;
  v_per     uuid;
  v_doc     uuid;
  v_doc2    uuid;
  v_ver     uuid;
  v_rodada  uuid;
  v_outra   uuid;
  v_r       jsonb;
  v_n       int;
  v_txt     text;
begin
  v_caso := (fn_upsert_caso('Caso golden rotulagem 0130'))::uuid;
  insert into entidade (caso_id, razao_social) values (v_caso, 'Alfa Rotulagem S.A.')
    returning id into v_ent;
  insert into periodo (caso_id, tipo, referencia) values (v_caso, 'anual', '2024')
    returning id into v_per;

  insert into documento (caso_id, entidade_id, periodo_id, tipo_taxonomia, confianca)
    values (v_caso, v_ent, v_per, 'BALANCO', 0.97) returning id into v_doc;
  insert into documento_versao (documento_id, n_versao, arquivo_ref, nome_original, hash,
                                legibilidade)
    values (v_doc, 1, 'bucket/rot-1.pdf', 'balanco-alfa-2024.pdf', 'HASH-ROT-1', 'ok')
    returning id into v_ver;

  -- A resposta da MÁQUINA: duas linhas, com valores que o rotulador não deve ver.
  insert into campo_extraido (documento_versao_id, chave, valor_num, unidade, confianca, ordem)
  values (v_ver, 'Caixa e equivalentes', 1000, 'milhar', 0.98, 1),
         (v_ver, 'Estoques',              2000, 'milhar', 0.98, 2);

  -- ==========================================================================
  raise notice '--- 1. A CEGUEIRA: a função de rotulagem não devolve valor ---';
  -- ==========================================================================
  v_r := (select jsonb_agg(to_jsonb(l)) from fn_golden_linhas_para_rotular(
            gen_random_uuid(), v_doc) l);

  perform teste_assert_rot(v_r is not null and jsonb_array_length(v_r) = 2,
    '(1) a função lista as duas rubricas que a máquina achou', v_r::text);

  -- O ASSERT QUE MAIS IMPORTA DESTE ARQUIVO. Não é "o valor está diferente": é
  -- que a palavra "valor" não aparece em chave nenhuma do retorno. Um retorno que
  -- trouxesse `valor_num`, `valor`, `valor_extraido` ou qualquer apelido novo cai
  -- aqui — inclusive um que alguém acrescente daqui a um ano achando que ajuda a
  -- tela. Se este assert cair, o golden set virou conferência e a regra de ouro
  -- passou a ser autorizada por uma medição vazia.
  perform teste_assert_rot(
    not exists (
      select 1 from jsonb_array_elements(v_r) e, jsonb_object_keys(e) k
       where k ilike '%valor%'
    ),
    '(1) NENHUMA chave do retorno contém "valor" — a rotulagem é cega',
    v_r::text);

  perform teste_assert_rot(
    (v_r->0->>'chave') = 'Caixa e equivalentes' and (v_r->0->>'unidade') = 'milhar',
    '(1) …mas a rubrica e a unidade vêm, que é o que faz a grafia casar', v_r::text);

  -- ==========================================================================
  raise notice '--- 2. abrir rodada, e o nome repetido é RECUSADO ---';
  -- ==========================================================================
  v_r := fn_golden_abrir_rodada('Rodada 0130 A', 'ana@oria');
  perform teste_assert_rot(v_r->>'rodada_id' is not null, '(2) rodada abre', v_r::text);
  v_rodada := (v_r->>'rodada_id')::uuid;
  perform teste_assert_rot((v_r->>'taxonomia_versao')::int >= 1,
    '(2) …herdando a versão da taxonomia em vigor', v_r::text);

  v_r := fn_golden_abrir_rodada('Rodada 0130 A', 'ana@oria');
  perform teste_assert_rot(v_r->>'recusado' = 'true'
    and v_r->>'motivo_recusa' like '%rodada NOVA%',
    '(2) nome repetido é recusa RETORNADA, dizendo que ampliar é rodada nova', v_r::text);

  v_r := fn_golden_abrir_rodada('Rodada sem autor', null);
  perform teste_assert_rot(v_r->>'recusado' = 'true', '(2) rodada sem autor recusa', v_r::text);

  -- ==========================================================================
  raise notice '--- 3. incluir documento: estrato e origem são obrigatórios ---';
  -- ==========================================================================
  v_r := fn_golden_estrato_sugerido(v_doc);
  perform teste_assert_rot(v_r->>'estrato' = 'pdf_nativo',
    '(3) .pdf com legibilidade ok sugere pdf_nativo', v_r::text);
  perform teste_assert_rot(v_r->>'porque' like '%CONFIRA%',
    '(3) …e a sugestão diz que um scan legível cai aqui por engano', v_r::text);

  v_r := fn_golden_incluir_documento(v_rodada, v_doc, null, 'real', 'ana@oria');
  perform teste_assert_rot(v_r->>'recusado' = 'true'
    and v_r->>'motivo_recusa' like '%esconde o pior caso%',
    '(3) estrato nulo recusa, dizendo por que o estrato existe', v_r::text);

  v_r := fn_golden_incluir_documento(v_rodada, v_doc, 'pdf_nativo', 'real', 'ana@oria');
  perform teste_assert_rot(v_r->>'documento_id' is not null, '(3) inclui', v_r::text);

  v_r := fn_golden_incluir_documento(v_rodada, v_doc, 'escaneado', 'real', 'ana@oria');
  perform teste_assert_rot(v_r->>'recusado' = 'true'
    and v_r->>'motivo_recusa' like '%contaria em dobro%',
    '(3) o mesmo documento duas vezes recusa: contaria em dobro na cobertura', v_r::text);

  -- ==========================================================================
  raise notice '--- 4. rotular o documento: as recusas que protegem a medição ---';
  -- ==========================================================================
  -- O typo é o plausível de verdade: o código do catálogo é `BALANCO`, e
  -- "BALANCO_PATRIMONIAL" é exatamente o que alguém escreve de memória.
  v_r := fn_golden_rotular(v_rodada, v_doc, 'ana@oria', 'BALANCO_PATRIMONIAL');
  perform teste_assert_rot(v_r->>'recusado' = 'true'
    and v_r->>'motivo_recusa' like '%falso negativo permanente%',
    '(5) tipo fora do catálogo recusa, nomeando o dano', v_r::text);

  v_r := fn_golden_rotular(v_rodada, v_doc, 'ana@oria');
  perform teste_assert_rot(v_r->>'recusado' = 'true'
    and v_r->>'motivo_recusa' like '%N mínimo%',
    '(6) rótulo vazio recusa: contaria na cobertura sem medir nada', v_r::text);

  v_r := fn_golden_rotular(v_rodada, v_doc, null, 'BALANCO');
  perform teste_assert_rot(v_r->>'recusado' = 'true',
    '(4) rótulo sem rotulador recusa', v_r::text);

  v_r := fn_golden_rotular(v_rodada, v_doc, 'ana@oria', 'BALANCO',
                           'Alfa Rotulagem S.A.', '2024', null, 'ok');
  perform teste_assert_rot(v_r->>'rotulo_id' is not null, '(4) rótulo grava', v_r::text);

  v_r := fn_golden_rotular(v_rodada, v_doc, 'ana@oria', 'BALANCO');
  perform teste_assert_rot(v_r->>'recusado' = 'true'
    and v_r->>'motivo_recusa' like '%append-only%',
    '(4) o mesmo rotulador duas vezes no mesmo documento recusa', v_r::text);

  -- Um SEGUNDO rotulador no mesmo documento é permitido — é o que o Arquitetura do Sistema/2 Especificação/f0/06 pede.
  v_r := fn_golden_rotular(v_rodada, v_doc, 'bruno@oria', 'BALANCO',
                           'Alfa Rotulagem S.A.', '2024');
  perform teste_assert_rot(v_r->>'rotulo_id' is not null,
    '(4) um SEGUNDO rotulador no mesmo documento é aceito', v_r::text);

  -- ==========================================================================
  raise notice '--- 5. os campos: rubrica fora da lista é ACEITA (perda silenciosa) ---';
  -- ==========================================================================
  v_r := fn_golden_rotular_campos(v_rodada, v_doc, 'ana@oria', jsonb_build_array(
    -- casa com a máquina, e o valor é o mesmo
    jsonb_build_object('chave', 'Caixa e equivalentes', 'valor_correto', '1000'),
    -- casa com a máquina, e o valor DIVERGE
    jsonb_build_object('chave', 'Estoques', 'valor_correto', '2500'),
    -- NÃO está na lista da máquina: a linha que a extração perdeu
    jsonb_build_object('chave', 'Imobilizado líquido', 'valor_correto', '7000'),
    -- sem valor: descartada e DITA
    jsonb_build_object('chave', 'Intangível'),
    -- sem rubrica: descartada
    jsonb_build_object('valor_correto', '10')
  ));

  perform teste_assert_rot((v_r->>'n_gravados')::int = 3,
    '(2) três campos gravados: os dois que casam e o que a extração perdeu', v_r::text);
  perform teste_assert_rot(jsonb_array_length(v_r->'pulados') = 2,
    '(2) dois pulados: sem valor e sem rubrica', v_r::text);
  perform teste_assert_rot(
    (select bool_or(p->>'porque' like '%sem entrar em métrica nenhuma%')
       from jsonb_array_elements(v_r->'pulados') p),
    '(2) …e o pulado por falta de valor DIZ que ele não entraria em métrica', v_r::text);

  -- ==========================================================================
  raise notice '--- 6. A REVELAÇÃO: casou/não casou vem no retorno, depois de gravar ---';
  -- ==========================================================================
  perform teste_assert_rot(
    (select count(*) from jsonb_array_elements(v_r->'gravados') g
      where (g->>'casou_com_a_extracao')::boolean) = 2,
    '(3) duas das três casaram com a extração', v_r::text);
  perform teste_assert_rot((v_r->>'n_sem_par')::int = 1,
    '(3) e uma não casou — a linha que a extração perdeu', v_r::text);
  perform teste_assert_rot(v_r->>'aviso_sem_par' like '%AUSENTE%',
    '(3) o aviso nomeia o que isso vira no placar: ausente, não errado', v_r::text);

  -- E O PLACAR CONCORDA COM A REVELAÇÃO. Este é o assert que amarra a 0130 à 0126:
  -- se o casamento da revelação usasse outro critério que o de fn_golden_campos, a
  -- tela prometeria um par que a métrica não encontra.
  v_r := (select to_jsonb(c) from fn_golden_campos(v_rodada) c limit 1);
  perform teste_assert_rot(
    (v_r->>'n_exato')::int = 1 and (v_r->>'n_errado')::int = 1 and (v_r->>'n_ausente')::int = 1,
    '(3) o placar da 0126 vê exatamente isso: 1 exato, 1 errado, 1 AUSENTE', v_r::text);

  -- ==========================================================================
  raise notice '--- 7. congelar ---';
  -- ==========================================================================
  v_r := fn_golden_abrir_rodada('Rodada 0130 vazia', 'ana@oria');
  v_outra := (v_r->>'rodada_id')::uuid;
  v_r := fn_golden_congelar(v_outra, 'ana@oria');
  perform teste_assert_rot(v_r->>'recusado' = 'true'
    and v_r->>'motivo_recusa' like '%parecendo evidência%',
    '(7) congelar rodada sem nenhum rótulo recusa', v_r::text);

  v_r := fn_golden_congelar(v_rodada, 'ana@oria');
  perform teste_assert_rot(v_r->>'congelada_por' = 'ana@oria', '(7) congela', v_r::text);
  perform teste_assert_rot(v_r->>'aviso_rotulador_unico' is null,
    '(7) …e não avisa de rotulador único, porque houve dois', v_r::text);

  v_r := fn_golden_congelar(v_rodada, 'ana@oria');
  perform teste_assert_rot(v_r->>'recusado' = 'true'
    and v_r->>'motivo_recusa' like '%Descongelar é recusado%',
    '(7) congelar duas vezes recusa, nomeando o gatilho da 0126', v_r::text);

  -- ==========================================================================
  raise notice '--- 8. rodada congelada: recusa RETORNADA, não exceção ---';
  -- ==========================================================================
  v_r := fn_golden_rotular(v_rodada, v_doc, 'carla@oria', 'BALANCO');
  perform teste_assert_rot(v_r->>'recusado' = 'true'
    and v_r->>'motivo_recusa' like '%Ampliar é rodada nova%',
    '(4) rotular em rodada congelada é recusa retornada, com o caminho de saída', v_r::text);

  v_r := fn_golden_rotular_campos(v_rodada, v_doc, 'carla@oria',
           jsonb_build_array(jsonb_build_object('chave', 'X', 'valor_correto', '1')));
  perform teste_assert_rot(v_r->>'recusado' = 'true',
    '(4) rotular campo em rodada congelada também', v_r::text);

  v_r := fn_golden_incluir_documento(v_rodada, v_doc, 'digital', 'real', 'ana@oria');
  perform teste_assert_rot(v_r->>'recusado' = 'true'
    and v_r->>'motivo_recusa' like '%rodada NOVA%',
    '(4) incluir documento em rodada congelada também', v_r::text);

  -- ==========================================================================
  raise notice '--- 9. um rotulador só: a medição é um PISO, e isso fica dito ---';
  -- ==========================================================================
  v_r := fn_golden_abrir_rodada('Rodada 0130 solo', 'ana@oria');
  v_outra := (v_r->>'rodada_id')::uuid;

  insert into documento (caso_id, entidade_id, periodo_id, tipo_taxonomia, confianca)
    values (v_caso, v_ent, v_per, 'DRE', 0.9) returning id into v_doc2;
  insert into documento_versao (documento_id, n_versao, arquivo_ref, nome_original, hash)
    values (v_doc2, 1, 'bucket/rot-2.pdf', 'dre-alfa-2024.pdf', 'HASH-ROT-2');

  perform fn_golden_incluir_documento(v_outra, v_doc2, 'escaneado', 'real', 'ana@oria');
  perform fn_golden_rotular(v_outra, v_doc2, 'ana@oria', 'DRE');
  v_r := fn_golden_congelar(v_outra, 'ana@oria');
  perform teste_assert_rot(v_r->>'aviso_rotulador_unico' like '%PISO%',
    '(7) com um rotulador só, o congelamento avisa que o número é um piso', v_r::text);

  -- ==========================================================================
  raise notice '--- 10. o progresso traz as DUAS contagens, e elas divergem ---';
  -- ==========================================================================
  -- A máquina chamou o segundo documento de DRE e o rótulo concordou, então aqui
  -- as duas contagens batem. O que o assert trava é a EXISTÊNCIA das duas: uma
  -- versão que devolvesse só a contagem da máquina esconderia o erro de
  -- classificação justamente do painel que decide se a amostra está pronta.
  v_r := (select to_jsonb(p) from fn_golden_progresso(v_outra) p where p.tipo = 'DRE');
  perform teste_assert_rot(
    (v_r->>'n_incluidos')::int = 1 and (v_r->>'n_rotulados')::int = 1,
    '(10) o progresso conta o incluído e o rotulado por tipo da máquina', v_r::text);
  perform teste_assert_rot((v_r->>'n_rotulados_verdade')::int = 1,
    '(10) …e traz também a contagem pela VERDADE, que é a que o portão do dial usa',
    v_r::text);
  perform teste_assert_rot((v_r->>'falta')::int = (v_r->>'n_minimo')::int - 1,
    '(10) e o que FALTA é medido contra a contagem da verdade, não contra a da máquina',
    v_r::text);

  raise notice 'TODOS OS TESTES DA ROTULAGEM DO GOLDEN SET (0130) PASSARAM';
end $$;

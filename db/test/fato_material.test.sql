-- Testes do fato material (db/migrations/0148).
-- Rodar via db/test/run.sh (que aplica TODAS as migrations antes).
--
-- O QUE ESTE ARQUIVO TRAVA, e por que cada propriedade importa mais do que
-- parece. Este é o único canal do produto em que a saída NÃO é um número: é uma
-- frase, lida de texto corrido, que vai ao topo da tela do mandato e que um
-- comitê de crédito lê ANTES da planilha. Um erro aqui não produz número errado
-- — produz um alerta errado, que é pior, porque alerta não se confere por
-- aritmética.
--
--   1. A EVIDÊNCIA É OBRIGATÓRIA. Fato sem trecho literal é descartado na
--      gravação. É a decisão (2) da 0148: um resumo escrito pelo modelo é
--      afirmação; a frase copiada do documento é evidência, e quem lê "incerteza
--      sobre continuidade operacional" tem de poder abrir a página e achar
--      aquela frase.
--   2. A RECUSA É CONTADA, não silenciosa. Recusa silenciosa vira ausência, e
--      ausência parece "este documento não disse nada" — que é exatamente o
--      estado que a 0148 existe para corrigir. Se o modelo passar a mandar fatos
--      sem prova, isso tem de aparecer como NÚMERO.
--   3. `null` NÃO É `[]`. Resposta sem a chave `fatos` (workflow antigo) não
--      pode apagar os fatos já gravados de uma versão. É o modo de falha do
--      `Gravar Campos` que desligou a reconciliação por onze dias em silêncio:
--      um insumo que some faz o estágio virar no-op, e no-op tem a mesma
--      aparência de "está tudo certo".
--   4. REEXTRAIR SUBSTITUI, NÃO ACUMULA. Sem isto, reprocessar um documento três
--      vezes mostra o mesmo covenant três vezes na tela.
--   5. O ENUM DO PROMPT E O CATÁLOGO DO BANCO SÃO O MESMO. São duas cópias em
--      dois mundos sem import cruzado (o enum vai no responseSchema da IA, a
--      severidade mora no banco). Um tipo que exista só no prompt é lido do
--      documento e JOGADO FORA como "tipo desconhecido" — o pior desfecho
--      possível desta fatia, e invisível sem este assert.
--   6. A TELA VÊ A VERSÃO CORRENTE, e só ela. Versão anterior é trilha; dois
--      alertas sobre a mesma frase seriam duas verdades.
--
-- RELIGAMENTO — os defeitos foram reintroduzidos e MEDIDOS:
--   * limite de 20 caracteres removido do `where`: o assert 1 caiu, e o fato sem
--     prova entrou como se fosse evidência.
--   * `delete` removido de `fn_registrar_fatos`: o assert 4 caiu com 2 linhas
--     onde devia haver 1.
--   * um tipo acrescentado só ao FATO_TIPO_ENUM do extract.mjs: o assert 5 caiu
--     nomeando o tipo.

create or replace function teste_assert_fato(p_ok boolean, p_nome text, p_detalhe text default null)
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
  v_caso   uuid;
  v_doc    uuid;
  v_v1     uuid;
  v_v2     uuid;
  v_out    jsonb;
  v_n      int;
  v_txt    text;
  -- As frases são as do caso real da v48 (ANEXO A.2), encurtadas.
  c_covenant constant text :=
    'o índice apurado em 31/12/2025 não atingiu o mínimo contratado, e os saldos originalmente '
    || 'classificados no passivo não circulante foram integralmente reclassificados para o passivo circulante';
  c_ressalva constant text :=
    'Opinião com ressalva sobre as demonstrações contábeis, em razão da limitação de escopo descrita a seguir';
begin
  raise notice '--- 1. A EVIDÊNCIA É OBRIGATÓRIA ---';

  insert into caso (nome) values ('fatos: o que o documento diz') returning id into v_caso;
  insert into documento (caso_id, tipo_taxonomia)
    values (v_caso, 'NOTAS_EXPL') returning id into v_doc;
  insert into documento_versao (documento_id, n_versao, arquivo_ref, nome_original)
    values (v_doc, 1, '33_notas.pdf', '33_Notas_Explicativas.pdf') returning id into v_v1;

  v_out := fn_registrar_fatos(v_v1, jsonb_build_array(
    jsonb_build_object('tipo', 'covenant_rompido', 'trecho', c_covenant,
                       'leitura', 'O covenant foi rompido e a dívida virou curto prazo.', 'pagina', 4),
    -- SEM PROVA: o "trecho" é um resumo do modelo, não uma frase do documento.
    jsonb_build_object('tipo', 'ressalva_auditoria', 'trecho', 'tem ressalva',
                       'leitura', 'O parecer tem ressalva.', 'pagina', 1),
    -- TIPO FORA DO CATÁLOGO, com prova de sobra.
    jsonb_build_object('tipo', 'fato_que_nao_existe', 'trecho', c_ressalva,
                       'leitura', 'Alguma coisa.', 'pagina', 2)
  ));

  perform teste_assert_fato((v_out->>'gravados')::int = 1,
    'só o fato COM trecho literal e tipo conhecido é gravado',
    v_out::text);

  raise notice '--- 2. A RECUSA É CONTADA, NÃO SILENCIOSA ---';

  perform teste_assert_fato((v_out->>'sem_prova')::int = 1,
    'o fato sem trecho literal é CONTADO na recusa (recusa silenciosa vira ausência)',
    v_out::text);
  perform teste_assert_fato((v_out->>'tipo_desconhecido')::int = 1,
    'o tipo fora do catálogo é CONTADO à parte — é diagnóstico diferente de "sem prova"',
    v_out::text);

  select trecho into v_txt from documento_fato where documento_versao_id = v_v1;
  perform teste_assert_fato(v_txt = c_covenant,
    '…e o trecho gravado é a frase do documento, sem reescrita');

  raise notice '--- 3. `null` NÃO É `[]` (o modo de falha do Gravar Campos) ---';

  -- Resposta de um workflow ANTIGO: a chave `fatos` não existe. Isso NÃO pode
  -- apagar o que já foi lido — apagar trilha por causa de um n8n desatualizado é
  -- o defeito que passou onze dias em silêncio na v47.
  v_out := fn_registrar_fatos(v_v1, null);
  select count(*)::int into v_n from documento_fato where documento_versao_id = v_v1;
  perform teste_assert_fato(v_n = 1,
    'resposta SEM a chave "fatos" não apaga os fatos já gravados da versão',
    format('%s fato(s), retorno %s', v_n, v_out));
  perform teste_assert_fato(v_out ? 'nota',
    '…e o retorno DIZ que não tocou em nada, em vez de responder "0 gravados" como se tivesse rodado');

  -- E o inverso tem de valer: lista VAZIA é uma leitura, e ela apaga.
  v_out := fn_registrar_fatos(v_v1, '[]'::jsonb);
  select count(*)::int into v_n from documento_fato where documento_versao_id = v_v1;
  perform teste_assert_fato(v_n = 0,
    'lista VAZIA é uma leitura de verdade ("li e não achei nada") e essa apaga',
    format('%s fato(s)', v_n));

  raise notice '--- 4. REEXTRAIR SUBSTITUI, NÃO ACUMULA ---';

  perform fn_registrar_fatos(v_v1, jsonb_build_array(
    jsonb_build_object('tipo', 'covenant_rompido', 'trecho', c_covenant, 'pagina', 4)));
  perform fn_registrar_fatos(v_v1, jsonb_build_array(
    jsonb_build_object('tipo', 'covenant_rompido', 'trecho', c_covenant, 'pagina', 4)));

  select count(*)::int into v_n from documento_fato where documento_versao_id = v_v1;
  perform teste_assert_fato(v_n = 1,
    'gravar duas vezes a mesma leitura deixa UM fato, não dois',
    format('%s fato(s)', v_n));

  raise notice '--- 5. O ENUM DO PROMPT E O CATÁLOGO DO BANCO SÃO O MESMO ---';

  -- A lista abaixo é uma cópia LITERAL de FATO_TIPO_ENUM (n8n/lib/extract.mjs).
  -- Ela existe aqui porque SQL não importa .mjs — e é justamente por não haver
  -- import que a divergência é possível. O custo de manter a cópia é uma linha;
  -- o custo de não ter o assert é um fato lido do documento e jogado fora.
  select string_agg(t, ', ' order by t) into v_txt
    from unnest(array[
      'continuidade_operacional', 'ressalva_auditoria', 'covenant_rompido',
      'reclassificacao_divida', 'litigio_relevante', 'garantia_dada',
      'evento_subsequente', 'parte_relacionada', 'mudanca_criterio_contabil'
    ]) t
   where not exists (select 1 from fato_tipo_catalogo c where c.tipo = t);
  perform teste_assert_fato(v_txt is null,
    'todo tipo do FATO_TIPO_ENUM (extract.mjs) existe no catálogo do banco',
    coalesce(v_txt, ''));

  select string_agg(c.tipo, ', ' order by c.tipo) into v_txt
    from fato_tipo_catalogo c
   where c.tipo <> all (array[
      'continuidade_operacional', 'ressalva_auditoria', 'covenant_rompido',
      'reclassificacao_divida', 'litigio_relevante', 'garantia_dada',
      'evento_subsequente', 'parte_relacionada', 'mudanca_criterio_contabil']);
  perform teste_assert_fato(v_txt is null,
    '…e o contrário também: tipo no banco que o prompt nunca pede é tipo que nunca chega',
    coalesce(v_txt, ''));

  -- E toda severidade tem de ser uma das três que a tela sabe pintar.
  select count(*)::int into v_n from fato_tipo_catalogo
   where severidade not in ('critico', 'relevante', 'informativo');
  perform teste_assert_fato(v_n = 0, 'toda severidade do catálogo é uma das três que a tela pinta');

  select count(*)::int into v_n from fato_tipo_catalogo where trim(coalesce(porque, '')) = '';
  perform teste_assert_fato(v_n = 0,
    'todo tipo diz POR QUE importa — sem isso o alerta é etiqueta, não decisão');

  raise notice '--- 6. A TELA VÊ A VERSÃO CORRENTE, E SÓ ELA ---';

  insert into documento_versao (documento_id, n_versao, arquivo_ref, nome_original)
    values (v_doc, 2, '33_notas_v2.pdf', '33_Notas_Explicativas.pdf') returning id into v_v2;
  perform fn_registrar_fatos(v_v2, jsonb_build_array(
    jsonb_build_object('tipo', 'ressalva_auditoria', 'trecho', c_ressalva,
                       'leitura', 'O parecer não é limpo.', 'pagina', 1)));

  select count(*)::int into v_n from fn_fatos_do_caso(v_caso);
  perform teste_assert_fato(v_n = 1,
    'o caso mostra UM fato — o da versão corrente; a versão 1 é trilha e não aparece',
    format('%s fato(s)', v_n));

  select tipo, rotulo, severidade into v_txt, v_txt, v_txt from fn_fatos_do_caso(v_caso);
  select f.tipo || ' | ' || f.rotulo || ' | ' || f.severidade || ' | ' || f.nome_documento
    into v_txt from fn_fatos_do_caso(v_caso) f;
  perform teste_assert_fato(
    v_txt = 'ressalva_auditoria | Opinião com ressalva do auditor | critico | 33_Notas_Explicativas.pdf',
    '…e ele chega com rótulo humano, gravidade e o nome do arquivo — a tela não precisa de switch',
    coalesce(v_txt, '<null>'));

  -- A ORDEM É A DA GRAVIDADE, e é o que faz a lista ser lida de cima. Com dois
  -- fatos de pesos diferentes na mesma versão, o crítico vem primeiro.
  perform fn_registrar_fatos(v_v2, jsonb_build_array(
    jsonb_build_object('tipo', 'parte_relacionada', 'trecho',
      'As operações com partes relacionadas estão detalhadas na nota 18 e foram realizadas em condições usuais'),
    jsonb_build_object('tipo', 'continuidade_operacional', 'trecho',
      'existe incerteza relevante que pode levantar dúvida significativa quanto à capacidade de continuidade operacional')));

  select string_agg(f.tipo, ' > ') into v_txt from (select tipo from fn_fatos_do_caso(v_caso)) f;
  perform teste_assert_fato(v_txt = 'continuidade_operacional > parte_relacionada',
    'a lista sai na ordem da GRAVIDADE — o crítico primeiro, para ser lida de cima',
    coalesce(v_txt, '<null>'));

  delete from documento_fato where documento_versao_id in (v_v1, v_v2);
  delete from documento_versao where id in (v_v1, v_v2);
  delete from documento where id = v_doc;
  delete from caso where id = v_caso;

  raise notice 'fato_material OK — evidência obrigatória; recusa contada; null≠[]; reextrair substitui; enum espelhado; versão corrente e ordem por gravidade';
end $$;

drop function teste_assert_fato(boolean, text, text);

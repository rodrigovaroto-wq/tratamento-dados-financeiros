-- 0143 — QUANDO A HIERARQUIA VEM ACHATADA, A CHECAGEM SE RECUSA A ACUSAR.
--
-- ACHADO NA RODADA v48, cruzando o portal com o banco: das 27 pendências
-- abertas, 12 vinham desta única causa, e o número denunciava sozinho — a razão
-- `soma_filhos / pai_valor` era **exatamente 2,0000** nas quinze seções
-- divergentes, em seis documentos diferentes.
--
-- A CAUSA NÃO É A CHECAGEM. O balanço real tem TRÊS níveis:
--
--     Ativo Circulante  44.022      ← total da seção
--       Disponível          825     ← subtotal de grupo
--         Caixa             606
--         Aplicações        181     606 + 181 + 38 = 825
--         Numerário          38
--       Contas a Receber 12.795     ← subtotal de grupo
--         … 4 folhas               24.861 + 3.845 − 9.644 − 6.267 = 12.795
--
-- …mas `campo_extraido.secao` vem ACHATADA: subtotais de grupo e folhas carregam
-- todos `secao = 'Ativo Circulante'`, e `fn_papel_linha('Disponível')` devolve
-- `conta`. A checagem soma os dois níveis e chega a 2× o pai. Ela está fazendo
-- exatamente o que deveria com a árvore que recebeu.
--
-- POR QUE O FIXTURE NÃO PEGOU: o `book-vertentes` tem DOIS níveis. O defeito só
-- aparece em documento com subtotal intermediário — que é o documento real.
--
-- O QUE ESTA MIGRATION FAZ, E O QUE ELA NÃO FAZ. Ela NÃO conserta a hierarquia:
-- isso é na extração, `secao` tem de trazer o grupo IMEDIATO, e é fatia própria
-- com rodada própria para medir. O que ela faz é a checagem **reconhecer a
-- assinatura e declarar `hierarquia_achatada`** em vez de acusar divergência.
--
-- Recusar-se a acusar quando não dá para conferir é a doutrina desta casa, e
-- aqui ela vale duplamente: a pendência dizia "a extração perdeu/errou linha
-- nessas seções" sobre uma extração que estava PERFEITA — conferida contra o
-- `GABARITO.json`, os 38 documentos batem no centavo. Mandar o analista abrir o
-- PDF para procurar um erro que não existe é o pior uso possível do tempo dele,
-- e queima a confiança na fila inteira.
--
-- A DETECÇÃO É ARITMÉTICA, não heurística de rótulo: `soma ≈ 2 × pai` dentro da
-- mesma tolerância de arredondamento que a checagem já usa. Uma seção de dois
-- níveis não produz esse número por acaso — para produzi-lo, as parcelas teriam
-- de somar exatamente o dobro do pai declarado.

do $mig$
declare
  v_src text; v_novo text; v_n int;
begin
  select pg_get_functiondef(p.oid) into v_src
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'fn_conferir_arvore';

  if v_src is null then
    raise exception '0143: fn_conferir_arvore não existe — migration fora de ordem';
  end if;

  -- Três âncoras, uma por coluna do SELECT final: resultado, achado e descrição.
  -- Regex e não literal pelo motivo que a 0142 aprendeu na prática: produção
  -- guarda o corpo com CRLF e o banco montado do zero guarda com LF.
  select count(*) into v_n from regexp_matches(v_src, 'when m\.div_abs > m\.tol', 'g');
  if v_n <> 3 then
    raise exception '0143: esperava 3 ocorrências de "when m.div_abs > m.tol" e achei % — a função mudou de forma', v_n;
  end if;

  v_novo := v_src;

  -- 1) resultado
  v_novo := regexp_replace(v_novo,
    '(when m\.n = 0            then ''precondicao_nao_satisfeita''\r?\n)(\s*)when m\.div_abs > m\.tol  then ''divergente''',
    E'\\1\\2-- 0143: soma ≈ 2× o pai é hierarquia achatada, não divergência.\n'
    || E'\\2when m.pai_valor <> 0 and abs(m.soma - 2 * m.pai_valor) <= m.tol\n'
    || E'\\2                        then ''precondicao_nao_satisfeita''\n'
    || E'\\2when m.div_abs > m.tol  then ''divergente''');

  -- 2) achado
  v_novo := regexp_replace(v_novo,
    '(when m\.n = 0          then ''sem_parcela''\r?\n)(\s*)when m\.div_abs > m\.tol then ''secao_nao_fecha''',
    E'\\1\\2when m.pai_valor <> 0 and abs(m.soma - 2 * m.pai_valor) <= m.tol\n'
    || E'\\2                       then ''hierarquia_achatada''\n'
    || E'\\2when m.div_abs > m.tol then ''secao_nao_fecha''');

  -- 3) descrição
  v_novo := regexp_replace(v_novo,
    '(\s*)when m\.div_abs > m\.tol then\r?\n(\s*)format\(''"%s" informa %s e a soma das %s parcelas',
    E'\\1when m.pai_valor <> 0 and abs(m.soma - 2 * m.pai_valor) <= m.tol then\n'
    || E'\\2format(''"%s" informa %s e as %s parcelas somam %s — exatamente o DOBRO. ''\n'
    || E'\\2       ''Isto não é a seção deixando de fechar: é a hierarquia do documento chegando ''\n'
    || E'\\2       ''ACHATADA, com o subtotal de grupo e as folhas dele no mesmo nível, então a ''\n'
    || E'\\2       ''soma conta os dois. Não há o que conferir no PDF — a extração dos valores ''\n'
    || E'\\2       ''está correta; o que falta é o nível intermediário da árvore.'',\n'
    || E'\\2       m.pai_chave, m.pai_valor, m.n, m.soma)\n'
    || E'\\1when m.div_abs > m.tol then\n'
    || E'\\2format(''"%s" informa %s e a soma das %s parcelas');

  if v_novo = v_src then
    raise exception '0143: nenhuma das três substituições pegou — abortado';
  end if;

  execute v_novo;

  select pg_get_functiondef(p.oid) into v_src
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'fn_conferir_arvore';
  if position('hierarquia_achatada' in v_src) = 0 then
    raise exception '0143: a função foi recriada sem o achado hierarquia_achatada — abortado';
  end if;
end $mig$;

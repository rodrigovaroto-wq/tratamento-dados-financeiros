-- 0142 — `tipo_incorreto` ACUSAVA SEM TER DIVERGÊNCIA PARA ACUSAR.
--
-- ACHADO NA RODADA v48 (24/08), a primeira em que o diagnóstico voltou a rodar
-- depois da correção do fio (`Gravar Campos` não devolvia `documento_id`, e
-- `fn_registrar_diagnostico` era chamada com NULL desde 13/08). Estágio parado
-- não gera achado; assim que voltou, gerou — e DOIS dos TRÊS eram falsos:
--
--   • `27_Composicao_do_Imobilizado`: "sugere tipo NOTAS_EXPL (documento está
--     registrado como NOTAS_EXPL)" — o MESMO tipo dos dois lados;
--   • `28_Folha_de_Pagamento`: "sugere tipo ? (registrado como (nenhum))" —
--     comparando nada com nada.
--
-- POR QUE. A condição tinha duas pernas e a primeira não olhava divergência
-- nenhuma:
--
--     if coalesce(p_tipo_confirma, true) = false
--        or (p_tipo_sugerido is not null and p_tipo_sugerido is distinct from v_tipo_atual)
--
-- `tipo_confirma = false` é o modelo dizendo "não confirmo", e ele diz isso
-- também quando reconhece o mesmo tipo com outro nome, ou quando não sabe o que
-- o documento é. Nos dois casos não há nada que um humano possa fazer: a
-- pendência pede uma decisão sobre uma diferença que não existe.
--
-- O QUE MUDA. A pendência passa a exigir divergência ACIONÁVEL — um tipo
-- sugerido diferente do registrado, ou uma recusa de confirmação sobre um
-- documento que TEM tipo. Recusar sem sugerir, num documento sem tipo, deixa de
-- abrir `tipo_incorreto`: esse caso já tem dono, é `classificacao_pendente`, e é
-- exatamente a pendência que o doc 28 já tinha aberto em paralelo — duas
-- pendências para o mesmo fato são dois toques humanos onde cabe um.
--
-- MEDIDO ANTES DE APLICAR, contra as três pendências reais da v48: a regra nova
-- MANTÉM o achado verdadeiro (`14_Balanco_COMBINADO` registrado como BALANCO,
-- sugerido COMBINADO) e derruba as duas falsas. Não é silenciamento: é a guarda
-- deixando de acusar onde não há acusação a fazer.
--
-- POR QUE É PATCH COM ÂNCORA, e não reemissão inteira: mesma razão da `0141`, e
-- ela está escrita lá. A função tem centenas de linhas e o que muda é UMA
-- condição; transcrevê-la à mão troca um risco pequeno e barulhento — âncora não
-- encontrada, que levanta exceção — por um grande e silencioso.

do $mig$
declare
  v_src text; v_novo text;
  -- ÂNCORA POR REGEX, E NÃO LITERAL, porque o fim de linha difere entre os dois
  -- bancos em que esta migration precisa rodar: a produção guarda o corpo com
  -- CRLF (veio de arquivos CRLF) e o banco montado do zero pelo `db/test/run.sh`
  -- guarda com LF. Uma âncora literal casa em um e falha no outro — e falhou,
  -- na primeira tentativa, exatamente assim.
  v_padrao constant text :=
    '  if coalesce\(p_tipo_confirma, true\) = false\r?\n'
    || '     or \(p_tipo_sugerido is not null and p_tipo_sugerido is distinct from v_tipo_atual\) then';
  v_troca constant text :=
    E'  -- 0142: exige divergência ACIONÁVEL. "Não confirmo" sozinho não basta —\n'
    || E'  -- o modelo diz isso também quando reconhece o mesmo tipo com outro nome\n'
    || E'  -- (doc 27 da v48: NOTAS_EXPL contra NOTAS_EXPL) ou quando não sabe o que o\n'
    || E'  -- documento é ("?" contra "(nenhum)", doc 28). Nos dois casos a pendência\n'
    || E'  -- pedia decisão sobre uma diferença que não existe.\n'
    || E'  if (p_tipo_sugerido is not null and p_tipo_sugerido is distinct from v_tipo_atual)\n'
    || E'     or (coalesce(p_tipo_confirma, true) = false\n'
    || E'         and v_tipo_atual is not null\n'
    || E'         and coalesce(p_tipo_sugerido, '''') <> coalesce(v_tipo_atual, '''')) then';
begin
  select pg_get_functiondef(p.oid) into v_src
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'fn_registrar_diagnostico';

  if v_src is null then
    raise exception '0142: fn_registrar_diagnostico não existe — migration fora de ordem';
  end if;

  if (select count(*) from regexp_matches(v_src, v_padrao, 'g')) <> 1 then
    raise exception '0142: a condição de tipo_incorreto não foi encontrada UMA vez — este patch precisa ser relido por gente';
  end if;

  v_novo := regexp_replace(v_src, v_padrao, v_troca);
  execute v_novo;

  -- Confere em vez de confiar.
  select pg_get_functiondef(p.oid) into v_src
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'fn_registrar_diagnostico';
  if position('0142: exige divergência ACIONÁVEL' in v_src) = 0 then
    raise exception '0142: a função foi recriada sem a condição nova — abortado';
  end if;
end $mig$;

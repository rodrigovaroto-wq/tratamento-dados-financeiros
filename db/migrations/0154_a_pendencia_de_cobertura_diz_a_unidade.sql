-- 0154 — A PENDÊNCIA DE COBERTURA JUNTAVA DUAS UNIDADES NA MESMA FRASE.
--
-- LIDO NA RODADA REAL DO `book-araucaria`, ao investigar 23 pendências de
-- `extracao_falhou`. A descrição que chega ao analista é esta:
--
--     Extração de "002_Balanco_...pdf" falhou ou veio incompleta
--     (276 linhas gravadas). Motivo: Extração INCOMPLETA: 68 linha(s)
--     devolvida(s) para um documento com 99 linha(s) de conta no texto...
--
-- **276 gravadas e 68 devolvidas, na mesma frase.** Lido de fora, isso parece
-- contradição — e foi exatamente assim que eu li da primeira vez, e cheguei a
-- suspeitar de um falso positivo que não existe.
--
-- Os dois números estão certos e medem coisas diferentes:
--
--     276 = PARES conta × coluna (linhas de `campo_extraido`)
--      68 = LINHAS do documento (uma conta com 5 exercícios é UMA linha)
--
-- 68 linhas × ~4 colunas com valor = 276 pares. A conta fecha.
--
-- `avaliarCobertura` (n8n/lib/cobertura.mjs) já explica a unidade dela com todas
-- as letras — o problema nasce quando o invólucro SQL prefixa `v_count`, que é
-- contagem de PARES, com a palavra "linhas". Duas unidades com o mesmo nome, e
-- a mais visível é a errada.
--
-- POR QUE ISTO MERECE MIGRATION EM VEZ DE FICAR ANOTADO: a pendência é o
-- produto. Ela existe para um analista decidir se pode usar o número, e uma
-- descrição que parece se contradizer ensina a ignorar a fila — que é o mesmo
-- estrago do alarme falso, por outro caminho. E o custo de arrumar é uma
-- palavra.
--
-- ---------------------------------------------------------------------------
-- O QUE A INVESTIGAÇÃO ACHOU E ESTA MIGRATION **NÃO** RESOLVE
-- ---------------------------------------------------------------------------
--
-- As 23 pendências são VERDADEIRAS. Medido com `n8n/medir-regua-cobertura.mjs`
-- contra os 38 documentos do `book-canastra`, onde a extração é conferida linha
-- a linha: **erro mediano da régua +3%**, e a pior razão de uma extração
-- PERFEITA é 96% — bem acima do limiar de 85%. A régua não infla.
--
-- Contra isso, as razões do araucária:
--
--     002_Balanco_Serraria .......  68 de  99 =  69%
--     098_Livro_Razao ............ 102 de 258 =  40%
--     105_Mapa_de_Divida .........  12 de  25 =  48%
--     125_Posicao_de_Estoques ....  21 de  27 =  78%
--
-- e o equivalente do Canastra, com o mesmo formato de documento:
--
--     17_Livro_Razao ............. 99 de 100 =  99%
--     20_Mapa_de_Divida .......... 12 de  11 = 109%
--
-- É SUB-EXTRAÇÃO REAL, e a guarda está fazendo o trabalho dela.
--
-- O QUE CHAMA ATENÇÃO É A CONSTÂNCIA: cinco livros razão de 258 linhas cada
-- devolveram 102, 101, 104, 102 e 102; cinco mapas de dívida de 25 linhas
-- devolveram 12, 12, 12, 12 e 12. Número que não varia com o documento é
-- assinatura de TETO, não de leitura.
--
-- E aqui a investigação PAROU, por falta de instrumento — o que é a segunda
-- metade desta migration. Para separar "o modelo leu pela metade" de "o
-- fatiamento não rodou" eu precisava saber EM QUANTOS BLOCOS o documento foi
-- lido. Esse número existe (`r.blocos` no `Juntar Blocos`), viaja no item, e
-- **não chega à pendência**. A execução foi cancelada, o n8n descartou os dados
-- dela, e a linha de `lote_execucao` — que carrega `documentos_fatiados` —
-- nunca foi escrita, porque o lote não fechou.
--
-- Então a pendência passa a dizer em quantos blocos o documento foi lido. Um
-- documento de 258 linhas lido em UM bloco e outro lido em QUATRO são
-- diagnósticos diferentes, e hoje eles têm exatamente a mesma aparência.

create or replace function fn_descricao_extracao_falhou(
  p_nome_original text,
  p_pares         integer,
  p_motivo        text
)
returns text
language sql
immutable
as $$
  -- 0154: a unidade vai escrita. `p_pares` conta linhas de `campo_extraido`,
  -- que são PARES conta × coluna — uma conta com cinco exercícios são cinco.
  -- O motivo, quando vem da guarda de cobertura, fala em LINHAS do documento.
  -- Sem os dois nomes por extenso a frase parece se contradizer.
  select format(
    'Extração de "%s" falhou ou veio incompleta (%s par(es) conta×coluna gravado(s)). Motivo: %s',
    coalesce(p_nome_original, '?'),
    coalesce(p_pares, 0),
    coalesce(p_motivo,
             'a chamada respondeu sem erro, mas não trouxe NENHUMA linha. '
             'Causa mais comum: formato que o pipeline ainda não converte em texto '
             '(.xlsx/.docx) — nesses casos a IA recebe um aviso em vez do arquivo.'));
$$;

comment on function fn_descricao_extracao_falhou(text, integer, text) is
  'A descrição da pendência de extração incompleta, com a UNIDADE escrita (0154): o número do '
  'banco são PARES conta×coluna e o da guarda de cobertura são LINHAS do documento. Juntos e sem '
  'nome, "276 gravadas / 68 devolvidas" parece contradição — e uma pendência que parece se '
  'contradizer ensina a ignorar a fila.';

-- -----------------------------------------------------------------------------
-- O corpo de `fn_registrar_campos_extraidos` muda em UMA linha: a construção da
-- descrição sai para a função acima. Tudo o mais é o da 0141, intacto.
-- -----------------------------------------------------------------------------
do $$
declare
  v_src text;
  v_novo text;
begin
  select pg_get_functiondef(p.oid) into v_src
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'fn_registrar_campos_extraidos'
  order by p.oid desc limit 1;

  if v_src is null then
    raise exception 'fn_registrar_campos_extraidos não existe — a 0154 depende dela';
  end if;

  -- A SUBSTITUIÇÃO É CIRÚRGICA E CONFERIDA. Recriar o corpo inteiro por cópia é
  -- o que a 0006 fez e regrediu funções em silêncio; o comentário da 0030
  -- registra isso. Aqui a migration falha ALTO se o trecho não for encontrado
  -- exatamente uma vez.
  v_novo := replace(v_src,
    'format(''Extração de "%s" falhou ou veio incompleta (%s linhas gravadas). Motivo: %s'',
                 coalesce(v_nome_original, ''?''), v_count,
                 coalesce(p_falha_motivo,
                          ''a chamada respondeu sem erro, mas não trouxe NENHUMA linha. ''
                          ''Causa mais comum: formato que o pipeline ainda não converte em texto ''
                          ''(.xlsx/.docx) — nesses casos a IA recebe um aviso em vez do arquivo.''))',
    'fn_descricao_extracao_falhou(v_nome_original, v_count, p_falha_motivo)');

  if v_novo = v_src then
    raise exception 'a 0154 não achou o trecho da descrição em fn_registrar_campos_extraidos — '
                    'o corpo mudou desde a 0128 e a substituição precisa ser revista';
  end if;

  execute v_novo;
end $$;

-- -----------------------------------------------------------------------------
-- A SONDA
-- -----------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  -- O MARCADOR É O NOME DA FUNÇÃO CHAMADA, e não o número da migration. Ele
  -- prova a LIGAÇÃO (o corpo chama mesmo `fn_descricao_extracao_falhou`) em vez
  -- de provar a safra — que é o que a sonda existe para medir. Um número de
  -- migration num comentário passaria com o corpo desligado.
  ('cobertura_diz_a_unidade', '0154', 'corpo', 'fn_registrar_campos_extraidos',
   'fn_descricao_extracao_falhou', null,
   'A pendência de extração incompleta volta a dizer "276 linhas gravadas" logo antes de "68 '
   'linhas devolvidas" — dois números certos, em unidades diferentes, com o mesmo nome. Parece '
   'contradição, e pendência que parece se contradizer ensina a ignorar a fila.',
   'informativo', 580),
  ('cobertura_descricao_com_unidade', '0154', 'funcao', 'fn_descricao_extracao_falhou', null, null,
   'A função que escreve a descrição com a unidade não existe, e o corpo que a chama quebra na '
   'primeira extração incompleta — que é pior que a frase confusa que ela corrige.',
   'informativo', 585)
on conflict (chave) do update
  set migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
      marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
      porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0154',
       revisado_em = date '2026-08-27',
       observacao = 'Revisão de 27/08/2026 (noite): a 0154 põe a UNIDADE na descrição da '
                    'pendência de extração incompleta — o número do banco são pares conta×coluna '
                    'e o da guarda são linhas do documento, e juntos sem nome pareciam '
                    'contradição. As 23 pendências do araucária são verdadeiras: medido com '
                    'medir-regua-cobertura.mjs contra o Canastra, o erro mediano da régua é +3% '
                    'e a pior extração perfeita dá 96%, contra razões de 40% a 78% no araucária.'
 where id;

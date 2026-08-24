-- 0140 — A GUARDA DE PADRÃO SUSPEITO ACUSOU O ANO.
--
-- ACHADO NA RODADA v47 (24/08), no `19_Faturamento_Intragrupo`. A guarda abriu
-- pendência dizendo:
--
--   "4 contas diferentes, na MESMA coluna, vieram com o MESMO valor material
--    (2023.00) — padrão típico de fabricação/alucinação, não de dado real."
--
-- É FALSO POSITIVO, e o número denuncia sozinho: 2023 é o ANO. A coluna é
-- `Exercício`, e o valor se repete nas quatro linhas de 2023 porque é assim que
-- um exercício funciona. Os valores monetários das mesmas linhas estavam
-- CERTOS e somavam certo (1.900 + 3.400 + 720 + 1.100 = 7.120, igual ao "Total
-- de 2023" do documento).
--
-- POR QUE A GUARDA NÃO VIU. A 0022/0034 já tinha aprendido que comparar valores
-- de colunas diferentes gerava falso — e agrupou por (valor, entidade_coluna,
-- periodo_coluna). O que ela não previu é que uma COLUNA pode não ser de valor
-- nenhum: num documento tabular, `Exercício`, `Quantidade`, `Natureza` e
-- `% do total` ocupam o mesmo `periodo_coluna` que "Valor" ocupa, e caem no
-- mesmo teste de materialidade. A guarda estava certa sobre "mesma coluna" e
-- errada sobre o que é uma coluna de valor.
--
-- O CUSTO DE ERRAR PARA CADA LADO É ASSIMÉTRICO, e é isso que justifica a
-- correção ser por lista explícita em vez de heurística esperta: um falso
-- positivo manda um analista conferir à mão um documento que está correto —
-- some com a confiança na fila. Um falso NEGATIVO deixa passar alucinação. Por
-- isso a lista abaixo nomeia dimensões conhecidas e não tenta adivinhar: coluna
-- que não estiver nela continua sendo checada, como antes.
--
-- MEDIDO ANTES DE APLICAR, contra as 38 versões da v47: o único documento que
-- muda de estado é o 19 (de 4 contas repetindo 2023 para 2 repetindo 1.900,
-- abaixo do limiar). O maior `n_contas` do lote passa a ser 3, contra um limiar
-- de 4 — a guarda continua com folga, não foi silenciada.
--
-- NÃO É COSMÉTICO: a mesma confusão entre "coluna de valor" e "coluna de
-- dimensão" está por trás do achado da escala (docs 24 e 28 da v47, onde
-- `Quantidade` e `Efetivo (pessoas)` herdaram `unidade`/`moeda` do documento).
-- Esta migration resolve o lado da guarda; o lado da escala é da extração.

-- -----------------------------------------------------------------------------
-- fn_coluna_de_dimensao — a coluna rotula a linha em vez de medi-la?
--
-- Comparação por rótulo, sem acento e sem caixa, porque o rótulo vem do
-- documento e o documento escreve "Exercício", "EXERCICIO" e "exercício". A
-- normalização é a MESMA do resto do schema (`fn_normalizar_texto`), e não uma
-- cópia local: rótulo normalizado de dois jeitos diferentes é como a 0103
-- descreve o defeito que ela foi corrigir.
-- -----------------------------------------------------------------------------
create or replace function fn_coluna_de_dimensao(p_coluna text)
returns boolean
language sql
immutable
as $fn$
  select case
    when p_coluna is null or btrim(p_coluna) = '' then false
    -- Os parênteses em volta do padrão NÃO são estilo: `~` liga mais forte que
    -- `||`, então sem eles o Postgres lê `(texto ~ 'a') || 'b'` — booleano
    -- concatenado com texto — e a função devolve texto em vez de booleano.
    else fn_normalizar_texto(p_coluna) ~ (
      -- Dimensões temporais que NÃO são período de valor: o ano solto numa
      -- coluna própria (v47, doc 19).
      '^(exercicio|ano|periodo|competencia|data|mes|vencimento)$'
      -- Contagens e medidas físicas: repetem por natureza e não são dinheiro.
      || '|^(quantidade|qtd|qtde|unidade|efetivo|efetivo \(pessoas\)|pessoas|headcount|dias|prazo)$'
      -- Classificadores textuais.
      || '|^(natureza|tipo|classe|categoria|situacao|status|moeda|indexador|empresa.*|contraparte|banco|contrato|historico|documento)$'
      -- Proporções e unitários: 100,00 repetido em "% do total" é aritmética,
      -- não alucinação; e custo unitário repete entre itens do mesmo insumo.
      || '|(^|\s)(%|percentual|participacao|custo unitario|preco unitario|valor unitario|taxa)($|\s)'
    )
  end;
$fn$;

comment on function fn_coluna_de_dimensao(text) is
  'A coluna ROTULA a linha (exercício, quantidade, natureza, %) em vez de medi-la em '
  'dinheiro. Nasceu do falso positivo da v47: a guarda de padrão suspeito acusou o ano '
  '2023 repetido na coluna "Exercício" como alucinação (0140).';

-- -----------------------------------------------------------------------------
-- fn_contas_repetindo_valor — idêntica à versão viva, com UMA cláusula a mais.
--
-- Reemitida inteira, e não alterada por fora, pela mesma razão da 0103: uma só
-- definição, para que a guarda e a explicação da guarda não divirjam.
-- -----------------------------------------------------------------------------
create or replace function fn_contas_repetindo_valor(p_documento_versao_id uuid)
returns table (valor numeric, n_contas int)
language sql
stable
as $fn$
  select ce.valor_num, count(distinct ce.chave)::int
  from campo_extraido ce
  where ce.documento_versao_id = p_documento_versao_id
    and ce.valor_num is not null
    and ce.valor_num <> 0
    -- MATERIAL: 1% do maior valor da versão. Valores pequenos (18, 40, 180)
    -- coincidem à toa e geraram os falsos da v24.
    and abs(ce.valor_num) >= (
      select greatest(coalesce(max(abs(c2.valor_num)), 0) * 0.01, 1)
      from campo_extraido c2 where c2.documento_versao_id = p_documento_versao_id
    )
    -- …e NÃO são totais de grupo. Ativo = Passivo + PL faz essas quatro linhas
    -- terem o mesmo valor por construção contábil.
    and not fn_rotulo_estrutural(ce.chave, array['ativo'])
    and not fn_rotulo_estrutural(ce.chave, array['passivo','patrimonio'])
    -- 0140: …e a coluna mede dinheiro. `Exercício` repetindo 2023 é o ano, não
    -- alucinação — foi o falso positivo da v47.
    and not fn_coluna_de_dimensao(ce.periodo_coluna)
  group by ce.valor_num, coalesce(ce.entidade_coluna, ''), coalesce(ce.periodo_coluna, '')
  order by count(distinct ce.chave) desc
  limit 1;
$fn$;

comment on function fn_contas_repetindo_valor(uuid) is
  'O valor material mais repetido entre contas DISTINTAS da mesma coluna, ignorando os '
  'totais estruturais (0034) e as colunas de dimensão (0140). Insumo do sinal 1 da '
  'guarda de extração (0013).';

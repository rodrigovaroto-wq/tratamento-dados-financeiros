-- =============================================================================
-- 0116 — O total IMPRESSO passa a ser LINHA, e o papel dela já tem de existir
--
-- O QUE MUDOU FORA DAQUI. O prompt de extração (n8n/lib/extract.mjs) passou a
-- exigir que o valor impresso NA MESMA LINHA do nome do agrupamento saia como
-- LINHA, e não só como o nome da `secao`. A auditoria da rodada v46 (17/08)
-- mediu o estrago do jeito antigo: o balanço veio com todas as contas e NENHUM
-- dos totais de topo — "ATIVO CIRCULANTE", "TOTAL DO ATIVO", "RECEITA
-- OPERACIONAL BRUTA" viraram metadado e o número sumiu. Sem eles a conferência
-- do export não tem contra o que conferir: a soma das contas vira a única
-- verdade disponível, que é exatamente o que a conferência existe para evitar.
--
-- POR QUE ISSO EXIGE MIGRATION. `fn_papel_linha` é quem decide se uma linha
-- recebe premissa na Modelagem (`linhas_para_modelagem` só pega papel='conta').
-- Ela já reconhece a maior parte dos totais que vão passar a chegar — a `0034`
-- ensinou os grupos do balanço que não trazem a palavra "total" ("ATIVO",
-- "PASSIVO E PATRIMÔNIO LÍQUIDO", "Ativo Circulante") e a `0042` fechou as
-- linhas de resultado da DRE e do Fluxo. Faltam as que a mudança do prompt
-- traz de novo, e que hoje chegariam como CONTA: o topo da DRE e os totais da
-- DVA. Uma linha dessas classificada como conta é dupla contagem — o defeito
-- mais caro deste projeto, porque não parece erro, parece um número maior.
--
-- O CRITÉRIO PARA ENTRAR NA LISTA CONTINUA SENDO O DA 0042: lista FECHADA de
-- rótulos, nunca semelhança. Errar para subtotal ESCONDE uma conta de verdade,
-- então só entra o rótulo que é total em qualquer documento em que apareça.
-- Ficaram DE FORA de propósito, e vale registrar por quê:
--   • "Receita bruta" / "Receita bruta de vendas" — numa DRE resumida essa É a
--     linha de receita, a mais projetável do modelo. Marcá-la subtotal a tira
--     da Modelagem. Só entra a forma longa "Receita operacional bruta", que é o
--     cabeçalho do bloco na estrutura completa.
--   • "Despesas operacionais" — idem: em DRE resumida é a própria despesa.
--   • "Imobilizado", "Estoques", "Disponível" — nomes de subgrupo que TAMBÉM
--     são conta em muito balanço. Quem os pega é a detecção ESTRUTURAL do
--     export (`detectarSubtotaisInformados` / `detectarSubtotaisPorOrdem`), que
--     olha o documento e não o rótulo — o lugar certo para o que é ambíguo.
-- =============================================================================

create or replace function fn_papel_linha(
  p_chave          text,
  p_tipo_taxonomia text default null,
  p_unidade        text default null
) returns text language sql immutable as $$
  with n as (
    select fn_normalizar_texto(p_chave) as t,
           fn_tokens_estruturais(p_chave) as toks
  )
  select case
    -- ---- DERIVADO: indicador gerencial, não dinheiro ------------------------
    when (select t from n) ~ '^(indice|indices) '
      or (select t from n) ~ '^media (mensal|diaria|anual)'
      or (select t from n) ~ '^ticket medio'
      or (select t from n) ~ '^prazo medio'
      or (select t from n) ~ '^(margem|rentabilidade|retorno) '
      or (select t from n) ~ '^capital circulante liquido'
      or (select t from n) ~ '^(giro|rotacao) (de|do|da) '
      or (select t from n) ~ 'indicador gerencial'
      then 'derivado'

    -- ---- SÉRIE MENSAL: insumo da curva de sazonalidade ----------------------
    when p_tipo_taxonomia = 'FATURAMENTO_24M' and fn_mes_do_rotulo(p_chave) is not null
      then 'serie_mensal'

    -- ---- SUBTOTAL: já é a soma de outras linhas -----------------------------
    -- (a) prefixo "total"/"subtotal"/"soma"
    when (select t from n) ~ '^(total|totais|subtotal|soma) ' or (select t from n) in ('total','totais','subtotal')
      then 'subtotal'
    -- (b) o total do grupo SEM a palavra "total" (0034), agora contra os tokens
    --     já calculados. Arrays em ordem alfabética — é igualdade de array.
    when (select toks from n) in (
        array['ativo'],
        array['passivo'],
        array['patrimonio'],
        array['passivo','patrimonio'],
        array['ativo','circulante'],
        array['ativo','circulante','nao'],
        array['circulante','passivo'],
        array['circulante','nao','passivo'],
        array['longo','prazo','realizavel'])
      then 'subtotal'
    -- (c) as linhas de RESULTADO da DRE e os subtotais do Fluxo, lista fechada
    when (select t from n) in (
        'receita operacional liquida','receita liquida','receita liquida de vendas',
        'lucro bruto','prejuizo bruto',
        'resultado operacional antes do resultado financeiro',
        'resultado antes dos tributos sobre o lucro','resultado antes dos tributos',
        'lucro liquido do exercicio','prejuizo liquido do exercicio',
        'lucro liquido','prejuizo liquido','resultado do exercicio',
        'resultado financeiro liquido','resultado financeiro')
      then 'subtotal'
    -- (c2) 0116: o TOPO da DRE, que só passa a chegar agora que o total
    --      impresso vira linha. A forma longa ("receita operacional bruta") é o
    --      cabeçalho do bloco de receita na estrutura completa — o valor dela é
    --      a soma das receitas por segmento/produto que vêm abaixo.
    when (select t from n) in (
        'receita operacional bruta','receitas operacionais brutas',
        'receita bruta operacional',
        'deducoes da receita bruta','deducoes da receita',
        'resultado antes do resultado financeiro',
        'resultado operacional')
      then 'subtotal'
    -- (c3) 0116: os totais da DVA. A DVA é feita de blocos que terminam em
    --      total ("Valor adicionado bruto", "Valor adicionado líquido
    --      produzido", "Valor adicionado total a distribuir") e a distribuição
    --      repete o mesmo montante por destinatário — contar o total junto com
    --      os destinatários dobra a demonstração inteira.
    when (select t from n) in (
        'valor adicionado bruto',
        'valor adicionado liquido produzido','valor adicionado liquido',
        'valor adicionado recebido em transferencia',
        'valor adicionado total a distribuir','valor adicionado a distribuir',
        'valor adicionado total','distribuicao do valor adicionado')
      then 'subtotal'
    when (select t from n) ~ '^caixa liquido (gerado|aplicado|gerado pelas)'
      or (select t from n) ~ '^(aumento|reducao|variacao) liquida? (de|do|da) caixa'
      then 'subtotal'

    else 'conta'
  end;
$$;

comment on function fn_papel_linha(text, text, text) is
  'Papel da linha na modelagem: conta | subtotal | derivado | serie_mensal. Lista FECHADA de padrões (não heurística de semelhança) porque errar para subtotal esconde conta de verdade e errar para conta deixa passar dupla contagem. 0102: tokeniza o rótulo uma vez e compara os nove grupos contra o resultado, em vez de nove chamadas a fn_rotulo_estrutural. 0116: cobre o topo da DRE e os totais da DVA, que só passam a chegar depois de o prompt exigir o total IMPRESSO como linha.';

grant execute on function fn_papel_linha(text, text, text) to authenticated;

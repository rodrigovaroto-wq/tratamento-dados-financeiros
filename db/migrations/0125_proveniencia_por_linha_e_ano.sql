-- 0125 — A PROVENIÊNCIA VOLTA AO ARQUIVO DE COMITÊ: página, confiança e aceite.
--
-- O QUE ESTAVA ABERTO, e o §2.3 do `docs/DIAGNOSTICO_SISTEMA_2026-08-11.md` já
-- tinha diagnosticado com precisão:
--
--     "Antes do PR #109 o arquivo de modelagem carregava as abas de dado, e cada
--      célula delas tinha nota de proveniência com documento, página, confiança e
--      status de aceite. O #109 separou os dois exports — decisão certa, medida —
--      e com as abas de dado saiu essa camada. (...) sobrou o nome do documento, e
--      sumiram a página, a confiança e quem aceitou. Para um arquivo que vai a
--      credor, 'de onde veio o 106.580' hoje se responde com o nome do arquivo,
--      não com a linha. Não é regressão de número — é redução de rastreabilidade
--      que aconteceu como efeito colateral de outra decisão."
--
-- ------------------------------------------------ E NEM O NOME DO ARQUIVO ESTAVA LÁ
-- Achado ao ler o código para consertar: o que a nota da `Premissas` mostra é
-- `documentos`, que a `fn_linhas_para_modelagem` monta como
-- `array_agg(distinct o.tipo_taxonomia)` — o TIPO do documento, não o arquivo.
-- A nota dizia "Extraído de BALANCO, DF_AUDITADA". Num mandato com oito balanços
-- isso não localiza nada: é a categoria, não a peça.
--
-- ------------------------------------------- POR QUE A MUDANÇA É NA `fn_valores_por_ano`
-- A tentação é acrescentar as colunas na `fn_linhas_para_modelagem`, que é de onde
-- a nota lê hoje. Estaria errado, e o erro seria silencioso: aquela função devolve
-- UMA linha por (seção, rótulo) — a proveniência dela é da ocorrência de maior
-- módulo, ENTRE TODOS OS EXERCÍCIOS. A nota é de uma célula de ANO. A célula de
-- 2023 receberia a página e a confiança da ocorrência de 2025, e diria com toda a
-- convicção uma coisa que não é sobre ela.
--
-- Rastreabilidade que aponta para a célula errada é pior que rastreabilidade
-- nenhuma: a primeira convida a conferir e leva ao lugar errado.
--
-- A série histórica por ano é a `fn_valores_por_ano`, e é lá que a proveniência
-- pertence — uma por (rótulo, seção, ANO), que é a identidade da célula.
--
-- ----------------------------------------- E O NÚMERO NÃO PODE MUDAR POR CAUSA DISTO
-- `valor` continua sendo `(array_agg(valor order by abs(valor) desc))[1]`,
-- LETRA POR LETRA. Não foi reescrito com janela, e a razão é aritmética: em empate
-- de módulo com sinais opostos (`abs(-1900) = abs(1900)`), duas expressões de
-- "pegue o de maior módulo" podem escolher valores DIFERENTES. Trocar a forma para
-- ganhar elegância mudaria número de modelo em produção sem ninguém pedir.
--
-- A proveniência é obtida por JOIN DE VOLTA na ocorrência que tem aquele valor.
-- Entre ocorrências de valor IDÊNTICO qualquer uma descreve o número corretamente
-- — e o desempate é declarado (maior confiança, depois menor página) para a nota
-- não trocar de conteúdo entre duas execuções sobre o mesmo dado.

-- O TIPO DE RETORNO MUDA (quatro colunas novas), e o Postgres não deixa
-- `create or replace` fazer isso — o `drop` é obrigatório, não zelo. É a mesma
-- sequência que a 0042 usou ao acrescentar `papel` à `fn_linhas_para_modelagem`.
drop function if exists fn_valores_por_ano(uuid, text);

create or replace function fn_valores_por_ano(p_caso_id uuid, p_entidade text default null)
returns table (
  rotulo_norm    text,
  secao_canonica text,
  ano            int,
  valor          numeric,
  n_ocorrencias  bigint,
  -- 0125: a proveniência DA CÉLULA — da ocorrência que produziu este `valor`,
  -- neste ano. `arquivo` é o nome do arquivo como o cliente mandou, não o tipo.
  arquivo        text,
  origem_pagina  int,
  confianca      numeric,
  status_aceite  text,
  aceito_por     text
)
language sql
stable
as $$
  -- marca-0125
  with ocorrencias as (
    select
      fn_normalizar_texto(ce.chave) as rotulo_norm,
      ce.secao_canonica,
      fn_ano_da_coluna(ce.periodo_coluna, p.referencia) as ano,
      ce.valor_num as valor,
      dv.nome_original as arquivo,
      ce.origem_pagina,
      ce.confianca,
      ce.status_aceite,
      ce.aceito_por
    from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
    left join periodo p on p.id = d.periodo_id
    left join entidade e on e.id = d.entidade_id
    where d.caso_id = p_caso_id
      and ce.valor_num is not null
      and (p_entidade is null
           or fn_mesma_entidade(coalesce(ce.entidade_coluna, e.razao_social, ''), p_entidade))
      and dv.id = fn_versao_com_extracao(d.id)
  ),
  agrupado as (
    select o.rotulo_norm, o.secao_canonica, o.ano,
           -- Maior módulo COM SINAL, igual à 0042. Duas grafias da mesma conta no
           -- mesmo exercício não somam: representam o mesmo saldo.
           --
           -- NÃO REESCREVER esta expressão. Ver o cabeçalho: em empate de módulo
           -- com sinais opostos, outra forma de "maior módulo" pode escolher outro
           -- valor, e isso é número de modelo mudando de graça.
           (array_agg(o.valor order by abs(o.valor) desc))[1] as valor,
           count(*) as n_ocorrencias
    from ocorrencias o
    where o.ano is not null
    group by o.rotulo_norm, o.secao_canonica, o.ano
  ),
  -- A PROVENIÊNCIA DA OCORRÊNCIA QUE DEU O VALOR, e não de uma qualquer do grupo.
  -- O desempate entre ocorrências de valor idêntico é declarado, para a nota não
  -- mudar de conteúdo entre duas execuções sobre o mesmo dado: maior confiança
  -- primeiro (é a que o sistema considera mais confiável), depois a página mais
  -- baixa (é onde um humano procuraria primeiro).
  com_proveniencia as (
    select distinct on (a.rotulo_norm, a.secao_canonica, a.ano)
           a.rotulo_norm, a.secao_canonica, a.ano, a.valor, a.n_ocorrencias,
           o.arquivo, o.origem_pagina, o.confianca, o.status_aceite, o.aceito_por
    from agrupado a
    left join ocorrencias o
      on o.rotulo_norm = a.rotulo_norm
     and o.secao_canonica is not distinct from a.secao_canonica
     and o.ano = a.ano
     and o.valor = a.valor
    order by a.rotulo_norm, a.secao_canonica, a.ano,
             o.confianca desc nulls last, o.origem_pagina asc nulls last, o.arquivo
  )
  select rotulo_norm, secao_canonica, ano, valor, n_ocorrencias,
         arquivo, origem_pagina, confianca, status_aceite, aceito_por
  from com_proveniencia
  order by rotulo_norm, ano;
$$;

comment on function fn_valores_por_ano(uuid, text) is
  'Série histórica por (rótulo, seção, ano) — valor de maior módulo com sinal (0042), só da versão vigente (0102). 0125: acrescenta a proveniência DA CÉLULA (arquivo, página, confiança, aceite), da ocorrência que produziu aquele valor naquele ano — nunca a de outro exercício.';

grant execute on function fn_valores_por_ano(uuid, text) to authenticated;

-- Testes da PROVENIÊNCIA POR CÉLULA (0125).
-- Rodar via Supabase/test/run.sh (que aplica as migrations e os fixtures antes).
--
-- O QUE ESTES TESTES PROTEGEM. A `fn_valores_por_ano` decide os NÚMEROS
-- históricos do modelo — é dela que sai a série de cada conta. A `0125` acrescenta
-- quatro colunas de proveniência a ela, e a única forma de isso ser um erro caro é
-- mexer no `valor` sem querer. Por isso o primeiro bloco confere o VALOR, não a
-- proveniência: se a série mudar, nada mais importa.

\set ON_ERROR_STOP on

create or replace function teste_assert(p_ok boolean, p_nome text, p_detalhe text default null)
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
  v_canastra uuid := '11111111-3333-3333-3333-111111111111';
  v_vertentes uuid := '11111111-1111-1111-1111-111111111111';
  v_n int;
  v_num numeric;
  v_txt text;
begin
  raise notice '--- 1. o VALOR não mudou: a série histórica é a mesma ---';
  -- Os números do book, conferidos contra o que o gerador declara. A `0125` não
  -- tocou na expressão de `valor` (o comentário dela explica por quê: em empate de
  -- módulo com sinais opostos, outra forma de "maior módulo" escolhe outro
  -- número), e este assert é o que faz esse cuidado valer alguma coisa.
  select valor into v_num from fn_valores_por_ano(v_canastra, 'CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.')
  where rotulo_norm = 'total do ativo' and ano = 2025;
  perform teste_assert(v_num = 137624,
    'TOTAL DO ATIVO de 2025 continua 137.624', format('%s', v_num));

  select valor into v_num from fn_valores_por_ano(v_canastra, 'CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.')
  where rotulo_norm = 'caixa e bancos conta movimento' and ano = 2023;
  perform teste_assert(v_num = 2853,
    'e o caixa de 2023 continua 2.853 (três exercícios, cada um o seu)', format('%s', v_num));

  raise notice '--- 2. a proveniência é DA CÉLULA, e o arquivo é o ARQUIVO ---';
  -- O que a nota mostrava antes era `documentos`, que é
  -- `array_agg(distinct tipo_taxonomia)` — o TIPO. Num mandato com seis balanços,
  -- "Extraído de BALANCO" não localiza nada.
  select arquivo into v_txt from fn_valores_por_ano(v_canastra, 'CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.')
  where rotulo_norm = 'total do ativo' and ano = 2025;
  perform teste_assert(v_txt like '%Balanco_Patrimonial_Canastra_Industria%',
    'o arquivo é o nome do PDF como o cliente mandou, não o tipo do documento',
    coalesce(v_txt, '(nulo)'));
  perform teste_assert(v_txt not in ('BALANCO', 'BALANCETE'),
    'e nunca é a categoria', coalesce(v_txt, '(nulo)'));

  select confianca, status_aceite into v_num, v_txt
  from fn_valores_por_ano(v_canastra, 'CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.')
  where rotulo_norm = 'total do ativo' and ano = 2025;
  perform teste_assert(v_num is not null and v_num between 0 and 1,
    'a confiança vem como fração entre 0 e 1', format('%s', v_num));
  perform teste_assert(v_txt = 'aceito',
    'e o status de aceite vem junto — é o que separa "o modelo leu" de "alguém conferiu"',
    coalesce(v_txt, '(nulo)'));

  raise notice '--- 3. CADA ANO tem a SUA proveniência (a razão de a 0125 mexer aqui) ---';
  -- Este é o assert central. A `fn_linhas_para_modelagem` também sabe dizer de
  -- onde veio uma linha — mas a resposta dela é da ocorrência de maior módulo
  -- ENTRE OS EXERCÍCIOS, e usá-la na nota de 2023 descreveria a célula de 2025.
  --
  -- No Canastra os três exercícios vêm do MESMO comparativo, então o teste é feito
  -- de outro jeito: uma linha por ano, cada uma com a sua entrada, e nenhuma nula.
  select count(*) into v_n from fn_valores_por_ano(v_canastra, 'CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.')
  where rotulo_norm = 'caixa e bancos conta movimento' and arquivo is not null;
  perform teste_assert(v_n = 3,
    'os TRÊS exercícios da mesma conta trazem, cada um, a sua proveniência',
    format('%s ano(s) com arquivo', v_n));

  -- E o número de linhas devolvidas não mudou: a proveniência não pode
  -- MULTIPLICAR a série. Um join que casa mais de uma ocorrência por (linha, ano)
  -- transformaria uma conta em três, e o modelo somaria a mesma conta três vezes —
  -- é o modo de falha que o `distinct on` da 0125 existe para impedir.
  select count(*) into v_n from fn_valores_por_ano(v_canastra, 'CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.')
  where rotulo_norm = 'caixa e bancos conta movimento';
  perform teste_assert(v_n = 3,
    'e a série continua com UMA linha por ano — a proveniência não multiplica nada',
    format('%s linha(s)', v_n));

  -- O MESMO, no caso inteiro: uma linha por (rótulo, seção, ano), sem duplicata.
  select count(*) into v_n from (
    select rotulo_norm, secao_canonica, ano, count(*) as n
    from fn_valores_por_ano(v_canastra, null)
    group by 1, 2, 3 having count(*) > 1
  ) d;
  perform teste_assert(v_n = 0,
    'nenhum trio (rótulo, seção, ano) aparece duas vezes no caso inteiro',
    format('%s trio(s) duplicados', v_n));

  -- E no book Vertentes também, que é o caso com duas grafias da mesma conta.
  select count(*) into v_n from (
    select rotulo_norm, secao_canonica, ano, count(*) as n
    from fn_valores_por_ano(v_vertentes, null)
    group by 1, 2, 3 having count(*) > 1
  ) d;
  perform teste_assert(v_n = 0, 'idem no book Vertentes', format('%s trio(s)', v_n));

  raise notice '--- 4. "não sei" continua sendo null, nunca um número inventado ---';
  -- O fixture do Canastra não declara `origem_pagina` (a extração nem sempre a
  -- informa). Isso tem de chegar como NULL, para a nota do Excel dizer "não sei"
  -- em vez de escrever "página 0" — que é a diferença entre uma nota auditável e
  -- uma que parece precisa e não é.
  select count(*) into v_n from fn_valores_por_ano(v_canastra, null)
  where origem_pagina = 0;
  perform teste_assert(v_n = 0,
    'página ausente não vira zero', format('%s linha(s) com página 0', v_n));

  raise notice '--- 5. NEGATIVO: a proveniência é da ocorrência que DEU o valor ---';
  -- Duas ocorrências do mesmo rótulo/ano com valores DIFERENTES: o valor escolhido
  -- é o de maior módulo, e a proveniência tem de ser a DELE. Se ela viesse de uma
  -- ocorrência qualquer do grupo, a nota apontaria para o documento onde aquele
  -- número não está.
  insert into campo_extraido
    (documento_versao_id, chave, valor_num, unidade, confianca, secao, secao_canonica,
     periodo_coluna, origem_pagina, status_aceite)
  values
    ('55555555-3333-0000-0000-000000000024', 'CONTA DE TESTE 0125', 100.0, 'milhar', 0.5,
     'Ativo Circulante', 'ativo_circulante', '2025', 7, 'pendente'),
    ('55555555-3333-0000-0000-000000000001', 'CONTA DE TESTE 0125', 900.0, 'milhar', 0.9,
     'Ativo Circulante', 'ativo_circulante', '2025', 3, 'aceito');

  select valor, origem_pagina, status_aceite into v_num, v_n, v_txt
  from fn_valores_por_ano(v_canastra, 'CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.')
  where rotulo_norm = 'conta de teste 0125' and ano = 2025;
  perform teste_assert(v_num = 900, 'o valor escolhido é o de maior módulo (900)', format('%s', v_num));
  perform teste_assert(v_n = 3,
    'e a página é a DA OCORRÊNCIA DE 900 (página 3), não a da de 100 (página 7)',
    format('página %s', v_n));
  perform teste_assert(v_txt = 'aceito',
    'e o aceite também é o dela', coalesce(v_txt, '(nulo)'));

  delete from campo_extraido where chave = 'CONTA DE TESTE 0125';

  raise notice 'TODOS OS TESTES DE PROVENIÊNCIA PASSARAM';
end $$;

drop function teste_assert(boolean, text, text);

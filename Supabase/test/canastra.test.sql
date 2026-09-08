-- Testes da ingestão sobre o book CANASTRA — o book DIFÍCIL.
-- Rodar via Supabase/test/run.sh (que aplica as migrations e o fixture antes).
--
-- O QUE ESTA SUÍTE ACRESCENTA À DE VERTENTES. A `reconciliacao.test.sql` prova
-- que extração fiel de documento FÁCIL não abre pendência. Este arquivo prova a
-- mesma coisa sobre documento DIFÍCIL — e é uma pergunta diferente, porque as 15
-- armadilhas do Canastra são exatamente as formas que a produção tem de parecer
-- erro sem ser: três exercícios com conta que nasce no meio, o mesmo saldo com
-- dois nomes, quatro escalas no mesmo caso, tranche em dólar, coluna de
-- eliminações que não é empresa, não controladores, prognóstico de contingência,
-- documento sem um número monetário sequer.
--
-- A REGRA: **documento difícil, extração fiel => a única pendência é a
-- divergência que o book planta de propósito** (R$ 240 mil de mútuos). Cada
-- armadilha que virar pendência aqui é falso positivo — e falso positivo ensina o
-- analista a ignorar o aviso, que é pior do que não ter aviso.
--
-- ESTA SUÍTE JÁ ACHOU TRÊS DEFEITOS, todos na primeira vez que rodou (ver a
-- `0123`): a checagem de mútuos procurava a palavra "mútuo" no rótulo de cada
-- linha (e nenhuma planilha real a repete ali), uma guarda documentada não
-- existia no código, e mútuo com sócio era somado junto com o intragrupo.

\set ON_ERROR_STOP on
\set CASO '11111111-3333-3333-3333-111111111111'

create or replace function teste_assert(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_ok then
    raise notice 'ok    %', p_nome;
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

create or replace function teste_reconciliar_tudo(p_caso uuid)
returns void language plpgsql as $$
declare r record;
begin
  for r in select id from documento where caso_id = p_caso order by id loop
    perform fn_reconciliar_por_documento(r.id);
  end loop;
end $$;

-- =============================================================================
do $$
declare
  v_caso uuid := '11111111-3333-3333-3333-111111111111';
  v_n int;
  v_num numeric;
  v_txt text;
  v_desc text;
  v_json jsonb;
  v_reg jsonb;
  v_doc uuid;
  v_ver uuid;
begin
  raise notice '--- 1. o book difícil chegou inteiro ao banco ---';

  select count(*) into v_n from documento where caso_id = v_caso;
  perform teste_assert(v_n >= 20, 'os documentos do book estão no caso',
    format('só %s documentos', v_n));

  -- TRÊS exercícios, e é o que separa este book do primeiro. Com dois, a série
  -- realizada do modelo tem dois pontos e qualquer tendência é uma reta; com
  -- três, ela passa a ter forma — e o comparativo passa a ter três colunas, que é
  -- onde o regex de um `x` só falhava (0121).
  select count(distinct ce.periodo_coluna) into v_n
  from campo_extraido ce
  join documento_versao dv on dv.id = ce.documento_versao_id
  join documento d on d.id = dv.documento_id
  where d.caso_id = v_caso and d.tipo_taxonomia = 'BALANCO'
    and ce.periodo_coluna in ('2023', '2024', '2025');
  perform teste_assert(v_n = 3, 'o balanço comparativo tem TRÊS exercícios',
    format('%s colunas de exercício', v_n));

  select count(distinct d.entidade_id) into v_n
  from documento d where d.caso_id = v_caso and d.tipo_taxonomia = 'BALANCO';
  perform teste_assert(v_n = 6, 'os SEIS balanços do grupo, um por empresa',
    format('%s entidades com balanço', v_n));

  raise notice '--- 2. extração fiel do book difícil: UMA pendência, a do book ---';
  perform teste_reconciliar_tudo(v_caso);

  select count(*) into v_n from pendencia
  where caso_id = v_caso and estado <> 'resolvida'
    and motivo <> 'reconciliacao:mutuos_planilha_vs_balanco';
  perform teste_assert(v_n = 0,
    'nenhuma armadilha do book virou pendência',
    format('%s pendência(s) além da de mútuos: %s', v_n,
      (select string_agg(motivo || ' :: ' || left(descricao, 200), ' | ')
         from pendencia where caso_id = v_caso and estado <> 'resolvida'
          and motivo <> 'reconciliacao:mutuos_planilha_vs_balanco')));

  raise notice '--- 3. a divergência de R$ 240 mil dos mútuos APARECE ---';
  -- ESTE É O ASSERT QUE ACHOU O DEFEITO DA 0123. Antes dela a checagem devolvia
  -- `documento_ausente` — ou seja, declarava que não havia o que conferir — e o
  -- caso saía com ZERO pendência. A divergência plantada pelo book não estava
  -- "não encontrada": estava afirmada inexistente, que é a forma mais silenciosa
  -- de uma checagem falhar.
  select count(*) into v_n from pendencia
  where caso_id = v_caso and estado <> 'resolvida'
    and motivo = 'reconciliacao:mutuos_planilha_vs_balanco';
  perform teste_assert(v_n = 1,
    'a divergência de mútuos do book abre UMA pendência', format('%s pendência(s)', v_n));

  select r.divergencia_abs into v_num from reconciliacao r
  where r.caso_id = v_caso and r.tipo = 'mutuos_planilha_vs_balanco'
    and r.resultado = 'zona_cinzenta'
  order by r.criado_em desc limit 1;
  -- R$ 240 mil, em REAIS: o documento está em milhar e a tolerância da checagem
  -- é em moeda base, então o número que ela guarda também tem de ser.
  perform teste_assert(v_num between 239000 and 241000,
    'e ela mede os R$ 240 mil que o gerador do book planta',
    format('divergência medida: %s', v_num));

  -- OS DOIS LADOS SE CONFIRMAM, e é isso que faz a planilha ser a parte errada.
  -- A holding registra 16.300 a receber; Indústria (11.400) e Comercial (4.900)
  -- registram 16.300 a pagar. UMA comparação, contra um saldo estabelecido por
  -- dupla evidência — não duas comparações repetindo o mesmo fato.
  select descricao into v_desc from pendencia
  where caso_id = v_caso and motivo = 'reconciliacao:mutuos_planilha_vs_balanco';
  perform teste_assert(v_desc like '%os dois lados%',
    'a pendência diz que o saldo do balanço vem dos DOIS lados', v_desc);
  perform teste_assert(v_desc like '%1 comparação%',
    'e faz UMA comparação, não uma por lado', v_desc);

  raise notice '--- 4. mútuo com SÓCIO fica fora da conferência intragrupo ---';
  -- A SPE tem "Empréstimo de sócios (mútuo com quotistas)" = 14.000. É mútuo, e
  -- está na conta certa, mas a contraparte é o quotista: a outra ponta dele não
  -- existe dentro do mandato, e a planilha intragrupo não tem por que listá-lo.
  -- Somá-lo no lado do balanço daria 14.240 de "divergência da planilha" onde há
  -- 240 — e escondia os 240 atrás de um número 60 vezes maior.
  select count(*) into v_n from campo_extraido ce
  join documento_versao dv on dv.id = ce.documento_versao_id
  join documento d on d.id = dv.documento_id
  where d.caso_id = v_caso and ce.chave ilike '%quotista%';
  perform teste_assert(v_n >= 1, 'o mútuo com quotistas está no fixture (é o caso a excluir)');

  perform teste_assert(fn_mutuo_com_socio('Empréstimo de sócios (mútuo com quotistas)'),
    'fn_mutuo_com_socio reconhece o empréstimo dos sócios');
  perform teste_assert(not fn_mutuo_com_socio('Mútuos a pagar - Canastra Participações'),
    'e NÃO confunde mútuo intragrupo com mútuo de sócio');

  perform teste_assert(v_desc not like '%14240%' and v_desc not like '%14.240%',
    'a divergência relatada NÃO inclui o empréstimo dos sócios', v_desc);

  raise notice '--- 5. a natureza pode estar fora da linha (a causa da 0123) ---';
  -- O quadro de mútuos do Canastra é uma tabela plana: "Mutuante | Mutuária |
  -- Saldo devedor", sob o título "RELAÇÃO DE MÚTUOS ENTRE PARTES RELACIONADAS".
  -- Nenhuma LINHA contém a palavra; a seção contém. É a forma normal, e era
  -- justamente a que a checagem não via.
  select count(*) into v_n from campo_extraido ce
  join documento_versao dv on dv.id = ce.documento_versao_id
  join documento d on d.id = dv.documento_id
  where d.caso_id = v_caso and d.tipo_taxonomia = 'MUTUOS'
    and fn_normalizar_texto(ce.chave) like '%mutuo%';
  perform teste_assert(v_n = 0,
    'nenhuma LINHA da planilha de mútuos repete a palavra (é assim no papel)',
    format('%s linha(s) com a palavra no rótulo', v_n));

  select count(*) into v_n from campo_extraido ce
  join documento_versao dv on dv.id = ce.documento_versao_id
  join documento d on d.id = dv.documento_id
  where d.caso_id = v_caso and d.tipo_taxonomia = 'MUTUOS'
    and fn_texto_nomeia_mutuo(ce.secao);
  perform teste_assert(v_n >= 2,
    'e a checagem as encontra pela SEÇÃO (degrau 2)',
    format('%s linha(s) reconhecidas', v_n));

  -- A PRECEDÊNCIA, travada. O degrau 2 só vale porque o degrau 1 está vazio; se a
  -- seção valesse por si, uma seção larga como a de Vertentes ("MÚTUOS E CONTAS
  -- INTRAGRUPO") passaria a incluir conta corrente e aluguel na soma de mútuos —
  -- exatamente o defeito que a 0117 já avisava, e que a primeira versão da 0123
  -- cometeu de novo (a divergência de Vertentes saltou de 180 para 2.220 mil).
  perform teste_assert(
    fn_texto_nomeia_mutuo('Vertentes Participações → Metalúrgica — Mútuo')
    and not fn_texto_nomeia_mutuo('Metalúrgica → VT Logística — Conta corrente'),
    'o RÓTULO separa mútuo de conta corrente quando ele fala (degrau 1)');
  perform teste_assert(fn_texto_nomeia_mutuo('MÚTUOS E CONTAS INTRAGRUPO'),
    'a seção larga também "nomeia" — e é por isso que ela não pode ter precedência');

  raise notice '--- 6. as escalas: quatro no mesmo caso, cada uma declarada ---';
  -- Demonstrações em R$ mil, mapa de dívida e faturamento em reais, estoque em
  -- tonelada, folha em pessoas. Quem ignora a `unidade` erra por 1.000x num
  -- caminho e cria uma fábrica com 412.000 empregados no outro.
  select count(distinct ce.unidade) into v_n
  from campo_extraido ce
  join documento_versao dv on dv.id = ce.documento_versao_id
  join documento d on d.id = dv.documento_id
  where d.caso_id = v_caso and ce.unidade is not null;
  perform teste_assert(v_n >= 4, 'quatro ou mais escalas declaradas no caso',
    format('%s escalas: %s', v_n,
      (select string_agg(distinct ce.unidade, ', ')
         from campo_extraido ce
         join documento_versao dv on dv.id = ce.documento_versao_id
         join documento d on d.id = dv.documento_id
        where d.caso_id = v_caso and ce.unidade is not null)));

  -- O headcount é em PESSOAS e tem de continuar em pessoas: 412 empregados, não
  -- 412.000. `fn_valor_em_base` só converte escala MONETÁRIA.
  select ce.valor_num into v_num
  from campo_extraido ce
  join documento_versao dv on dv.id = ce.documento_versao_id
  join documento d on d.id = dv.documento_id
  where d.caso_id = v_caso and d.tipo_taxonomia = 'HEADCOUNT'
    and ce.chave = 'TOTAL' and ce.unidade = 'pessoas';
  perform teste_assert(v_num between 100 and 5000,
    'o headcount total é um número de PESSOAS, não de milhares',
    format('headcount = %s', v_num));

  raise notice '--- 7. a tranche em DÓLAR não entra somada em reais ---';
  -- Erro de ~5,4x se a coluna errada for somada — a mesma família do que a 0035
  -- corrigiu. A linha em dólar DECLARA `moeda`, e é o que separa as duas.
  select count(*) into v_n from campo_extraido ce
  join documento_versao dv on dv.id = ce.documento_versao_id
  join documento d on d.id = dv.documento_id
  where d.caso_id = v_caso and d.tipo_taxonomia = 'MAPA_DIVIDA' and ce.moeda = 'USD';
  perform teste_assert(v_n = 1, 'há exatamente uma linha em dólar no mapa de dívida',
    format('%s linha(s) em USD', v_n));

  select sum(ce.valor_num) into v_num from campo_extraido ce
  join documento_versao dv on dv.id = ce.documento_versao_id
  join documento d on d.id = dv.documento_id
  where d.caso_id = v_caso and d.tipo_taxonomia = 'MAPA_DIVIDA'
    and ce.chave like 'TOTAL — saldo devedor' and ce.moeda = 'BRL';
  perform teste_assert(v_num > 0 and v_num = (
    select sum(ce2.valor_num) from campo_extraido ce2
    join documento_versao dv2 on dv2.id = ce2.documento_versao_id
    join documento d2 on d2.id = dv2.documento_id
    where d2.caso_id = v_caso and d2.tipo_taxonomia = 'MAPA_DIVIDA'
      and ce2.chave like '%saldo devedor' and ce2.chave not like 'TOTAL%'
      and ce2.moeda = 'BRL'),
    'o TOTAL do mapa é a soma das linhas em REAIS (a de dólar não entra duas vezes)',
    format('total declarado: %s', v_num));

  raise notice '--- 8. a coluna "Eliminações" não é empresa, e há não controladores ---';
  select count(*) into v_n from entidade
  where caso_id = v_caso and fn_normalizar_texto(razao_social) like '%eliminac%';
  perform teste_assert(v_n = 0,
    'nenhuma entidade foi criada a partir da coluna de eliminações',
    format('%s entidade(s) chamadas "Eliminações"', v_n));

  select count(*) into v_n from campo_extraido ce
  join documento_versao dv on dv.id = ce.documento_versao_id
  join documento d on d.id = dv.documento_id
  where d.caso_id = v_caso and d.tipo_taxonomia = 'COMBINADO'
    and ce.entidade_coluna = 'Eliminações';
  perform teste_assert(v_n >= 3,
    'as eliminações estão como COLUNA do combinado', format('%s linha(s)', v_n));

  -- "Combinado = soma das colunas" está errado POR CONSTRUÇÃO: há 35% de não
  -- controladores na CN Transportes, e a diferença tem linha própria.
  select count(*) into v_n from campo_extraido ce
  join documento_versao dv on dv.id = ce.documento_versao_id
  join documento d on d.id = dv.documento_id
  where d.caso_id = v_caso and d.tipo_taxonomia = 'COMBINADO'
    and ce.chave ilike '%não controladores%';
  perform teste_assert(v_n = 1, 'a participação de não controladores é uma linha declarada');

  raise notice '--- 9. documento sem número não gera linha, e isso é o CERTO (0111) ---';
  select count(*) into v_n from documento d
  where d.caso_id = v_caso
    and d.tipo_taxonomia in ('CERTIDOES', 'ORGANOGRAMA', 'CONTRATO_SOCIAL');
  perform teste_assert(v_n = 3, 'os três documentos sem valor monetário estão no caso');

  select count(*) into v_n from campo_extraido ce
  join documento_versao dv on dv.id = ce.documento_versao_id
  join documento d on d.id = dv.documento_id
  where d.caso_id = v_caso
    and d.tipo_taxonomia in ('CERTIDOES', 'ORGANOGRAMA', 'CONTRATO_SOCIAL');
  perform teste_assert(v_n = 0,
    'e nenhum deles produziu linha financeira', format('%s linha(s) indevidas', v_n));

  -- E não podem ser contados como falha de extração — é o acerto da 0111.
  select count(*) into v_n from pendencia
  where caso_id = v_caso and estado <> 'resolvida'
    and descricao ilike '%certid%';
  perform teste_assert(v_n = 0, 'a certidão negativa não abre pendência de extração vazia');

  raise notice '--- 10. conta que nasce no meio do histórico: vazio NÃO é zero ---';
  -- A antecipação de recebíveis nasce em 2024 e o parcelamento tributário em
  -- 2025. Extração fiel não inventa a linha nos anos anteriores — e um zero ali
  -- seria um VALOR, que o modelo projetaria.
  select count(*) into v_n from campo_extraido ce
  join documento_versao dv on dv.id = ce.documento_versao_id
  join documento d on d.id = dv.documento_id
  where d.caso_id = v_caso and d.tipo_taxonomia = 'BALANCO'
    and ce.chave ilike '%antecipação de recebíveis%' and ce.periodo_coluna = '2023';
  perform teste_assert(v_n = 0,
    'a antecipação de recebíveis NÃO tem linha em 2023 (ela nasce depois)',
    format('%s linha(s) inventadas em 2023', v_n));

  select count(*) into v_n from campo_extraido ce
  join documento_versao dv on dv.id = ce.documento_versao_id
  join documento d on d.id = dv.documento_id
  where d.caso_id = v_caso and d.tipo_taxonomia = 'BALANCO'
    and ce.chave ilike '%antecipação de recebíveis%' and ce.periodo_coluna = '2025';
  perform teste_assert(v_n >= 1, 'e TEM linha em 2025');

  raise notice '--- 11. o mesmo saldo com dois nomes, e nenhum foi apagado ---';
  -- "Duplicatas a receber de clientes - mercado interno" (2023/2024) vira
  -- "Clientes - duplicatas a receber - mercado interno" (2025). A doutrina do
  -- repositório é não apagar conta: os dois rótulos ficam, e quem decide é o
  -- humano na revisão.
  select count(distinct ce.chave) into v_n from campo_extraido ce
  join documento_versao dv on dv.id = ce.documento_versao_id
  join documento d on d.id = dv.documento_id
  where d.caso_id = v_caso and d.tipo_taxonomia = 'BALANCO'
    and ce.chave ilike '%duplicatas a receber%mercado interno%';
  perform teste_assert(v_n = 2,
    'os DOIS rótulos da mesma conta estão gravados, nenhum apagado',
    format('%s rótulo(s)', v_n));

  raise notice '--- 12. contingência por prognóstico: o passivo não infla ---';
  -- Somar provável + possível + remoto infla o passivo. A `secao` carrega o
  -- prognóstico, que é o que separa o provisionado da divulgação em nota.
  select count(distinct ce.secao) into v_n from campo_extraido ce
  join documento_versao dv on dv.id = ce.documento_versao_id
  join documento d on d.id = dv.documento_id
  where d.caso_id = v_caso and d.tipo_taxonomia = 'CONTINGENCIAS';
  perform teste_assert(v_n >= 3,
    'os três prognósticos estão separados por seção', format('%s seções', v_n));

  raise notice '--- 13. o INTRAGRUPO que não é mútuo fecha nos dois balanços (0124) ---';
  -- O ESPELHO É A CHECAGEM, e o pareamento é pelo PAR DE EMPRESAS, não pela
  -- natureza. O book mostra por quê: quem vende chama de "Contas a receber
  -- intragrupo - Canastra Comercial" e quem compra chama de "Fornecedores
  -- intragrupo - Canastra Indústria" — pela natureza elas nunca se encontram.
  -- O ID VEM DA CHAMADA, não de `order by criado_em desc limit 1`: `reconciliacao`
  -- é log append-only e todas as linhas de uma transação compartilham o
  -- `criado_em`, então ordenar por ele escolhe uma linha arbitrária entre as do
  -- mesmo instante. Foi assim que este assert falhou ao ser escrito — leu a linha
  -- de um período MULTI (que confere os pares de três exercícios) achando que lia
  -- a de 2025.
  select fn_reconciliar_intragrupo(v_caso, p.id) into v_json
  from periodo p where p.caso_id = v_caso and p.tipo = 'anual' and p.referencia = '2025';
  perform teste_assert(v_json->>'resultado' = 'ok',
    'os pares intragrupo de 2025 fecham: aluguel 940, conta corrente 1.900, fornecimento 2.900 e 5.200',
    format('resultado: %s', v_json->>'resultado'));

  select r.materialidade->>'pares_conferidos' into v_txt from reconciliacao r
  where r.id = (v_json->>'reconciliacao_id')::uuid;
  perform teste_assert(v_txt = '4',
    'e são os QUATRO pares do book, num exercício só', format('pares: %s', v_txt));

  -- No período MULTI a contagem soma os exercícios, e é o que se espera: a
  -- Comercial tem coluna de 2024 e as demais não, então 2024 contribui com o par
  -- Indústria × Comercial e 2023 com nenhum.
  select fn_reconciliar_intragrupo(v_caso, p.id) into v_json
  from periodo p where p.caso_id = v_caso and p.tipo = 'multi' and p.referencia = '23,24,25';
  select r.materialidade->>'pares_conferidos' into v_txt from reconciliacao r
  where r.id = (v_json->>'reconciliacao_id')::uuid;
  perform teste_assert(v_txt = '5',
    'nos três exercícios são 5 conferências de par (4 em 2025 + 1 em 2024)',
    format('pares: %s', v_txt));
  perform teste_assert(v_json->>'resultado' = 'ok', 'e todas fecham');

  -- A CONTRAPARTE SAI DO RÓTULO, e é isso que dispensa adivinhar qual conta casa
  -- com qual. Seis rótulos intragrupo do book casam com a empresa certa; três
  -- rótulos de terceiro não casam com ninguém.
  perform teste_assert(
    fn_contraparte_intragrupo(v_caso, 'Conta corrente a pagar - CN Transportes e Logística')
      = (select id from entidade where caso_id = v_caso and razao_social ilike 'CN TRANSPORTES%'),
    'o rótulo nomeia a contraparte, e ela é achada na lista de entidades do caso');
  perform teste_assert(
    fn_contraparte_intragrupo(v_caso, 'Aluguéis a receber - terceiros') is null,
    'e "terceiros" NÃO casa com empresa nenhuma — senão a checagem inventaria par');
  perform teste_assert(
    fn_contraparte_intragrupo(v_caso, 'Duplicatas a receber de clientes - mercado interno') is null,
    'nem "mercado interno"');
  -- A própria empresa não é contraparte de si: rótulo redundante não é relação.
  perform teste_assert(
    fn_contraparte_intragrupo(v_caso, 'Fornecedores intragrupo - Canastra Agroflorestal',
      (select id from entidade where caso_id = v_caso and razao_social ilike 'CANASTRA AGRO%')) is null,
    'linha do balanço de A que nomeia A não é intragrupo');

  -- O LADO vem da SEÇÃO CANÔNICA primeiro. "Fornecedores intragrupo - X" é
  -- obrigação e não tem "a pagar" no nome: quem decidir só pelo rótulo erra o
  -- lado e a soma sai dos dois lados errada de uma vez.
  perform teste_assert(fn_lado_intragrupo('Fornecedores intragrupo - X', 'passivo_circulante') = 'passivo',
    'a seção canônica decide o lado');
  perform teste_assert(fn_lado_intragrupo('Fornecedores intragrupo - X', null) = 'passivo',
    'e sem ela o rótulo "fornecedor" ainda diz obrigação');
  perform teste_assert(fn_lado_intragrupo('Contas a receber intragrupo - X', null) = 'ativo',
    'e "a receber" diz crédito');

  raise notice '--- 14. NEGATIVO: o espelho intragrupo pega o lado que não fecha ---';
  -- Mexe em UM lado do par Indústria × CN Transportes (a conta corrente de 1.900)
  -- e a checagem tem de acusar — nomeando as duas empresas e a natureza.
  update campo_extraido ce set valor_num = 1900 + 900
  where ce.chave = 'Conta corrente a receber - Canastra Indústria'
    and ce.documento_versao_id in (
      select fn_versao_atual(d.id) from documento d
      where d.caso_id = v_caso and d.tipo_taxonomia = 'BALANCO');
  perform teste_reconciliar_tudo(v_caso);

  select count(*) into v_n from pendencia
  where caso_id = v_caso and estado <> 'resolvida'
    and motivo = 'reconciliacao:intragrupo_espelho';
  perform teste_assert(v_n = 1, 'o par que não fecha abre UMA pendência',
    format('%s pendência(s)', v_n));

  select descricao into v_desc from pendencia
  where caso_id = v_caso and motivo = 'reconciliacao:intragrupo_espelho';
  perform teste_assert(v_desc like '%CN TRANSPORTES%' and v_desc like '%CANASTRA INDÚSTRIA%',
    'e ela NOMEIA as duas empresas do par', v_desc);
  perform teste_assert(v_desc like '%conta corrente%',
    'e a natureza, para o analista saber onde procurar', v_desc);
  perform teste_assert(v_desc like '%900000%',
    'e a diferença em reais (900 mil, escalas já convertidas)', v_desc);
  -- E SÓ o par mexido: os outros três continuam fechando, então não podem
  -- aparecer na mensagem. Uma pendência que cita par que fecha é ruído.
  perform teste_assert(v_desc not like '%IMOBILIÁRIA%' and v_desc not like '%AGROFLORESTAL%',
    'os pares que fecham não são citados', v_desc);

  update campo_extraido ce set valor_num = 1900
  where ce.chave = 'Conta corrente a receber - Canastra Indústria'
    and ce.documento_versao_id in (
      select fn_versao_atual(d.id) from documento d
      where d.caso_id = v_caso and d.tipo_taxonomia = 'BALANCO');
  perform teste_reconciliar_tudo(v_caso);
  select count(*) into v_n from pendencia
  where caso_id = v_caso and estado <> 'resolvida'
    and motivo = 'reconciliacao:intragrupo_espelho';
  perform teste_assert(v_n = 0, 'corrigido o lado, a pendência auto-resolve',
    format('%s pendência(s) ainda abertas', v_n));

  raise notice '--- 15. NEGATIVO: a checagem de mútuos ainda pega o erro real ---';
  -- Uma checagem que passou a achar mais coisa tem de continuar sabendo dizer
  -- "confere". Alinhando a planilha com o balanço, a pendência resolve.
  update campo_extraido ce set valor_num = valor_num + 240
  where ce.documento_versao_id = (
      select fn_versao_atual(d.id) from documento d
      where d.caso_id = v_caso and d.tipo_taxonomia = 'MUTUOS')
    and ce.chave like 'CANASTRA PARTICIPAÇÕES%INDÚSTRIA%';
  update campo_extraido ce set valor_num = 16300
  where ce.documento_versao_id = (
      select fn_versao_atual(d.id) from documento d
      where d.caso_id = v_caso and d.tipo_taxonomia = 'MUTUOS')
    and ce.chave = 'TOTAL';
  perform teste_reconciliar_tudo(v_caso);

  select count(*) into v_n from pendencia
  where caso_id = v_caso and estado <> 'resolvida'
    and motivo = 'reconciliacao:mutuos_planilha_vs_balanco';
  perform teste_assert(v_n = 0,
    'planilha corrigida: a pendência de mútuos auto-resolve',
    format('%s pendência(s) ainda abertas', v_n));

  -- O VEREDITO VEM DA CHAMADA, não da tabela. `reconciliacao` é log append-only e
  -- todas as linhas gravadas dentro de UMA transação compartilham o `criado_em`
  -- (`now()` é fixo no transaction), então `order by criado_em desc limit 1`
  -- escolhe uma linha arbitrária entre as do mesmo instante — este assert falhou
  -- exatamente assim ao ser escrito, apontando 'zona_cinzenta' depois de a
  -- pendência ter auto-resolvido. Perguntar à função é determinístico e é o que
  -- se quer afirmar.
  select fn_reconciliar_mutuos(v_caso, p.id)->>'resultado' into v_txt
  from periodo p where p.caso_id = v_caso and p.tipo = 'anual' and p.referencia = '2025';
  perform teste_assert(v_txt = 'ok',
    'e a reconciliação passa a dizer "ok", não "documento_ausente"',
    format('resultado: %s', v_txt));

  -- Desfaz, para o caso ficar como o fixture o deixou.
  update campo_extraido ce set valor_num = valor_num - 240
  where ce.documento_versao_id = (
      select fn_versao_atual(d.id) from documento d
      where d.caso_id = v_caso and d.tipo_taxonomia = 'MUTUOS')
    and ce.chave like 'CANASTRA PARTICIPAÇÕES%INDÚSTRIA%';
  update campo_extraido ce set valor_num = 16060
  where ce.documento_versao_id = (
      select fn_versao_atual(d.id) from documento d
      where d.caso_id = v_caso and d.tipo_taxonomia = 'MUTUOS')
    and ce.chave = 'TOTAL';
  perform teste_reconciliar_tudo(v_caso);

  select count(*) into v_n from pendencia
  where caso_id = v_caso and estado <> 'resolvida'
    and motivo = 'reconciliacao:mutuos_planilha_vs_balanco';
  perform teste_assert(v_n = 1, 'e volta a abrir quando a divergência volta');

  raise notice '--- 16. HOLDING registrada, subsidiária no conteúdo: não é entidade_incorreta (0160) ---';
  -- Reproduz o achado real do lote 7377 (ESTADO.md, SESSÃO 79): o
  -- `33_Notas_Explicativas` registrado em GRUPO CANASTRA, com o diagnóstico de
  -- conteúdo apontando Canastra Indústria. As DUAS já são entidades do fixture
  -- (nenhum dado inventado) — são a holding e uma subsidiária real do book.
  select fn_registrar_documento(
    v_caso, 'GRUPO CANASTRA', 'anual', '2025', 'BALANCO', 0.9, 'nome_arquivo',
    'supabase_storage', 'b/33.pdf', '33_Notas_Explicativas_Canastra.pdf', true, 'H-0160-A', 'ok'
  ) into v_reg;
  v_doc := (v_reg->>'documento_id')::uuid;
  v_ver := (v_reg->>'documento_versao_id')::uuid;

  perform fn_registrar_diagnostico(v_doc, v_ver, 'CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.',
            true, 'BALANCO', 'anual', '2025', 'ok', null, 'r', 'j');

  select count(*) into v_n from pendencia
   where caso_id = v_caso and motivo = 'diagnostico:entidade:' || v_doc and estado <> 'resolvida';
  perform teste_assert(v_n = 0,
    'GRUPO CANASTRA × Canastra Indústria NÃO abre a pendência clássica de "entidade incorreta"',
    format('%s pendência(s) diagnostico:entidade', v_n));

  select count(*), max(descricao) into v_n, v_desc from pendencia
   where caso_id = v_caso and motivo = 'diagnostico:entidade_grupo:' || v_doc and estado <> 'resolvida';
  perform teste_assert(v_n = 1,
    'e abre UMA pendência de hierarquia, distinta pelo motivo', format('%s pendência(s)', v_n));
  perform teste_assert(v_desc like '%GRUPO CANASTRA%' and v_desc like '%CANASTRA INDÚSTRIA DE EMBALAGENS%',
    'a descrição nomeia as DUAS empresas', v_desc);
  perform teste_assert(v_desc not ilike '%incorreto%' and v_desc not ilike '%errad%',
    'e não chama nenhuma das duas de errada — é hierarquia, não erro', v_desc);
  perform teste_assert(v_desc ilike '%sem fundir%' or v_desc ilike '%diferentes%',
    'e não sugere fundir as duas: continuam sendo empresas distintas', v_desc);

  raise notice '--- 17. NEGATIVO: divergência de VERDADE continua abrindo entidade_incorreta (0160) ---';
  -- Um nome que não bate com NENHUMA empresa do caso não é hierarquia — é o
  -- erro que a 0121 já sabia acusar, e a 0160 não pode ter destravado isso.
  select fn_registrar_documento(
    v_caso, 'CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.', 'anual', '2025', 'DRE', 0.9, 'nome_arquivo',
    'supabase_storage', 'b/34.pdf', '34_DRE_Canastra_Industria.pdf', true, 'H-0160-B', 'ok'
  ) into v_reg;
  v_doc := (v_reg->>'documento_id')::uuid;
  v_ver := (v_reg->>'documento_versao_id')::uuid;

  perform fn_registrar_diagnostico(v_doc, v_ver, 'Empresa Fantasma Que Não Existe No Caso Ltda.',
            true, 'DRE', 'anual', '2025', 'ok', null, 'r', 'j');

  select count(*) into v_n from pendencia
   where caso_id = v_caso and motivo = 'diagnostico:entidade:' || v_doc and estado <> 'resolvida';
  perform teste_assert(v_n = 1,
    'nome que não casa com NINGUÉM do caso continua abrindo entidade_incorreta',
    format('%s pendência(s)', v_n));

  select count(*) into v_n from pendencia
   where caso_id = v_caso and motivo = 'diagnostico:entidade_grupo:' || v_doc and estado <> 'resolvida';
  perform teste_assert(v_n = 0,
    'e NÃO abre pendência de hierarquia — não há outra empresa candidata',
    format('%s pendência(s)', v_n));

  raise notice 'TODOS OS TESTES DO BOOK CANASTRA PASSARAM';
end $$;

drop function teste_assert(boolean, text, text);
drop function teste_reconciliar_tudo(uuid);

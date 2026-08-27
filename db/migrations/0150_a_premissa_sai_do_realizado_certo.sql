-- 0150 — A PREMISSA DO REALIZADO SOMAVA O QUE NÃO PODE SER SOMADO.
--
-- ACHADO NA RODADA COMPARATIVA DO CANASTRA (27/08/2026), no mandato "Teste
-- comparativo - Grupo Canastra". As oito premissas que o próprio caso responde
-- vieram assim, gravadas com `origem = 'historico'`:
--
--   PMR .............. 348,6 dias   (plausível: ~80)
--   PME .............. 177,5 dias   (plausível: ~60)
--   CUSTO_VARIAVEL ... 287,7 % da receita  (plausível: ~55%)
--   SGA_PCT ..........  83,2 %      (plausível: ~14%)
--
-- Não é imprecisão: é soma do que não se soma. Três causas, e as três se somam
-- no mesmo número.
--
-- CAUSA 1 — O TOTAL SOMA COM AS PRÓPRIAS COMPONENTES. A bolsa de custos deu
-- 410.749, que é exatamente:
--
--    177.077  "(-) CUSTO DOS PRODUTOS VENDIDOS E DOS SERVIÇOS PRESTADOS"  ← o TOTAL
--    177.133  as cinco componentes dele (matéria-prima, mão de obra, energia,
--             depreciação industrial, outros custos)
--     56.539  o CPV da Cn Transportes
--   --------
--    410.749
--
-- `fn_papel_linha` classifica esse total como `conta`, e está fazendo o que a
-- `0116` mandou: a lista de subtotais é FECHADA e deixou o topo da DRE de fora
-- DE PROPÓSITO, porque num documento resumido "Despesas operacionais" É a conta.
-- A doutrina continua certa; o que faltava é o discriminador que ela não tinha
-- como ter: **o total é subtotal quando o MESMO documento também traz as
-- componentes dele.** `fn_papel_linha` é `immutable` e enxerga um rótulo por
-- vez — quem enxerga o documento inteiro é esta função.
--
-- CAUSA 2 — A ABERTURA ANALÍTICA SOMA POR CIMA DA CONTA QUE ELA ABRE. A bolsa
-- "clientes" deu 174.142 num grupo cuja maior conta de clientes é 35.044: entram
-- os 312 sacados do aging de recebíveis (um por linha), os itens da posição de
-- estoque (bobina a bobina), os bancos do extrato (banco a banco) e o balancete
-- analítico inteiro — todos abertura de contas que o balanço já declara. Somar
-- os dois é contar duas vezes, e o produto não tinha como saber a diferença:
-- `taxonomia_tipo_documento` não declarava quais tipos são DEMONSTRAÇÃO e quais
-- são ABERTURA. Passa a declarar.
--
-- CAUSA 3 — O CASO É DE OITO EMPRESAS E O MODELO PROJETA UMA. A tela pergunta
-- qual entidade a modelagem projeta (`caso_modelagem.entidade`) e a soma do
-- realizado ignorava a resposta: media o numerador em oito empresas e o
-- denominador também, e as duas distorções não se cancelam — cada razão erra
-- para um lado diferente. O combinado do grupo entra por cima disso, somando o
-- consolidado com as parcelas que o formam.
--
-- E UM QUARTO, QUE NÃO ERA DEFEITO E VIROU CAPACIDADE. `fn_linhas_para_modelagem`
-- devolve UM número por rótulo — "a ocorrência de maior módulo" (0042), que o
-- nome `valor_ultimo` sugere ser a mais recente e não é: numa empresa que
-- encolhe, a de maior módulo é a mais ANTIGA. Para uma razão do realizado isso
-- basta mal; para a média de vários exercícios não serve. Esta migration passa a
-- devolver o valor POR EXERCÍCIO, que é o que permite projetar pela média
-- histórica em vez de pelo último ano — e o último ano de uma empresa em
-- reestruturação é o pior ano dela.
--
-- O QUE ESTA MIGRATION NÃO FAZ: não muda `fn_linhas_para_modelagem`. Aquela
-- função alimenta a LISTA da tela (uma linha por rótulo, para escolher premissa)
-- e a conferência do "pronto"; mudá-la mudaria as duas por tabela. A soma do
-- realizado ganha função própria, com a regra própria dela.

-- -----------------------------------------------------------------------------
-- 1. O EXERCÍCIO DA COLUNA — e a coluna que não é exercício
-- -----------------------------------------------------------------------------
--
-- `campo_extraido.periodo_coluna` é texto livre, do jeito que o documento
-- escreveu o cabeçalho. Medido no caso do Canastra: "31/12/2024", "2024",
-- "Saldo", "Valor", "Crédito", "Faturamento (R$)", "Ticket médio (R$)".
--
-- As três últimas NÃO SÃO PERÍODO — são dimensões da tabela, e a `0140` já
-- tinha pago para aprender isso em outro lugar. Uma média histórica que as
-- tratasse como ano misturaria "crédito" com "2024" na mesma série.
--
-- A regra é a mais simples que responde: **ano de quatro dígitos plausível
-- dentro do texto, ou nada.** Nada é a resposta certa para "Saldo" — e é o que
-- faz a coluna sem ano ficar de fora da média em vez de virar um exercício
-- inventado.
create or replace function fn_exercicio_da_coluna(p_coluna text)
returns integer
language sql immutable
as $$
  select (m[1])::int
  from regexp_match(coalesce(p_coluna, ''), '(19[5-9][0-9]|20[0-9]{2}|21[0-9]{2})') m
  where m[1] is not null
$$;

comment on function fn_exercicio_da_coluna(text) is
  'O exercício que o cabeçalho da coluna nomeia, ou NULL quando ele não nomeia exercício nenhum '
  '("Saldo", "Crédito", "Ticket médio"). Ausência é ausência: coluna sem ano fica FORA da série '
  'histórica em vez de virar um ano inventado.';

-- -----------------------------------------------------------------------------
-- 2. QUAL TIPO DE DOCUMENTO É DEMONSTRAÇÃO, E QUAL É ABERTURA DELA
-- -----------------------------------------------------------------------------
--
-- Dado, não código: a lista vive no catálogo, ao lado da granularidade e da
-- obrigatoriedade, porque é da mesma natureza que elas — e porque tipo novo é
-- LINHA nova, não `if` novo.
--
-- O critério não é "documento detalhado": é **este documento reafirma, aberta,
-- uma conta que outro documento do mesmo caso já declara?**
--
--   • BALANCETE abre o balanço conta a conta — o próprio plano de contas;
--   • AGING_AR e AGING_AP abrem clientes e fornecedores, sacado a sacado;
--   • ESTOQUE abre a conta de estoques, item a item;
--   • EXTRATO_BANCARIO abre caixa e bancos, banco a banco;
--   • RAZAO abre qualquer conta, lançamento a lançamento;
--   • APLIC_FINANC abre as aplicações;
--   • DEBITOS_TRIB abre os tributos a recolher;
--   • HEADCOUNT e FOLHA abrem a despesa de pessoal.
--
-- COMBINADO fica de fora da soma por outro motivo, e é o mais importante para o
-- book de 190: ele é a SOMA das empresas menos as eliminações. Somá-lo junto das
-- parcelas conta o grupo inteiro duas vezes — a armadilha central do
-- `book-araucaria`, que aqui já apareceu sozinha.
alter table taxonomia_tipo_documento
  add column if not exists abertura_analitica boolean not null default false;

comment on column taxonomia_tipo_documento.abertura_analitica is
  'Este tipo REAFIRMA aberta uma conta que uma demonstração já declara (o balancete abre o '
  'balanço; o aging abre clientes; o extrato abre bancos). Linha que só aparece em documento '
  'assim NÃO entra na soma do realizado: somá-la conta a mesma conta duas vezes. `false` é o '
  'padrão seguro — o tipo novo entra somando, e quem o cadastra decide.';

update taxonomia_tipo_documento set abertura_analitica = true
where codigo in ('BALANCETE', 'AGING_AR', 'AGING_AP', 'ESTOQUE', 'EXTRATO_BANCARIO',
                 'RAZAO', 'APLIC_FINANC', 'DEBITOS_TRIB', 'HEADCOUNT', 'SPED', 'COMBINADO');

-- -----------------------------------------------------------------------------
-- 3. AS LINHAS DO REALIZADO — por exercício, de uma entidade, sem dupla contagem
-- -----------------------------------------------------------------------------
--
-- Uma linha por (seção, rótulo, exercício). O que ela filtra, e cada filtro é
-- uma das causas acima:
--
--   • só a versão VIGENTE de cada documento (a mesma regra da 0102);
--   • só coluna que nomeia exercício (item 1);
--   • só documento de DEMONSTRAÇÃO (item 2);
--   • só a entidade pedida, quando pedida (item 3) — e a entidade da linha é a
--     COLUNA quando o documento tem várias empresas lado a lado, com a capa como
--     fallback só quando o documento é de uma empresa só (a regra da 0146);
--   • e o TOTAL que soma com as próprias componentes sai marcado `subtotal`
--     (item 4, abaixo), para quem somar não somar os dois.
create or replace function fn_linhas_do_realizado(p_caso_id uuid, p_entidade text default null)
returns table(
  secao_canonica text,
  rotulo_norm text,
  chave text,
  entidade text,
  exercicio integer,
  valor numeric,
  papel text,
  documentos text[]
)
language sql stable
as $$
  -- marca-0150
  --
  -- A MARCA FICA, e o motivo é o mesmo da 0102: a sonda de instalação confere se
  -- a correção está APLICADA NO BANCO procurando `0150` no corpo desta função —
  -- é o que separa "mergeado" de "aplicado". Uma reemissão futura mantém a
  -- marca; trocá-la apagaria a resposta da pergunta que ela faz.
  with bruto as (
    select
      ce.secao_canonica,
      ce.chave,
      fn_normalizar_texto(ce.chave) as rotulo_norm,
      -- 0146: a capa só responde quando o documento é de UMA empresa.
      coalesce(ce.entidade_coluna,
               case when (select count(distinct ce2.entidade_coluna)
                            from campo_extraido ce2
                           where ce2.documento_versao_id = ce.documento_versao_id
                             and ce2.entidade_coluna is not null) > 1
                    then null else e.razao_social end) as entidade,
      fn_exercicio_da_coluna(ce.periodo_coluna) as exercicio,
      ce.valor_num,
      ce.unidade,
      d.tipo_taxonomia,
      dv.documento_id
    from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
    left join entidade e on e.id = d.entidade_id
    left join taxonomia_tipo_documento t on t.codigo = d.tipo_taxonomia
    where d.caso_id = p_caso_id
      and ce.valor_num is not null
      and dv.id = fn_versao_com_extracao(d.id)
      -- A ABERTURA ANALÍTICA NÃO SOMA. Tipo desconhecido (fora do catálogo)
      -- entra somando: o padrão seguro é o de sempre, e o catálogo é quem
      -- declara a exceção.
      and coalesce(t.abertura_analitica, false) = false
      and fn_exercicio_da_coluna(ce.periodo_coluna) is not null
  ),
  filtrado as (
    select * from bruto
    where p_entidade is null
       or fn_normalizar_texto(entidade) = fn_normalizar_texto(p_entidade)
  ),
  papel_do_rotulo as (
    select distinct chave, tipo_taxonomia, unidade,
           fn_papel_linha(chave, tipo_taxonomia, unidade) as papel
    from (select distinct chave, tipo_taxonomia, unidade from filtrado) d
  ),
  com_papel as (
    select f.*, p.papel
    from filtrado f
    join papel_do_rotulo p
      on p.chave = f.chave
     and p.tipo_taxonomia is not distinct from f.tipo_taxonomia
     and p.unidade is not distinct from f.unidade
  ),
  agrupado as (
    select
      c.secao_canonica,
      c.rotulo_norm,
      (array_agg(c.chave order by length(c.chave)))[1] as chave,
      max(c.entidade) as entidade,
      c.exercicio,
      -- Dentro do MESMO exercício, a mesma conta pode vir de dois documentos
      -- (o balanço e a DF auditada dizem a mesma coisa). O de maior módulo é o
      -- desempate da 0042, e continua valendo — aqui ele escolhe entre cópias
      -- do mesmo fato, não entre anos diferentes.
      (array_agg(c.valor_num order by abs(c.valor_num) desc nulls last))[1] as valor,
      (array_agg(c.papel order by fn_papel_prioridade(c.papel)))[1] as papel,
      array_agg(distinct c.tipo_taxonomia) as documentos,
      -- Quantos documentos DISTINTOS trouxeram esta linha neste exercício: é o
      -- que o item 4 usa para saber se o total veio acompanhado das componentes.
      array_agg(distinct c.documento_id) as docs_ids
    from com_papel c
    group by c.secao_canonica, c.rotulo_norm, c.exercicio
  ),
  -- ---------------------------------------------------------------------------
  -- 4. O TOTAL QUE VEIO COM AS COMPONENTES É SUBTOTAL, MESMO SEM ESTAR NA LISTA
  -- ---------------------------------------------------------------------------
  --
  -- A `0116` deixou o topo da DRE fora da lista fechada de subtotais porque num
  -- documento RESUMIDO ele é a conta. O discriminador que faltava é estrutural e
  -- só existe olhando o documento inteiro: se o módulo desta linha bate com a
  -- SOMA das outras contas da mesma seção, mesmo exercício e mesma entidade, ela
  -- é o total delas — e somar os dois conta duas vezes.
  --
  -- A tolerância é de 1% e existe porque a soma de valores arredondados ao
  -- milhar não fecha ao centavo: medido no Canastra, 177.077 contra 177.133
  -- (0,03%). Sem folga, o discriminador não dispararia exatamente no caso que o
  -- motivou.
  soma_das_contas as (
    select a.secao_canonica, a.exercicio, a.entidade,
           sum(abs(a.valor)) filter (where a.papel = 'conta') as total_contas
    from agrupado a
    group by a.secao_canonica, a.exercicio, a.entidade
  )
  select
    a.secao_canonica,
    a.rotulo_norm,
    a.chave,
    a.entidade,
    a.exercicio,
    a.valor,
    case
      when a.papel = 'conta'
       and s.total_contas is not null
       and abs(a.valor) > 0
       -- `2 × |valor|` porque o próprio valor está DENTRO de `total_contas`:
       -- o total mais as componentes dá duas vezes o total. É a mesma
       -- aritmética que a 0143 usa para declarar hierarquia achatada.
       and abs(s.total_contas - 2 * abs(a.valor)) <= 0.01 * abs(a.valor)
      then 'subtotal'
      else a.papel
    end as papel,
    a.documentos
  from agrupado a
  left join soma_das_contas s
    on s.secao_canonica is not distinct from a.secao_canonica
   and s.exercicio = a.exercicio
   and s.entidade is not distinct from a.entidade
$$;

comment on function fn_linhas_do_realizado(uuid, text) is
  'As linhas do caso POR EXERCÍCIO, de uma entidade, sem o que não se soma (0150): fora a '
  'abertura analítica (balancete, aging, estoque, extrato — elas reabrem contas que a '
  'demonstração já declara), fora o combinado (soma das empresas), fora a coluna que não nomeia '
  'exercício, e com o total que veio acompanhado das próprias componentes marcado `subtotal`. '
  'É a base das premissas do realizado e da média histórica; a LISTA da tela continua saindo de '
  'fn_linhas_para_modelagem, que agrupa por rótulo e não por exercício.';

grant execute on function fn_exercicio_da_coluna(text) to authenticated;
grant execute on function fn_linhas_do_realizado(uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- O CATÁLOGO DE INSTALAÇÃO
-- -----------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('realizado_exercicio_da_coluna', '0150', 'funcao', 'fn_exercicio_da_coluna', null, null,
   'Sem ela não há série histórica: a média das premissas passa a sair de um exercício só — e o '
   'exercício de uma empresa em reestruturação é o pior ano dela.',
   'importante', 450),
  ('realizado_sem_dupla_contagem', '0150', 'corpo', 'fn_linhas_do_realizado', '0150', null,
   'As oito premissas do realizado voltam a somar o que não se soma: o total da DRE com as '
   'próprias componentes, o aging de recebíveis por cima da conta de clientes, e as oito empresas '
   'do grupo num modelo que projeta uma. Medido no Canastra: PMR de 348 dias e custo variável de '
   '287% da receita, gravados como premissa.',
   'bloqueante', 460),
  ('realizado_abertura_declarada', '0150', 'coluna', 'taxonomia_tipo_documento.abertura_analitica',
   null, null,
   'Sem a coluna, o produto não tem como distinguir a demonstração da abertura dela, e a soma do '
   'realizado volta a contar duas vezes toda conta que tenha um relatório analítico junto.',
   'importante', 470)
on conflict (chave) do update
  set migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
      marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
      porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0150',
       revisado_em = date '2026-08-27',
       observacao = 'Revisão de 27/08/2026: a 0150 conserta a soma do realizado, que gravava '
                    'PMR de 348 dias e custo variável de 287% da receita como premissa. Três '
                    'requisitos novos: o exercício da coluna, o corpo da soma sem dupla '
                    'contagem, e a coluna que declara qual documento é abertura analítica.'
 where id;

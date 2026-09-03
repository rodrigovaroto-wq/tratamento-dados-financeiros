-- =============================================================================
-- 0158 — O "PRONTO" DA MODELAGEM AFIRMAVA PARÂMETROS, NÃO COBERTURA
--
-- O DEFEITO, medido contra um caso real (Grupo Vertentes) com parâmetros
-- definidos, 6 premissas ativas com valor e vínculo em lote de 5 seções:
--
--     "pronto": true,
--     "linhas_do_caso": 480,
--     "linhas_com_premissa": 23,
--     "linhas_sem_premissa": 457
--
-- 23 DE 480 LINHAS PROJETAM, E O VEREDITO DIZ "pronto". O portal lê essa chave
-- e pinta um chip VERDE "pronto para exportar"
-- (`portal/src/app/casos/[id]/modelagem/page.tsx:402`, fora do escopo desta
-- migration — é o portal quem decide como exibir, não o banco). O analista lê
-- "pronto", exporta, e recebe um arquivo que abre normalmente com 95% das
-- contas sem projeção nenhuma. `linhas_sem_premissa` já vinha do lado, mas um
-- booleano ao lado de um número que ninguém é obrigado a olhar é exatamente a
-- forma da regra 1 do CLAUDE.md: ausência apresentada como dado.
--
-- O CORPO VIGENTE (0134), lido de `pg_proc` e não do que uma sessão anterior
-- possa ter resumido, já tinha avançado da versão mais ingênua
-- (`'pronto', param is not null`, que seria a 0101/0038): desde a 0134,
-- `pronto` exige `parametros is not null AND premissas_ativas > 0 AND
-- premissas_sem_valor = []`. Isso barra o caso sem NENHUMA premissa ativa e o
-- caso com premissa ativa e valor vazio — mas não pergunta, em momento algum,
-- se alguma LINHA REAL do caso foi de fato vinculada a alguma dessas
-- premissas. Um caso com 6 premissas ativas, todas com valor, e ZERO vínculo
-- real (só vínculos órfãos, ou nenhum vínculo) já passava antes desta
-- migration — e um caso com 23 vínculos reais em 480 linhas projetáveis
-- passa pela MESMA porta, porque a porta não conta vínculo nenhum.
--
-- A CORREÇÃO tem duas partes deliberadamente separadas — uma estende o
-- BOOLEANO, a outra publica o NÚMERO — porque são duas perguntas diferentes:
--
--   (1) "pronto" ganha UMA condição nova: `linhas_com_premissa > 0`. O caso
--       ruim que ela mata é o mais nítido — zero linha real vinculada — e
--       nada além disso: ver abaixo por que as outras duas condições
--       cogitadas NÃO entram.
--
--   (2) O retorno ganha `fracao_linhas_com_premissa`: a fração de linhas
--       PROJETÁVEIS (papel='conta') que têm premissa, para o chip poder
--       dizer "23 de 480 (4,8%)" em vez de um "pronto" plano. Ficar em 23/480
--       depois desta migration continua tecnicamente "pronto" (as 23 que
--       foram vinculadas estão corretas, com valor, sem órfão) — o número
--       novo é o que dá ao portal (fatia própria, não tocada aqui) o material
--       para deixar de tratar 4,8% de cobertura como sinônimo de "completo".
--       Transformar isso num bloqueio binário exigiria um LIMIAR de cobertura
--       que ninguém mediu e que este arquivo não inventa — decisão do dono,
--       não do banco.
--
-- O DENOMINADOR da fração é `linhas_do_caso`, sem cálculo novo — e a
-- armadilha aqui era justamente ACREDITAR no nome da chave. `linhas_do_caso`
-- SOA como "todas as linhas do caso", mas o corpo (0101/0134) já a define
-- como `count(*) from contas`, e `contas` já filtra `papel = 'conta'` — os
-- `subtotal`/`serie_mensal`/`derivado` são contados à parte, em
-- `linhas_nao_projetaveis`, desde a 0042. Escrever a fração sobre
-- `count(*) from linhas` (todos os papéis) em vez de `linhas_do_caso` teria
-- sido o MESMO defeito da regra 1 uma casa adiante: infra-representar a
-- cobertura real ao inflar o denominador com linha que nunca poderia ter
-- premissa. `linhas_do_caso` já é o denominador honesto — a correção é usá-lo,
-- não inventar outro.
--
-- POR QUE `vinculos_orfaos` E `sazonalidade_sem_curva` NÃO ENTRAM NO
-- BOOLEANO, embora uma leitura razoável do defeito sugerisse as duas —
-- e as duas foram cogitadas antes deste arquivo:
--
--   `sazonalidade_sem_curva` é a 0134 declarando, por escrito e com teste
--   (`Supabase/test/sazonalidade_pronto.test.sql`, assert do bloco 4), que
--   curva mensal ativa sem documento mensal INFORMA e NÃO BLOQUEIA: o valor
--   ANUAL da linha continua certo, só o rateio dentro do ano fica liso.
--   Bloquear aqui reabriria exatamente o defeito que a 0134 existe para
--   fechar — o portão cobrando uma ação que não existe (a curva não se
--   digita, vem do documento) — e o teste já medido reprovaria: a REVERSÃO de
--   uma correção anterior não é o preço certo para esta.
--
--   `vinculos_orfaos` é config apontando para um rótulo que não existe MAIS
--   no caso corrente (documento reextraído, rótulo mudou, ou o analista digitou
--   antes do documento chegar — `Supabase/test/premissas.test.sql`, bloco 8,
--   mede exatamente esse caso: "Receita de hospedagem" configurada antes de
--   qualquer documento existir). O vínculo órfão não faz NENHUMA linha
--   projetar errado — ele não projeta nada, porque não há linha do lado de
--   cá. É ruído de configuração, não um número errado no book. Tratá-lo como
--   bloqueante trocaria "avisar sobre lixo inofensivo" por "travar o export
--   por causa de lixo inofensivo", e o `Supabase/test/premissas.test.sql`
--   (bloco 8) já teria de mudar para deixar de afirmar `pronto = true` com o
--   órfão presente — mudança que este arquivo não tem base medida para pedir.
--
--   As duas continuam INFORMANDO — já eram publicadas antes desta migration
--   e continuam sendo — só não bloqueiam. É o mesmo desenho que a própria
--   0134 já usa para `sazonalidade_sem_curva`: existe uma diferença real
--   entre "isto está ERRADO" (bloqueia) e "isto está PIOR do que podia estar,
--   mas não muda o resultado" (informa).
--
-- A SONDA segue o achado D da revisão da 0157: um requisito de `corpo` só
-- prova que um TRECHO aparece publicado, e um `false and (predicado)`
-- preserva o trecho como substring — não pega nada. A decisão em si
-- (`linhas_com_premissa > 0`, ao lado das duas condições da 0134) sai do
-- corpo de `fn_conferir_modelagem` para uma função PURA,
-- `fn_modelagem_esta_pronta`, exercitável por literais — sem fixture de
-- documento — e a sonda a EXECUTA contra cinco combinações fixas, no modelo
-- de `instalacao_sonda_combinado_estrutural`.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- fn_modelagem_esta_pronta — a DECISÃO isolada, em função PURA, para poder ser
-- medida por literais. As quatro condições, na ordem em que aparecem:
--   (a) e (b) e (c) já existiam dentro do corpo desde a 0134;
--   (d) é o acréscimo desta migration — nasce aqui e só aqui.
-- -----------------------------------------------------------------------------
create or replace function fn_modelagem_esta_pronta(
  p_parametros_definidos boolean,
  p_premissas_ativas bigint,
  p_premissas_sem_valor integer,
  p_linhas_com_premissa bigint
) returns boolean
language sql
immutable
as $$
  select
    -- (a) 0134: sem parâmetro de modelagem não há o que exportar.
    coalesce(p_parametros_definidos, false)
    -- (b) 0134: nenhuma premissa ativa é caso ainda não começado.
    and coalesce(p_premissas_ativas, 0) > 0
    -- (c) 0134: premissa ativa sem valor projetaria com zero, calado.
    and coalesce(p_premissas_sem_valor, 0) = 0
    -- (d) 0158: e pelo menos UMA linha real do caso precisa estar, de fato,
    -- vinculada a alguma dessas premissas — sem isso, (a)+(b)+(c) valem com
    -- zero linha projetando e o "pronto" afirmava só que os parâmetros
    -- existem, não que algo foi coberto.
    and coalesce(p_linhas_com_premissa, 0) > 0;
$$;

comment on function fn_modelagem_esta_pronta(boolean, bigint, integer, bigint) is
  '(0158) A decisão de "pronto" da Modelagem, isolada em função PURA para poder ser exercitada por '
  'literais (instalacao_sonda_modelagem_pronta), sem fixture de documento nem de caso. As três '
  'primeiras condições são da 0134 (parâmetros definidos, premissa ativa, nenhuma sem valor); a '
  'quarta (linhas_com_premissa > 0) é da 0158 — sem ela um caso com premissas configuradas e ZERO '
  'linha de fato vinculada (ou uma fração ínfima, como 23 de 480 medido no Grupo Vertentes) '
  'respondia "pronto" só porque os parâmetros existiam. Ela NÃO cobra fração mínima de cobertura: '
  'isso é limiar de negócio que ninguém mediu, e o número vai em '
  'fracao_linhas_com_premissa para o portal decidir como exibir. Também NÃO cobra '
  'vinculos_orfaos nem sazonalidade_sem_curva vazios — os dois continuam INFORMANDO no retorno de '
  'fn_conferir_modelagem, por desenho: nenhum dos dois torna um número do book ERRADO (o órfão não '
  'projeta nada porque não há linha do lado de cá; a curva sem documento mensal deixa o valor '
  'ANUAL certo, só lisa o rateio mensal — ver o cabeçalho da 0134).';

grant execute on function fn_modelagem_esta_pronta(boolean, bigint, integer, bigint) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_conferir_modelagem — reemitida a partir do corpo vigente (0134). Diff
-- aditivo: a única linha REMOVIDA é a definição antiga de `pronto`
-- (substituída pela chamada à função pura), e o resto do corpo é idêntico —
-- inclusive os comentários da 0134, que continuam valendo para as três
-- primeiras condições.
-- -----------------------------------------------------------------------------
create or replace function fn_conferir_modelagem(p_caso_id uuid)
returns jsonb
language sql
stable
as $$
  with linhas as (
    select * from fn_linhas_para_modelagem(p_caso_id)
  ),
  contas as (
    select rotulo_norm from linhas where papel = 'conta'
  ),
  vinculadas as (
    select distinct l.rotulo_norm
    from caso_linha_premissa l
    where l.caso_id = p_caso_id and l.premissa_codigo is not null
      and l.rotulo_norm in (select rotulo_norm from contas)
  ),
  orfaos as (
    select distinct l.rotulo_norm
    from caso_linha_premissa l
    where l.caso_id = p_caso_id and l.premissa_codigo is not null
      and l.rotulo_norm not in (select rotulo_norm from linhas)
  ),
  nao_projetaveis as (
    select jsonb_object_agg(papel, n) as j
    from (select papel, count(*) as n from linhas where papel <> 'conta' group by papel) x
  ),
  -- 0134: a premissa ativa, com a FÓRMULA dela ao lado. É a fórmula que decide
  -- se `valores` vazio é defeito ou é o estado normal — não o código, que
  -- envelheceria a cada premissa nova.
  ativas as (
    select cp.premissa_codigo, cp.valores, pc.formula
    from caso_premissa cp
    join premissa_catalogo pc on pc.codigo = cp.premissa_codigo
    where cp.caso_id = p_caso_id and cp.ativo
  ),
  premissas as (
    select count(*) as ativas,
           array_agg(premissa_codigo order by premissa_codigo)
             filter (where formula <> 'curva_mensal'
                       and (valores is null or valores = '{}'::jsonb)) as sem_valor,
           -- O caso ruim DE VERDADE: curva mensal ativa e o caso sem documento
           -- mensal de onde derivá-la. As linhas vinculadas ficam com rateio
           -- liso, e isso precisa ser DITO — não bloqueia, porque o anual
           -- continua certo.
           array_agg(premissa_codigo order by premissa_codigo)
             filter (where formula = 'curva_mensal'
                       and not exists (select 1 from fn_sazonalidade_do_caso(p_caso_id)))
             as saz_sem_curva
    from ativas
  ),
  param as (
    select to_jsonb(m) as j from caso_modelagem m where m.caso_id = p_caso_id
  )
  select jsonb_build_object(
    'parametros', (select j from param),
    'premissas_ativas', (select ativas from premissas),
    'premissas_sem_valor', to_jsonb(coalesce((select sem_valor from premissas), array[]::text[])),
    -- 0134: informação, não bloqueio. Ver o cabeçalho.
    'sazonalidade_sem_curva',
      to_jsonb(coalesce((select saz_sem_curva from premissas), array[]::text[])),
    'linhas_do_caso', (select count(*) from contas),
    'linhas_nao_projetaveis', coalesce((select j from nao_projetaveis), '{}'::jsonb),
    'linhas_com_premissa', (select count(*) from vinculadas),
    'linhas_sem_premissa', greatest((select count(*) from contas) - (select count(*) from vinculadas), 0),
    'vinculos_orfaos', to_jsonb(coalesce(
      (select array_agg(rotulo_norm order by rotulo_norm) from orfaos), array[]::text[])),
    -- 0158: a fração de linhas PROJETÁVEIS (papel='conta') que têm premissa —
    -- mesmo denominador de `linhas_do_caso` (já exclui subtotal/serie_mensal/
    -- derivado, contados à parte em `linhas_nao_projetaveis`). NULL, não
    -- zero, quando o caso não tem linha projetável nenhuma: zero coberto de
    -- zero possível não é a mesma coisa que zero coberto de 480 possíveis, e
    -- fabricar um dos dois números pela ausência do outro é a regra 1.
    'fracao_linhas_com_premissa',
      case when (select count(*) from contas) > 0
        then round((select count(*) from vinculadas)::numeric
                    / (select count(*) from contas), 4)
        else null
      end,
    'pronto', fn_modelagem_esta_pronta(
      (select j from param) is not null,
      (select ativas from premissas),
      coalesce(array_length((select sem_valor from premissas), 1), 0),
      (select count(*) from vinculadas))
  );
$$;

comment on function fn_conferir_modelagem(uuid) is
  'Diagnóstico da Modelagem de um caso. Desde a 0134, premissa de `curva_mensal` (SAZONALIDADE, '
  'CRONOGRAMA_FISICO, PARADA_MANUTENCAO) NÃO conta como "sem valor": a curva dela é derivada do '
  'documento mensal por fn_sazonalidade_do_caso, não digitada, e cobrá-la travava o "pronto" com '
  'uma pendência sem ação possível. O caso ruim de verdade — curva ativa e caso sem documento '
  'mensal — ganhou nome próprio em `sazonalidade_sem_curva`, que informa e não bloqueia, porque os '
  'números ANUAIS continuam certos e só o rateio mensal fica liso. Desde a 0158, `pronto` '
  '(fn_modelagem_esta_pronta) também exige que ALGUMA linha real esteja vinculada — parâmetros '
  'definidos e premissas com valor não bastam quando zero linha do caso foi de fato coberta, ou '
  'quando a cobertura é uma fração ínfima do total (medido: 23 de 480, Grupo Vertentes) — e o '
  'retorno ganha `fracao_linhas_com_premissa` para o portal poder mostrar QUANTO, não só '
  '"pronto"/"não pronto". `vinculos_orfaos` e `sazonalidade_sem_curva` continuam informando e não '
  'bloqueando: nenhum dos dois deixa um número do book errado.';

grant execute on function fn_conferir_modelagem(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- A SONDA DE INSTALAÇÃO — a view abaixo EXECUTA fn_modelagem_esta_pronta com
-- literais fixos, no modelo de instalacao_sonda_combinado_estrutural (0157,
-- achado D): um requisito de corpo/função só prova que um TRECHO existe
-- publicado, e um `false and (predicado)` preserva esse trecho como
-- substring sem preservar o comportamento. Só devolve 1 linha quando as
-- cinco combinações abaixo — o positivo e as quatro negações, uma por
-- condição — casam TODAS com o esperado ao mesmo tempo.
-- -----------------------------------------------------------------------------
create or replace view instalacao_sonda_modelagem_pronta as
select 1 as ok
where
  -- positivo: parâmetros definidos, premissas ativas com valor, e alguma
  -- linha de fato coberta — inclusive no caso MEDIDO (23 de 480: continua
  -- "pronto" porque as 23 vinculadas estão corretas; a fração informa o
  -- resto, não bloqueia sozinha).
  fn_modelagem_esta_pronta(true, 6, 0, 23) = true
  -- sem parâmetro de modelagem, não há "pronto" possível.
  and fn_modelagem_esta_pronta(false, 6, 0, 23) = false
  -- nenhuma premissa ativa: caso ainda não começado.
  and fn_modelagem_esta_pronta(true, 0, 0, 23) = false
  -- premissa ativa sem valor: projetaria com zero, calado.
  and fn_modelagem_esta_pronta(true, 6, 1, 23) = false
  -- 0158: zero linha real vinculada — o caso que o corpo vigente (0134,
  -- sozinho) deixava passar como "pronto".
  and fn_modelagem_esta_pronta(true, 6, 0, 0) = false;

comment on view instalacao_sonda_modelagem_pronta is
  '(0158) Autoteste da decisão de fn_modelagem_esta_pronta, EXECUTADA por literais (função pura, '
  'sem fixture de caso nem documento): 1 linha só se o positivo e as quatro negações — sem '
  'parâmetro, sem premissa ativa, premissa sem valor, e ZERO linha vinculada — valem todas ao '
  'mesmo tempo. Um marcador textual de corpo/função não pega um "false and" que mate o predicado '
  'e deixe os comentários intactos; esta view pega, porque o predicado É executado (achado D da '
  'revisão da 0157).';

grant select on instalacao_sonda_modelagem_pronta to authenticated;

-- -----------------------------------------------------------------------------
-- A SONDA — o catálogo
-- -----------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('modelagem_pronto_exige_cobertura', '0158', 'corpo', 'fn_conferir_modelagem',
   'fn_modelagem_esta_pronta', null,
   'O chip "pronto para exportar" da tela de Modelagem acendia verde com parâmetros definidos e '
   'premissas com valor, mesmo com ZERO linha do caso de fato vinculada, ou com uma fração ínfima '
   'coberta — medido em produção (Grupo Vertentes): 23 de 480 linhas com premissa, `pronto = true`. '
   'O analista exporta achando o modelo completo e recebe um book com 95% das contas sem projeção. '
   'Este requisito prova só a FIAÇÃO (a conferência chama a decisão nova); a decisão em si é o '
   'requisito modelagem_pronta_regra_viva.',
   'bloqueante', 610),
  ('fn_modelagem_esta_pronta', '0158', 'funcao', 'fn_modelagem_esta_pronta', null, null,
   'Sem ela a decisão de "pronto" volta a estar espalhada dentro do corpo de fn_conferir_modelagem, '
   'sem poder ser exercitada por literal — e o achado D da revisão da 0157 já mediu que um '
   'marcador textual sozinho não distingue predicado vivo de predicado morto.',
   'importante', 615),
  ('modelagem_pronta_regra_viva', '0158', 'seed', 'instalacao_sonda_modelagem_pronta', null, 1,
   'A regra de quando a Modelagem está pronta pode existir como código morto: um requisito de '
   '"corpo" ou "função" prova só que o texto está no arquivo, não que o predicado decide certo. '
   'Esta linha executa a decisão contra cinco combinações fixas; ausente aqui quer dizer que um '
   'caso com zero linha vinculada, ou com premissa ativa sem valor, pode voltar a responder '
   '"pronto" — e o chip volta a mentir em silêncio.',
   'bloqueante', 616),
  ('modelagem_publica_fracao_de_cobertura', '0158', 'corpo', 'fn_conferir_modelagem',
   'fracao_linhas_com_premissa', null,
   'Sem este campo o portal não tem como mostrar QUANTO da Modelagem está coberto — só um '
   'booleano que, por desenho, não bloqueia por fração baixa (o limiar é decisão do dono, não do '
   'banco). Sua ausência devolve o defeito original pela porta de trás: 23 de 480 volta a ter a '
   'mesma aparência de 480 de 480.',
   'importante', 617)
on conflict (chave) do update
  set migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
      marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
      porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0158',
       revisado_em = date '2026-09-03',
       observacao = 'Revisão de 03/09/2026: a 0158 fecha a lacuna que a 0134 deixou aberta — '
                    '"pronto" exigia parâmetros e premissas com valor, mas nunca perguntava se '
                    'alguma linha real do caso tinha sido vinculada. Medido no Grupo Vertentes: '
                    '23 de 480 linhas cobertas, `pronto = true`, chip verde. A decisão foi isolada '
                    'em fn_modelagem_esta_pronta (função pura, no modelo do achado D da 0157) e o '
                    'retorno ganhou fracao_linhas_com_premissa. Quatro requisitos novos.'
 where id;

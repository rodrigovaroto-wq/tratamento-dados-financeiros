-- 0151 — O DESEMPATE ENTRE DOIS DOCUMENTOS DO MESMO PERÍODO JÁ EXISTIA. ELE ERA
-- SILENCIOSO, E ESCOLHIA O MAIOR.
--
-- O handoff da sessão 72 diz, sobre o `book-araucaria`: "o que continua sem
-- resposta é o desempate — não há mecanismo que escolha entre duas versões do
-- mesmo período". A frase está meio certa. Não há mecanismo DECLARADO; há um
-- mecanismo, e ele está numa linha da `0150`:
--
--     (array_agg(c.valor_num order by abs(c.valor_num) desc nulls last))[1]
--
-- com o comentário ao lado: "Dentro do MESMO exercício, a mesma conta pode vir
-- de dois documentos (o balanço e a DF auditada dizem a mesma coisa). O de maior
-- módulo é o desempate da 0042."
--
-- Quando os dois dizem A MESMA COISA, escolher qualquer um é indiferente e a
-- regra não faz mal. Quando eles DISCORDAM — que é a pergunta inteira do
-- araucária — a regra vira: **fica com o maior**. Num caso de reestruturação
-- esse é o pior padrão possível: dos dois números, ele escolhe sempre o que
-- infla o ativo. E a armadilha central do araucária é exatamente essa —
-- um combinado preliminar que infla o ativo do grupo em até 32.800 (R$ mil) E
-- FECHA, porque ativo e passivo caem na mesma medida quando um par intragrupo
-- deixa de ser eliminado. Contra um número que fecha, nenhuma reconciliação
-- existente dispara: `fn_reconciliar_ativo_passivo_pl` confere se bate, e bate.
--
-- Então o defeito não é a ausência de desempate. É um desempate sem critério,
-- sem autor e sem rastro — o analista lê o número no export e não tem como saber
-- que houve escolha, nem que havia outro número.
--
-- O QUE MEDI ANTES DE ESCREVER, na fixture do Canastra (28 documentos, extração
-- real): 117 conceitos aparecem em DOIS OU MAIS documentos, e só CINCO
-- discordam. Os cinco valem mais que qualquer argumento, porque foram eles que
-- desenharam os filtros:
--
--   "total"         EXTRATO_BANCARIO 825.000 × HEADCOUNT 20.510.900
--   "total geral"   AGING_AP 25.734.000 × AGING_AR 28.706.000
--   "total vencido" AGING_AP 13.383.000 × AGING_AR 16.936.000
--   "direito de uso — arrendamentos"  BALANCO 7.822 = BALANCETE 7.822 × NOTAS_EXPL 7.825
--   "veículos e empilhadeiras"        BALANCO 3.914 = BALANCETE 3.914 × NOTAS_EXPL 3.916
--
-- Os TRÊS PRIMEIROS são falsos, e cada um por um motivo diferente que virou
-- filtro: o rótulo é genérico e não tem seção canônica (o "total" de um extrato
-- e o de uma folha não são o mesmo conceito — um está em milhares de reais e o
-- outro em PESSOAS); o papel da linha é `subtotal`, e o total de um documento é
-- do documento, não do grupo; e a unidade nem é comparável.
--
-- OS DOIS ÚLTIMOS SÃO VERDADEIROS e ficam ABAIXO da tolerância (3 mil em 7,8
-- milhões = 0,04%). São o mesmo fenômeno que o araucária traz em escala: a nota
-- explicativa e o balanço discordando em centavos de arredondamento. A
-- tolerância os deixa passar, e é o que ela existe para fazer.
--
-- O RESULTADO NA FIXTURE, DEPOIS DOS FILTROS: **zero conflitos**. É a resposta
-- certa para um book construído para ser internamente consistente — e é também
-- o motivo de o teste desta migration construir um caso próprio com o conflito
-- dentro. Uma checagem que só devolve zero é uma checagem que não se provou.
--
-- O QUE ESTA MIGRATION FAZ, EM TRÊS MOVIMENTOS:
--
--   1. a AUTORIDADE de um tipo de documento passa a ser DADO no catálogo, do
--      mesmo jeito que a `0150` fez com `abertura_analitica` — e pela mesma
--      razão: regra de negócio contábil em lista dentro de função é regra que
--      ninguém acha para mudar;
--   2. o conflito passa a ser DECLARADO, com o vencedor, o perdedor, a
--      diferença e o CRITÉRIO por extenso. Nada é apagado — é a doutrina do
--      repositório desde a 0105, e aqui ela é mais importante que nunca:
--      o número perdedor é a evidência de que houve escolha;
--   3. quando a autoridade NÃO separa os dois, o conflito volta como EMPATE e o
--      valor não muda — continua o da 0042, o de maior módulo. Empate não é
--      motivo para inventar critério novo; é motivo para chamar o humano. Em
--      particular NÃO desempato por "mais recente": `criado_em` é a hora do
--      UPLOAD, não a data do documento, e desempatar por ordem de upload seria
--      trocar uma regra silenciosa por outra.

-- -----------------------------------------------------------------------------
-- 1. A AUTORIDADE É DADO DO CATÁLOGO
-- -----------------------------------------------------------------------------
--
-- A escala é de intervalos largos, de propósito: os sinais do documento (item 2)
-- somam e subtraem dentro dela, e com degraus de 10 um sinal nunca atravessa
-- dois níveis por acidente.
--
-- A ORDEM, e o porquê de cada degrau — é doutrina contábil, não preferência:
--
--   60  DF_AUDITADA ....... passou por terceiro independente, com parecer. É o
--                           documento que o comitê aceita sem perguntar.
--   50  BALANCO, DRE, ..... a demonstração FECHADA da própria entidade: os
--       FLUXO_CAIXA,        ajustes de encerramento já estão nela.
--       DMPL, DVA
--   40  NOTAS_EXPL ........ acompanha a demonstração e detalha o que ela
--                           resume. Onde os dois trazem o MESMO número e
--                           discordam, a face da demonstração é a que amarra o
--                           conjunto — foi ela que teve de fechar. (Medido no
--                           Canastra: a nota diz 7.825 onde o balanço diz 7.822.)
--   30  COMBINADO ......... DERIVADO: é a soma das empresas menos as
--                           eliminações, e a eliminação é julgamento de quem
--                           montou. A `0150` já o tira da soma do realizado pelo
--                           mesmo motivo. Aqui ele perde a disputa contra as
--                           peças que o formam — que é a armadilha do araucária.
--   20  BALANCETE ......... razão sintético PRÉ-fechamento: legítimo, e ainda
--                           sem os ajustes de encerramento.
--   10  RAZAO ............. lançamento a lançamento, sem fechamento nenhum.
--    0  todo o resto ...... o catálogo não declarou autoridade para este tipo.
--
-- ZERO NÃO É "PERDE SEMPRE" NEM "GANHA SEMPRE": é "não decide". Dois zeros
-- empatam e vão para o humano. Um zero contra um declarado perde — e isso é
-- deliberado: a declaração no catálogo É a evidência, e um tipo que ninguém
-- classificou não deveria calar um balanço.
alter table taxonomia_tipo_documento
  add column if not exists autoridade smallint not null default 0;

comment on column taxonomia_tipo_documento.autoridade is
  'Peso da EVIDÊNCIA deste tipo de documento quando dois documentos do mesmo período discordam '
  'sobre a mesma conta (0151). Maior vence, e o motivo vai por extenso na pendência. 0 = o '
  'catálogo não declarou autoridade para este tipo: ele não decide (dois zeros empatam e a '
  'decisão volta para o humano). Nada é apagado em nenhum caso — o perdedor é a evidência de que '
  'houve escolha.';

update taxonomia_tipo_documento set autoridade = 60 where codigo in ('DF_AUDITADA');
update taxonomia_tipo_documento set autoridade = 50
 where codigo in ('BALANCO', 'DRE', 'FLUXO_CAIXA', 'DMPL', 'DVA');
update taxonomia_tipo_documento set autoridade = 40 where codigo in ('NOTAS_EXPL');
update taxonomia_tipo_documento set autoridade = 30 where codigo in ('COMBINADO');
update taxonomia_tipo_documento set autoridade = 20 where codigo in ('BALANCETE');
update taxonomia_tipo_documento set autoridade = 10 where codigo in ('RAZAO');

-- -----------------------------------------------------------------------------
-- 2. O SINAL QUE O PRÓPRIO DOCUMENTO DÁ
-- -----------------------------------------------------------------------------
--
-- O tipo diz o que o documento É; estes dois dizem em que ESTADO ele chegou. Os
-- dois só existem porque a armadilha do araucária não é "um combinado" — é um
-- combinado PRELIMINAR, e a palavra está no nome do arquivo.
--
-- POR QUE SÓ O NOME DO ARQUIVO, e não o conteúdo: o nome é o que o remetente
-- escreveu de propósito para avisar, é determinístico, e não custa chamada de
-- IA. O conteúdo diria mais e exigiria confiar no modelo para uma decisão que
-- muda número — e a `0148` já ensinou que, quando o texto decide, a evidência
-- tem de ser a frase literal, que aqui não temos onde guardar.
--
-- O PESO É ASSIMÉTRICO DE PROPÓSITO: `preliminar` só DERRUBA (−25), `assinado`
-- só LEVANTA (+5), e nenhum dos dois inventa autoridade do nada. Falso positivo
-- de "preliminar" rebaixa um documento bom em um degrau e meio — ele ainda ganha
-- de quem está dois degraus abaixo (um balanço preliminar, 25, continua vencendo
-- um balancete, 20), e o critério aparece escrito na pendência, onde alguém
-- pode discordar. Falso negativo não muda nada.
create or replace function fn_documento_preliminar(p_nome text)
returns boolean
language sql
immutable
as $$
  -- Os parênteses NÃO são estilo: `~` tem precedência MAIOR que `||`, então sem
  -- eles o Postgres lê `(texto ~ 'primeira metade') || 'segunda metade'` e a
  -- função devolve TEXTO em vez de booleano — casando com meia expressão.
  select fn_normalizar_texto(coalesce(p_nome, '')) ~
    ('(^|[^a-z])(preliminar|preliminary|rascunho|draft|provisori[ao]|minuta|prev[ei]a|wip|'
     || 'nao auditad[ao]|sem auditoria|nao revisad[ao]|para discussao)([^a-z]|$)');
$$;

comment on function fn_documento_preliminar(text) is
  'O nome do arquivo declara que o documento é preliminar/rascunho? Só REBAIXA autoridade (0151), '
  'nunca levanta: falso positivo custa um degrau e meio e fica escrito na pendência; falso '
  'negativo não muda nada.';

create or replace function fn_autoridade_do_documento(p_documento_id uuid)
returns table (autoridade integer, motivo text)
language sql
stable
as $$
  select
    (coalesce(t.autoridade, 0)
     + case when dv.assinado is true then 5 else 0 end
     - case when fn_documento_preliminar(dv.nome_original) then 25 else 0 end)::integer,
    coalesce(t.codigo, 'sem tipo')
      || case when coalesce(t.autoridade, 0) = 0
              then ' (o catálogo não declara autoridade para este tipo)' else '' end
      || case when dv.assinado is true then ', assinado' else '' end
      || case when fn_documento_preliminar(dv.nome_original)
              then ', e o nome do arquivo diz que é preliminar' else '' end
  from documento d
  left join taxonomia_tipo_documento t on t.codigo = d.tipo_taxonomia
  left join documento_versao dv on dv.id = fn_versao_com_extracao(d.id)
  where d.id = p_documento_id;
$$;

comment on function fn_autoridade_do_documento(uuid) is
  'A autoridade documental de UM documento e o motivo por extenso (0151): a do tipo no catálogo, '
  'mais 5 se a versão está assinada, menos 25 se o nome do arquivo declara preliminar. É o que '
  'decide quando dois documentos do mesmo período discordam sobre a mesma conta.';

-- -----------------------------------------------------------------------------
-- 3. OS CONFLITOS DO CASO
-- -----------------------------------------------------------------------------
--
-- Uma linha por PAR de documentos que discordam sobre o mesmo conceito, no mesmo
-- exercício, da mesma entidade. Os filtros são os cinco falsos positivos que a
-- fixture do Canastra devolveu, cada um virado em critério:
--
--   • SEÇÃO CANÔNICA declarada e diferente de NAO_CLASSIFICAVEL — sem conceito
--     contábil comum, "total" e "total" não são a mesma coisa;
--   • PAPEL `conta` — o subtotal de um documento é do documento. Somar ou
--     comparar totais de escopos diferentes é o erro que a 0105 e a 0144 já
--     pagaram duas vezes;
--   • UNIDADE CONVERSÍVEL nos dois lados, e valores comparados NA BASE — foi
--     "pessoas" contra "milhar" que produziu o conflito mais absurdo dos cinco;
--   • TOLERÂNCIA — a mesma convenção das outras reconciliações (o maior entre
--     R$ 100 e 0,5%). É ela que deixa passar os 3 mil em 7,8 milhões entre a
--     nota explicativa e o balanço, que é arredondamento e não discordância;
--   • VERSÃO VIGENTE de cada documento (0102/0118) — senão uma reextração
--     apareceria discordando de si mesma.
--
-- O EXERCÍCIO VEM DA COLUNA, E NA FALTA DELA DO PERÍODO DO DOCUMENTO. A `0150`
-- usa só a coluna, porque para SOMAR é melhor deixar de fora do que somar num
-- ano inventado. Aqui a conta é outra: um documento de período único, sem
-- cabeçalho de ano nas linhas, é justamente o formato em que a segunda versão de
-- um balanço chega — e ignorá-lo esconderia o conflito que esta função existe
-- para achar. `fn_exercicio_da_coluna` continua sendo quem responde, e continua
-- devolvendo nulo (= fora) para "Saldo", "Crédito" e para períodos multi-ano
-- como '23,24,25'.
create or replace function fn_conflitos_do_caso(
  p_caso_id        uuid,
  p_entidade       text    default null,
  p_tolerancia_abs numeric default 100,
  p_tolerancia_pct numeric default 0.005
)
returns table (
  secao_canonica       text,
  chave                text,
  entidade             text,
  exercicio            integer,
  documento_vencedor   uuid,
  tipo_vencedor        text,
  valor_vencedor       numeric,
  documento_perdedor   uuid,
  tipo_perdedor        text,
  valor_perdedor       numeric,
  diferenca            numeric,
  decidido             boolean,
  criterio             text
)
language sql
stable
as $$
  with bruto as (
    select
      ce.secao_canonica,
      fn_normalizar_texto(ce.chave) as rotulo,
      ce.chave,
      -- 0146: a capa só responde quando o documento é de UMA empresa. Num
      -- documento de várias, a linha sem coluna não tem dono e fica de fora —
      -- atribuí-la à capa criaria conflito entre uma empresa e um fantasma.
      coalesce(ce.entidade_coluna,
               case when (select count(distinct ce2.entidade_coluna)
                            from campo_extraido ce2
                           where ce2.documento_versao_id = ce.documento_versao_id
                             and ce2.entidade_coluna is not null) > 1
                    then null else e.razao_social end) as entidade,
      coalesce(fn_exercicio_da_coluna(ce.periodo_coluna),
               fn_exercicio_da_coluna(p.referencia)) as exercicio,
      fn_valor_em_base(ce.valor_num, ce.unidade) as valor,
      d.id as documento_id,
      d.tipo_taxonomia
    from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d         on d.id = dv.documento_id
    left join entidade e     on e.id = d.entidade_id
    left join periodo p      on p.id = d.periodo_id
    where d.caso_id = p_caso_id
      and ce.valor_num is not null
      and dv.id = fn_versao_com_extracao(d.id)
      and ce.secao_canonica is not null
      and ce.secao_canonica <> 'NAO_CLASSIFICAVEL'
      and fn_fator_escala(ce.unidade) is not null
      and fn_papel_linha(ce.chave, d.tipo_taxonomia, ce.unidade) = 'conta'
      and coalesce(fn_exercicio_da_coluna(ce.periodo_coluna),
                   fn_exercicio_da_coluna(p.referencia)) is not null
  ),
  filtrado as (
    select * from bruto b
    where b.entidade is not null
      and (p_entidade is null or fn_mesma_entidade(b.entidade, p_entidade))
  ),
  -- Um valor por (conceito, exercício, entidade, DOCUMENTO). Dentro do mesmo
  -- documento a mesma conta pode aparecer em mais de uma linha (a coluna de
  -- outro exercício, uma repetição de página); o de maior módulo representa o
  -- documento, e é a regra da 0042 usada onde ela é inofensiva — aqui ela
  -- escolhe entre linhas de UMA fonte, não entre fontes que discordam.
  por_documento as (
    select f.secao_canonica, f.rotulo, f.entidade, f.exercicio, f.documento_id,
           max(f.tipo_taxonomia) as tipo,
           (array_agg(f.chave order by length(f.chave)))[1] as chave,
           (array_agg(f.valor order by abs(f.valor) desc nulls last))[1] as valor
    from filtrado f
    group by f.secao_canonica, f.rotulo, f.entidade, f.exercicio, f.documento_id
  ),
  com_autoridade as (
    select pd.*, a.autoridade, a.motivo
    from por_documento pd
    cross join lateral fn_autoridade_do_documento(pd.documento_id) a
  ),
  pares as (
    select
      a.secao_canonica, a.chave, a.entidade, a.exercicio,
      a.documento_id as doc_a, a.tipo as tipo_a, a.valor as valor_a,
      a.autoridade as aut_a, a.motivo as motivo_a,
      b.documento_id as doc_b, b.tipo as tipo_b, b.valor as valor_b,
      b.autoridade as aut_b, b.motivo as motivo_b
    from com_autoridade a
    join com_autoridade b
      on b.secao_canonica = a.secao_canonica
     and b.rotulo         = a.rotulo
     and b.entidade       is not distinct from a.entidade
     and b.exercicio      = a.exercicio
     and b.documento_id   > a.documento_id          -- par sem repetir a ordem
    where abs(a.valor - b.valor)
            > greatest(p_tolerancia_abs, abs(a.valor) * p_tolerancia_pct)
  )
  select
    p.secao_canonica,
    p.chave,
    p.entidade,
    p.exercicio,
    case when p.aut_a >= p.aut_b then p.doc_a   else p.doc_b   end,
    case when p.aut_a >= p.aut_b then p.tipo_a  else p.tipo_b  end,
    case when p.aut_a >= p.aut_b then p.valor_a else p.valor_b end,
    case when p.aut_a >= p.aut_b then p.doc_b   else p.doc_a   end,
    case when p.aut_a >= p.aut_b then p.tipo_b  else p.tipo_a  end,
    case when p.aut_a >= p.aut_b then p.valor_b else p.valor_a end,
    abs(p.valor_a - p.valor_b),
    p.aut_a <> p.aut_b,
    case when p.aut_a <> p.aut_b then
      format('%s vence: %s (autoridade %s) contra %s (autoridade %s)',
             case when p.aut_a > p.aut_b then p.tipo_a else p.tipo_b end,
             case when p.aut_a > p.aut_b then p.motivo_a else p.motivo_b end,
             greatest(p.aut_a, p.aut_b),
             case when p.aut_a > p.aut_b then p.motivo_b else p.motivo_a end,
             least(p.aut_a, p.aut_b))
    else
      format('EMPATE em autoridade %s (%s × %s): a escolha é humana — o valor '
             || 'não foi trocado, continua o de maior módulo',
             p.aut_a, p.motivo_a, p.motivo_b)
    end
  from pares p;
$$;

comment on function fn_conflitos_do_caso(uuid, text, numeric, numeric) is
  'Dois documentos do mesmo período discordando sobre a MESMA conta, com o vencedor por '
  'autoridade documental e o critério por extenso (0151). Compara na base, só entre linhas com '
  'seção canônica, papel conta e unidade conversível — os três filtros vieram dos falsos '
  'positivos medidos na fixture do Canastra. `decidido = false` é empate: ninguém vence e a '
  'decisão é humana.';

-- -----------------------------------------------------------------------------
-- 4. A CHECAGEM, NA FORMA DAS OUTRAS (Classe A)
-- -----------------------------------------------------------------------------
--
-- Por caso/entidade e sem período: o conflito é entre documentos de um mesmo
-- exercício, mas quais exercícios existem é o que a checagem descobre — pedir
-- período por fora faria a tela ter de adivinhar qual perguntar.
--
-- A DIVERGÊNCIA REGISTRADA É O MÁXIMO, NÃO A SOMA. Somar discordâncias de contas
-- que nada têm entre si produz um número que não existe em lugar nenhum; o maior
-- conflito é o que decide se isto é material. (A 0105 soma porque lá o total é
-- literalmente o valor dobrado no patrimônio — outra grandeza.)
create or replace function fn_reconciliar_versoes_do_periodo(
  p_caso_id     uuid,
  p_entidade_id uuid
)
returns jsonb
language plpgsql
as $$
declare
  v_entidade  text;
  v_c         record;
  v_n         int := 0;
  v_empates   int := 0;
  v_maior     numeric := 0;
  v_detalhe   jsonb := '[]'::jsonb;
  v_descricao text;
  v_resultado text;
  v_documento uuid;
begin
  select razao_social into v_entidade from entidade where id = p_entidade_id;

  for v_c in
    select * from fn_conflitos_do_caso(p_caso_id, v_entidade)
    order by diferenca desc
  loop
    v_n := v_n + 1;
    if not v_c.decidido then v_empates := v_empates + 1; end if;
    v_maior := greatest(v_maior, v_c.diferenca);
    v_detalhe := v_detalhe || jsonb_build_array(jsonb_build_object(
      'secao_canonica', v_c.secao_canonica, 'conta', v_c.chave,
      'entidade', v_c.entidade, 'exercicio', v_c.exercicio,
      'vencedor', jsonb_build_object('documento_id', v_c.documento_vencedor,
                                     'tipo', v_c.tipo_vencedor, 'valor', v_c.valor_vencedor),
      'perdedor', jsonb_build_object('documento_id', v_c.documento_perdedor,
                                     'tipo', v_c.tipo_perdedor, 'valor', v_c.valor_perdedor),
      'diferenca', v_c.diferenca, 'decidido', v_c.decidido, 'criterio', v_c.criterio));
  end loop;

  -- O documento de MAIOR diferença ancora o link da tela. O conflito é entre
  -- dois, então não há "o" documento — mas mandar quem lê para o mais material
  -- é melhor que mandar para o mais antigo.
  v_documento := (v_detalhe->0->'perdedor'->>'documento_id')::uuid;
  if v_documento is null then
    select d.id into v_documento
    from documento d
    where d.caso_id = p_caso_id
      and (p_entidade_id is null or d.entidade_id = p_entidade_id)
    order by d.criado_em
    limit 1;
  end if;

  if v_n = 0 then
    v_resultado := 'ok';
    v_descricao := 'Nenhuma conta em que dois documentos do mesmo exercício discordem.';
  else
    v_resultado := 'divergencia';
    v_descricao := format(
      '%s conta(s) em que dois documentos do mesmo exercício discordam (maior diferença: %s). '
      || '%s'
      || 'NADA foi apagado: o número do perdedor continua gravado, e é ele a evidência de que '
      || 'houve escolha. Conflitos: %s',
      v_n, to_char(v_maior, 'FM999G999G999D00'),
      case when v_empates > 0
           then format('%s deles EMPATAM em autoridade documental e ninguém decidiu por você — '
                       || 'o valor em uso continua o de maior módulo, que é o padrão antigo. ',
                       v_empates)
           else '' end,
      (select string_agg(format('%s (%s): %s diz %s, %s diz %s — %s',
                                x->>'conta', x->>'exercicio',
                                x->'vencedor'->>'tipo',
                                to_char((x->'vencedor'->>'valor')::numeric, 'FM999G999G999D00'),
                                x->'perdedor'->>'tipo',
                                to_char((x->'perdedor'->>'valor')::numeric, 'FM999G999G999D00'),
                                x->>'criterio'), '; ')
         from jsonb_array_elements(v_detalhe) x));
  end if;

  return fn_registrar_reconciliacao(
    p_caso_id, p_entidade_id, null, 'conflito_entre_documentos', 'A', v_documento,
    jsonb_build_object('conflitos', v_detalhe), null,
    v_resultado, v_maior, null,
    jsonb_build_object('tolerancia_abs', 100, 'tolerancia_pct', 0.005,
                       'criterio', 'mesma seção canônica, mesmo rótulo, mesmo exercício, mesma '
                                || 'entidade, papel conta, unidade conversível; vencedor por '
                                || 'autoridade documental (taxonomia_tipo_documento.autoridade)',
                       'empates', v_empates),
    v_descricao);
end;
$$;

comment on function fn_reconciliar_versoes_do_periodo(uuid, uuid) is
  'Checagem de reconciliação (0151): duas versões do mesmo período discordando sobre a mesma '
  'conta. Declara o vencedor por autoridade documental e o critério; empate volta para o humano '
  'sem trocar valor nenhum. Por caso/entidade — quais exercícios existem é o que ela descobre.';

grant execute on function fn_documento_preliminar(text) to authenticated;
grant execute on function fn_autoridade_do_documento(uuid) to authenticated;
grant execute on function fn_conflitos_do_caso(uuid, text, numeric, numeric) to authenticated;
grant execute on function fn_reconciliar_versoes_do_periodo(uuid, uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 5. A CHECAGEM ENTRA NA RODADA
-- -----------------------------------------------------------------------------
--
-- OS TIPOS QUE DISPARAM são os que trazem conta com seção canônica e discordam
-- entre si: as demonstrações, o combinado, o balancete, a DF auditada e a nota
-- explicativa. Aging, extrato, estoque e razão NÃO disparam — não porque não
-- possam conflitar, mas porque foram exatamente eles que produziram os três
-- falsos positivos medidos na fixture, e a função já os barra por seção e papel;
-- fazê-los DISPARAR só gastaria uma passada por documento para registrar `ok`.
-- Eles continuam sendo LIDOS quando outro documento dispara a checagem.
--
-- O resto do corpo é o da 0133, inalterado.
create or replace function fn_reconciliar_por_documento(p_documento_id uuid)
returns jsonb language plpgsql as $$
declare
  v_caso_id     uuid;
  v_entidade_id uuid;
  v_periodo_id  uuid;
  v_tipo        text;
  v_checagens   jsonb := '[]'::jsonb;
  v_periodos    uuid[];
  v_per         uuid;
  v_res         jsonb;

begin
  select caso_id, entidade_id, periodo_id, tipo_taxonomia
    into v_caso_id, v_entidade_id, v_periodo_id, v_tipo
  from documento where id = p_documento_id;

  if v_caso_id is null then
    return jsonb_build_object('executado', false, 'motivo', 'documento não encontrado');
  end if;

  -- 0133: a conferência INTRA-documento vem PRIMEIRO. Se as seções do próprio
  -- documento não fecham, as comparações entre documentos abaixo estão sendo
  -- feitas sobre números que já não se sustentam — e é melhor que a fila diga
  -- isso antes de dizer que o Ativo bate com o Passivo (que, com totais
  -- impressos dos dois lados, bate mesmo quando faltam contas no meio).
  --
  -- Sem loop de período: a árvore é INTRA-documento, então o período do
  -- documento é o único que existe aqui — não há documento par a procurar.
  if v_tipo in ('BALANCO', 'BALANCETE', 'COMBINADO') then
    v_checagens := v_checagens || jsonb_build_array(fn_reconciliar_arvore(p_documento_id));
  end if;

  select array_agg(p.id order by (p.id = v_periodo_id) desc, p.referencia)
    into v_periodos
  from periodo p
  where p.caso_id = v_caso_id
    and (p.id = v_periodo_id or fn_periodos_compativeis(p.id, v_periodo_id));
  if v_periodos is null or cardinality(v_periodos) = 0 then
    v_periodos := array[v_periodo_id];
  end if;

  -- Classe A (0009)
  if v_tipo in ('BALANCO', 'BALANCETE', 'COMBINADO') then
    foreach v_per in array v_periodos loop
      v_res := fn_reconciliar_ativo_passivo_pl(v_caso_id, v_entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res);
  end if;
  if v_tipo in ('BALANCO', 'BALANCETE', 'COMBINADO', 'FLUXO_CAIXA') then
    foreach v_per in array v_periodos loop
      v_res := fn_reconciliar_caixa_bp_fluxo(v_caso_id, v_entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res);
  end if;

  -- Classe B (0015/0021)
  if v_tipo in ('DRE', 'FATURAMENTO_24M') then
    foreach v_per in array v_periodos loop
      v_res := fn_reconciliar_receita_dre_vs_faturamento(v_caso_id, v_entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res);
  end if;
  if v_tipo in ('DRE', 'MAPA_DIVIDA') then
    foreach v_per in array v_periodos loop
      v_res := fn_reconciliar_despfin_dre_vs_divida(v_caso_id, v_entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res);
  end if;

  -- Mútuos (0117/0123). Pelos dois lados: quem chega por último fecha o par.
  if v_tipo in ('MUTUOS', 'BALANCO', 'COMBINADO', 'DF_AUDITADA') then
    foreach v_per in array v_periodos loop
      v_res := fn_reconciliar_mutuos(v_caso_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res);
  end if;

  -- Intragrupo FORA mútuo (0124). Disparada por balanço individual, que é a
  -- única peça de que ela precisa — não há documento par a esperar. `COMBINADO`
  -- não dispara e não é lido: as linhas intragrupo dele são eliminações.
  if v_tipo in ('BALANCO', 'BALANCETE', 'DF_AUDITADA') then
    foreach v_per in array v_periodos loop
      v_res := fn_reconciliar_intragrupo(v_caso_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res);
  end if;

  -- Duplicidade de rótulo (0105). Sem loop de período: é por caso/entidade.
  if v_tipo in ('BALANCO', 'BALANCETE', 'COMBINADO') then
    v_checagens := v_checagens || jsonb_build_array(
      fn_reconciliar_duplicidade(v_caso_id, v_entidade_id));
  end if;

  -- Conflito entre documentos do mesmo período (0151). Sem loop de período: a
  -- checagem descobre sozinha quais exercícios existem.
  if v_tipo in ('BALANCO', 'BALANCETE', 'COMBINADO', 'DF_AUDITADA', 'DRE',
                'FLUXO_CAIXA', 'DMPL', 'DVA', 'NOTAS_EXPL') then
    v_checagens := v_checagens || jsonb_build_array(
      fn_reconciliar_versoes_do_periodo(v_caso_id, v_entidade_id));
  end if;

  return jsonb_build_object('executado', true, 'documento_id', p_documento_id, 'checagens', v_checagens);
end;
$$;

comment on function fn_reconciliar_por_documento(uuid) is
  'Roda as reconciliações que o tipo do documento autoriza. Desde a 0133 começa pela conferência '
  'INTRA-documento (fn_reconciliar_arvore): com totais impressos dos dois lados, Ativo = Passivo+PL '
  'fecha mesmo quando faltam contas no meio, então a árvore tem de falar primeiro. Desde a 0151 '
  'termina pelo conflito entre documentos do mesmo período, que é o único achado que sobrevive a '
  'um número que FECHA.';

-- -----------------------------------------------------------------------------
-- 6. A SOMA DO REALIZADO PARA DE ESCOLHER O MAIOR
-- -----------------------------------------------------------------------------
--
-- Reemissão inteira da função da 0150, com UMA mudança: a ordem do desempate.
-- Reemitir é o padrão do repositório para função — a definição vigente fica
-- legível num arquivo só, em vez de exigir ler duas migrations em ordem.
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
  -- marca-0151
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
      dv.documento_id,
      aut.autoridade
    from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
    left join entidade e on e.id = d.entidade_id
    left join taxonomia_tipo_documento t on t.codigo = d.tipo_taxonomia
    cross join lateral fn_autoridade_do_documento(d.id) aut
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
      -- 0151: O DESEMPATE ENTRE DOCUMENTOS, QUE ERA SILENCIOSO.
      --
      -- Dentro do MESMO exercício, a mesma conta pode vir de dois documentos (o
      -- balanço e a DF auditada dizem a mesma coisa). Quando eles CONCORDAM, a
      -- escolha é indiferente. Quando discordam, a regra da 0042 — o de maior
      -- módulo — vira "fica com o maior", que num caso de reestruturação
      -- escolhe sempre o número que infla o ativo.
      --
      -- A AUTORIDADE DOCUMENTAL DECIDE PRIMEIRO, e o maior módulo fica como
      -- último recurso: no EMPATE de autoridade o valor não muda, é o mesmo de
      -- antes desta migration. Trocar o número no empate seria substituir uma
      -- regra silenciosa por outra — e quem avisa que houve empate é
      -- `fn_reconciliar_versoes_do_periodo`, com o número perdedor à vista.
      (array_agg(c.valor_num
                 order by c.autoridade desc, abs(c.valor_num) desc nulls last))[1] as valor,
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
  -- O SINAL SEPARA AS DUAS FAMÍLIAS QUE MORAM NA MESMA SEÇÃO. Medido no Canastra
  -- 2025: `receita_bruta` guarda as receitas (positivas) E as deduções
  -- (negativas), e cada família tem o próprio total impresso —
  -- "Receita operacional bruta" 188.000 e "(-) Deduções da receita bruta"
  -- 48.128. Somando a seção inteira, nenhum dos dois bate com o dobro de si
  -- mesmo, e o discriminador não dispara para nenhum: a receita ficaria certa e
  -- a dedução contaria duas vezes. Agrupando por sinal, os dois batem — 188.000
  -- contra as quatro linhas de venda, 48.128 contra ICMS, PIS/COFINS e
  -- devoluções.
  soma_das_contas as (
    select a.secao_canonica, a.exercicio, a.entidade, sign(a.valor) as sinal,
           sum(abs(a.valor)) filter (where a.papel = 'conta') as total_contas
    from agrupado a
    group by a.secao_canonica, a.exercicio, a.entidade, sign(a.valor)
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
   and s.sinal = sign(a.valor)
$$;

comment on function fn_linhas_do_realizado(uuid, text) is
  'As linhas do caso POR EXERCÍCIO, de uma entidade, sem o que não se soma (0150): fora a '
  'abertura analítica (balancete, aging, estoque, extrato — elas reabrem contas que a '
  'demonstração já declara), fora o combinado (soma das empresas), fora a coluna que não nomeia '
  'exercício, e com o total que veio acompanhado das próprias componentes marcado `subtotal`. '
  'Desde a 0151, quando dois documentos do mesmo exercício discordam sobre a mesma conta, quem '
  'decide é a AUTORIDADE DOCUMENTAL — o maior módulo da 0042 fica como último recurso, para o '
  'empate. É a base das premissas do realizado e da média histórica; a LISTA da tela continua '
  'saindo de fn_linhas_para_modelagem, que agrupa por rótulo e não por exercício.';

grant execute on function fn_linhas_do_realizado(uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 7. O CATÁLOGO DE INSTALAÇÃO
-- -----------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('conflito_autoridade_declarada', '0151', 'coluna', 'taxonomia_tipo_documento.autoridade',
   null, null,
   'Sem a coluna não há como decidir entre dois documentos que discordam, e o produto volta ao '
   'desempate silencioso da 0042: fica com o maior. Num caso de reestruturação isso é escolher '
   'sempre o número que infla o ativo.',
   'importante', 480),
  ('conflito_entre_documentos', '0151', 'funcao', 'fn_conflitos_do_caso', null, null,
   'É a única checagem que sobrevive a um número que FECHA: um combinado preliminar sem uma '
   'eliminação intragrupo infla ativo e passivo na mesma medida, e Ativo = Passivo + PL continua '
   'batendo. Sem ela, o conflito entre duas versões do mesmo período não produz achado nenhum.',
   'bloqueante', 490),
  ('conflito_na_rodada', '0151', 'corpo', 'fn_reconciliar_por_documento', '0151', null,
   'A checagem existe e nunca roda: o despachante é quem a chama quando um balanço, um combinado '
   'ou uma DF auditada é registrado. Sem o corpo novo, `fn_conflitos_do_caso` fica instalada e '
   'muda, que é a forma de estágio parado que a rodada de 27/08 ensinou a reconhecer.',
   'bloqueante', 500),
  ('realizado_desempata_por_autoridade', '0151', 'corpo', 'fn_linhas_do_realizado', '0151', null,
   'As premissas do realizado voltam a sair do número de maior módulo quando dois documentos '
   'discordam — o combinado preliminar ganhando do balanço que ele deveria resumir.',
   'importante', 510)
on conflict (chave) do update
  set migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
      marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
      porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0151',
       revisado_em = date '2026-08-27',
       observacao = 'Revisão de 27/08/2026: a 0151 dá critério ao desempate entre dois '
                    'documentos do mesmo período, que já existia e era silencioso (a 0150 '
                    'ficava com o de maior módulo). Quatro requisitos novos: a coluna de '
                    'autoridade no catálogo, a função que acha o conflito, o despachante que a '
                    'chama, e a soma do realizado desempatando por autoridade.'
 where id;

-- =============================================================================
-- Migration 0122 — a pergunta que vai AO CLIENTE passa a ser escrita em
-- português: período por extenso, valor com separador de milhar, e a janela
-- móvel deixa de ser lida como ano
--
-- DE ONDE ISTO VEIO. A `0120` construiu o banco de perguntas e a sessão 51 deu
-- a ele uma tela. Rodando as duas coisas sobre o book da Canastra — 38
-- documentos, 6 empresas, 3 exercícios — as perguntas saíram assim, LITERAL:
--
--   "Na DRE de 24,25 não localizamos a linha de despesas financeiras."
--   "Qual a participação dos cinco maiores clientes no faturamento de L36M?"
--   "A relação de mútuos informa 16060 milhar em operações entre empresas…"
--
-- Nenhuma das três está errada no dado: `24,25` é a referência multi-ano como o
-- classificador a grava, `L36M` é a notação de janela móvel de `Arquitetura do Sistema/2 Especificação/f0/03`, e
-- `16060 milhar` é a soma com a escala que a extração declarou. Estão erradas
-- no LEITOR — e o leitor aqui é o cliente do mandato, não o analista. Este é o
-- único texto do sistema que sai da casa; ele não pode falar em chave interna.
--
-- SÃO TRÊS CONSERTOS, e o terceiro é o que não é cosmético.
--
--   1. PERÍODO POR EXTENSO. `fn_periodo_por_extenso(tipo, referencia)` devolve
--      a frase que cabe depois de "de"/"em" nos templates da entrega: um ano
--      ("2025"), dois ("2024 e 2025"), três seguidos ("2023 a 2025"), lista
--      quando há buraco ("2021, 2023 e 2025"), trimestre com o ano na frente
--      ("2025 (1º trimestre)") e janela móvel como janela ("um período de 36
--      meses"). Referência que não diz ano nenhum SAI COMO VEIO — esconder o
--      que não se entendeu é pior que mostrar.
--
--   2. VALOR EM REAIS. `fn_valor_pt_br(valor, unidade)` devolve
--      "R$ 16.060 mil" no lugar de "16060 milhar", com a escala em palavra e o
--      separador de milhar do país. Escala desconhecida vira sufixo visível, e
--      escalas MISTAS continuam recusando a soma (isso a 0120 já fazia certo).
--
--   3. `fn_anos_texto` PARA DE LER `L36M` COMO O ANO 2036, e este é um defeito
--      de DADO, não de redação. A função (0023) procura ano de quatro dígitos e,
--      não achando, aceita dois dígitos no fim do texto — regra escrita para
--      "dez/25" e "12M25". Em "L36M" o que está no fim é o TAMANHO DA JANELA:
--
--        select fn_anos_texto('L36M');  -- {2036}   ← antes desta migration
--        select fn_anos_texto('L24M');  -- {2024}
--
--      Duas consequências medidas, as duas invisíveis:
--
--      • na `0120`, o período da pergunta é escolhido pelo MAIOR ano do caso.
--        Um documento `L36M` num mandato de 2025 declarava 2036 e GANHAVA a
--        escolha — a pergunta saía falando da janela móvel em vez do exercício.
--        Foi exatamente o que a Canastra produziu no `{ano}` da 7.1. Corrigir
--        só o texto teria trocado "L36M" por "2036", que é pior: vira um ano
--        plausível e errado;
--      • em `fn_valor_conceito`/`fn_valores_por_ano` (0023 em diante), a coluna
--        rotulada `L24M` de uma planilha entrava como o EXERCÍCIO de 2024, e o
--        modelo passaria a tratar uma janela móvel como ano fechado.
--
--      A regra nova é estreita de propósito: só a notação `L<n>M` (a de Arquitetura do Sistema/2 Especificação/f0/03)
--      é removida antes da busca por ano. `12M25` continua sendo 2025 — ali o
--      que está no fim é o ano, e é o `12M` que é a janela.
--
-- O QUE ESTA MIGRATION NÃO FAZ, e é decisão, não esquecimento:
--
--   • NÃO reescreve o texto das perguntas. Os templates são verbatim da entrega
--     (cap. 10 do onboarding) e continuam sendo; o que muda é só o que o
--     sistema PREENCHE neles. Parafrasear pergunta de negócio é do autor dela.
--   • NÃO inventa data-base. `{data_base}` continua recebendo o período do
--     documento, não um "31/12/2025" deduzido do ano: quase todo balanço
--     brasileiro fecha em 31/12, mas "quase todo" não é o documento — e este
--     repositório já pagou o preço de dar precisão falsa a quem vai conferir.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- fn_anos_texto — a janela móvel deixa de virar ano.
-- Corpo da 0023 com UMA mudança: a limpeza de `L<n>M` antes da varredura.
-- -----------------------------------------------------------------------------
create or replace function fn_anos_texto(p_texto text)
returns integer[]
language plpgsql
immutable
as $$
declare
  anos int[] := '{}';
  tok  text;
  m    text[];
  txt  text;
begin
  if p_texto is null then return anos; end if;
  -- A NOTAÇÃO DE JANELA MÓVEL SAI ANTES DE PROCURAR ANO. `L24M`, `L36M`, `L12M`
  -- (Arquitetura do Sistema/2 Especificação/f0/03) dizem QUANTOS MESES a série cobre, não em que ano ela termina. A
  -- borda de palavra impede comer o "L" de outra coisa, e a limpeza é cirúrgica:
  -- "L24M 2025" continua devolvendo 2025, e `12M25` continua devolvendo 2025
  -- (lá o final é o ano, e a janela está na frente).
  txt := regexp_replace(p_texto, '(^|[^0-9A-Za-z])[Ll][0-9]{1,3}[Mm]([^0-9A-Za-z]|$)',
                        '\1 \2', 'g');
  foreach tok in array regexp_split_to_array(txt, '[^0-9]+') loop
    if tok ~ '^(19|20)[0-9]{2}$' then
      anos := anos || (tok)::int;
    end if;
  end loop;
  if cardinality(anos) = 0 then
    -- ano de 2 dígitos no fim ("dez/25", "12M25")
    m := regexp_match(txt, '([0-9]{2})[^0-9]*$');
    if m is not null then
      anos := anos || ('20' || m[1])::int;
    end if;
  end if;
  select array_agg(distinct a order by a) into anos from unnest(anos) a;
  return coalesce(anos, '{}'::int[]);
end;
$$;

comment on function fn_anos_texto(text) is
  'Anos que um rótulo de período/coluna denota (0023). Desde a 0122 a notação de JANELA MÓVEL '
  '(L24M, L36M) não é lida como ano: ela diz o tamanho da série, não o exercício — antes L36M '
  'devolvia 2036 e vencia a escolha de período da pergunta ao cliente.';

-- -----------------------------------------------------------------------------
-- fn_anos_do_periodo — os anos que uma REFERÊNCIA DE PERÍODO denota.
--
-- POR QUE ELA EXISTE AO LADO DE `fn_anos_texto`, e não dentro dela: as duas
-- leem textos de origens diferentes. `fn_anos_texto` lê rótulo de COLUNA de
-- planilha, que é texto do cliente e pode ser qualquer coisa; esta lê
-- `periodo.referencia`, que é FORMATO NOSSO — quem escreve é o
-- `parsePeriodo` (N8N/lib/classifier.mjs) ou a revisão humana. É por isso que
-- aqui "23,24,25" pode ser expandido com segurança para os três exercícios, e
-- lá não podia: no rótulo de uma coluna, a mesma sequência pode ser um valor.
-- -----------------------------------------------------------------------------
create or replace function fn_anos_do_periodo(p_referencia text)
returns integer[]
language sql
immutable
as $$
  select case
    when p_referencia is null then '{}'::int[]
    when p_referencia ~ '^\s*[0-9]{2}\s*(,\s*[0-9]{2}\s*)+$' then (
      select array_agg(distinct ('20' || trim(t))::int order by ('20' || trim(t))::int)
      from unnest(string_to_array(p_referencia, ',')) t)
    else fn_anos_texto(p_referencia)
  end;
$$;

comment on function fn_anos_do_periodo(text) is
  'Anos que uma referência de PERÍODO denota (0122). Difere de fn_anos_texto por expandir a '
  'lista de dois dígitos do formato multi ("23,24,25" → 2023, 2024, 2025), que é formato nosso — '
  'em rótulo de coluna de planilha a mesma sequência pode ser um valor.';

grant execute on function fn_anos_do_periodo(text) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_periodo_por_extenso — o período como se escreve para alguém de fora.
--
-- O RESULTADO TEM DE CABER DEPOIS DE "de"/"em", que é como os templates da
-- entrega o usam ("No balanço de {data_base}", "Na DRE de {ano}", "os juros
-- incorridos em {ano}"). É por isso que o trimestre sai com o ANO NA FRENTE —
-- "2025 (1º trimestre)" e não "1º trimestre de 2025", que produziria "Na DRE de
-- 1º trimestre de 2025".
-- -----------------------------------------------------------------------------
create or replace function fn_periodo_por_extenso(p_tipo text, p_referencia text)
returns text
language plpgsql
immutable
as $$
declare
  anos  int[];
  m     text[];
  trim_ text;
  lista text;
begin
  if p_referencia is null or length(trim(p_referencia)) = 0 then
    return null;
  end if;

  -- JANELA MÓVEL: é uma janela, e a frase diz isso. Não tem ano para dizer —
  -- desde a 0122 `fn_anos_texto` também não inventa um.
  m := regexp_match(p_referencia, '(^|[^0-9A-Za-z])[Ll]([0-9]{1,3})[Mm]([^0-9A-Za-z]|$)');
  if m is not null then
    return 'um período de ' || m[2] || ' meses';
  end if;

  anos := fn_anos_do_periodo(p_referencia);

  -- TRIMESTRE: o ano vem primeiro (ver o cabeçalho), o trimestre entre
  -- parênteses. Sem ano identificado, cai no fallback do fim.
  m := regexp_match(p_referencia, '([1-4])[Tt]([0-9]{2,4})');
  if m is not null and cardinality(anos) >= 1 then
    return anos[cardinality(anos)]::text || ' (' || m[1] || 'º trimestre)';
  end if;

  if cardinality(anos) = 0 then
    -- NÃO ENTENDI O RÓTULO: devolvo o rótulo. Um período que o sistema não
    -- soube ler tem de aparecer como está, para quem lê perceber — sumir com
    -- ele deixaria a pergunta afirmando um exercício que ninguém verificou.
    return trim(p_referencia);
  end if;

  if cardinality(anos) = 1 then
    return anos[1]::text;
  end if;

  if cardinality(anos) = 2 then
    return anos[1]::text || ' e ' || anos[2]::text;
  end if;

  -- Três ou mais: intervalo quando são seguidos ("2023 a 2025"), lista quando
  -- há buraco ("2021, 2023 e 2025") — o intervalo afirmaria exercícios que o
  -- documento não traz.
  if anos[cardinality(anos)] - anos[1] = cardinality(anos) - 1 then
    return anos[1]::text || ' a ' || anos[cardinality(anos)]::text;
  end if;

  select string_agg(a::text, ', ' order by a) into lista
  from unnest(anos[1:cardinality(anos) - 1]) a;
  return lista || ' e ' || anos[cardinality(anos)]::text;
end;
$$;

comment on function fn_periodo_por_extenso(text, text) is
  'O período como se escreve para o CLIENTE (0122), na forma que cabe depois de "de"/"em": '
  '"2025", "2024 e 2025", "2023 a 2025", "2021, 2023 e 2025", "2025 (1º trimestre)", '
  '"um período de 36 meses". Rótulo sem ano identificável volta como veio.';

grant execute on function fn_periodo_por_extenso(text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_valor_pt_br — dinheiro escrito como dinheiro.
--
-- POR QUE `to_char` COM VÍRGULA E PONTO LITERAIS, e não `G`/`D`: os símbolos de
-- agrupamento do `to_char` dependem do `lc_numeric` do servidor, que é ambiente
-- e não schema — o mesmo SQL sairia "16,060" num banco e "16.060" noutro. Com
-- os literais em notação inglesa e um `translate` no fim, o resultado é o mesmo
-- em qualquer instalação, que é o que um texto enviado a cliente exige.
-- -----------------------------------------------------------------------------
create or replace function fn_valor_pt_br(p_valor numeric, p_unidade text default null)
returns text
language plpgsql
immutable
as $$
declare
  num    text;
  escala text;
begin
  if p_valor is null then return null; end if;

  -- Centavos só quando existem: "R$ 16.060 mil" e não "R$ 16.060,00 mil".
  if p_valor = trunc(p_valor) then
    num := to_char(abs(p_valor), 'FM999,999,999,999,990');
  else
    num := to_char(abs(p_valor), 'FM999,999,999,999,990.00');
  end if;
  num := translate(num, '.,', ',.');
  -- O SINAL VEM ANTES DA MOEDA ("-R$ 240 mil"), que é como se escreve — e não
  -- "R$ -240 mil", que é como o `to_char` entregaria.
  if p_valor < 0 then num := '-R$ ' || num; else num := 'R$ ' || num; end if;

  escala := case fn_normalizar_texto(coalesce(p_unidade, ''))
    when 'milhar'  then ' mil'
    when 'milhares' then ' mil'
    when 'mil'     then ' mil'
    -- Singular quando é UM milhão. Detalhe pequeno e visível: o texto sai da casa.
    when 'milhao'  then case when abs(p_valor) = 1 then ' milhão' else ' milhões' end
    when 'milhoes' then case when abs(p_valor) = 1 then ' milhão' else ' milhões' end
    when 'unidade' then ''
    when ''        then ''
    -- ESCALA QUE NÃO CONHEÇO FICA VISÍVEL, com a palavra que veio do documento:
    -- é informação sobre a extração, e some-la faria o número mudar de tamanho
    -- em silêncio.
    else ' ' || p_unidade
  end;

  return num || escala;
end;
$$;

comment on function fn_valor_pt_br(numeric, text) is
  'Valor em reais como se escreve no Brasil (0122): "R$ 16.060 mil". A escala vira palavra '
  '(milhar → mil, milhao → milhões); escala desconhecida fica visível no fim. Independe do '
  'lc_numeric do servidor — o texto sai igual em qualquer instalação.';

grant execute on function fn_valor_pt_br(numeric, text) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_sugerir_perguntas — o corpo da 0120 com DUAS trocas: o marcador de período
-- passa pelo `fn_periodo_por_extenso` e o de saldo pelo `fn_valor_pt_br`. Todo
-- o resto (disparos, ja_enviada por entidade, prefixo da empresa, ordenação) é
-- o corpo VIGENTE, copiado inteiro — republicar função a partir de uma versão
-- antiga é o defeito que a 0026 já cometeu neste repositório.
-- -----------------------------------------------------------------------------
create or replace function fn_sugerir_perguntas(p_caso_id uuid)
returns table (
  codigo     text,
  titulo     text,
  prioridade int,
  entidade   text,
  entidade_id uuid,
  pergunta   text,
  motivo     text,
  risco      text,
  impacto    text,
  gatilho    text,
  fonte      text,
  ja_enviada boolean
)
language sql
stable
as $$
  with tem_conteudo as (
    select exists (
      select 1
      from documento d
      join campo_extraido ce on ce.documento_versao_id = fn_versao_com_extracao(d.id)
      where d.caso_id = p_caso_id and ce.valor_num is not null
    ) as ok
  ),
  -- QUAIS CÓDIGOS DISPARAM, E PARA QUEM (0120/0119): a espécie `sempre` vale
  -- para o caso; as ancoradas disparam uma vez por ENTIDADE que não satisfaz,
  -- espelhando a pendência `linha_exigida_ausente`.
  disparos as (
    select pc.codigo, null::text as entidade, null::uuid as entidade_id
    from pergunta_catalogo pc
    where pc.ativo and pc.gatilho_especie = 'sempre'
      and (select ok from tem_conteudo)
    union
    select distinct pc.codigo, x.entidade, x.entidade_id
    from pergunta_catalogo pc
    join fn_exigencias_do_caso(p_caso_id) x
      on x.tipo_taxonomia = pc.gatilho_tipo_taxonomia
     and x.conceito = pc.gatilho_conceito
    where pc.ativo
      and ((pc.gatilho_especie = 'exigencia_ausente' and not x.satisfeita)
        or (pc.gatilho_especie = 'linha_presente' and x.satisfeita))
  ),
  -- {saldo_mutuos}: soma das linhas que casam MUTUOS:saldo_de_mutuo na versão
  -- vigente. Escala única acompanha; escalas mistas NÃO são somadas às cegas.
  saldo_mutuos as (
    select case
      when count(*) = 0 then null
      when count(distinct coalesce(c.unidade, '')) > 1 then '(valores em escalas mistas — conferir)'
      -- 0122: era `sum(valor)::text || ' ' || unidade`, que produzia
      -- "16060 milhar" no texto enviado ao cliente.
      else fn_valor_pt_br(sum(c.valor_num), max(nullif(c.unidade, '')))
    end as txt
    from (
      select ce.valor_num, ce.unidade
      from documento d
      join campo_extraido ce on ce.documento_versao_id = fn_versao_com_extracao(d.id)
      where d.caso_id = p_caso_id
        and d.tipo_taxonomia = 'MUTUOS'
        and ce.valor_num is not null
        and exists (
          select 1
          from taxonomia_linha_exigida e
          join taxonomia_linha_localizador l on l.exigencia_id = e.id
          where e.tipo_taxonomia = 'MUTUOS' and e.conceito = 'saldo_de_mutuo' and e.ativo
            and case
              when l.contra = 'estrutural' then fn_rotulo_estrutural(ce.chave, l.termos_inclui)
              else
                not exists (
                  select 1 from unnest(l.termos_inclui) t
                  where fn_normalizar_texto(case when l.contra = 'secao'
                                            then coalesce(ce.secao, '') else ce.chave end)
                    not like '%' || fn_normalizar_texto(t) || '%')
                and not exists (
                  select 1 from unnest(l.termos_exclui) t
                  where fn_normalizar_texto(case when l.contra = 'secao'
                                            then coalesce(ce.secao, '') else ce.chave end)
                    like '%' || fn_normalizar_texto(t) || '%')
            end)
    ) c
  )
  select pc.codigo, pc.titulo, pc.prioridade, di.entidade, di.entidade_id,
         -- A ENTIDADE ENTRA COMO PREFIXO, e não reescrevendo o texto da entrega.
         case when di.entidade is not null then 'Sobre a ' || di.entidade || ': ' else '' end ||
         replace(replace(replace(pc.pergunta,
           -- 0122: o período vai POR EXTENSO. Era a `referencia` crua, e o que
           -- chegava ao cliente era "Na DRE de 24,25" / "de L36M" / "de 12M25".
           '{data_base}',    coalesce(per.por_extenso, '(período não informado)')),
           '{ano}',          coalesce(per.por_extenso, '(período não informado)')),
           '{saldo_mutuos}', coalesce(sm.txt, '(não localizado)')) as pergunta,
         pc.motivo, pc.risco, pc.impacto,
         case when pc.gatilho_especie = 'sempre' then 'sempre'
              else pc.gatilho_especie || ':' || pc.gatilho_tipo_taxonomia || ':' || pc.gatilho_conceito
         end as gatilho,
         pc.fonte,
         exists (
           select 1 from caso_pergunta cp
           where cp.caso_id = p_caso_id and cp.pergunta_codigo = pc.codigo and cp.acao = 'enviada'
             and cp.entidade_id is not distinct from di.entidade_id
         ) as ja_enviada
  from pergunta_catalogo pc
  join disparos di on di.codigo = pc.codigo
  cross join saldo_mutuos sm
  -- O PERÍODO MAIS RECENTE É POR ANO, NÃO POR ORDEM ALFABÉTICA (0120) — e desde
  -- a 0122 a janela móvel não finge um ano para vencer essa escolha: `L36M`
  -- devolvia 2036 e ganhava de um 2025 real.
  left join lateral (
    select fn_periodo_por_extenso(p2.tipo, p2.referencia) as por_extenso
    from documento d2
    join periodo p2 on p2.id = d2.periodo_id
    where d2.caso_id = p_caso_id
      and (pc.gatilho_tipo_taxonomia is null or d2.tipo_taxonomia = pc.gatilho_tipo_taxonomia)
      -- O PERÍODO É O DA EMPRESA DE QUE A PERGUNTA FALA (0122). A sugestão é
      -- por (pergunta × entidade) desde a 0119, e o período não acompanhava:
      -- num grupo em que a DRE da Indústria cobre 2023–2025 e a da Comercial
      -- só 2024–2025, a pergunta sobre a Comercial saía dizendo "Na DRE de
      -- 2023 a 2025" — um exercício que o documento DELA não tem. Quem recebe
      -- não reconhece o próprio documento na pergunta.
      and (di.entidade_id is null or d2.entidade_id = di.entidade_id)
    order by coalesce((select max(a) from unnest(fn_anos_do_periodo(p2.referencia)) a), -1) desc,
             -- EMPATE NO ANO MAIS RECENTE: ganha o período MAIS ESPECÍFICO. Um
             -- caso com "2025" e "24,25" tem os dois terminando em 2025, e
             -- perguntar "no faturamento de 2025" é mais preciso que "de 2024 e
             -- 2025". Sem este critério o desempate era alfabético — e o
             -- alfabeto punha o comparativo na frente.
             cardinality(coalesce(fn_anos_do_periodo(p2.referencia), '{}'::int[])) asc,
             p2.referencia desc
    limit 1
  ) per on true
  order by pc.prioridade, pc.codigo, di.entidade nulls first;
$$;

comment on function fn_sugerir_perguntas(uuid) is
  'Perguntas ao cliente SUGERIDAS para o caso (0120): exigencia_ausente/linha_presente avaliadas '
  'sobre fn_exigencias_do_caso (a mesma fonte da pendência linha_exigida_ausente — as duas faces '
  'nunca divergem); sempre = caso com conteúdo. Marcadores {data_base}/{ano} saem por EXTENSO e '
  '{saldo_mutuos} em reais (0122); desconhecidos ficam visíveis. Nada é gravado ao sugerir; '
  'ja_enviada informa, não filtra. Uma sugestão por (pergunta × entidade que não satisfaz).';

grant execute on function fn_sugerir_perguntas(uuid) to authenticated;

-- =============================================================================
-- VERIFICAÇÃO EMBUTIDA — e ela AVISA, nunca derruba a reaplicação.
--
-- É a lição da 0119/0120: uma verificação que levanta exceção transforma
-- qualquer mudança legítima de dado num erro de migration. Aqui ela confere o
-- que a própria migration promete (as três funções respondendo o que o
-- cabeçalho diz) e escreve NOTICE.
-- =============================================================================
do $$
declare
  v_falhas text[] := '{}';
begin
  if fn_anos_texto('L36M') <> '{}'::int[] then
    v_falhas := v_falhas || 'fn_anos_texto(L36M) ainda devolve ano';
  end if;
  if fn_anos_texto('12M25') <> '{2025}'::int[] then
    v_falhas := v_falhas || 'fn_anos_texto(12M25) deveria ser 2025';
  end if;
  if fn_periodo_por_extenso('multi', '23,24,25') <> '2023 a 2025' then
    v_falhas := v_falhas || ('periodo 23,24,25 → '
      || coalesce(fn_periodo_por_extenso('multi', '23,24,25'), 'null'));
  end if;
  if fn_valor_pt_br(16060, 'milhar') <> 'R$ 16.060 mil' then
    v_falhas := v_falhas || ('valor 16060/milhar → '
      || coalesce(fn_valor_pt_br(16060, 'milhar'), 'null'));
  end if;

  if cardinality(v_falhas) > 0 then
    raise notice '0122: CONFERIR — %', array_to_string(v_falhas, '; ');
  else
    raise notice '0122 ok: janela móvel não é ano, período por extenso, valor em reais';
  end if;
end $$;

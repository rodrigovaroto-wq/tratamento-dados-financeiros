-- 0159 — O ESPELHO EXATO DA 0155, DO OUTRO LADO DO RÓTULO.
--
-- MEDIDO NA RODADA REAL DO ARAUCÁRIA DE 03/09/2026 (lote `7417`, 190
-- documentos). Seis documentos classificados COMBINADO pela IA
-- (`openai_conteudo`, confiança 1,0):
--
--   arquivo                                                    tipo        entidades_na_planilha
--   167_Demonstracoes_Contabeis_Completas_..._2025.pdf         COMBINADO            0
--   168_Demonstracoes_Contabeis_Completas_..._2024.pdf         COMBINADO            0
--   169_Demonstracoes_Contabeis_Completas_..._2023.pdf         COMBINADO            0
--   170_Demonstracoes_Contabeis_Completas_..._2022.pdf         COMBINADO            0
--   171_Demonstracoes_Contabeis_Completas_..._2021.pdf         COMBINADO            0
--   175_Demonstracoes_Contabeis_arquivo_do_escritorio_..._2021 COMBINADO            0
--
-- `entidades_na_planilha = 0` — NENHUM deles é combinado. São o conjunto
-- completo de demonstrações de UMA empresa (Araucária Serraria), e o
-- diagnóstico de conteúdo (`fn_registrar_diagnostico`) abriu, SOZINHO, uma
-- pendência `tipo_incorreto` nos seis, dizendo literalmente "sugere
-- BALANCO... trata-se de balanço patrimonial e demonstrações de uma única
-- empresa (não combinado)".
--
-- O EFEITO, pela escala da 0151 (BALANCO=50, COMBINADO=30, +5 assinado):
--
--     167 (COMBINADO, 256 pares conta×coluna extraídos)          = 30+5 = 35
--     002_Balanco_Patrimonial_Araucaria_Serraria (BALANCO,
--       49% de cobertura, pendência `extracao_falhou` real)      = 50+5 = 55
--
-- NUM CONFLITO ENTRE OS DOIS, O MAL EXTRAÍDO GANHA — `fn_linhas_do_realizado`
-- escolhe por `autoridade desc`, e 55 > 35 sem perguntar mais nada.
--
-- ---------------------------------------------------------------------------
-- POR QUE A 0155 NÃO PEGA ESTE LADO
-- ---------------------------------------------------------------------------
--
-- `fn_autoridade_do_documento` só ABAIXA (`least`), de propósito — foi escrita
-- para o problema oposto (o combinado DE VERDADE rotulado BALANCO subindo para
-- 50 e empatando com o individual). Com `varias_empresas = false`, ela devolve
-- `do_tipo` intocado — e `do_tipo` do COMBINADO já É 30, o piso da escala. Não
-- há rebaixamento acontecendo aqui para desligar: o número nunca teve para
-- onde cair. O defeito não está no `least`, está em não haver NADA do lado de
-- cima quando o rótulo mente na direção contrária.
--
-- ---------------------------------------------------------------------------
-- O QUE FOI TENTADO, MEDIDO, E DESCARTADO — inclusive um que passou de
-- primeira e só se provou errado ao rodar a suíte
-- ---------------------------------------------------------------------------
--
-- (1) PROMOVER O DOCUMENTO A BALANCO. Descartado sem escrever código: seria
-- inventar um tipo que o classificador não declarou (regra 1 do CLAUDE.md —
-- `tipo_taxonomia` é dado, não palpite nosso).
--
-- (2) LEVANTAR A AUTORIDADE NUMÉRICA quando a estrutura mostra menos de duas
-- empresas — o espelho literal do `least`, um `greatest(do_tipo,
-- piso_nao_derivado)`. Descartado porque `piso_nao_derivado` não tem
-- candidato honesto: a 0155 usa a autoridade da PRÓPRIA linha COMBINADO do
-- catálogo como teto porque "derivado" é um conceito único. "Não derivado"
-- não é único: o documento pode ser um BALANCO (50), uma DRE (50), uma
-- DF_AUDITADA (60) — o classificador nunca disse QUAL, e escolher um piso
-- seria a mesma promoção de rótulo do item (1), em forma de número.
--
-- (3) O ESPELHO ESTRUTURAL PURO da 0155: `decide_sozinho = false` quando
-- `codigo = 'COMBINADO' and not fn_documento_de_varias_empresas(id)` — a
-- mesma pergunta que a 0155 faz, do lado oposto (menos de duas empresas nas
-- colunas). ESTE FOI ESCRITO, RODADO, E DERRUBOU
-- `Supabase/test/desempate.test.sql`, bloco 1 — que registra um documento
-- COMBINADO PRELIMINAR sem NENHUMA coluna de empresa (o fixture nunca marcou
-- `entidade_coluna`, porque aquele teste mede o eixo assinado/preliminar, não
-- o eixo de várias empresas) e espera que ele PERCA decididamente contra um
-- balanço assinado — `decidido = true`. A 0155 prova que ≥2 empresas nas
-- colunas CONFIRMA que a peça é derivada; este achado prova a contrapositiva:
-- **menos de duas empresas nas colunas NÃO confirma que a peça não é
-- derivada** — ausência de marcação não é prova de ausência de estrutura, só
-- de fixture que não se importou de marcar. Um COMBINADO comum, sem
-- diagnóstico contradizendo nada, é exatamente o caso que este critério
-- classificaria como "suspeito" por engano, revertendo o desempate que a
-- 0151 já resolve bem para ele. Ficou registrado aqui porque é o achado mais
-- caro desta migration: a mesma pergunta estrutural que funciona na direção
-- "mostrar 2+ prova derivado" NÃO funciona invertida.
--
-- ---------------------------------------------------------------------------
-- A CORREÇÃO: A MESMA PERGUNTA QUE O ANALISTA JÁ TEM NA TELA
-- ---------------------------------------------------------------------------
--
-- O que sobra sem inventar número nem se apoiar numa ausência estrutural que
-- não prova nada é o dado que o PRÓPRIO SISTEMA já calculou e já mostra: a
-- pendência `tipo_incorreto`, aberta por `fn_registrar_diagnostico` quando o
-- diagnóstico de conteúdo confirma que o tipo registrado provavelmente está
-- errado. É exatamente o que aconteceu nos seis documentos medidos — o
-- sistema JÁ SABIA, com justificativa por extenso, e o número usava o rótulo
-- do mesmo jeito.
--
-- Este arquivo NÃO muda a autoridade numérica de ninguém. Ele acrescenta uma
-- terceira coluna a `fn_autoridade_do_documento`, `decide_sozinho`, que é
-- `false` exatamente quando o documento está rotulado COMBINADO E tem uma
-- pendência `tipo_incorreto` ABERTA (não resolvida) — e usa essa coluna em
-- `fn_conflitos_do_caso` para que o conflito pare de ser resolvido
-- silenciosamente pela autoridade quando o rótulo de um dos dois lados já
-- está, no PRÓPRIO CASO, sob suspeita declarada. Resolver a pendência (um
-- humano confirma que o rótulo está certo apesar do diagnóstico) devolve
-- `decide_sozinho = true` sozinho, pela mesma linha do ciclo de vida que a
-- pendência já tem — nenhum mecanismo novo de "aceitar" precisa ser
-- inventado. O valor gravado não muda — exatamente como o EMPATE da 0151 já
-- não muda o valor — mas o conflito para de ser reportado como decidido, e o
-- motivo diz por quê.
--
-- ---------------------------------------------------------------------------
-- A RESTRIÇÃO DA 0155 CONTINUA DE PÉ, SEM TOCAR
-- ---------------------------------------------------------------------------
--
-- `fn_documento_de_varias_empresas` e o `least(do_tipo, teto_derivado)` da
-- 0155 não mudam uma linha, e esta migration não lê `campo_extraido` em
-- lugar nenhum. Um combinado DE VERDADE (colunas nomeando ≥2 empresas)
-- rotulado BALANCO continua limitado à autoridade de COMBINADO e continua
-- `decide_sozinho = true` — a nova regra só olha documentos rotulados
-- COMBINADO, e um BALANCO nunca entra nela.
-- `Supabase/test/autoridade_combinado.test.sql` segue passando sem alteração,
-- e `Supabase/test/desempate.test.sql` (que a tentativa (3) acima derrubou)
-- também.
--
-- =============================================================================

-- -----------------------------------------------------------------------------
-- fn_documento_decide_sozinho — a DECISÃO isolada, em função PURA sobre dois
-- valores já computados, para poder ser exercitada por literais (no modelo de
-- fn_modelagem_esta_pronta, 0158) sem fixture de documento nem de pendência.
-- -----------------------------------------------------------------------------
create or replace function fn_documento_decide_sozinho(
  p_codigo               text,
  p_tipo_incorreto_aberto boolean
) returns boolean
language sql
immutable
as $$
  -- 0159: falso SÓ quando o rótulo é COMBINADO (o único tipo que se
  -- autodeclara "peça derivada" no catálogo) E o próprio diagnóstico de
  -- conteúdo do caso já abriu (e ninguém resolveu) uma pendência dizendo que
  -- o tipo está errado. Não olha estrutura nenhuma — ver o cabeçalho desta
  -- migration para o porquê: um critério estrutural "menos de duas empresas
  -- ⇒ suspeito" derrubou um fixture legítimo (desempate.test.sql) que nunca
  -- teve motivo para marcar `entidade_coluna`.
  select not (p_codigo = 'COMBINADO' and coalesce(p_tipo_incorreto_aberto, false));
$$;

comment on function fn_documento_decide_sozinho(text, boolean) is
  '(0159) Um documento rotulado COMBINADO cujo próprio diagnóstico de conteúdo já abriu (e '
  'ninguém resolveu) uma pendência tipo_incorreto tem o rótulo contestado pelo sistema que o '
  'classificou — medido no araucária de 03/09: seis documentos COMBINADO, ZERO empresas na '
  'planilha, com `tipo_incorreto` aberta dizendo "trata-se de balanço... não combinado". Esta '
  'função isola a decisão para ser exercitada por literais (instalacao_sonda_rotulo_contraditorio) '
  'sem fixture de documento nem de pendência. Não é o espelho estrutural de '
  'fn_documento_de_varias_empresas (0155) — esse espelho foi tentado e MEDIDO como falso: menos '
  'de duas empresas nas colunas não prova que a peça não é derivada, só que o documento não '
  'marcou `entidade_coluna` (ver o cabeçalho da 0159). O sinal usado aqui é o que o próprio '
  'sistema já publica na tela de pendências, não uma inferência nova sobre dados que podem '
  'simplesmente estar ausentes por outro motivo.';

grant execute on function fn_documento_decide_sozinho(text, boolean) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_autoridade_do_documento — reemitida a partir do corpo vigente (0155).
-- Diff aditivo: o corpo original nasce todo dentro do CTE `base`, que ganha
-- UM campo novo (`tipo_incorreto_aberto`, um `exists` sobre `pendencia`) e
-- passa a alimentar `com_confianca`; o SELECT final ganha a terceira coluna
-- `decide_sozinho` e um trecho novo no `motivo` — nenhuma linha da 0155 foi
-- removida além da assinatura de retorno, trocada porque Postgres não deixa
-- `create or replace` mudar as colunas de uma função RETURNS TABLE.
-- -----------------------------------------------------------------------------
drop function if exists fn_autoridade_do_documento(uuid);

create function fn_autoridade_do_documento(p_documento_id uuid)
returns table (autoridade integer, motivo text, decide_sozinho boolean)
language sql
stable
as $$
  -- 0155: um documento cujas linhas nomeiam VÁRIAS empresas é derivado, e a
  -- autoridade dele não pode passar da de COMBINADO — senão o combinado empata
  -- com o balanço individual e o empate volta a "fica com o maior".
  with base as (
    select
      coalesce(t.autoridade, 0) as do_tipo,
      coalesce(t.codigo, 'sem tipo') as codigo,
      coalesce(t.autoridade, 0) = 0 as sem_declaracao,
      dv.assinado is true as assinado,
      fn_documento_preliminar(dv.nome_original) as preliminar,
      fn_documento_de_varias_empresas(d.id) as varias_empresas,
      (select coalesce(tc.autoridade, 30) from taxonomia_tipo_documento tc
        where tc.codigo = 'COMBINADO') as teto_derivado,
      -- 0159: o mesmo sinal que já aparece na tela de pendências do caso —
      -- ver o cabeçalho desta migration para por que NÃO é um critério
      -- estrutural sobre `campo_extraido`.
      exists (
        select 1 from pendencia pd
        where pd.documento_id = d.id
          and pd.tipo = 'tipo_incorreto'
          and pd.estado <> 'resolvida'
      ) as tipo_incorreto_aberto
    from documento d
    left join taxonomia_tipo_documento t on t.codigo = d.tipo_taxonomia
    left join documento_versao dv on dv.id = fn_versao_com_extracao(d.id)
    where d.id = p_documento_id
  ),
  com_confianca as (
    select b.*, fn_documento_decide_sozinho(b.codigo, b.tipo_incorreto_aberto) as decide_sozinho
    from base b
  )
  select
    (case when b.varias_empresas then least(b.do_tipo, b.teto_derivado) else b.do_tipo end
     + case when b.assinado then 5 else 0 end
     - case when b.preliminar then 25 else 0 end)::integer,
    b.codigo
      || case when b.sem_declaracao
              then ' (o catálogo não declara autoridade para este tipo)' else '' end
      || case when b.varias_empresas
              then format(', mas as colunas nomeiam VÁRIAS empresas — é peça derivada, e a '
                       || 'autoridade não passa da de combinado (%s)', b.teto_derivado)
              else '' end
      || case when not b.decide_sozinho
              then ' — o diagnóstico de conteúdo já contesta este rótulo (pendência '
                   || 'tipo_incorreto aberta): o documento não decide sozinho contra outro (0159)'
              else '' end
      || case when b.assinado then ', assinado' else '' end
      || case when b.preliminar
              then ', e o nome do arquivo diz que é preliminar' else '' end,
    b.decide_sozinho
  from com_confianca b;
$$;

comment on function fn_autoridade_do_documento(uuid) is
  'A autoridade documental de UM documento, o motivo por extenso, e se ele decide sozinho contra '
  'outro (0151): a do tipo no catálogo, mais 5 se assinada, menos 25 se o nome do arquivo declara '
  'preliminar. Desde a 0155, colunas nomeando VÁRIAS empresas limitam a autoridade à de COMBINADO '
  '— o rótulo diz "fechada" e a estrutura diz "derivada". Desde a 0159, `decide_sozinho` vira '
  'falso quando o documento é COMBINADO e tem uma pendência `tipo_incorreto` ABERTA — o próprio '
  'diagnóstico de conteúdo já contesta o rótulo. Medido no araucária (03/09): seis documentos '
  'assim, com a autoridade baixa (35) perdendo em silêncio contra um BALANCO mal extraído (55) '
  'da mesma empresa. A autoridade NUMÉRICA não muda nesse caso — não há piso honesto para '
  'promovê-la a (ver o cabeçalho da 0159) — só a confiança de que o documento pode decidir um '
  'conflito sozinho.';

grant execute on function fn_autoridade_do_documento(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_conflitos_do_caso — reemitida a partir do corpo vigente (0152). Diff
-- aditivo: `autoridade`/`com_autoridade`/`pares` ganham `decide_sozinho`
-- (a/b); o SELECT final troca `p.aut_a <> p.aut_b` por
-- `(p.aut_a <> p.aut_b) and p.decide_sozinho_a and p.decide_sozinho_b` na
-- coluna `decidido`, e o CASE do `criterio` ganha um ramo novo, testado
-- ANTES dos dois que já existiam — nenhuma linha do corpo de 0152 foi
-- removida além dessas.
-- -----------------------------------------------------------------------------
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
  -- 0152: o par nasce DEPOIS do agrupamento. A versão anterior pedia o produto
  -- cartesiano (6.859.127 pares comparados para achar 34, 12,4 s por chamada).
  --
  -- A versão vigente de cada documento do caso, UMA VEZ (era chamada no join e
  -- de novo dentro de fn_autoridade_do_documento).
  with versao as materialized (
    select d.id as documento_id, d.tipo_taxonomia, d.entidade_id, d.periodo_id,
           fn_versao_com_extracao(d.id) as documento_versao_id
    from documento d
    where d.caso_id = p_caso_id
  ),
  -- (b) 0146: a capa só responde quando o documento é de UMA empresa. Num
  -- documento de várias, a linha sem coluna não tem dono e fica de fora —
  -- atribuí-la à capa criaria conflito entre uma empresa e um fantasma. UMA
  -- linha por versão, em vez de uma avaliação por linha extraída.
  multi_entidade as materialized (
    select v.documento_versao_id,
           count(distinct ce.entidade_coluna) > 1 as varias
    from versao v
    left join campo_extraido ce
      on ce.documento_versao_id = v.documento_versao_id
     and ce.entidade_coluna is not null
    group by v.documento_versao_id
  ),
  -- As linhas candidatas, com os filtros baratos (índice + coluna) primeiro.
  -- `fn_papel_linha` NÃO entra aqui — ela é a cara, e entra depois de já ter
  -- sido calculada uma vez por tripla distinta.
  cru as materialized (
    select ce.id, ce.chave, ce.unidade, ce.valor_num, ce.secao_canonica,
           ce.entidade_coluna, ce.periodo_coluna,
           v.documento_id, v.tipo_taxonomia, v.documento_versao_id,
           e.razao_social, p.referencia as periodo_referencia,
           m.varias
    from versao v
    join campo_extraido ce on ce.documento_versao_id = v.documento_versao_id
    join multi_entidade m  on m.documento_versao_id = v.documento_versao_id
    left join entidade e   on e.id = v.entidade_id
    left join periodo p    on p.id = v.periodo_id
    where ce.valor_num is not null
      and ce.secao_canonica is not null
      and ce.secao_canonica <> 'NAO_CLASSIFICAVEL'
      and fn_fator_escala(ce.unidade) is not null
  ),
  -- (d) `fn_papel_linha` uma vez por tripla distinta, não uma por linha.
  papeis as materialized (
    select t.chave, t.tipo_taxonomia, t.unidade,
           fn_papel_linha(t.chave, t.tipo_taxonomia, t.unidade) as papel
    from (select distinct chave, tipo_taxonomia, unidade from cru) t
  ),
  bruto as materialized (
    select
      c.secao_canonica,
      fn_normalizar_texto(c.chave) as rotulo,
      c.chave,
      coalesce(c.entidade_coluna, case when c.varias then null else c.razao_social end) as entidade,
      coalesce(fn_exercicio_da_coluna(c.periodo_coluna),
               fn_exercicio_da_coluna(c.periodo_referencia)) as exercicio,
      fn_valor_em_base(c.valor_num, c.unidade) as valor,
      c.documento_id,
      c.tipo_taxonomia
    from cru c
    join papeis pp
      on pp.chave = c.chave
     and pp.tipo_taxonomia is not distinct from c.tipo_taxonomia
     and pp.unidade is not distinct from c.unidade
    where pp.papel = 'conta'
  ),
  -- (e) `fn_mesma_entidade` É PLPGSQL E ESTAVA SENDO CHAMADA POR LINHA. Medido
  -- no araucária: 10.570 linhas extraídas para **40 strings de entidade
  -- distintas**. É a mesma correção do `papeis` logo acima, e o mesmo defeito:
  -- função pura avaliada sobre LINHAS quando o argumento tem poucos valores.
  entidades_do_caso as materialized (
    select distinct b.entidade from bruto b where b.entidade is not null
  ),
  entidades_alvo as materialized (
    select e.entidade from entidades_do_caso e
    where p_entidade is null or fn_mesma_entidade(e.entidade, p_entidade)
  ),
  filtrado as materialized (
    select b.* from bruto b
    join entidades_alvo ea on ea.entidade = b.entidade
    where b.exercicio is not null
  ),
  -- Um valor por (conceito, exercício, entidade, DOCUMENTO). Dentro do mesmo
  -- documento a mesma conta pode aparecer em mais de uma linha (a coluna de
  -- outro exercício, uma repetição de página); o de maior módulo representa o
  -- documento, e é a regra da 0042 usada onde ela é inofensiva — aqui ela
  -- escolhe entre linhas de UMA fonte, não entre fontes que discordam.
  por_documento as materialized (
    select f.secao_canonica, f.rotulo, f.entidade, f.exercicio, f.documento_id,
           max(f.tipo_taxonomia) as tipo,
           (array_agg(f.chave order by length(f.chave)))[1] as chave,
           (array_agg(f.valor order by abs(f.valor) desc nulls last))[1] as valor
    from filtrado f
    group by f.secao_canonica, f.rotulo, f.entidade, f.exercicio, f.documento_id
  ),
  -- (a) O AGRUPAMENTO QUE MATA O CARTESIANO. Só grupo com mais de um documento
  -- e com dispersão acima do piso da tolerância pode conter par. Ver a prova de
  -- que o pré-filtro é conservador no cabeçalho.
  grupos as materialized (
    select secao_canonica, rotulo, entidade, exercicio
    from por_documento
    group by secao_canonica, rotulo, entidade, exercicio
    having count(*) > 1
       and (max(valor) - min(valor)) > p_tolerancia_abs
  ),
  candidatos as materialized (
    select pd.*
    from por_documento pd
    join grupos g
      on g.secao_canonica = pd.secao_canonica
     and g.rotulo         = pd.rotulo
     and g.entidade       is not distinct from pd.entidade
     and g.exercicio      = pd.exercicio
  ),
  -- (c) A autoridade uma vez por DOCUMENTO — e só dos documentos que sobraram.
  -- 0159: `decide_sozinho` vem junto — é a mesma chamada, sem custo extra.
  autoridade as materialized (
    select dd.documento_id, a.autoridade, a.motivo, a.decide_sozinho
    from (select distinct documento_id from candidatos) dd
    cross join lateral fn_autoridade_do_documento(dd.documento_id) a
  ),
  com_autoridade as materialized (
    select c.*, au.autoridade, au.motivo, au.decide_sozinho
    from candidatos c join autoridade au on au.documento_id = c.documento_id
  ),
  pares as (
    select
      a.secao_canonica, a.chave, a.entidade, a.exercicio,
      a.documento_id as doc_a, a.tipo as tipo_a, a.valor as valor_a,
      a.autoridade as aut_a, a.motivo as motivo_a, a.decide_sozinho as decide_sozinho_a,
      b.documento_id as doc_b, b.tipo as tipo_b, b.valor as valor_b,
      b.autoridade as aut_b, b.motivo as motivo_b, b.decide_sozinho as decide_sozinho_b
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
    -- 0159: um lado com o rótulo contestado pelo próprio diagnóstico não
    -- decide sozinho — nem para vencer, nem para perder em silêncio.
    -- `decidido` passa a exigir os dois lados confiáveis, além da
    -- autoridade diferir.
    (p.aut_a <> p.aut_b) and p.decide_sozinho_a and p.decide_sozinho_b,
    case
      when not (p.decide_sozinho_a and p.decide_sozinho_b) then
        format('SEM DECISÃO AUTOMÁTICA: %s (autoridade %s) tem o rótulo contestado pelo próprio '
               || 'diagnóstico de conteúdo — %s. O valor em uso não foi trocado; a escolha é '
               || 'humana.',
               case when not p.decide_sozinho_a then p.tipo_a else p.tipo_b end,
               case when not p.decide_sozinho_a then p.aut_a else p.aut_b end,
               case when not p.decide_sozinho_a then p.motivo_a else p.motivo_b end)
      when p.aut_a <> p.aut_b then
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
  'seção canônica, papel conta e unidade conversível. `decidido = false` é empate OU rótulo '
  'contestado pelo diagnóstico (0159, um lado com `decide_sozinho = false`) — nos dois casos '
  'ninguém vence e a decisão é humana. O par nasce DEPOIS do agrupamento (0152) — a versão '
  'anterior pedia o produto cartesiano e levava 12,4 s por chamada no lote de 190 documentos.';

grant execute on function fn_conflitos_do_caso(uuid, text, numeric, numeric) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_reconciliar_versoes_do_periodo — reemitida a partir do corpo vigente
-- (0151). Diff aditivo: a ÚNICA linha mudada é o texto do `format` que conta
-- quantos conflitos ficaram sem decisão — ele dizia só "EMPATAM em autoridade
-- documental", e desde a 0159 `decidido = false` também acontece por rótulo
-- contestado pelo diagnóstico, sem autoridade empatar em número nenhum. Dizer
-- "empatam" para os dois seria a mesma imprecisão que a regra 5 do CLAUDE.md
-- proíbe. O resto do corpo é idêntico.
-- -----------------------------------------------------------------------------
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
           -- 0159: "empatam" deixou de ser a única causa de `decidido = false`
           -- — um rótulo contestado pelo diagnóstico (0159) também zera a
           -- decisão automática sem que a autoridade numérica empate.
           then format('%s deles NÃO TÊM decisão automática (empate de autoridade, ou o rótulo '
                       || 'de um dos dois contestado pelo próprio diagnóstico de conteúdo) e '
                       || 'ninguém decidiu por você — o valor em uso continua o de maior módulo, '
                       || 'que é o padrão antigo. ',
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
  'conta. Declara o vencedor por autoridade documental e o critério; sem decisão automática '
  '(empate de autoridade, ou desde a 0159, rótulo contestado pelo diagnóstico) volta para o '
  'humano sem trocar valor nenhum.';

grant execute on function fn_reconciliar_versoes_do_periodo(uuid, uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- A SONDA — a decisão pura, executada por literais, e a fiação nas duas
-- funções que a consomem.
-- -----------------------------------------------------------------------------
create or replace view instalacao_sonda_rotulo_contraditorio as
select 1 as ok
where
  -- o caso medido: rotulado COMBINADO, com tipo_incorreto ABERTA — os seis do
  -- araucária de 03/09 (167 a 171, e o 175).
  fn_documento_decide_sozinho('COMBINADO', true) = false
  -- COMBINADO sem nenhuma pendência tipo_incorreto: decide sozinho, como
  -- sempre — é o caso comum, e é o que a tentativa estrutural (descartada,
  -- ver o cabeçalho) classificaria errado.
  and fn_documento_decide_sozinho('COMBINADO', false) = true
  -- NULL (nenhuma linha de pendência casou, `exists` nunca devolve NULL, mas
  -- a função pura não pode depender disso): coalesce trata como ausente.
  and fn_documento_decide_sozinho('COMBINADO', null) = true
  -- o espelho exato do que a 0155 protege: BALANCO com tipo_incorreto aberta
  -- (o diagnóstico pode discordar de QUALQUER tipo) continua decidindo
  -- sozinho — é a autoridade dele que a 0155 rebaixa via `least` quando a
  -- ESTRUTURA confirma várias empresas, não esta regra.
  and fn_documento_decide_sozinho('BALANCO', true) = true
  -- qualquer outro tipo nunca se autodeclarou derivado — tipo_incorreto
  -- nele é assunto de outra pendência, não desta.
  and fn_documento_decide_sozinho('RAZAO', true) = true;

comment on view instalacao_sonda_rotulo_contraditorio is
  '(0159) Autoteste de fn_documento_decide_sozinho, EXECUTADA por literais (função pura, sem '
  'fixture de documento nem de pendência): 1 linha só se o caso medido (COMBINADO com '
  'tipo_incorreto aberta), o caso comum (COMBINADO sem pendência, decide sozinho), o NULL '
  '(coalesce trata como ausente), o espelho da 0155 (BALANCO com tipo_incorreto continua '
  'decidindo sozinho — é a autoridade que cai, não a confiança) e o irrelevante (RAZAO, nunca se '
  'autodeclarou derivado) valem todos ao mesmo tempo. Um marcador textual de corpo/função não '
  'pega um "false and" que mate o predicado e deixe os comentários intactos (achado D da revisão '
  'da 0157) — esta view pega, porque o predicado É executado.';

grant select on instalacao_sonda_rotulo_contraditorio to authenticated;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('fn_documento_decide_sozinho', '0159', 'funcao', 'fn_documento_decide_sozinho', null, null,
   'Sem ela não há critério para reconhecer que um rótulo COMBINADO está contestado pelo próprio '
   'diagnóstico de conteúdo, e a autoridade de um documento assim volta a decidir conflitos '
   'sozinha — como no araucária de 03/09, seis documentos de UMA empresa perdendo em silêncio '
   'contra um BALANCO da mesma empresa com 49% de cobertura.',
   'importante', 620),
  ('rotulo_contraditorio_regra_viva', '0159', 'seed', 'instalacao_sonda_rotulo_contraditorio',
   null, 1,
   'A regra de quando um documento não decide sozinho pode existir como código morto: um '
   'requisito de "corpo" ou "função" prova só que o texto está no arquivo, não que o predicado '
   'decide certo. Esta linha executa a decisão contra cinco combinações fixas, incluindo o '
   'espelho exato da 0155 (BALANCO contestado continua decidindo sozinho) — ausente aqui quer '
   'dizer que o buraco fechado pela 0155 pode ter reaberto por acidente, ou que o buraco que '
   'esta migration fecha nunca fechou de verdade.',
   'bloqueante', 621),
  ('autoridade_publica_decide_sozinho', '0159', 'corpo', 'fn_autoridade_do_documento',
   'fn_documento_decide_sozinho', null,
   'Sem esta chamada `fn_autoridade_do_documento` continua devolvendo só autoridade e motivo — '
   'nenhum consumidor tem como saber que um documento tem o rótulo contestado pelo diagnóstico, '
   'e o conflito volta a ser resolvido só pelo número.',
   'bloqueante', 622),
  ('conflitos_nao_decidem_com_rotulo_contestado', '0159', 'corpo', 'fn_conflitos_do_caso',
   'decide_sozinho_a', null,
   'Sem esta condição em `decidido`, `fn_conflitos_do_caso` volta a resolver um conflito pela '
   'autoridade mesmo quando um dos dois documentos tem o rótulo contestado pelo próprio '
   'diagnóstico de conteúdo — o defeito medido no araucária (167, COMBINADO com tipo_incorreto '
   'aberta, autoridade 35, perdendo em silêncio contra um BALANCO de autoridade 55 e 49% de '
   'cobertura) volta a passar sem alarme nenhum na reconciliação.',
   'bloqueante', 623)
on conflict (chave) do update
  set migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
      marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
      porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0159',
       revisado_em = date '2026-09-03',
       observacao = 'Revisão de 03/09/2026: a 0159 fecha o espelho exato do que a 0155 fechou. '
                    'Medido no araucária (lote 7417): seis documentos rotulados COMBINADO, com '
                    'a pendência tipo_incorreto aberta pelo próprio diagnóstico de conteúdo — o '
                    'conjunto completo de demonstrações de UMA empresa — perdendo em silêncio '
                    '(autoridade 35) contra um BALANCO da mesma empresa com 49% de cobertura '
                    '(autoridade 55). Uma primeira tentativa usou o espelho ESTRUTURAL exato da '
                    '0155 (menos de duas empresas nas colunas) e foi DERRUBADA por '
                    'desempate.test.sql: ausência de `entidade_coluna` não prova que a peça não '
                    'é derivada, só que o fixture não marcou. A correção final usa o sinal que o '
                    'próprio sistema já publica (a pendência tipo_incorreto) em vez de inferir '
                    'estrutura sobre dado ausente. Sem piso honesto para promover a autoridade '
                    'numérica, a correção não mexe no número: acrescenta `decide_sozinho` a '
                    'fn_autoridade_do_documento e fn_conflitos_do_caso passa a exigi-lo dos dois '
                    'lados para declarar um conflito decidido. A restrição da 0155 (combinado de '
                    'verdade rotulado BALANCO continua limitado ao teto de COMBINADO) não foi '
                    'tocada. Quatro requisitos novos.'
 where id;

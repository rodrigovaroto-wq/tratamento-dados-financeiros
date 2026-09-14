-- =============================================================================
-- 0168 — O nome truncado que casa com os outros não é ambiguidade
--
-- O QUE O DONO VIU no export do caso "teste 143": a OMNIBEAUTY aparece como
-- QUATRO empresas, em quatro blocos de coluna separados no book —
--
--     OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE                 7 documentos
--     OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE MARCAS LTDA     2 documentos
--     OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE SURUBIJU        1 documento
--     OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE SURUBIJU, 1930  1 documento
--
-- É UMA empresa só (CNPJ 36.193.378/0001-04 nos dois balanços que o dono
-- anexou). O balanço de 2023 fica sozinho num bloco e não compara com nada; o
-- faturamento cai fora do grupo. "SURUBIJU, 1930" é o ENDEREÇO: conferido no
-- PDF `OMNIBEAUTY - FATURAMENTO 2024.pdf`, o relatório imprime
--
--     Empresa:   OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE
--     Endereço:  SURUBIJU, 1930
--
-- — o template do contador TRUNCA a razão social num campo de largura fixa, e a
-- linha de endereço vem logo abaixo, sem separação visual. A extração leu as
-- duas como uma.
--
-- CAUSA RAIZ, no código. Quem cria a quarta linha é `fn_upsert_entidade` (0153),
-- na regra "no empate, não escolhe": com DOIS ou mais candidatos aproximados e
-- nenhum exato, ela cria uma entidade NOVA e registra `entidade_ambigua`. O
-- efeito é CUMULATIVO — a partir da segunda variante, toda variante nova
-- encontra 2+ candidatos e vira linha própria.
--
-- Essa regra existe por um motivo real e continua certa: "Araucaria SPE" casa
-- com "Araucária Bioenergia SPE" E com "Araucária Imobiliária SPE", que são
-- empresas DIFERENTES — escolher uma delas põe o balanço de uma dentro da
-- outra, calado. Foi o incidente que a 0153 corrigiu.
--
-- O QUE ESTA MIGRATION MEDIU ANTES DE DECIDIR, e é o número que corrige uma
-- hipótese que a sessão anterior tinha escrito aqui. `fn_mesma_entidade` NÃO
-- considera as quatro variantes a mesma empresa par a par. Os seis pares, no
-- banco (`select fn_mesma_entidade(a,b)`):
--
--     truncado      × MARCAS LTDA       → VERDADEIRO
--     truncado      × SURUBIJU          → VERDADEIRO
--     truncado      × SURUBIJU, 1930    → VERDADEIRO
--     MARCAS LTDA   × SURUBIJU          → **FALSO**
--     MARCAS LTDA   × SURUBIJU, 1930    → **FALSO**
--     SURUBIJU      × SURUBIJU, 1930    → VERDADEIRO
--
-- ("marcas" não é prefixo de "surubiju".) Ou seja: pelo NOME, "…DE MARCAS" e
-- "…DE SURUBIJU" são tão indistinguíveis de duas empresas irmãs quanto
-- "Bioenergia" e "Imobiliária" são. Quem prova que são a mesma é o CNPJ, que
-- `fn_upsert_entidade` não recebe. Fundi-las aqui seria ESCOLHER no empate —
-- exatamente o que a 0153 proíbe, e pela razão certa.
--
-- A CORREÇÃO, então, é a fatia que o nome SOZINHO prova: antes de criar a
-- entidade nova por ambiguidade, perguntar se os candidatos (mais o nome que
-- chega) formam UM ÚNICO GRUPO — se cada par entre eles casa. Se formam, não há
-- duas empresas: há um nome escrito de comprimentos diferentes, e a resposta é o
-- candidato de razão social mais completa. Se não formam, NADA MUDA — cria a
-- entidade própria e registra `entidade_ambigua`, como a 0153 faz hoje.
--
-- O GANHO, MEDIDO contra os quatro nomes reais, na ordem que reproduz o que o
-- dono viu (MARCAS, SURUBIJU, truncado, "SURUBIJU, 1930"):
--
--     sem esta migration: 4 entidades   ← reproduz o export, linha por linha
--     com esta migration: 3 entidades
--
-- A quarta variante ("SURUBIJU, 1930", o endereço grudado) deixa de virar linha
-- e entra em "…DE SURUBIJU", com `entidade_alias_fundido` no log. As duas que
-- sobram separadas são MARCAS × SURUBIJU, que é a ambiguidade de verdade
-- descrita acima.
--
-- E O QUE FALTA, dito com o número para não virar surpresa: fechar de 3 para 1
-- exige o CNPJ chegar até aqui — é mudança na EXTRAÇÃO (o nome do emitente sai
-- do template truncado com o endereço colado), não neste algoritmo. Está
-- registrado no `HANDOFF.md` como defeito de qualidade de extração.
--
-- E A ORDEM IMPORTA, o que também é medido: se o nome truncado chegasse
-- PRIMEIRO, cada variante seguinte acharia UM candidato só e seria absorvida
-- por ele — uma entidade, sem esta migration. O lote real chegou na outra
-- ordem. Esta migration reduz o dano em toda ordem; não o zera em nenhuma.
--
-- POR QUE O CANDIDATO MAIS LONGO. O nome que sobrevive é o que o analista vê no
-- book e na pendência. Entre "OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE" e a mesma
-- coisa com "SURUBIJU" no fim, o segundo guarda mais do que o sistema recebeu.
-- O nome que CHEGA entra na conta do grupo mas não na escolha: ele é o que pode
-- estar contaminado pelo endereço, e descartá-lo é de propósito.
--
-- O QUE ESTA MIGRATION NÃO FAZ: ela não funde o que já está fragmentado. O caso
-- "teste 143" continua com as quatro linhas até alguém decidir fundi-las — é
-- mudança de DADO de produção, não de código, e precisa da decisão do dono.
-- Esta migration impede o PRÓXIMO lote de nascer assim.
--
-- Idempotente: `create or replace`.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- fn_entidades_sao_um_grupo — os candidatos são todos a mesma empresa?
--
-- Verdadeiro quando CADA PAR entre eles casa por `fn_mesma_entidade`. Com um
-- candidato só, é trivialmente verdadeiro (e quem chama nem pergunta). Com zero,
-- falso — não há grupo nenhum.
--
-- NÃO é fecho transitivo: exige que TODOS casem com TODOS, que é mais estrito.
-- A diferença importa e é de propósito: A~B e B~C sem A~C significa que B é um
-- nome curto o bastante para casar com duas empresas distintas — exatamente o
-- "Araucaria SPE" da 0153, e exatamente o caso em que não se deve escolher.
-- -----------------------------------------------------------------------------
create or replace function fn_entidades_sao_um_grupo(p_nomes text[])
returns boolean
language sql
immutable
as $$
  select coalesce(array_length(p_nomes, 1), 0) > 0
     and not exists (
       select 1
       from unnest(p_nomes) with ordinality as a(nome, i)
       join unnest(p_nomes) with ordinality as b(nome, j) on j > i
       where not fn_mesma_entidade(a.nome, b.nome)
     );
$$;

comment on function fn_entidades_sao_um_grupo(text[]) is
  'Os nomes são todos a MESMA empresa? Exige que cada PAR case por fn_mesma_entidade — não é '
  'fecho transitivo de propósito: A~B e B~C sem A~C é o apelido curto que casa com duas '
  'empresas distintas (o "Araucaria SPE" da 0153), e ali não se escolhe.';

-- -----------------------------------------------------------------------------
-- fn_upsert_entidade — corpo da 0153 com o ramo do grupo único.
-- -----------------------------------------------------------------------------
create or replace function fn_upsert_entidade(p_caso_id uuid, p_nome text)
returns uuid
language plpgsql
as $$
declare
  v_id        uuid;
  v_n         int;
  v_candidatos text;
  v_nomes     text[];
begin
  -- 0153: no empate, não escolhe.
  if p_nome is null or length(trim(p_nome)) = 0 then return null; end if;

  -- (1) exato pela forma canônica — não há o que desempatar.
  select c.entidade_id into v_id
  from fn_entidades_candidatas(p_caso_id, p_nome) c
  where c.exata
  order by c.razao_social
  limit 1;
  if v_id is not null then return v_id; end if;

  -- (2)/(3) quantos APROXIMADOS existem?
  select count(*), string_agg(c.razao_social, ' × ' order by c.razao_social),
         array_agg(c.razao_social)
    into v_n, v_candidatos, v_nomes
  from fn_entidades_candidatas(p_caso_id, p_nome) c;

  if v_n = 1 then
    select c.entidade_id into v_id from fn_entidades_candidatas(p_caso_id, p_nome) c limit 1;
    return v_id;
  end if;

  -- (3b) 0168: DOIS OU MAIS CANDIDATOS QUE CASAM ENTRE SI NÃO SÃO AMBIGUIDADE.
  -- São o mesmo nome escrito de comprimentos diferentes (o template do contador
  -- trunca a razão social num campo de largura fixa). Fica o mais COMPLETO — o
  -- mais longo —, que é o que identifica a empresa na tela e na pendência.
  -- O nome novo entra no grupo: se ele casa com todos, o grupo continua um só.
  if v_n > 1 and fn_entidades_sao_um_grupo(v_nomes || trim(p_nome)) then
    select c.entidade_id into v_id
    from fn_entidades_candidatas(p_caso_id, p_nome) c
    order by length(c.razao_social) desc, c.razao_social
    limit 1;

    insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:entidade', 'entidade_alias_fundido', 'entidade:' || v_id,
            jsonb_build_object('caso_id', p_caso_id, 'nome_procurado', trim(p_nome),
                               'candidatos', v_candidatos, 'quantos', v_n,
                               'porque', 'os candidatos casam todos entre si — é um nome só, '
                                      || 'truncado de jeitos diferentes pela fonte'));
    return v_id;
  end if;

  insert into entidade (caso_id, razao_social) values (p_caso_id, trim(p_nome))
    returning id into v_id;

  if v_n > 1 then
    -- A AMBIGUIDADE É REGISTRADA AQUI e virada em pendência por quem tem o
    -- documento na mão. Esta função não conhece documento — inventar um vínculo
    -- para poder abrir a pendência aqui seria a entidade fantasma da 0146 ao
    -- contrário.
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:entidade', 'entidade_ambigua', 'entidade:' || v_id,
            jsonb_build_object('caso_id', p_caso_id, 'nome_procurado', trim(p_nome),
                               'candidatos', v_candidatos, 'quantos', v_n));
  end if;

  return v_id;
end;
$$;

comment on function fn_upsert_entidade(p_caso_id uuid, p_nome text) is
  'Acha ou cria a entidade do caso pelo nome (0030), sem ESCOLHER no empate (0153): canônico '
  'exato, depois o único aproximado. 0168: dois ou mais aproximados que casam TODOS ENTRE SI '
  'não são ambiguidade — são um nome truncado de jeitos diferentes, e fica o mais completo. '
  'Candidatos que NÃO casam entre si (Araucária Bioenergia × Araucária Imobiliária) continuam '
  'criando entidade própria com `entidade_ambigua` no log.';

-- -----------------------------------------------------------------------------
-- O CATÁLOGO DA SONDA — requisito de CORPO sobre a função nova.
-- -----------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('alias_truncado_nao_fragmenta', '0168', 'corpo', 'fn_upsert_entidade',
   'fn_entidades_sao_um_grupo', null,
   'Sem esta migration, a variante de nome que casa com DOIS candidatos que casam entre si cria '
   'entidade própria, e cada variante seguinte cria mais uma — efeito cumulativo. Medido com os '
   'quatro nomes reais do caso "teste 143" (o template do contador trunca a razão social e num '
   'dos relatórios a linha de endereço grudou no nome): 4 entidades sem a migration, 3 com ela. '
   'Cada linha a mais é um bloco de coluna sozinho no book, um balanço que não compara com nada '
   'e um faturamento fora do grupo.',
   'bloqueante', 660)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0168', revisado_em = current_date,
       observacao = 'A 0168 acrescenta fn_entidades_sao_um_grupo e muda o corpo de '
                    'fn_upsert_entidade — requisito de corpo (o nome da função nova, que some '
                    'num create or replace com o corpo velho). O comportamento é provado no CI '
                    '(alias_truncado.test.sql), inclusive o contrapositivo da 0153.';

commit;

-- =============================================================================
-- 0169 — O CNPJ é a identidade que o nome não é
--
-- O QUE A 0168 NÃO CONSEGUIU FECHAR, e por quê. Ela reduziu a OMNIBEAUTY de
-- QUATRO entidades para TRÊS no lote do caso "teste 143", e parou ali por uma
-- razão medida, não por falta de esforço: as variantes "…DE MARCAS" e
-- "…DE SURUBIJU" NÃO casam por `fn_mesma_entidade` ("marcas" não é prefixo de
-- "surubiju"). Pelo NOME elas são tão indistinguíveis de duas empresas irmãs
-- quanto "Araucária Bioenergia" e "Araucária Imobiliária" são — e escolher uma
-- seria ESCOLHER NO EMPATE, que é o que a 0153 existe para proibir.
--
-- Quem prova que são a mesma empresa é o **CNPJ 36.193.378/0001-04**, o mesmo
-- nos dois balanços que o dono anexou. O nome é um rótulo que a fonte trunca; o
-- CNPJ é a identidade. O sistema nunca o usou: a coluna `entidade.cnpj` existe
-- desde a 0001 e **nunca foi populada em lugar nenhum do produto**.
--
-- ESTA MIGRATION FAZ O BANCO SABER USÁ-LO. Ela não faz o CNPJ CHEGAR até aqui —
-- isso é a extração, e é a fatia seguinte. Enquanto o parâmetro chegar nulo,
-- **nada muda**: todo caminho de nome continua byte a byte o da 0168, e há
-- assert provando isso.
--
-- AS TRÊS REGRAS, em ordem de força:
--
--   1. CNPJ IGUAL É A MESMA EMPRESA, ponto. Se alguma entidade do caso já tem
--      este CNPJ, é ela — sem olhar o nome. É isto que funde as variantes
--      truncadas em QUALQUER ordem de chegada, coisa que a 0168 só conseguia
--      quando a ordem ajudava.
--
--   2. CNPJ DIFERENTE É OUTRA EMPRESA, e isso **desliga o casamento por nome**
--      contra ela. Uma candidata cujo CNPJ conhecido difere do que chegou sai
--      da lista de candidatas — o nome não tem autoridade para contradizer o
--      registro fiscal. Isto corrige, quando há CNPJ, o LIMITE CONHECIDO da
--      0153 que o `entidade_ambigua.test.sql` mede desde sempre: hoje
--      "ALFA COMERCIO EXTERIOR LTDA." é ABSORVIDA em silêncio por
--      "ALFA COMERCIO LTDA." porque uma é subsequência da outra.
--
--   3. CNPJ AUSENTE NÃO DECIDE NADA. Null é ausência, não informação — e
--      ausência não vira dado (regra 1 do CLAUDE.md). Candidata sem CNPJ
--      continua candidata; o nome decide, como na 0168.
--
-- E O CNPJ FICA GRAVADO quando a entidade ainda não tem um. É o que faz a regra
-- 1 valer a partir do SEGUNDO documento: o primeiro ensina a identidade, os
-- demais a usam. Nunca SOBRESCREVE um CNPJ já gravado — se dois documentos da
-- mesma entidade trazem CNPJs diferentes, isso é divergência para humano, e a
-- regra 2 já os terá separado antes de chegar aqui.
--
-- POR QUE VALIDAR O DÍGITO VERIFICADOR, e não só contar 14 dígitos: o CNPJ vai
-- chegar de uma IA lendo um PDF, às vezes escaneado. Um número inventado ou mal
-- lido que passe como identidade é PIOR que nenhum — ele funde duas empresas de
-- verdade, calado, que é o dano exato que a 0153 existe para evitar. CNPJ que
-- não fecha o DV é tratado como AUSENTE, não como dado.
--
-- A ARMADILHA DO OVERLOAD, e ela já derrubou um lote real: acrescentar um
-- parâmetro com default SEM matar a assinatura antiga deixa DUAS funções vivas,
-- e a chamada de dois argumentos casa com AMBAS — o Postgres recusa com
-- "function is not unique", no meio de uma rodada, não em teste. Foi o que a
-- 0118 teve de consertar em `fn_registrar_documento`, e é o que
-- `reextracao.test.sql` mede até hoje. Por isso o `drop function` explícito
-- abaixo, antes do `create`.
--
-- Idempotente: `drop ... if exists` + `create or replace`.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- fn_cnpj_canonico — 14 dígitos com DV que fecha, ou NULO.
--
-- Devolve os 14 dígitos sem pontuação. Devolve NULO (= "não sei") para tudo o
-- mais: comprimento errado, todos os dígitos iguais (00000000000000 e irmãos,
-- que passam no DV por acidente aritmético e não são CNPJ de ninguém), ou DV
-- que não fecha.
-- -----------------------------------------------------------------------------
create or replace function fn_cnpj_canonico(p_cnpj text)
returns text
language plpgsql
immutable
as $$
declare
  d     text;
  peso  int;
  soma  int;
  -- `dv` e `i` NÃO são declarados: os `for` abaixo declaram os próprios e
  -- sombreariam estes. Declará-los é ruído que `plpgsql.extra_warnings =
  -- shadowed_variables` acusa.
begin
  if p_cnpj is null then return null; end if;
  d := regexp_replace(p_cnpj, '[^0-9]', '', 'g');
  if length(d) <> 14 then return null; end if;
  if d ~ ('^' || substr(d, 1, 1) || '{14}$') then return null; end if;

  -- DV1 sobre os 12 primeiros; DV2 sobre os 13 primeiros. Os pesos descem de 9
  -- a 2 e reiniciam, que é o algoritmo do módulo 11 da Receita.
  for dv in 1 .. 2 loop
    soma := 0;
    peso := 1;
    for i in reverse (11 + dv) .. 1 loop
      peso := peso + 1;
      if peso > 9 then peso := 2; end if;
      soma := soma + substr(d, i, 1)::int * peso;
    end loop;
    soma := soma % 11;
    if soma < 2 then soma := 0; else soma := 11 - soma; end if;
    if substr(d, 12 + dv, 1)::int <> soma then return null; end if;
  end loop;

  return d;
end;
$$;

comment on function fn_cnpj_canonico(text) is
  '14 dígitos de CNPJ com o DV conferido, ou NULO. 0169: o CNPJ vai chegar de uma IA lendo PDF '
  'escaneado — um número inventado que passe como identidade funde duas empresas de verdade em '
  'silêncio, que é pior que não ter CNPJ nenhum. DV que não fecha é AUSÊNCIA, não dado.';

-- -----------------------------------------------------------------------------
-- fn_entidades_candidatas_cnpj — as candidatas da 0153, menos as que o CNPJ
-- desmente.
--
-- Com `p_cnpj` nulo devolve EXATAMENTE `fn_entidades_candidatas` — é a
-- propriedade que mantém todo o comportamento da 0168 intacto enquanto a
-- extração não manda CNPJ nenhum.
--
-- Com CNPJ, tira da lista quem tem um CNPJ conhecido e DIFERENTE. Quem não tem
-- CNPJ continua na lista: ausência não desqualifica ninguém.
-- -----------------------------------------------------------------------------
create or replace function fn_entidades_candidatas_cnpj(
  p_caso_id uuid, p_nome text, p_cnpj text
)
returns table (entidade_id uuid, razao_social text, exata boolean)
language sql
stable
as $$
  select c.entidade_id, c.razao_social, c.exata
  from fn_entidades_candidatas(p_caso_id, p_nome) c
  join entidade e on e.id = c.entidade_id
  where fn_cnpj_canonico(p_cnpj) is null
     or fn_cnpj_canonico(e.cnpj) is null
     or fn_cnpj_canonico(e.cnpj) = fn_cnpj_canonico(p_cnpj)
  order by c.exata desc, c.razao_social;
$$;

comment on function fn_entidades_candidatas_cnpj(uuid, text, text) is
  'As candidatas da 0153 menos as que o CNPJ desmente (0169). CNPJ nulo devolve a lista inteira: '
  'ausência não desqualifica ninguém. CNPJ conhecido e diferente sai — o nome não tem autoridade '
  'para contradizer o registro fiscal.';

-- -----------------------------------------------------------------------------
-- fn_upsert_entidade — corpo da 0168 com o CNPJ por cima.
--
-- O DROP É OBRIGATÓRIO, não higiene: ver a armadilha do overload no cabeçalho.
-- -----------------------------------------------------------------------------
drop function if exists fn_upsert_entidade(uuid, text);

create or replace function fn_upsert_entidade(
  p_caso_id uuid, p_nome text, p_cnpj text default null
)
returns uuid
language plpgsql
as $$
declare
  v_id         uuid;
  v_n          int;
  v_candidatos text;
  v_nomes      text[];
  v_cnpj       text := fn_cnpj_canonico(p_cnpj);
begin
  -- 0153: no empate, não escolhe. (E o requisito de sonda `entidade_ambigua_nao_decide`
  -- tem o literal "0153" como MARCADOR DE CORPO — tirar esta linha derruba a sonda
  -- sem mudar comportamento nenhum. Achado ao rodar a suíte desta fatia.)
  if p_nome is null or length(trim(p_nome)) = 0 then return null; end if;

  -- (0) 0169: CNPJ IGUAL É A MESMA EMPRESA, e ele não pergunta o nome. É esta
  -- regra que funde as variantes truncadas em QUALQUER ordem de chegada —
  -- a 0168 só conseguia quando a ordem ajudava.
  if v_cnpj is not null then
    select e.id into v_id
    from entidade e
    where e.caso_id = p_caso_id and fn_cnpj_canonico(e.cnpj) = v_cnpj
    order by length(e.razao_social) desc, e.razao_social
    limit 1;

    -- O RASTRO É OBRIGATÓRIO AQUI, e a revisão desta fatia o achou faltando.
    -- Este é o ramo MAIS FORTE da função — funde sem olhar o nome — e era o
    -- único caminho de fusão sem uma linha em `evento_auditoria` (o (3b) grava
    -- `entidade_alias_fundido`, o de ambiguidade grava `entidade_ambigua`).
    --
    -- O cenário que torna isso perigoso é o MESMO template que já colou o
    -- endereço no nome: o rodapé do relatório traz o CNPJ do ESCRITÓRIO DE
    -- CONTABILIDADE, não o do emitente. Lido em documentos de três clientes do
    -- mesmo mandato, o primeiro cria a entidade e os outros dois caem nela sem
    -- comparar nome nenhum. É o dano da 0153 por uma porta nova — e sem o
    -- evento não haveria uma linha dizendo que "CONTABILIDADE X LTDA." foi
    -- respondido com "OMNIBEAUTY".
    if v_id is not null then
      if fn_entidade_canonica(
           (select e.razao_social from entidade e where e.id = v_id)
         ) is distinct from fn_entidade_canonica(trim(p_nome)) then
        insert into evento_auditoria (ator, acao, entidade_ref, depois)
        values ('sistema:entidade', 'entidade_cnpj_casou', 'entidade:' || v_id,
                jsonb_build_object('caso_id', p_caso_id, 'nome_procurado', trim(p_nome),
                                   'nome_mantido',
                                   (select e.razao_social from entidade e where e.id = v_id),
                                   'cnpj', v_cnpj,
                                   'porque', 'o CNPJ é o mesmo — o nome não foi consultado'));
      end if;
      return v_id;
    end if;
  end if;

  -- (1) exato pela forma canônica — não há o que desempatar.
  select c.entidade_id into v_id
  from fn_entidades_candidatas_cnpj(p_caso_id, p_nome, p_cnpj) c
  where c.exata
  order by c.razao_social
  limit 1;
  if v_id is not null then
    perform fn_entidade_aprender_cnpj(v_id, v_cnpj);
    return v_id;
  end if;

  -- (2)/(3) quantos APROXIMADOS existem?
  select count(*), string_agg(c.razao_social, ' × ' order by c.razao_social),
         array_agg(c.razao_social)
    into v_n, v_candidatos, v_nomes
  from fn_entidades_candidatas_cnpj(p_caso_id, p_nome, p_cnpj) c;

  -- APRENDER SÓ NO CASAMENTO EXATO, e este `return` SEM `aprender` é a
  -- correção mais importante que a revisão desta fatia trouxe. Este ramo é o
  -- casamento FROUXO (subsequência de prefixos) — é ele que faz "Metalúrgica"
  -- ser absorvido por "VERTENTES METALÚRGICA LTDA.". Deixá-lo GRAVAR o CNPJ
  -- transformaria um palpite de nome em identidade fiscal permanente:
  -- "Canastra" com o CNPJ do GRUPO CANASTRA (a holding, impressa no
  -- consolidado) seria absorvido pela subsidiária e escreveria nela o CNPJ da
  -- holding — e daí em diante TODO documento da holding cairia na subsidiária
  -- pelo ramo (0), sem olhar nome. A própria 0168 já diz que o nome que CHEGA é
  -- o que pode estar contaminado; o CNPJ do mesmo documento não pode ser
  -- promovido a identidade por um casamento que o nome só aproximou.
  if v_n = 1 then
    select c.entidade_id into v_id
    from fn_entidades_candidatas_cnpj(p_caso_id, p_nome, p_cnpj) c limit 1;
    return v_id;
  end if;

  -- (3b) 0168: dois ou mais candidatos que casam ENTRE SI não são ambiguidade.
  if v_n > 1 and fn_entidades_sao_um_grupo(v_nomes || trim(p_nome)) then
    select c.entidade_id into v_id
    from fn_entidades_candidatas_cnpj(p_caso_id, p_nome, p_cnpj) c
    order by length(c.razao_social) desc, c.razao_social
    limit 1;

    insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:entidade', 'entidade_alias_fundido', 'entidade:' || v_id,
            jsonb_build_object('caso_id', p_caso_id, 'nome_procurado', trim(p_nome),
                               'candidatos', v_candidatos, 'quantos', v_n,
                               'porque', 'os candidatos casam todos entre si — é um nome só, '
                                      || 'truncado de jeitos diferentes pela fonte'));
    -- Sem `aprender` pelo mesmo motivo do ramo acima, e aqui é PIOR: o nome que
    -- chega é justamente o truncado, o que pode trazer o endereço colado.
    return v_id;
  end if;

  insert into entidade (caso_id, razao_social, cnpj) values (p_caso_id, trim(p_nome), v_cnpj)
    returning id into v_id;

  -- NASCER COM CNPJ MERECE O MESMO RASTRO QUE APRENDER DEPOIS. É uma afirmação
  -- de identidade tirada de UM documento, que nunca mais é revisitada e que
  -- passa a mandar sobre todo nome — o mínimo honesto é ela aparecer no log.
  if v_cnpj is not null then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:entidade', 'entidade_cnpj_aprendido', 'entidade:' || v_id,
            jsonb_build_object('cnpj', v_cnpj, 'como', 'nasceu com ele'));
  end if;

  if v_n > 1 then
    -- A AMBIGUIDADE É REGISTRADA AQUI e virada em pendência por quem tem o
    -- documento na mão. Esta função não conhece documento.
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:entidade', 'entidade_ambigua', 'entidade:' || v_id,
            jsonb_build_object('caso_id', p_caso_id, 'nome_procurado', trim(p_nome),
                               'candidatos', v_candidatos, 'quantos', v_n,
                               -- O CNPJ VAI JUNTO, e a revisão achou ele faltando:
                               -- `fn_pendencia_entidade_ambigua` (0153) monta a descrição
                               -- a partir deste payload, e o analista lia "casa com mais de
                               -- uma empresa: A × B" sem o único número que decide — a
                               -- regra 1 pelo avesso (a nota existe e cala o dado).
                               'cnpj', v_cnpj));
  end if;

  return v_id;
end;
$$;

comment on function fn_upsert_entidade(p_caso_id uuid, p_nome text, p_cnpj text) is
  'Acha ou cria a entidade do caso (0030), sem ESCOLHER no empate (0153), com o nome truncado '
  'que casa com os outros fundido no mais completo (0168). 0169: o CNPJ manda — igual é a mesma '
  'empresa sem olhar o nome, diferente tira a candidata da lista, ausente não decide nada. O '
  'primeiro documento ensina a identidade, os demais a usam; nunca sobrescreve CNPJ já gravado.';

-- -----------------------------------------------------------------------------
-- fn_entidade_aprender_cnpj — grava o CNPJ na entidade que ainda não tem um.
--
-- Separada e nomeada porque ela é a peça que faz a regra 1 valer a partir do
-- SEGUNDO documento, e porque "nunca sobrescreve" é uma decisão, não um
-- detalhe: dois CNPJs diferentes na mesma entidade é divergência para humano,
-- e a regra 2 já os terá separado antes de chegar aqui.
-- -----------------------------------------------------------------------------
create or replace function fn_entidade_aprender_cnpj(p_entidade_id uuid, p_cnpj text)
returns void
language plpgsql
as $$
declare
  v_cnpj  text := fn_cnpj_canonico(p_cnpj);
  v_antes text;
begin
  if p_entidade_id is null or v_cnpj is null then return; end if;

  -- `cnpj is null`, NÃO `fn_cnpj_canonico(cnpj) is null`, e a diferença foi
  -- achada na revisão desta fatia: com o canônico, um CNPJ INVÁLIDO já gravado
  -- (um '36.193.378/0001' truncado por planilha, digitado por uma pessoa) seria
  -- SOBRESCRITO pelo número que a IA leu, e o comentário logo acima estaria
  -- mentindo. Coluna vazia é ausência; coluna com número ruim é um registro
  -- humano que só uma pessoa deve corrigir.
  select e.cnpj into v_antes from entidade e where e.id = p_entidade_id;

  update entidade set cnpj = v_cnpj
   where id = p_entidade_id and cnpj is null;

  if found then
    insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
    values ('sistema:entidade', 'entidade_cnpj_aprendido', 'entidade:' || p_entidade_id,
            jsonb_build_object('cnpj', v_antes),
            jsonb_build_object('cnpj', v_cnpj, 'como', 'aprendido de um documento posterior'));
  end if;
end;
$$;

comment on function fn_entidade_aprender_cnpj(uuid, text) is
  'Grava o CNPJ numa entidade que ainda não tem um, com rastro (0169). Nunca sobrescreve: dois '
  'CNPJs diferentes na mesma entidade é divergência para humano, não algo para a função resolver.';

-- AS TRÊS, e a revisão achou a terceira faltando: `fn_upsert_entidade` é
-- SECURITY INVOKER, então um chamador rodando como `authenticated` estouraria
-- `permission denied for function fn_entidade_aprender_cnpj` EXATAMENTE no ponto
-- em que o CNPJ seria aprendido. A suíte local roda como `postgres` e nunca veria.
grant execute on function fn_cnpj_canonico(text) to authenticated;
grant execute on function fn_entidade_aprender_cnpj(uuid, text) to authenticated;
grant execute on function fn_entidades_candidatas_cnpj(uuid, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- O BANCO PASSA A AFIRMAR A DOUTRINA, em vez de só a função obedecê-la.
--
-- "CNPJ igual é a mesma empresa DENTRO DO CASO" é a regra 1 desta migration, e
-- sem este índice o banco não a garantia: duas chamadas concorrentes de
-- `fn_upsert_entidade` para o mesmo caso e CNPJ passam ambas pelo `select` do
-- ramo (0) sem achar nada e ambas inserem. O nó de ingestão processa itens em
-- lote, então concorrência não é hipótese remota.
--
-- Seguro de aplicar: a coluna `entidade.cnpj` existe desde a 0001 e NUNCA foi
-- populada por caminho nenhum do produto — não há duplicata possível para o
-- índice recusar. `where cnpj is not null` porque ausência não colide com
-- ausência: um caso pode ter muitas entidades sem CNPJ.
-- -----------------------------------------------------------------------------
create unique index if not exists entidade_caso_cnpj_unico
  on entidade (caso_id, cnpj) where cnpj is not null;

comment on index entidade_caso_cnpj_unico is
  'A regra 1 da 0169 afirmada pelo BANCO: dentro de um caso, um CNPJ identifica UMA entidade. '
  'Sem ela, duas chamadas concorrentes de fn_upsert_entidade inserem as duas.';

-- -----------------------------------------------------------------------------
-- O CATÁLOGO DA SONDA — requisito de CORPO sobre `fn_upsert_entidade`.
-- -----------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('cnpj_e_identidade', '0169', 'corpo', 'fn_upsert_entidade',
   'fn_entidades_candidatas_cnpj', null,
   'Sem esta migration o sistema identifica empresa só pelo NOME, e o nome é o que a fonte '
   'trunca: no lote do caso "teste 143" a OMNIBEAUTY virou quatro linhas, e a 0168 só conseguiu '
   'fechar de quatro para três porque "…DE MARCAS" e "…DE SURUBIJU" não casam entre si. O que '
   'prova que são a mesma empresa é o CNPJ 36.193.378/0001-04, igual nos dois balanços. Sem o '
   'CNPJ como identidade, cada variante de grafia continua podendo virar uma empresa, e um '
   'balanço fica num bloco de coluna sozinho sem comparar com nada.',
   'bloqueante', 670)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0169', revisado_em = current_date,
       observacao = 'A 0169 troca a assinatura de fn_upsert_entidade (2 → 3 args, com DROP da '
                    'antiga: overload vivo derruba lote real com "function is not unique") e '
                    'acrescenta fn_cnpj_canonico, fn_entidades_candidatas_cnpj e '
                    'fn_entidade_aprender_cnpj. Requisito de corpo pelo nome da candidata '
                    'filtrada, que some num create or replace com o corpo velho. O '
                    'comportamento é provado no CI (cnpj_identidade.test.sql), inclusive a '
                    'propriedade de que CNPJ nulo não muda NADA da 0168.';

commit;

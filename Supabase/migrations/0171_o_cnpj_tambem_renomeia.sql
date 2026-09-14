-- =============================================================================
-- 0171 — O CNPJ também renomeia, não só funde
--
-- DECISÃO DO DONO, tomada em resposta direta depois da 0169/0170: quando o CNPJ
-- funde duas variantes de nome na mesma entidade, ela deveria também adotar o
-- nome MAIS COMPLETO entre os que já apareceram — hoje ela só funde e mantém o
-- nome de quem chegou primeiro, que pode ser o truncado ou o contaminado pelo
-- endereço (o caso real da OMNIBEAUTY: se "…DE SURUBIJU, 1930" chegasse antes
-- de "…DE MARCAS LTDA", o CNPJ fundiria as duas e o nome que sobraria no book
-- seria o do endereço colado).
--
-- A DOUTRINA QUE ISSO PRECISA RESPEITAR, e é a mesma da 0168: "o nome que
-- CHEGA pode estar contaminado" — só que agora o CNPJ já PROVOU que os dois
-- nomes são a mesma empresa, então a pergunta deixa de ser "que empresa é
-- essa" (a 0153 resolve isso) e passa a ser só "qual dos dois nomes é mais
-- limpo". Comprimento cru sozinho NÃO decide isso — é medido abaixo, com os
-- quatro nomes reais, que "SURUBIJU, 1930" (55 caracteres) é mais LONGO que
-- "MARCAS LTDA" (52) e mesmo assim é o nome ERRADO.
--
-- TRÊS SINAIS, EM ORDEM DE FORÇA — cada um só decide quando o de cima empatou:
--
--   1. CARA DE ENDEREÇO COLADO (vírgula seguida de número no fim — o padrão
--      exato de "SURUBIJU, 1930") NUNCA VENCE, mesmo sendo mais longo. É o
--      sinal mais forte porque é o mais específico ao defeito medido.
--   2. SUFIXO SOCIETÁRIO (LTDA, S.A., EIRELI, …) — o MESMO padrão que
--      `fn_entidade_canonica` já usa para reconhecer e tirar o sufixo (0030).
--      Um nome com sufixo é uma razão social mais completa que um sem.
--   3. COMPRIMENTO CRU — só desempata entre dois nomes que empataram nos dois
--      sinais acima. É o critério que a 0168 já usa sozinho para a fusão SEM
--      CNPJ (`order by length desc`), e continua certo ali porque naquele
--      caso não há CNPJ provando identidade — o risco é outro.
--
-- CONFERIDO CONTRA OS QUATRO NOMES REAIS (a ordem importa, e as duas ordens
-- estão medidas): "MARCAS LTDA" vence "SURUBIJU, 1930" nos dois sentidos de
-- chegada — o sinal 1 protege mesmo quando o nome contaminado chega DEPOIS e
-- é mais longo. "SURUBIJU" sozinho vence "SURUBIJU, 1930" pelo mesmo sinal.
-- "MARCAS LTDA" vence o truncado "…DE" pelo sinal 2.
--
-- ESCOPO: só o ramo (0) da 0169/0170 — o CNPJ IGUAL. Os ramos de casamento
-- APROXIMADO (0153/0168) continuam SEM renomear ao decidir, porque ali o CNPJ
-- não provou nada: é só um nome curto batendo com um nome comprido, e a
-- própria 0168 já escolhe o mais completo ENTRE OS QUE JÁ EXISTIAM (nunca o
-- que chega). Esta migration não toca esses ramos.
--
-- MUDANÇA NÃO É MEDIDA CONTRA UM LOTE REAL AINDA (limite desta sessão: sem
-- credencial de OpenAI nem acesso ao n8n) — é medida contra os nomes reais que
-- o dono já forneceu, determinística, sem IA envolvida nesta fatia.
--
-- Idempotente: `create or replace`.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- fn_nome_parece_ter_endereco_colado — vírgula + número no fim.
--
-- É o padrão EXATO de "SURUBIJU, 1930": o template do contador cola a linha de
-- endereço embaixo da razão social truncada, e a extração lê as duas juntas.
-- Não tenta reconhecer endereço em geral — só esta assinatura específica, que
-- é a que os dados reais mostraram. Um falso positivo aqui é uma razão social
-- que por acaso termina em "algo, 123", que é raro; um falso negativo (um
-- endereço colado sem vírgula) cai no sinal 2/3, que ainda funciona bem para
-- o caso real.
-- -----------------------------------------------------------------------------
create or replace function fn_nome_parece_ter_endereco_colado(p_nome text)
returns boolean
language sql
immutable
as $$
  select trim(p_nome) ~ ',\s*\d+\s*$';
$$;

comment on function fn_nome_parece_ter_endereco_colado(text) is
  '0171: vírgula seguida de número no fim do nome — o padrão exato de "…SURUBIJU, 1930", onde o '
  'template do contador colou a linha de endereço na razão social truncada.';

-- -----------------------------------------------------------------------------
-- fn_nome_tem_sufixo_societario — o MESMO padrão que fn_entidade_canonica usa.
--
-- Deliberadamente o mesmo regex da 0030 (`fn_entidade_canonica`), não um novo:
-- é a definição que o resto do sistema já usa para "isto é um sufixo
-- societário", e divergir aqui criaria dois conceitos de sufixo no mesmo
-- produto.
-- -----------------------------------------------------------------------------
create or replace function fn_nome_tem_sufixo_societario(p_nome text)
returns boolean
language sql
immutable
as $$
  -- A PONTUAÇÃO É ACHATADA ANTES, e isso DIVERGE de `fn_entidade_canonica` de
  -- propósito. A 0030 casa o sufixo ANTES de achatar a pontuação, com
  -- `s\s*a` — e `\s*` não casa PONTO. Medido: `S/A` e `SA` eram reconhecidos,
  -- **`S.A.` não**, que é a grafia mais comum das duas. A primeira versão
  -- desta função copiou o padrão da 0030 e herdou o buraco, enquanto o
  -- comentário afirmava cobrir S.A. — achado na revisão desta fatia.
  --
  -- O BURACO DA 0030 CONTINUA LÁ e NÃO é consertado aqui: `fn_entidade_canonica`
  -- é a base do casamento EXATO de todo o produto, e mexer nela reclassifica
  -- entidade em todo caso já aberto. O efeito medido é limitado — "ALFA S.A."
  -- e "ALFA" deixam de casar como EXATAS mas continuam casando por
  -- `fn_mesma_entidade` (aproximado), então o dano é degradar exato→aproximado,
  -- não perder o casamento. Fica declarado aqui, não corrigido de lado.
  select trim(regexp_replace(
           regexp_replace(fn_normalizar_texto(p_nome), '[.,;:/\\()''"-]', ' ', 'g'),
           '\s+', ' ', 'g'))
         ~ '\s(ltda|limitada|s a|sa|eireli|me|epp|mei|em recuperacao judicial|em rj)$';
$$;

comment on function fn_nome_tem_sufixo_societario(text) is
  '0171: o nome termina em sufixo societário (LTDA, S.A., S/A, EIRELI, …)? MESMA lista da '
  'fn_entidade_canonica (0030), mas achatando a pontuação ANTES de casar — sem isso "S.A." não '
  'é reconhecido (o ponto não é espaço), e era o caso da primeira versão desta função.';

-- -----------------------------------------------------------------------------
-- fn_nomes_compartilham_raiz — os dois nomes são o MESMO nome escrito diferente?
--
-- NÃO é `fn_mesma_entidade`, e a diferença foi MEDIDA: os dois nomes reais que
-- esta fatia existe para resolver — "…GESTAO DE MARCAS LTDA" e "…GESTAO DE
-- SURUBIJU, 1930" — **não casam** por `fn_mesma_entidade` ("marcas" não é
-- prefixo de "surubiju"), que é exatamente o achado que fez a 0168 parar em 3
-- entidades em vez de 1. Usar aquela função como guarda do renomeio bloquearia
-- justamente o caso motivador — medido, e foi assim que esta função nasceu.
--
-- O QUE ELA PERGUNTA: os dois nomes começam igual por tempo suficiente para
-- serem o mesmo nome truncado de jeitos diferentes? O critério é o PREFIXO
-- COMUM de tokens, na forma canônica, com duas exigências:
--   • pelo menos um token significativo (4+ caracteres) no prefixo comum — a
--     mesma régua de significância que `fn_mesma_entidade` (0030) já usa, para
--     "de"/"e"/"do" não fundarem parentesco;
--   • o prefixo comum cobre pelo menos METADE dos tokens do nome mais curto.
--
-- MEDIDO CONTRA OS QUATRO CASOS REAIS, e cada um cai do lado certo:
--   • "…GESTAO DE MARCAS" × "…GESTAO DE SURUBIJU 1930" → prefixo 5 de 6 → SIM
--   • "ALFA COMERCIO" × "ALFA COMERCIO LTDA"           → prefixo 2 de 2 → SIM
--   • "ARAUCARIA BIOENERGIA SPE" × "ARAUCARIA IMOBILIARIA SPE" → 1 de 3 → NÃO
--   • "PADARIA DO JOAO" × "METALURGICA SAO PEDRO"      → 0        → NÃO
--
-- O terceiro é o que importa: duas SPEs distintas que compartilham só a
-- primeira palavra NÃO autorizam reescrever o nome de uma com o da outra, mesmo
-- que um CNPJ errado as tenha fundido. O quarto é o cenário do CNPJ do
-- escritório de contabilidade.
-- -----------------------------------------------------------------------------
create or replace function fn_nomes_compartilham_raiz(p_a text, p_b text)
returns boolean
language plpgsql
immutable
as $$
declare
  a                 text[] := string_to_array(fn_entidade_canonica(p_a), ' ');
  b                 text[] := string_to_array(fn_entidade_canonica(p_b), ' ');
  n                 int := 0;
  menor             int;
  i                 int;
  tem_significativo boolean := false;
begin
  if a is null or b is null then return false; end if;
  menor := least(coalesce(array_length(a, 1), 0), coalesce(array_length(b, 1), 0));
  if menor = 0 then return false; end if;

  for i in 1 .. menor loop
    exit when a[i] is distinct from b[i];
    n := n + 1;
    if length(a[i]) >= 4 then tem_significativo := true; end if;
  end loop;

  return tem_significativo and n * 2 >= menor;
end;
$$;

comment on function fn_nomes_compartilham_raiz(text, text) is
  '0171: os dois nomes são o MESMO nome escrito diferente? Prefixo comum de tokens cobrindo pelo '
  'menos metade do nome mais curto, com um token significativo (4+) dentro. NÃO é '
  'fn_mesma_entidade — aquela devolve FALSO para "…DE MARCAS" × "…DE SURUBIJU, 1930", que são o '
  'caso real desta fatia; esta devolve VERDADEIRO. E devolve FALSO para Araucária Bioenergia × '
  'Imobiliária, que compartilham só a primeira palavra.';

grant execute on function fn_nomes_compartilham_raiz(text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_entidade_nome_mais_completo — o desempate de três sinais do cabeçalho.
-- -----------------------------------------------------------------------------
create or replace function fn_entidade_nome_mais_completo(p_atual text, p_novo text)
returns text
language sql
immutable
as $$
  select case
    -- (1) cara de endereço colado nunca vence, mesmo mais longo.
    when fn_nome_parece_ter_endereco_colado(p_novo)
     and not fn_nome_parece_ter_endereco_colado(p_atual) then p_atual
    when fn_nome_parece_ter_endereco_colado(p_atual)
     and not fn_nome_parece_ter_endereco_colado(p_novo) then p_novo
    -- (2) sufixo societário vence quem não tem.
    when fn_nome_tem_sufixo_societario(p_novo)
     and not fn_nome_tem_sufixo_societario(p_atual) then p_novo
    when fn_nome_tem_sufixo_societario(p_atual)
     and not fn_nome_tem_sufixo_societario(p_novo) then p_atual
    -- (3) empatados nos dois sinais acima: comprimento cru desempata.
    when length(trim(p_novo)) > length(trim(p_atual)) then p_novo
    else p_atual
  end;
$$;

comment on function fn_entidade_nome_mais_completo(text, text) is
  '0171: entre dois nomes que o CNPJ já provou serem a MESMA empresa, qual fica. Três sinais em '
  'ordem: cara de endereço colado (nunca vence, mesmo mais longo) > sufixo societário > '
  'comprimento cru. Sem isso, "SURUBIJU, 1930" (55 chars) venceria "MARCAS LTDA" (52) só por ser '
  'mais longo — e é o nome ERRADO.';

grant execute on function fn_nome_parece_ter_endereco_colado(text) to authenticated;
grant execute on function fn_nome_tem_sufixo_societario(text) to authenticated;
grant execute on function fn_entidade_nome_mais_completo(text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_upsert_entidade — corpo da 0169/0170 com o renomeio do ramo (0).
-- -----------------------------------------------------------------------------
create or replace function fn_upsert_entidade(p_caso_id uuid, p_nome text, p_cnpj text DEFAULT NULL::text) RETURNS uuid
language plpgsql
as $$
declare
  v_id         uuid;
  v_n          int;
  v_candidatos text;
  v_nomes      text[];
  v_cnpj       text := fn_cnpj_canonico(p_cnpj);
  v_nome_atual text;
  v_nome_novo  text;
begin
  -- 0153: no empate, não escolhe. (E o requisito de sonda `entidade_ambigua_nao_decide`
  -- tem o literal "0153" como MARCADOR DE CORPO — tirar esta linha derruba a sonda
  -- sem mudar comportamento nenhum. Achado ao rodar a suíte desta fatia.)
  if p_nome is null or length(trim(p_nome)) = 0 then return null; end if;

  -- (0) 0169: CNPJ IGUAL É A MESMA EMPRESA, e ele não pergunta o nome. É esta
  -- regra que funde as variantes truncadas em QUALQUER ordem de chegada —
  -- a 0168 só conseguia quando a ordem ajudava.
  if v_cnpj is not null then
    -- `order by` sem efeito prático desde a 0169: o índice único
    -- `entidade_caso_cnpj_unico (caso_id, cnpj)` garante NO MÁXIMO uma linha.
    -- Fica como documentação da invariante, não como desempate de verdade.
    select e.id, e.razao_social into v_id, v_nome_atual
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
      -- O EVENTO DE CASAMENTO fica na forma CANÔNICA: ele existe para registrar
      -- que o CNPJ respondeu um nome MATERIALMENTE diferente do gravado, e
      -- diferença só de sufixo/pontuação não é isso.
      if fn_entidade_canonica(v_nome_atual) is distinct from fn_entidade_canonica(trim(p_nome)) then
        insert into evento_auditoria (ator, acao, entidade_ref, depois)
        values ('sistema:entidade', 'entidade_cnpj_casou', 'entidade:' || v_id,
                jsonb_build_object('caso_id', p_caso_id, 'nome_procurado', trim(p_nome),
                                   'nome_mantido_antes_do_renomeio', v_nome_atual,
                                   'cnpj', v_cnpj,
                                   'compartilham_raiz', fn_nomes_compartilham_raiz(v_nome_atual, trim(p_nome)),
                                   'porque', 'o CNPJ é o mesmo — o nome não foi consultado'));
      end if;

      -- 0171: O CNPJ TAMBÉM PODE RENOMEAR, não só fundir — com TRÊS guardas, e
      -- as três nasceram da revisão desta fatia, cada uma de um defeito medido.
      --
      -- O RENOMEIO FICA FORA DA GUARDA CANÔNICA ACIMA (defeito 1 medido): a
      -- canônica TIRA o sufixo societário, então "ALFA COMERCIO" e "ALFA
      -- COMERCIO LTDA" são canonicamente IGUAIS — e o renomeio, aninhado
      -- naquele `if`, nunca rodava justamente no caso em que o sinal 2 (sufixo)
      -- existe para decidir. Medido: o nome final ficava "ALFA COMERCIO".
      v_nome_novo := fn_entidade_nome_mais_completo(v_nome_atual, trim(p_nome));

      if v_nome_novo is distinct from v_nome_atual
         -- GUARDA 1 (defeito 2 medido): SÓ RENOMEIA ENTRE NOMES DA MESMA RAIZ.
         -- O CNPJ basta para FUNDIR (é a regra 1 da 0169, e o dono a aprovou),
         -- mas não basta para reescrever o nome: o cenário do rodapé com o CNPJ
         -- do ESCRITÓRIO DE CONTABILIDADE — descrito no cabeçalho desta própria
         -- função — fazia "PADARIA DO JOAO LTDA" virar "METALURGICA SAO PEDRO
         -- COMERCIO LTDA", medido. Antes da 0171 a fusão errada pelo menos
         -- PRESERVAVA o nome; o renomeio piorava o dano em vez de melhorá-lo.
         -- Quando os nomes não compartilham raiz, o `entidade_cnpj_casou` acima
         -- já registrou o casamento suspeito e é ELE que o humano lê.
         --
         -- `fn_nomes_compartilham_raiz` e NÃO `fn_mesma_entidade`: a primeira
         -- versão desta guarda usou a segunda e BLOQUEOU O CASO MOTIVADOR —
         -- medido, o nome final da OMNIBEAUTY voltou a ser "…SURUBIJU, 1930".
         -- Ver o cabeçalho da função nova para as quatro medições.
         and fn_nomes_compartilham_raiz(v_nome_atual, trim(p_nome))
         -- GUARDA 2 (defeito 3 medido): NÃO CRIA HOMÔNIMA. Sem isto, o renomeio
         -- deixava DUAS entidades do mesmo caso com a razão social idêntica, e
         -- o ramo (1) — casamento exato — passava a escolher uma delas por
         -- `order by razao_social limit 1`, empate puro entre strings iguais,
         -- SEM registrar ambiguidade nenhuma. Medido: 2 entidades homônimas, 0
         -- eventos. É o defeito silencioso clássico deste projeto — os
         -- documentos se dividem entre duas linhas que a tela mostra como uma.
         and not exists (
           select 1 from entidade e2
           where e2.caso_id = p_caso_id and e2.id <> v_id
             and fn_entidade_canonica(e2.razao_social) = fn_entidade_canonica(v_nome_novo))
      then
        update entidade set razao_social = v_nome_novo where id = v_id;
        insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
        values ('sistema:entidade', 'entidade_renomeada_por_cnpj', 'entidade:' || v_id,
                jsonb_build_object('razao_social', v_nome_atual),
                jsonb_build_object('razao_social', v_nome_novo, 'cnpj', v_cnpj,
                                   'porque', 'nome mais completo pela mesma empresa (CNPJ)'));

      elsif v_nome_novo is distinct from v_nome_atual then
        -- RECUSA COM RASTRO, e não em silêncio. Chegar aqui significa que o
        -- nome que veio ERA mais completo e mesmo assim não foi adotado — ou
        -- porque não é variante do gravado (CNPJ suspeito), ou porque adotá-lo
        -- criaria uma homônima (duas entidades que provavelmente deveriam ser
        -- UMA). As duas coisas são informação para quem revisa; nenhuma delas
        -- pode ser decidida por esta função, que não conhece documento.
        insert into evento_auditoria (ator, acao, entidade_ref, depois)
        values ('sistema:entidade', 'entidade_renomeio_recusado', 'entidade:' || v_id,
                jsonb_build_object('caso_id', p_caso_id, 'razao_social_mantida', v_nome_atual,
                                   'razao_social_recusada', v_nome_novo, 'cnpj', v_cnpj,
                                   'compartilham_raiz', fn_nomes_compartilham_raiz(v_nome_atual, trim(p_nome)),
                                   'homonima_existiria', exists (
                                     select 1 from entidade e2
                                     where e2.caso_id = p_caso_id and e2.id <> v_id
                                       and fn_entidade_canonica(e2.razao_social)
                                           = fn_entidade_canonica(v_nome_novo))));
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
  'fundido no mais completo (0168), com o CNPJ como identidade (0169). 0171: quando o CNPJ funde '
  'duas variantes de nome, adota a mais completa entre elas (fn_entidade_nome_mais_completo) — '
  'com rastro em entidade_renomeada_por_cnpj. Os ramos de casamento aproximado (sem CNPJ) '
  'continuam sem renomear ao decidir: ali o CNPJ não provou identidade nenhuma.';

-- -----------------------------------------------------------------------------
-- O CATÁLOGO DA SONDA — requisito de CORPO sobre o marcador do renomeio.
-- -----------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('cnpj_renomeia', '0171', 'corpo', 'fn_upsert_entidade',
   'fn_entidade_nome_mais_completo', null,
   'Sem esta migration, o CNPJ funde entidades mas mantém o nome de quem chegou primeiro — que '
   'pode ser o nome truncado ou contaminado pelo endereço (o caso real: "…DE SURUBIJU, 1930", que '
   'é MAIS LONGO que o nome certo "…DE MARCAS LTDA" e venceria por comprimento cru sozinho). Sem '
   'o desempate por sufixo societário e cara de endereço, o book do cliente mostraria o nome '
   'errado mesmo depois de as quatro linhas terem sido corretamente fundidas em uma.',
   'bloqueante', 690)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0171', revisado_em = current_date,
       observacao = 'A 0171 acrescenta fn_nome_parece_ter_endereco_colado, '
                    'fn_nome_tem_sufixo_societario e fn_entidade_nome_mais_completo, e muda o '
                    'ramo (0) de fn_upsert_entidade para renomear ao fundir por CNPJ. Requisito '
                    'de corpo pelo nome da função de desempate, que some num create or replace '
                    'com o corpo velho. Provado no CI (cnpj_renomeia.test.sql) com os quatro '
                    'nomes reais da OMNIBEAUTY, nas duas ordens de chegada.';

commit;

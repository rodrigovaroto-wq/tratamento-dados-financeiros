-- 0030 — Canonicalizar entidade e período no caminho de ESCRITA
--
-- Três defeitos com a mesma forma: o dado é gravado CRU, a comparação depois é
-- feita de um jeito mais esperto, e o descasamento entre os dois produz duplicata
-- ou "não achei" — sempre em silêncio.
--
-- 1. ENTIDADE DUPLICADA NA BASE — e é uma regressão que EU introduzi no PR #65.
--    `fn_registrar_documento` casa entidade por `lower(razao_social)`, sem
--    `unaccent` e sem tirar pontuação nem sufixo societário. Antes do #65 isso
--    quase sempre dava certo, porque a entidade vinha de UMA fonte só (o
--    diagnóstico da extração). Depois do #65 ela vem de DUAS, e elas escrevem
--    diferente:
--      • nome do arquivo   → "Vertentes Metalurgica"        (sem acento, porque
--        `n8n/lib/normalize.mjs` remove diacríticos de propósito)
--      • diagnóstico da IA → "Vertentes Metalúrgica Ltda."
--    `lower()` não aproxima os dois ⇒ DUAS linhas `entidade` para a mesma empresa
--    ⇒ o export conta cada uma como coluna própria e qualquer soma do grupo
--    duplica. O export já mascarava o sintoma (`consolidarNomesDeEntidade`), e é
--    exatamente por isso que a duplicidade na base passou sem ser vista.
--
-- 2. `fn_coluna_entidade` CASA POR IGUALDADE EXATA — é a causa da pendência
--    "não foi possível localizar a linha de Ativo Total / Passivo+PL" que apareceu
--    no teste v31. No balanço COMBINADO os cabeçalhos de coluna são apelidos
--    curtos ("Metalúrgica", "Componentes", "VT Logística") e `razao_social` é a
--    razão completa ("VERTENTES METALÚRGICA LTDA.") ⇒ nunca casa ⇒ a função
--    devolve o sentinela `E'\x01'` ⇒ `fn_valor_conceito_col` e `fn_soma_secao` não
--    retornam nada ⇒ `v_n_anos = 0` ⇒ pendência de pré-condição. Os rótulos em si
--    estavam certos: "TOTAL DO ATIVO" casa os padrões desde sempre.
--    O portal RESOLVE isso há tempos com casamento por token com prefixo
--    (`consolidarNomesDeEntidade`, portal/src/lib/export.ts). O banco não tinha
--    equivalente — as duas metades do mesmo problema, uma resolvida e uma não.
--
-- 3. PERÍODO GRAVADO CRU FRAGMENTA O EXERCÍCIO. `referencia = p_periodo_ref` sem
--    canonicalizar: '2025' e '12M25' são o MESMO exercício e viram duas linhas em
--    `periodo`. A `0022` canonicaliza na COMPARAÇÃO (`fn_periodos_equivalentes`),
--    o que faz a reconciliação achar o par — mas o dashboard, o checklist e o
--    export continuam vendo dois períodos, e o documento fica ligado a um deles.
--
-- Idempotente: `create or replace` + a consolidação de duplicatas é condicional.

begin;

-- ---------------------------------------------------------------------------
-- Forma canônica de um nome de entidade, para CASAMENTO (não para exibição).
--
-- Tira o que varia entre fontes sem mudar quem a empresa é: acento, pontuação,
-- espaço repetido e sufixo societário. O que sobra é o núcleo do nome.
--
-- NÃO é o nome que aparece na tela: `razao_social` continua guardando a grafia
-- que a fonte trouxe. Canonicalizar para exibir apagaria informação real.
-- ---------------------------------------------------------------------------
create or replace function fn_entidade_canonica(p_nome text)
returns text
language sql
immutable
as $$
  select nullif(
    trim(regexp_replace(
      regexp_replace(
        -- sufixos societários, no FIM do nome (é onde eles aparecem). 'spe' e
        -- 'scp' NÃO entram: em "Vertentes Imóveis SPE" a sigla faz parte do nome
        -- da sociedade de propósito específico, e tirá-la funde SPEs diferentes.
        regexp_replace(fn_normalizar_texto(p_nome),
          '\s+(ltda|limitada|s\s*a|sa|s\s*/\s*a|eireli|me|epp|mei|em recuperacao judicial|em rj)\.?\s*$',
          '', 'g'),
        '[.,;:/\\()''"-]', ' ', 'g'),
      '\s+', ' ', 'g')),
    '');
$$;

comment on function fn_entidade_canonica(text) is
  'Forma canônica de nome de entidade para CASAMENTO: sem acento, pontuação nem sufixo '
  'societário. Não substitui razao_social, que preserva a grafia da fonte.';

-- ---------------------------------------------------------------------------
-- Dois nomes são a MESMA entidade?
--
-- Porta o critério que o portal já usa (`consolidarNomesDeEntidade`): igualdade
-- canônica OU todo token do nome CURTO é prefixo de algum token do LONGO, na
-- ordem. É o que faz "Metalúrgica" casar "VERTENTES METALÚRGICA LTDA." e
-- "Part." casar "Participações" — sem fazer "Componentes" casar "Participações",
-- porque 'compon' não é prefixo de 'particip'.
--
-- Exige pelo menos UM token com 4+ caracteres no lado curto: sem isso, um apelido
-- de duas letras casaria meia base, e fundir entidades diferentes é o erro mais
-- caro possível aqui (pior que não casar, que só abre pendência).
-- ---------------------------------------------------------------------------
create or replace function fn_mesma_entidade(p_a text, p_b text)
returns boolean
language plpgsql
immutable
as $$
declare
  a text := fn_entidade_canonica(p_a);
  b text := fn_entidade_canonica(p_b);
  curto text[]; longo text[];
  i int; j int; achou boolean;
begin
  if a is null or b is null then return false; end if;
  if a = b then return true; end if;

  if length(a) <= length(b) then
    curto := string_to_array(a, ' '); longo := string_to_array(b, ' ');
  else
    curto := string_to_array(b, ' '); longo := string_to_array(a, ' ');
  end if;

  -- Token significativo no lado curto (4+ chars). "vt logistica" passa por
  -- 'logistica'; um apelido "ab" não passa, e é isso que se quer.
  if not exists (select 1 from unnest(curto) t where length(t) >= 4) then
    return false;
  end if;

  j := 1;
  for i in 1 .. array_length(curto, 1) loop
    achou := false;
    while j <= array_length(longo, 1) loop
      if longo[j] like curto[i] || '%' then
        achou := true; j := j + 1; exit;
      end if;
      j := j + 1;
    end loop;
    if not achou then return false; end if;
  end loop;
  return true;
end;
$$;

comment on function fn_mesma_entidade(text, text) is
  'Dois nomes são a mesma entidade? Igualdade canônica ou tokens do nome curto como '
  'prefixo dos do longo, em ordem (mesmo critério de consolidarNomesDeEntidade no portal).';

-- ---------------------------------------------------------------------------
-- Defeito 2: fn_coluna_entidade deixa de exigir igualdade exata.
-- Mesma função da 0023, com uma linha diferente — e é essa linha que faz a
-- reconciliação do balanço combinado sair da pré-condição.
-- ---------------------------------------------------------------------------
create or replace function fn_coluna_entidade(p_documento_versao_id uuid, p_entidade_id uuid)
returns text
language plpgsql
as $$
declare
  v_tem_col boolean;
  v_razao   text;
  v_col     text;
  v_dono    boolean;
begin
  select exists (
    select 1 from campo_extraido ce
    where ce.documento_versao_id = p_documento_versao_id and ce.entidade_coluna is not null
  ) into v_tem_col;
  if not v_tem_col then return null; end if;

  select e.razao_social into v_razao from entidade e where e.id = p_entidade_id;
  if v_razao is not null then
    -- 0030: era `fn_normalizar_texto(ce.entidade_coluna) = fn_normalizar_texto(v_razao)`.
    -- Igualdade exata nunca casa apelido de coluna com razão social completa, que é
    -- o formato NORMAL de um balanço combinado.
    select ce.entidade_coluna into v_col
    from campo_extraido ce
    where ce.documento_versao_id = p_documento_versao_id
      and ce.entidade_coluna is not null
      and fn_mesma_entidade(ce.entidade_coluna, v_razao)
    limit 1;
    if v_col is not null then return v_col; end if;
  end if;

  select (d.entidade_id = p_entidade_id) into v_dono
  from documento_versao dv join documento d on d.id = dv.documento_id
  where dv.id = p_documento_versao_id;

  if coalesce(v_dono, false) then
    -- Total do próprio documento. Mesmo vocabulário de `tipoColunaNaoEntidade`
    -- em portal/src/lib/export.ts, para o portal e o banco concordarem.
    select ce.entidade_coluna into v_col
    from campo_extraido ce
    where ce.documento_versao_id = p_documento_versao_id
      and ce.entidade_coluna is not null
      and fn_normalizar_texto(ce.entidade_coluna) ~ '^(combinad|consolidad|total|soma)'
    limit 1;
    if v_col is not null then return v_col; end if;
  end if;

  return E'\x01';
end;
$$;

-- ---------------------------------------------------------------------------
-- Defeitos 1 e 3: casar entidade e período por forma canônica.
--
-- Os dois passos viram funções próprias (`fn_upsert_entidade` / `fn_upsert_periodo`)
-- e `fn_registrar_documento` é redefinida com o corpo EXATO da 0026, trocando só as
-- duas buscas por chamadas a elas. Extrair os passos em vez de embutir a lógica é
-- o que permite testá-los sozinhos — e o que evita repetir o erro da 0006, que
-- recriou um corpo antigo por inteiro e regrediu funções silenciosamente.
-- ---------------------------------------------------------------------------
create or replace function fn_upsert_entidade(p_caso_id uuid, p_nome text)
returns uuid
language plpgsql
as $$
declare v_id uuid;
begin
  if p_nome is null or length(trim(p_nome)) = 0 then return null; end if;

  -- Casa pela forma CANÔNICA: é o que impede "Vertentes Metalurgica" (do nome do
  -- arquivo, sem acento) e "Vertentes Metalúrgica Ltda." (do diagnóstico) de virarem
  -- duas empresas. Ordena por criado_em para ser determinístico quando a base já
  -- tem duplicata de antes desta migration.
  select e.id into v_id
  from entidade e
  where e.caso_id = p_caso_id and fn_mesma_entidade(e.razao_social, p_nome)
  -- `entidade` não tem coluna de data; ordenar pela razão social torna a escolha
  -- DETERMINÍSTICA quando a base já carrega duplicata de antes desta migration.
  -- Sem ordem explícita, dois documentos do mesmo lote poderiam se ligar a linhas
  -- diferentes da mesma empresa — a duplicidade sobreviveria à própria correção.
  order by e.razao_social
  limit 1;

  if v_id is null then
    insert into entidade (caso_id, razao_social) values (p_caso_id, trim(p_nome))
      returning id into v_id;
  end if;
  return v_id;
end;
$$;

create or replace function fn_upsert_periodo(p_caso_id uuid, p_tipo text, p_ref text)
returns uuid
language plpgsql
as $$
declare
  v_id  uuid;
  v_can text;
begin
  if p_ref is null or length(trim(p_ref)) = 0 then return null; end if;
  v_can := fn_periodo_canonico(coalesce(p_tipo, 'outro'), p_ref);

  -- Casa por forma CANÔNICA: '2025' e '12M25' são o mesmo exercício e não podem
  -- virar duas linhas. A 0022 já canonicalizava na comparação; aqui é na ESCRITA,
  -- que é o que faz o dashboard, o checklist e o export verem um período só.
  select p.id into v_id
  from periodo p
  where p.caso_id = p_caso_id
    and fn_periodo_canonico(p.tipo, p.referencia) = v_can
  order by p.referencia
  limit 1;

  if v_id is null then
    insert into periodo (caso_id, tipo, referencia)
      values (p_caso_id, coalesce(p_tipo, 'outro'), trim(p_ref))
      returning id into v_id;
  end if;
  return v_id;
end;
$$;

comment on function fn_upsert_entidade(uuid, text) is
  'Acha ou cria a entidade casando pela forma canônica (0030). Impede duplicata quando '
  'o nome vem do arquivo (sem acento) e do diagnóstico (com acento e sufixo).';
comment on function fn_upsert_periodo(uuid, text, text) is
  'Acha ou cria o período casando pela forma canônica (0030). Impede que 2025 e 12M25 '
  'virem dois exercícios.';

-- fn_registrar_documento: corpo da 0026 com as duas buscas trocadas pelas
-- auxiliares canônicas acima. Nada mais muda.
create or replace function fn_registrar_documento(
  p_caso_id        uuid,
  p_entidade_nome  text,
  p_periodo_tipo   text,
  p_periodo_ref    text,
  p_tipo_taxonomia text,
  p_confianca      numeric,
  p_fonte          text,
  p_origem_arquivo origem_arquivo,
  p_arquivo_ref    text,
  p_nome_original  text,
  p_assinado       boolean,
  p_hash           text,
  p_legibilidade   legibilidade,
  p_threshold      numeric default 0.7,
  p_justificativa  text default null
)
returns jsonb
language plpgsql
as $$
declare
  v_entidade_id uuid;
  v_periodo_id  uuid;
  v_documento_id uuid;
  v_versao_id   uuid;
  v_n_versao    int := 1;
  v_obrig obrigatoriedade;
  v_reaproveitou boolean := false;
begin
  -- 0030: casamento por forma CANÔNICA. Era `lower(razao_social) = lower(...)`, e
  -- desde o PR #65 a entidade vem de duas fontes que escrevem diferente ("Vertentes
  -- Metalurgica" do nome do arquivo, sem acento; "Vertentes Metalúrgica Ltda." do
  -- diagnóstico) — `lower()` não aproxima as duas e criava DUAS empresas.
  v_entidade_id := fn_upsert_entidade(p_caso_id, p_entidade_nome);

  -- 0030: idem para período. '2025' e '12M25' são o MESMO exercício; gravar cru
  -- fragmentava em duas linhas `periodo` e o documento ficava ligado a uma delas.
  v_periodo_id := fn_upsert_periodo(p_caso_id, p_periodo_tipo, p_periodo_ref);

  -- Já existe ESTE arquivo (mesmo hash) neste caso? Então é reextração/reenvio:
  -- versão nova sob o mesmo documento. Hash nulo nunca casa (ver cabeçalho).
  if p_hash is not null and length(trim(p_hash)) > 0 then
    select dv.documento_id into v_documento_id
    from documento_versao dv
    join documento d on d.id = dv.documento_id
    where d.caso_id = p_caso_id and dv.hash = p_hash
    order by dv.criada_em desc
    limit 1;
    v_reaproveitou := v_documento_id is not null;
  end if;

  if v_reaproveitou then
    select coalesce(max(n_versao), 0) + 1 into v_n_versao
      from documento_versao where documento_id = v_documento_id;
    -- A classificação da versão nova prevalece SOBRE A DO SISTEMA, nunca sobre a
    -- do humano: se alguém já revisou este documento na fila (`fonte='humano'`,
    -- `db/migrations/0008`), a reextração não desfaz a decisão dele — é a
    -- anti-ancoragem de sempre (docs/01), no sentido que importa: máquina não
    -- sobrepõe humano. Entidade/período seguem a mesma regra.
    update documento d set
      tipo_taxonomia = case when d.fonte = 'humano' then d.tipo_taxonomia else p_tipo_taxonomia end,
      entidade_id    = case when d.fonte = 'humano' then d.entidade_id else coalesce(v_entidade_id, d.entidade_id) end,
      periodo_id     = case when d.fonte = 'humano' then d.periodo_id else coalesce(v_periodo_id, d.periodo_id) end,
      confianca      = case when d.fonte = 'humano' then d.confianca else p_confianca end,
      fonte          = case when d.fonte = 'humano' then d.fonte else p_fonte end,
      justificativa  = case when d.fonte = 'humano' then d.justificativa else p_justificativa end,
      status         = case when d.fonte = 'humano' then d.status else 'em_validacao' end
    where d.id = v_documento_id;
  else
    insert into documento (caso_id, entidade_id, periodo_id, tipo_taxonomia, status, confianca, fonte, justificativa)
      values (p_caso_id, v_entidade_id, v_periodo_id, p_tipo_taxonomia, 'em_validacao', p_confianca, p_fonte, p_justificativa)
      returning id into v_documento_id;
  end if;

  insert into documento_versao
    (documento_id, n_versao, origem_arquivo, arquivo_ref, nome_original, assinado, hash, legibilidade)
    values (v_documento_id, v_n_versao, coalesce(p_origem_arquivo,'supabase_storage'),
            p_arquivo_ref, p_nome_original, p_assinado, p_hash, p_legibilidade)
    returning id into v_versao_id;

  -- Checklist: só na PRIMEIRA vez. Reextração não é documento novo — inserir de
  -- novo daria dois itens "presente" para o mesmo documento e inflaria a
  -- completude com um arquivo só (a `unique` do checklist não cobre isso porque
  -- `documento_id` faz parte da linha).
  if p_tipo_taxonomia is not null and not v_reaproveitou then
    select obrigatoriedade into v_obrig from taxonomia_tipo_documento where codigo = p_tipo_taxonomia;
    insert into checklist_item_status
      (caso_id, entidade_id, periodo_id, tipo_taxonomia, obrigatoriedade, status, documento_id)
      values (p_caso_id, v_entidade_id, v_periodo_id, p_tipo_taxonomia,
              coalesce(v_obrig,'complementar'), 'presente', v_documento_id);
  end if;

  -- Pendência de classificação incerta: idempotente por documento. Antes cada
  -- reenvio abria mais uma (documento novo, pendência nova); agora, se já existe
  -- uma aberta para este documento, ela continua sendo a mesma pendência — a
  -- reextração não multiplica cartões na fila do dono.
  if p_tipo_taxonomia is null or coalesce(p_confianca,0) < p_threshold then
    if not exists (
      select 1 from pendencia p
      where p.documento_id = v_documento_id
        and p.tipo = 'classificacao_pendente'
        and p.estado <> 'resolvida'
    ) then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id)
        values (p_caso_id, 'classificacao', 'classificacao_pendente', 'importante', true,
                format('Classificação incerta (conf=%s, fonte=%s) para "%s". Motivo: %s',
                       coalesce(p_confianca,0), coalesce(p_fonte,'?'), coalesce(p_nome_original,'?'),
                       coalesce(nullif(trim(p_justificativa), ''), 'nenhuma justificativa fornecida')),
                v_documento_id);
    end if;
  end if;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:n8n',
            case when v_reaproveitou then 'documento_reextraido' else 'documento_registrado' end,
            'documento:'||v_documento_id,
            jsonb_build_object('tipo', p_tipo_taxonomia, 'confianca', p_confianca, 'fonte', p_fonte,
                               'justificativa', p_justificativa, 'n_versao', v_n_versao,
                               'hash', p_hash));

  return jsonb_build_object(
    'documento_id', v_documento_id,
    'documento_versao_id', v_versao_id,
    'n_versao', v_n_versao,
    'reaproveitou_documento', v_reaproveitou
  );
end;
$$;

commit;

-- =============================================================================
-- 0179 — fatia 1.3 do plano F1: `entidade.papel_no_grupo` tipado E preenchido
--
-- O DEFEITO, medido em 18/09/2026 contra o schema e contra produção (seção
-- 12.1 de `Arquitetura do Sistema/3 Estado e Execução/ARQUITETURA_ALVO_E_ROADMAP.md`):
-- `papel_no_grupo` (0001) é `text` livre desde a PRIMEIRA migration deste
-- repositório — 178 migrations atrás — e está **NULL em TODO caso do banco**,
-- não só no mandato AMO. Isso não é lacuna de um mandato: é ausência de
-- CAMINHO DE ESCRITA em qualquer lugar do pipeline. A coluna existe, logo quem
-- lê o schema conclui que "o papel no grupo está modelado" — a regra 7 do
-- CLAUDE.md na forma mais cara, porque o dado diz o contrário do que a
-- presença da coluna sugere. Os DOIS ÚNICOS lugares do repositório com o
-- valor não-nulo são as fixtures SQL literais dos books (`fixture_book_canastra.sql`,
-- `fixture_book_vertentes.sql`) — escritas à mão para o export, não produzidas
-- por função nenhuma (achado da fatia 1.1, `f42f3cf`).
--
-- A ARMADILHA QUE ISSO TROUXE PARA ESTA MIGRATION: as duas fixtures gravavam o
-- literal `'alvo'` para TODAS as entidades, indistintamente — um placeholder
-- de quem escreveu a fixture, não uma classificação de papel. `'alvo'` não bate
-- nenhum dos 5 rótulos do enum novo (holding/operacional/veiculo/coligada/
-- fora_do_perimetro), e o `alter column ... using papel_no_grupo::entidade_papel_no_grupo`
-- quebraria com QUALQUER valor fora do enum já presente na tabela — e as
-- fixtures são carregadas pelo próprio `Supabase/test/run.sh` antes dos testes,
-- então a suíte inteira reprovaria na aplicação desta migration, não num
-- assert. A correção NÃO foi um WHERE silencioso descartando o valor (regra 1
-- do CLAUDE.md pelo avesso): os dois geradores (`Supabase/test/gerar_fixture.py`,
-- `Supabase/test/gerar_fixture_canastra.py`) passaram a escrever um rótulo
-- válido por entidade, usando a própria CHAVE que o autor do fixture já tinha
-- escolhido para cada uma no dicionário `ENT` (ex.: a chave já se chamava
-- "holding" para VERTENTES PARTICIPAÇÕES S.A. e "spe" para VERTENTES IMÓVEIS
-- SPE LTDA. — nada foi inferido de novo, só destravado o que o nome da chave
-- já dizia) — ver o comentário `PAPEL = {...}` em cada gerador. As duas fixtures
-- (`Supabase/test/fixture_book_vertentes.sql`, `Supabase/test/fixture_book_canastra.sql`)
-- e o teste sintético `Supabase/test/eixo_documento_e_coluna.test.sql` (que
-- também gravava `'alvo'` à mão) foram regenerados/corrigidos NESTA MESMA
-- fatia, antes desta migration ser testada.
--
-- A DECISÃO DE PRODUTO JÁ TOMADA (não repetida aqui a cada sessão — ver a
-- fatia 1.3 do roadmap): **não existe sinal automático seguro para inferir
-- papel_no_grupo hoje.** Não há tabela `participacao`/hierarquia (fatia 1.5,
-- futura), e o único documento "COMBINADO" do mandato AMO acabou de ser
-- corrigido como NÃO sendo o combinado do grupo (seção 12.1). Inferir papel
-- automaticamente aqui seria ausência virando dado — a regra 1 outra vez.
-- Por isso esta migration NÃO tenta classificar entidade real nenhuma: ela
-- (a) tipa a coluna, (b) abre um caminho de escrita EXPLÍCITO, chamado por um
-- humano/analista (`fn_entidade_definir_papel_no_grupo` — portal ou SQL
-- direto, o portal não é escopo desta fatia), e (c) marca com pendência
-- COMPLEMENTAR (nunca bloqueante — ausência de classificação não é defeito)
-- toda entidade que nasce sem papel, para que "ninguém decidiu ainda" fique
-- visível em vez de indistinguível de "não precisa decidir".
--
-- MEDIÇÃO NÃO-VAZIA (regra 2), em `Supabase/test/entidade_papel_no_grupo.test.sql`:
-- com a chamada nova a `fn_pendencia_papel_no_grupo_indefinido` comentada
-- dentro de `fn_upsert_entidade` (estado equivalente à 0178), rodado contra o
-- estado anterior — **11 dos 21 asserts reprovaram** (medido de fato, não
-- estimado; ver o cabeçalho do arquivo de teste para o detalhe por bloco).
-- Religada a chamada, os 21 asserts do arquivo passam. A mesma medição
-- também achou e corrigiu um bug de EMPATE DE TIMESTAMP no próprio teste
-- (dois evento_auditoria na mesma transação têm o mesmo `now()`) — ver o
-- cabeçalho do arquivo de teste.
--
-- **Pronto quando** (critério da fatia 1.3, roadmap): as 8 entidades reais do
-- mandato têm papel, ou têm pendência dizendo por que não. Esta migration
-- entrega o CAMINHO — aplicá-la em produção e chamar
-- `fn_entidade_definir_papel_no_grupo` para as 8 é decisão de uma sessão
-- seguinte, contra a sonda (migration escrita ≠ aplicada).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- (1) O ENUM E A MIGRAÇÃO DA COLUNA.
--
-- SEM `begin;`/`commit;` neste arquivo, de propósito: o passo (2) abaixo
-- acrescenta um rótulo a `pendencia_tipo` (enum já existente) e o USA no mesmo
-- arquivo (dentro de `fn_pendencia_papel_no_grupo_indefinido` e no backfill
-- final) — o Postgres proíbe usar um rótulo de enum recém-criado por
-- `ALTER TYPE ... ADD VALUE` dentro da MESMA transação em que ele nasceu
-- ("unsafe use of new value of enum type"). Os precedentes deste repositório
-- que também acrescentam rótulo de enum (0013, 0016, 0036, 0112, 0113) nunca
-- usaram `begin;`/`commit;`, pela mesma razão — cada statement de topo aplica
-- em autocommit e o rótulo novo já está committed quando as funções abaixo o
-- referenciam.
-- -----------------------------------------------------------------------------

create type entidade_papel_no_grupo as enum (
  'holding',
  'operacional',
  'veiculo',
  'coligada',
  'fora_do_perimetro'
);

comment on type entidade_papel_no_grupo is
  '0179: papel da entidade dentro do grupo do mandato. Tipado a partir de `entidade.papel_no_grupo` '
  '(text livre desde a 0001, NULL em todo caso do banco — fatia 1.3 do plano F1). Não existe sinal '
  'automático para preenchê-lo (sem tabela participacao/hierarquia — fatia 1.5, futura): o único '
  'caminho de escrita é `fn_entidade_definir_papel_no_grupo`, chamado por um humano.';

alter table entidade
  alter column papel_no_grupo type entidade_papel_no_grupo
  using papel_no_grupo::entidade_papel_no_grupo;

comment on column entidade.papel_no_grupo is
  '0179: enum entidade_papel_no_grupo (antes: text livre, NULL em todo caso — 0001 a 0178). NULL '
  'continua sendo o estado inicial de TODA entidade nova (fn_upsert_entidade nunca o passa no '
  'insert) — a ausência é honesta enquanto ninguém decidir, e fn_pendencia_papel_no_grupo_indefinido '
  'marca essa ausência sem afirmar hierarquia nenhuma. Só fn_entidade_definir_papel_no_grupo escreve '
  'aqui.';

-- -----------------------------------------------------------------------------
-- (2) A PENDÊNCIA — mesmo desenho de `fn_pendencia_entidade_nome_suspeito`
-- (0178) e `fn_pendencia_entidade_ambigua` (0153): idempotente por MOTIVO
-- (uma por entidade), nunca decide o papel — só marca a ausência.
-- -----------------------------------------------------------------------------

alter type pendencia_tipo add value if not exists 'papel_no_grupo_indefinido';

create function public.fn_pendencia_papel_no_grupo_indefinido(p_caso_id uuid, p_entidade_id uuid, p_nome text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
declare
  v_motivo text := 'papel_no_grupo_indefinido:' || p_entidade_id;
  v_pend   uuid;
begin
  select id into v_pend from pendencia
   where caso_id = p_caso_id and motivo = v_motivo and estado <> 'resolvida'
   limit 1;
  if v_pend is not null then return v_pend; end if;

  insert into pendencia
    (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, entidade_id, motivo)
  values (
    p_caso_id, 'diagnostico', 'papel_no_grupo_indefinido', 'complementar', true,
    format('A entidade "%s" ainda não tem papel no grupo (holding/operacional/veículo/coligada/'
           || 'fora do perímetro) — ninguém decidiu ainda, e o sistema não infere isso sozinho '
           || '(não há hierarquia de participação societária modelada — fatia 1.5, futura). '
           || 'O EFEITO, hoje: nenhum, porque nenhum consumidor lê `papel_no_grupo` ainda — esta '
           || 'entidade entra e sai do book exatamente como as demais. O efeito aparece nas fatias '
           || 'seguintes do plano F1: o perímetro do combinado (1.4) e a participação societária '
           || '(1.5) vão depender deste papel para decidir o que entra em cada agrupamento, e esta '
           || 'entidade ficará de fora de qualquer agrupamento automático até alguém chamar '
           || 'fn_entidade_definir_papel_no_grupo para ela.',
           p_nome),
    p_entidade_id, v_motivo)
  returning id into v_pend;

  return v_pend;
end;
$$;

comment on function public.fn_pendencia_papel_no_grupo_indefinido(p_caso_id uuid, p_entidade_id uuid, p_nome text) IS '0179: pendência complementar (não bloqueia nada) para entidade sem papel no grupo. Idempotente por entidade_id (motivo). Nunca decide o papel — só marca a ausência, regra 1 do CLAUDE.md.';

-- -----------------------------------------------------------------------------
-- (3) O CAMINHO DE ESCRITA — a parte que "não pode ficar de fora" (roadmap,
-- fatia 1.3). Ação explícita de um humano/analista: valida a entidade, grava
-- o papel, registra evento_auditoria e resolve a pendência acima quando ela
-- existir. Reatribuir (chamar de novo com papel diferente) é permitido — é o
-- ESTADO ATUAL da classificação, não um registro append-only; o histórico de
-- quem mudou o quê e quando mora em evento_auditoria, não numa coluna
-- imutável (mesmo raciocínio de fn_entidade_talvez_renomear/fn_revisar_documento:
-- o campo mutável guarda o AGORA, a trilha guarda o ANTES).
-- -----------------------------------------------------------------------------

create function public.fn_entidade_definir_papel_no_grupo(p_entidade_id uuid, p_papel entidade_papel_no_grupo, p_autor text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
declare
  v_papel_anterior entidade_papel_no_grupo;
  v_caso_id        uuid;
begin
  select papel_no_grupo, caso_id into v_papel_anterior, v_caso_id
  from entidade where id = p_entidade_id;

  if v_caso_id is null then
    raise exception 'entidade % não encontrada', p_entidade_id;
  end if;

  update entidade set papel_no_grupo = p_papel where id = p_entidade_id;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
  values (p_autor, 'entidade_papel_no_grupo_definido', 'entidade:' || p_entidade_id,
          jsonb_build_object('papel_novo', p_papel, 'papel_anterior', v_papel_anterior));

  update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = p_autor
   where entidade_id = p_entidade_id
     and tipo = 'papel_no_grupo_indefinido'
     and motivo = 'papel_no_grupo_indefinido:' || p_entidade_id
     and estado <> 'resolvida';

  return p_entidade_id;
end;
$$;

comment on function public.fn_entidade_definir_papel_no_grupo(p_entidade_id uuid, p_papel entidade_papel_no_grupo, p_autor text) IS '0179: o ÚNICO caminho de escrita de entidade.papel_no_grupo — chamado por um humano/analista (portal ou SQL direto; o portal não é escopo da fatia 1.3). Grava evento_auditoria (ator = p_autor, nunca ''sistema:...''), e resolve fn_pendencia_papel_no_grupo_indefinido se estiver aberta para esta entidade. Reatribuir com papel diferente é permitido — é o estado ATUAL, o histórico mora em evento_auditoria.';

grant execute on function public.fn_entidade_definir_papel_no_grupo(uuid, entidade_papel_no_grupo, text) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_upsert_entidade — reemitida INTEIRA, verbatim do corpo vigente (0178),
-- com só uma linha nova antes do `return v_id` final (nunca por âncora de
-- texto em corpo de função — mesmo cuidado da 0178 sobre a 0177). A
-- assinatura não muda, então `create or replace` basta, sem DROP.
--
-- INCONDICIONAL, e de propósito: toda entidade que nasce por este `insert`
-- final nasce com papel_no_grupo NULL por construção (a coluna nunca é
-- passada no insert) — vale tanto para a entidade real quanto para a
-- suspeita de título/arquivo (0178) e para o balcão ambíguo (0153/0162,
-- 0175-0177): são sinais DIFERENTES, e é honesto os dois ficarem abertos ao
-- mesmo tempo (uma entidade pode ser, simultaneamente, "nome suspeito, revisar"
-- E "sem papel no grupo, ninguém decidiu ainda").
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_upsert_entidade(p_caso_id uuid, p_nome text, p_cnpj text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
declare
  v_id         uuid;
  v_n          int;
  v_candidatos text;
  v_nomes      text[];
  v_cnpj       text := fn_cnpj_canonico(p_cnpj);
  v_nome_atual text;
  v_e_balcao   boolean;
  v_mesmo_nome_do_balcao boolean;
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

    if v_id is not null then
      v_e_balcao := fn_entidade_e_balcao_ambiguo(p_caso_id, v_id);

      -- 0177 (ALTO): o nome que chega pode ser o PRÓPRIO nome do balcão —
      -- um SEGUNDO documento do MESMO balcão, chegando pela classificação,
      -- com o CNPJ que ele já aprendeu. A 0176 tratava QUALQUER chegada
      -- contra um balcão como colisão externa, mesmo quando é o balcão
      -- recebendo mais um documento seu: a pendência abria dizendo que o
      -- nome "chegou... sem ser, ela própria, um balcão ambíguo" e que "o
      -- sistema NÃO... atribuiu este documento/entidade a ele" — as DUAS
      -- afirmações falsas, porque o nome que chegou É o do balcão e o
      -- documento SIM termina atribuído a ele pelo ramo (1) de casamento
      -- exato por nome, alguns passos abaixo. MEDIDO nesta sessão: uma
      -- pendência de colisão nascia (0→1) mesmo quando o documento novo era
      -- só mais um do MESMO balcão.
      v_mesmo_nome_do_balcao := v_e_balcao
        and fn_entidade_canonica(v_nome_atual) is not distinct from fn_entidade_canonica(trim(p_nome));

      -- MEDIDO (0176): um documento novo de OUTRA empresa (mesmo CNPJ de
      -- rodapé de contador) virava absorvido pelo balcão sem nunca ganhar
      -- linha própria — entidades no caso ficavam em 3 em vez de virarem 4.
      -- Trata o CNPJ como se nunca tivesse chegado (`v_cnpj := null`) para o
      -- resto desta chamada: sem isso, o `insert` do fim desta função
      -- tentaria gravar este MESMO CNPJ numa entidade nova e violaria
      -- `entidade_caso_cnpj_unico` — e, pior, atribuiria à empresa nova um
      -- CNPJ que pode não ser dela.
      if v_e_balcao and not v_mesmo_nome_do_balcao then
        perform fn_pendencia_cnpj_colide_balcao(p_caso_id, v_id, v_cnpj, trim(p_nome), null);
        v_id := null;
        v_cnpj := null;
      else
        -- O EVENTO DE CASAMENTO fica na forma CANÔNICA: ele existe para registrar
        -- que o CNPJ respondeu um nome MATERIALMENTE diferente do gravado, e
        -- diferença só de sufixo/pontuação não é isso. Quando é o PRÓPRIO
        -- balcão (v_mesmo_nome_do_balcao), esta condição já é falsa por
        -- construção — nenhum evento de "casamento" nasce, porque não houve
        -- casamento: é o mesmo nome de sempre.
        if fn_entidade_canonica(v_nome_atual) is distinct from fn_entidade_canonica(trim(p_nome)) then
          insert into evento_auditoria (ator, acao, entidade_ref, depois)
          values ('sistema:entidade', 'entidade_cnpj_casou', 'entidade:' || v_id,
                  jsonb_build_object('caso_id', p_caso_id, 'nome_procurado', trim(p_nome),
                                     'nome_mantido_antes_do_renomeio', v_nome_atual,
                                     'cnpj', v_cnpj,
                                     'pode_renomear', fn_pode_renomear_por_cnpj(v_nome_atual, trim(p_nome)),
                                     'porque', 'o CNPJ é o mesmo — o nome não foi consultado'));
        end if;

        -- 0173: O RENOMEIO VIROU FUNÇÃO PRÓPRIA, e os DOIS caminhos a chamam.
        -- Antes ele morava aqui dentro, e só este caminho (a classificação) o
        -- executava — o diagnóstico, que é o único que roda para TODO documento,
        -- gravava o CNPJ e ia embora sem renomear. Medido: identidade fiscal em
        -- 100% do lote e renomeio em ~50%.
        perform fn_entidade_talvez_renomear(p_caso_id, v_id, trim(p_nome), v_cnpj);

        return v_id;
      end if;
    end if;
  end if;

  -- (1) exato pela forma canônica — não há o que desempatar.
  select c.entidade_id into v_id
  from fn_entidades_candidatas_cnpj(p_caso_id, p_nome, p_cnpj) c
  where c.exata
  order by c.razao_social
  limit 1;
  if v_id is not null then
    -- 0174: usa o RETORNO, não `perform`. Sem isto, quando `fn_entidade_aprender_cnpj`
    -- funde esta entidade numa OUTRA que já tinha o mesmo CNPJ (a corrida entre
    -- o ramo (0) acima e este ramo, ou a mesma situação chegando pela porta do
    -- diagnóstico — ver o cabeçalho da função), `v_id` ficaria apontando para
    -- uma linha DELETADA, e o `insert into documento` em `fn_registrar_documento`
    -- quebraria a FK `documento.entidade_id → entidade.id`.
    v_id := fn_entidade_aprender_cnpj(v_id, v_cnpj);
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

  -- 0178: NEM CNPJ NEM CANDIDATO NENHUM CASOU, e o nome tem cara de
  -- título/coluna/aba/arquivo — a CONJUNÇÃO que separa isso do balcão
  -- ambíguo real (que também chega sem CNPJ por este mesmo `insert`, mas com
  -- nome vindo do CONTEÚDO do documento, não de um título). Não recusa o
  -- `insert` (o documento não pode ficar sem entidade — perderia
  -- proveniência) e não funde com nada — só marca para revisão humana.
  -- MEDIDO (`Supabase/test/entidade_titulo_suspeito.test.sql`): os 4 nomes
  -- reais do AMO teste 00 (Empresas, Vencidos, Status Extratos, Controle
  -- Extratos Ofx) batem aqui; um nome real de empresa do mesmo mandato,
  -- AMOBELEZA COMERCIO DIGITAL E OFFLINE LTDA (com CNPJ), não passa por este
  -- `if` porque `v_cnpj` não é nulo — nem chega a ser avaliado contra o léxico.
  if v_cnpj is null and fn_entidade_nome_parece_titulo_ou_arquivo(trim(p_nome)) then
    perform fn_pendencia_entidade_nome_suspeito(p_caso_id, v_id, trim(p_nome));
  end if;

  -- 0179: TODA entidade nasce aqui com papel_no_grupo NULL por construção (a
  -- coluna não é passada no insert acima) — marca a ausência, incondicional,
  -- porque não existe sinal automático para decidir o papel (fatia 1.3;
  -- roadmap, seção 12.1: sem participacao/hierarquia modelada). Vale tanto
  -- para a entidade real quanto para a suspeita de título/arquivo logo acima
  -- e para o balcão ambíguo (0153/0162, 0175-0177) — são sinais diferentes, e
  -- é honesto os dois estarem abertos ao mesmo tempo.
  perform fn_pendencia_papel_no_grupo_indefinido(p_caso_id, v_id, trim(p_nome));

  return v_id;
end;
$$;

COMMENT ON FUNCTION public.fn_upsert_entidade(p_caso_id uuid, p_nome text, p_cnpj text) IS 'Acha ou cria a entidade do caso (0030), sem ESCOLHER no empate (0153), com o nome truncado fundido no mais completo (0168), com o CNPJ como identidade (0169) e adotando a variante mais completa ao fundir por CNPJ (0171/0173 — a decisão mora em fn_entidade_talvez_renomear, chamada dos dois caminhos). 0174: o ramo (1) usa o RETORNO de fn_entidade_aprender_cnpj. 0176: o ramo (0) não devolve mais um balcão ambíguo (0162/0175) direto para OUTRA empresa — trata o CNPJ como ausente e registra a colisão (fn_pendencia_cnpj_colide_balcao). 0177: essa colisão só é registrada quando quem chegou NÃO é, ela própria, o mesmo balcão — um segundo documento do PRÓPRIO balcão (mesmo nome, mesmo CNPJ) não abre pendência falsa; segue pelo caminho normal. 0178: uma entidade NOVA (nenhum candidato casou), sem CNPJ, com nome que bate fn_entidade_nome_parece_titulo_ou_arquivo, ainda é criada (documento não perde dona) mas ganha pendência entidade_incorreta/entidade_nome_suspeito para revisão humana — nunca fundida nem apagada. 0179: toda entidade nova (real, suspeita ou balcão) ganha também a pendência papel_no_grupo_indefinido, incondicional — não há sinal automático para classificar o papel no grupo.';

-- -----------------------------------------------------------------------------
-- O BACKFILL. Entidades que JÁ EXISTEM neste banco (inclusive as 8 reais do
-- mandato AMO, quando esta migration for aplicada em produção — escrita ≠
-- aplicada, decisão de uma sessão seguinte) e ainda não têm papel_no_grupo
-- ganham a mesma pendência complementar. Idempotente por motivo — rodar esta
-- migration mais de uma vez, ou num banco onde alguma entidade já tenha sido
-- marcada, não duplica nada.
-- -----------------------------------------------------------------------------

do $$
declare
  r record;
begin
  for r in
    select e.id, e.caso_id, e.razao_social
    from entidade e
    where e.papel_no_grupo is null
  loop
    perform fn_pendencia_papel_no_grupo_indefinido(r.caso_id, r.id, r.razao_social);
  end loop;
end;
$$;

-- -----------------------------------------------------------------------------
-- O CATÁLOGO DA SONDA.
--
-- `entidade_papel_no_grupo_tipo_existe` usa tipo='coluna' (não 'tabela'): o
-- enum não é uma tabela, e o catálogo (0131/0147) só aceita
-- tabela/coluna/funcao/seed/comportamento/corpo — acrescentar um tipo novo só
-- para "enum" seria escopo maior do que esta fatia pede (mudaria o `check` de
-- `instalacao_requisito.tipo`, usado por TODO requisito já cadastrado). A
-- checagem de tipo='coluna' contra `entidade.papel_no_grupo` já prova que a
-- coluna existe via `pg_attribute` (0132/0147) — não confere que ela é enum,
-- mas ausência de coluna nenhuma (migration nem aplicada) é o sintoma que
-- este requisito precisa acusar, e esse ele acusa.
-- -----------------------------------------------------------------------------

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('entidade_papel_no_grupo_tipo_existe', '0179', 'coluna', 'entidade.papel_no_grupo',
   null, null,
   'A coluna que a fatia 1.3 tipou em enum (entidade_papel_no_grupo). Ausente (banco anterior à '
   '0179), papel_no_grupo continua text livre e NULL em todo caso — sem tipo mais forte e sem '
   'caminho de escrita nenhum (seção 12.1 do roadmap).',
   'importante', 750)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('fn_entidade_definir_papel_no_grupo_existe', '0179', 'funcao', 'fn_entidade_definir_papel_no_grupo',
   null, null,
   'O único caminho de escrita de papel_no_grupo. Sem ele, a coluna tipada continua com o mesmo '
   'vazio de antes, só com tipo mais forte — exatamente o risco que o roadmap nomeia na fatia 1.3.',
   'importante', 751)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('fn_pendencia_papel_no_grupo_indefinido_existe', '0179', 'funcao', 'fn_pendencia_papel_no_grupo_indefinido',
   null, null,
   'A função que marca a ausência de papel no grupo para revisão humana, sem decidir nada — regra 1 '
   'do CLAUDE.md. Ausente, a chamada nova em fn_upsert_entidade não teria como deixar rastro.',
   'importante', 752)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('upsert_entidade_marca_papel_indefinido', '0179', 'corpo', 'fn_upsert_entidade',
   'fn_pendencia_papel_no_grupo_indefinido(p_caso_id, v_id', null,
   'Prova a CHAMADA dentro de fn_upsert_entidade, não só a existência da função (o mesmo cuidado da '
   '0178 com upsert_entidade_marca_nome_suspeito): sem esta linha no corpo publicado, uma reemissão '
   'futura da função pode perder a marca mesmo com fn_pendencia_papel_no_grupo_indefinido '
   'continuando presente e testada, e a sonda ficaria muda sobre isso.',
   'importante', 753)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0179', revisado_em = current_date,
       observacao = 'A 0179 fecha a fatia 1.3 do plano F1: papel_no_grupo tipado em enum '
                    '(entidade_papel_no_grupo) e com caminho de escrita explícito '
                    '(fn_entidade_definir_papel_no_grupo, chamado por humano) — sem inferência '
                    'automática (regra 1: não há sinal seguro sem a fatia 1.5, participação '
                    'societária). Toda entidade nova ganha pendência complementar '
                    'papel_no_grupo_indefinido até alguém decidir; backfill cobre as que já '
                    'existiam. As 8 entidades reais do mandato AMO ainda não têm papel definido — '
                    'aplicar a migration e chamar a função para elas é decisão de uma sessão '
                    'seguinte, contra a sonda.';

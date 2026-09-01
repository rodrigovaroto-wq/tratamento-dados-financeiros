-- 0153 — QUANDO O NOME CASA COM DUAS EMPRESAS, ELE NÃO IDENTIFICA NENHUMA.
--
-- MEDIDO NA RODADA REAL DO `book-araucaria` (27/08/2026). O arquivo
-- `009_Balanco_Patrimonial_Araucaria_SPE_2025x2024x2023x2022x2021.pdf` é da
-- **Araucária Imobiliária SPE Ltda.** — o resumo que o próprio sistema extraiu
-- do documento diz isso, com todas as letras. Ele foi gravado sob
-- **ARAUCÁRIA BIOENERGIA SPE LTDA.**, junto com o
-- `042_Demonstracao_do_Resultado_Araucaria_SPE_...`.
--
-- Balanço e DRE de CINCO exercícios de uma empresa, dentro de outra. E vai
-- FECHAR: os dois são demonstrações completas, então `Ativo = Passivo + PL`
-- bate dos dois lados e nenhuma reconciliação dispara. É a família de defeito
-- que esta base já nomeou três vezes — o que não produz erro nenhum.
--
-- A CAUSA, rodada contra o banco de produção:
--
--     fn_mesma_entidade('Araucaria SPE', 'ARAUCÁRIA BIOENERGIA SPE LTDA.')  → true
--     fn_mesma_entidade('Araucaria SPE', 'ARAUCÁRIA IMOBILIÁRIA SPE LTDA.') → true
--
-- Casa com as DUAS. O casamento da `0030` é por SUBSEQUÊNCIA de prefixos —
-- "araucaria" casa "araucaria", "spe" casa "spe" pulando "bioenergia" — e num
-- grupo em que toda empresa se chama "Araucária ⟨coisa⟩ Ltda." qualquer nome
-- parcial é subsequência de vários.
--
-- E O DESEMPATE ERA ESTE, em `fn_upsert_entidade` (0030):
--
--     order by e.razao_social
--     limit 1
--
-- com o comentário ao lado: *"ordenar pela razão social torna a escolha
-- DETERMINÍSTICA"*. **É o mesmo defeito que a 0151 acabou de corrigir em
-- `fn_linhas_do_realizado`, num segundo lugar** — uma regra de desempate sem
-- critério, sem autor e sem rastro. Lá era `order by abs(valor) desc` ("fica com
-- o maior"); aqui é `order by razao_social` ("fica com a primeira do
-- alfabeto"). BIOENERGIA vem antes de IMOBILIÁRIA, e foi só isso que decidiu.
--
-- DETERMINÍSTICO NÃO É CORRETO. Um desempate determinístico entre coisas que
-- não deviam ser desempatadas apenas garante que o erro será sempre o mesmo.
--
-- ---------------------------------------------------------------------------
-- O QUE ESTA MIGRATION NÃO FAZ, E POR QUÊ
-- ---------------------------------------------------------------------------
--
-- **Não aperta `fn_mesma_entidade`.** A frouxidão dela é deliberada e útil: é
-- o que faz "Metalúrgica" casar "VERTENTES METALÚRGICA LTDA." e "Part." casar
-- "Participações", que é o problema real de nome vindo de fonte diferente.
-- Apertá-la trocaria um erro caro (fundir empresas) por outro (partir a mesma
-- empresa em duas), e o comentário da própria 0030 já diz qual dos dois é pior.
--
-- O que muda é o que se faz com o RESULTADO dela quando ele é plural. Um
-- casamento que devolve dois candidatos não é um casamento ruim — é uma
-- PERGUNTA, e ela tem de chegar a um humano em vez de virar um `limit 1`.

-- =============================================================================
-- 1. OS CANDIDATOS PASSAM A SER VISÍVEIS
-- =============================================================================
--
-- Separada de `fn_upsert_entidade` porque quem abre a pendência precisa saber
-- CONTRA QUEM o nome casou — dizer "ambíguo" sem nomear os candidatos devolve o
-- trabalho inteiro para a mesa, que é o que este produto existe para não fazer.
create or replace function fn_entidades_candidatas(p_caso_id uuid, p_nome text)
returns table (entidade_id uuid, razao_social text, exata boolean)
language sql
stable
as $$
  select e.id, e.razao_social,
         fn_entidade_canonica(e.razao_social) = fn_entidade_canonica(p_nome)
  from entidade e
  where e.caso_id = p_caso_id
    and p_nome is not null
    and length(trim(p_nome)) > 0
    and fn_mesma_entidade(e.razao_social, p_nome)
  order by (fn_entidade_canonica(e.razao_social) = fn_entidade_canonica(p_nome)) desc,
           e.razao_social;
$$;

comment on function fn_entidades_candidatas(uuid, text) is
  'As entidades do caso com que um nome casa, a exata primeiro (0153). Mais de uma linha sem '
  'nenhuma exata é AMBIGUIDADE: o nome não identifica empresa nenhuma, e quem decide é o humano.';

-- =============================================================================
-- 2. `fn_upsert_entidade` PARA DE ESCOLHER NO EMPATE
-- =============================================================================
--
-- A ordem das três respostas é o conteúdo desta correção:
--
--   1. CASAMENTO EXATO pela forma canônica → é ele, sem dúvida. Precisa vir
--      primeiro: sem isso, `order by razao_social` podia preferir um casamento
--      APROXIMADO a um exato só porque o nome dele vem antes no alfabeto —
--      "ARAUCÁRIA BIOENERGIA SPE" ganharia de "Araucaria SPE" mesmo quando
--      "Araucaria SPE" existe e é literalmente o nome procurado;
--   2. UM ÚNICO casamento aproximado → é ele. É o caso normal, e é o que faz
--      as duas grafias da mesma empresa continuarem sendo uma entidade só;
--   3. DOIS OU MAIS aproximados e nenhum exato → **não escolhe**. Cria uma
--      entidade com o nome como veio, e a ambiguidade fica declarada em
--      `evento_auditoria` para `fn_registrar_documento` transformar em
--      pendência.
--
-- POR QUE CRIAR EM VEZ DE RECUSAR. Recusar deixaria o documento sem entidade, e
-- documento sem entidade some das telas que agrupam por empresa — o defeito
-- ficaria invisível de novo, que é exatamente o que se está corrigindo. Criando,
-- o número não contamina NENHUMA das duas empresas candidatas (que é o dano
-- real), o documento continua visível, e a pendência diz o que decidir. Fundir
-- depois é uma chamada de `fn_fundir_entidade`; separar o que já foi fundido
-- por engano é reextrair o caso.
create or replace function fn_upsert_entidade(p_caso_id uuid, p_nome text)
returns uuid
language plpgsql
as $$
declare
  v_id        uuid;
  v_n         int;
  v_candidatos text;
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
  select count(*), string_agg(c.razao_social, ' × ' order by c.razao_social)
    into v_n, v_candidatos
  from fn_entidades_candidatas(p_caso_id, p_nome) c;

  if v_n = 1 then
    select c.entidade_id into v_id from fn_entidades_candidatas(p_caso_id, p_nome) c limit 1;
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

comment on function fn_upsert_entidade(uuid, text) is
  'Acha ou cria a entidade do caso pelo nome (0030), sem ESCOLHER no empate (0153): casamento '
  'canônico exato primeiro, depois o único aproximado; com dois ou mais aproximados e nenhum '
  'exato, cria entidade própria e registra `entidade_ambigua` em evento_auditoria — porque '
  '"Araucaria SPE" casa com Bioenergia SPE E com Imobiliária SPE, e o `order by razao_social` '
  'da 0030 punha o balanço de uma dentro da outra sem dizer nada.';

-- =============================================================================
-- 3. A AMBIGUIDADE VIRA PENDÊNCIA, COM OS CANDIDATOS POR EXTENSO
-- =============================================================================
--
-- `entidade_incorreta` já existe no enum e é exatamente isto: o sistema não sabe
-- de quem é o documento. A descrição traz os candidatos e o que fazer, porque
-- pendência que diz só "ambíguo" é pendência que ninguém sabe fechar.
create or replace function fn_pendencia_entidade_ambigua(
  p_caso_id uuid, p_documento_id uuid, p_entidade_id uuid
)
returns uuid
language plpgsql
as $$
declare
  v_ev   jsonb;
  v_pend uuid;
  v_nome text;
begin
  select ev.depois into v_ev
  from evento_auditoria ev
  where ev.acao = 'entidade_ambigua'
    and ev.entidade_ref = 'entidade:' || p_entidade_id
  order by ev.criado_em desc
  limit 1;

  if v_ev is null then return null; end if;

  select razao_social into v_nome from entidade where id = p_entidade_id;

  -- Uma pendência por ENTIDADE ambígua, não por documento: cinco balanços da
  -- mesma empresa fazem UMA pergunta, e cinco pendências idênticas são a
  -- enxurrada que ensina o analista a ignorar a fila.
  select id into v_pend from pendencia
  where caso_id = p_caso_id and motivo = 'entidade_ambigua:' || p_entidade_id
    and estado <> 'resolvida'
  limit 1;
  if v_pend is not null then return v_pend; end if;

  insert into pendencia
    (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao,
     documento_id, entidade_id, motivo)
  values (
    p_caso_id, 'classificacao', 'entidade_incorreta', 'bloqueante', false,
    format('O nome "%s" casa com MAIS DE UMA empresa deste mandato (%s) e não identifica '
           || 'nenhuma. O documento foi registrado numa entidade própria com esse nome, para '
           || 'não somar os números dele em nenhuma das candidatas — que é o dano que uma '
           || 'escolha errada aqui causa, e ele não produz erro nenhum: o balanço da empresa '
           || 'errada FECHA. Decida de quem é e funda com fn_fundir_entidade; se for uma '
           || 'empresa nova de verdade, basta renomear.',
           v_nome, v_ev->>'candidatos'),
    p_documento_id, p_entidade_id, 'entidade_ambigua:' || p_entidade_id)
  returning id into v_pend;

  return v_pend;
end;
$$;

comment on function fn_pendencia_entidade_ambigua(uuid, uuid, uuid) is
  'Transforma a ambiguidade registrada por fn_upsert_entidade em pendência bloqueante, nomeando '
  'os candidatos (0153). Uma por entidade, não por documento.';

-- -----------------------------------------------------------------------------
-- O GATILHO — porque a função que abre a pendência precisa ser CHAMADA
-- -----------------------------------------------------------------------------
--
-- Esta é a lição da sessão 72, aplicada de véspera: *um estágio desligado tem
-- exatamente a mesma aparência de um estágio que rodou e não achou nada.*
-- `fn_pendencia_entidade_ambigua` instalada e sem chamador seria a
-- `fn_conflitos_do_caso` da 0151 de novo — presente, correta e muda.
--
-- POR QUE GATILHO E NÃO UMA LINHA EM `fn_registrar_documento`: aquela função
-- tem 160 linhas e é recriada por inteiro a cada migration que a toca. A 0006
-- já regrediu funções silenciosamente exatamente assim, recriando um corpo
-- antigo — e o comentário da 0030 registra isso. O gatilho não pede que ninguém
-- recopie nada, e vale para QUALQUER caminho de escrita (o registro do
-- documento, o diagnóstico da IA que troca a entidade, a revisão humana).
--
-- `of entidade_id` no UPDATE: sem isso o gatilho dispararia em toda revisão de
-- documento, e uma pendência já resolvida seria reaberta a cada clique.
create or replace function fn_trg_entidade_ambigua()
returns trigger language plpgsql as $$
begin
  if new.entidade_id is not null then
    perform fn_pendencia_entidade_ambigua(new.caso_id, new.id, new.entidade_id);
  end if;
  return null;
end;
$$;

drop trigger if exists trg_entidade_ambigua on documento;
create trigger trg_entidade_ambigua
  after insert or update of entidade_id on documento
  for each row execute function fn_trg_entidade_ambigua();

comment on function fn_trg_entidade_ambigua() is
  'Chama fn_pendencia_entidade_ambigua quando um documento ganha entidade (0153). Existe porque '
  'checagem instalada e sem chamador é indistinguível de checagem que não achou nada.';

-- =============================================================================
-- 4. FUNDIR DUAS ENTIDADES QUE SÃO A MESMA EMPRESA
-- =============================================================================
--
-- A saída da pendência acima, e também o conserto do que já está no banco: o
-- `book-araucaria` gravou **25 entidades para 14 empresas**, e onze delas são
-- sobra do nome do arquivo ("Comparativo Araucaria Serraria", "Liquido
-- Araucaria Serraria", "Log").
--
-- NADA É APAGADO SEM RASTRO: o evento de auditoria guarda o nome que existia e
-- quantos documentos mudaram de dono. É a mesma doutrina da 0105 e da 0151 —
-- quem lê o número depois tem de conseguir saber que houve uma decisão.
create or replace function fn_fundir_entidade(
  p_caso_id uuid, p_de_id uuid, p_para_id uuid, p_por text default 'sistema:fusao'
)
returns jsonb
language plpgsql
as $$
declare
  v_de    text;
  v_para  text;
  v_docs  int;
begin
  if p_de_id = p_para_id then
    raise exception 'fundir uma entidade nela mesma não faz sentido (%)', p_de_id;
  end if;

  select razao_social into v_de   from entidade where id = p_de_id   and caso_id = p_caso_id;
  select razao_social into v_para from entidade where id = p_para_id and caso_id = p_caso_id;
  if v_de is null or v_para is null then
    raise exception 'entidade não encontrada neste mandato (de=%, para=%)', p_de_id, p_para_id;
  end if;

  update documento set entidade_id = p_para_id
   where caso_id = p_caso_id and entidade_id = p_de_id;
  get diagnostics v_docs = row_count;

  -- Tudo o que aponta para a entidade acompanha o documento. `checklist_item_status`
  -- e `pendencia` guardam entidade_id por conta própria, e deixá-los para trás
  -- faria o Portão 1 continuar cobrando de uma empresa que não existe mais.
  update checklist_item_status set entidade_id = p_para_id
   where caso_id = p_caso_id and entidade_id = p_de_id;
  update pendencia set entidade_id = p_para_id
   where caso_id = p_caso_id and entidade_id = p_de_id;
  update reconciliacao set entidade_id = p_para_id
   where caso_id = p_caso_id and entidade_id = p_de_id;

  -- A pendência de ambiguidade da entidade fundida está respondida.
  update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = p_por
   where caso_id = p_caso_id and motivo = 'entidade_ambigua:' || p_de_id and estado <> 'resolvida';

  delete from entidade where id = p_de_id and caso_id = p_caso_id;

  insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
  values (p_por, 'entidade_fundida', 'entidade:' || p_para_id,
          jsonb_build_object('entidade_id', p_de_id, 'razao_social', v_de),
          jsonb_build_object('entidade_id', p_para_id, 'razao_social', v_para,
                             'documentos_movidos', v_docs));

  return jsonb_build_object('fundida', v_de, 'em', v_para, 'documentos', v_docs);
end;
$$;

comment on function fn_fundir_entidade(uuid, uuid, uuid, text) is
  'Funde duas entidades que são a mesma empresa, levando junto documentos, checklist, pendências '
  'e reconciliações (0153). Nada some sem rastro: evento_auditoria guarda o nome que existia e '
  'quantos documentos mudaram de dono.';

grant execute on function fn_entidades_candidatas(uuid, text) to authenticated;
grant execute on function fn_pendencia_entidade_ambigua(uuid, uuid, uuid) to authenticated;
grant execute on function fn_fundir_entidade(uuid, uuid, uuid, text) to authenticated;

-- =============================================================================
-- 5. A SONDA
-- =============================================================================
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('entidade_ambigua_nao_decide', '0153', 'corpo', 'fn_upsert_entidade', '0153', null,
   'O nome que casa com DUAS empresas volta a escolher a primeira do alfabeto: medido no '
   'book-araucaria, o balanço e a DRE de cinco exercícios da Araucária Imobiliária SPE foram '
   'gravados dentro da Araucária Bioenergia SPE. Não produz erro nenhum — o balanço da empresa '
   'errada FECHA, e nenhuma reconciliação dispara contra um número que fecha.',
   'bloqueante', 550),
  ('entidade_candidatas', '0153', 'funcao', 'fn_entidades_candidatas', null, null,
   'Sem ela a ambiguidade não tem como ser nomeada, e a pendência diria "ambíguo" sem dizer '
   'contra quem — devolvendo o trabalho inteiro para a mesa.',
   'importante', 560),
  ('entidade_ambigua_na_rodada', '0153', 'funcao', 'fn_trg_entidade_ambigua', null, null,
   'A pendência de entidade ambígua existe e NADA a chama: o documento entra na empresa errada '
   'em silêncio, como entrou no araucária. É a forma de estágio parado que a rodada de 27/08 '
   'ensinou a reconhecer — instalada, correta e muda.',
   'bloqueante', 565),
  ('entidade_fusao', '0153', 'funcao', 'fn_fundir_entidade', null, null,
   'A pendência de entidade ambígua fica sem saída: não há como dizer "estas duas são a mesma '
   'empresa" sem editar tabela à mão, e o mandato fica com duas colunas por empresa no export.',
   'importante', 570)
on conflict (chave) do update
  set migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
      marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
      porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0153',
       revisado_em = date '2026-08-27',
       observacao = 'Revisão de 27/08/2026 (noite): a 0153 tira o desempate silencioso de '
                    'fn_upsert_entidade, que era o mesmo defeito da 0151 num segundo lugar — '
                    'lá "fica com o maior", aqui "fica com a primeira do alfabeto". Medido no '
                    'book-araucaria: balanço e DRE de cinco exercícios da Araucária Imobiliária '
                    'SPE gravados dentro da Araucária Bioenergia SPE, sem erro nenhum. Três '
                    'requisitos novos: o corpo que não decide no empate, os candidatos '
                    'visíveis, e a fusão que dá saída à pendência.'
 where id;

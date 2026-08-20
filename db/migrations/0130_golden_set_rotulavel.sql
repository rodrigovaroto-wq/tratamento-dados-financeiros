-- =============================================================================
-- 0130 — O GOLDEN SET PASSA A SER ROTULÁVEL.
--
-- A 0126 construiu o golden set inteiro do lado da LEITURA: quatro tabelas, as
-- cinco métricas do `f0/06`, o portão `fn_golden_suficiente` e a regra de ouro
-- executada em `fn_mudar_dial`. E não construiu nenhuma função de ESCRITA. Hoje
-- abrir uma rodada, incluir um documento ou gravar um rótulo só é possível
-- escrevendo `insert` à mão no psql, e congelar é um `update` na coluna certa.
--
-- Isto é o mesmo defeito que esta linhagem vem corrigindo em três migrations
-- seguidas, uma camada acima: a 0126 fez a regra de ouro ser executada, a 0127
-- fez o dial ser lido, a 0128 fez a classificação existir — e todas as três
-- dependem de um golden set que ninguém consegue alimentar. O portão está
-- construído e não há estrada até ele.
--
-- O QUE ESTA MIGRATION NÃO MUDA. Nenhuma métrica, nenhum critério, nenhum
-- comportamento do dial. `fn_golden_suficiente` continua exatamente como está.
-- Se um número mudar depois desta migration, é porque passou a EXISTIR rótulo —
-- não porque a régua mudou.
--
-- -----------------------------------------------------------------------------
-- A DECISÃO DE DESENHO QUE GOVERNA O RESTO: A ROTULAGEM É CEGA.
--
-- Fechamento #5 do `docs/01` (anti-ancoragem): nenhum número da máquina vira
-- fato sem aceite humano explícito. Aqui a aposta é maior que numa tela de
-- aceite, porque o rótulo do golden set é a EVIDÊNCIA que autoriza subir
-- autonomia. Rotulador que vê a resposta da máquina enquanto rotula não produz
-- ground truth: produz uma conferência. E conferência tem viés conhecido de
-- confirmação — o número plausível passa. A métrica então sobe sem que nada
-- tenha melhorado, e o dial sobe com ela. O sistema certificaria a si mesmo.
--
-- Por isso `fn_golden_linhas_para_rotular` devolve as rubricas SEM os valores.
--
-- E POR QUE ELA DEVOLVE AS RUBRICAS, em vez de esconder tudo. Porque o que se
-- mede é o VALOR, e a rubrica é só a chave de casamento: `fn_golden_campos`
-- compara `valor_num` juntando por `fn_normalizar_texto(chave)` + período +
-- entidade. Esconder as rubricas faria o rotulador digitar a grafia dele
-- ("Receita líquida de vendas" contra "Receita Líquida"), o par não casaria, e a
-- linha entraria como AUSENTE — a família de defeito mais grave do placar,
-- creditada à máquina por uma diferença de datilografia. A medição passaria a
-- medir a coincidência de grafia entre duas pessoas.
--
-- Ver a rubrica não ancora o julgamento do valor: o valor continua tendo de ser
-- lido no papel. Ver o valor ancoraria, e é exatamente ele que não vem.
--
-- A CONTRAPARTIDA, e ela é obrigatória: uma lista só das rubricas que a máquina
-- ACHOU deixaria a perda silenciosa invisível — o rotulador confirmaria as 40
-- linhas extraídas e nunca notaria as 3 que a extração perdeu. Então
-- `fn_golden_rotular_campos` aceita rubrica que não está na lista, e a tela tem
-- de perguntar por ela com palavra. É o inverso da cobertura: a lista mostra o
-- que a máquina viu, e a pergunta cobra o que ela não viu.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- fn_golden_abrir_rodada — a rodada nasce aqui, e nasce datada.
--
-- `taxonomia_versao` vem do catálogo em vigor quando ela abre, e não é parâmetro
-- opcional por conveniência: o `f0/06` amarra o rótulo à versão da taxonomia em
-- que foi feito porque "tipo correto em v1 pode não ser tipo correto em v2". Uma
-- rodada que herdasse a versão errada mediria a máquina contra um gabarito de
-- outra época.
-- -----------------------------------------------------------------------------
create or replace function fn_golden_abrir_rodada(
  p_nome              text,
  p_autor             text,
  p_nota              text default null,
  p_taxonomia_versao  int  default null
)
returns jsonb
language plpgsql
as $$
declare
  v_nome   text := nullif(trim(coalesce(p_nome, '')), '');
  v_autor  text := nullif(trim(coalesce(p_autor, '')), '');
  v_versao int;
  v_id     uuid;
begin
  if v_nome is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'Rodada sem nome. O nome é a referência que uma decisão de dial cita '
                       '("subiu com base na rodada X"), e "a rodada de agosto" não é referência.');
  end if;

  if v_autor is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'Rodada sem autor. Quem abriu a rodada é parte da evidência: o golden set '
                       'autoriza subir autonomia, e evidência sem procedência não autoriza nada.');
  end if;

  if exists (select 1 from golden_rodada r where r.nome = v_nome) then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('Já existe uma rodada chamada "%s". O f0/06 amplia o golden set com '
                              'rodada NOVA e nunca editando a anterior — reusar o nome faria duas '
                              'evidências diferentes responderem pela mesma citação.', v_nome));
  end if;

  v_versao := coalesce(p_taxonomia_versao,
                       (select max(t.versao) from taxonomia_tipo_documento t where t.ativo),
                       1);

  insert into golden_rodada (nome, taxonomia_versao, criada_por, nota)
  values (v_nome, v_versao, v_autor, p_nota)
  returning id into v_id;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
  values (v_autor, 'golden_rodada_aberta', 'golden_rodada:'||v_id,
          jsonb_build_object('nome', v_nome, 'taxonomia_versao', v_versao));

  return jsonb_build_object('rodada_id', v_id, 'nome', v_nome, 'taxonomia_versao', v_versao);
end;
$$;

comment on function fn_golden_abrir_rodada(text, text, text, int) is
  'Abre uma rodada de calibração do f0/06. Recusa nome repetido em vez de deixar o unique estourar: '
  'ampliar o golden set é rodada nova, e o nome é o que uma decisão de dial cita como evidência.';

grant execute on function fn_golden_abrir_rodada(text, text, text, int) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_golden_estrato_sugerido — SUGESTÃO, e o nome da função diz isso.
--
-- O estrato é propriedade objetiva do arquivo (a 0126 o pôs em
-- `golden_documento` e não em `golden_rotulo` justamente por isso: "nenhum dos
-- dois rotuladores decide se o arquivo é escaneado"). Mas o banco não sabe
-- distinguir um PDF nativo de um PDF escaneado — isso exigiria olhar as páginas.
-- O que ele tem é a extensão e a legibilidade, e com isso dá para acertar os
-- casos fáceis e errar os difíceis.
--
-- Então isto sugere e a pessoa confirma. E como não é julgamento de conteúdo,
-- sugerir aqui não ancora nada: quem olha o arquivo vê num segundo se é um scan.
-- -----------------------------------------------------------------------------
create or replace function fn_golden_estrato_sugerido(p_documento_id uuid)
returns jsonb
language plpgsql
stable
as $$
declare
  v_nome  text;
  v_leg   legibilidade;
  v_ext   text;
begin
  select dv.nome_original, dv.legibilidade into v_nome, v_leg
  from documento_versao dv
  where dv.documento_id = p_documento_id
  order by dv.n_versao desc
  limit 1;

  if v_nome is null and v_leg is null then
    return jsonb_build_object('estrato', null,
      'porque', 'O documento não tem versão com nome de arquivo — não há de onde inferir.');
  end if;

  v_ext := lower(coalesce(substring(v_nome from '\.([A-Za-z0-9]+)$'), ''));

  if v_ext in ('xlsx', 'xls', 'csv', 'docx', 'doc', 'txt') then
    return jsonb_build_object('estrato', 'digital',
      'porque', format('Extensão .%s: arquivo de escritório, texto nativo.', v_ext));
  end if;

  if v_ext in ('jpg', 'jpeg', 'png', 'heic', 'webp') then
    return jsonb_build_object('estrato', 'foto',
      'porque', format('Extensão .%s: imagem, o pior estrato de captura.', v_ext));
  end if;

  if v_ext = 'pdf' then
    -- A legibilidade é o único sinal que o banco tem sobre a qualidade da
    -- captura, e ela é o veredito da extração, não do arquivo. Serve para
    -- separar "PDF que se leu bem" de "PDF que não se leu" — que é quase sempre
    -- um scan ruim. Quase: um PDF nativo com layout hostil também degrada.
    if v_leg is null or v_leg = 'ok' then
      return jsonb_build_object('estrato', 'pdf_nativo',
        'porque', 'PDF que a extração leu sem apontar degradação. CONFIRA: um scan legível cai '
                  'aqui por engano, e escaneado é o estrato que decide se o dial pode subir.');
    end if;
    return jsonb_build_object('estrato', 'escaneado',
      'porque', format('PDF com legibilidade "%s" — degradação é o sintoma típico de scan.', v_leg));
  end if;

  return jsonb_build_object('estrato', null,
    'porque', format('Extensão "%s" não está em nenhuma das quatro faixas. Diga você.',
                     coalesce(nullif(v_ext, ''), '(sem extensão)')));
end;
$$;

comment on function fn_golden_estrato_sugerido(uuid) is
  'Sugere o golden_estrato pela extensão e pela legibilidade. É SUGESTÃO: o banco não distingue PDF '
  'nativo de PDF escaneado sem olhar as páginas, e escaneado é justamente o estrato cujo pior caso '
  'decide a subida de dial. Sugerir aqui não ancora julgamento nenhum — estrato é propriedade do '
  'arquivo, não leitura de conteúdo.';

grant execute on function fn_golden_estrato_sugerido(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_golden_candidatos — o que pode entrar numa rodada.
--
-- Devolve o que a tela precisa para MONTAR a amostra estratificada do `f0/06`, e
-- de propósito não decide por ela: amostragem estratificada é escolha humana
-- sobre um conjunto que a pessoa conhece (qual cliente, qual arquivo era um
-- horror), e uma função que sorteasse 25 documentos entregaria uma amostra que
-- ninguém pode defender numa reunião.
--
-- `n_linhas` está aqui porque documento com zero linha extraída é candidato
-- RUIM: rotulá-lo mede a extração contra o vazio e todo campo entra como
-- ausente. Não é proibido — perda total é um dado real —, mas quem inclui
-- precisa estar vendo isso.
-- -----------------------------------------------------------------------------
create or replace function fn_golden_candidatos(p_rodada uuid default null)
returns table (
  documento_id      uuid,
  caso_id           uuid,
  caso_nome         text,
  nome_original     text,
  tipo_maquina      text,
  tipo_nome         text,
  obrigatoriedade   text,
  legibilidade      text,
  n_linhas          int,
  estrato_sugerido  text,
  estrato_porque    text,
  ja_na_rodada      boolean,
  ja_rotulado       boolean
)
language sql
stable
as $$
  select d.id,
         d.caso_id,
         c.nome,
         dv.nome_original,
         d.tipo_taxonomia,
         t.documento,
         t.obrigatoriedade::text,
         dv.legibilidade::text,
         (select count(*)::int from campo_extraido ce
           where ce.documento_versao_id = fn_versao_com_extracao(d.id)),
         (fn_golden_estrato_sugerido(d.id)->>'estrato'),
         (fn_golden_estrato_sugerido(d.id)->>'porque'),
         (p_rodada is not null and exists (
            select 1 from golden_documento gd
             where gd.rodada_id = p_rodada and gd.documento_id = d.id)),
         (p_rodada is not null and exists (
            select 1 from golden_rotulo gr
             where gr.rodada_id = p_rodada and gr.documento_id = d.id))
  from documento d
  join caso c on c.id = d.caso_id
  left join taxonomia_tipo_documento t on t.codigo = d.tipo_taxonomia
  left join lateral (
    select dv2.nome_original, dv2.legibilidade
    from documento_versao dv2
    where dv2.documento_id = d.id
    order by dv2.n_versao desc
    limit 1
  ) dv on true
  order by c.nome, d.tipo_taxonomia nulls last, dv.nome_original;
$$;

comment on function fn_golden_candidatos(uuid) is
  'Os documentos que podem entrar numa rodada, com estrato sugerido e as bandeiras de já-incluído / '
  'já-rotulado. Não sorteia a amostra de propósito: a estratificação do f0/06 é escolha humana, e '
  'amostra sorteada por função é amostra que ninguém consegue defender.';

grant execute on function fn_golden_candidatos(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_golden_incluir_documento
--
-- `origem` NÃO é inferida, e isso é decisão. O banco não tem coluna que
-- distinga documento de cliente de documento do book sintético — os dois entram
-- pelo mesmo pipeline. E a distinção governa TODAS as métricas do dial: a 0126
-- conta só `real`, porque rotular um book cujo GABARITO.json já se conhece mede o
-- instrumento e não o modelo. Chutar isso erraria em silêncio no sentido pior
-- (inflando a amostra com o que se sabe de antemão), então quem inclui declara.
-- -----------------------------------------------------------------------------
create or replace function fn_golden_incluir_documento(
  p_rodada       uuid,
  p_documento_id uuid,
  p_estrato      golden_estrato,
  p_origem       golden_origem,
  p_autor        text,
  p_nota         text default null
)
returns jsonb
language plpgsql
as $$
declare
  v_rodada golden_rodada;
  v_autor  text := nullif(trim(coalesce(p_autor, '')), '');
begin
  if v_autor is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'Sem autor: quem escolheu a amostra é parte da evidência.');
  end if;

  select * into v_rodada from golden_rodada where id = p_rodada;
  if v_rodada.id is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('Rodada %s não existe.', p_rodada));
  end if;

  -- O gatilho da 0126 já barra isto com exceção. Aqui a recusa é RETORNADA
  -- porque a tela precisa dizer o que fazer — e o que fazer é abrir rodada nova,
  -- não tentar de novo.
  if v_rodada.congelada_em is not null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('A rodada "%s" foi congelada em %s. Rodada congelada não recebe mais '
                              'documento: o f0/06 amplia com rodada NOVA, senão a evidência que '
                              'autorizou uma subida de dial muda depois da subida.',
                              v_rodada.nome, v_rodada.congelada_em::date));
  end if;

  if not exists (select 1 from documento d where d.id = p_documento_id) then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('Documento %s não existe.', p_documento_id));
  end if;

  if exists (select 1 from golden_documento gd
              where gd.rodada_id = p_rodada and gd.documento_id = p_documento_id) then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'Este documento já está nesta rodada. Como estrato e origem não se editam '
                       '(append-only), corrigi-los é rodada nova — e um documento incluído duas '
                       'vezes contaria em dobro na cobertura.');
  end if;

  if p_estrato is null or p_origem is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'Estrato e origem são obrigatórios. Estrato porque a métrica agregada sobre '
                       'estratos misturados esconde o pior caso, que é justamente o que decide a '
                       'subida; origem porque as métricas do dial contam só documento real.');
  end if;

  insert into golden_documento (rodada_id, documento_id, estrato, origem, incluido_por, nota)
  values (p_rodada, p_documento_id, p_estrato, p_origem, v_autor, p_nota);

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
  values (v_autor, 'golden_documento_incluido', 'golden_rodada:'||p_rodada,
          jsonb_build_object('documento_id', p_documento_id,
                             'estrato', p_estrato, 'origem', p_origem));

  return jsonb_build_object('rodada_id', p_rodada, 'documento_id', p_documento_id,
                            'estrato', p_estrato, 'origem', p_origem);
end;
$$;

comment on function fn_golden_incluir_documento(uuid, uuid, golden_estrato, golden_origem, text, text) is
  'Inclui um documento na rodada. Estrato e origem são obrigatórios e não inferidos: o banco não '
  'distingue documento de cliente do book sintético, e chutar isso inflaria a amostra com aquilo '
  'cujo gabarito já se conhece — que é medir o instrumento, não o modelo.';

grant execute on function fn_golden_incluir_documento(uuid, uuid, golden_estrato, golden_origem, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_golden_linhas_para_rotular — A FUNÇÃO CEGA.
--
-- Devolve as rubricas que a extração encontrou, SEM `valor_num`. É o coração do
-- desenho, e a razão está no cabeçalho desta migration: a rubrica é a chave de
-- casamento e o valor é o que se mede. Dar a rubrica evita que diferença de
-- grafia vire ausência falsa; dar o valor destruiria a independência do rótulo.
--
-- Quem mexer nesta função e acrescentar o valor ao retorno desliga o golden set
-- sem quebrar nenhum teste de tipo: as métricas continuariam sendo calculadas,
-- só deixariam de significar algo. Daí o teste em `golden_rotulagem.test.sql`
-- que falha se `valor` reaparecer no retorno.
-- -----------------------------------------------------------------------------
create or replace function fn_golden_linhas_para_rotular(
  p_rodada       uuid,
  p_documento_id uuid,
  p_rotulador    text default null
)
returns table (
  chave            text,
  secao            text,
  periodo_coluna   text,
  entidade_coluna  text,
  origem_pagina    int,
  unidade          text,
  ja_rotulada      boolean
)
language sql
stable
as $$
  select ce.chave, ce.secao, ce.periodo_coluna, ce.entidade_coluna, ce.origem_pagina, ce.unidade,
         exists (
           select 1 from golden_campo gc
            where gc.rodada_id = p_rodada
              and gc.documento_id = p_documento_id
              and (p_rotulador is null or gc.rotulador = p_rotulador)
              and fn_normalizar_texto(gc.chave) = fn_normalizar_texto(ce.chave)
              and coalesce(gc.periodo_coluna, '') = coalesce(ce.periodo_coluna, '')
              and coalesce(gc.entidade_coluna, '') = coalesce(ce.entidade_coluna, '')
         )
  from campo_extraido ce
  where ce.documento_versao_id = fn_versao_com_extracao(p_documento_id)
    and ce.valor_num is not null
  order by ce.origem_pagina nulls last, ce.ordem, ce.chave;
$$;

comment on function fn_golden_linhas_para_rotular(uuid, uuid, text) is
  'As rubricas que a extração achou, SEM O VALOR. Rotulagem cega (fechamento #5 do docs/01): quem vê '
  'o palpite da máquina produz conferência, não ground truth, e a métrica sobe sem nada melhorar. A '
  'rubrica vem porque é a chave de casamento de fn_golden_campos — esconde-la faria diferença de '
  'grafia entrar como AUSENTE, cobrando da máquina um erro de datilografia.';

grant execute on function fn_golden_linhas_para_rotular(uuid, uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_golden_rotular — o julgamento do DOCUMENTO, uma vez por rotulador.
--
-- `p_tipo_correto` é conferido contra o catálogo, e recusar tipo desconhecido não
-- é preciosismo: um erro de digitação no tipo não vira erro de digitação no
-- relatório. Ele vira um FALSO NEGATIVO permanente da máquina — o documento
-- passa a ter verdade "BALANCO_PATRIMONAL", a máquina disse "BALANCO_PATRIMONIAL"
-- e o F1 daquele tipo cai por um typo que ninguém mais vai reler, porque o rótulo
-- é append-only.
-- -----------------------------------------------------------------------------
create or replace function fn_golden_rotular(
  p_rodada                 uuid,
  p_documento_id           uuid,
  p_rotulador              text,
  p_tipo_correto           text    default null,
  p_entidade_correta       text    default null,
  p_periodo_correto        text    default null,
  p_assinado_correto       boolean default null,
  p_legibilidade           legibilidade default null,
  p_item_checklist_correto text    default null,
  p_nota                   text    default null
)
returns jsonb
language plpgsql
as $$
declare
  v_rodada    golden_rodada;
  v_rotulador text := nullif(trim(coalesce(p_rotulador, '')), '');
  v_tipo      text := nullif(trim(coalesce(p_tipo_correto, '')), '');
  v_id        uuid;
begin
  if v_rotulador is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'Rótulo sem rotulador. O f0/06 mede concordância ENTRE rotuladores, e a '
                       'chave da tabela é (rodada, documento, rotulador) exatamente para isso — '
                       'rótulo anônimo não tem como participar de concordância nenhuma.');
  end if;

  select * into v_rodada from golden_rodada where id = p_rodada;
  if v_rodada.id is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('Rodada %s não existe.', p_rodada));
  end if;
  if v_rodada.congelada_em is not null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('A rodada "%s" está congelada desde %s e não aceita mais rótulo. '
                              'Ampliar é rodada nova: evidência que ainda muda não sustenta uma '
                              'decisão registrada contra ela.',
                              v_rodada.nome, v_rodada.congelada_em::date));
  end if;

  if not exists (select 1 from golden_documento gd
                  where gd.rodada_id = p_rodada and gd.documento_id = p_documento_id) then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'Este documento não está nesta rodada. Inclua-o primeiro, declarando estrato '
                       'e origem — são eles que fazem a amostra ser estratificada em vez de ser um '
                       'monte de arquivos.');
  end if;

  if exists (select 1 from golden_rotulo gr
              where gr.rodada_id = p_rodada and gr.documento_id = p_documento_id
                and gr.rotulador = v_rotulador) then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('%s já rotulou este documento nesta rodada, e rótulo é append-only: '
                              'corrigir um rótulo depois da medição é reescrever a justificativa de '
                              'uma decisão de dial a posteriori. Se o rótulo estava errado, a '
                              'correção é rodada nova.', v_rotulador));
  end if;

  if v_tipo is not null
     and not exists (select 1 from taxonomia_tipo_documento t where t.codigo = v_tipo) then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('"%s" não é um código de tipo do catálogo. Tipo digitado errado não '
                              'fica errado só no rótulo: ele vira falso negativo permanente da '
                              'máquina no F1 daquele tipo, e ninguém relê um rótulo append-only.',
                              v_tipo));
  end if;

  -- Rótulo com todos os campos nulos é ruído: ele CONTA como documento rotulado
  -- na cobertura (a 0126 conta a existência da linha) e não mede nada. Seria a
  -- forma mais fácil de bater o n_minimo sem produzir evidência.
  if v_tipo is null and p_entidade_correta is null and p_periodo_correto is null
     and p_assinado_correto is null and p_legibilidade is null
     and p_item_checklist_correto is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'Rótulo vazio. Ele contaria como documento rotulado na cobertura e não '
                       'mediria nada — é o jeito mais fácil de bater o N mínimo do f0/06 sem '
                       'produzir evidência. Julgue ao menos um campo.');
  end if;

  insert into golden_rotulo
    (rodada_id, documento_id, rotulador, tipo_correto, entidade_correta, periodo_correto,
     assinado_correto, legibilidade, item_checklist_correto, nota)
  values
    (p_rodada, p_documento_id, v_rotulador, v_tipo,
     nullif(trim(coalesce(p_entidade_correta, '')), ''),
     nullif(trim(coalesce(p_periodo_correto, '')), ''),
     p_assinado_correto, p_legibilidade,
     nullif(trim(coalesce(p_item_checklist_correto, '')), ''), p_nota)
  returning id into v_id;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
  values (v_rotulador, 'golden_rotulo', 'golden_rodada:'||p_rodada,
          jsonb_build_object('documento_id', p_documento_id, 'rotulo_id', v_id,
                             'porque', 'rotulagem CEGA: o rotulador nao viu a resposta da maquina '
                                       '(fn_golden_linhas_para_rotular nao devolve valor). '
                                       'fechamento #5 do docs/01.'));

  return jsonb_build_object('rotulo_id', v_id, 'rotulador', v_rotulador,
                            'documento_id', p_documento_id);
end;
$$;

comment on function fn_golden_rotular(uuid, uuid, text, text, text, text, boolean, legibilidade, text, text) is
  'Grava o julgamento humano do documento (f0/06, "o que é rotulado"), um por rotulador. Recusa tipo '
  'fora do catálogo porque typo em rótulo append-only vira falso negativo permanente da máquina, e '
  'recusa rótulo vazio porque ele contaria na cobertura sem medir nada.';

grant execute on function fn_golden_rotular(uuid, uuid, text, text, text, text, boolean, legibilidade, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_golden_rotular_campos — os valores, e a REVELAÇÃO depois de gravado.
--
-- Aceita rubrica que não está na lista da máquina, de propósito: é o único jeito
-- de a perda silenciosa ser medida. Linha que o documento tem e a extração não
-- trouxe entra como rótulo sem par, e `fn_golden_campos` a conta em `n_ausente`
-- — a família de defeito que custou as três camadas de cobertura desta casa.
--
-- E devolve, POR LINHA, se ela casou com alguma linha da máquina. Isto é a
-- revelação, e ela vem DEPOIS da gravação — nunca antes. Antes seria a ancoragem
-- pela porta de trás: "sua linha não casou" durante a digitação é um convite a
-- procurar a grafia que casa, e aí o rótulo passa a perseguir a máquina.
-- Depois, é informação: quem vê 3 de 12 sem par sabe que ou a extração perdeu
-- três linhas, ou ele escreveu três rubricas de um jeito que o normalizador não
-- reconhece — e as duas coisas são coisas que ele precisa saber.
-- -----------------------------------------------------------------------------
create or replace function fn_golden_rotular_campos(
  p_rodada       uuid,
  p_documento_id uuid,
  p_rotulador    text,
  p_campos       jsonb
)
returns jsonb
language plpgsql
as $$
declare
  v_rodada    golden_rodada;
  v_rotulador text := nullif(trim(coalesce(p_rotulador, '')), '');
  v_versao    uuid;
  v_item      jsonb;
  v_chave     text;
  v_valor     numeric;
  v_tol       numeric;
  v_classe    text;
  v_per       text;
  v_ent       text;
  v_casou     boolean;
  v_gravados  jsonb := '[]'::jsonb;
  v_pulados   jsonb := '[]'::jsonb;
  v_n_sem_par int := 0;
begin
  if v_rotulador is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'Rótulo de campo sem rotulador.');
  end if;

  select * into v_rodada from golden_rodada where id = p_rodada;
  if v_rodada.id is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('Rodada %s não existe.', p_rodada));
  end if;
  if v_rodada.congelada_em is not null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('A rodada "%s" está congelada desde %s.',
                              v_rodada.nome, v_rodada.congelada_em::date));
  end if;

  if not exists (select 1 from golden_documento gd
                  where gd.rodada_id = p_rodada and gd.documento_id = p_documento_id) then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'Este documento não está nesta rodada.');
  end if;

  if p_campos is null or jsonb_typeof(p_campos) <> 'array' or jsonb_array_length(p_campos) = 0 then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'Nenhum campo para rotular.');
  end if;

  v_versao := fn_versao_com_extracao(p_documento_id);

  for v_item in select * from jsonb_array_elements(p_campos)
  loop
    v_chave := nullif(trim(coalesce(v_item->>'chave', '')), '');
    v_per   := nullif(trim(coalesce(v_item->>'periodo_coluna', '')), '');
    v_ent   := nullif(trim(coalesce(v_item->>'entidade_coluna', '')), '');
    v_valor := case when (v_item->>'valor_correto') ~ '^-?\d+(\.\d+)?$'
                    then (v_item->>'valor_correto')::numeric end;
    v_tol   := coalesce(case when (v_item->>'tolerancia') ~ '^\d+(\.\d+)?$'
                             then (v_item->>'tolerancia')::numeric end, 0);
    v_classe := nullif(trim(coalesce(v_item->>'classe_contabil_correta', '')), '');

    if v_chave is null then
      v_pulados := v_pulados || jsonb_build_object(
        'chave', v_item->>'chave', 'porque', 'sem rubrica: não haveria como casar com linha nenhuma');
      continue;
    end if;

    -- Campo sem valor é descartado e DITO. `fn_golden_campos` filtra
    -- `valor_correto is not null`, então gravá-lo criaria uma linha que existe no
    -- banco e não aparece em métrica nenhuma — o pior estado, porque quem conta
    -- rótulos acha que rotulou.
    if v_valor is null then
      v_pulados := v_pulados || jsonb_build_object(
        'chave', v_chave,
        'porque', 'sem valor numérico: fn_golden_campos só conta rótulo com valor, então esta '
                  'linha existiria no banco sem entrar em métrica nenhuma');
      continue;
    end if;

    if v_classe is not null
       and not exists (select 1 from classe_contabil_catalogo cc where cc.codigo = v_classe) then
      v_pulados := v_pulados || jsonb_build_object(
        'chave', v_chave,
        'porque', format('classe contábil "%s" não está no catálogo das cinco do docs/05', v_classe));
      continue;
    end if;

    if exists (select 1 from golden_campo gc
                where gc.rodada_id = p_rodada and gc.documento_id = p_documento_id
                  and gc.rotulador = v_rotulador
                  and gc.chave = v_chave
                  and coalesce(gc.periodo_coluna, '') = coalesce(v_per, '')
                  and coalesce(gc.entidade_coluna, '') = coalesce(v_ent, '')) then
      v_pulados := v_pulados || jsonb_build_object(
        'chave', v_chave,
        'porque', 'já rotulada por você nesta rodada (append-only: corrigir é rodada nova)');
      continue;
    end if;

    insert into golden_campo
      (rodada_id, documento_id, rotulador, chave, periodo_coluna, entidade_coluna,
       valor_correto, classe_contabil_correta, tolerancia)
    values
      (p_rodada, p_documento_id, v_rotulador, v_chave, v_per, v_ent, v_valor, v_classe, v_tol);

    -- A REVELAÇÃO, calculada com o mesmo casamento de `fn_golden_campos`: chave
    -- normalizada + período + entidade. Usar outro critério aqui faria a tela
    -- prometer um par que a métrica não vai encontrar.
    select exists (
      select 1 from campo_extraido ce
       where ce.documento_versao_id = v_versao
         and ce.valor_num is not null
         and fn_normalizar_texto(ce.chave) = fn_normalizar_texto(v_chave)
         and coalesce(ce.periodo_coluna, '') = coalesce(v_per, '')
         and coalesce(ce.entidade_coluna, '') = coalesce(v_ent, '')
    ) into v_casou;

    if not v_casou then v_n_sem_par := v_n_sem_par + 1; end if;

    v_gravados := v_gravados || jsonb_build_object(
      'chave', v_chave, 'periodo_coluna', v_per, 'entidade_coluna', v_ent,
      'valor_correto', v_valor, 'tolerancia', v_tol, 'casou_com_a_extracao', v_casou);
  end loop;

  if jsonb_array_length(v_gravados) > 0 then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values (v_rotulador, 'golden_campos', 'golden_rodada:'||p_rodada,
            jsonb_build_object('documento_id', p_documento_id,
                               'n_gravados', jsonb_array_length(v_gravados),
                               'n_sem_par', v_n_sem_par,
                               'n_pulados', jsonb_array_length(v_pulados)));
  end if;

  return jsonb_build_object(
    'gravados', v_gravados,
    'pulados', v_pulados,
    'n_gravados', jsonb_array_length(v_gravados),
    'n_sem_par', v_n_sem_par,
    -- O texto do aviso mora aqui e não na tela: o motivo é o mesmo de sempre
    -- nesta casa — quem lê o retorno da função no psql precisa ver a mesma coisa
    -- que quem lê a tela, senão existem duas verdades.
    'aviso_sem_par', case when v_n_sem_par = 0 then null else format(
      '%s linha(s) que você rotulou não casaram com nenhuma linha da extração. Isso conta como '
      'AUSENTE no placar (perda silenciosa) e pode ser uma de duas coisas: a extração perdeu a '
      'linha de verdade, ou a rubrica que você escreveu não é reconhecível como a mesma. As duas '
      'importam, e são diferentes.', v_n_sem_par) end);
end;
$$;

comment on function fn_golden_rotular_campos(uuid, uuid, text, jsonb) is
  'Grava os valores lidos pelo humano e REVELA, depois de gravar, quais casaram com a extração. '
  'Aceita rubrica fora da lista da máquina de propósito: é o único caminho pelo qual a perda '
  'silenciosa (n_ausente) chega a ser medida. Revelar antes de gravar seria ancoragem pela porta de '
  'trás — o rótulo passaria a perseguir a grafia que casa.';

grant execute on function fn_golden_rotular_campos(uuid, uuid, text, jsonb) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_golden_progresso — quanto falta, por tipo.
--
-- CUIDADO COM A AUTORIDADE, e isto já mordeu esta casa uma vez: `fn_golden_
-- cobertura` (0126) agrupa pela VERDADE do consenso, porque ela responde "a
-- amostra cobre 20 balanços de verdade?". Aqui o agrupamento é pelo tipo que a
-- MÁQUINA diz, e é o certo para esta pergunta: quem monta a amostra escolhe
-- documentos antes de rotular, e nesse momento a única etiqueta que existe é a
-- da máquina. As duas contagens podem divergir — e divergirem é justamente o
-- sinal de que a classificação erra. Por isso as duas aparecem, lado a lado, e
-- por isso o retorno diz qual é qual pelo nome da coluna.
--
-- `n_minimo` é o MAIOR entre os critérios: o dial é por estágio, cada estágio tem
-- seu mínimo, e uma barra de progresso que mostrasse o menor diria "pronto"
-- enquanto o portão de outro estágio ainda recusa.
-- -----------------------------------------------------------------------------
create or replace function fn_golden_progresso(p_rodada uuid)
returns table (
  tipo                  text,
  tipo_nome             text,
  obrigatoriedade       text,
  n_incluidos           int,
  n_rotulados           int,
  n_rotulados_verdade   int,
  n_minimo              int,
  falta                 int
)
language sql
stable
as $$
  with alvo as (
    select coalesce(max(gc.n_minimo), 20) as n from golden_criterio gc
  ),
  incl as (
    select d.tipo_taxonomia as tipo,
           count(*)::int as n_incluidos,
           count(*) filter (where exists (
             select 1 from golden_rotulo gr
              where gr.rodada_id = gd.rodada_id and gr.documento_id = gd.documento_id))::int
             as n_rotulados
    from golden_documento gd
    join documento d on d.id = gd.documento_id
    where gd.rodada_id = p_rodada and gd.origem = 'real'
    group by 1
  ),
  -- A contagem pela VERDADE, para a divergência ficar à vista: é este número que
  -- o portão do dial usa, via fn_golden_cobertura.
  verdade as (
    select c.tipo, c.n_documentos::int as n
    from fn_golden_cobertura(p_rodada) c
  )
  select coalesce(i.tipo, v.tipo),
         t.documento,
         t.obrigatoriedade::text,
         coalesce(i.n_incluidos, 0),
         coalesce(i.n_rotulados, 0),
         coalesce(v.n, 0),
         (select n from alvo),
         greatest((select n from alvo) - coalesce(v.n, 0), 0)
  from incl i
  full outer join verdade v on v.tipo = i.tipo
  left join taxonomia_tipo_documento t on t.codigo = coalesce(i.tipo, v.tipo)
  order by t.obrigatoriedade, 1;
$$;

comment on function fn_golden_progresso(uuid) is
  'Quanto falta para a rodada bater o N do f0/06, por tipo. Traz DUAS contagens de propósito: '
  'n_rotulados agrupa pelo tipo que a MÁQUINA diz (é a etiqueta que existe na hora de montar a '
  'amostra) e n_rotulados_verdade pelo consenso humano (é o que o portão do dial conta). Divergirem '
  'não é bug: é o erro de classificação aparecendo.';

grant execute on function fn_golden_progresso(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_golden_congelar — o ato que transforma rótulo em EVIDÊNCIA.
--
-- Congelar é o que dá data à evidência, e é por isso que `fn_golden_suficiente`
-- recusa rodada não congelada. A recusa aqui que mais importa é a de rodada
-- VAZIA: uma rodada congelada com zero rótulo passaria pelo teste de
-- "congelada?", chegaria ao portão e seria reprovada por outro motivo — mas
-- ficaria na lista de rodadas do painel parecendo evidência.
--
-- E documento incluído e NÃO rotulado não impede o congelamento, de propósito.
-- Ele não conta em métrica nenhuma (as métricas partem do rótulo), então não
-- contamina nada; e proibir seria obrigar quem desistiu de um arquivo a rotulá-lo
-- de qualquer jeito para poder fechar a rodada — o que produziria rótulo ruim,
-- que é pior que rótulo nenhum. O número aparece no retorno para ficar dito.
-- -----------------------------------------------------------------------------
create or replace function fn_golden_congelar(p_rodada uuid, p_autor text)
returns jsonb
language plpgsql
as $$
declare
  v_rodada     golden_rodada;
  v_autor      text := nullif(trim(coalesce(p_autor, '')), '');
  v_n_doc      int;
  v_n_rot      int;
  v_n_campos   int;
  v_n_sem_rot  int;
  v_rotuladores text[];
begin
  if v_autor is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'Congelar sem autor. O congelamento é o ato que transforma rótulo em '
                       'evidência datada, e evidência sem quem a fechou não datou nada.');
  end if;

  select * into v_rodada from golden_rodada where id = p_rodada;
  if v_rodada.id is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('Rodada %s não existe.', p_rodada));
  end if;

  if v_rodada.congelada_em is not null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('A rodada "%s" já foi congelada em %s por %s. Descongelar é recusado '
                              'pelo gatilho da 0126: uma rodada que volta a aceitar rótulo depois '
                              'de ter autorizado uma subida de dial reabre o furo que congelar '
                              'fecha.', v_rodada.nome, v_rodada.congelada_em::date,
                              coalesce(v_rodada.congelada_por, '?')));
  end if;

  select count(*)::int into v_n_doc
    from golden_documento gd where gd.rodada_id = p_rodada;
  select count(*)::int into v_n_rot
    from golden_rotulo gr where gr.rodada_id = p_rodada;
  select count(*)::int into v_n_campos
    from golden_campo gc where gc.rodada_id = p_rodada;

  if v_n_rot = 0 then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('A rodada "%s" tem %s documento(s) e nenhum rótulo. Congelada assim '
                              'ela apareceria na lista de rodadas parecendo evidência, e não é: '
                              'congelar dá DATA a um julgamento que aqui não existe.',
                              v_rodada.nome, v_n_doc));
  end if;

  select count(*)::int into v_n_sem_rot
  from golden_documento gd
  where gd.rodada_id = p_rodada
    and not exists (select 1 from golden_rotulo gr
                     where gr.rodada_id = gd.rodada_id and gr.documento_id = gd.documento_id);

  select array_agg(distinct gr.rotulador order by gr.rotulador) into v_rotuladores
    from golden_rotulo gr where gr.rodada_id = p_rodada;

  update golden_rodada
     set congelada_em = now(), congelada_por = v_autor
   where id = p_rodada;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
  values (v_autor, 'golden_rodada_congelada', 'golden_rodada:'||p_rodada,
          jsonb_build_object('nome', v_rodada.nome, 'n_documentos', v_n_doc,
                             'n_rotulos', v_n_rot, 'n_campos', v_n_campos,
                             'n_documentos_sem_rotulo', v_n_sem_rot,
                             'rotuladores', to_jsonb(v_rotuladores)));

  return jsonb_build_object(
    'rodada_id', p_rodada, 'nome', v_rodada.nome, 'congelada_por', v_autor,
    'n_documentos', v_n_doc, 'n_rotulos', v_n_rot, 'n_campos', v_n_campos,
    'n_documentos_sem_rotulo', v_n_sem_rot,
    'rotuladores', to_jsonb(v_rotuladores),
    -- UM ROTULADOR SÓ É UMA ESCOLHA LEGÍTIMA COM UMA CONSEQUÊNCIA MEDÍVEL, e ela
    -- fica dita no ato de congelar em vez de descoberta quando o número não
    -- fecha. O f0/06 pede dois rotuladores "nos casos ambíguos" para que a
    -- discordância entre humanos seja EXCLUÍDA do placar da máquina. Com um só,
    -- não há discordância a excluir: o documento genuinamente ambíguo entra como
    -- erro da máquina, e a medição fica CONSERVADORA — subestima a qualidade.
    -- Conservador é o lado certo para errar, e mesmo assim precisa estar escrito:
    -- quem lê "acerto 0,91" tem direito de saber que 0,91 é um piso.
    'aviso_rotulador_unico', case when coalesce(array_length(v_rotuladores, 1), 0) > 1 then null else
      format('Rodada rotulada só por %s. fn_golden_inter_avaliador não terá dado, e nada será '
             'excluído do placar por "humanos discordam" — documento ambíguo conta como erro da '
             'máquina. A medição fica conservadora: o número que sair é um PISO da qualidade real, '
             'não uma estimativa dela.', coalesce(v_rotuladores[1], '?')) end);
end;
$$;

comment on function fn_golden_congelar(uuid, text) is
  'Congela a rodada — o ato que dá DATA à evidência e sem o qual fn_golden_suficiente não autoriza '
  'subida. Recusa rodada sem nenhum rótulo (apareceria na lista parecendo evidência) e não recusa '
  'documento incluído sem rótulo (ele não entra em métrica, e exigi-lo produziria rótulo ruim, que é '
  'pior que rótulo nenhum). Avisa quando houve um rotulador só: aí a medição é um piso.';

grant execute on function fn_golden_congelar(uuid, text) to authenticated;

-- =============================================================================
-- Migration 0161 — A pendência de PERÍODO calava a mesma justificativa que a
-- de TIPO já mostra.
--
-- MEDIDO NA RODADA REAL do lote `7377` (02/09, mandato "teste Canastra", ver
-- `ESTADO.md` seção "SESSÃO 79"). Das 13 pendências daquela rodada, um
-- explorador separou 4 como DIVERGÊNCIA REAL entre nome do arquivo e conteúdo
-- do documento (`27_Composicao_do_Imobilizado` registrado NOTAS_EXPL com
-- diagnóstico sugerindo BALANCO; `35_Demonstracoes_Contabeis` registrado
-- DF_AUDITADA com diagnóstico sugerindo BALANCO; e 2 documentos comparativos
-- multi-ano em que o diagnóstico propõe a data-base em vez do intervalo) —
-- casos em que a regra 1 deste projeto proíbe decidir sozinho: não há como
-- saber, só pelo nome do arquivo, se o documento É balanço ou nota, ou se o
-- período certo é o intervalo ou a data-base. Certo. A pergunta desta fatia
-- não é "quem decide" — é "o revisor que abre a pendência tem o que precisa
-- para decidir em segundos, ou tem que caçar a informação?".
--
-- MEDIDO CONTRA O CORPO VIGENTE de `fn_registrar_diagnostico` (o que vale — não
-- o texto de nenhuma migration sozinha, ver 0147): as duas famílias abrem a
-- pendência assim (`Supabase/schema.sql`, função vigente antes desta migration):
--
--   tipo_incorreto (ramo ~linha 8488-8492):
--     format('Diagnóstico de conteúdo sugere tipo "%s" (documento está
--            registrado como "%s"). %s',
--            coalesce(p_tipo_sugerido, '?'), coalesce(v_tipo_atual, '(nenhum)'),
--            coalesce(p_justificativa, ''))
--
--   periodo_incorreto (ramo ~linha 8513-8517):
--     format('Diagnóstico de conteúdo sugere período "%s %s" (documento está
--            registrado com "%s %s").',
--            p_periodo_tipo, p_periodo_referencia,
--            coalesce(v_periodo_tipo_atual, '?'), coalesce(v_periodo_ref_atual, '(nenhum)'))
--     -- SEM `p_justificativa` no final.
--
-- A CAUSA, medida por leitura do corpo vigente e de `N8N/lib/extract.mjs`
-- (o prompt que produz o parâmetro): `p_justificativa` é UMA SÓ explicação por
-- documento — "1-2 frases explicando o diagnóstico acima (o que você viu ou
-- não viu)" — cobrindo entidade, tipo, período e legibilidade JUNTOS, e chega
-- pronta na MESMA chamada de `fn_registrar_diagnostico` que abre as duas
-- pendências. O ramo de tipo_incorreto já a mostra desde que existe (nem uma
-- migration à parte foi precisa); o de periodo_incorreto nunca a citou — não
-- por decisão, o `format()` do período simplesmente não tinha o `%s` extra.
-- Um revisor abrindo uma pendência de `periodo_incorreto` (itens 3 e 4 do
-- lote 7377) vê o período sugerido contra o registrado, mas não vê POR QUE o
-- diagnóstico chegou lá — mesmo quando o modelo já escreveu essa razão, e ela
-- está sentada no banco, na mesma linha de `evento_auditoria` que a pendência.
--
-- O QUE ISTO NÃO É: não é o gap de confiança (`confianca`) que o diagnóstico
-- de conteúdo produz (`N8N/lib/ia.mjs`/`extract.mjs`) — CONFIRMADO por leitura
-- de `fn_registrar_diagnostico` (onze parâmetros, nenhum é confiança) e de
-- `evento_auditoria` (o jsonb gravado no fim da função também não carrega
-- `confianca`): o valor nunca chega a ser parâmetro da função nem é
-- persistido em lugar nenhum no momento em que a pendência abre. Não é "o
-- banco já sabe e não conta" — é "o banco nunca recebeu". Fechar esse gap
-- pediria mudar a ASSINATURA da função e a query do n8n que a chama
-- (`N8N/build-workflow.mjs`), o que é bem mais que enriquecer a mensagem com
-- o que já está em mãos — fora do escopo desta fatia, registrado aqui para
-- não se perder.
--
-- Também não é `documento_fato`/`fato_tipo_catalogo` (0148/0149): aquele
-- catálogo é sobre FATOS MATERIAIS declarados em texto corrido (continuidade
-- operacional, covenant rompido, ressalva de auditoria...), um domínio
-- diferente de "este documento é BALANCO ou NOTAS_EXPL" — não haveria fato
-- material a citar aqui mesmo se o catálogo fosse consultado.
--
-- ---------------------------------------------------------------------------
-- O QUE ESTA MIGRATION FAZ, E SÓ ISTO
-- ---------------------------------------------------------------------------
-- Acrescenta `coalesce(p_justificativa, '')` ao FORMAT do `periodo_incorreto`,
-- espelhando exatamente o que o `tipo_incorreto` já faz — mesmo parâmetro,
-- mesma função, mesma chamada. NÃO toca `tipo`, `severidade` nem
-- `sobrepujavel` (são esses três campos — não o `motivo` — que governam a
-- fila de revisão e o fechamento por `fn_revisar_documento`, por doutrina do
-- projeto): a pendência continua exatamente a mesma decisão pendente, só com
-- a razão do diagnóstico visível sem precisar abrir `evento_auditoria` à
-- parte. Não decide se o período certo é o intervalo ou a data-base — só
-- pára de esconder o "por quê" que o próprio diagnóstico já escreveu.
--
-- PATCH COM ÂNCORA sobre o corpo VIGENTE (não reemissão inteira) pela mesma
-- razão da 0160: reemitir copiando o texto de uma migration antiga arrisca
-- regredir em silêncio um patch mais novo que só existe no corpo aplicado.
-- =============================================================================

do $mig$
declare
  v_src text; v_novo text; v_n_antes int; v_n_depois int;
  v_pat constant text :=
    'format(''Diagnóstico de conteúdo sugere período "%s %s" (documento está registrado com "%s %s").'',' || E'\n' ||
    '                 p_periodo_tipo, p_periodo_referencia, coalesce(v_periodo_tipo_atual, ''?''), coalesce(v_periodo_ref_atual, ''(nenhum)'')),';
  v_rep constant text :=
    'format(''Diagnóstico de conteúdo sugere período "%s %s" (documento está registrado com "%s %s"). %s'',' || E'\n' ||
    '                 p_periodo_tipo, p_periodo_referencia, coalesce(v_periodo_tipo_atual, ''?''), coalesce(v_periodo_ref_atual, ''(nenhum)''),' || E'\n' ||
    '                 coalesce(p_justificativa, '''')),';
begin
  select pg_get_functiondef(p.oid) into v_src
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'fn_registrar_diagnostico';

  if v_src is null then
    raise exception '0161: fn_registrar_diagnostico não existe — migration fora de ordem';
  end if;

  v_n_antes := (length(v_src) - length(replace(v_src, v_pat, ''))) / greatest(length(v_pat), 1);
  if v_n_antes <> 1 then
    raise exception '0161: o bloco do format() de periodo_incorreto não foi encontrado UMA vez (achei %) — este patch precisa ser relido por gente', v_n_antes;
  end if;

  v_novo := replace(v_src, v_pat, v_rep);

  execute v_novo;

  -- Confere em vez de confiar.
  select pg_get_functiondef(p.oid) into v_src
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'fn_registrar_diagnostico';
  if position('registrado com "%s %s"). %s' in v_src) = 0 then
    raise exception '0161: a função foi recriada sem o `%%s` novo no format() do período — abortado';
  end if;
  if position('0142: exige divergência ACIONÁVEL' in v_src) = 0 then
    raise exception '0161: o patch apagou o da 0142 — abortado';
  end if;
  if position('0160: o nome que não casou' in v_src) = 0 then
    raise exception '0161: o patch apagou o da 0160 — abortado';
  end if;
end $mig$;

comment on function fn_registrar_diagnostico(uuid, uuid, text, boolean, text, text, text, legibilidade, text, text, text) is
  'Registra o diagnóstico de conteúdo (E1/E2) e confere contra o que já está no banco. 0121: a '
  'entidade casa e diverge pela forma CANÔNICA. 0142: tipo só diverge com divergência ACIONÁVEL. '
  '0160: quando a entidade não casa, mas o nome diagnosticado é ELE MESMO outra (ou mais de uma) '
  'empresa já cadastrada no mesmo caso, a função não sabe se o registro está certo ou errado — não '
  'presume nenhuma das duas, nomeia as candidatas na pendência e deixa a revisão decidir, sem '
  'fundir nem mover o documento sozinha. 0161: a pendência de periodo_incorreto passa a citar a '
  'justificativa do diagnóstico, como o tipo_incorreto já fazia — mesmo parâmetro, mesma chamada, '
  'sem decidir nada novo.';

grant execute on function fn_registrar_diagnostico(uuid, uuid, text, boolean, text, text, text, legibilidade, text, text, text) to authenticated;

-- =============================================================================
-- SONDA
-- =============================================================================
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('periodo_incorreto_cita_justificativa', '0161', 'corpo', 'fn_registrar_diagnostico',
   'registrado com "%s %s"). %s', null,
   'Medido no lote 7377 (02/09): as pendências `periodo_incorreto` (2 dos 4 achados que o '
   'explorador marcou como divergência real, sem resposta automática honesta) mostravam o período '
   'sugerido contra o registrado mas nunca a justificativa do diagnóstico — mesmo ela chegando '
   'pronta na MESMA chamada e o `tipo_incorreto` já mostrando a mesma informação desde sempre. '
   'Sem isto, o revisor decide sem a razão que o próprio diagnóstico escreveu.',
   'importante', 590)
on conflict (chave) do update
  set migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
      marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
      porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0161',
       revisado_em = date '2026-09-09',
       observacao = 'Revisão de 09/09/2026: a 0161 acrescenta `coalesce(p_justificativa, '''')` ao '
                    'format() de periodo_incorreto em fn_registrar_diagnostico, espelhando o que '
                    'tipo_incorreto já fazia — mesmo parâmetro, mesma chamada, sem decidir tipo, '
                    'severidade ou sobrepujavel. Os outros 3 dos 4 achados do lote 7377 marcados '
                    'como "divergência real" (2 tipo_incorreto + o par de periodo_incorreto que '
                    'gerou esta migration) não precisam de migration própria: a pendência '
                    'tipo_incorreto já cita a justificativa desde antes desta revisão, e não há '
                    'campo de confiança ou fato material aplicável ainda gravado no banco para '
                    'aquele instante (`confianca` nunca é parâmetro de fn_registrar_diagnostico, '
                    'nem é persistida em evento_auditoria) — enriquecer com ela pediria mudar a '
                    'assinatura da função e a chamada do n8n, fora do escopo de "o que o banco já '
                    'sabe e não está dizendo".'
 where id;

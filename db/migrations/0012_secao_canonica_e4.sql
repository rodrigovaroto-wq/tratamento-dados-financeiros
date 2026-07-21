-- =============================================================================
-- Migration 0012 — Seção canônica sugerida pela IA (E4, classificação do export)
--
-- Problema: o classificador de seção do export (portal/src/lib/statement-
-- templates.ts) é determinístico (palavras-chave + casamento tolerante). Ele
-- cobre bem o vocabulário contábil comum, mas cada mandato tem um plano de
-- contas diferente — contas com nome incomum caem em "Contas Não Classificadas"
-- até alguém ampliar as listas de palavras-chave. Meta do dono: ≥90% dos campos
-- extraídos dentro das tabelas/categorias certas.
--
-- Solução (doutrina docs/01, N1 — sugestão, nunca fato): a MESMA chamada de
-- extração (n8n/lib/extract.mjs) que já roda para todo documento passa a
-- devolver, por linha, uma `secao_canonica` — a IA classifica a conta pelo
-- SIGNIFICADO contábil (não só o nome literal) numa seção padronizada. Não
-- aumenta o nº de chamadas à OpenAI (mesmo padrão do diagnóstico, 0010).
--
-- O classificador do export usa essa sugestão como ÚLTIMO recurso — só quando
-- ele mesmo (âncora/seção-livre/palavra-chave) não classificou. Não sobrepõe a
-- regra determinística (que não precisa de golden set para ser confiável);
-- apenas preenche a lacuna que hoje viraria "Não Classificada". A linha
-- continua PENDENTE/âmbar no export até o aceite humano (anti-ancoragem): a
-- seção afeta só ONDE a linha aparece, nunca torna o número um fato.
--
-- Para SUBIR o dial (fazer a IA ter prioridade sobre a regra determinística, ou
-- auto-clear), é preciso golden set + concordância medida (docs/01 regra de
-- ouro, f0/06) — não é o que esta migration faz.
-- =============================================================================

alter table campo_extraido
  add column if not exists secao_canonica text;  -- sugestão da IA (enum lógico em statement-templates.ts / extract.mjs); null = sem sugestão / não classificável
comment on column campo_extraido.secao_canonica is
  'Seção canônica SUGERIDA pela IA na extração (E2), pelo significado contábil da conta. '
  'Chaves = as de statement-templates.ts (ativo_circulante, dre custos, atividades_investimento, etc.). '
  'N1/advisory: usada só como fallback do classificador determinístico do export; nunca vira fato sem aceite humano.';

-- -----------------------------------------------------------------------------
-- fn_registrar_campos_extraidos — mesma assinatura de 0005/0006/0010 (sem
-- DROP); agora também grava `secao_canonica` por linha (quando presente).
-- -----------------------------------------------------------------------------
create or replace function fn_registrar_campos_extraidos(
  p_documento_versao_id uuid,
  p_campos jsonb,
  p_nivel nivel_autonomia default 'N0'
)
returns int
language plpgsql
as $$
declare
  v_count int := 0;
  v_item jsonb;
begin
  if p_campos is null or jsonb_typeof(p_campos) <> 'array' then
    return 0;
  end if;

  for v_item in select * from jsonb_array_elements(p_campos)
  loop
    insert into campo_extraido
      (documento_versao_id, chave, valor_texto, valor_num, unidade, confianca,
       origem_pagina, origem_linha, nivel_autonomia, secao, secao_canonica)
    values (
      p_documento_versao_id,
      coalesce(v_item->>'chave', '(sem rótulo)'),
      v_item->>'valor_texto',
      case when (v_item->>'valor_num') ~ '^-?\d+(\.\d+)?$' then (v_item->>'valor_num')::numeric else null end,
      v_item->>'unidade',
      case when (v_item->>'confianca') ~ '^-?\d+(\.\d+)?$' then (v_item->>'confianca')::numeric else null end,
      case when (v_item->>'origem_pagina') ~ '^\d+$' then (v_item->>'origem_pagina')::int else null end,
      v_item->>'origem_linha',
      p_nivel,
      v_item->>'secao',
      v_item->>'secao_canonica'
    );
    v_count := v_count + 1;
  end loop;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:n8n', 'extracao_sombra', 'documento_versao:'||p_documento_versao_id,
            jsonb_build_object('campos', v_count, 'nivel', p_nivel));

  return v_count;
end;
$$;

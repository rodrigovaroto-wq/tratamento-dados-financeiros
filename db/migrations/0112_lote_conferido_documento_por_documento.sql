-- =============================================================================
-- Migration 0112 — Documento que o pipeline PULOU passa a ser denunciado
--
-- O QUE O "Teste V45 - Canastra" MOSTROU, e que é pior que qualquer número errado:
-- dos 35 documentos registrados, **19 nunca tiveram a extração chamada**. Não
-- vieram errados, não vieram truncados, não vieram vazios — a chamada nunca
-- aconteceu. E o sistema INTEIRO ficou calado:
--
--   • `campo_extraido`: nenhuma linha (não há o que conferir);
--   • `evento_auditoria`: nenhum `extracao_sombra` (a função nem foi chamada);
--   • `pendencia`: nenhuma `extracao_falhou` (o Sinal 3 da 0016/0043 mora DENTRO
--     de `fn_registrar_campos_extraidos`, e ela não rodou);
--   • o portal: 35 documentos "presentes", checklist verde, Portão 1 satisfeito.
--
-- A causa foi de mecânica do n8n (duas conexões cruas no mesmo input do
-- `Registrar Documento` — corrigida no mesmo commit com um nó Merge e o
-- `Recompor Contexto`). Mas a LIÇÃO é outra, e é estrutural: **toda guarda de
-- extração deste repositório vive dentro do caminho da extração.** Guarda que
-- mora no caminho não cobre o caso de o caminho não ser percorrido. Era o único
-- modo de falha que nenhuma das três camadas de cobertura podia ver, porque as
-- três medem o que VOLTOU de uma chamada que foi feita.
--
-- `fn_conferir_lote` mede de fora: compara os documentos REGISTRADOS no caso com
-- os que têm evento de extração, e nomeia os que ficaram sem. É a pergunta que
-- ninguém estava fazendo — "o pipeline passou por todos?" — e ela não custa IA.
--
-- Abre pendência BLOQUEANTE: um documento nunca extraído é um buraco no dado
-- entregue, e o book sai incompleto sem que nada no arquivo diga isso. Diferente
-- de `item_sem_conteudo` (0036), que trata do obrigatório que chegou VAZIO: aqui
-- o documento pode ser complementar e o problema é o mesmo — ele foi pulado.
-- =============================================================================

alter type pendencia_tipo add value if not exists 'documento_nao_extraido';

-- -----------------------------------------------------------------------------
-- fn_documentos_nao_extraidos — os documentos do caso sem NENHUM evento de
-- extração em NENHUMA das suas versões.
--
-- Por que `evento_auditoria` e não `campo_extraido`: um documento pode
-- legitimamente ter zero linha (certidão, organograma — ver 0111), e nesse caso
-- a extração ACONTECEU. O que esta função procura é a ausência da CHAMADA, e o
-- único rastro dela é o `extracao_sombra` que `fn_registrar_campos_extraidos`
-- grava sempre — inclusive quando grava zero campo.
-- -----------------------------------------------------------------------------
create or replace function fn_documentos_nao_extraidos(p_caso_id uuid)
returns table (documento_id uuid, tipo_taxonomia text, nome_original text)
language sql
stable
as $$
  select d.id, d.tipo_taxonomia,
         (select dv.nome_original from documento_versao dv
           where dv.documento_id = d.id order by dv.n_versao desc limit 1)
  from documento d
  where d.caso_id = p_caso_id
    and not exists (
      select 1
      from documento_versao dv
      join evento_auditoria ea
        on ea.acao = 'extracao_sombra'
       and ea.entidade_ref = 'documento_versao:' || dv.id::text
      where dv.documento_id = d.id
    )
  order by d.tipo_taxonomia, 3;
$$;

comment on function fn_documentos_nao_extraidos(uuid) is
  'Documentos do caso para os quais a extração NUNCA foi chamada (sem evento extracao_sombra em '
  'nenhuma versão). Zero linha com extração feita NÃO entra aqui — isso é 0111/0036.';

grant execute on function fn_documentos_nao_extraidos(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_conferir_lote — a conferência de fora, chamada no fim da execução.
--
-- Idempotente e AUTO-RESOLVENTE pelo mesmo padrão dos outros sinais: reprocessar
-- o documento faz a pendência dele se fechar sozinha, porque o evento passa a
-- existir. Uma pendência por DOCUMENTO (não uma por lote): é o documento que
-- precisa ser reprocessado, e uma pendência agregada não diz qual.
-- -----------------------------------------------------------------------------
create or replace function fn_conferir_lote(p_caso_id uuid)
returns jsonb
language plpgsql
as $$
declare
  v_total       int;
  v_nao_extr    int := 0;
  v_d           record;
  v_nomes       text[] := array[]::text[];
begin
  if not exists (select 1 from caso where id = p_caso_id) then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('caso %s não encontrado', p_caso_id));
  end if;

  select count(*) into v_total from documento where caso_id = p_caso_id;

  -- Resolve as que voltaram a ter extração (reprocessamento fecha sozinho).
  update pendencia p
     set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:conferir_lote'
   where p.caso_id = p_caso_id
     and p.tipo = 'documento_nao_extraido'
     and p.estado <> 'resolvida'
     and not exists (
       select 1 from fn_documentos_nao_extraidos(p_caso_id) x
        where p.motivo = 'lote:nao_extraido:' || x.documento_id::text
     );

  for v_d in select * from fn_documentos_nao_extraidos(p_caso_id) loop
    v_nao_extr := v_nao_extr + 1;
    v_nomes := v_nomes || coalesce(v_d.nome_original, '(sem nome)');

    if not exists (
      select 1 from pendencia p
       where p.caso_id = p_caso_id
         and p.tipo = 'documento_nao_extraido'
         and p.estado <> 'resolvida'
         and p.motivo = 'lote:nao_extraido:' || v_d.documento_id::text
    ) then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel,
                             descricao, documento_id, motivo)
        values (p_caso_id, 'extracao', 'documento_nao_extraido', 'bloqueante', false,
          format('O documento "%s" (%s) foi registrado no caso, mas a extração NUNCA foi '
                 'chamada para ele — não é extração vazia nem truncada: a chamada não '
                 'aconteceu. O book sai sem NENHUMA linha deste documento. Reprocessar o '
                 'lote; se repetir, o defeito é de roteamento no workflow (ver o log da '
                 'execução no n8n).',
                 coalesce(v_d.nome_original, '(sem nome)'),
                 coalesce(v_d.tipo_taxonomia, 'sem tipo')),
          v_d.documento_id, 'lote:nao_extraido:' || v_d.documento_id::text);
    end if;
  end loop;

  return jsonb_build_object(
    'caso_id', p_caso_id,
    'documentos_no_caso', v_total,
    'documentos_extraidos', v_total - v_nao_extr,
    'documentos_nao_extraidos', v_nao_extr,
    'nomes_nao_extraidos', to_jsonb(v_nomes),
    -- O lote só está íntegro quando TODO documento registrado passou pela
    -- extração. É a pergunta que faltava, e a resposta é um booleano só.
    'lote_integro', v_nao_extr = 0
  );
end;
$$;

comment on function fn_conferir_lote(uuid) is
  'Conferência de FORA do caminho da extração: nomeia os documentos que o pipeline pulou e abre '
  'pendência bloqueante por documento. Existe porque as guardas de extração vivem DENTRO da '
  'extração, e não cobrem o caso de a chamada nunca ter sido feita (Teste V45: 19 de 35).';

grant execute on function fn_conferir_lote(uuid) to authenticated;

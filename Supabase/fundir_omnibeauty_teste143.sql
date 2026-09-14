-- =============================================================================
-- FUSÃO RETROATIVA — as quatro linhas da OMNIBEAUTY no caso "teste 143"
--
-- ISTO MUDA DADO DE PRODUÇÃO. Nenhuma migration faz isso, e é de propósito: a
-- migration 0168 impede o PRÓXIMO lote de nascer fragmentado, mas não toca no
-- que já está gravado. Quem decide fundir é o dono do mandato, não o código.
--
-- O QUE ESTE ARQUIVO CONSERTA. No export do caso "teste 143" a OMNIBEAUTY
-- aparece como QUATRO empresas, em quatro blocos de coluna separados no book:
--
--     OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE                 7 documentos
--     OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE MARCAS LTDA     2 documentos
--     OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE SURUBIJU        1 documento
--     OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE SURUBIJU, 1930  1 documento
--
-- O efeito: o balanço de 2023 fica num bloco sozinho e não compara com nada, e
-- o faturamento cai fora do grupo.
--
-- A PROVA DE QUE SÃO UMA SÓ NÃO ESTÁ NO NOME — ESTÁ NO CNPJ. Isto é o ponto
-- desta cabeçalho, e é a razão de a 0168 NÃO ter fundido as quatro sozinha:
-- medido par a par com `fn_mesma_entidade`, "…DE MARCAS" e "…DE SURUBIJU" NÃO
-- casam ("marcas" não é prefixo de "surubiju"), e pelo nome são tão
-- indistinguíveis de duas empresas irmãs quanto "Araucária Bioenergia" e
-- "Araucária Imobiliária" são. Quem prova que são a mesma é o CNPJ
-- **36.193.378/0001-04**, o mesmo nos dois balanços que o dono anexou — um
-- dado que o algoritmo não recebe e que o dono leu com os olhos.
--
-- Por isso este arquivo é executado por uma PESSOA que conferiu o CNPJ, e não
-- por uma migration.
--
-- "SURUBIJU, 1930" é o ENDEREÇO: o template do contador trunca a razão social
-- num campo de largura fixa e imprime o endereço na linha de baixo, sem
-- separação visual (conferido em `OMNIBEAUTY - FATURAMENTO 2024.pdf`).
--
-- COMO RODAR, nesta ordem:
--
--   PARTE 1 — só lê. Rode sozinha e CONFIRA o que ela mostra: são quatro
--             linhas? os documentos são os que você espera? o nome que vai
--             sobreviver é o certo?
--   PARTE 2 — muda. Só rode depois de conferir a Parte 1.
--
-- A Parte 2 é IDEMPOTENTE: rodada duas vezes, a segunda não faz nada e diz
-- isso. E ela NÃO apaga documento nenhum — `fn_fundir_entidade` move os
-- documentos, o checklist, as pendências e as reconciliações para a entidade
-- que fica, resolve a pendência de ambiguidade, e grava em `evento_auditoria`
-- o nome que existia e quantos documentos mudaram de dono. Só a LINHA vazia da
-- entidade absorvida é removida.
--
-- POR QUE NÃO `update documento ... delete from entidade`, que é o que um
-- plano anterior propunha: `fn_fundir_entidade` (0153) já existe e leva junto
-- `checklist_item_status`, `pendencia` e `reconciliacao` — deixá-los para trás
-- faria o Portão 1 continuar cobrando de uma empresa que não existe mais.
-- =============================================================================


-- =============================================================================
-- PARTE 1 — CONFERÊNCIA (só lê; rode e leia antes de qualquer coisa)
-- =============================================================================
with caso as (
  select id from caso where nome = 'teste 143'
)
select e.id,
       e.razao_social,
       e.cnpj,
       count(d.id)                                   as documentos,
       min(d.criado_em)                              as primeiro_documento,
       string_agg(distinct d.tipo_taxonomia, ', ')  as tipos,
       case when e.razao_social = 'OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE MARCAS LTDA'
            then '<<< ESTA FICA'  else 'será absorvida' end as destino
  from entidade e
  join caso c on c.id = e.caso_id
  left join documento d on d.entidade_id = e.id
 where e.razao_social ilike '%omnibeauty%'
 group by e.id, e.razao_social, e.cnpj
 order by primeiro_documento nulls last;

-- E os eventos que o `fn_upsert_entidade` deixou quando criou as linhas extras.
-- `entidade_ambigua` é a 0153 recusando escolher; `entidade_alias_fundido` é a
-- 0168 já tendo evitado uma delas (não aparece neste lote, que é anterior).
select ev.criado_em, ev.acao, ev.entidade_ref, ev.depois
  from evento_auditoria ev
 where ev.acao in ('entidade_ambigua', 'entidade_alias_fundido')
   and ev.depois->>'caso_id' = (select id::text from caso where nome = 'teste 143')
 order by ev.criado_em;


-- =============================================================================
-- PARTE 2 — A FUSÃO (muda dado; só depois de conferir a Parte 1)
--
-- O NOME QUE SOBREVIVE é "OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE MARCAS LTDA",
-- e a regra é declarada em vez de esperta: é a única das quatro que é uma razão
-- social COMPLETA — tem o sufixo societário no fim e não tem endereço colado.
-- As outras três são o mesmo nome truncado ("…GESTAO DE") ou truncado com o
-- endereço grudado ("…SURUBIJU", "…SURUBIJU, 1930").
--
-- Se você quiser que sobreviva outro nome, troque a constante `c_fica` abaixo —
-- ela aparece UMA vez.
-- =============================================================================
do $$
declare
  c_fica constant text := 'OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE MARCAS LTDA';
  v_caso   uuid;
  v_para   uuid;
  v_n      int;
  v_r      jsonb;
  v_docs   int := 0;
  v_alvo   record;
begin
  select id into v_caso from caso where nome = 'teste 143';
  if v_caso is null then
    raise exception 'não achei o caso "teste 143" neste banco — confira em que projeto você está';
  end if;

  select count(*) into v_n
    from entidade where caso_id = v_caso and razao_social ilike '%omnibeauty%';

  if v_n = 0 then
    raise exception 'nenhuma entidade OMNIBEAUTY neste caso — nada a fundir, e isso é suspeito';
  end if;

  if v_n = 1 then
    -- IDEMPOTENTE: já foi fundida (por esta rodada ou por outra). Não faz nada.
    raise notice 'NADA A FAZER: a OMNIBEAUTY já é UMA entidade só neste caso.';
    return;
  end if;

  select id into v_para
    from entidade where caso_id = v_caso and razao_social = c_fica;

  if v_para is null then
    raise exception 'não achei a entidade que deveria SOBREVIVER ("%"). As que existem são: %',
      c_fica,
      (select string_agg(razao_social, ' | ' order by razao_social)
         from entidade where caso_id = v_caso and razao_social ilike '%omnibeauty%');
  end if;

  raise notice 'Fundindo % entidades OMNIBEAUTY em "%"', v_n - 1, c_fica;

  for v_alvo in
    select id, razao_social
      from entidade
     where caso_id = v_caso and razao_social ilike '%omnibeauty%' and id <> v_para
     order by razao_social
  loop
    v_r := fn_fundir_entidade(v_caso, v_alvo.id, v_para, 'humano:fusao_omnibeauty_teste143');
    v_docs := v_docs + (v_r->>'documentos')::int;
    raise notice '  "%" -> % documento(s) movido(s)', v_alvo.razao_social, v_r->>'documentos';
  end loop;

  -- O CNPJ QUE PROVOU A FUSÃO FICA GRAVADO, e não é enfeite: é a evidência de
  -- POR QUE estas quatro linhas viraram uma. Sem ele, daqui a seis meses a
  -- fusão parece um palpite de alguém.
  update entidade set cnpj = coalesce(cnpj, '36.193.378/0001-04') where id = v_para;

  -- O CHECKLIST E AS RECONCILIAÇÕES PRECISAM SER REFEITOS. Os documentos
  -- mudaram de dono; o Kit Básico e as checagens foram calculados quando eles
  -- estavam espalhados por quatro empresas. Sem isto, o portal continua
  -- mostrando o estado antigo — a fusão teria arrumado o dado e deixado a TELA
  -- mentindo, que é o defeito que este projeto persegue.
  perform fn_recomputar_completude(v_caso);
  perform fn_reconciliar_caso(v_caso);

  raise notice 'PRONTO: % documento(s) movido(s) no total. Checklist e reconciliações refeitos.',
    v_docs;
  raise notice 'CONFIRA rodando a PARTE 1 de novo — deve sobrar UMA linha, com o CNPJ preenchido.';
end $$;

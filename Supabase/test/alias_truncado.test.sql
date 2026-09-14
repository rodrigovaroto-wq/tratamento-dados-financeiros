-- =============================================================================
-- 0168 — o nome truncado que casa com os outros não vira empresa nova
--
-- OS NOMES SÃO OS REAIS (regra 4): as quatro linhas de "OMNIBEAUTY" que o dono
-- viu no export do caso "teste 143", com a grafia exata, incluindo o
-- "SURUBIJU, 1930" que é o ENDEREÇO grudado pelo template do contador.
--
-- A ORDEM DE CHEGADA É PARTE DO ARRANJO, não enfeite: é ela que reproduz as
-- quatro linhas. Com o nome truncado chegando PRIMEIRO, cada variante seguinte
-- acharia um candidato só e seria absorvida — não haveria defeito para medir.
-- O bloco 2 prova isso, para que ninguém "conserte" o teste trocando a ordem.
--
-- O QUE ESTE ARQUIVO MEDE:
--   1. os quatro nomes reais, na ordem que reproduz o export: TRÊS entidades,
--      não quatro, e a variante do endereço entra na de nome mais completo com
--      `entidade_alias_fundido` no log (sem a 0168 são QUATRO e não há evento);
--   2. a ordem favorável continua dando UMA entidade (o ramo do candidato único
--      da 0153 não regrediu);
--   3. O CONTRAPOSITIVO DA 0153: candidatos que NÃO casam entre si continuam
--      sem escolha — "Araucaria SPE" contra Bioenergia × Imobiliária segue
--      criando entidade própria com `entidade_ambigua`. Se este bloco passar a
--      fundir, a 0168 comeu a correção que ela prometeu preservar;
--   4. `fn_entidades_sao_um_grupo` NÃO é fecho transitivo — A~B e B~C sem A~C é
--      falso. É a diferença entre os dois casos acima, isolada.
-- =============================================================================

create or replace function teste_assert_alias(p_cond boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_cond then
    raise notice 'ok    %', p_nome;
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

do $$
declare
  v_caso   uuid;
  v_id     uuid;
  v_n      int;
  v_nomes  text;
begin
  raise notice '--- 1. os quatro nomes reais da OMNIBEAUTY, na ordem do lote ---';
  v_caso := (fn_upsert_caso('Alias truncado — OMNIBEAUTY'))::uuid;

  perform fn_upsert_entidade(v_caso, 'OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE MARCAS LTDA');
  perform fn_upsert_entidade(v_caso, 'OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE SURUBIJU');
  perform fn_upsert_entidade(v_caso, 'OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE');
  -- A QUARTA é a do endereço grudado, e é ela que a 0168 impede de nascer: ela
  -- casa com "…DE SURUBIJU" e com o truncado, e esses dois casam entre si.
  v_id := fn_upsert_entidade(v_caso, 'OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE SURUBIJU, 1930');

  select count(*), string_agg(razao_social, ' | ' order by razao_social)
    into v_n, v_nomes from entidade where caso_id = v_caso;

  -- ESTE É O ASSERT QUE REPROVA COM A CORREÇÃO DESLIGADA: sem o ramo (3b) saem
  -- QUATRO entidades — exatamente as quatro linhas do export do dono.
  perform teste_assert_alias(v_n = 3,
    'os quatro nomes viram TRÊS entidades, não quatro (a variante do endereço não vira linha)',
    format('%s entidades: %s', v_n, v_nomes));

  perform teste_assert_alias(
    (select razao_social from entidade where id = v_id)
      = 'OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE SURUBIJU',
    'e ela entra no candidato de nome MAIS COMPLETO — o nome que chega, contaminado pelo '
      || 'endereço, é descartado',
    coalesce((select razao_social from entidade where id = v_id), '(nulo)'));

  perform teste_assert_alias(exists (
      select 1 from evento_auditoria ev
      where ev.acao = 'entidade_alias_fundido' and ev.entidade_ref = 'entidade:' || v_id),
    'a fusão deixa rastro (`entidade_alias_fundido`) — decidir calado seria pior que fragmentar');

  -- O QUE A 0168 NÃO PROMETE, medido para não virar surpresa: "…DE MARCAS" e
  -- "…DE SURUBIJU" NÃO casam entre si ("marcas" não é prefixo de "surubiju"), e
  -- pelo nome sozinho são tão indistinguíveis de duas empresas irmãs quanto
  -- Bioenergia e Imobiliária. Quem prova que são a mesma é o CNPJ, que esta
  -- função não recebe. Fechar de 3 para 1 é trabalho da EXTRAÇÃO.
  perform teste_assert_alias(not fn_mesma_entidade(
      'OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE MARCAS LTDA',
      'OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE SURUBIJU'),
    'LIMITE DECLARADO: "…DE MARCAS" × "…DE SURUBIJU" não casam — as duas que sobram são a '
      || 'ambiguidade de verdade, e só o CNPJ a resolve');

  raise notice '--- 2. com o truncado PRIMEIRO, o ramo do candidato único da 0153 resolve ---';
  v_caso := (fn_upsert_caso('Alias truncado — ordem favorável'))::uuid;
  perform fn_upsert_entidade(v_caso, 'OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE');
  perform fn_upsert_entidade(v_caso, 'OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE MARCAS LTDA');
  perform fn_upsert_entidade(v_caso, 'OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE SURUBIJU');
  perform fn_upsert_entidade(v_caso, 'OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE SURUBIJU, 1930');
  select count(*) into v_n from entidade where caso_id = v_caso;
  perform teste_assert_alias(v_n = 1,
    'chegando o truncado primeiro, as quatro variantes são UMA entidade (e era assim antes '
      || 'da 0168 também — o defeito mora na outra ordem)',
    format('%s entidades', v_n));

  raise notice '--- 3. CONTRAPOSITIVO DA 0153: quem não casa entre si continua sem escolha ---';
  v_caso := (fn_upsert_caso('Alias truncado — Araucária'))::uuid;
  perform fn_upsert_entidade(v_caso, 'ARAUCÁRIA BIOENERGIA SPE LTDA.');
  perform fn_upsert_entidade(v_caso, 'ARAUCÁRIA IMOBILIÁRIA SPE LTDA.');
  v_id := fn_upsert_entidade(v_caso, 'Araucaria SPE');

  perform teste_assert_alias(
    (select razao_social from entidade where id = v_id) = 'Araucaria SPE',
    'o nome que casa com DUAS empresas diferentes segue em entidade própria — a 0168 não comeu '
      || 'a 0153',
    coalesce((select razao_social from entidade where id = v_id), '(nulo)'));

  perform teste_assert_alias(exists (
      select 1 from evento_auditoria ev
      where ev.acao = 'entidade_ambigua' and ev.entidade_ref = 'entidade:' || v_id),
    'e a ambiguidade continua registrada (é dela que nasce a pendência)');

  perform teste_assert_alias(not exists (
      select 1 from evento_auditoria ev
      where ev.acao = 'entidade_alias_fundido' and ev.entidade_ref = 'entidade:' || v_id),
    'sem nenhum `entidade_alias_fundido` no meio — fundir aqui seria escolher no empate');

  raise notice '--- 4. o grupo NÃO é fecho transitivo, e a diferença é de propósito ---';
  -- A~B e B~C sem A~C significa que B é um nome curto o bastante para casar com
  -- duas empresas distintas. Fecho transitivo fundiria as duas; todos-com-todos
  -- não funde, e é por isso que o bloco 3 acima continua passando.
  perform teste_assert_alias(
    fn_mesma_entidade('OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE',
                      'OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE MARCAS LTDA')
    and fn_mesma_entidade('OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE',
                          'OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE SURUBIJU')
    and not fn_entidades_sao_um_grupo(array[
      'OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE',
      'OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE MARCAS LTDA',
      'OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE SURUBIJU']),
    'A~B e B~C sem A~C NÃO é um grupo (fecho transitivo fundiria; todos-com-todos não)');

  perform teste_assert_alias(
    fn_entidades_sao_um_grupo(array[
      'OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE',
      'OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE SURUBIJU',
      'OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE SURUBIJU, 1930']),
    'e os três que casam DOIS A DOIS são um grupo');

  perform teste_assert_alias(
    not fn_entidades_sao_um_grupo(array[]::text[])
    and not fn_entidades_sao_um_grupo(null),
    'lista vazia ou nula não é grupo nenhum — sem grupo não há quem escolher');

  raise notice 'ALIAS TRUNCADO OK — 4 nomes viram 3 entidades, o endereço não vira empresa, e o '
               'empate de verdade continua sem escolha';
end $$;

-- =============================================================================
-- 0132 — A SONDA DE INSTALAÇÃO PARA DE CRESCER COM O DADO QUE ELA MEDE
--
-- A `0131` (de ontem) põe `fn_instalacao_resumo` no topo do painel, que é a tela
-- mais carregada da casa. Dois defeitos de custo entraram com ela, e os dois são
-- meus:
--
-- 1. `select count(*) from <tabela>` PARA CADA REQUISITO DE SEED. Hoje é barato
--    porque as tabelas semeadas são pequenas — mas um dos requisitos é
--    `lote_execucao`, que ganha uma linha por execução de ingestão E NUNCA PARA
--    DE CRESCER. A pergunta que a sonda faz é "tem ao menos N linhas?", e
--    `count(*)` responde muito mais do que isso: varre a tabela inteira para
--    devolver um número que ninguém usa além da comparação.
--
--    MEDIDO neste banco, com 50.000 lotes inseridos (~um ano de operação):
--      • `count(*)` sozinho ................. 5,9 ms   (e cresce linearmente)
--      • a sonda inteira .................... 7,9 ms
--      • a forma limitada ................... 0,218 ms (e é CONSTANTE)
--    27× mais barato hoje, e a diferença aumenta para sempre. Multiplique por
--    ~3 para a instância do dono, e por toda carga do painel.
--
-- 2. `information_schema.columns` PARA REQUISITO DE COLUNA. É uma view sobre
--    `pg_attribute` com junções e checagem de privilégio por linha.
--    MEDIDO: 3,4 ms por consulta contra 0,25 ms com `pg_attribute` direto —
--    14× mais caro para responder a mesma pergunta.
--
-- O QUE NÃO MUDA, e é o ponto: nenhuma resposta da sonda muda. Os 46 casos, os
-- 13 requisitos e as recusas continuam idênticos — o teste da `0131` roda sem
-- uma linha alterada nos asserts de resultado. Isto é custo, não comportamento.
--
-- POR QUE A FORMA LIMITADA RESPONDE A MESMA COISA. O requisito pergunta
-- `>= criterio_seed`. `select count(*) from (select 1 from t limit criterio) x`
-- devolve `min(real, criterio)`, então:
--   • resultado = criterio  →  há AO MENOS criterio linhas  →  presente
--   • resultado < criterio  →  esse é o total EXATO da tabela →  ausente
-- O caso ausente continua sabendo o número exato (varreu menos que o critério,
-- logo varreu tudo), que é justamente o caso em que o número importa para quem
-- lê a tela — "3 linha(s)" quando o critério é 8 diz que o seed rodou pela
-- metade. No caso presente o número exato não informa nada que a tela use, e
-- pagar uma varredura completa para exibi-lo é o defeito.
--
-- POR QUE ISTO É MIGRATION E NÃO AJUSTE DE TELA. A sonda é função de banco, e a
-- tela só a chama. Reescrever o corpo é a única forma de o painel deixar de
-- pagar a varredura — e `create or replace` mantém a assinatura, então nada que
-- chama precisa mudar.
--
-- O CORPO ABAIXO É O DA 0131, copiado inteiro, com as DUAS mudanças cirúrgicas
-- marcadas por comentário `-- 0132:`. É a regra da casa: função reescrita por
-- inteiro, diferença localizável.
-- =============================================================================

create or replace function fn_instalacao_conferir()
returns table (
  chave       text,
  migration   text,
  tipo        text,
  objeto      text,
  presente    boolean,
  detalhe     text,
  porque      text,
  severidade  text
)
language plpgsql
stable
as $$
declare
  r         instalacao_requisito;
  v_ok      boolean;
  v_det     text;
  v_n       bigint;
  v_alvo    regclass;
  v_crit    int;
begin
  for r in select * from instalacao_requisito order by ordem, chave loop
    v_ok  := false;
    v_det := null;

    if r.tipo = 'tabela' then
      v_ok := to_regclass('public.' || r.objeto) is not null;

    elsif r.tipo = 'funcao' then
      -- `to_regproc` falha quando a função tem sobrecargas ambíguas; o nome sem
      -- argumentos resolve pelo único candidato, e sobrecarga é sinal de que o
      -- requisito devia declarar a assinatura. Nenhum dos requisitos abaixo tem.
      begin
        v_ok := to_regproc('public.' || r.objeto) is not null;
      exception when others then
        -- Ambiguidade significa que EXISTE mais de uma — logo, existe.
        v_ok := true;
        v_det := 'mais de uma assinatura com este nome';
      end;

    elsif r.tipo = 'coluna' then
      -- 0132: `pg_attribute` em vez de `information_schema.columns` — mesma
      -- resposta, 14× mais barato (3,4 ms → 0,25 ms medidos). A view do
      -- information_schema junta várias tabelas de catálogo e filtra por
      -- privilégio linha a linha; aqui a pergunta é "existe esta coluna", e
      -- `attrelid` já vem resolvido por `to_regclass`.
      --
      -- `to_regclass` devolvendo NULL não é erro: significa que a TABELA não
      -- existe, e aí a coluna também não — `attrelid = null` não casa com nada e
      -- o `exists` dá false, que é a resposta certa. É a mesma proteção do ramo
      -- de seed abaixo, obtida de graça pela forma da consulta.
      v_ok := exists (
        select 1 from pg_attribute a
         where a.attrelid  = to_regclass('public.' || split_part(r.objeto, '.', 1))
           and a.attname   = split_part(r.objeto, '.', 2)
           and a.attnum    > 0
           and not a.attisdropped);

    elsif r.tipo in ('seed', 'comportamento') then
      -- A tabela pode não existir ainda: contar nela levantaria erro e derrubaria
      -- a sonda inteira, transformando "um requisito faltando" em "o painel não
      -- abre". A sonda de instalação é o último lugar do sistema que pode falhar
      -- por causa do que ela existe para medir.
      v_alvo := to_regclass('public.' || r.objeto);
      if v_alvo is null then
        v_ok  := false;
        v_det := 'a tabela nem existe';
      else
        -- 0132: CONTAGEM LIMITADA AO CRITÉRIO. Ver o cabeçalho: a pergunta é
        -- ">= criterio", e varrer a tabela inteira para respondê-la faz o custo
        -- do painel crescer junto com `lote_execucao`, que cresce para sempre.
        v_crit := greatest(coalesce(r.criterio_seed, 1), 1);
        execute format('select count(*) from (select 1 from public.%I limit %s) x',
                       r.objeto, v_crit)
           into v_n;
        v_ok := v_n >= v_crit;
        -- No caso PRESENTE o total exato não é conhecido (nem usado pela tela).
        -- No caso AUSENTE ele é exato por construção — a varredura parou antes do
        -- limite, logo passou por tudo — e é nele que o número informa algo:
        -- "3 linha(s)" com critério 8 diz que o seed rodou pela metade.
        v_det := case when v_ok then format('%s linha(s) ou mais', v_crit)
                      else format('%s linha(s)', v_n) end;
      end if;
    end if;

    return query select r.chave, r.migration, r.tipo, r.objeto, v_ok, v_det,
                        r.porque, r.severidade;
  end loop;
end;
$$;

comment on function fn_instalacao_conferir() is
  'Confere cada requisito de instalacao_requisito contra o catálogo do banco. Sobrevive ao objeto '
  'ausente (to_regclass/to_regproc devolvem NULL em vez de erro): a sonda não pode falhar por causa '
  'do que ela existe para medir. 0132: o custo NÃO cresce com o dado — a contagem de seed é limitada '
  'ao critério (lote_execucao cresce por execução, e o painel a sonda a cada carga) e a checagem de '
  'coluna usa pg_attribute em vez de information_schema. Garante o contrapositivo, não o positivo: '
  'objeto ausente é migration ausente; objeto presente não prova que o corpo está na versão certa.';

grant execute on function fn_instalacao_conferir() to authenticated;

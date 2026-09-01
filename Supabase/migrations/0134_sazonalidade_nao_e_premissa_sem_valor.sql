-- =============================================================================
-- 0134 — SAZONALIDADE NÃO É "PREMISSA SEM VALOR", e o "pronto" da Modelagem
--        deixa de travar para sempre
--
-- O DEFEITO, anotado desde a sessão 39 como suspeita e MEDIDO agora.
--
-- `fn_conferir_modelagem` (0101) monta a lista `premissas_sem_valor` assim:
--
--     array_agg(premissa_codigo) filter (where ativo and
--       (valores is null or valores = '{}'::jsonb))
--
-- e `pronto` exige que essa lista esteja VAZIA. O critério está certo para quase
-- toda premissa: `SGA_PCT` sem percentual digitado é, de fato, premissa pela
-- metade — alguém a ativou e não disse quanto.
--
-- Só que TRÊS premissas do catálogo têm `formula = 'curva_mensal'` —
-- `SAZONALIDADE`, `CRONOGRAMA_FISICO` e `PARADA_MANUTENCAO` — e nelas
-- `valores` VAZIO É O ESTADO CERTO. A curva delas não é digitada: sai de
-- `fn_sazonalidade_do_caso` (0040), que a DERIVA do documento mensal do próprio
-- caso, mês a mês, a partir dos rótulos "jan/2024". O comentário do
-- `export-modelagem.ts` já diz isso em voz alta: *"A sazonalidade não projeta
-- valor: ela DISTRIBUI nos meses o valor anual que outra premissa projetou."*
--
-- O EFEITO, medido no banco de teste antes desta migration:
--
--     antes de vincular:  pronto=false, sem_valor=[SGA_PCT]
--     depois de vincular: pronto=false, sem_valor=[SAZONALIDADE, SGA_PCT]
--
-- Ou seja: o analista faz a coisa CERTA — vincula a sazonalidade à linha de
-- receita, que é exatamente o que a aba Modelagem existe para permitir — e a
-- tela passa a dizer que o modelo não está pronto, com uma pendência que ele
-- NÃO TEM COMO RESOLVER. Não há campo para preencher; a curva vem do documento.
-- É atrito puro no processo: o portão cobra uma ação que não existe, e a saída
-- que sobra para quem está com pressa é DESVINCULAR a sazonalidade — perdendo a
-- distribuição mensal para calar o aviso.
--
-- A CORREÇÃO, e o que ela deliberadamente NÃO faz.
--
-- `curva_mensal` sai de `premissas_sem_valor`. E o critério é a FÓRMULA do
-- catálogo, não uma lista de códigos: quem acrescentar a quarta curva mensal
-- amanhã não vai ter de lembrar de editar esta função — é a mesma lição do
-- limiar 0.95 no corpo da `fn_registrar_campos_extraidos` (corrigido pela 0041)
-- e da lista fechada de rótulos que a 0133 substituiu por estrutura.
--
-- O QUE NÃO SE FAZ É CALAR O CASO REAL. Existe um estado ruim de verdade aqui:
-- sazonalidade ATIVA num caso que não tem documento mensal. Aí
-- `fn_sazonalidade_do_caso` devolve vazio, e as linhas vinculadas ficam sem
-- distribuição nenhuma — o valor anual é rateado liso pelos doze meses. Isso é
-- degradação silenciosa, e silenciar seria trocar um atrito por uma mentira.
--
-- Então ele ganha nome PRÓPRIO: `sazonalidade_sem_curva`. E ele NÃO bloqueia o
-- `pronto`, por uma razão que vale escrever: os números ANUAIS continuam certos
-- — só o rateio mensal fica liso. Bloquear o portão por causa de uma degradação
-- que não altera o resultado anual devolveria o atrito pela porta dos fundos, e
-- o analista aprenderia a ignorar o portão. O portão trava o que está ERRADO; o
-- que está PIOR do que poderia estar é informação, e informação se publica.
-- =============================================================================

create or replace function fn_conferir_modelagem(p_caso_id uuid)
returns jsonb
language sql
stable
as $$
  with linhas as (
    select * from fn_linhas_para_modelagem(p_caso_id)
  ),
  contas as (
    select rotulo_norm from linhas where papel = 'conta'
  ),
  vinculadas as (
    select distinct l.rotulo_norm
    from caso_linha_premissa l
    where l.caso_id = p_caso_id and l.premissa_codigo is not null
      and l.rotulo_norm in (select rotulo_norm from contas)
  ),
  orfaos as (
    select distinct l.rotulo_norm
    from caso_linha_premissa l
    where l.caso_id = p_caso_id and l.premissa_codigo is not null
      and l.rotulo_norm not in (select rotulo_norm from linhas)
  ),
  nao_projetaveis as (
    select jsonb_object_agg(papel, n) as j
    from (select papel, count(*) as n from linhas where papel <> 'conta' group by papel) x
  ),
  -- 0134: a premissa ativa, com a FÓRMULA dela ao lado. É a fórmula que decide
  -- se `valores` vazio é defeito ou é o estado normal — não o código, que
  -- envelheceria a cada premissa nova.
  ativas as (
    select cp.premissa_codigo, cp.valores, pc.formula
    from caso_premissa cp
    join premissa_catalogo pc on pc.codigo = cp.premissa_codigo
    where cp.caso_id = p_caso_id and cp.ativo
  ),
  premissas as (
    select count(*) as ativas,
           array_agg(premissa_codigo order by premissa_codigo)
             filter (where formula <> 'curva_mensal'
                       and (valores is null or valores = '{}'::jsonb)) as sem_valor,
           -- O caso ruim DE VERDADE: curva mensal ativa e o caso sem documento
           -- mensal de onde derivá-la. As linhas vinculadas ficam com rateio
           -- liso, e isso precisa ser DITO — não bloqueia, porque o anual
           -- continua certo.
           array_agg(premissa_codigo order by premissa_codigo)
             filter (where formula = 'curva_mensal'
                       and not exists (select 1 from fn_sazonalidade_do_caso(p_caso_id)))
             as saz_sem_curva
    from ativas
  ),
  param as (
    select to_jsonb(m) as j from caso_modelagem m where m.caso_id = p_caso_id
  )
  select jsonb_build_object(
    'parametros', (select j from param),
    'premissas_ativas', (select ativas from premissas),
    'premissas_sem_valor', to_jsonb(coalesce((select sem_valor from premissas), array[]::text[])),
    -- 0134: informação, não bloqueio. Ver o cabeçalho.
    'sazonalidade_sem_curva',
      to_jsonb(coalesce((select saz_sem_curva from premissas), array[]::text[])),
    'linhas_do_caso', (select count(*) from contas),
    'linhas_nao_projetaveis', coalesce((select j from nao_projetaveis), '{}'::jsonb),
    'linhas_com_premissa', (select count(*) from vinculadas),
    'linhas_sem_premissa', greatest((select count(*) from contas) - (select count(*) from vinculadas), 0),
    'vinculos_orfaos', to_jsonb(coalesce(
      (select array_agg(rotulo_norm order by rotulo_norm) from orfaos), array[]::text[])),
    'pronto', (select j from param) is not null
              and (select ativas from premissas) > 0
              and coalesce(array_length((select sem_valor from premissas), 1), 0) = 0
  );
$$;

comment on function fn_conferir_modelagem(uuid) is
  'Diagnóstico da Modelagem de um caso. Desde a 0134, premissa de `curva_mensal` (SAZONALIDADE, '
  'CRONOGRAMA_FISICO, PARADA_MANUTENCAO) NÃO conta como "sem valor": a curva dela é derivada do '
  'documento mensal por fn_sazonalidade_do_caso, não digitada, e cobrá-la travava o "pronto" com '
  'uma pendência sem ação possível. O caso ruim de verdade — curva ativa e caso sem documento '
  'mensal — ganhou nome próprio em `sazonalidade_sem_curva`, que informa e não bloqueia, porque os '
  'números ANUAIS continuam certos e só o rateio mensal fica liso.';

grant execute on function fn_conferir_modelagem(uuid) to authenticated;

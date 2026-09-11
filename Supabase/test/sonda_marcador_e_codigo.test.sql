-- =============================================================================
-- O MARCADOR DA SONDA TEM DE SER CÓDIGO, NÃO COMENTÁRIO.
--
-- O DEFEITO QUE ISTO FECHA, medido em 11/09/2026 pela auditoria de erro
-- acumulado que o dono pediu: dos 31 requisitos `tipo='corpo'` de
-- `instalacao_requisito`, **18 usavam como marcador um COMENTÁRIO SQL
-- (`-- 0142`) ou o número da migration (`0155`)**.
--
-- Por que isso é grave, e não estético: o ramo `corpo` da sonda faz
-- `position(marcador in pg_get_functiondef(objeto))`. Se o marcador é o
-- comentário de cabeçalho, então uma reemissão que COPIE o cabeçalho e PERCA a
-- lógica passa na sonda — ela responde "presente" sobre uma função que não faz
-- mais o que a migration mandava. É a `estagio-desligado-parece-limpo.md`
-- cometida pelo instrumento construído para evitá-la, e foi assim que este
-- projeto já perdeu uma rodada.
--
-- O QUE ESTE TESTE NÃO FAZ: consertar os 18. Trocar o marcador de um requisito
-- exige saber qual token de código é único àquela mudança, e um token errado faz
-- a sonda acusar ausência FALSA — que é pior que o defeito atual, porque manda a
-- próxima sessão investigar uma migration que está lá. Eles ficam NOMEADOS na
-- lista histórica abaixo: o registro de quem entrou antes do portão.
--
-- O QUE ELE FAZ: impede a lista de CRESCER. Requisito `corpo` novo tem de
-- apontar para código — nome de função chamada, variável, fragmento de
-- `format()`, coluna — como a 0157/0158/0164 já fazem.
-- =============================================================================
do $$
declare
  v_historicos text[] := array[
    'combinado_pela_estrutura','conceito_na_coluna','conflito_na_rodada',
    'conflito_sem_cartesiano','diagnostico_nao_confirma_pelo_balcao',
    'entidade_ambigua_nao_decide','entidade_hierarquia_nao_e_erro',
    'entidade_que_o_documento_nao_declarou','fato_grava_sem_derrubar',
    'fato_leitura_estavel','hierarquia_achatada_nao_acusa',
    'limiar_de_auto_aceite_exclui','realizado_desempata_por_autoridade',
    'realizado_sem_dupla_contagem','reconciliacao_escopo_declarado',
    'sazonalidade_no_pronto','sonda_nao_cresce_com_o_dado',
    'tipo_incorreto_com_divergencia'
  ];
  v_ruins text;
  v_n int;
begin
  select count(*), string_agg(chave || ' (marcador: ' || marcador || ')', E'\n      ')
    into v_n, v_ruins
  from instalacao_requisito
  where tipo = 'corpo'
    and not (chave = any(v_historicos))
    -- COMENTÁRIO: começa com `--`, em qualquer posição do marcador.
    and (marcador like '--%'
         -- SÓ O NÚMERO DA MIGRATION: quatro dígitos, com ou sem sufixo curto
         -- de desambiguação (`0149 (4)`), mas sem nenhum token de código.
         or marcador ~ '^[0-9]{4}([^A-Za-z_]|$)');

  if v_n > 0 then
    raise exception E'% requisito(s) de corpo com marcador que NÃO é código:\n      %\n'
      '      O marcador vira `position(... in pg_get_functiondef(...))`. Comentário ou\n'
      '      número de migration passa numa reemissão que copiou o cabeçalho e perdeu a\n'
      '      lógica — a sonda responde "presente" sobre função que não faz mais o que a\n'
      '      migration mandava. Aponte para CÓDIGO: nome de função chamada, variável,\n'
      '      fragmento de format(), coluna. Ver Supabase/test/sonda_marcador_e_codigo.test.sql',
      v_n, v_ruins;
  end if;

  raise notice 'ok    todo requisito de corpo NOVO aponta para código (% histórico(s) nomeado(s))',
    array_length(v_historicos, 1);
  raise notice 'SONDA MARCADOR OK — a lista histórica não cresceu';
end $$;

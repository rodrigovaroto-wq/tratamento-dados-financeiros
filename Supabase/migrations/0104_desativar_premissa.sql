-- =============================================================================
-- Migration 0104 — desativar premissa, e os vínculos que ela deixaria para trás
--
-- O QUE FALTAVA. `fn_ativar_premissa` (0038) liga e ajusta; não havia como
-- DESLIGAR. Na tela, uma premissa ativada por engano ficava ativada para sempre:
-- os botões eram "Ativar" e "Atualizar", e nenhum deles desfazia a escolha.
--
-- E DESATIVAR NÃO É SÓ `ativo = false`. `caso_linha_premissa` guarda o vínculo
-- linha↔premissa, e ele NÃO olha `caso_premissa.ativo`. Baixar só a bandeira
-- deixaria o caso num estado em que as três peças discordam entre si, cada uma
-- em silêncio:
--
--   • a TELA monta o seletor de cada linha a partir das premissas ATIVAS. Vínculo
--     para premissa desativada não casa com opção nenhuma, então o seletor
--     aparece VAZIO — a tela diz "sem premissa" enquanto o banco diz o contrário;
--   • `fn_conferir_modelagem` conta `linhas_com_premissa` direto de
--     `caso_linha_premissa`, sem olhar `ativo` — a caixa de conferência
--     continuaria contando aquelas linhas como configuradas;
--   • o EXPORT procura a premissa do vínculo entre as ativas
--     (`config.premissas.find(...)`), não acha, e a linha sai no arquivo sem
--     projeção — sem que nada, em nenhuma das telas, tenha avisado.
--
-- Três leituras diferentes do mesmo caso é exatamente a classe de defeito que
-- este repositório mais pagou caro. Então o vínculo é LIMPO junto, na mesma
-- transação, e o número de vínculos desfeitos VOLTA para quem clicou — desfazer
-- 44 linhas de uma seção sem dizer quantas seria pior que não desfazer.
--
-- A MESMA PREMISSA PODE ESTAR EM DOIS PAPÉIS. `caso_linha_premissa` tem
-- `premissa_codigo` E `sazonalidade_codigo`, e as premissas de natureza
-- `sazonalidade` entram na segunda coluna. Desativar limpa as DUAS, e conta
-- separado: são decisões distintas do analista, e juntá-las num número só
-- esconderia que a curva mensal de 30 linhas também caiu.
--
-- A LINHA SÓ É APAGADA quando fica sem as duas. Enquanto restar sazonalidade, a
-- linha continua existindo com `premissa_codigo` nulo — que é o mesmo estado de
-- "escolhi não projetar esta linha", já suportado desde a 0038.
--
-- RECUSA RETORNADA, não levantada (padrão 0036/0037/0038/0041): desativar o que
-- já está desativado é erro de chamador, e a tentativa interessa à trilha tanto
-- quanto o acerto.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- fn_desativar_premissa — desliga a premissa no caso e desfaz o que ela dirigia.
-- -----------------------------------------------------------------------------
create or replace function fn_desativar_premissa(
  p_caso_id uuid,
  p_codigo  text,
  p_autor   text
)
returns jsonb
language plpgsql
as $$
declare
  v_nome     text;
  v_ativa    boolean;
  v_vinculos int := 0;
  v_sazo     int := 0;
  v_orfas    int := 0;
begin
  select nome into v_nome from premissa_catalogo where codigo = p_codigo;
  if v_nome is null then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values (p_autor, 'premissa_recusada', 'caso:'||p_caso_id,
              jsonb_build_object('codigo', p_codigo, 'porque', 'codigo inexistente no catalogo',
                                 'acao_pedida', 'desativar'));
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('A premissa "%s" não existe no catálogo.', p_codigo));
  end if;

  select ativo into v_ativa
  from caso_premissa where caso_id = p_caso_id and premissa_codigo = p_codigo;

  -- Nunca ativada, ou já desativada. Não é exceção — é um clique que não tem o
  -- que desfazer, e a resposta precisa dizer isso em vez de fingir sucesso.
  if v_ativa is null or v_ativa = false then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('A premissa "%s" não está ativa neste caso — não há o que remover.',
                              v_nome));
  end if;

  -- 1. O vínculo que dirige a projeção da linha.
  update caso_linha_premissa
     set premissa_codigo = null, atualizado_por = p_autor, atualizado_em = now()
   where caso_id = p_caso_id and premissa_codigo = p_codigo;
  get diagnostics v_vinculos = row_count;

  -- 2. O mesmo código usado como CURVA MENSAL da linha (natureza sazonalidade).
  update caso_linha_premissa
     set sazonalidade_codigo = null, atualizado_por = p_autor, atualizado_em = now()
   where caso_id = p_caso_id and sazonalidade_codigo = p_codigo;
  get diagnostics v_sazo = row_count;

  -- 3. Linha que ficou sem as duas não é "linha sem premissa": é linha sobre a
  -- qual não há mais decisão registrada. Mantê-la faria a trilha afirmar uma
  -- escolha que o analista desfez.
  delete from caso_linha_premissa
   where caso_id = p_caso_id and premissa_codigo is null and sazonalidade_codigo is null;
  get diagnostics v_orfas = row_count;

  update caso_premissa
     set ativo = false, atualizado_por = p_autor, atualizado_em = now()
   where caso_id = p_caso_id and premissa_codigo = p_codigo;

  -- `valores` NÃO é apagado, de propósito: reativar a premissa devolve o que já
  -- tinha sido digitado. Remover por engano custa um clique para desfazer, não
  -- cinco anos de valores redigitados.
  insert into decisao (caso_id, tipo, autor, motivo, payload)
    values (p_caso_id, 'override', p_autor,
            format('Premissa "%s" REMOVIDA da modelagem (%s vínculo(s) e %s sazonalidade(s) desfeitos)',
                   v_nome, v_vinculos, v_sazo),
            jsonb_build_object('premissa', p_codigo, 'ativo', false,
                               'n_vinculos_desfeitos', v_vinculos,
                               'n_sazonalidades_desfeitas', v_sazo,
                               'n_linhas_removidas', v_orfas));

  return jsonb_build_object(
    'caso_id', p_caso_id, 'premissa', p_codigo, 'nome', v_nome, 'ativo', false,
    'n_vinculos_desfeitos', v_vinculos,
    'n_sazonalidades_desfeitas', v_sazo,
    'n_linhas_removidas', v_orfas);
end;
$$;

comment on function fn_desativar_premissa(uuid, text, text) is
  'Desativa a premissa no caso e LIMPA os vínculos que ela dirigia (premissa e sazonalidade), '
  'devolvendo quantos foram desfeitos. Vínculo órfão faria tela, conferência e export lerem o '
  'mesmo caso de três formas diferentes. `valores` é preservado para a reativação.';

grant execute on function fn_desativar_premissa(uuid, text, text) to authenticated;

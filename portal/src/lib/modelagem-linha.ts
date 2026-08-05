// A IDENTIDADE DE UMA LINHA DE MODELAGEM — e por que ela não é só o rótulo.
//
// O DEFEITO QUE ISTO CORRIGE (relatado pelo dono no teste da tela): ele escolhia
// a premissa de UMA linha, não mexia em nenhuma outra, salvava — e outra linha,
// que ele nunca tocou, aparecia preenchida com a mesma premissa.
//
// A causa não estava no salvamento, estava na LEITURA. No banco, a identidade da
// linha é o par (`secao_canonica`, `rotulo_norm`) — o índice único de
// `caso_linha_premissa` inclui a seção, e `fn_linhas_para_modelagem` agrupa por
// `group by o.secao_canonica, o.rotulo_norm`. O portal, nos dois lugares em que
// casava vínculo com linha, usava só o `rotulo_norm`:
//
//   const vinculoPorRotulo = new Map(vinculos.map((v) => [v.rotulo_norm, v]));
//
// e demonstração real repete rótulo entre seções o tempo todo. No caso do teste
// v35 são TREZE: `Empréstimos e Financiamentos` e `Arrendamentos` estão no
// passivo circulante E no não circulante; `Capital social`, `Reserva legal` e
// `Prejuízos acumulados` estão no patrimônio líquido E na DMPL; `Provisão para
// contingências` está no passivo não circulante E nas despesas operacionais.
//
// O efeito era em cadeia, e o primeiro passo é o que o dono viu:
//
//   1. a tela mostrava a premissa da linha do circulante na linha homônima do NÃO
//      circulante — "completou sozinho";
//   2. esse valor virava o `orig` daquela seção, então na próxima vez que ele
//      salvasse aquela seção por qualquer outro motivo, a linha ia ao banco DE
//      VERDADE com uma premissa que ninguém escolheu ali;
//   3. no export, `valorBase` e o rótulo exibido vinham do último homônimo do
//      mapa — podia ser o saldo da OUTRA seção, e a projeção partia dele.
//
// Nada disso dava erro. O arquivo saía com um número plausível e errado.
//
// A chave usa `\u0000` (byte zero) como separador porque é o único caractere que não pode
// aparecer num rótulo vindo do banco (texto Postgres não guarda byte zero) —
// separador visível como `|` ou `::` casaria dois pares diferentes se algum
// rótulo o contivesse.

/** Identidade de uma linha de modelagem: o par (seção canônica, rótulo normalizado). */
export function chaveDaLinha(
  secaoCanonica: string | null | undefined,
  rotuloNorm: string,
): string {
  return `${secaoCanonica ?? ""}\u0000${rotuloNorm}`;
}

/** O que `fn_linhas_para_modelagem` devolve, no que interessa ao casamento. */
export interface LinhaParaCasar {
  secao_canonica: string | null;
  rotulo_norm: string;
  chave: string;
  valor_ultimo: number | null;
}

/** O que `caso_linha_premissa` guarda. */
export interface VinculoParaCasar {
  secao_canonica: string | null;
  rotulo_norm: string;
  premissa_codigo: string | null;
  sazonalidade_codigo: string | null;
}

export interface LinhaDeConfig {
  rotulo: string;
  secaoCanonica: string | null;
  premissaCodigo: string | null;
  sazonalidadeCodigo: string | null;
  valorBase: number | null;
}

/**
 * Casa cada vínculo com a linha do caso, PELO PAR (seção, rótulo).
 *
 * Vínculo sem linha correspondente (o documento não chegou, ou foi reextraído com
 * outro rótulo) mantém o `rotulo_norm` como rótulo exibido e `valorBase` nulo —
 * é o mesmo comportamento de antes, e `fn_conferir_modelagem` já o denuncia como
 * `vinculos_orfaos`. Descartá-lo aqui esconderia a configuração órfã do arquivo.
 */
export function casarVinculosComLinhas(
  vinculos: VinculoParaCasar[],
  linhas: LinhaParaCasar[],
): LinhaDeConfig[] {
  const porChave = new Map(linhas.map((l) => [chaveDaLinha(l.secao_canonica, l.rotulo_norm), l]));
  return vinculos.map((v) => {
    const l = porChave.get(chaveDaLinha(v.secao_canonica, v.rotulo_norm));
    return {
      rotulo: l?.chave ?? v.rotulo_norm,
      secaoCanonica: v.secao_canonica,
      premissaCodigo: v.premissa_codigo,
      sazonalidadeCodigo: v.sazonalidade_codigo,
      valorBase: l?.valor_ultimo ?? null,
    };
  });
}

/**
 * O vínculo de cada linha, para a TELA — indexado pela mesma identidade.
 *
 * A tela pergunta por (seção, rótulo) e recebe o que está gravado para aquela
 * linha, e só para ela.
 */
export function vinculoPorLinha(
  vinculos: VinculoParaCasar[],
): Map<string, VinculoParaCasar> {
  return new Map(vinculos.map((v) => [chaveDaLinha(v.secao_canonica, v.rotulo_norm), v]));
}

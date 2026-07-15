// Completude vs Kit Básico (Portão 1) — f0/04.
//
// v1 "bom o suficiente para começar": um item do Kit Básico é considerado
// PRESENTE se existe ao menos um documento classificado com aquele código no
// caso. Completude por entidade×período (matriz esperada) é refinamento de
// fatia posterior — exige o dono definir a matriz esperada por mandato.
//
// Regra determinística: item obrigatório ausente → pendência `item_faltante`
// BLOQUEANTE; se o código está na lista NÃO-sobrepujável, sobrepujavel=false.

import { KIT_BASICO, NAO_SOBREPUJAVEIS } from './taxonomia.mjs';

// presentes: array de códigos de taxonomia já classificados/confirmados no caso.
export function computeCompletude(presentes, opts = {}) {
  const kit = opts.kitBasico || KIT_BASICO;
  const naoSobrepujaveis = opts.naoSobrepujaveis || NAO_SOBREPUJAVEIS;

  const setPresentes = new Set(presentes);
  const faltantes = kit.filter((codigo) => !setPresentes.has(codigo));

  const pendencias = faltantes.map((codigo) => ({
    tipo: 'item_faltante',
    severidade: 'bloqueante',
    origem_estagio: 'completude',
    sobrepujavel: !naoSobrepujaveis.includes(codigo),
    descricao: `Item obrigatório do Kit Básico ausente: ${codigo}`,
    alvo_tipo_taxonomia: codigo,
  }));

  return {
    completo: faltantes.length === 0,
    faltantes,
    pendencias,
    // Portão 1 satisfeito quando não há obrigatório faltante.
    // (Portão 2 tem regra adicional de ressalvas/bloqueantes — f0/04.)
    portao1_ok: faltantes.length === 0,
  };
}

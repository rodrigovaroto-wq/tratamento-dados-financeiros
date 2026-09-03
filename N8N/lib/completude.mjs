// Completude vs Kit Básico (Portão 1) — Arquitetura do Sistema/2 Especificação/f0/04.
//
// v1 "bom o suficiente para começar": um item do Kit Básico é considerado
// PRESENTE se existe ao menos um documento classificado com aquele código no
// caso. Completude por entidade×período (matriz esperada) é refinamento de
// fatia posterior — exige o dono definir a matriz esperada por mandato.
//
// Regra determinística: item obrigatório ausente → pendência `item_faltante`
// BLOQUEANTE; se o código está na lista NÃO-sobrepujável, sobrepujavel=false.

import { KIT_BASICO, NAO_SOBREPUJAVEIS } from './taxonomia.mjs';

// TRÊS ESTADOS, não dois (Supabase/migrations/0036 — item 3 do §7.4 do Onboarding).
//
// A v1 tinha só "presente" e "faltante", e presente queria dizer "existe um
// documento com aquele código". Um .xlsx que o pipeline não converte, um arquivo
// ilegível ou uma chamada de extração que falhou produziam um item PRESENTE do
// qual não saiu uma única linha: dashboard verde e a parte do book vazia.
//
// O terceiro estado usa o vocabulário que `Arquitetura do Sistema/3 Estado e Execução/07` já define —
// `recebido_não_válido` — e NÃO redefine o Portão 1. O documento chegou (a
// completude conta a chegada); o que falta é validade. Quem trava o avanço é a
// pendência bloqueante, que é exactamente como `Arquitetura do Sistema/3 Estado e Execução/07` desenha o portão:
// "elegível ao Portão 2 se e somente se não há pendência bloqueante aberta".
//
// A pendência é NÃO-SOBREPUJÁVEL sempre, independente da lista de códigos: a
// lista fechada de `Arquitetura do Sistema/3 Estado e Execução/07` inclui "arquivo ilegível de item essencial", e não
// há o que ressalvar num obrigatório do qual não veio nenhum número.
//
// presentes:   códigos de taxonomia já classificados/confirmados no caso.
// semConteudo: subconjunto de `presentes` cujos documentos não renderam NENHUMA
//              linha extraída (em nenhuma versão).
// ATENÇÃO (Supabase/migrations/0157): esta função decide presença por
// `setPresentes.has(codigo)` — a regra do RÓTULO EXATO que a 0157 aboliu no
// banco (fn_documento_serve_como aceita, só para COMBINADO, um documento
// estruturalmente combinado e com conteúdo classificado de BALANCO/DRE/
// FLUXO_CAIXA). Ela NÃO foi reescrita para acompanhar isso de propósito: o
// único chamador desta função é o teste dela mesma — quem grava de verdade é
// o n8n chamando `fn_recomputar_completude` no banco, que já tem a regra
// nova. Reescrever aqui sem religar o caller criaria uma segunda fonte de
// verdade que nunca é exercitada em produção. Se um dia este arquivo passar
// a alimentar decisão real, é isto que precisa mudar primeiro.
export function computeCompletude(presentes, opts = {}) {
  const kit = opts.kitBasico || KIT_BASICO;
  const naoSobrepujaveis = opts.naoSobrepujaveis || NAO_SOBREPUJAVEIS;

  const setPresentes = new Set(presentes);
  const faltantes = kit.filter((codigo) => !setPresentes.has(codigo));

  // Só interessa o que é obrigatório E chegou: um complementar vazio não trava
  // portão, e um código em `semConteudo` que nem está presente é incoerência do
  // chamador — ignorada em silêncio de propósito, para a função não inventar
  // pendência sobre documento que não existe (aí o caso é `faltante`).
  const setSemConteudo = new Set(opts.semConteudo || []);
  const semConteudo = kit.filter((codigo) => setPresentes.has(codigo) && setSemConteudo.has(codigo));

  const pendencias = [
    ...faltantes.map((codigo) => ({
      tipo: 'item_faltante',
      severidade: 'bloqueante',
      origem_estagio: 'completude',
      sobrepujavel: !naoSobrepujaveis.includes(codigo),
      descricao: `Item obrigatório do Kit Básico ausente: ${codigo}`,
      alvo_tipo_taxonomia: codigo,
    })),
    ...semConteudo.map((codigo) => ({
      tipo: 'item_sem_conteudo',
      severidade: 'bloqueante',
      origem_estagio: 'completude',
      sobrepujavel: false,
      descricao:
        `Item obrigatório "${codigo}" foi RECEBIDO, mas nenhuma linha foi extraída de nenhuma `
        + 'versão dele: o documento existe e o book sai VAZIO nesta parte. Causas comuns: formato '
        + 'que o pipeline ainda não converte (.xlsx/.docx), arquivo ilegível, ou chamada de '
        + 'extração que falhou.',
      alvo_tipo_taxonomia: codigo,
    })),
  ];

  return {
    completo: faltantes.length === 0,
    faltantes,
    semConteudo,
    pendencias,
    // Portão 1 satisfeito quando não há obrigatório faltante — CHEGADA, e só.
    // (Portão 2 tem regra adicional de ressalvas/bloqueantes — Arquitetura do Sistema/2 Especificação/f0/04.)
    portao1_ok: faltantes.length === 0,
    // O que de fato autoriza seguir: chegou tudo E tem conteúdo aproveitável.
    pronto_para_revisao: faltantes.length === 0 && semConteudo.length === 0,
  };
}

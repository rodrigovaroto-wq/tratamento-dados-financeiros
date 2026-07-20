// Classificador determinístico por NOME DE ARQUIVO + regras (E1).
//
// Autonomia: classificação doc→checklist nasce em N1 (sugere, humano confirma).
// Este classificador é o passo barato/determinístico; quando não tem confiança,
// o workflow N8N faz fallback para a OpenAI ler o conteúdo (ver openai.mjs).
//
// Não decide nada sozinho: devolve uma SUGESTÃO com confiança e os sinais que
// a sustentam, para a fila de revisão.

import { normalize } from './normalize.mjs';
import { ALIASES } from './taxonomia.mjs';

const THRESHOLD_AUTO = 0.7; // abaixo disso → fallback OpenAI / pendência de classificação

// --- Período -----------------------------------------------------------------
// Reconhece as convenções de f0/03 (12M25, 1T25/1T26, L24M, listas multi-ano)
// e formatos adicionais pedidos pelo dono: ano isolado ("2025") e intervalo de
// anos ("2021-2025", "2021 a 2025") — expandido para a lista completa, não só
// os extremos.
export function parsePeriodo(textoNormalizado) {
  const t = textoNormalizado;

  // 12M25 / 12M2025  → anual (12 meses do ano)
  let m = t.match(/\b(\d{1,2})m(\d{2,4})\b/);
  if (m && Number(m[1]) === 12) {
    return { tipo: 'anual', referencia: `12M${m[2].slice(-2)}` };
  }
  // LxxM → últimos xx meses (ex.: L24M, L12M, L36M ou "faturamento 36 meses")
  m = t.match(/\bl(\d{1,2})m\b/) || t.match(/\b(\d{2})\s*meses\b/);
  if (m) {
    const n = m[1];
    return { tipo: 'multi', referencia: `L${n}M` };
  }
  // 1T25 / 2T2025 → trimestre
  m = t.match(/\b([1-4])t(\d{2,4})\b/);
  if (m) {
    return { tipo: 'trimestre', referencia: `${m[1]}T${m[2].slice(-2)}` };
  }
  // intervalo de anos: "2021-2025" | "2021 a 2025" | "21-25" → expande a lista
  // inteira (não só os extremos), no formato multi-ano existente ("21,22,...").
  m = t.match(/\b(20\d{2}|\d{2})\s*(?:-|–|a)\s*(20\d{2}|\d{2})\b/);
  if (m) {
    const full = (y) => (y.length === 2 ? `20${y}` : y);
    const start = Number(full(m[1]));
    const end = Number(full(m[2]));
    if (start <= end && end - start <= 50) {
      const anos = [];
      for (let y = start; y <= end; y++) anos.push(String(y).slice(-2));
      return { tipo: 'multi', referencia: anos.join(',') };
    }
  }
  // listas multi-ano: "23, 24 e 25" | "2023 2024 2025" | "23 24 26"
  const anos = t.match(/\b(20)?\d{2}\b/g);
  if (anos && anos.length >= 2) {
    const norm = anos.map((a) => a.slice(-2));
    return { tipo: 'multi', referencia: norm.join(',') };
  }
  // ano isolado: "2025" (só um número de 4 dígitos plausível como ano).
  // Sinal FRACO de propósito — um ano sozinho é muito mais ambíguo que os
  // formatos estruturados acima (poderia ser parte de qualquer texto), então
  // pesa menos na confiança (ver classifyByFilename) e não deve, sozinho,
  // empurrar a classificação por nome a pular a verificação da IA.
  if (anos && anos.length === 1 && /^(19|20)\d{2}$/.test(anos[0])) {
    return { tipo: 'anual', referencia: anos[0], fraco: true };
  }
  return null;
}

// --- Tipo (código da taxonomia) ----------------------------------------------
export function parseTipo(textoNormalizado) {
  for (const { codigo, termos } of ALIASES) {
    for (const termo of termos) {
      if (textoNormalizado.includes(termo)) {
        return { codigo, termo };
      }
    }
  }
  return null;
}

// --- Assinado (atributo de validação formal, f0/03) --------------------------
export function parseAssinado(textoNormalizado) {
  if (/\bassinad[oa]s?\b/.test(textoNormalizado)) return true;
  return null; // desconhecido (não é "não assinado")
}

// --- Classificação completa por nome -----------------------------------------
// Retorna sempre um objeto; confianca baixa sinaliza necessidade de fallback.
export function classifyByFilename(nomeOriginal) {
  const t = normalize(nomeOriginal);
  const tipo = parseTipo(t);
  const periodo = parsePeriodo(t);
  const assinado = parseAssinado(t);

  const sinais = { tipo: !!tipo, periodo: !!periodo, assinado: assinado === true };

  // Confiança: tipo é o sinal forte; período reforça (menos se for um sinal
  // fraco, tipo ano isolado — não deve, sozinho, somado ao tipo, ultrapassar
  // o limiar e pular a verificação da IA); assinado é bônus pequeno.
  let confianca = 0;
  if (tipo) confianca += 0.6;
  if (periodo) confianca += periodo.fraco ? 0.05 : 0.3;
  if (assinado === true) confianca += 0.1;
  confianca = Math.min(1, Number(confianca.toFixed(2)));

  const precisaFallback = confianca < THRESHOLD_AUTO || !tipo;

  return {
    tipo_taxonomia: tipo ? tipo.codigo : null,
    periodo: periodo, // {tipo, referencia} | null
    assinado, // true | null
    confianca,
    fonte: 'nome_arquivo',
    precisa_fallback_openai: precisaFallback,
    sinais,
    // entidade não sai do nome com confiança; fica para conteúdo/humano
    entidade: null,
  };
}

export { THRESHOLD_AUTO };

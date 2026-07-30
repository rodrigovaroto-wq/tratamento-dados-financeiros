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
  // Prefixo de ORDENAÇÃO do arquivo não é ano. Achado com dado real
  // ("13_Balancete_Analitico_Componentes_2025.pdf" saía como período
  // "multi 13,25" — o "13" do prefixo virou o ano 2013 e o 2025 virou 25):
  // um número no COMEÇO do nome, seguido de separador, é numeração de arquivo,
  // não competência. Remover antes de procurar ano evita períodos-lixo, que
  // além de exibirem errado fragmentam a tabela `periodo` e impedem a
  // reconciliação de casar os documentos do mesmo exercício.
  const t = String(textoNormalizado || '')
    .replace(/^\s*\d{1,3}\s*[-_. ]+/, '')
    // "2025x2024"/"2025 x 2024" é comparativo: o 'x' separa exercícios.
    .replace(/(\d)\s*[x\u00d7]\s*(\d)/g, '$1 $2');

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
  // Só é multi-ano de verdade quando os candidatos têm a MESMA largura: um nome
  // como "Balancete 13 2025" mistura numeração com ano, e tratar os dois como
  // exercício produzia "13,25" (bug real). Havendo exatamente UM ano de 4
  // dígitos, ele manda — é o sinal forte.
  const anos4 = t.match(/\b(19|20)\d{2}\b/g);
  if (anos4 && anos4.length === 1) {
    return { tipo: 'anual', referencia: anos4[0], fraco: true };
  }
  if (anos4 && anos4.length >= 2) {
    return { tipo: 'multi', referencia: anos4.map((a) => a.slice(-2)).sort().join(',') };
  }
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

// --- Entidade ----------------------------------------------------------------
// O "teste v31" mostrou o preço de devolver `entidade: null` aqui. A cadeia era:
// num documento que o nome classifica ACIMA do limiar (0,90 nos comparativos
// `..._2025x2024.pdf`) o fallback da IA nunca roda, então a ÚNICA fonte de
// entidade passava a ser o `diagnostico` da EXTRAÇÃO. Quando a extração falha —
// no v31, teto de gasto da OpenAI derrubou 8 de 14 — a entidade morre junto, e o
// dashboard mostrou "—" nos 14. Os nomes diziam a empresa em voz alta:
// `Vertentes_Metalurgica`, `VT_Logistica`, `Grupo_Vertentes`.
//
// O que isto NÃO faz, porque seria furar a anti-ancoragem (docs/01, f0/06):
//   • não soma confiança nenhuma — um documento não pode PULAR a verificação da
//     IA porque o nome sugeriu uma empresa. `confianca` continua saindo só de
//     tipo/período/assinado, e `THRESHOLD_AUTO` continua valendo igual;
//   • não vira fato: sai com `fonte: 'nome_arquivo'` e seque o caminho de sempre
//     — `fn_registrar_diagnostico` (0010) só preenche entidade quando está vazia
//     e abre pendência quando o conteúdo diverge do que foi registrado.
// É uma HIPÓTESE barata que sobrevive à falha da extração, e nada além disso.
//
// AUTO-CONTIDA de propósito (recebe `aliases` por parâmetro, declara os próprios
// helpers): o gerador embute o `toString()` desta função no Code node, que não
// importa arquivo. É o mesmo padrão de `diagnosticarErroApi` — e é o que impede
// este virar o quarto mirror manual do repositório, já que dois dos anteriores
// divergiram na prática.
export function parseEntidade(textoNormalizado, aliases) {
  // Palavras que descrevem o DOCUMENTO, não a empresa. Sem isto,
  // `12_Mutuos_Intragrupo_Grupo_Vertentes` viraria "Intragrupo Grupo Vertentes".
  const RUIDO = new Set([
    'combinado', 'combinada', 'combinadas', 'consolidado', 'consolidada', 'consolidadas',
    'analitico', 'analitica', 'sintetico', 'sintetica', 'intragrupo', 'intra',
    'assinado', 'assinada', 'assinados', 'assinadas', 'final', 'rev', 'revisado',
    'versao', 'copia', 'scan', 'digitalizado', 'grupo_', 'exercicio', 'exercicios',
  ]);
  // Siglas que ficam feias em Title Case ("Vt Logistica"). Lista curta e
  // explícita: adivinhar por "não tem vogal" erraria em `SPE`.
  const SIGLAS = new Set(['vt', 'spe', 'sa', 'me', 'epp', 'ltda', 'eireli', 'scp']);

  const ehPeriodo = (tok) =>
    /^(19|20)?\d{2}$/.test(tok) ||        // 2025, 25
    /^\d{1,3}$/.test(tok) ||              // número de sequência do arquivo (01)
    /^\d{2,4}x\d{2,4}$/.test(tok) ||      // 2025x2024 (comparativo)
    /^\d{1,2}m\d{2,4}$/.test(tok) ||      // 12m25
    /^l\d{1,2}m$/.test(tok) ||            // l24m
    /^\d{1,2}m$/.test(tok) ||             // 24m
    /^[1-4]t\d{2,4}$/.test(tok);          // 1t25

  // Remove TODOS os termos de tipo presentes, do mais longo para o mais curto.
  // Parar no primeiro match (como `parseTipo` faz, e deve fazer) deixaria lixo:
  // em `06_BP_COMBINADO_Grupo_Vertentes` o alias que casa é 'combinado', e o
  // 'bp' sobraria dentro do nome da entidade.
  let s = ` ${textoNormalizado} `;
  const termos = [];
  for (const a of aliases || []) for (const termo of a.termos) termos.push(termo);
  termos.sort((x, y) => y.length - x.length);
  for (const termo of termos) s = s.split(` ${termo} `).join(' ');

  const tokens = s
    .split(' ')
    .filter((tok) => tok && tok.length > 1 && !ehPeriodo(tok) && !RUIDO.has(tok));
  if (tokens.length === 0) return null;

  const nome = tokens
    .map((tok) => (SIGLAS.has(tok) ? tok.toUpperCase() : tok.charAt(0).toUpperCase() + tok.slice(1)))
    .join(' ');
  // Duas letras não identificam empresa nenhuma; devolver isso como hipótese só
  // geraria uma entidade-lixo na base para um humano ter que apagar depois.
  return nome.length >= 3 ? nome : null;
}

// --- Classificação completa por nome -----------------------------------------
// Retorna sempre um objeto; confianca baixa sinaliza necessidade de fallback.
export function classifyByFilename(nomeOriginal) {
  const t = normalize(nomeOriginal);
  const tipo = parseTipo(t);
  const periodo = parsePeriodo(t);
  const assinado = parseAssinado(t);
  const entidade = parseEntidade(t, ALIASES);

  const sinais = { tipo: !!tipo, periodo: !!periodo, assinado: assinado === true, entidade: !!entidade };

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
    // Hipótese barata, NUNCA fato — e deliberadamente fora do cálculo de
    // `confianca` acima (ver o comentário de `parseEntidade`).
    entidade,
  };
}

export { THRESHOLD_AUTO };

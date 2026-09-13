// Descobre os nomes REAIS dos campos de um formulário de intake (N8N Form
// Trigger) a partir do HTML renderizado — em vez de adivinhar/fixar nomes
// (ex.: "Mandato (nome do caso)"), que podem não bater com o atributo `name`
// real gerado pelo N8N para aquele campo. Um POST com o nome errado ainda
// pode receber 200 do N8N (o webhook aceita a requisição HTTP antes de saber
// se o workflow vai ter dado pra processar) — a execução falha DEPOIS, sem
// nenhum sinal pro portal (achado em produção, sessão 7 cont.¹²: upload
// "com sucesso" no portal, mas 0 tokens gastos — o workflow nunca recebeu
// arquivo nenhum sob o nome que o portal mandava).
//
// Parser tolerante por regex (não uma dependência de DOM parsing completa):
// o form do N8N é HTML simples, não uma SPA — os <input> já vêm no HTML
// inicial. Retorna null quando não encontra o suficiente, para o chamador
// cair no fallback configurado (nunca piora o comportamento anterior).

interface CamposDetectados {
  fileFieldName: string | null;
  textFieldName: string | null;
}

function parseAttrs(tag: string): Record<string, string> {
  const attrs: Record<string, string> = {};
  const re = /([\w-]+)\s*=\s*"([^"]*)"|([\w-]+)\s*=\s*'([^']*)'/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(tag))) {
    const key = (m[1] ?? m[3]).toLowerCase();
    const val = m[2] ?? m[4] ?? "";
    attrs[key] = val;
  }
  return attrs;
}

export function parseFormFieldNames(html: string): CamposDetectados {
  const inputs: Record<string, string>[] = [];
  const re = /<input\b([^>]*)>/gi;
  let m: RegExpExecArray | null;
  while ((m = re.exec(html))) {
    inputs.push(parseAttrs(m[1]));
  }

  const fileInput = inputs.find((a) => (a.type ?? "").toLowerCase() === "file" && a.name);
  const textInput = inputs.find((a) => {
    const type = (a.type ?? "text").toLowerCase();
    return type !== "file" && type !== "hidden" && type !== "submit" && type !== "button" && a.name;
  });

  return {
    fileFieldName: fileInput?.name ?? null,
    textFieldName: textInput?.name ?? null,
  };
}

// ---------------------------------------------------------------------------
// A DESCOBERTA, que agora tem DOIS chamadores
// ---------------------------------------------------------------------------
//
// Ela morava dentro de `app/api/intake/route.ts` enquanto só o encaminhamento
// pela Serverless Function existia. Com o envio direto do navegador
// (`app/api/intake/destino/route.ts`), o MESMO par de nomes precisa chegar a
// dois lugares — e duas cópias desta função seriam a forma mais fácil de o
// portal voltar a postar sob um nome que o workflow não lê, que é o defeito da
// sessão 7 cont.¹² (200 OK na tela, zero token gasto, nenhum arquivo recebido).
//
// A descoberta continua acontecendo NO SERVIDOR nos dois caminhos: quem manda
// os bytes pode ser o navegador, mas quem decide o nome do campo nunca é.

const CAMPO_MANDATO_ENV = () => process.env.N8N_INTAKE_FIELD_MANDATO || null;
const CAMPO_ARQUIVOS_ENV = () => process.env.N8N_INTAKE_FIELD_ARQUIVOS || null;

// Fallback de último recurso, só usado se não houver env E a descoberta falhar
// (instância fora do ar, HTML inesperado etc.) — mantém o comportamento
// anterior em vez de travar o upload por completo.
const CAMPO_MANDATO_FALLBACK = "Mandato (nome do caso)";
const CAMPO_ARQUIVOS_FALLBACK = "Arquivos";

export interface CamposDoForm {
  mandato: string;
  arquivos: string;
  /** `true` quando os nomes vieram do HTML do próprio Form, não do fallback. */
  descoberto: boolean;
}

export async function descobrirNomesDeCampo(url: string): Promise<CamposDoForm> {
  const mandatoEnv = CAMPO_MANDATO_ENV();
  const arquivosEnv = CAMPO_ARQUIVOS_ENV();
  if (mandatoEnv && arquivosEnv) {
    return { mandato: mandatoEnv, arquivos: arquivosEnv, descoberto: false };
  }
  try {
    const resp = await fetch(url, { method: "GET" });
    if (!resp.ok) throw new Error(`GET do form retornou HTTP ${resp.status}`);
    const html = await resp.text();
    const { fileFieldName, textFieldName } = parseFormFieldNames(html);
    return {
      mandato: mandatoEnv || textFieldName || CAMPO_MANDATO_FALLBACK,
      arquivos: arquivosEnv || fileFieldName || CAMPO_ARQUIVOS_FALLBACK,
      descoberto: Boolean(!mandatoEnv && textFieldName) || Boolean(!arquivosEnv && fileFieldName),
    };
  } catch {
    // Sem acesso de leitura ao form (rede, URL errada) — cai no fallback;
    // o erro "de verdade" (se houver) aparece no POST logo em seguida.
    return {
      mandato: mandatoEnv || CAMPO_MANDATO_FALLBACK,
      arquivos: arquivosEnv || CAMPO_ARQUIVOS_FALLBACK,
      descoberto: false,
    };
  }
}

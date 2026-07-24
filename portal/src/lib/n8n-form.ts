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

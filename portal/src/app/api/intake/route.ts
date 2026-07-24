import { NextResponse } from "next/server";
import { parseFormFieldNames } from "@/lib/n8n-form";

// Recebe o upload do portal (multipart) e ENCAMINHA para a URL do Form do N8N
// — servidor-a-servidor (sem CORS). O pipeline (classificação/extração/
// reconciliação) continua 100% no N8N: o portal é só um front-end de intake
// mais amigável, submetendo ao MESMO endpoint que o formulário público do N8N.
// Assim, reenviar no mesmo "mandato" (nome do caso) acumula no mesmo caso —
// fn_upsert_caso reusa por nome (db/migrations/0006).
//
// Precisa do runtime Node (streams/FormData de arquivo), não Edge.
export const runtime = "nodejs";

// Nomes de campo: se as envs vierem preenchidas, são um override explícito
// (usadas direto). Sem elas, o nome é DESCOBERTO lendo o HTML do próprio Form
// do N8N (ver n8n-form.ts) — não adivinhado. Achado em produção (sessão 7
// cont.¹²): o portal enviava um POST com os rótulos visíveis ("Mandato (nome
// do caso)"/"Arquivos") como nome de campo, mas o N8N pode gerar um atributo
// `name` INTERNO diferente do rótulo. O webhook aceitava o POST (200 OK — "o
// upload deu certo" no portal) mas o workflow não recebia arquivo nenhum sob
// o nome esperado, o node `Listar Arquivos` lançava erro e a execução morria
// ANTES de qualquer chamada à OpenAI — daí "sucesso na tela, 0 tokens gastos".
const CAMPO_MANDATO_ENV = process.env.N8N_INTAKE_FIELD_MANDATO || null;
const CAMPO_ARQUIVOS_ENV = process.env.N8N_INTAKE_FIELD_ARQUIVOS || null;
// Fallback de último recurso, só usado se não houver env E a descoberta falhar
// (instância fora do ar, HTML inesperado etc.) — mantém o comportamento
// anterior em vez de travar o upload por completo.
const CAMPO_MANDATO_FALLBACK = "Mandato (nome do caso)";
const CAMPO_ARQUIVOS_FALLBACK = "Arquivos";

async function descobrirNomesDeCampo(url: string): Promise<{ mandato: string; arquivos: string; descoberto: boolean }> {
  if (CAMPO_MANDATO_ENV && CAMPO_ARQUIVOS_ENV) {
    return { mandato: CAMPO_MANDATO_ENV, arquivos: CAMPO_ARQUIVOS_ENV, descoberto: false };
  }
  try {
    const resp = await fetch(url, { method: "GET" });
    if (!resp.ok) throw new Error(`GET do form retornou HTTP ${resp.status}`);
    const html = await resp.text();
    const { fileFieldName, textFieldName } = parseFormFieldNames(html);
    return {
      mandato: CAMPO_MANDATO_ENV || textFieldName || CAMPO_MANDATO_FALLBACK,
      arquivos: CAMPO_ARQUIVOS_ENV || fileFieldName || CAMPO_ARQUIVOS_FALLBACK,
      descoberto: Boolean(!CAMPO_MANDATO_ENV && textFieldName) || Boolean(!CAMPO_ARQUIVOS_ENV && fileFieldName),
    };
  } catch {
    // Sem acesso de leitura ao form (rede, URL errada) — cai no fallback;
    // o erro "de verdade" (se houver) aparece no POST logo em seguida.
    return {
      mandato: CAMPO_MANDATO_ENV || CAMPO_MANDATO_FALLBACK,
      arquivos: CAMPO_ARQUIVOS_ENV || CAMPO_ARQUIVOS_FALLBACK,
      descoberto: false,
    };
  }
}

export async function POST(request: Request) {
  const url = process.env.N8N_INTAKE_FORM_URL;
  if (!url) {
    return NextResponse.json(
      {
        error:
          "Upload pelo portal não configurado: defina N8N_INTAKE_FORM_URL (URL de produção do Form do N8N) nas variáveis de ambiente da Vercel.",
      },
      { status: 503 },
    );
  }

  let form: FormData;
  try {
    form = await request.formData();
  } catch {
    return NextResponse.json({ error: "Requisição inválida (multipart esperado)." }, { status: 400 });
  }

  const mandato = String(form.get("mandato") ?? "").trim();
  const arquivos = form
    .getAll("arquivos")
    .filter((f): f is File => f instanceof File && f.size > 0);

  if (!mandato) {
    return NextResponse.json({ error: "Informe o nome do mandato." }, { status: 400 });
  }
  if (arquivos.length === 0) {
    return NextResponse.json({ error: "Selecione ao menos um arquivo." }, { status: 400 });
  }

  const campos = await descobrirNomesDeCampo(url);

  // Monta o multipart no formato do Form do N8N e encaminha.
  const fwd = new FormData();
  fwd.append(campos.mandato, mandato);
  for (const arquivo of arquivos) {
    fwd.append(campos.arquivos, arquivo, arquivo.name);
  }

  let resp: Response;
  try {
    resp = await fetch(url, { method: "POST", body: fwd });
  } catch (e) {
    return NextResponse.json(
      { error: `Não foi possível contatar o N8N: ${(e as Error).message}` },
      { status: 502 },
    );
  }

  if (!resp.ok) {
    const detalhe = await resp.text().catch(() => "");
    return NextResponse.json(
      {
        error: `O N8N recusou a submissão (HTTP ${resp.status}). Confira a URL do Form e os nomes dos campos ` +
          `(usados: mandato="${campos.mandato}", arquivos="${campos.arquivos}"). ${detalhe.slice(0, 300)}`,
      },
      { status: 502 },
    );
  }

  return NextResponse.json({
    ok: true,
    mandato,
    arquivos: arquivos.length,
    desde: new Date().toISOString(),
  });
}

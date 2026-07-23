import { NextResponse } from "next/server";

// Recebe o upload do portal (multipart) e ENCAMINHA para a URL do Form do N8N
// — servidor-a-servidor (sem CORS). O pipeline (classificação/extração/
// reconciliação) continua 100% no N8N: o portal é só um front-end de intake
// mais amigável, submetendo ao MESMO endpoint que o formulário público do N8N.
// Assim, reenviar no mesmo "mandato" (nome do caso) acumula no mesmo caso —
// fn_upsert_caso reusa por nome (db/migrations/0006).
//
// Precisa do runtime Node (streams/FormData de arquivo), não Edge.
export const runtime = "nodejs";

// Os nomes dos campos esperados pelo Form do N8N são configuráveis por env —
// o default casa com os rótulos atuais do formulário (n8n/build-workflow.mjs:
// "Mandato (nome do caso)" / "Arquivos"). Se a instância do dono usar rótulos
// diferentes, basta ajustar as envs, sem mexer no código.
const CAMPO_MANDATO = process.env.N8N_INTAKE_FIELD_MANDATO || "Mandato (nome do caso)";
const CAMPO_ARQUIVOS = process.env.N8N_INTAKE_FIELD_ARQUIVOS || "Arquivos";

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

  // Monta o multipart no formato do Form do N8N e encaminha.
  const fwd = new FormData();
  fwd.append(CAMPO_MANDATO, mandato);
  for (const arquivo of arquivos) {
    fwd.append(CAMPO_ARQUIVOS, arquivo, arquivo.name);
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
        error: `O N8N recusou a submissão (HTTP ${resp.status}). Confira a URL do Form e os nomes dos campos. ${detalhe.slice(0, 300)}`,
      },
      { status: 502 },
    );
  }

  return NextResponse.json({ ok: true, mandato, arquivos: arquivos.length });
}

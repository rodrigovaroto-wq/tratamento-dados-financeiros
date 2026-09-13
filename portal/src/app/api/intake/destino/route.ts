import { NextResponse } from "next/server";
import { descobrirNomesDeCampo } from "@/lib/n8n-form";

// PARA ONDE O NAVEGADOR MANDA UM LOTE QUE NÃO CABE NA FUNCTION.
//
// Ver `src/lib/limite-de-envio.ts` para o defeito inteiro (413 da borda da
// Vercel com 48 arquivos). Em uma linha: acima de ~4 MB o corpo não chega à
// Serverless Function, então os bytes têm de ir do navegador direto ao Form do
// n8n — e para isso o navegador precisa saber DUAS coisas que só o servidor
// sabe: a URL do Form e os nomes REAIS dos campos.
//
// A DESCOBERTA CONTINUA NO SERVIDOR, e isso é o ponto. O navegador não adivinha
// nome de campo nenhum: ele recebe o par já resolvido pela mesma função que o
// encaminhamento usa (`descobrirNomesDeCampo`). Postar sob o nome errado é o
// defeito da sessão 7 cont.¹² — 200 OK na tela, nenhum arquivo recebido, zero
// token gasto —, e ele não pode voltar por uma porta nova.
//
// O QUE ISTO EXPÕE, dito na cara. Esta rota entrega a URL de produção do Form
// do n8n a quem está autenticado no portal (todas as rotas passam pelo
// `proxy.ts`, que manda para /login quem não está). Essa URL é de um formulário
// PÚBLICO por construção — é o mesmo endereço que qualquer pessoa com o link
// usa para submeter documentos, e era assim antes desta rota existir. O que
// muda é que agora ela sai também no tráfego do navegador de quem já pode
// enviar arquivos pelo portal. Não há credencial nenhuma aqui: nem chave do
// n8n, nem do Supabase, nem do provedor de IA.
export const runtime = "nodejs";

export async function GET() {
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

  const campos = await descobrirNomesDeCampo(url);

  return NextResponse.json({
    url,
    campos: { mandato: campos.mandato, arquivos: campos.arquivos },
    descoberto: campos.descoberto,
    // O RELÓGIO É O DO SERVIDOR, e não é preciosismo: `agora` vira o `desde` do
    // acompanhamento (`/api/intake/status`), que o compara com `criado_em` das
    // linhas gravadas pelo pipeline. Um navegador adiantado em cinco minutos
    // filtraria para fora os documentos do próprio lote que acabou de mandar —
    // e a tela acompanharia um lote vivo contando zero para sempre.
    //
    // Ele é lido ANTES do envio de propósito: `desde` só pode errar para o lado
    // de abrir demais a janela (no máximo pega o que o próprio envio criou),
    // nunca para o de fechar.
    agora: new Date().toISOString(),
  });
}

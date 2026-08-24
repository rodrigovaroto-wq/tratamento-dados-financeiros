import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { paginar } from "@/lib/supabase/paginar";

// Consultado pelo portal (polling) depois de um upload, pra saber quando os
// arquivos enviados já passaram pela classificação E pela extração — não tem
// nenhum "flag de concluído" único no schema, então isto combina dois sinais:
//   1. `documento` criado para o caso (classificação terminou) desde o envio.
//   2. `evento_auditoria` do tipo `extracao_sombra` referenciando aquele
//      documento_versao (extração TENTOU rodar — sucesso ou falha; sempre
//      gravado por fn_registrar_campos_extraidos, ver db/migrations/0016).
// "Pronto" aqui significa "o pipeline terminou de tentar", não "sem erros" —
// pendências (se houver) continuam visíveis no dashboard do caso como sempre.
export const runtime = "nodejs";

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const casoNome = searchParams.get("caso")?.trim();
  const desde = searchParams.get("desde");
  const esperados = Number(searchParams.get("esperados") ?? "0");

  if (!casoNome || !desde || !Number.isFinite(esperados) || esperados <= 0) {
    return NextResponse.json({ error: "Parâmetros inválidos (caso, desde, esperados)." }, { status: 400 });
  }

  const supabase = await createClient();

  // A FALHA VEM PRIMEIRO, e vem antes de qualquer contagem de progresso.
  //
  // Esta rota deduz "está processando" da AUSÊNCIA de documentos — e falha
  // produz a mesma ausência. Foi assim que 35 documentos recusados pelo
  // orçamento viraram um "aguarde" eterno: o pipeline tinha morrido dois minutos
  // antes e a tela seguia calma. Perguntar pela falha ANTES de contar progresso é
  // o que faz os dois estados deixarem de ter a mesma aparência.
  const { data: falhas } = await supabase.rpc("fn_falhas_abertas", {
    p_caso_nome: casoNome,
    p_desde: desde,
  });
  const falha = (falhas as Array<{ id: string; etapa: string; mensagem: string }> | null)?.[0];
  if (falha) {
    return NextResponse.json({
      classificados: 0, processados: 0, esperados, pronto: false,
      falha: { id: falha.id, etapa: falha.etapa, mensagem: falha.mensagem },
    });
  }

  const { data: caso, error: casoErr } = await supabase
    .from("caso")
    .select("id")
    .eq("nome", casoNome)
    .maybeSingle();

  if (casoErr) {
    return NextResponse.json({ error: casoErr.message }, { status: 500 });
  }
  if (!caso) {
    // Ainda nem o `caso` foi criado — normal logo após o envio.
    return NextResponse.json({ classificados: 0, processados: 0, esperados, pronto: false });
  }

  // PAGINADO: estes dois são CONTADORES DE PROGRESSO da ingestão, e o teto do
  // PostgREST (1000 por consulta, silencioso) faria a barra parar em mil
  // documentos e o lote parecer travado quando está andando.
  const { data: documentos, error: docErr } = await paginar<{ id: string; documento_versao: { id: string }[] }>(
    (de, ate) =>
      supabase
        .from("documento")
        .select("id, documento_versao(id)")
        .eq("caso_id", caso.id)
        .gte("criado_em", desde)
        .order("id", { ascending: true })
        .range(de, ate),
  );

  if (docErr) {
    return NextResponse.json({ error: docErr.message }, { status: 500 });
  }

  const docs = documentos;
  const classificados = docs.length;
  const versaoIds = docs.flatMap((d) => (d.documento_versao ?? []).map((v) => v.id));

  let processados = 0;
  if (versaoIds.length > 0) {
    const refs = versaoIds.map((id) => `documento_versao:${id}`);
    const { data: eventos, error: evtErr } = await paginar<{ entidade_ref: string }>((de, ate) =>
      supabase
        .from("evento_auditoria")
        .select("entidade_ref")
        .eq("acao", "extracao_sombra")
        .gte("criado_em", desde)
        .in("entidade_ref", refs)
        .order("id", { ascending: true })
        .range(de, ate),
    );

    if (evtErr) {
      return NextResponse.json({ error: evtErr.message }, { status: 500 });
    }
    processados = new Set(eventos.map((e) => e.entidade_ref)).size;
  }

  const pronto = classificados >= esperados && processados >= esperados;

  // TERMINOU E NÃO TROUXE NADA — o estado que passava por SUCESSO.
  //
  // `pronto` mede que o pipeline TENTOU ler cada arquivo: um evento
  // `extracao_sombra` por documento, gravado por `fn_registrar_campos_extraidos`
  // tanto no acerto quanto na falha (0016). É a medida certa para saber que o
  // trabalho acabou — e é cega para o que ele produziu. Um lote em que TODA
  // leitura falhou emite exatamente os mesmos eventos de um lote perfeito, e a
  // tela dizia "pronto" para os dois.
  //
  // `comLinhas` conta quantos documentos deixaram ao menos uma linha no banco.
  // É a diferença entre "tentou" e "conseguiu".
  //
  // SÓ QUANDO `pronto`, e a condição é o que torna isto barato: é uma consulta a
  // mais no ÚLTIMO polling, não a cada 8 segundos durante 20 minutos. Perguntar
  // antes também não responderia nada — um documento sem linhas no meio do lote
  // é um documento que ainda não foi lido.
  let comLinhas: number | null = null;
  if (pronto && versaoIds.length > 0) {
    const { data: campos, error: campoErr } = await paginar<{ documento_versao_id: string }>((de, ate) =>
      supabase
        .from("campo_extraido")
        .select("documento_versao_id")
        .in("documento_versao_id", versaoIds)
        .order("id", { ascending: true })
        .range(de, ate),
    );
    // ERRO AQUI NÃO DERRUBA O `pronto`. O lote terminou de verdade, e trocar
    // essa notícia por uma tela de erro porque a CONFERÊNCIA falhou seria pior
    // que não conferir. `null` diz "não sei", e quem lê trata diferente de zero.
    if (!campoErr) comLinhas = new Set(campos.map((c) => c.documento_versao_id)).size;
  }

  return NextResponse.json({ classificados, processados, esperados, pronto, comLinhas });
}

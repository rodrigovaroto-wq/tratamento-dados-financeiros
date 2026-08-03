import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import {
  ampliarNotasNoBuffer, buildExportWorkbook, nomeArquivoSanitizado,
  type DocumentoParaExport, type MacroAnual, type MacroExpectativa,
} from "@/lib/export";
import type { CampoExtraido } from "@/lib/types";

// exceljs (usado em lib/export.ts) usa Buffer/streams do Node — precisa do
// runtime Node, não Edge.
export const runtime = "nodejs";

export async function GET(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  // MODO (decisão do dono): `?modo=dados` entrega só as abas de dado — insumo de
  // conferência, disponível desde a ingestão. Sem o parâmetro sai o completo, com
  // a Modelagem. Valor desconhecido cai em "completo" em vez de erro: um link
  // datilografado errado não deve deixar o analista sem arquivo.
  const modo = new URL(request.url).searchParams.get("modo") === "dados" ? "dados" : "completo";
  const supabase = await createClient();

  const [casoRes, documentosRes] = await Promise.all([
    supabase.from("caso").select("id, nome, produto").eq("id", id).single(),
    supabase
      .from("documento")
      .select(
        // `n_versao` é o que permite ao export saber qual extração é a VIGENTE
        // quando o mesmo arquivo foi reextraído (db/migrations/0026 registra a
        // reextração como versão nova do mesmo documento) — sem ela, as duas
        // extrações entrariam juntas e a soma da seção contaria as duas.
        `id, tipo_taxonomia,
         entidade:entidade_id(razao_social), periodo:periodo_id(tipo, referencia),
         documento_versao(id, nome_original, n_versao)`,
      )
      .eq("caso_id", id),
  ]);

  if (casoRes.error || !casoRes.data) {
    return NextResponse.json({ error: "Caso não encontrado." }, { status: 404 });
  }

  const caso = casoRes.data;

  // `.error` das consultas PRINCIPAIS: a 0028 nomeou este defeito ("`?? []` sobre
  // `.data`, sem olhar `.error`") e corrigiu SÓ o ramo macro. Aqui era o pior lugar
  // para ele estar: erro de RLS/permissão/relacionamento no PostgREST produzia um
  // book com "Linhas totais extraídas: 0" e nenhuma mensagem — exatamente o sintoma
  // do teste v14, que a 0016 tentou tornar impossível.
  //
  // E aqui a resposta certa é DIFERENTE da do macro. Macro é opcional: a aba declara
  // "a consulta falhou" e o resto do book segue valendo. Sem `documento` ou
  // `campo_extraido`, o book não tem conteúdo nenhum — entregar um arquivo vazio é
  // pior que não entregar, porque um `.xlsx` que abre parece um resultado.
  if (documentosRes.error) {
    console.error(`[export] consulta de documentos falhou: ${documentosRes.error.message}`, { caso_id: id });
    return NextResponse.json(
      {
        error: "Não foi possível ler os documentos deste caso — o export foi ABORTADO em vez de gerar uma planilha vazia.",
        detalhe: documentosRes.error.message,
        dica: "Causa mais comum: RLS/GRANT (ver db/migrations/0028). O dado pode estar na base; a consulta é que não chegou nele.",
      },
      { status: 500 },
    );
  }
  const documentos = (documentosRes.data as unknown as DocumentoParaExport[] | null) ?? [];

  const versaoIds = documentos.flatMap((doc) => (doc.documento_versao ?? []).map((v) => v.id));
  const camposRes = versaoIds.length
    ? await supabase
        .from("campo_extraido")
        .select(
          "id, documento_versao_id, secao, secao_canonica, entidade_coluna, periodo_coluna, chave, valor_texto, valor_num, unidade, confianca, origem_pagina, ordem, status_aceite, aceito_por, aceito_em",
        )
        .in("documento_versao_id", versaoIds)
        // ORDEM DO DOCUMENTO (db/migrations/0027). Sem isto o PostgREST devolve
        // as linhas em ordem arbitrária, e a detecção de "subtotal impresso
        // acima dos seus componentes" — que é o que conserta o Ativo Circulante
        // da VT Logística (7.254 onde o documento diz 3.961) — não tem sinal
        // nenhum para trabalhar. `nullsFirst: false` mantém a extração ANTIGA
        // (ordem nula) no fim, sem embaralhar o que tem ordem.
        .order("documento_versao_id", { ascending: true })
        .order("ordem", { ascending: true, nullsFirst: false })
    : { data: [] as CampoExtraido[], error: null };

  if (camposRes.error) {
    console.error(`[export] consulta de campos extraídos falhou: ${camposRes.error.message}`, { caso_id: id });
    return NextResponse.json(
      {
        error: "Não foi possível ler as linhas extraídas — o export foi ABORTADO em vez de gerar uma planilha sem números.",
        detalhe: camposRes.error.message,
        dica: "Causa mais comum: RLS/GRANT (ver db/migrations/0028). O dado pode estar na base; a consulta é que não chegou nele.",
      },
      { status: 500 },
    );
  }
  const campos = (camposRes.data as CampoExtraido[] | null) ?? [];

  // POR QUE a extração falhou, e não só QUAIS documentos falharam. No "teste v30"
  // os 14 documentos falharam e o export listava os nomes — a CAUSA (que a
  // pendência já registrava) ficava só na fila de revisão, numa tela diferente.
  // Quem abre o book precisa saber, ali, se o problema é crédito da OpenAI, cota
  // do dia ou cadência: as três pedem ações diferentes e só uma delas é nossa.
  const falhasRes = await supabase
    .from("pendencia")
    .select("descricao, documento_id")
    .eq("caso_id", id)
    .eq("tipo", "extracao_falhou")
    .neq("estado", "resolvida");
  // Esta é auxiliar (a lista de causas), então segue a doutrina do macro: declara
  // que não deu para ler, em vez de abortar o book inteiro ou omitir em silêncio.
  if (falhasRes.error) {
    console.error(`[export] consulta de causas de falha falhou: ${falhasRes.error.message}`, { caso_id: id });
  }
  const causasDeFalha = [
    ...(falhasRes.error
      ? [`(não foi possível ler as causas registradas: ${falhasRes.error.message})`]
      : []),
    ...new Set(
      ((falhasRes.data as Array<{ descricao: string | null }> | null) ?? [])
        .map((p) => p.descricao ?? "")
        // A descrição da pendência é "Extração de 'X.pdf' falhou ... Motivo: <causa>".
        // Só a causa interessa aqui: o nome do arquivo já vai na outra coluna, e
        // repetir 14 vezes o mesmo motivo esconderia o que importa.
        .map((d) => d.split(/Motivo:\s*/)[1]?.trim())
        .filter((c): c is string => !!c),
    ),
  ];

  // Índices macro (db/migrations/0025). São do CASO nenhum — a série é a mesma
  // para todos os mandatos —, por isso vêm à parte e não filtram por caso.
  // Falha aqui NÃO derruba o export: sem macro o arquivo sai como sempre saiu,
  // só sem a aba Macro e com as premissas de inflação/juro zeradas. Um índice
  // indisponível não pode impedir alguém de baixar a planilha do mandato.
  const [anuaisRes, expRes] = await Promise.all([
    supabase.rpc("fn_indice_macro_anual", { p_desde_ano: new Date().getFullYear() - 11 }),
    supabase
      .from("indice_macro_expectativa")
      .select("serie, ano_ref, mediana, coletado_em")
      .gte("ano_ref", new Date().getFullYear() - 1)
      .order("coletado_em", { ascending: false }),
  ]);

  // Erro de CONSULTA (RLS sem policy volta 0 linhas sem erro; função sem
  // `grant execute` para `authenticated` volta erro de permissão — os dois
  // aconteceram de fato na `0025`, ver db/migrations/0028) é DIFERENTE de "sem
  // dado coletado", e as duas coisas não podem cair na mesma mensagem — foi
  // exatamente essa confusão que fez o export dizer "sem dado coletado" com a
  // base já povoada. `console.error` fica nos logs da função (Vercel/servidor):
  // não é visível no arquivo, mas para de ser invisível PARA SEMPRE.
  const nomesRes = await supabase.from("indice_macro_serie").select("codigo, nome");
  // NOMEAR a parte que falhou, não só a primeira mensagem. Com `??` em cadeia,
  // uma falha só nos NOMES das séries produzia uma mensagem indistinguível de
  // uma falha nos índices — e as duas degradam o arquivo de formas diferentes
  // (código cru no rótulo × série inteira ausente). Quem for conferir no
  // Supabase precisa saber onde olhar.
  const macroErro = [
    anuaisRes.error && `índices anuais: ${anuaisRes.error.message}`,
    expRes.error && `expectativas do Focus: ${expRes.error.message}`,
    nomesRes.error && `nomes das séries: ${nomesRes.error.message}`,
  ].filter(Boolean).join("; ") || undefined;
  if (macroErro) {
    console.error(`[export] consulta de índices macro falhou: ${macroErro}`, {
      anuais: anuaisRes.error, expectativas: expRes.error, series: nomesRes.error,
    });
  }

  const anuais = (anuaisRes.data as MacroAnual[] | null) ?? [];
  // A API devolve todas as coletas; para o export vale a MAIS RECENTE de cada
  // (série, ano) — e como vem ordenado por coleta decrescente, o primeiro que
  // aparece já é o certo.
  const vistos = new Set<string>();
  const expectativas = ((expRes.data as MacroExpectativa[] | null) ?? []).filter((e) => {
    const k = `${e.serie}/${e.ano_ref}`;
    if (vistos.has(k)) return false;
    vistos.add(k);
    return true;
  });

  const nomes = Object.fromEntries(
    (nomesRes.data ?? []).map((s: { codigo: string; nome: string }) => [s.codigo, s.nome]),
  );

  const macro = anuais.length > 0 || expectativas.length > 0
    ? { anuais, expectativas, nomes }
    : undefined;

  const workbook = buildExportWorkbook({ caso, documentos, campos, macro, macroErro, causasDeFalha, modo });
  const buffer = await ampliarNotasNoBuffer(await workbook.xlsx.writeBuffer());
  // O nome do arquivo DIZ qual dos dois é. Dois arquivos com o mesmo nome na
  // pasta de Downloads, um com modelo e outro sem, é confusão garantida — e a
  // pergunta "qual desses é o completo?" não tem resposta olhando o ícone.
  const sufixo = modo === "dados" ? "dados" : "completo";
  const filename = `${nomeArquivoSanitizado(caso.nome)}-${sufixo}-${new Date().toISOString().slice(0, 10)}.xlsx`;

  return new NextResponse(buffer as unknown as BodyInit, {
    headers: {
      "Content-Type": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      "Content-Disposition": `attachment; filename="${filename}"`,
    },
  });
}

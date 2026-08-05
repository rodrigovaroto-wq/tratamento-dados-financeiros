import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import type { EntradaModeloInstitucional, LinhaModelo } from "@/lib/modelo-institucional";
import {
  ampliarNotasNoBuffer, buildExportWorkbook, nomeArquivoSanitizado, type ConfigModelagem,
  type DocumentoParaExport, type MacroAnual, type MacroExpectativa,
} from "@/lib/export";
import type { CampoExtraido } from "@/lib/types";
import {
  casarVinculosComLinhas, type LinhaParaCasar, type VinculoParaCasar,
} from "@/lib/modelagem-linha";

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

  // ---- Fase 7.4: a configuração de modelagem e o Portão 2 -------------------
  //
  // O modo COMPLETO carrega um modelo projetado. Entregar isso sobre base que não
  // passou o Portão 2 seria dar aparência de resultado aprovado a número que
  // ninguém aprovou — e a regra do portão é determinística (f0/04, 0037), então
  // não há julgamento a fazer aqui: pergunta-se e obedece-se.
  //
  // O modo DADOS não passa por aqui de propósito: ele é insumo de CONFERÊNCIA, e
  // conferir é justamente o que se faz antes de aprovar. Bloqueá-lo criaria o
  // impasse de precisar da aprovação para poder conferir.
  let modelagemConfig: ConfigModelagem | undefined;
  let modeloInstitucional: EntradaModeloInstitucional | undefined;
  if (modo === "completo") {
    const portao = await supabase.rpc("fn_avaliar_portao2", { p_caso_id: id });
    const aval = portao.data as { elegivel?: boolean; motivos?: string[] } | null;
    if (aval && aval.elegivel === false) {
      return NextResponse.json(
        {
          error: "O export COMPLETO foi recusado: este caso não passou o Portão 2.",
          motivos: aval.motivos ?? [],
          dica: "Use \"Exportar dados\" para conferir a extração — esse modo não depende do portão. "
            + "O completo carrega modelo projetado, e projetar sobre base não aprovada dá aparência "
            + "de resultado aprovado a número que ninguém aprovou.",
        },
        { status: 409 },
      );
    }

    // A configuração vem em três consultas porque são três coisas distintas:
    // parâmetros do caso, premissas ativas (com o catálogo para saber a fórmula),
    // e o vínculo linha↔premissa. Ausência de qualquer uma NÃO é erro: o arquivo
    // sai com o esqueleto agregado, como sempre saiu.
    const [paramRes, premRes, vincRes, linhasRes, sazoRes] = await Promise.all([
      supabase.from("caso_modelagem").select("*").eq("caso_id", id).maybeSingle(),
      supabase.from("caso_premissa")
        .select("premissa_codigo, valores, origem, "
          + "premissa_catalogo!inner(nome, formula, unidade, natureza)")
        .eq("caso_id", id).eq("ativo", true),
      supabase.from("caso_linha_premissa")
        .select("rotulo_norm, secao_canonica, premissa_codigo, sazonalidade_codigo")
        .eq("caso_id", id),
      supabase.rpc("fn_linhas_para_modelagem", { p_caso_id: id }),
      // A curva mensal do caso (0040). Vem vazia quando não há FATURAMENTO_24M —
      // e aí as linhas com sazonalidade ficam sem distribuição mensal, dizendo
      // por quê, em vez de rateio uniforme.
      supabase.rpc("fn_sazonalidade_do_caso", { p_caso_id: id }),
    ]);

    const par = paramRes.data as unknown as {
      entidade: string | null; ultimo_exercicio_real: number | null; anos_projetados: number;
      setor: string | null;
    } | null;
    // O embed do PostgREST vem como ARRAY (ele não assume 1:1 no tipo gerado),
    // então normaliza-se aqui em vez de confiar no formato — um `?.nome` sobre
    // array daria `undefined` silencioso e a premissa apareceria sem nome no
    // arquivo.
    type EmbedCatalogo = {
      nome: string; formula: string; unidade: string | null; natureza?: string;
    };
    const premissas = ((premRes.data ?? []) as unknown as Array<{
      premissa_codigo: string; valores: Record<string, number>;
      origem?: string | null;
      premissa_catalogo: EmbedCatalogo | EmbedCatalogo[] | null;
    }>).map((p) => {
      const cat = Array.isArray(p.premissa_catalogo) ? p.premissa_catalogo[0] : p.premissa_catalogo;
      return {
        codigo: p.premissa_codigo,
        nome: cat?.nome ?? p.premissa_codigo,
        formula: cat?.formula ?? "",
        unidade: cat?.unidade ?? null,
        natureza: cat?.natureza ?? "",
        origem: p.origem ?? null,
        valores: p.valores ?? {},
      };
    });

    // O rótulo EXIBIDO e o valor base vêm de `fn_linhas_para_modelagem` (0039),
    // casados pelo PAR (seção, rótulo normalizado) — a mesma identidade que o
    // índice único de `caso_linha_premissa` usa. Sem a seção, rótulo repetido
    // entre seções (13 no caso do v35: `Empréstimos e Financiamentos`,
    // `Arrendamentos`, `Capital social`…) fazia o vínculo herdar o valor base da
    // OUTRA seção, e a projeção partia do saldo errado sem dar erro nenhum.
    const linhas = casarVinculosComLinhas(
      (vincRes.data ?? []) as unknown as VinculoParaCasar[],
      (linhasRes.data ?? []) as unknown as LinhaParaCasar[],
    );

    if (par || premissas.length > 0 || linhas.length > 0) {
      const curva = ((sazoRes.data ?? []) as unknown as Array<{ mes: number; fracao: number }>)
        .sort((a2, b2) => a2.mes - b2.mes)
        .map((x) => Number(x.fracao));

      modelagemConfig = {
        entidade: par?.entidade ?? null,
        sazonalidade: curva.length === 12 ? curva : undefined,
        ultimoExercicioReal: par?.ultimo_exercicio_real ?? null,
        anosProjetados: par?.anos_projetados ?? 5,
        premissas,
        linhas,
      };
    }

    // ---- Fase 9: o MODELO INSTITUCIONAL --------------------------------------
    //
    // Ele exige DUAS coisas que o modelo agregado não exigia, e as duas são
    // condição de existência e não preferência:
    //
    //   • ENTIDADE MODELADA. Sem ela o modelo somaria o ativo de uma empresa do
    //     grupo com o passivo de outra — foi medido contra o book (0044): "Ativo
    //     Circulante 2024" devolvia o da VT Logística enquanto a Metalúrgica
    //     tinha 17× mais. Balanço que não existe em lugar nenhum, com cara de
    //     balanço.
    //   • ÚLTIMO EXERCÍCIO REAL, para saber onde termina o realizado e começa a
    //     projeção. Adivinhar isso pelo maior ano extraído erraria justamente no
    //     caso em que o cliente mandou um balancete parcial do ano corrente.
    //
    // Faltando qualquer uma, o arquivo sai SEM as 14 abas e o motivo é dito no
    // cabeçalho da resposta — em vez de sair um modelo silenciosamente errado.
    const entidadeModelada = par?.entidade?.trim() || null;
    const ultimoReal = par?.ultimo_exercicio_real ?? null;
    if (entidadeModelada && ultimoReal) {
      const valoresRes = await supabase.rpc("fn_valores_por_ano", {
        p_caso_id: id, p_entidade: entidadeModelada,
      });
      const valores = (valoresRes.data ?? []) as unknown as Array<{
        rotulo_norm: string; secao_canonica: string | null; ano: number; valor: number;
      }>;
      // Só exercícios ATÉ o último realizado entram como histórico: um balancete
      // do ano corrente não é exercício fechado, e tratá-lo como tal faria a
      // projeção partir de meio ano.
      const anosHistoricos = [...new Set(valores.map((v) => v.ano))]
        .filter((a) => a <= ultimoReal).sort((a, b) => a - b);
      const nProj = par?.anos_projetados ?? 5;
      const anosProjetados = Array.from({ length: nProj }, (_, i) => ultimoReal + 1 + i);

      const porRotulo = new Map<string, Record<string, number>>();
      for (const v of valores) {
        if (!anosHistoricos.includes(v.ano)) continue;
        if (!porRotulo.has(v.rotulo_norm)) porRotulo.set(v.rotulo_norm, {});
        porRotulo.get(v.rotulo_norm)![String(v.ano)] = Number(v.valor);
      }
      const linhasModelo: LinhaModelo[] = ((linhasRes.data ?? []) as unknown as Array<{
        secao_canonica: string | null; chave: string; rotulo_norm: string;
        papel: LinhaModelo["papel"]; unidade: string | null; moeda: string | null;
        documentos: string[] | null;
      }>).map((l) => ({
        secao_canonica: l.secao_canonica, chave: l.chave, rotulo_norm: l.rotulo_norm,
        papel: l.papel, unidade: l.unidade, moeda: l.moeda, documentos: l.documentos,
        valores: porRotulo.get(l.rotulo_norm) ?? {},
      }));

      // A base macro do modelo: realizado + Focus, com a fonte de cada célula.
      const macroModelo = [
        ...anuais.map((a) => ({
          serie: a.serie, ano: a.ano, valor: Number(a.retorno),
          fonte: `realizado (${a.meses} meses)`,
        })),
        ...expectativas.map((e) => ({
          serie: e.serie, ano: e.ano_ref, valor: Number(e.mediana),
          fonte: `Focus, coleta ${e.coletado_em}`,
        })),
      ];

      // Unidade dominante: a das linhas, não um palpite. Se o caso mistura milhar
      // e unidade, a dominante entra no cabeçalho e a divergência aparece por
      // linha (cada célula histórica leva a sua unidade em nota).
      const contagemUnidade = new Map<string, number>();
      for (const l of linhasModelo) {
        if (!l.unidade) continue;
        contagemUnidade.set(l.unidade, (contagemUnidade.get(l.unidade) ?? 0) + 1);
      }
      const unidadeDominante = [...contagemUnidade.entries()].sort((a, b) => b[1] - a[1])[0]?.[0];

      modeloInstitucional = {
        caso: { nome: caso.nome, produto: caso.produto },
        agora: new Date(),
        entidade: entidadeModelada,
        setor: par?.setor ?? null,
        anosHistoricos, anosProjetados,
        stressPct: 0.2,
        caixaMinimo: 0,
        aliquotaTributos: 0.34,
        linhas: linhasModelo,
        premissas,
        vinculos: ((vincRes.data ?? []) as unknown as Array<{
          rotulo_norm: string; premissa_codigo: string | null; sazonalidade_codigo: string | null;
        }>).map((v) => ({
          rotulo_norm: v.rotulo_norm,
          premissa_codigo: v.premissa_codigo,
          sazonalidade_codigo: v.sazonalidade_codigo,
        })),
        macro: macroModelo,
        unidade: unidadeDominante === "milhar" ? "R$ mil"
          : unidadeDominante === "unidade" ? "R$" : (unidadeDominante ?? "R$"),
      };
    }
  }

  const workbook = buildExportWorkbook({
    caso, documentos, campos, macro, macroErro, causasDeFalha, modo, modelagemConfig,
    modeloInstitucional,
  });
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

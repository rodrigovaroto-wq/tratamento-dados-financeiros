// Tipos das linhas lidas do Postgres (subconjunto usado pelo portal).
// Fonte da verdade do schema: db/migrations/*.sql — manter em sincronia.

export type CasoStatus =
  | "intake"
  | "em_triagem"
  | "completude_ok"
  | "em_revisao"
  | "aprovado"
  | "pronto_para_base"
  | "bloqueado"
  | "aguardando_cliente";

export type Obrigatoriedade = "obrigatorio" | "complementar";

export interface Caso {
  id: string;
  nome: string;
  produto: string;
  status: CasoStatus;
  criado_em: string;
}

export interface Entidade {
  id: string;
  caso_id: string;
  razao_social: string;
  cnpj: string | null;
  papel_no_grupo: string | null;
}

export interface Periodo {
  id: string;
  caso_id: string;
  tipo: string;
  referencia: string;
}

export type Legibilidade = "ok" | "degradado" | "ilegivel";

export interface DocumentoVersao {
  id: string;
  nome_original: string | null;
  legibilidade: Legibilidade | null;
  nota_legibilidade: string | null;
}

export interface Documento {
  id: string;
  caso_id: string;
  entidade_id: string | null;
  periodo_id: string | null;
  tipo_taxonomia: string | null;
  status: string;
  confianca: number | null;
  fonte: string | null;
  justificativa: string | null;
  resumo: string | null;
  criado_em: string;
  entidade: Pick<Entidade, "razao_social"> | null;
  periodo: Pick<Periodo, "tipo" | "referencia"> | null;
  documento_versao: DocumentoVersao[] | null;
}

export type StatusAceite = "pendente" | "aceito" | "com_ressalva";

// Uma linha extraída pelo diagnóstico/extração (E2, N0/sombra) — db/migrations/0005, 0010, 0011.
// status_aceite/aceito_por/aceito_em = Portão 2 mínimo (f0/07): sem aceite,
// nunca é "fato" — só sugestão pendente de revisão.
export interface CampoExtraido {
  id: string;
  documento_versao_id: string;
  secao: string | null;
  secao_canonica: string | null; // sugestão da IA (db/migrations/0012) — chaves de statement-templates.ts; fallback advisory do classificador
  entidade_coluna: string | null; // db/migrations/0014 — nome da coluna/entidade quando o documento tem várias entidades lado a lado (null = documento de 1 entidade só)
  chave: string;
  valor_texto: string | null;
  valor_num: number | null;
  unidade: string | null;
  confianca: number | null;
  origem_pagina: number | null;
  status_aceite: StatusAceite;
  aceito_por: string | null;
  aceito_em: string | null;
}

export interface ChecklistItem {
  id: string;
  caso_id: string;
  tipo_taxonomia: string;
  obrigatoriedade: Obrigatoriedade;
  status: string;
  documento_id: string | null;
}

export interface Pendencia {
  id: string;
  caso_id: string;
  tipo: string;
  severidade: "bloqueante" | "importante" | "complementar";
  estado: string;
  descricao: string | null;
  documento_id: string | null;
  criada_em: string;
}

// Tipos de pendencia_tipo (db/migrations/0001, 0009) gerados pela reconciliação
// Classe A (E3) — divergência aritmética detectada ou pré-condição não satisfeita.
export const PENDENCIA_TIPOS_RECONCILIACAO = [
  "divergencia_reconciliacao",
  "precondicao_nao_satisfeita",
] as const;

// Tipos de pendencia_tipo (db/migrations/0001, 0010) gerados pelo diagnóstico de
// conteúdo (E1/E2) — o conteúdo diverge do que já está registrado no documento.
// Corrigíveis pela MESMA fila de revisão da classificação (fn_revisar_documento
// já aceita tipo/entidade/período juntos).
export const PENDENCIA_TIPOS_DIAGNOSTICO_REVISAVEIS = [
  "classificacao_pendente",
  "tipo_incorreto",
  "entidade_incorreta",
  "periodo_incorreto",
] as const;

// Pendência de diagnóstico que não é "corrigível" via tipo/entidade/período —
// sinaliza problema no ARQUIVO em si, listada à parte (só leitura).
export const PENDENCIA_TIPO_ARQUIVO_ILEGIVEL = "arquivo_ilegivel";

// Tipos de pendencia_tipo (db/migrations/0013, 0016) gerados pela GUARDA de
// qualidade da extração (E2) — não são erro de classificação nem divergência
// de reconciliação, são sinais de que a extração em si pode não ser confiável
// (padrão fabricado, confiança baixa, ou a chamada falhou/veio truncada e
// gravou menos linhas do que devia). Só leitura — revisar contra o arquivo
// original antes de aceitar.
export const PENDENCIA_TIPOS_QUALIDADE_EXTRACAO = [
  "extracao_padrao_suspeito",
  "extracao_baixa_confianca",
  "extracao_falhou",
] as const;

export interface TaxonomiaTipoDocumento {
  codigo: string;
  categoria: string;
  documento: string;
  obrigatoriedade: Obrigatoriedade;
}

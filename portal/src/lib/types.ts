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
  criado_em: string;
  entidade: Pick<Entidade, "razao_social"> | null;
  periodo: Pick<Periodo, "tipo" | "referencia"> | null;
  documento_versao: Array<{ nome_original: string | null }> | null;
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

export interface TaxonomiaTipoDocumento {
  codigo: string;
  categoria: string;
  documento: string;
  obrigatoriedade: Obrigatoriedade;
}

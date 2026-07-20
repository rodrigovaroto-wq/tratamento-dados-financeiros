import type { CasoStatus } from "./types";

// Rótulo + cor por status do caso (f0/04 — máquina de estado do caso).
export const CASO_STATUS_LABEL: Record<CasoStatus, string> = {
  intake: "Intake",
  em_triagem: "Em triagem",
  completude_ok: "Completude OK",
  em_revisao: "Em revisão",
  aprovado: "Aprovado",
  pronto_para_base: "Pronto p/ base",
  bloqueado: "Bloqueado",
  aguardando_cliente: "Aguardando cliente",
};

export const CASO_STATUS_COLOR: Record<CasoStatus, string> = {
  intake: "bg-neutral-100 text-neutral-700",
  em_triagem: "bg-amber-100 text-amber-800",
  completude_ok: "bg-emerald-100 text-emerald-800",
  em_revisao: "bg-blue-100 text-blue-800",
  aprovado: "bg-emerald-100 text-emerald-800",
  pronto_para_base: "bg-emerald-100 text-emerald-800",
  bloqueado: "bg-red-100 text-red-800",
  aguardando_cliente: "bg-amber-100 text-amber-800",
};

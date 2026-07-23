import Link from "next/link";
import UploadForm from "@/components/upload-form";

export default function NovoMandatoPage() {
  return (
    <div className="max-w-2xl space-y-6">
      <div>
        <Link href="/casos" className="text-sm text-neutral-500 underline">
          ← Voltar aos mandatos
        </Link>
        <h1 className="mt-2 text-lg font-semibold">Novo mandato</h1>
        <p className="text-sm text-neutral-500">
          Suba os arquivos brutos do mandato. Você pode enviar mais depois — basta usar o mesmo nome
          de mandato para acumular tudo no mesmo checklist, exportação e checagem de dados.
        </p>
      </div>
      <UploadForm />
    </div>
  );
}

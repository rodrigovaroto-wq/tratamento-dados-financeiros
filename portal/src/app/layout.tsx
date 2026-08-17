import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Oria Partners · Tratamento de Dados Financeiros",
  description: "Portal interno — mandatos, conferência da ingestão e fila de revisão.",
  // O sextante como ícone da aba: é a parte da marca que sobrevive a 16px.
  icons: { icon: "/logo-oria-sextante.svg" },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="pt-BR" className="h-full">
      <body className="min-h-full bg-tinta-50 text-tinta-900 antialiased">{children}</body>
    </html>
  );
}

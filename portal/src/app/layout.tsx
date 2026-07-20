import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Oria · Tratamento de Dados Financeiros",
  description: "Portal interno — dashboard de casos e fila de revisão de classificação.",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="pt-BR" className="h-full">
      <body className="min-h-full bg-neutral-50 text-neutral-900 antialiased">{children}</body>
    </html>
  );
}

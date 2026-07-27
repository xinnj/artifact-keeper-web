import type { Metadata } from "next";
import { headers } from "next/headers";
import localFont from "next/font/local";
import { Providers } from "@/providers";
import { Toaster } from "@/components/ui/sonner";
import { NONCE_HEADER } from "@/lib/security-headers";
import "./globals.css";

// Geist is self-hosted (next/font/local) rather than fetched from
// fonts.googleapis.com via next/font/google. The latter downloads the font
// CSS during `next build`, which fails in build environments that cannot reach
// Google (e.g. our China-based deploy server). Self-hosting removes the
// build-time network dependency entirely. Fonts sourced from the canonical
// vercel/geist-font repo: fonts/Geist/webfonts/Geist[wght].woff2 and
// fonts/GeistMono/webfonts/GeistMono[wght].woff2.
const geistSans = localFont({
  src: "./fonts/geist-sans-variable.woff2",
  variable: "--font-geist-sans",
  weight: "100 900",
});

const geistMono = localFont({
  src: "./fonts/geist-mono-variable.woff2",
  variable: "--font-geist-mono",
  weight: "100 900",
});

export const metadata: Metadata = {
  title: "Artifact Keeper",
  description:
    "Enterprise artifact registry for managing software packages across multiple formats.",
};

export default async function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  // Per-request CSP nonce set by the middleware. Reading `headers()` also
  // opts every route into dynamic rendering, which nonce-based CSP requires:
  // Next.js stamps the nonce onto framework scripts during SSR only.
  const nonce = (await headers()).get(NONCE_HEADER) ?? undefined;
  return (
    <html lang="en" suppressHydrationWarning>
      <body
        className={`${geistSans.variable} ${geistMono.variable} antialiased`}
      >
        <Providers nonce={nonce}>{children}</Providers>
        <Toaster />
      </body>
    </html>
  );
}

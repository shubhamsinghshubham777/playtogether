import type { Metadata } from "next";
import { Space_Grotesk, Outfit, JetBrains_Mono } from "next/font/google";
import "./globals.css";
import { Analytics } from "@vercel/analytics/next";
import { Header } from "@/components/Header";
import { Footer } from "@/components/Footer";
import { AnalyticsBeacon } from "@/components/AnalyticsBeacon";
import { SITE_CONFIG } from "@/lib/constants";

const spaceGrotesk = Space_Grotesk({
  variable: "--font-space-grotesk",
  subsets: ["latin"],
  display: "swap",
});

const outfit = Outfit({
  variable: "--font-outfit",
  subsets: ["latin"],
  display: "swap",
});

const jetbrainsMono = JetBrains_Mono({
  variable: "--font-jetbrains-mono",
  subsets: ["latin"],
  display: "swap",
});

export const metadata: Metadata = {
  metadataBase: new URL(SITE_CONFIG.url),
  title: {
    default: "SyncTogether — Synchronized Video & Media Playback",
    template: "%s | SyncTogether",
  },
  description: SITE_CONFIG.description,
  keywords: [
    "watch together app",
    "sync video playback",
    "watch party desktop app",
    "watch movies together online",
    "synchronized media player",
    "real-time facecams",
    "hardware-accelerated sync player",
    "YouTube sync watch",
  ],
  authors: [{ name: SITE_CONFIG.creatorName }],
  creator: SITE_CONFIG.creatorName,
  openGraph: {
    type: "website",
    locale: "en_US",
    url: SITE_CONFIG.url,
    title: "SyncTogether — Synchronized Video & Media Playback",
    description: SITE_CONFIG.description,
    siteName: SITE_CONFIG.name,
    images: [
      {
        url: "/og-image.png",
        width: 1200,
        height: 630,
        alt: "SyncTogether — Synchronized Media Playback",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "SyncTogether — Synchronized Video & Media Playback",
    description: SITE_CONFIG.description,
    images: ["/og-image.png"],
    creator: "@shubhamsingh",
  },
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
      "max-video-preview": -1,
      "max-image-preview": "large",
      "max-snippet": -1,
    },
  },
  other: {
    "awin-verification": "Awin",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  const jsonLdOrg = {
    "@context": "https://schema.org",
    "@type": "Organization",
    name: SITE_CONFIG.name,
    url: SITE_CONFIG.url,
    logo: `${SITE_CONFIG.url}/icon.png`,
    sameAs: [SITE_CONFIG.githubRepo],
  };

  const jsonLdApp = {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    name: "SyncTogether",
    operatingSystem: "macOS 12.0+, Windows 10/11",
    applicationCategory: "MultimediaApplication",
    offers: {
      "@type": "Offer",
      price: "0",
      priceCurrency: "USD",
    },
    description: SITE_CONFIG.description,
  };

  return (
    <html
      lang="en"
      className={`${spaceGrotesk.variable} ${outfit.variable} ${jetbrainsMono.variable} dark`}
    >
      <head>
        <meta name="awin-verification" content="Awin" />
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLdOrg) }}
        />
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLdApp) }}
        />
      </head>
      <body className="min-h-screen flex flex-col bg-[#08070C] text-gray-100 antialiased selection:bg-purple-500/30 selection:text-white">
        <Header />
        <main className="flex-1 pt-20">{children}</main>
        <Footer />
        <Analytics />
        <AnalyticsBeacon />
      </body>
    </html>
  );
}

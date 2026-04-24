import type { Metadata } from 'next';
import './globals.css';

const SITE_URL =
  process.env.NEXT_PUBLIC_SITE_URL ||
  process.env.SITE_URL ||
  'http://localhost:3001';

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: {
    default: 'Hustlr — Parametric Income Insurance for Gig Workers',
    template: '%s | Hustlr',
  },
  description: 'Hustlr provides parametric income insurance for gig workers. Real-time disruption detection, automatic payouts, and AI-powered fraud prevention. Protect your earnings with Hustlr.',
  keywords: [
    'parametric insurance',
    'gig worker insurance',
    'income protection',
    'disruption insurance',
    'rain insurance',
    'platform outage insurance',
    'gig economy',
    'delivery insurance',
    'ride-sharing insurance',
    'India insurance',
    'Chennai insurance',
    'Mumbai insurance',
    'Bengaluru insurance',
    'Delhi insurance',
  ],
  authors: [{ name: 'Hustlr' }],
  creator: 'Hustlr',
  publisher: 'Hustlr',
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
      'max-video-preview': -1,
      'max-image-preview': 'large',
      'max-snippet': -1,
    },
  },
  openGraph: {
    type: 'website',
    locale: 'en_US',
    url: 'https://hustlr.in',
    title: 'Hustlr — Parametric Income Insurance for Gig Workers',
    description: 'Real-time disruption detection, automatic payouts, and AI-powered fraud protection for gig workers. Protect your earnings with Hustlr.',
    siteName: 'Hustlr',
    images: [
      {
        url: '/og-image.png',
        width: 1200,
        height: 630,
        alt: 'Hustlr - Parametric Income Insurance',
      },
    ],
  },
  twitter: {
    card: 'summary_large_image',
    title: 'Hustlr — Parametric Income Insurance for Gig Workers',
    description: 'Real-time disruption detection, automatic payouts, and AI-powered fraud protection for gig workers.',
    images: ['/twitter-image.png'],
    creator: '@hustlr_in',
  },
  verification: {
    google: 'your-google-verification-code',
  },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <link rel="canonical" href="https://hustlr.in" />
        <link
          href="https://fonts.googleapis.com/css2?family=Manrope:wght@400;500;600;700;800;900&display=swap"
          rel="stylesheet"
        />
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{
            __html: JSON.stringify({
              '@context': 'https://schema.org',
              '@type': 'SoftwareApplication',
              name: 'Hustlr',
              applicationCategory: 'FinanceApplication',
              operatingSystem: 'Web',
              offers: {
                '@type': 'Offer',
                price: '49',
                priceCurrency: 'INR',
                description: 'Weekly premium for Standard Shield plan',
              },
              description: 'Parametric income insurance for gig workers with real-time disruption detection and automatic payouts',
              url: 'https://hustlr.in',
              author: {
                '@type': 'Organization',
                name: 'Hustlr',
                url: 'https://hustlr.in',
              },
            }),
          }}
        />
      </head>
      <body className="min-h-screen bg-[#0A0B0A] text-[#E1E3DE]" suppressHydrationWarning>
        {children}
      </body>
    </html>
  );
}
